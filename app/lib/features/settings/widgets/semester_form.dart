import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/week_utils.dart';
import '../../../core/widgets/hint_icon.dart';
import '../../../data/models/semester.dart';

/// 学期表单：名称 / 第 1 周周一 / 总周数。
///
/// 这三项是整个课表的时间基准（周次换算、今日视图、周次选择器范围都依赖它），
/// 因此这里对输入做了较严格的约束：
/// - 「第 1 周周一」无论选哪天都会归一化到所在周的周一；
/// - 总周数限制在 1~60。
///
/// 表单不自己保存，任何改动通过 [onChanged] 抛给父级（设置页统一保存）。
class SemesterForm extends StatefulWidget {
  const SemesterForm({
    super.key,
    required this.semester,
    required this.onChanged,
    this.enabled = true,
    this.showNameField = true,
  });

  final Semester semester;
  final ValueChanged<Semester> onChanged;
  final bool enabled;
  final bool showNameField;

  @override
  State<SemesterForm> createState() => _SemesterFormState();
}

class _SemesterFormState extends State<SemesterForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _weeksCtrl;
  late final TextEditingController _startCtrl;
  late final TextEditingController _currentWeekCtrl;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _weeksFocus = FocusNode();
  final FocusNode _currentWeekFocus = FocusNode();
  String? _weeksError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.semester.name);
    _weeksCtrl = TextEditingController(text: '${widget.semester.totalWeeks}');
    _startCtrl = TextEditingController(text: _startLabel(widget.semester.startMonday));
    _currentWeekCtrl = TextEditingController(text: '${_currentWeekGuess()}');
  }

  static String _startLabel(DateTime d) =>
      '${_formatDate(d)} ${_weekdayLabel(d.weekday)}';

  /// 按「今天」推算当前是第几周，用于「按今天定位」的默认值。
  ///
  /// 今天不在学期内时夹到 1~总周数，避免默认值是个离谱的数字。
  int _currentWeekGuess() {
    final w = weekOfDate(DateTime.now(), widget.semester.startMonday);
    if (w < 1) return 1;
    if (w > widget.semester.totalWeeks) return widget.semester.totalWeeks;
    return w;
  }

  @override
  void didUpdateWidget(covariant SemesterForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semester.id != widget.semester.id) {
      _nameCtrl.text = widget.semester.name;
      _weeksCtrl.text = '${widget.semester.totalWeeks}';
      _startCtrl.text = _startLabel(widget.semester.startMonday);
      _currentWeekCtrl.text = '${_currentWeekGuess()}';
      _weeksError = null;
      return;
    }
    if (oldWidget.semester.startMonday != widget.semester.startMonday) {
      _startCtrl.text = _startLabel(widget.semester.startMonday);
    }
    if (!_nameFocus.hasFocus && _nameCtrl.text != widget.semester.name) {
      _nameCtrl.text = widget.semester.name;
    }
    if (!_weeksFocus.hasFocus) {
      final t = '${widget.semester.totalWeeks}';
      if (_weeksCtrl.text != t) {
        _weeksCtrl.text = t;
        _weeksError = null;
      }
    }
    if (!_currentWeekFocus.hasFocus) {
      final t = '${_currentWeekGuess()}';
      if (_currentWeekCtrl.text != t) _currentWeekCtrl.text = t;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _weeksCtrl.dispose();
    _startCtrl.dispose();
    _currentWeekCtrl.dispose();
    _nameFocus.dispose();
    _weeksFocus.dispose();
    _currentWeekFocus.dispose();
    super.dispose();
  }

  void _emit({String? name, DateTime? startMonday, int? totalWeeks}) {
    widget.onChanged(
      widget.semester.copyWith(
        name: name ?? _nameCtrl.text.trim(),
        startMonday: startMonday ?? widget.semester.startMonday,
        totalWeeks: totalWeeks ?? widget.semester.totalWeeks,
      ),
    );
  }

  void _onNameChanged(String v) => _emit(name: v.trim());

  void _onWeeksChanged(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 1 || n > 60) {
      setState(() => _weeksError = '请输入 1~60 之间的周数');
      return;
    }
    setState(() => _weeksError = null);
    _emit(totalWeeks: n);
  }

  Future<void> _pickStartMonday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.semester.startMonday,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择第 1 周的任意一天',
      cancelText: '取消',
      confirmText: '确定',
      fieldLabelText: '日期',
    );
    if (picked == null) return;
    // 统一归一化到所在周的周一，避免用户点错到周二导致周次计算整体偏移。
    _emit(startMonday: mondayOf(picked));
  }

  /// 「按今天定位」：把今天算作第 [n] 周，反推第 1 周的周一。
  ///
  /// 用户往往只记得「现在是第几周」，不一定记得开学那周的周一，
  /// 这个入口让学期范围可以直接由「今天第 N 周」确定。
  void _applyCurrentWeek() {
    final n = int.tryParse(_currentWeekCtrl.text.trim());
    if (n == null || n < 1 || n > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 1~60 之间的周数')),
      );
      return;
    }
    final start = startMondayForWeek(DateTime.now(), n);
    _emit(startMonday: start);
    _currentWeekFocus.unfocus();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已按「今天第 $n 周」定位：第 1 周周一 = ${_formatDate(start)}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sem = widget.semester;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showNameField) ...[
          TextField(
            controller: _nameCtrl,
            focusNode: _nameFocus,
            enabled: widget.enabled,
            textInputAction: TextInputAction.next,
            onChanged: _onNameChanged,
            onSubmitted: (_) => _weeksFocus.requestFocus(),
            decoration: InputDecoration(
              isDense: true,
              labelText: '学期名称',
              hintText: '如 2025-2026 学年第二学期',
              prefixIcon: const Icon(Icons.school_outlined, size: 18),
              suffixIcon: _nameCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _nameCtrl.clear();
                        _onNameChanged('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // 三个字段纵向排列：手机窄屏下并排会被图标与内边距挤到截断，
        // 纵向排列能保证日期与周数完整显示。
        TextField(
          key: const Key('semester_start_field'),
          controller: _startCtrl,
          readOnly: true,
          enabled: widget.enabled,
          onTap: _pickStartMonday,
          decoration: const InputDecoration(
            isDense: true,
            labelText: '第 1 周周一',
            prefixIcon: Icon(Icons.event_outlined, size: 18),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HintIcon(
                  message: '点击日期选择第 1 周中的任意一天，'
                      '系统会自动换算到这一周的周一。',
                ),
                Icon(Icons.calendar_month, size: 18),
                SizedBox(width: 8),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('semester_weeks_field'),
          controller: _weeksCtrl,
          focusNode: _weeksFocus,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: _onWeeksChanged,
          onSubmitted: (_) => _weeksFocus.unfocus(),
          decoration: const InputDecoration(
            isDense: true,
            labelText: '总周数',
            prefixIcon: Icon(Icons.date_range_outlined, size: 18),
            suffixText: '周',
            suffixIcon: HintIcon(
              message: '总周数常见 16~20 周，可手动输入 1~60。',
            ),
          ),
        ),
        if (_weeksError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _weeksError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 10),
        // 「按今天定位」做成独立浅色卡片：和上方输入框分开，窄屏也不会挤。
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.today_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('按「今天」快速定位学期', style: theme.textTheme.bodyMedium),
                  ),
                  HintIcon(
                    message: '今天：${_formatDate(DateTime.now())}。\n'
                        '把今天算作第 N 周，即可反推第 1 周周一。',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('今天是第', style: theme.textTheme.bodySmall),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      key: const Key('semester_current_week_field'),
                      controller: _currentWeekCtrl,
                      focusNode: _currentWeekFocus,
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '周',
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('周', style: theme.textTheme.bodySmall),
                  const Spacer(),
                  FilledButton.tonal(
                    key: const Key('semester_apply_current_week'),
                    onPressed: widget.enabled ? _applyCurrentWeek : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('定位'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '第 1 周周一：${_formatDate(sem.startMonday)}　·　学期结束：'
          '${_formatDate(addDays(sem.startMonday, sem.totalWeeks * 7 - 1))}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (!_isMonday(sem.startMonday))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '起始日期不是周一，周次换算会有偏差，建议改成 ${_formatDate(mondayOf(sem.startMonday))}。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool _isMonday(DateTime d) => d.weekday == DateTime.monday;

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _weekdayLabel(int weekday) => '周${weekdayShortNames[weekday - 1]}';
}