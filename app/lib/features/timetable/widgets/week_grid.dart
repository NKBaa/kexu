import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/conflict_utils.dart';
import '../../../core/utils/week_utils.dart';
import '../../../data/models/course.dart';
import '../../../data/models/semester.dart';
import '../../../data/models/timetable.dart';
import 'course_card.dart';

/// 周课表网格：左侧固定时间轴 + 右侧周一~周日（可只显示工作日）。
///
/// - 每节一行，行高由可用高度自适应（[minRowHeight] 为下限，放不下则纵向滚动）；
/// - 每个 [Session] 在所属星期列中纵向跨 `SessionEntry.rowSpan` 行；
/// - **同一列里节次相交的多个时段横向并排**（按重叠簇分栏），冲突日整列按栏数
///   适当加宽，避免每张卡被压成一条竖条；不相交的时段仍占满整列宽度。
/// - 时间冲突（同一天、节次相交、周次相交）的卡片加警告色描边 + 警告图标，
///   对应星期的表头也会出现一个警告标记；冲突判定见 [conflictedSessionIds]；
/// - 列宽由 `Expanded` 均分；手机竖屏默认按可用宽度均分，让 7 天（隐藏周末时 5 天）
///   一屏放下，只有窄到列宽不足时外层才退化为横向滚动；
/// - [showWeekend] 为 false 时只渲染周一到周五（设置里的「显示周六、周日」）。
/// - **长按**课程卡片可打开编辑页修改课程信息；
/// - **拖动**课程卡片可调整它占用的节次（保持跨节数不变，星期不变）。
class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.timetable,
    required this.week,
    this.onTap,
    this.onLongPress,
    this.onBlankRangeSelected,
    this.onPeriodsChanged,
    this.today,
    this.showWeekend = true,
    this.holidayDays = const <int>{},
    this.minRowHeight = 52,
    this.timeAxisWidth = 64,
  });

  final Timetable timetable;

  /// 当前显示的周次（1-based）。
  final int week;

  /// 卡片点击回调。
  final void Function(Course, Session)? onTap;

  /// 卡片长按回调（编辑课程信息）。
  final void Function(Course, Session)? onLongPress;

  /// 长按空白处并拖动选择节次范围后回调（星期 1~7，start/end 1-based，含两端）。
  final void Function(int dayOfWeek, int startPeriod, int endPeriod)?
      onBlankRangeSelected;

  /// 拖动课程后回调新的节次范围与目标星期（start/end 含两端，dayOfWeek 1~7）。
  final void Function(
    Course course,
    Session session,
    int startPeriod,
    int endPeriod,
    int dayOfWeek,
  )? onPeriodsChanged;

  /// 用于高亮「今天」所在列；为空则不标记。
  final DateTime? today;

  /// 是否显示周六、周日两列（false 时只显示周一到周五）。
  final bool showWeekend;

  /// 当前周里放假的星期（1=周一 … 7=周日），这些列不显示课程，改显示「节假日」。
  final Set<int> holidayDays;

  final double minRowHeight;
  final double timeAxisWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxPeriod = timetable.maxPeriod;
    final rawByDay = timetable.byDayForWeek(week);
    final dayCount = showWeekend ? 7 : 5;
    final byDay = <int, List<SessionEntry>>{
      for (var day = 1; day <= 7; day++)
        day: holidayDays.contains(day)
            ? const <SessionEntry>[]
            : (rawByDay[day] ?? const <SessionEntry>[]),
    };
    // 作息可能有多套（夏季/秋季作息不同），按**当前展示周**的日期挑选生效的那套，
    // 而不是永远用第一套。
    final weekSchedule = timetable.scheduleForDate(
      dateOfWeekDay(timetable.semester.startMonday, week < 1 ? 1 : week, 1),
    );
    final slots = <int, TimeSlot>{
      for (final slot in weekSchedule.slots) slot.period: slot,
    };
    // 只有「今天」确实落在当前显示的周次时才高亮；
    // 否则切到其它周时，同一星期几会被误标成今天。
    final todayWeek = today == null
        ? null
        : weekOfDate(today!, timetable.semester.startMonday);
    final todayDow = todayWeek == week ? today?.weekday : null;

    // 冲突日按分栏数横向加宽：让并排的每门课仍有接近普通列的宽度，
    // 而不是被压成一条只放得下一个字的竖条；其它列等比略窄。
    final dayFlex = <int, int>{
      for (var day = 1; day <= dayCount; day++)
        day: _dayFlexFor(byDay[day] ?? const <SessionEntry>[]),
    };

    // 每天是否有时间冲突：用于表头标记（卡片级高亮在 _DayColumn 内计算）。
    final conflictDays = <int>{
      for (var day = 1; day <= dayCount; day++)
        if (conflictedSessionIds(byDay[day] ?? const <SessionEntry>[]).isNotEmpty)
          day,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.maxHeight.isFinite;
        const headerHeight = 44.0;
        final available = bounded ? constraints.maxHeight - headerHeight : 0.0;

        var rowHeight = minRowHeight;
        if (available > 0) {
          final fit = available / maxPeriod;
          if (fit > rowHeight) rowHeight = fit;
        }
        final gridHeight = rowHeight * maxPeriod;

        final header = SizedBox(
          height: headerHeight,
          child: Row(
            children: [
              SizedBox(
                width: timeAxisWidth,
                child: Center(
                  child: Text(
                    '节次',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              for (var day = 1; day <= dayCount; day++)
                Expanded(
                  flex: dayFlex[day]!,
                  child: _DayHeader(
                    day: day,
                    week: week,
                    startMonday: timetable.semester.startMonday,
                    isToday: todayDow == day,
                    hasConflict: conflictDays.contains(day),
                    isHoliday: holidayDays.contains(day),
                  ),
                ),
            ],
          ),
        );

        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimeAxis(
              slots: slots,
              maxPeriod: maxPeriod,
              rowHeight: rowHeight,
              width: timeAxisWidth,
            ),
            for (var day = 1; day <= dayCount; day++)
              Expanded(
                flex: dayFlex[day]!,
                child: _DayColumn(
                  day: day,
                  entries: byDay[day] ?? const <SessionEntry>[],
                  slots: slots,
                  rowHeight: rowHeight,
                  maxPeriod: maxPeriod,
                  isToday: todayDow == day,
                  isHoliday: holidayDays.contains(day),
                  onTap: onTap,
                  onLongPress: onLongPress,
                  onBlankRangeSelected: onBlankRangeSelected,
                  onPeriodsChanged: onPeriodsChanged,
                ),
              ),
          ],
        );

        // 高度无界（例如被放进外层滚动容器）：整体滚动。
        if (!bounded) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                SizedBox(height: gridHeight, child: row),
              ],
            ),
          );
        }

        final Widget body = gridHeight > available + 0.5
            ? SingleChildScrollView(
                child: SizedBox(height: gridHeight, child: row),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: SizedBox(height: gridHeight, child: row),
              );

        return Column(
          children: [
            header,
            Expanded(child: body),
          ],
        );
      },
    );
  }
}

/// 左侧时间轴：每节显示节次号 + 起止时间。
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.slots,
    required this.maxPeriod,
    required this.rowHeight,
    required this.width,
  });

  final Map<int, TimeSlot> slots;
  final int maxPeriod;
  final double rowHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lineColor = scheme.outline.withAlpha(90);

    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: scheme.outline.withAlpha(160), width: 0.6),
        ),
      ),
      child: Column(
        children: [
          for (var period = 1; period <= maxPeriod; period++)
            Container(
              height: rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: lineColor, width: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$period',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (rowHeight >= 36)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      // 时间轴窄（手机竖屏要放下 7 天，轴只有 50 宽）时，
                      // 「08:00-08:45」横排会被截断，改成上下两行显示。
                      child: width >= 60
                          ? Text(
                              slots[period]?.label ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  slots[period]?.start ?? '',
                                  maxLines: 1,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 9,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  slots[period]?.end ?? '',
                                  maxLines: 1,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 9,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 顶部星期表头（周一~周日 + 具体日期）。
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.week,
    required this.startMonday,
    required this.isToday,
    this.hasConflict = false,
    this.isHoliday = false,
  });

  final int day;
  final int week;
  final DateTime startMonday;
  final bool isToday;

  /// 该天是否存在时间冲突（右上角显示警告标记）。
  final bool hasConflict;

  /// 该天是否为用户添加的节假日。
  final bool isHoliday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = week >= 1 ? dateOfWeekDay(startMonday, week, day) : null;
    final foreground = isHoliday
        ? scheme.onTertiaryContainer
        : (isToday ? scheme.onPrimaryContainer : scheme.onSurface);
    final secondary = isHoliday
        ? scheme.onTertiaryContainer
        : (isToday ? scheme.onPrimaryContainer : scheme.onSurfaceVariant);

    return Container(
      decoration: BoxDecoration(
        color: isHoliday
            ? scheme.tertiaryContainer.withAlpha(150)
            : (isToday ? scheme.primaryContainer : null),
        border: Border(
          left: BorderSide(color: scheme.outline.withAlpha(90), width: 0.6),
        ),
      ),
      alignment: Alignment.center,
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weekdayShortNames[day - 1],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (date != null)
                  Text(
                    '${date.month}/${date.day}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      color: secondary,
                    ),
                  ),
              ],
            ),
          ),
          if (hasConflict)
            Positioned(
              top: 1,
              right: 1,
              child: Semantics(
                label: '该天存在时间冲突',
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 12,
                  color: scheme.error,
                ),
              ),
            ),
          if (isHoliday)
            Positioned(
              top: 1,
              left: 2,
              child: Semantics(
                label: '节假日',
                child: Text(
                  '假',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个星期列：节次分隔线 + 课程卡片。
///
/// 同一 `startPeriod` 分组内的 N 个时段**并排**（N 列），
/// 跨节时段仍按 `rowSpan` 计算高度；时间冲突的卡片加高亮。
class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.day,
    required this.entries,
    required this.slots,
    required this.rowHeight,
    required this.maxPeriod,
    required this.isToday,
    required this.isHoliday,
    required this.onTap,
    required this.onLongPress,
    required this.onBlankRangeSelected,
    required this.onPeriodsChanged,
  });

  final int day;
  final List<SessionEntry> entries;
  final Map<int, TimeSlot> slots;
  final double rowHeight;
  final int maxPeriod;
  final bool isToday;
  final bool isHoliday;
  final void Function(Course, Session)? onTap;
  final void Function(Course, Session)? onLongPress;
  final void Function(int dayOfWeek, int startPeriod, int endPeriod)?
      onBlankRangeSelected;
  final void Function(Course, Session, int, int, int)? onPeriodsChanged;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  int? _previewStart;
  int? _previewEnd;

  /// 空白处长按拖动时正在选择的节次范围。
  int? _createStart;
  int? _createEnd;

  int _periodAt(double dy) =>
      ((dy / widget.rowHeight).floor() + 1).clamp(1, widget.maxPeriod).toInt();

  ({int start, int end})? _resolve(DragTargetDetails<_DragSession> details) {
    final render = context.findRenderObject();
    if (render is! RenderBox) return null;
    final local = render.globalToLocal(details.offset);
    return resolveDraggedPeriods(
      dropTopDy: local.dy,
      rowHeight: widget.rowHeight,
      originalStart: details.data.session.startPeriod,
      originalEnd: details.data.session.endPeriod,
      maxPeriod: widget.maxPeriod,
    );
  }

  void _clearPreview() {
    if (_previewStart == null && _previewEnd == null) return;
    setState(() {
      _previewStart = null;
      _previewEnd = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (widget.isHoliday) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withAlpha(70),
          border: Border(
            left: BorderSide(color: scheme.outline.withAlpha(90), width: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: RotatedBox(
          quarterTurns: 1,
          child: Text(
            '节假日',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      );
    }

    // 该列内「与其它时段冲突」的时段 id（同一天内判定）。
    final conflicted = conflictedSessionIds(widget.entries);

    // 冲突课程横向分栏：同一天里节次相交的课程各占一栏并排显示，
    // 不再纵向叠在一起（竖向空间有限时叠放会互相遮挡）。
    final placed = layoutSessionLanes(widget.entries);

    final column = Container(
      decoration: BoxDecoration(
        color: widget.isToday ? scheme.primary.withAlpha(12) : null,
        border: Border(
          left: BorderSide(color: scheme.outline.withAlpha(90), width: 0.6),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnWidth = constraints.maxWidth;
          return Stack(
            children: [
              // 节次分隔线
              Column(
                children: [
                  for (var period = 1; period <= widget.maxPeriod; period++)
                    Container(
                      height: widget.rowHeight,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: scheme.outline.withAlpha(60),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              for (final item in placed)
                _positionedCard(item, conflicted, columnWidth),
              // 长按空白拖动时，画出正在选择的节次范围。
              if (_createStart != null && _createEnd != null)
                Positioned(
                  top: (math.min(_createStart!, _createEnd!) - 1) *
                          widget.rowHeight +
                      2,
                  height: (math.max(_createStart!, _createEnd!) -
                              math.min(_createStart!, _createEnd!) +
                              1) *
                          widget.rowHeight -
                      4,
                  left: 2,
                  right: 2,
                  child: IgnorePointer(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.6),
                          width: 1.4,
                        ),
                      ),
                      child: Text(
                        math.min(_createStart!, _createEnd!) ==
                                math.max(_createStart!, _createEnd!)
                            ? '第 ${_createStart!} 节'
                            : '第 ${math.min(_createStart!, _createEnd!)}-'
                                '${math.max(_createStart!, _createEnd!)} 节',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              // 拖动经过本列时，画出目标时间段并标注「第 X-Y 节」。
              if (_previewStart != null && _previewEnd != null)
                Positioned(
                  top: (_previewStart! - 1) * widget.rowHeight + 2,
                  height: (_previewEnd! - _previewStart! + 1) * widget.rowHeight - 4,
                  left: 2,
                  right: 2,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        border: Border.all(color: scheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _previewStart == _previewEnd
                              ? '第$_previewStart节'
                              : '第$_previewStart-$_previewEnd节',
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );

    // 空白处长按：按落点换算节次，用于「在点击处新增课程」。
    final gestureColumn = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: widget.onBlankRangeSelected == null
          ? null
          : (details) {
              final period = _periodAt(details.localPosition.dy);
              HapticFeedback.selectionClick();
              setState(() {
                _createStart = period;
                _createEnd = period;
              });
            },
      onLongPressMoveUpdate: widget.onBlankRangeSelected == null
          ? null
          : (details) {
              if (_createStart == null) return;
              final period = _periodAt(details.localPosition.dy);
              if (period == _createEnd) return;
              setState(() => _createEnd = period);
            },
      onLongPressEnd: widget.onBlankRangeSelected == null
          ? null
          : (_) {
              final start = _createStart;
              final end = _createEnd;
              setState(() {
                _createStart = null;
                _createEnd = null;
              });
              if (start == null || end == null) return;
              widget.onBlankRangeSelected!(
                widget.day,
                math.min(start, end),
                math.max(start, end),
              );
            },
      child: column,
    );

    if (widget.onPeriodsChanged == null) return gestureColumn;

    // 整列作为放置目标：同一周内可拖到任意星期（不再限制原星期），
    // 落点纵向位置决定新的起始节次，横向列决定新的星期。
    return DragTarget<_DragSession>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        final periods = _resolve(details);
        if (periods == null) return;
        if (periods.start == _previewStart && periods.end == _previewEnd) return;
        setState(() {
          _previewStart = periods.start;
          _previewEnd = periods.end;
        });
      },
      onLeave: (_) => _clearPreview(),
      onAcceptWithDetails: (details) {
        final periods = _resolve(details);
        _clearPreview();
        if (periods == null) return;
        if (periods.start == details.data.session.startPeriod &&
            periods.end == details.data.session.endPeriod &&
            widget.day == details.data.session.dayOfWeek) {
          return;
        }
        widget.onPeriodsChanged!(
          details.data.course,
          details.data.session,
          periods.start,
          periods.end,
          widget.day,
        );
      },
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: active
                ? Border.all(color: scheme.primary, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: gestureColumn,
        );
      },
    );
  }

  /// 把一条时段放到它所属的横向分栏里。
  ///
  /// 同一天内节次相交的课程会被分到不同 lane（并排），
  /// 不相交的课程独占整列宽度；纵向位置仍由起止节次决定。
  Widget _positionedCard(
    PlacedSession placed,
    Set<String> conflicted,
    double columnWidth,
  ) {
    final session = placed.entry.session;
    final span = session.endPeriod - session.startPeriod + 1;
    final laneWidth = columnWidth / placed.laneCount;
    final width = (laneWidth - 2).clamp(6.0, laneWidth);
    final left = (placed.lane * laneWidth + 1).clamp(0.0, columnWidth - width);
    final cardHeight = span * widget.rowHeight - 4;
    final startSlot = widget.slots[session.startPeriod];
    final endSlot = widget.slots[session.endPeriod];
    final timeLabel = startSlot != null && endSlot != null
        ? '${startSlot.start}-${endSlot.end}'
        : '';

    return Positioned(
      top: (session.startPeriod - 1) * widget.rowHeight,
      height: span * widget.rowHeight,
      left: left,
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: _draggableCard(
          CourseCard(
            course: placed.entry.course,
            session: session,
            timeLabel: timeLabel,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            conflicting: conflicted.contains(session.id),
          ),
          placed.entry,
          // 窄卡片放不下拖动手柄，也避免手柄盖住文字；这类卡片仍可长按编辑。
          showHandle: width >= 30 && cardHeight >= 36,
          cardWidth: width,
          cardHeight: cardHeight,
        ),
      ),
    );
  }

  /// 把卡片包成可拖动的（同一周内可拖到任意星期 / 节次）。
  ///
  /// 只有右下角的「拖动柄」能发起拖动，卡片正文的点击/长按仍分别用于
  /// 查看详情和编辑课程，避免手指在课表上滑动时误触拖动。
  Widget _draggableCard(
    Widget card,
    SessionEntry entry, {
    required bool showHandle,
    required double cardWidth,
    required double cardHeight,
  }) {
    if (widget.onPeriodsChanged == null || !showHandle) return card;

    Widget handle() => Container(
          key: ValueKey('course_drag_handle_${entry.session.id}'),
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            Icons.drag_indicator,
            size: 12,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        );

    final data = _DragSession(course: entry.course, session: entry.session);
    final feedback = SizedBox(
      width: 120,
      height: 56,
      child: CourseCard(course: entry.course, session: entry.session),
    );

    return Stack(
      children: [
        card,
        Positioned(
          right: 2,
          bottom: 2,
          child: Tooltip(
            message: '按住拖动调整节次',
            child: Draggable<_DragSession>(
              data: data,
              feedback: feedback,
              // 手指按在右下角手柄上时，让反馈卡片的左上角对齐原卡片左上角，
              // 这样落点节次 = 卡片顶部所在节次，不会因手柄位置整体偏移。
              dragAnchorStrategy: (draggable, context, position) =>
                  Offset(cardWidth - 8, cardHeight - 8),
              childWhenDragging: Opacity(opacity: 0.3, child: handle()),
              child: handle(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 拖动中的课程数据（用于 DragTarget 判定与回写）。
class _DragSession {
  const _DragSession({required this.course, required this.session});

  final Course course;
  final Session session;
}

/// 根据拖动落点的纵向位置换算新的节次范围。
///
/// 规则：
/// - 保持原有**跨节数**不变（只整体移动，不改变时长）；
/// - 结果夹在 1~[maxPeriod] 内，拖出边界时贴边；
/// - 抽成顶层函数便于单元测试（UI 只负责把落点坐标传进来）。
({int start, int end}) resolveDraggedPeriods({
  required double dropTopDy,
  required double rowHeight,
  required int originalStart,
  required int originalEnd,
  required int maxPeriod,
}) {
  final span = (originalEnd - originalStart).clamp(0, maxPeriod - 1);
  final rawStart = (dropTopDy / rowHeight).floor() + 1;
  final start = rawStart.clamp(1, maxPeriod - span);
  return (start: start, end: start + span);
}

/// 一个时段在当天列里的横向分栏位置。
class PlacedSession {
  const PlacedSession({
    required this.entry,
    required this.lane,
    required this.laneCount,
  });

  final SessionEntry entry;

  /// 第几栏（从 0 开始）。
  final int lane;

  /// 该时段所在「重叠簇」一共分几栏。
  final int laneCount;
}

/// 把同一天的时段按「节次是否相交」分配到横向分栏（lane）。
///
/// 背景：以前只把「起始节次相同」的课程并排，起始节次不同但节次相交的课程
/// （如 1-2 节与 2-3 节）会纵向叠在一起互相遮挡。现在按区间图着色：
/// - 相交的时段一定在不同 lane（横向并排）；
/// - 不相交的时段尽量复用 lane（占满整列宽度）；
/// - 每个「重叠簇」单独计算 lane 数，避免一处冲突把整天课程都挤窄。
///
/// 抽成顶层纯函数便于单元测试。
List<PlacedSession> layoutSessionLanes(List<SessionEntry> entries) {
  if (entries.isEmpty) return const <PlacedSession>[];

  // 先按起始节次排序（相同起点按结束节次），保证贪心分栏最优。
  final sorted = List<SessionEntry>.of(entries)
    ..sort((a, b) {
      final c = a.session.startPeriod.compareTo(b.session.startPeriod);
      if (c != 0) return c;
      return a.session.endPeriod.compareTo(b.session.endPeriod);
    });

  // laneEnds[lane] = 该栏已放置时段的最后结束节次。
  final laneEnds = <int>[];
  final laneOf = <int>[];
  for (var i = 0; i < sorted.length; i++) {
    final session = sorted[i].session;
    var lane = 0;
    while (lane < laneEnds.length && laneEnds[lane] >= session.startPeriod) {
      lane++;
    }
    if (lane == laneEnds.length) {
      laneEnds.add(session.endPeriod);
    } else {
      laneEnds[lane] = session.endPeriod;
    }
    laneOf.add(lane);
  }

  // 重叠簇：按起始节次扫描，start > 当前簇最大 end 时开启新簇。
  final clusterOf = <int>[];
  var cluster = 0;
  var clusterEnd = sorted.first.session.endPeriod;
  clusterOf.add(cluster);
  for (var i = 1; i < sorted.length; i++) {
    final session = sorted[i].session;
    if (session.startPeriod > clusterEnd) {
      cluster++;
      clusterEnd = session.endPeriod;
    } else if (session.endPeriod > clusterEnd) {
      clusterEnd = session.endPeriod;
    }
    clusterOf.add(cluster);
  }

  // 每个簇的 lane 数 = 该簇内最大 lane + 1。
  final clusterLaneCount = <int, int>{};
  for (var i = 0; i < sorted.length; i++) {
    final need = laneOf[i] + 1;
    if (need > (clusterLaneCount[clusterOf[i]] ?? 0)) {
      clusterLaneCount[clusterOf[i]] = need;
    }
  }

  return [
    for (var i = 0; i < sorted.length; i++)
      PlacedSession(
        entry: sorted[i],
        lane: laneOf[i],
        laneCount: clusterLaneCount[clusterOf[i]] ?? 1,
      ),
  ];
}

/// 某一天列需要的 flex：按该天最大分栏数横向加宽（上限 4，避免其它列过窄）。
///
/// 例如某天同时有 2 门冲突课，这一列占 2 份宽度，两门课各占约 1 份，
/// 与普通单列宽度接近，文字不会被压成一条竖线；其余列按比例略窄。
int _dayFlexFor(List<SessionEntry> entries) {
  if (entries.isEmpty) return 1;
  var maxLanes = 1;
  for (final placed in layoutSessionLanes(entries)) {
    if (placed.laneCount > maxLanes) maxLanes = placed.laneCount;
  }
  return math.min(4, math.max(1, maxLanes));
}
