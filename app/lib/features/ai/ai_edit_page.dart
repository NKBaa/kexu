import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_notice.dart';
import '../../data/models/ai_ops.dart';
import '../../data/models/schedule_event.dart';
import '../../data/models/timetable.dart';
import '../../data/services/ai_apply_service.dart';
import '../schedule/providers/schedule_events_provider.dart';
import '../schedule/schedule_event_ai.dart';
import '../settings/providers/settings_provider.dart';
import '../timetable/providers/timetable_provider.dart';
import 'ai_client.dart';
import 'ai_client_provider.dart';
import 'ai_exception.dart';
import 'ai_image_intent.dart';
import 'now_context.dart';

/// 「一句话改课表」页面（对话式）。
///
/// 流程：输入自然语言 → 模型产出结构化操作方案（或先反问）→ 用户逐条核对 → 应用。
/// 之所以要有「方案预览」这一步，是因为模型偶尔会理解偏；
/// 让用户先看到「将要发生什么」，比直接改完再撤销更符合直觉。
///
/// 对话式设计的意义：用户说「高数」而课表里有两门高数时，模型会先反问；
/// 用户点一下候选答案就能继续，不必重新打一遍完整指令。
class AiEditPage extends ConsumerStatefulWidget {
  const AiEditPage({super.key});

  @override
  ConsumerState<AiEditPage> createState() => _AiEditPageState();
}

/// 对话里一条记录的类型。
enum _EntryKind { user, assistant, plan, schedulePlan, report, error }

/// 对话记录条目。
class _ChatEntry {
  _ChatEntry._({
    required this.kind,
    this.text = '',
    this.options = const <String>[],
    this.images = const <AiImageAttachment>[],
    this.plan,
    this.events = const <ScheduleEvent>[],
    this.report,
  });

  factory _ChatEntry.user(
    String text, {
    List<AiImageAttachment> images = const <AiImageAttachment>[],
  }) =>
      _ChatEntry._(kind: _EntryKind.user, text: text, images: images);

  factory _ChatEntry.assistant(String text, {List<String> options = const <String>[]}) =>
      _ChatEntry._(kind: _EntryKind.assistant, text: text, options: options);

  factory _ChatEntry.plan(AiEditPlan plan) =>
      _ChatEntry._(kind: _EntryKind.plan, text: plan.summary, plan: plan);

  factory _ChatEntry.schedulePlan(List<ScheduleEvent> events) =>
      _ChatEntry._(
        kind: _EntryKind.schedulePlan,
        text: '日程方案',
        events: events,
      );

  factory _ChatEntry.report(ApplyReport report) =>
      _ChatEntry._(kind: _EntryKind.report, text: report.summary, report: report);

  factory _ChatEntry.error(String text) => _ChatEntry._(kind: _EntryKind.error, text: text);

  final _EntryKind kind;
  final String text;
  final List<String> options;
  final List<AiImageAttachment> images;
  final AiEditPlan? plan;
  final List<ScheduleEvent> events;
  final ApplyReport? report;

  /// 方案卡片里被勾选的操作下标。
  final Set<int> selected = <int>{};

  /// 该方案是否已经应用过（应用后禁用勾选与按钮）。
  bool applied = false;
}

class _AiEditPageState extends ConsumerState<AiEditPage> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<_ChatEntry> _entries = <_ChatEntry>[];

  /// 多轮对话历史：用户原话 + 模型原始回复。
  final List<AiChatMessage> _history = <AiChatMessage>[];

  bool _busy = false;
  bool _applying = false;

  /// 待发送图片：给语言模型看；没有语言模型时先由识图模型转述。
  final List<AiImageAttachment> _images = <AiImageAttachment>[];
  static const int _maxImages = 4;
  String _busyText = '正在理解你的指令…';

  /// 示例指令：刻意用白话/模糊说法，演示「AI 会自己换算时间、必要时反问」。
  static const List<String> _examples = <String>[
    '把明天的课都挪到下周',
    '高数改成单双周都上',
    '第 3 节改成 10:05 上课',
    '明天下午 3 点交高数作业',
    '下个月 5 号报名截止',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 交互

  Future<void> _send() async {
    if (_busy || _applying) return;
    await _submit(_inputCtrl.text.trim());
  }

  Future<void> _pickImages() async {
    if (_busy || _applying) return;
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择图片（给 AI 看）',
        type: FileType.image,
      );
      if (files.isEmpty) return;
      final room = _maxImages - _images.length;
      if (room <= 0) {
        _addError('最多附 $_maxImages 张图片，请先删掉一些再添加。');
        return;
      }
      final picked = <AiImageAttachment>[];
      for (final file in files) {
        if (picked.length >= room) break;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        picked.add(AiImageAttachment(
          bytes: bytes,
          mimeType: file.extension,
          name: file.name,
        ));
      }
      if (picked.isEmpty) return;
      setState(() => _images.addAll(picked));
    } catch (e) {
      _addError('选择图片失败：$e');
    }
  }

  void _removeImage(int index) {
    if (_busy || _applying) return;
    if (index < 0 || index >= _images.length) return;
    setState(() => _images.removeAt(index));
  }

  /// 提交一条指令：既来自输入框，也来自反问气泡里的候选 chip。
  Future<void> _submit(String instruction) async {
    if (_busy || _applying) return;

    final images = List<AiImageAttachment>.of(_images);
    var text = instruction.trim();
    if (text.isEmpty && images.isEmpty) {
      _addError('请先描述要改的课表或要添加的日程，例如「把明天的课挪到下周」。');
      return;
    }
    if (text.isEmpty) text = '根据这张图片帮我调整课表。';

    // 设置是异步加载的：这里等它真正就绪再判断，避免「刚打开页面就点发送」
    // 时把「还在加载」误判成「没配置模型」。
    var textConfigured = false;
    var visionConfigured = false;
    try {
      final ai = (await ref.read(settingsProvider.future)).aiConfig;
      textConfigured = ai.textConfigured;
      visionConfigured = ai.visionConfigured;
    } catch (_) {
      textConfigured = false;
      visionConfigured = false;
    }
    if (!mounted) return;

    if (images.isEmpty && !textConfigured) {
      _addError('还没有配置语言模型。请到「设置 → 大模型配置 → 语言模型」里填写。');
      return;
    }
    if (images.isNotEmpty && !textConfigured && !visionConfigured) {
      _addError('还没有配置模型。请到「设置 → 大模型配置」里配置语言模型或识图模型。');
      return;
    }

    // 同一个 AI 窗口同时处理「改课表」和「加日程」。
    final wantsSchedule =
        images.isEmpty && _looksLikeSchedule(text) && !_looksLikeTimetable(text);
    if (wantsSchedule) {
      await _submitSchedule(text);
      return;
    }

    final timetable = ref.read(timetableProvider).valueOrNull;
    if (timetable == null) {
      _addError('课表还没加载完成，请稍后再试。');
      return;
    }

    setState(() {
      _busy = true;
      _busyText = images.isEmpty
          ? '正在理解你的指令…'
          : textConfigured
              ? '语言模型正在看图片…'
              : '识图模型正在转述图片…';
      _entries.add(_ChatEntry.user(text, images: images));
      _inputCtrl.clear();
      _images.clear();
    });
    _scrollToBottom();

    try {
      final result = await AiImageIntentService().plan(
        instruction: text,
        current: timetable,
        images: images,
        history: List<AiChatMessage>.from(_history),
        textClient: ref.read(textAiClientProvider),
        visionClient: ref.read(visionAiClientProvider),
        textConfigured: textConfigured,
        visionConfigured: visionConfigured,
        onStatus: (status) {
          if (mounted) setState(() => _busyText = status);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        // 历史用「用户原话 + 模型原始输出」：下一轮模型才能衔接上一轮的反问。
        _history
          ..add(AiChatMessage.user(result.historyText))
          ..add(AiChatMessage.assistant(result.turn.rawOutput));
        _appendTurn(result.turn.plan);
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries.add(_ChatEntry.error(e.message));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries.add(_ChatEntry.error('生成方案失败：$e'));
      });
    }
    _scrollToBottom();
  }

  static final RegExp _scheduleWords = RegExp(
    '日程|考试|作业|截止|报名|活动|会议|开会|例会|讲座|聚会|聚餐|约会|'
    '生日|纪念日|提醒|缴费|交表|打卡|面试|比赛|答辩|体检|值日|班会|'
    '取快递|还书|复习',
  );
  static final RegExp _timetableWords = RegExp(
    '课表|课程|节|周次|学期|作息|教室|老师|教师|上课|调课|停课|补课',
  );

  bool _looksLikeSchedule(String text) => _scheduleWords.hasMatch(text);
  bool _looksLikeTimetable(String text) => _timetableWords.hasMatch(text);

  Future<void> _submitSchedule(String text) async {
    setState(() {
      _busy = true;
      _busyText = '正在整理日程…';
      _entries.add(_ChatEntry.user(text));
      _inputCtrl.clear();
    });
    _scrollToBottom();
    try {
      final events = await ScheduleEventAiService(
        client: ref.read(textAiClientProvider),
      ).plan(text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries.add(_ChatEntry.schedulePlan(events));
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries.add(_ChatEntry.error(e.message));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries.add(_ChatEntry.error('整理日程失败：$e'));
      });
    }
    _scrollToBottom();
  }

  /// 把一轮解析结果追加到对话里：可能是反问、方案，或「无法执行」的说明。
  void _appendTurn(AiEditPlan plan) {
    if (plan.hasQuestion) {
      final text = plan.warnings.isEmpty
          ? plan.question
          : '${plan.question}\n\n（${plan.warnings.join('；')}）';
      _entries.add(_ChatEntry.assistant(text, options: plan.options));
    }

    if (plan.ops.isNotEmpty) {
      final entry = _ChatEntry.plan(plan);
      entry.selected.addAll(List<int>.generate(plan.ops.length, (i) => i));
      _entries.add(entry);
      return;
    }

    if (plan.hasQuestion) return;

    final text = plan.summary.isNotEmpty
        ? plan.summary
        : '模型没有给出任何可执行的改动，请把指令说得更具体一些。';
    _entries.add(_ChatEntry.assistant(text));
    if (plan.warnings.isNotEmpty) {
      _entries.add(_ChatEntry.error(plan.warnings.join('；')));
    }
  }

  Future<void> _apply(_ChatEntry entry) async {
    final plan = entry.plan;
    if (plan == null || entry.applied || _applying) return;

    final timetable = ref.read(timetableProvider).valueOrNull;
    if (timetable == null) {
      _addError('课表还没加载完成，请稍后再试。');
      return;
    }

    final ops = <AiOp>[
      for (var i = 0; i < plan.ops.length; i++)
        if (entry.selected.contains(i)) plan.ops[i],
    ];
    if (ops.isEmpty) {
      _addError('请至少勾选一条要执行的改动。');
      return;
    }

    setState(() => _applying = true);

    final report = const AiApplyService().apply(
      timetable,
      AiEditPlan(summary: plan.summary, ops: ops),
    );
    await ref.read(timetableProvider.notifier).replaceTimetable(report.timetable);

    if (!mounted) return;
    setState(() {
      _applying = false;
      entry.applied = true;
      _entries.add(_ChatEntry.report(report));
    });
    _scrollToBottom();

    showAppNotice(context, report.summary);
  }

  Future<void> _applySchedule(_ChatEntry entry) async {
    if (entry.applied || _applying || entry.events.isEmpty) return;
    setState(() => _applying = true);
    await ref.read(scheduleEventsProvider.notifier).addEvents(entry.events);
    if (!mounted) return;
    setState(() {
      _applying = false;
      entry.applied = true;
      _entries.add(_ChatEntry.assistant('已添加 ${entry.events.length} 个日程。'));
    });
    _scrollToBottom();
    showAppNotice(context, '已添加 ${entry.events.length} 个日程');
  }

  void _clear() {
    if (_busy || _applying) return;
    setState(() {
      _entries.clear();
      _history.clear();
      _inputCtrl.clear();
      _images.clear();
    });
  }

  void _addError(String message) {
    setState(() => _entries.add(_ChatEntry.error(message)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------------ 渲染

  @override
  Widget build(BuildContext context) {
    final timetable = ref.watch(timetableProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '课序 AI',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
            Text(
              '改课表 · 加日程 · 也可以发图片',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            key: const ValueKey('ai_edit_clear'),
            onPressed: _busy || _applying ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空对话',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                _buildNowBar(timetable),
                Expanded(child: _buildConversation()),
                _buildComposer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primaryContainer.withValues(alpha: 0.85),
                scheme.surface,
                scheme.secondaryContainer.withValues(alpha: 0.65),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: _glow(scheme.primary.withValues(alpha: 0.34), 280),
        ),
        Positioned(
          bottom: 80,
          left: -100,
          child: _glow(scheme.tertiary.withValues(alpha: 0.28), 320),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  /// 毛玻璃面板：半透明 + 背景模糊 + 细边框。
  Widget _glass({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding,
    double radius = 24,
    Color? tint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: tint ?? scheme.surface.withValues(alpha: 0.58),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }

  /// 顶部「现在」信息条：今天日期/星期 · 第 N 教学周。
  Widget _buildNowBar(Timetable? timetable) {
    final theme = Theme.of(context);
    final String text;
    if (timetable == null) {
      text = '现在：课表还没加载完成';
    } else {
      final now = NowContext.fromTimetable(timetable);
      text = '现在：${now.monthDayLabel} ${now.weekdayLabel} · ${now.weekLabel}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: _glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversation() {
    if (_entries.isEmpty) return _buildEmptyState();
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _entries.length + (_busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _entries.length) return _buildThinkingBubble();
        return _buildEntry(_entries[index]);
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Center(
          child: _glass(
            radius: 30,
            padding: const EdgeInsets.all(18),
            child: Icon(
              Icons.auto_awesome,
              size: 34,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '把想法直接说给课序',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '不用找菜单。说「把明天的课挪到下周」，或者「明天下午 3 点交作业」，'
          'AI 会先整理成方案，你确认后再改课表或加日程。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        _glass(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '可以这样说',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final example in _examples)
                    ActionChip(
                      label: Text(example, style: const TextStyle(fontSize: 12)),
                      onPressed: _busy || _applying
                          ? null
                          : () => setState(() => _inputCtrl.text = example),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '也可以点左下角图片按钮，把课表截图直接发给 AI。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEntry(_ChatEntry entry) {
    switch (entry.kind) {
      case _EntryKind.user:
        return _buildUserBubble(entry);
      case _EntryKind.assistant:
        return _buildAssistantBubble(entry);
      case _EntryKind.plan:
        return _buildPlanCard(entry);
      case _EntryKind.schedulePlan:
        return _buildSchedulePlanCard(entry);
      case _EntryKind.report:
        return _buildReportCard(entry.report!);
      case _EntryKind.error:
        return _buildErrorBubble(entry.text);
    }
  }

  Widget _buildUserBubble(_ChatEntry entry) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 560),
        child: _glass(
          radius: 20,
          tint: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.images.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final image in entry.images)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          image.bytes,
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                  ],
                ),
                if (entry.text.isNotEmpty) const SizedBox(height: 8),
              ],
              if (entry.text.isNotEmpty)
                Text(
                  entry.text,
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(_ChatEntry entry) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 620),
        child: _glass(
          radius: 20,
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(entry.text)),
                ],
              ),
              if (entry.options.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final option in entry.options)
                      ActionChip(
                        key: ValueKey('ai_edit_option_$option'),
                        label:
                            Text(option, style: const TextStyle(fontSize: 12)),
                        onPressed:
                            _busy || _applying ? null : () => _submit(option),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBubble(String message) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: _glass(
        radius: 20,
        tint: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _glass(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(_busyText, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchedulePlanCard(_ChatEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _glass(
        key: const ValueKey('ai_schedule_plan_card'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '日程方案（${entry.events.length} 项）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final event in entry.events)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined, size: 20),
                title: Text(event.title),
                subtitle: Text(
                  '${event.dateKey}'
                  '${event.allDay ? ' · 全天' : ' · ${event.startTime}${event.endTime == null ? '' : '-${event.endTime}'}'}'
                  '${event.note.isEmpty ? '' : ' · ${event.note}'}',
                ),
              ),
            const SizedBox(height: 4),
            if (entry.applied)
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  const Text('已添加'),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('ai_schedule_apply'),
                  onPressed: _applying ? null : () => _applySchedule(entry),
                  icon: _applying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text('添加 ${entry.events.length} 个日程'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(_ChatEntry entry) {
    final plan = entry.plan!;
    final theme = Theme.of(context);
    final allSelected = entry.selected.length == plan.ops.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _glass(
        key: const ValueKey('ai_edit_plan_card'),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '修改方案（${plan.ops.length} 项）',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!entry.applied)
                  TextButton(
                    key: const ValueKey('ai_edit_select_all'),
                    onPressed: () => setState(() {
                      if (allSelected) {
                        entry.selected.clear();
                      } else {
                        entry.selected
                          ..clear()
                          ..addAll(List<int>.generate(plan.ops.length, (i) => i));
                      }
                    }),
                    child: Text(allSelected ? '全不选' : '全选'),
                  ),
              ],
            ),
            if (plan.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(plan.summary, style: theme.textTheme.bodyMedium),
              ),
            if (plan.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  plan.warnings.join('；'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            for (var i = 0; i < plan.ops.length; i++) _buildOpTile(entry, i, plan.ops[i]),
            const SizedBox(height: 8),
            if (entry.applied)
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('已应用', style: theme.textTheme.bodySmall),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('ai_edit_apply'),
                  onPressed: _applying ? null : () => _apply(entry),
                  icon: _applying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text('应用 ${entry.selected.length} 项改动'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpTile(_ChatEntry entry, int index, AiOp op) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      key: ValueKey('ai_edit_op_$index'),
      value: entry.selected.contains(index),
      onChanged: entry.applied
          ? null
          : (v) => setState(() {
                if (v == true) {
                  entry.selected.add(index);
                } else {
                  entry.selected.remove(index);
                }
              }),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(op.describe(), style: theme.textTheme.bodyMedium),
      subtitle: Text(
        aiOpKindLabel(op.kind) + (op.courseName.isEmpty ? '' : ' · ${op.courseName}'),
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Widget _buildReportCard(ApplyReport report) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _glass(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('执行结果', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(report.summary),
            if (report.appliedDetails.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final d in report.appliedDetails)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('✓ $d', style: theme.textTheme.bodySmall),
                ),
            ],
            if (report.skippedDetails.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final d in report.skippedDetails)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '✗ $d',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: _glass(
        radius: 26,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_images.isNotEmpty) ...[
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            image.bytes,
                            key: ValueKey('ai_edit_image_$index'),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton.filled(
                            key: ValueKey('ai_edit_image_remove_$index'),
                            visualDensity: VisualDensity.compact,
                            constraints:
                                const BoxConstraints.tightFor(width: 24, height: 24),
                            padding: EdgeInsets.zero,
                            tooltip: '移除图片',
                            onPressed: _busy || _applying
                                ? null
                                : () => _removeImage(index),
                            icon: const Icon(Icons.close, size: 14),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _examples.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ActionChip(
                      key: ValueKey('ai_edit_example_$i'),
                      label: Text(_examples[i],
                          style: const TextStyle(fontSize: 12)),
                      onPressed: _busy || _applying
                          ? null
                          : () => setState(() => _inputCtrl.text = _examples[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: 46,
                  width: 46,
                  child: IconButton.filledTonal(
                    key: const ValueKey('ai_edit_add_image'),
                    tooltip: '发图片给 AI 看',
                    onPressed: _busy || _applying ? null : _pickImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('ai_edit_input'),
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 4,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: _images.isEmpty
                          ? '改课表、加日程，或发一张课表图片…'
                          : '可以补充一句图片要改什么…',
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surface.withValues(alpha: 0.55),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  width: 46,
                  child: IconButton.filled(
                    key: const ValueKey('ai_edit_send'),
                    tooltip: '发送',
                    onPressed: _busy || _applying ? null : _send,
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}