import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../../data/models/bell_schedule.dart';
import '../../../data/models/semester.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../widgets/period_form.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 作息方案编辑页：名称 + 生效日期区间 + 每节的起止时间。
///
/// 为什么把「生效日期」作为方案的一部分：学校换季时作息会变
/// （如夏季 14:30 上课、冬季 14:00 上课），只有日期区间才能让 App
/// 在正确的时间显示正确的时间表。
class BellScheduleEditorPage extends ConsumerStatefulWidget {
  const BellScheduleEditorPage({
    super.key,
    this.initial,
    this.isNew = false,
    this.canDelete = true,
  });

  /// 为 null 表示新建。
  final BellSchedule? initial;
  final bool isNew;
  final bool canDelete;

  @override
  ConsumerState<BellScheduleEditorPage> createState() => _BellScheduleEditorPageState();
}

class _BellScheduleEditorPageState extends ConsumerState<BellScheduleEditorPage> {
  late final TextEditingController _nameCtrl;
  late List<TimeSlot> _slots;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _nameCtrl = TextEditingController(text: init?.name ?? '新作息方案');
    _slots = List<TimeSlot>.from(init?.slots ?? defaultTimeSlots());
    _start = init?.startDate;
    _end = init?.endDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _start : _end) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
      helpText: isStart ? '选择生效起始日期' : '选择生效结束日期',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = null;
      } else {
        _end = picked;
        if (_start != null && picked.isBefore(_start!)) _start = null;
      }
    });
  }

  bool get _rangeValid {
    if (_start == null || _end == null) return true;
    return !_end!.isBefore(_start!);
  }

  Future<void> _save(WidgetsBinding? _) async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('方案名称不能为空', error: true);
      return;
    }
    if (!_rangeValid) {
      _toast('结束日期不能早于开始日期', error: true);
      return;
    }
    if (_slots.isEmpty) {
      _toast('至少保留一个节次', error: true);
      return;
    }

    setState(() => _saving = true);
    final schedule = BellSchedule(
      id: widget.initial?.id ?? ids(),
      name: name,
      slots: _slots,
      startDate: _start,
      endDate: _end,
    );
    try {
      await ref.read(timetableProvider.notifier).upsertSchedule(schedule);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('已保存作息方案「$name」')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e', error: true);
    }
  }

  Future<void> _delete() async {
    final init = widget.initial;
    if (init == null || !widget.canDelete) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这套作息？'),
        content: Text('「${init.name}」将被删除，使用它的日期会回退到其它方案。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(timetableProvider.notifier).deleteSchedule(init.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsSubPage(
      title: widget.isNew ? '新建作息方案' : '编辑作息方案',
      actions: [
        if (!widget.isNew)
          IconButton(
            tooltip: '删除方案',
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.canDelete ? _delete : null,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const Key('bell_name_field'),
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '方案名称',
                      hintText: '如「夏季作息」「秋季作息」',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('生效日期', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Text(
                    '留空表示不限日期。限定日期的方案优先命中，'
                    '因此「夏季作息 05-01~09-30」会覆盖不限日期的默认方案。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('bell_start_date'),
                        onPressed: () => _pickDate(isStart: true),
                        icon: const Icon(Icons.event_available, size: 18),
                        label: Text(_start == null ? '起始日期：不限' : '起始：${_fmt(_start!)}'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('bell_end_date'),
                        onPressed: () => _pickDate(isStart: false),
                        icon: const Icon(Icons.event_busy, size: 18),
                        label: Text(_end == null ? '结束日期：不限' : '结束：${_fmt(_end!)}'),
                      ),
                      if (_start != null || _end != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _start = null;
                            _end = null;
                          }),
                          child: const Text('清除日期'),
                        ),
                    ],
                  ),
                  if (!_rangeValid)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('结束日期不能早于开始日期',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('每节时间', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  PeriodForm(
                    timeSlots: _slots,
                    onChanged: (next) => setState(() => _slots = next),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              FilledButton.icon(
                key: const Key('bell_save_button'),
                onPressed: _saving ? null : () => _save(null),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text('保存方案'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String ids() => newId();
}

/// 作息方案列表（供学期与作息页嵌入）。
class BellScheduleList extends ConsumerWidget {
  const BellScheduleList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timetable = ref.watch(timetableProvider).valueOrNull;
    if (timetable == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final now = DateTime.now();
    final active = timetable.scheduleForDate(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '共 ${timetable.schedules.length} 套作息',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '今天生效：「${active.name}」',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              key: const Key('bell_add_button'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BellScheduleEditorPage(isNew: true),
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增方案'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final s in timetable.schedules)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              key: Key('bell_item_${s.id}'),
              leading: Icon(
                s.id == active.id ? Icons.check_circle : Icons.schedule,
                color: s.id == active.id
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: Row(
                children: [
                  Flexible(child: Text(s.name)),
                  if (s.id == active.id) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('当前生效',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          )),
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                '${s.rangeLabel} · ${s.slots.length} 节'
                '${s.slots.isEmpty ? '' : ' · 第 1 节 ${s.slots.first.start}'}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BellScheduleEditorPage(
                    initial: s,
                    canDelete: timetable.schedules.length > 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}