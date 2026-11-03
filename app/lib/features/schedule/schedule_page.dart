import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/holiday_utils.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/holiday.dart';
import '../../data/models/semester.dart';
import '../../data/models/timetable.dart';
import '../editor/course_editor_page.dart';
import '../settings/providers/settings_provider.dart';
import '../timetable/providers/timetable_provider.dart';

/// 日程页：按天列出当前教学周的课程，适合快速看「今天/明天有什么课」。
class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timetableProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          IconButton(
            key: const Key('schedule_today_button'),
            tooltip: '回到本周',
            icon: const Icon(Icons.today_outlined),
            onPressed: () {
              final week = ref.read(academicWeekProvider);
              if (week >= 1) {
                ref.read(currentWeekProvider.notifier).setWeek(week);
              }
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('读取课表失败：$e')),
        data: (timetable) => _ScheduleBody(timetable: timetable),
      ),
    );
  }
}

class _ScheduleBody extends ConsumerWidget {
  const _ScheduleBody({required this.timetable});

  final Timetable timetable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final totalWeeks = timetable.semester.totalWeeks > 0
        ? timetable.semester.totalWeeks
        : 16;
    final week = ref.watch(currentWeekProvider).clamp(1, totalWeeks);
    final showWeekend = settings?.showWeekend ?? true;
    final holidays = settings?.holidays ?? const [];
    final dayCount = showWeekend ? 7 : 5;
    final today = DateTime.now();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _WeekHeader(
          week: week,
          totalWeeks: totalWeeks,
          onPrevious: week > 1
              ? () => ref.read(currentWeekProvider.notifier).previous()
              : null,
          onNext: week < totalWeeks
              ? () => ref.read(currentWeekProvider.notifier).next()
              : null,
        ),
        const SizedBox(height: 12),
        for (var day = 1; day <= dayCount; day++) ...[
          _buildDay(
            context,
            ref,
            timetable: timetable,
            week: week,
            day: day,
            date: dateOfWeekDay(timetable.semester.startMonday, week, day),
            holiday: holidayForDate(
              holidays,
              dateOfWeekDay(timetable.semester.startMonday, week, day),
            ),
            isToday: week == weekOfDate(today, timetable.semester.startMonday) &&
                day == today.weekday,
            slots: timetable.slotsForDate(
              dateOfWeekDay(timetable.semester.startMonday, week, day),
            ),
          ),
          if (day != dayCount) const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        Text(
          '日程只显示当前教学周；点课程可进入编辑页。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDay(
    BuildContext context,
    WidgetRef ref, {
    required Timetable timetable,
    required int week,
    required int day,
    required DateTime date,
    required Holiday? holiday,
    required bool isToday,
    required List<TimeSlot> slots,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = timetable.entriesAt(week, day);
    final slotByPeriod = {for (final s in slots) s.period: s};
    final isHoliday = holiday != null;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isToday ? scheme.primary : scheme.outlineVariant,
          width: isToday ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isToday
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.month}/${date.day}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isToday
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
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
                      Row(
                        children: [
                          Text(
                            weekdayName(day),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '今天',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        isHoliday
                            ? '节假日 · ${holiday.name}'
                            : '${entries.length} 个时段',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isHoliday
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isHoliday)
              Text(
                '放假，不排课。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else if (entries.isEmpty)
              Text(
                '没有课',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              for (final entry in entries) ...[
                _CourseRow(
                  entry: entry,
                  startSlot: slotByPeriod[entry.session.startPeriod],
                  endSlot: slotByPeriod[entry.session.endPeriod],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CourseEditorPage(course: entry.course),
                    ),
                  ),
                ),
                if (entry != entries.last) const Divider(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({
    required this.entry,
    required this.startSlot,
    required this.endSlot,
    required this.onTap,
  });

  final SessionEntry entry;
  final TimeSlot? startSlot;
  final TimeSlot? endSlot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = startSlot == null || endSlot == null
        ? '第 ${entry.session.startPeriod}-${entry.session.endPeriod} 节'
        : '${startSlot!.start}-${endSlot!.end}';
    final meta = [
      if (entry.course.teacher?.trim().isNotEmpty == true)
        entry.course.teacher!,
      if (entry.session.location?.trim().isNotEmpty == true)
        entry.session.location!,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(
                time,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.week,
    required this.totalWeeks,
    required this.onPrevious,
    required this.onNext,
  });

  final int week;
  final int totalWeeks;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              key: const Key('schedule_prev_week'),
              tooltip: '上一周',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '第 $week 周',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '共 $totalWeeks 周',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('schedule_next_week'),
              tooltip: '下一周',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
