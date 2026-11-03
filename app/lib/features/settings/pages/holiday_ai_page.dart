import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../data/models/holiday.dart';
import '../../ai/ai_client.dart';
import '../../ai/ai_exception.dart';
import '../../notifications/class_reminder_sessions.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../providers/settings_provider.dart';
import '../holiday_ai.dart';
import 'ai_settings_page.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 用自然语言设置节假日：模型只负责解析日期，用户确认后才写入设置。
class HolidayAiPage extends ConsumerStatefulWidget {
  const HolidayAiPage({super.key});

  @override
  ConsumerState<HolidayAiPage> createState() => _HolidayAiPageState();
}

class _HolidayAiPageState extends ConsumerState<HolidayAiPage> {
  final TextEditingController _controller = TextEditingController();
  HolidayAiPlan? _plan;
  bool _loading = false;
  bool _applying = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_loading) return;
    final instruction = _controller.text.trim();
    if (instruction.isEmpty) {
      showAppNotice(context, '先描述一下放假安排，例如「国庆 10 月 1 日到 7 日放假」');
      return;
    }
    final ai = ref.read(aiConfigProvider).valueOrNull;
    if (ai == null || !ai.text.isConfigured) {
      showAppNotice(context, '还没有配置语言模型，请先到「大模型配置」里填写');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
    });
    final settings = ref.read(settingsProvider).valueOrNull;
    final today = DateTime.now();
    final client = AiClient(config: ai.text);
    try {
      final raw = await client.chatText(
        buildHolidayAiPrompt(
          instruction: instruction,
          today: today,
          existing: settings?.holidays ?? const [],
        ),
        system: '你是课表 App 的节假日解析器。只输出 JSON，不要解释，不要 Markdown。',
      );
      final plan = parseHolidayAiOutput(raw, fallbackYear: today.year);
      if (!mounted) return;
      setState(() => _plan = plan);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '解析失败：$e');
    } finally {
      client.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null || plan.isEmpty || _applying) return;
    setState(() => _applying = true);
    try {
      final settings = ref.read(settingsProvider).valueOrNull;
      if (settings == null) return;
      final newDates = <String>{
        for (final draft in plan.drafts)
          for (final date in draft.dates) Holiday.formatDateKey(date),
      };
      final next = <Holiday>[
        ...settings.holidays.where((h) => !newDates.contains(h.dateKey)),
        for (final draft in plan.drafts)
          for (final date in draft.dates)
            Holiday(id: newId(), date: date, name: draft.name),
      ];
      await ref.read(settingsProvider.notifier).setHolidays(next);

      final timetable = ref.read(timetableProvider).valueOrNull;
      final updated = ref.read(settingsProvider).valueOrNull;
      if (timetable != null && updated != null) {
        await syncFromTimetable(timetable, updated);
      }
      if (!mounted) return;
      showAppNotice(context, '已添加 ${newDates.length} 天节假日');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showAppNotice(context, '添加失败：$e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ai = ref.watch(aiConfigProvider).valueOrNull;
    final configured = ai?.text.isConfigured ?? false;
    final plan = _plan;

    return SettingsSubPage(
      title: 'AI 设置节假日',
      subtitle: '用一句话描述放假日期，AI 解析后由你确认添加；不会直接改课表',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!configured)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '需要先配置语言模型',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AI 设置节假日使用「语言模型」配置；配置后回来即可使用。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      key: const Key('holiday_ai_open_ai_settings'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AiSettingsPage(),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('打开大模型配置'),
                    ),
                  ],
                ),
              ),
            ),
          if (!configured) const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '描述放假安排',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('holiday_ai_input'),
                    controller: _controller,
                    minLines: 3,
                    maxLines: 6,
                    enabled: configured && !_loading,
                    decoration: const InputDecoration(
                      hintText: '例如：国庆节 10 月 1 日到 10 月 7 日放假；'
                          '11 月 6 日校运会放假一天',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('holiday_ai_generate'),
                      onPressed: configured && !_loading ? _generate : null,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_loading ? '解析中…' : 'AI 解析'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
          if (plan != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '解析结果',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (plan.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        plan.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    for (final draft in plan.drafts)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.beach_access_outlined),
                        title: Text(draft.name),
                        subtitle: Text(draft.dateLabel),
                      ),
                    if (plan.warnings.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final warning in plan.warnings)
                        Text(
                          warning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('holiday_ai_apply'),
                        onPressed: _applying ? null : _apply,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(_applying ? '添加中…' : '确认添加'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '示例：\n'
            '• 国庆节 10 月 1 日到 7 日放假\n'
            '• 11 月 6 日校运会放假\n'
            '• 元旦 1 月 1 日放假一天',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
