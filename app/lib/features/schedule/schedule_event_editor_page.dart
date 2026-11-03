import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../data/models/schedule_event.dart';
import 'providers/schedule_events_provider.dart';

/// 新建/编辑日程。
class ScheduleEventEditorPage extends ConsumerStatefulWidget {
  const ScheduleEventEditorPage({
    super.key,
    required this.initialDate,
    this.initial,
  });

  final DateTime initialDate;
  final ScheduleEvent? initial;

  @override
  ConsumerState<ScheduleEventEditorPage> createState() =>
      _ScheduleEventEditorPageState();
}

class _ScheduleEventEditorPageState
    extends ConsumerState<ScheduleEventEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _allDay = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? widget.initialDate;
    _start = _parseTime(e?.startTime);
    _end = _parseTime(e?.endTime);
    _allDay = e == null || e.allDay;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static TimeOfDay? _parseTime(String? text) {
    if (text == null || text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择日程日期',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = (start ? _start : _end) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: start ? '开始时间' : '结束时间',
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写日程标题');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final event = ScheduleEvent(
      id: widget.initial?.id ?? newId(),
      title: title,
      date: _date,
      startTime: _allDay ? null : (_start == null ? null : _fmt(_start!)),
      endTime: _allDay ? null : (_end == null ? null : _fmt(_end!)),
      note: _noteCtrl.text.trim(),
    );
    await ref.read(scheduleEventsProvider.notifier).upsert(event);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日程'),
        content: Text('确定删除「${initial.title}」吗？'),
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
    if (ok != true) return;
    await ref.read(scheduleEventsProvider.notifier).remove(initial.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '新建日程' : '编辑日程'),
        actions: [
          TextButton(
            key: const Key('schedule_event_save'),
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    key: const Key('schedule_event_title'),
                    controller: _titleCtrl,
                    autofocus: widget.initial == null,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      hintText: '如：交高数作业、社团例会',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('日期'),
                    subtitle: Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-'
                      '${_date.day.toString().padLeft(2, '0')}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDate,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('全天'),
                    value: _allDay,
                    onChanged: (v) => setState(() => _allDay = v),
                  ),
                  if (!_allDay) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('开始时间'),
                      subtitle: Text(_start == null ? '未设置' : _fmt(_start!)),
                      onTap: () => _pickTime(start: true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('结束时间'),
                      subtitle: Text(_end == null ? '未设置' : _fmt(_end!)),
                      onTap: () => _pickTime(start: false),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('schedule_event_note'),
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '备注（可选）',
                      hintText: '地点、要带的东西、提醒自己…',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (widget.initial != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('schedule_event_delete'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除日程'),
            ),
          ],
        ],
      ),
    );
  }
}
