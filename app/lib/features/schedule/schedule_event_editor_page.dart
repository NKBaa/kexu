import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/coloros_theme.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/week_utils.dart';
import '../../core/widgets/apple_pickers.dart';
import '../../data/models/schedule_event.dart';
import 'providers/schedule_events_provider.dart';

/// 新建/编辑日程（ColorOS 16 风格）。
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

  static String _dateText(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showAppleDatePicker(
      context,
      initial: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: '选择日程日期',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final initial = (start ? _start : _end) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showAppleTimePicker(
      context,
      initial: initial,
      title: start ? '开始时间' : '结束时间',
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
      setState(() => _error = '请填写日程名称');
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
    final palette = ColorOsPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.elevated,
        title: Text('删除日程', style: TextStyle(color: palette.text)),
        content: Text(
          '确定删除「${initial.title}」吗？',
          style: TextStyle(color: palette.secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: palette.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
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
    final palette = ColorOsPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(palette),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  _buildTitleCard(palette),
                  const SizedBox(height: 12),
                  _buildDateCard(palette),
                  const SizedBox(height: 12),
                  _buildNoteCard(palette),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(color: palette.danger, fontSize: 12),
                    ),
                  ],
                  if (widget.initial != null) ...[
                    const SizedBox(height: 18),
                    TextButton.icon(
                      key: const Key('schedule_event_delete'),
                      onPressed: _delete,
                      icon: Icon(Icons.delete_outline, color: palette.danger),
                      label: Text(
                        '删除日程',
                        style: TextStyle(color: palette.danger),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(ColorOsPalette palette) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: palette.secondary)),
          ),
          Expanded(
            child: Text(
              widget.initial == null ? '新建' : '编辑',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            key: const Key('schedule_event_save'),
            onPressed: _saving ? null : _save,
            child: Text(
              '完成',
              style: TextStyle(
                color: palette.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleCard(ColorOsPalette palette) {
    return ColorOsCard(
      color: palette.surface,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('schedule_event_title'),
            controller: _titleCtrl,
            autofocus: widget.initial == null,
            textInputAction: TextInputAction.next,
            cursorColor: palette.accent,
            style: TextStyle(
              color: palette.text,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: '请输入日程名称',
              hintStyle: TextStyle(
                color: palette.secondary,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.elevated,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_outlined, size: 14, color: palette.secondary),
                const SizedBox(width: 4),
                Text(
                  '普通日程',
                  style: TextStyle(color: palette.secondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(ColorOsPalette palette) {
    return ColorOsCard(
      color: palette.surface,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '全天',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch(
                value: _allDay,
                onChanged: (v) => setState(() => _allDay = v),
                activeTrackColor: palette.accent,
                inactiveTrackColor: palette.separator,
                thumbColor: const WidgetStatePropertyAll(Colors.white),
              ),
            ],
          ),
          Divider(color: palette.separator, height: 1),
          _InfoRow(
            label: '开始',
            value: _dateText(_date),
            secondary: weekdayName(_date.weekday),
            palette: palette,
            onTap: _pickDate,
          ),
          Divider(color: palette.separator, height: 1, indent: 0),
          if (!_allDay) ...[
            _InfoRow(
              label: '开始时间',
              value: _start == null ? '未设置' : _fmt(_start!),
              palette: palette,
              onTap: () => _pickTime(start: true),
            ),
            Divider(color: palette.separator, height: 1),
            _InfoRow(
              label: '结束时间',
              value: _end == null ? '未设置' : _fmt(_end!),
              palette: palette,
              onTap: () => _pickTime(start: false),
            ),
          ] else
            _InfoRow(
              label: '结束',
              value: _dateText(_date),
              secondary: weekdayName(_date.weekday),
              palette: palette,
              onTap: _pickDate,
            ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(ColorOsPalette palette) {
    return ColorOsCard(
      color: palette.surface,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: TextField(
        key: const Key('schedule_event_note'),
        controller: _noteCtrl,
        minLines: 2,
        maxLines: 5,
        cursorColor: palette.accent,
        style: TextStyle(color: palette.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: '备注',
          hintStyle: TextStyle(color: palette.secondary, fontSize: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.palette,
    required this.onTap,
    this.secondary,
  });

  final String label;
  final String value;
  final String? secondary;
  final ColorOsPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: palette.secondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (secondary != null)
                  Text(
                    secondary!,
                    style: TextStyle(color: palette.secondary, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: palette.secondary, size: 18),
          ],
        ),
      ),
    );
  }
}
