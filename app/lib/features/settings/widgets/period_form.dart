import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/semester.dart';

/// 作息时间表编辑：每个「第 N 节」的起止时间。
///
/// 时间用 `HH:mm` 文本输入（Windows 端键盘友好，Android 端弹出数字键盘），
/// 输入不合法时行内报错且**不向父级提交**，避免把坏数据写进课表。
/// 支持末尾增删节次与「恢复默认 12 节作息」。
class PeriodForm extends StatefulWidget {
  const PeriodForm({
    super.key,
    required this.timeSlots,
    required this.onChanged,
    this.enabled = true,
    this.maxPeriods = 20,
  });

  final List<TimeSlot> timeSlots;
  final ValueChanged<List<TimeSlot>> onChanged;
  final bool enabled;
  final int maxPeriods;

  @override
  State<PeriodForm> createState() => _PeriodFormState();
}

class _PeriodFormState extends State<PeriodForm> {
  final List<_SlotRow> _rows = [];
  final Map<int, String?> _errors = {};
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _buildRows(widget.timeSlots);
  }

  @override
  void didUpdateWidget(covariant PeriodForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_syncing) return;
    // 外部整表替换（如恢复默认、导入数据）时重建。
    if (!_sameSlots(oldWidget.timeSlots, widget.timeSlots) &&
        !_sameSlots(_currentSlotsOrNull() ?? const [], widget.timeSlots)) {
      _disposeRows();
      _buildRows(widget.timeSlots);
      setState(() => _errors.clear());
    }
  }

  @override
  void dispose() {
    _disposeRows();
    super.dispose();
  }

  bool _sameSlots(List<TimeSlot> a, List<TimeSlot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].period != b[i].period ||
          a[i].start != b[i].start ||
          a[i].end != b[i].end) {
        return false;
      }
    }
    return true;
  }

  void _buildRows(List<TimeSlot> slots) {
    final sorted = [...slots]..sort((a, b) => a.period.compareTo(b.period));
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      _rows.add(
        _SlotRow(
          period: i + 1,
          start: TextEditingController(text: s.start),
          end: TextEditingController(text: s.end),
        ),
      );
    }
  }

  void _disposeRows() {
    for (final r in _rows) {
      r.start.dispose();
      r.end.dispose();
    }
    _rows.clear();
  }

  List<TimeSlot>? _currentSlotsOrNull() {
    final out = <TimeSlot>[];
    for (var i = 0; i < _rows.length; i++) {
      final s = _parseTime(_rows[i].start.text);
      final e = _parseTime(_rows[i].end.text);
      if (s == null || e == null) return null;
      out.add(TimeSlot(period: i + 1, start: s, end: e));
    }
    return out;
  }

  static String? _parseTime(String raw) {
    final t = raw.trim().replaceAll('：', ':').replaceAll('.', ':');
    final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(t);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null || h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// 校验并向上提交。任一格非法就不提交，只更新行内错误。
  void _validateAndEmit() {
    final errors = <int, String?>{};
    final out = <TimeSlot>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final s = _parseTime(row.start.text);
      final e = _parseTime(row.end.text);
      if (s == null) {
        errors[i] = '格式应为 HH:mm';
      } else if (e == null) {
        errors[i] = '格式应为 HH:mm';
      } else if (_minutes(e) <= _minutes(s)) {
        errors[i] = '结束时间需晚于开始';
      } else {
        errors[i] = null;
        out.add(TimeSlot(period: i + 1, start: s, end: e));
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      // 自动补齐序号（删除中间行后重排）。
      for (var i = 0; i < _rows.length; i++) {
        _rows[i].period = i + 1;
      }
    });
    if (errors.values.any((v) => v != null)) return;

    _syncing = true;
    widget.onChanged(out);
    // 让父级重建后 didUpdateWidget 不把我的输入又覆盖掉。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncing = false);
  }

  void _addPeriod() {
    if (_rows.length >= widget.maxPeriods) return;
    final last = _rows.isEmpty ? null : _rows.last;
    String start = '08:00';
    String end = '08:45';
    if (last != null) {
      final lastEnd = _parseTime(last.end.text);
      if (lastEnd != null) {
        // 默认下一节在上一节结束后 10 分钟开始，持续 45 分钟。
        start = _fmtMinutes(_minutes(lastEnd) + 10);
        end = _fmtMinutes(_minutes(lastEnd) + 10 + 45);
      }
    }
    setState(() {
      _rows.add(
        _SlotRow(
          period: _rows.length + 1,
          start: TextEditingController(text: start),
          end: TextEditingController(text: end),
        ),
      );
      _errors.clear();
    });
    _validateAndEmit();
  }

  void _removeLast() {
    if (_rows.length <= 1) return;
    setState(() {
      final r = _rows.removeLast();
      r.start.dispose();
      r.end.dispose();
      _errors.clear();
    });
    _validateAndEmit();
  }

  void _removeAt(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      final r = _rows.removeAt(index);
      r.start.dispose();
      r.end.dispose();
      _errors.clear();
    });
    _validateAndEmit();
  }

  void _resetDefault() {
    setState(() {
      _disposeRows();
      _buildRows(defaultTimeSlots());
      _errors.clear();
    });
    _validateAndEmit();
  }

  static String _fmtMinutes(int total) {
    final t = total % (24 * 60);
    final h = t ~/ 60;
    final m = t % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '共 ${_rows.length} 节',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            if (_errors.values.any((v) => v != null))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '有 ${_errors.values.where((v) => v != null).length} 处时间需要修正',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            TextButton.icon(
              onPressed: widget.enabled ? _resetDefault : null,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('恢复默认'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _rows.length; i++) _buildRow(context, i),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.enabled && _rows.length < widget.maxPeriods ? _addPeriod : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加一节'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: widget.enabled && _rows.length > 1 ? _removeLast : null,
              icon: const Icon(Icons.remove, size: 16),
              label: const Text('删除末节'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, int index) {
    final theme = Theme.of(context);
    final row = _rows[index];
    final err = _errors[index];
    final s = _parseTime(row.start.text);
    final e = _parseTime(row.end.text);
    final span = (s != null && e != null) ? _minutes(e) - _minutes(s) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '第${index + 1}节',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: _timeField(
              controller: row.start,
              label: '开始',
              hasError: err != null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Icon(Icons.remove, size: 12, color: theme.colorScheme.outline),
          ),
          SizedBox(
            width: 96,
            child: _timeField(
              controller: row.end,
              label: '结束',
              hasError: err != null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: err != null
                  ? Text(err, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))
                  : Text(
                      span == null ? '' : '$span 分钟',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          IconButton(
            tooltip: '删除该节',
            onPressed: widget.enabled && _rows.length > 1 ? () => _removeAt(index) : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _timeField({
    required TextEditingController controller,
    required String label,
    required bool hasError,
  }) {
    return TextField(
      controller: controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: (_) => _validateAndEmit(),
      onSubmitted: (_) => _validateAndEmit(),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: '08:00',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        errorText: hasError ? '' : null,
        errorStyle: const TextStyle(fontSize: 0, height: 0),
        errorBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
      ),
    );
  }
}

class _SlotRow {
  _SlotRow({required this.period, required this.start, required this.end});

  int period;
  final TextEditingController start;
  final TextEditingController end;
}