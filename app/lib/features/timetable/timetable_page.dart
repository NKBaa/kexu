import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/app_notice.dart';
import '../../core/utils/holiday_utils.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/course.dart';
import '../../data/models/holiday.dart';
import '../../data/models/semester.dart';
import '../../data/models/timetable.dart';
import 'providers/timetable_provider.dart';
import 'timetable_share_service.dart';
import '../batch/batch_ops_page.dart';
import '../editor/course_editor_page.dart';
import '../onboarding/onboarding_wizard_page.dart';
import '../settings/pages/data_settings_page.dart';
import '../settings/providers/settings_provider.dart';
import 'widgets/week_grid.dart';

enum _TimetableMenuAction {
  add,
  batch,
  share,
  data,
  tutorial,
  previousWeek,
  nextWeek,
}

/// 课表主视图。
///
/// 顶部参考移动端课表：大号「第 N 周」+ 日期，右侧添加/撤销/重做/更多；
/// 主体：[WeekGrid]（手机竖屏默认一屏放下 7 天/5 天，极窄屏才横向滚动；>=900 宽屏右侧附当日课程栏）；
/// 空课表时显示空状态并引导「添加课程 / 导入课表」。
class TimetablePage extends ConsumerWidget {
  const TimetablePage({
    super.key,
    this.onAddRequested,
  });

  /// 顶栏「添加」入口：手动添加、图片转课表等新增动作。
  /// AI 助手已移到外层右下角悬浮按钮，更突出、也支持直接上传图片。
  final VoidCallback? onAddRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timetableProvider);

    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('课表')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('课表')),
        body: _ErrorState(message: '$error'),
      ),
      data: (timetable) => _TimetableView(
        timetable: timetable,
        onAddRequested: onAddRequested,
      ),
    );
  }
}

class _TimetableView extends ConsumerStatefulWidget {
  const _TimetableView({
    required this.timetable,
    this.onAddRequested,
  });

  final Timetable timetable;
  final VoidCallback? onAddRequested;

  @override
  ConsumerState<_TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends ConsumerState<_TimetableView> {
  @override
  Widget build(BuildContext context) {
    final timetable = widget.timetable;
    final rawWeek = ref.watch(currentWeekProvider);
    final academicWeek = ref.watch(academicWeekProvider);
    final totalWeeks = timetable.semester.totalWeeks > 0
        ? timetable.semester.totalWeeks
        : (timetable.semester.allWeeks.isEmpty
            ? 16
            : timetable.semester.allWeeks.last);
    final week = rawWeek.clamp(1, totalWeeks);
    // 设置里的「显示周六、周日」：关闭后周视图只排周一到周五。
    final settings = ref.watch(settingsProvider).valueOrNull;
    final showWeekend = settings?.showWeekend ?? true;
    final holidays = settings?.holidays ?? const <Holiday>[];

    final dayCount = showWeekend ? 7 : 5;
    final holidayDays = <int>{
      for (var day = 1; day <= dayCount; day++)
        if (holidayForDate(
              holidays,
              dateOfWeekDay(timetable.semester.startMonday, week, day),
            ) !=
            null)
          day,
    };

    // 今天所处的教学周：优先用 academicWeekProvider，异常值（0/越界）时按日期现算。
    var thisWeek = academicWeek;
    if (thisWeek < 1 || thisWeek > totalWeeks) {
      thisWeek = weekOfDate(DateTime.now(), timetable.semester.startMonday);
    }
    if (thisWeek < 1 || thisWeek > totalWeeks) thisWeek = 1;

    final now = DateTime.now();
    final canGoBack = week != thisWeek;
    final canUndoDescription = ref.watch(undoDescriptionProvider).valueOrNull;
    final canRedoDescription = ref.watch(redoDescriptionProvider);
    final canUndo = canUndoDescription != null;
    final canRedo = canRedoDescription != null;
    final undoDetail = (canUndoDescription ?? '').trim();
    final redoDetail = (canRedoDescription ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 92,
        titleSpacing: 16,
        title: InkWell(
          key: const Key('timetable_week_title'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pickWeek(context, ref, week, totalWeeks),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '第 $week 周',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${now.year}/${now.month}/${now.day}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // 回到本周放在顶栏；添加课程收进更多菜单。
          IconButton(
            key: const Key('timetable_this_week'),
            tooltip: '回到本周',
            icon: const Icon(Icons.today_outlined),
            onPressed: canGoBack
                ? () => ref
                    .read(currentWeekProvider.notifier)
                    .setWeek(thisWeek)
                : null,
          ),
          IconButton(
            key: const Key('timetable_undo_button'),
            tooltip: undoDetail.isEmpty ? '撤销上一步' : '撤销：$undoDetail',
            icon: const Icon(Icons.undo),
            onPressed: canUndo ? () => _undo(context, ref) : null,
          ),
          IconButton(
            key: const Key('timetable_redo_button'),
            tooltip: redoDetail.isEmpty ? '重做' : '重做：$redoDetail',
            icon: const Icon(Icons.redo),
            onPressed: canRedo ? () => _redo(context, ref) : null,
          ),
          IconButton(
            key: const Key('timetable_more_button'),
            tooltip: '更多',
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _openMoreSheet(
              context,
              ref,
              week: week,
              totalWeeks: totalWeeks,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: timetable.courses.isEmpty
          ? const _EmptyState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 600;
                final isWide = constraints.maxWidth >= 900;

                // 手机竖屏：默认让 7 天（隐藏周末时 5 天）**一屏放下**，不横向滑动。
                // 列宽 = (可用宽度 - 时间轴) / 天数；窄屏时间轴收窄到 46、时间分两行显示
                // （08:00 / 08:45），把宽度让给课程列。
                // 只有屏幕窄到列宽低于 [minColumnWidth] 时才退化为横向滚动。
                final axisWidth = isNarrow ? 46.0 : 64.0;
                const minColumnWidth = 42.0;
                var columnWidth = (constraints.maxWidth - axisWidth) / dayCount;
                final needHorizontalScroll = columnWidth < minColumnWidth;
                if (needHorizontalScroll) columnWidth = minColumnWidth;

                Widget grid = WeekGrid(
                  timetable: timetable,
                  week: week,
                  today: now,
                  showWeekend: showWeekend,
                  holidayDays: holidayDays,
                  minRowHeight: 54,
                  timeAxisWidth: axisWidth,
                  onTap: (course, session) => _showCourseSheet(
                    context,
                    course,
                    session,
                    timetable.slotsForWeek(week),
                  ),
                  onLongPress: (course, session) =>
                      _openCourseEditor(context, course),
                  onBlankRangeSelected: (day, start, end) =>
                      _openNewCourseAt(context, day, start, end),
                  onPeriodsChanged: (course, session, start, end, day) =>
                      _changeSessionPeriods(
                        context,
                        ref,
                        course,
                        session,
                        start,
                        end,
                        day,
                      ),
                );

                // 切周时让整块课表做一个轻量的横向滑入 + 淡入动效。
                grid = _WeekSwitcher(week: week, child: grid);

                // 手机/桌面一屏放下 7 天时，左右划动切换周次；窄到需要横向滚动时
                // 优先保留网格自身的横向滚动，不抢手势。
                if (!needHorizontalScroll) {
                  grid = GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity.abs() < 220) return;
                      final notifier = ref.read(currentWeekProvider.notifier);
                      if (velocity > 0) {
                        if (week > 1) notifier.previous();
                      } else {
                        if (week < totalWeeks) notifier.next();
                      }
                    },
                    child: grid,
                  );
                }

                if (isNarrow && needHorizontalScroll) {
                  grid = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: axisWidth + dayCount * columnWidth,
                      height: constraints.maxHeight.isFinite
                          ? constraints.maxHeight
                          : null,
                      child: grid,
                    ),
                  );
                }

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: grid),
                      VerticalDivider(
                        width: 1,
                        thickness: 0.6,
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withAlpha(120),
                      ),
                      SizedBox(
                        width: 300,
                        child: _DayPanel(
                          timetable: timetable,
                          week: week,
                          weekday: now.weekday,
                          holidayName: holidayForDate(
                            holidays,
                            dateOfWeekDay(
                              timetable.semester.startMonday,
                              week,
                              now.weekday,
                            ),
                          )?.name,
                          onTap: (course, session) => _showCourseSheet(
                            context,
                            course,
                            session,
                            timetable.slotsForWeek(week),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return grid;
              },
            ),
    );
  }

  /// 点标题选择周次（参考移动端课表的「点周次切换」）。
  Future<void> _pickWeek(
    BuildContext context,
    WidgetRef ref,
    int current,
    int totalWeeks,
  ) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Text(
                    '切换周次',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '共 $totalWeeks 周',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: totalWeeks,
                itemBuilder: (context, index) {
                  final week = index + 1;
                  return ListTile(
                    key: Key('week_picker_$week'),
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('$week'),
                    ),
                    title: Text('第 $week 周'),
                    trailing: week == current
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(ctx).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(week),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) {
      ref.read(currentWeekProvider.notifier).setWeek(picked);
    }
  }

  Future<void> _openMoreSheet(
    BuildContext context,
    WidgetRef ref, {
    required int week,
    required int totalWeeks,
  }) async {
    final action = await showModalBottomSheet<_TimetableMenuAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        Widget item({
          required Key key,
          required IconData icon,
          required String title,
          required _TimetableMenuAction value,
          bool enabled = true,
        }) {
          return ListTile(
            key: key,
            enabled: enabled,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(
              icon,
              color: enabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(title),
            onTap: enabled ? () => Navigator.of(ctx).pop(value) : null,
          );
        }

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  '更多',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.onAddRequested != null)
                item(
                  key: const Key('timetable_add_button'),
                  icon: Icons.add_circle_outline,
                  title: '添加课程',
                  value: _TimetableMenuAction.add,
                ),
              item(
                key: const Key('timetable_batch_button'),
                icon: Icons.checklist_outlined,
                title: '批量修改',
                value: _TimetableMenuAction.batch,
              ),
              item(
                key: const Key('timetable_share_button'),
                icon: Icons.ios_share,
                title: '分享课表',
                value: _TimetableMenuAction.share,
              ),
              item(
                key: const Key('timetable_data_button'),
                icon: Icons.file_download_outlined,
                title: '导入 / 导出数据',
                value: _TimetableMenuAction.data,
              ),
              item(
                key: const Key('timetable_tutorial_button'),
                icon: Icons.restart_alt,
                title: '重启教程',
                value: _TimetableMenuAction.tutorial,
              ),
              const Divider(height: 12),
              item(
                key: const Key('timetable_prev_week'),
                icon: Icons.chevron_left,
                title: '上一周',
                value: _TimetableMenuAction.previousWeek,
                enabled: week > 1,
              ),
              item(
                key: const Key('timetable_next_week'),
                icon: Icons.chevron_right,
                title: '下一周',
                value: _TimetableMenuAction.nextWeek,
                enabled: week < totalWeeks,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action != null && context.mounted) {
      _onMenuAction(context, ref, action);
    }
  }

  void _onMenuAction(
    BuildContext context,
    WidgetRef ref,
    _TimetableMenuAction action,
  ) {
    switch (action) {
      case _TimetableMenuAction.add:
        widget.onAddRequested?.call();
      case _TimetableMenuAction.batch:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const BatchOpsPage()),
        );
      case _TimetableMenuAction.share:
        _openShareSheet(context, ref);
      case _TimetableMenuAction.data:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DataSettingsPage()),
        );
      case _TimetableMenuAction.tutorial:
        _openTutorial();
      case _TimetableMenuAction.previousWeek:
        ref.read(currentWeekProvider.notifier).previous();
      case _TimetableMenuAction.nextWeek:
        ref.read(currentWeekProvider.notifier).next();
    }
  }

  /// Word 式撤销：只回退上一步，不弹出历史列表。
  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(timetableProvider.notifier);
    final detail = (await controller.nextUndoDescription())?.trim() ?? '';
    final ok = await controller.undoLatestChange();
    if (!context.mounted) return;
    showAppNotice(
      context,
      ok
          ? (detail.isEmpty ? '已撤销上一步' : '已撤销：$detail')
          : '没有可撤销的更改',
    );
  }

  /// Word 式重做：恢复上一次撤销。
  Future<void> _redo(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(timetableProvider.notifier);
    final detail = (controller.redoDescription ?? '').trim();
    final ok = await controller.redoLastChange();
    if (!context.mounted) return;
    showAppNotice(
      context,
      ok
          ? (detail.isEmpty ? '已重做' : '已重做：$detail')
          : '没有可重做的操作',
    );
  }

  /// 长按课程：打开编辑页手动修改课程信息。
  /// 分享当前课表：日历文件（.ics）或完整 JSON 数据文件。
  Future<void> _openTutorial() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OnboardingWizardPage(replay: true),
      ),
    );
  }

  Future<void> _openShareSheet(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('分享日历文件（.ics）'),
              subtitle: const Text('导入手机/电脑日历，按日期显示每次课'),
              key: const Key('share_ics_option'),
              onTap: () => Navigator.pop(ctx, 'ics'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('分享 JSON 文件'),
              subtitle: const Text('完整课表数据，可备份或再次导入'),
              key: const Key('share_json_option'),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    final holidays = ref.read(settingsProvider).valueOrNull?.holidays ?? const <Holiday>[];
    const service = TimetableShareService();
    try {
      if (action == 'ics') {
        await service.shareIcs(widget.timetable, holidays: holidays);
      } else {
        await service.shareJson(widget.timetable);
      }
    } catch (e) {
      if (!context.mounted) return;
      showAppNotice(context, '分享失败：$e');
    }
  }

  Future<void> _openCourseEditor(BuildContext context, Course course) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CourseEditorPage(course: course)),
    );
    if (result == true && context.mounted) {
      showAppNotice(context, '课程已更新');
    }
  }

  /// 长按课表空白处：打开新增课程页，并预填点击的星期与节次。
  Future<void> _openNewCourseAt(
    BuildContext context,
    int dayOfWeek,
    int startPeriod,
    int endPeriod,
  ) async {
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => CourseEditorPage(
          initialDayOfWeek: dayOfWeek,
          initialPeriod: startPeriod,
          initialEndPeriod: endPeriod,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.045),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (result == true && context.mounted) {
      showAppNotice(context, '课程已添加');
    }
  }

  /// 拖动课程后调整它占用的节次与星期（同一周内可自由拖到任意一天）。
  Future<void> _changeSessionPeriods(
    BuildContext context,
    WidgetRef ref,
    Course course,
    Session session,
    int startPeriod,
    int endPeriod,
    int dayOfWeek,
  ) async {
    if (startPeriod == session.startPeriod &&
        endPeriod == session.endPeriod &&
        dayOfWeek == session.dayOfWeek) {
      return;
    }
    final sessions = <Session>[
      for (final s in course.sessions)
        s.id == session.id
            ? s.copyWith(
                dayOfWeek: dayOfWeek,
                startPeriod: startPeriod,
                endPeriod: endPeriod,
              )
            : s,
    ];
    await ref
        .read(timetableProvider.notifier)
        .updateCourse(course.copyWith(sessions: sessions));
    if (!context.mounted) return;
    final label = startPeriod == endPeriod
        ? '第$startPeriod节'
        : '第$startPeriod-$endPeriod节';
    final dayLabel = '周${weekdayShortNames[dayOfWeek - 1]}';
    showAppNotice(
      context,
      '已把「${course.name}」调整到$dayLabel $label',
    );
  }

}

/// 课程详情弹层。
void _showCourseSheet(
  BuildContext context,
  Course course,
  Session session,
  List<TimeSlot> slots,
) {
  final theme = Theme.of(context);
  final background = CoursePalette.of(course.colorIndex);
  final teacher = (session.teacher ?? course.teacher ?? '').trim();
  final location = (session.location ?? '').trim();
  final weeks = formatWeeks(session.weeks);
  final slotByPeriod = <int, TimeSlot>{
    for (final slot in slots) slot.period: slot,
  };
  final startSlot = slotByPeriod[session.startPeriod];
  final endSlot = slotByPeriod[session.endPeriod];
  final timeRange = startSlot != null && endSlot != null
      ? '${startSlot.start}-${endSlot.end}'
      : '';
  final periodLabel = session.startPeriod == session.endPeriod
      ? '第${session.startPeriod}节'
      : '第${session.startPeriod}-${session.endPeriod}节';

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    course.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.schedule,
              label: '节次',
              value: timeRange.isEmpty ? periodLabel : '$periodLabel · $timeRange',
            ),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: '时间',
              value: weeks.isEmpty
                  ? '${weekdayName(session.dayOfWeek)} · 未设置周次'
                  : '${weekdayName(session.dayOfWeek)} · $weeks',
            ),
            if (location.isNotEmpty)
              _InfoRow(
                icon: Icons.place_outlined,
                label: '地点',
                value: location,
              ),
            if (teacher.isNotEmpty)
              _InfoRow(
                icon: Icons.person_outline,
                label: '教师',
                value: teacher,
              ),
            if (course.courseCode != null && course.courseCode!.isNotEmpty)
              _InfoRow(
                icon: Icons.tag,
                label: '课程号',
                value: course.courseCode!,
              ),
            if (course.credit != null)
              _InfoRow(
                icon: Icons.workspace_premium_outlined,
                label: '学分',
                value: '${course.credit}',
              ),
            if (course.note != null && course.note!.isNotEmpty)
              _InfoRow(
                icon: Icons.notes_outlined,
                label: '备注',
                value: course.note!,
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WeekSwitcher extends StatefulWidget {
  const _WeekSwitcher({required this.week, required this.child});

  final int week;
  final Widget child;

  @override
  State<_WeekSwitcher> createState() => _WeekSwitcherState();
}

class _WeekSwitcherState extends State<_WeekSwitcher> {
  int _direction = 1;

  @override
  void didUpdateWidget(covariant _WeekSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.week != oldWidget.week) {
      _direction = widget.week > oldWidget.week ? 1 : -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(widget.week);
        final begin = incoming
            ? Offset(0.12 * _direction, 0)
            : Offset(-0.12 * _direction, 0);
        return SlideTransition(
          position: Tween<Offset>(begin: begin, end: Offset.zero)
              .animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(widget.week),
        child: widget.child,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// 宽屏右侧的「当日课程」栏。
class _DayPanel extends StatelessWidget {
  const _DayPanel({
    required this.timetable,
    required this.week,
    required this.weekday,
    this.holidayName,
    required this.onTap,
  });

  final Timetable timetable;
  final int week;
  final int weekday;

  /// 当日如果是节假日，显示节日名称并隐藏课程。
  final String? holidayName;
  final void Function(Course, Session) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = timetable.entriesAt(week, weekday);
    final date = dateOfWeekDay(timetable.semester.startMonday, week, weekday);
    final holiday = holidayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${weekdayName(weekday)} · 第 $week 周',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${date.month}月${date.day}日',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                holiday == null ? '${entries.length} 门' : '节假日',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: holiday != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.celebration_outlined,
                          color: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          holiday,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '今天不上课',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '这一天没有课',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: entries.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _DayTile(
                          entry: entry,
                          onTap: () => onTap(entry.course, entry.session),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.entry, required this.onTap});

  final SessionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = entry.session;
    final location = (session.location ?? '').trim();
    final color = CoursePalette.of(entry.course.colorIndex);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.course.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '第${session.startPeriod}-${session.endPeriod}节'
                        '${location.isEmpty ? '' : ' · $location'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 64,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '还没有课程',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '点顶栏的「添加」开始排课：\n'
                '可以手动添加，或让 AI 从课表截图识别。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // 纯提示，不放按钮 —— 添加入口在顶栏
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.north_east,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '顶栏「添加」',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              '课表加载失败',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
