import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/holiday_utils.dart';
import '../../../core/utils/ids.dart';
import '../../../core/utils/week_utils.dart';
import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/hint_icon.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/holiday.dart';
import '../../notifications/class_reminder_sessions.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../providers/settings_provider.dart';
import '../pages/holiday_ai_page.dart';

/// 「学期与作息」里的节假日管理卡片。
///
/// 节假日会影响上课提醒：放假当天不排提醒；所有改动即时保存并重新同步原生提醒。
class HolidaySettingsCard extends ConsumerStatefulWidget {
  const HolidaySettingsCard({super.key});

  @override
  ConsumerState<HolidaySettingsCard> createState() => _HolidaySettingsCardState();
}

class _HolidaySettingsCardState extends ConsumerState<HolidaySettingsCard> {
  Future<void> _syncReminders() async {
    final timetable = ref.read(timetableProvider).valueOrNull;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (timetable == null || settings == null) return;
    try {
      await syncFromTimetable(timetable, settings);
    } catch (e) {
      debugPrint('同步上课提醒失败：$e');
    }
  }

  Future<void> _addHoliday() async {
    final holiday = await showDialog<Holiday>(
      context: context,
      builder: (_) => const AddHolidayDialog(),
    );
    if (holiday == null) return;
    await ref.read(settingsProvider.notifier).addHoliday(holiday);
    await _syncReminders();
    if (!mounted) return;
    showAppNotice(context, '已添加节假日：${holiday.name}');
  }

  Future<void> _openHolidayAi() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const HolidayAiPage()),
    );
    if (changed == true) await _syncReminders();
  }

  Future<void> _deleteHoliday(Holiday holiday) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除节假日'),
        content: Text('确定删除「${holiday.name}（${holiday.dateKey}）」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(settingsProvider.notifier).removeHoliday(holiday.id);
    await _syncReminders();
    if (!mounted) return;
    showAppNotice(context, '已删除节假日：${holiday.name}');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();
    return _buildCard(context, settings);
  }

  Widget _buildCard(BuildContext context, AppSettings settings) {
    final theme = Theme.of(context);
    final holidays = sortHolidays(settings.holidays);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.beach_access_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('节假日', style: theme.textTheme.titleSmall),
                const SizedBox(width: 2),
                const HintIcon(
                  message: '添加放假的日期后，这些天不会安排上课提醒。'
                      '名称随便填，比如「国庆节」「校运会」。',
                ),
                const Spacer(),
                TextButton.icon(
                  key: const Key('holiday_ai_button'),
                  onPressed: _openHolidayAi,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('AI 设置'),
                ),
                TextButton.icon(
                  key: const Key('holiday_add_button'),
                  onPressed: _addHoliday,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (holidays.isEmpty)
              Text(
                '还没有添加节假日。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (var i = 0; i < holidays.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                _HolidayRow(
                  holiday: holidays[i],
                  onDelete: () => _deleteHoliday(holidays[i]),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _HolidayRow extends StatelessWidget {
  const _HolidayRow({required this.holiday, required this.onDelete});

  final Holiday holiday;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                holiday.date.month.toString(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              Text(
                holiday.date.day.toString(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(holiday.name, style: theme.textTheme.bodyMedium),
              Text(
                '${holiday.dateKey} · ${weekdayName(holiday.date.weekday)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '删除',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }
}

/// 添加节假日的日期 + 名称对话框。
class AddHolidayDialog extends StatefulWidget {
  const AddHolidayDialog({super.key});

  @override
  State<AddHolidayDialog> createState() => _AddHolidayDialogState();
}

class _AddHolidayDialogState extends State<AddHolidayDialog> {
  DateTime _date = dateOnly(DateTime.now());
  late final TextEditingController _dateCtrl;
  final TextEditingController _nameCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: formatDateKey(_date));
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择放假日期',
      cancelText: '取消',
      confirmText: '确定',
      fieldLabelText: '日期',
    );
    if (picked == null) return;
    setState(() {
      _date = dateOnly(picked);
      _dateCtrl.text = formatDateKey(_date);
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写节日名称');
      return;
    }
    Navigator.of(context).pop(
      Holiday(id: newId(), date: _date, name: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('添加节假日'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('holiday_date_field'),
            readOnly: true,
            controller: _dateCtrl,
            onTap: _pickDate,
            decoration: InputDecoration(
              labelText: '日期',
              prefixIcon: const Icon(Icons.event_outlined, size: 18),
              suffixText: weekdayName(_date.weekday),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('holiday_name_field'),
            controller: _nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '名称',
              hintText: '如「国庆节」',
              errorText: _error,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('holiday_submit_button'),
          onPressed: _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
