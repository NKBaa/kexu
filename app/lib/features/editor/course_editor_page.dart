import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/course.dart';
import '../../data/models/semester.dart';
import '../timetable/providers/timetable_provider.dart';
import 'widgets/session_editor.dart';

/// 课程编辑器：单门课程的新增 / 编辑。
///
/// 大学课程极不规律，因此这里刻意**不用**「起始周 + 结束周 + 单双周」这种有损模型，
/// 而是允许一门课挂多个时段，每个时段独立选择周次（见 `WeekPicker`）。
///
/// 入口约定：
/// - `CourseEditorPage()`：新增课程（学期取当前课表的学期）
/// - `CourseEditorPage(course: c)`：编辑已有课程
/// - `CourseEditorPage(semesterId: 'x')`：指定学期新增（多学期场景）
///
/// 保存成功会 `Navigator.pop(true)`，取消/返回 `pop(false)`，方便调用方刷新提示。
class CourseEditorPage extends ConsumerStatefulWidget {
  const CourseEditorPage({
    super.key,
    this.course,
    this.semesterId,
    this.initialDayOfWeek,
    this.initialPeriod,
    this.initialEndPeriod,
  });

  /// 为 null 表示新增。
  final Course? course;

  /// 新增时归属的学期；为空则用当前课表的学期。
  final String? semesterId;

  /// 从课表空白处新增时预填的星期（1=周一）。
  final int? initialDayOfWeek;

  /// 从课表空白处新增时预填的节次（只填这一节）。
  final int? initialPeriod;

  /// 从课表空白处拖拽选择时预填的结束节次。
  final int? initialEndPeriod;

  @override
  ConsumerState<CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends ConsumerState<CourseEditorPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _teacherCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _creditCtrl;
  late final TextEditingController _noteCtrl;
  final FocusNode _teacherFocus = FocusNode();
  final FocusNode _codeFocus = FocusNode();
  final FocusNode _creditFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();

  late List<Session> _sessions;
  late int _colorIndex;
  bool _dirty = false;
  bool _saving = false;

  /// 新增课程时只在首次拿到课表数据后自动分配一次颜色，之后不再覆盖用户选择。
  bool _colorAutoAssigned = false;
  bool _defaultSessionAdded = false;

  bool get _isEdit => widget.course != null;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _teacherCtrl = TextEditingController(text: c?.teacher ?? '');
    _codeCtrl = TextEditingController(text: c?.courseCode ?? '');
    _creditCtrl = TextEditingController(
      text: c?.credit == null ? '' : _trimNumber(c!.credit!),
    );
    _noteCtrl = TextEditingController(text: c?.note ?? '');
    _sessions = [
      for (final s in c?.sessions ?? const <Session>[]) s,
    ];
    _colorIndex = c?.colorIndex ?? 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _codeCtrl.dispose();
    _creditCtrl.dispose();
    _noteCtrl.dispose();
    _teacherFocus.dispose();
    _codeFocus.dispose();
    _creditFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  static String _trimNumber(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  // ------------------------------------------------------------------ 时段

  /// 新增一个默认时段：周一 第1-2节，全周。若已有周次，沿用最后一个时段的周次。
  void _addSession(int totalWeeks) {
    final last = _sessions.isEmpty ? null : _sessions.last;
    final weeks = last == null || last.weeks.isEmpty
        ? List<int>.generate(totalWeeks, (i) => i + 1)
        : [...last.weeks];
    final start = last == null ? 1 : last.startPeriod;
    final end = last == null ? 2 : last.endPeriod;
    setState(() {
      _sessions.add(
        Session(
          id: newId(),
          dayOfWeek: last?.dayOfWeek ?? 1,
          startPeriod: start,
          endPeriod: end,
          weeks: weeks,
          location: last?.location,
        ),
      );
      _dirty = true;
    });
  }

  void _removeSession(String id) {
    setState(() {
      _sessions.removeWhere((s) => s.id == id);
      _dirty = true;
    });
  }

  void _duplicateSession(Session s, int totalWeeks) {
    setState(() {
      _sessions.add(
        Session(
          id: newId(),
          dayOfWeek: s.dayOfWeek,
          startPeriod: s.startPeriod,
          endPeriod: s.endPeriod,
          weeks: [...s.weeks],
          location: s.location,
          teacher: s.teacher,
        ),
      );
      _dirty = true;
    });
  }

  void _updateSession(Session next) {
    final i = _sessions.indexWhere((s) => s.id == next.id);
    if (i < 0) return;
    setState(() {
      _sessions[i] = next;
      _dirty = true;
    });
  }

  /// 校验并返回每个时段的问题列表（与 [_sessions] 等长）。
  ///
  /// 关键点：同一星期 + 节次重叠**不一定**是错误——单周在 A 教室、双周在 B 教室
  /// 是常见排法。因此只有「节次重叠 且 周次有交集」才算冲突。
  List<List<String>> _computeSessionIssues(int totalWeeks) {
    final issues = <List<String>>[
      for (var i = 0; i < _sessions.length; i++) <String>[],
    ];
    for (var i = 0; i < _sessions.length; i++) {
      final a = _sessions[i];
      if (a.weeks.isEmpty) {
        issues[i].add('未选择周次：该时段不会出现在课表里');
      }
      if (a.startPeriod < 1 || a.endPeriod < a.startPeriod) {
        issues[i].add('节次范围不合法');
      }
      for (var j = i + 1; j < _sessions.length; j++) {
        final b = _sessions[j];
        if (a.dayOfWeek != b.dayOfWeek) continue;
        final overlapPeriod = a.startPeriod <= b.endPeriod && b.startPeriod <= a.endPeriod;
        if (!overlapPeriod) continue;
        final shared = a.weeks.toSet().intersection(b.weeks.toSet());
        if (shared.isEmpty) continue;
        final detail = '${weekdayName(a.dayOfWeek)} '
            '${_periodRangeText(a.startPeriod, a.endPeriod)} 与时段 ${j + 1} 重复'
            '（共同周次 ${formatWeeks(shared.toList()..sort())}）';
        issues[i].add(detail);
        issues[j].add(detail);
      }
    }
    return issues;
  }

  static String _periodRangeText(int start, int end) =>
      start == end ? '第$start节' : '第$start-$end节';

  // ------------------------------------------------------------------ 保存

  Future<void> _save(int totalWeeks) async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写课程名称')),
      );
      return;
    }
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要一个上课时段')),
      );
      return;
    }

    final issues = _computeSessionIssues(totalWeeks);
    final blocking = <String>[];
    for (var i = 0; i < issues.length; i++) {
      for (final m in issues[i]) {
        if (m.startsWith('未选择周次')) continue; // 仅提示，允许继续
        blocking.add('时段 ${i + 1}：$m');
      }
    }
    if (blocking.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('时段冲突'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('以下时段在相同星期有节次重叠、且周次有交集：'),
              const SizedBox(height: 8),
              for (final b in blocking.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $b', style: Theme.of(ctx).textTheme.bodySmall),
                ),
              const SizedBox(height: 8),
              const Text('请调整节次或周次后重试。'),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('知道了')),
          ],
        ),
      );
      return;
    }

    final semesterId = widget.semesterId ??
        widget.course?.semesterId ??
        ref.read(timetableProvider).valueOrNull?.semester.id;
    if (semesterId == null || semesterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到学期信息，请先在设置里配置学期')),
      );
      return;
    }

    final teacher = _teacherCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final note = _noteCtrl.text.trim();
    final credit = double.tryParse(_creditCtrl.text.trim());

    final course = Course(
      id: widget.course?.id ?? newId(),
      semesterId: semesterId,
      name: _nameCtrl.text.trim(),
      teacher: teacher.isEmpty ? null : teacher,
      courseCode: code.isEmpty ? null : code,
      credit: credit,
      note: note.isEmpty ? null : note,
      colorIndex: _colorIndex,
      sessions: _sessions,
      adjustments: widget.course?.adjustments ?? const [],
    );

    setState(() => _saving = true);
    try {
      final controller = ref.read(timetableProvider.notifier);
      if (_isEdit) {
        await controller.updateCourse(course);
      } else {
        await controller.addCourses([course]);
      }
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前课程的改动还没有保存，返回将丢失这些内容。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('继续编辑')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('放弃修改')),
        ],
      ),
    );
    return ok ?? false;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final asyncTimetable = ref.watch(timetableProvider);
    final timetable = asyncTimetable.valueOrNull;

    // 新增时给个合理的默认颜色：按已有课程数轮换，避免全是一个颜色。
    if (!_isEdit && !_colorAutoAssigned && timetable != null) {
      _colorAutoAssigned = true;
      _colorIndex = timetable.courses.length % CoursePalette.colors.length;
    }

    final totalWeeks = timetable?.semester.totalWeeks ?? 16;
    final slots = (timetable?.timeSlots.isNotEmpty ?? false)
        ? timetable!.timeSlots
        : defaultTimeSlots();

    // 新课程首次进入时补一个默认时段（只补一次，且必须在算冲突之前）。
    if (!_isEdit && !_defaultSessionAdded && _sessions.isEmpty && timetable != null) {
      _defaultSessionAdded = true;
      final periods = slots.map((s) => s.period).toList()..sort();
      final maxPeriod = periods.isEmpty ? 1 : periods.last;
      final initialPeriod = widget.initialPeriod?.clamp(1, maxPeriod).toInt();
      final initialEnd = widget.initialEndPeriod
          ?.clamp(initialPeriod ?? 1, maxPeriod)
          .toInt();
      final day = (widget.initialDayOfWeek ?? 1).clamp(1, 7).toInt();
      _sessions = [
        Session(
          id: newId(),
          dayOfWeek: day,
          startPeriod: initialPeriod ?? slots.first.period,
          endPeriod: initialEnd ??
              initialPeriod ??
              (slots.length > 1 ? slots[1].period : slots.first.period),
          weeks: List<int>.generate(totalWeeks, (i) => i + 1),
        ),
      ];
    }

    final issues = _computeSessionIssues(totalWeeks);

    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _confirmDiscard();
        if (!ok || !mounted) return;
        setState(() => _dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(false);
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? '编辑课程' : '新增课程'),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => _save(totalWeeks),
              child: Text(_saving ? '保存中…' : '保存'),
            ),
            const SizedBox(width: 4),
          ],
          bottom: _saving
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: asyncTimetable.isLoading && timetable == null
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    _sectionTitle(context, '基本信息', Icons.badge_outlined),
                    const SizedBox(height: 8),
                    _buildBasicInfo(context),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _sectionTitle(context, '上课时段', Icons.schedule_outlined),
                        const SizedBox(width: 8),
                        Text(
                          '共 ${_sessions.length} 个时段',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '一门课可以有多个时段（如周一 1-2 节 + 周三 5-6 节）。'
                      '每个时段可单独设置周次，支持单周、双周、断续周次。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _sessions.length; i++)
                      SessionEditor(
                        key: ValueKey(_sessions[i].id),
                        index: i,
                        session: _sessions[i],
                        timeSlots: slots,
                        totalWeeks: totalWeeks,
                        slotIssues: issues[i],
                        showTeacherField: true,
                        onChanged: _updateSession,
                        onRemove: _sessions.length > 1
                            ? () => _removeSession(_sessions[i].id)
                            : null,
                        onDuplicate: () => _duplicateSession(_sessions[i], totalWeeks),
                      ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: () => _addSession(totalWeeks),
                      icon: const Icon(Icons.add),
                      label: const Text('添加上课时段'),
                    ),
                    const SizedBox(height: 18),
                    _sectionTitle(context, '备注', Icons.notes_outlined),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteCtrl,
                      focusNode: _noteFocus,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => _markDirty(),
                      decoration: const InputDecoration(
                        hintText: '如：需要带计算器 / 课程群 / 考试形式…',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '提示：编辑已有课程时，调课/停课/补课记录会保留不变。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              if (_isEdit)
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _confirmDeleteCourse(totalWeeks),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('删除'),
                  ),
                ),
              if (_isEdit) const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(totalWeeks),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? '保存中…' : '保存课程'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildBasicInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nameCtrl,
          autofocus: !_isEdit,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.none,
          onChanged: (_) => _markDirty(),
          onFieldSubmitted: (_) => _teacherFocus.requestFocus(),
          validator: (v) => (v ?? '').trim().isEmpty ? '课程名称不能为空' : null,
          decoration: const InputDecoration(
            isDense: true,
            labelText: '课程名称 *',
            hintText: '如 高等数学 A（二）',
            prefixIcon: Icon(Icons.book_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _teacherCtrl,
                focusNode: _teacherFocus,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _markDirty(),
                onFieldSubmitted: (_) => _codeFocus.requestFocus(),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '教师',
                  hintText: '如 张老师',
                  prefixIcon: Icon(Icons.person_outline, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _codeCtrl,
                focusNode: _codeFocus,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _markDirty(),
                onFieldSubmitted: (_) => _creditFocus.requestFocus(),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '课程编号',
                  hintText: '选填',
                  prefixIcon: Icon(Icons.tag, size: 18),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: TextFormField(
                controller: _creditCtrl,
                focusNode: _creditFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                onChanged: (_) => _markDirty(),
                onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return null;
                  final d = double.tryParse(s);
                  if (d == null) return '需为数字';
                  if (d < 0 || d > 100) return '学分不合法';
                  return null;
                },
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '学分',
                  hintText: '3',
                  prefixIcon: Icon(Icons.star_outline, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildColorPicker(context)),
          ],
        ),
      ],
    );
  }

  Widget _buildColorPicker(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('课程颜色', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < CoursePalette.colors.length; i++)
              Semantics(
                button: true,
                selected: _colorIndex == i,
                label: '颜色 ${i + 1}',
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _colorIndex = i;
                      _dirty = true;
                    });
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: CoursePalette.of(i),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorIndex == i
                            ? theme.colorScheme.onSurface
                            : Colors.black.withValues(alpha: 0.08),
                        width: _colorIndex == i ? 2.5 : 1,
                      ),
                    ),
                    child: _colorIndex == i
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDeleteCourse(int totalWeeks) async {
    final c = widget.course;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程？'),
        content: Text('将删除「${c.name}」及其 ${c.sessions.length} 个上课时段，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref.read(timetableProvider.notifier).deleteCourses({c.id});
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }
}