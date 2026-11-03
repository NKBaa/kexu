import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/utils/week_utils.dart';
import '../../../data/models/course.dart';
import '../../../data/models/semester.dart';
import 'week_picker.dart';

/// 单个上课时段（[Session]）的编辑控件。
///
/// 一个 [Session] = 星期 + 起始/结束节次 + 生效周次 + 地点（+ 可选单独教师）。
/// 本控件不持有真值：任何字段变化都通过 [onChanged] 把新的 [Session] 抛给父级，
/// 由课程编辑器统一维护 `List<Session>`（便于跨时段校验冲突、整体保存）。
///
/// [slotIssues] 由父级算好后传入，用于展示「同一星期 + 节次重叠」等冲突提示。
class SessionEditor extends StatefulWidget {
  const SessionEditor({
    super.key,
    required this.index,
    required this.session,
    required this.timeSlots,
    required this.totalWeeks,
    required this.onChanged,
    this.onRemove,
    this.onDuplicate,
    this.slotIssues = const [],
    this.showTeacherField = false,
    this.compact = false,
    this.initiallyExpanded = true,
  });

  /// 第几个时段（从 0 开始），仅用于展示与删除回调。
  final int index;

  final Session session;
  final List<TimeSlot> timeSlots;
  final int totalWeeks;

  final ValueChanged<Session> onChanged;

  /// 删除该时段；为 null 时显示为禁用（至少保留一个时段）。
  final VoidCallback? onRemove;

  /// 复制该时段；父级实现。
  final VoidCallback? onDuplicate;

  /// 该时段的校验问题（空表示无问题）。
  final List<String> slotIssues;

  /// 是否显示「此时段单独教师」输入框（与课程默认教师不同时用）。
  final bool showTeacherField;

  final bool compact;
  final bool initiallyExpanded;

  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  late final TextEditingController _locationCtrl;
  late final TextEditingController _teacherCtrl;
  late final FocusNode _locationFocus;
  late final FocusNode _teacherFocus;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _locationCtrl = TextEditingController(text: widget.session.location ?? '');
    _teacherCtrl = TextEditingController(text: widget.session.teacher ?? '');
    _locationFocus = FocusNode();
    _teacherFocus = FocusNode();
    _expanded = widget.initiallyExpanded;
    _locationFocus.addListener(_syncFromSessionOnBlur);
    _teacherFocus.addListener(_syncFromSessionOnBlur);
  }

  @override
  void didUpdateWidget(covariant SessionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一条时段（列表里删/增/重排）时整体重置。
    if (oldWidget.session.id != widget.session.id) {
      _locationCtrl.text = widget.session.location ?? '';
      _teacherCtrl.text = widget.session.teacher ?? '';
      return;
    }
    // 外部（批量修改等）改了地点/教师且当前未聚焦时同步文本。
    final loc = widget.session.location ?? '';
    if (!_locationFocus.hasFocus && _locationCtrl.text != loc) {
      _locationCtrl.text = loc;
    }
    final teacher = widget.session.teacher ?? '';
    if (!_teacherFocus.hasFocus && _teacherCtrl.text != teacher) {
      _teacherCtrl.text = teacher;
    }
  }

  @override
  void dispose() {
    _locationFocus.removeListener(_syncFromSessionOnBlur);
    _teacherFocus.removeListener(_syncFromSessionOnBlur);
    _locationFocus.dispose();
    _teacherFocus.dispose();
    _locationCtrl.dispose();
    _teacherCtrl.dispose();
    super.dispose();
  }

  /// 失焦时把输入框内容规整（去掉多余空白），避免保存时带空格。
  void _syncFromSessionOnBlur() {
    if (_locationFocus.hasFocus || _teacherFocus.hasFocus) return;
    final loc = widget.session.location ?? '';
    final teacher = widget.session.teacher ?? '';
    if (_locationCtrl.text.trim() != loc) {
      _locationCtrl.text = loc;
    }
    if (_teacherCtrl.text.trim() != teacher) {
      _teacherCtrl.text = teacher;
    }
  }

  // ------------------------------------------------------------------ 工具

  /// 节次下拉的候选项：优先用学校作息表的节次，作息为空时退化为 1..12。
  List<int> get _periods {
    final fromSlots = widget.timeSlots.map((t) => t.period).where((p) => p > 0).toSet().toList()
      ..sort();
    if (fromSlots.isEmpty) {
      return List<int>.generate(12, (i) => i + 1);
    }
    return fromSlots;
  }

  TimeSlot? _slotOf(int period) {
    for (final t in widget.timeSlots) {
      if (t.period == period) return t;
    }
    return null;
  }

  /// 节次下拉项：`第 1 节 08:00-08:45`，让用户直接看到该节的作息时间。
  String _slotItemLabel(int period) {
    final s = _slotOf(period);
    return s == null ? '第$period节' : '第$period节 ${s.start}-${s.end}';
  }

  void _update(Session next) => widget.onChanged(next);

  void _onDayChanged(int? day) {
    if (day == null) return;
    _update(widget.session.copyWith(dayOfWeek: day));
  }

  void _onStartChanged(int? p) {
    if (p == null) return;
    // 起始节次不能大于结束节次，自动把结束节次顶上去。
    final end = widget.session.endPeriod < p ? p : widget.session.endPeriod;
    _update(widget.session.copyWith(startPeriod: p, endPeriod: end));
  }

  void _onEndChanged(int? p) {
    if (p == null) return;
    // 结束节次不能小于起始节次，自动把起始节次压下来。
    final start = widget.session.startPeriod > p ? p : widget.session.startPeriod;
    _update(widget.session.copyWith(startPeriod: start, endPeriod: p));
  }

  void _onWeeksChanged(List<int> weeks) {
    _update(widget.session.copyWith(weeks: weeks));
  }

  void _onLocationChanged(String raw) {
    final v = raw.trim();
    _update(
      widget.session.copyWith(
        location: v.isEmpty ? null : v,
        clearLocation: v.isEmpty,
      ),
    );
  }

  void _onTeacherChanged(String raw) {
    final v = raw.trim();
    _update(
      widget.session.copyWith(
        teacher: v.isEmpty ? null : v,
        clearTeacher: v.isEmpty,
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final hasIssue = widget.slotIssues.isNotEmpty;
    final summary = _summary();

    return Card(
      margin: EdgeInsets.symmetric(vertical: widget.compact ? 3 : 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: hasIssue
              ? theme.colorScheme.error.withValues(alpha: 0.7)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, summary, hasIssue),
          if (_expanded)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildScheduleRow(context),
                  const SizedBox(height: 10),
                  WeekPicker(
                    totalWeeks: widget.totalWeeks,
                    selectedWeeks: s.weeks,
                    onChanged: _onWeeksChanged,
                    dense: true,
                    maxGridHeight: 116,
                    label: '上课周次',
                    helperText: widget.totalWeeks > 0 ? '共 ${widget.totalWeeks} 周' : null,
                  ),
                  const SizedBox(height: 8),
                  _buildLocationRow(context),
                  if (hasIssue) ...[
                    const SizedBox(height: 8),
                    _buildIssueBanner(context),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String summary, bool hasIssue) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasIssue
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${widget.index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hasIssue
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasIssue)
              Tooltip(
                message: widget.slotIssues.join('\n'),
                child: Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
              ),
            if (widget.onDuplicate != null)
              IconButton(
                tooltip: '复制此时段',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                onPressed: widget.onDuplicate,
              ),
            IconButton(
              tooltip: widget.onRemove == null ? '至少保留一个时段' : '删除此时段',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: widget.onRemove == null
                    ? theme.colorScheme.outline
                    : theme.colorScheme.error,
              ),
              onPressed: widget.onRemove,
            ),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// 摘要：`周一 第1-2节 08:00-09:40 · 1-16周(单)`。
  String _summary() {
    final s = widget.session;
    final buf = StringBuffer(weekdayName(s.dayOfWeek))
      ..write(' ')
      ..write(s.startPeriod == s.endPeriod ? '第${s.startPeriod}节' : '第${s.startPeriod}-${s.endPeriod}节');
    final t = _periodTimeRangeLabel();
    if (t.isNotEmpty) buf.write(' $t');
    if (s.weeks.isEmpty) {
      buf.write(' · 未选周次');
    } else {
      buf.write(' · ${formatWeeks(s.weeks)}');
    }
    return buf.toString();
  }

  Widget _buildScheduleRow(BuildContext context) {
    final theme = Theme.of(context);
    final periods = _periods;
    final days = <int>[1, 2, 3, 4, 5, 6, 7];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: widget.compact ? 116 : 132,
          child: DropdownButtonFormField<int>(
            initialValue: days.contains(widget.session.dayOfWeek) ? widget.session.dayOfWeek : 1,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '星期',
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            items: [
              for (final d in days)
                DropdownMenuItem(value: d, child: Text(weekdayName(d))),
            ],
            onChanged: _onDayChanged,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.compact ? 128 : 146,
              child: DropdownButtonFormField<int>(
                initialValue: periods.contains(widget.session.startPeriod)
                    ? widget.session.startPeriod
                    : periods.first,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '开始节',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                selectedItemBuilder: (context) => [
                  for (final p in periods) Text('第$p节'),
                ],
                items: [
                  for (final p in periods)
                    DropdownMenuItem(
                      value: p,
                      child: Text(
                        _slotItemLabel(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _onStartChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(
              width: widget.compact ? 128 : 146,
              child: DropdownButtonFormField<int>(
                initialValue: periods.contains(widget.session.endPeriod)
                    ? widget.session.endPeriod
                    : periods.last,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '结束节',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                ),
                selectedItemBuilder: (context) => [
                  for (final p in periods)
                    if (p >= widget.session.startPeriod) Text('第$p节'),
                ],
                items: [
                  for (final p in periods)
                    if (p >= widget.session.startPeriod)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          _slotItemLabel(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
                onChanged: _onEndChanged,
              ),
            ),
          ],
        ),
        if (!widget.compact)
          Text(
            _periodTimeRangeLabel(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  String _periodTimeRangeLabel() {
    final s = widget.session;
    final start = _slotOf(s.startPeriod);
    final end = _slotOf(s.endPeriod);
    if (start == null && end == null) return '';
    final a = start?.start ?? '';
    final b = end?.end ?? '';
    if (a.isEmpty || b.isEmpty) return '';
    return '$a-$b';
  }

  Widget _buildLocationRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _locationCtrl,
            focusNode: _locationFocus,
            textInputAction: widget.showTeacherField ? TextInputAction.next : TextInputAction.done,
            onChanged: _onLocationChanged,
            onSubmitted: widget.showTeacherField
                ? (_) => _teacherFocus.requestFocus()
                : (_) => _locationFocus.unfocus(),
            decoration: const InputDecoration(
              isDense: true,
              labelText: '地点',
              hintText: '如 A101 / 线上',
              prefixIcon: Icon(Icons.place_outlined, size: 18),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
        ),
        if (widget.showTeacherField) ...[
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _teacherCtrl,
              focusNode: _teacherFocus,
              textInputAction: TextInputAction.done,
              onChanged: _onTeacherChanged,
              onSubmitted: (_) => _teacherFocus.unfocus(),
              decoration: InputDecoration(
                isDense: true,
                labelText: '此时段教师',
                hintText: '留空用课程教师',
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                suffixIcon: _teacherCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _teacherCtrl.clear();
                          _onTeacherChanged('');
                        },
                      ),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _weeksBadge(context),
        ),
      ],
    );
  }

  Widget _weeksBadge(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final text = s.weeks.isEmpty ? '未选周次' : '${s.weeks.length}周';
    final empty = s.weeks.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: empty
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: empty ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIssueBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.slotIssues.join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}