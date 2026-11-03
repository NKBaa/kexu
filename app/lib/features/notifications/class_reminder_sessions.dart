/// 上课提醒的「计划生成」层：纯函数 + 一个同步入口。
///
/// 这里刻意把「算哪些课要提醒」与「怎么通知」拆开：
/// - [buildReminderSessions] 是纯函数，输入课表 + 设置 + 当前时间，
///   输出未来 7 天要提醒的课程列表，便于单元测试；
/// - [syncFromTimetable] 负责把结果交给 [ClassReminderService]。
///
/// 通知是否真的能弹出来取决于系统（尤其国产 ROM 的通知/自启动策略），
/// 这里只保证「该提醒的课都排上了」，不承诺一定以厂商卡片展示。
library;

import '../../core/utils/holiday_utils.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/semester.dart';
import '../../data/models/timetable.dart';
import 'class_reminder_service.dart';

/// 提醒计划的覆盖天数（含今天）。
const int classReminderHorizonDays = 7;

/// 生成未来 7 天的上课提醒列表（纯函数）。
///
/// 规则：
/// - 从 [now] 当天开始，逐天看 7 天（今天 + 之后 6 天）；
/// - 跳过节假日（[AppSettings.holidays] 里出现的日期整天不提醒）；
/// - 跳过不在学期周次范围内的日期；
/// - 每节课按当天的作息方案换算起止时间；
/// - **提醒时间已过去的不再安排**（例如 10:00 打开 App 时，
///   8:00 的课不会再补一条通知），避免一打开就收到一堆过期提醒。
///
/// 返回的每项包含：`date`（yyyy-MM-dd）、`start`（HH:mm）、
/// `end`（HH:mm）、`name`、`location`，并按日期、开始时间升序排列。
List<Map<String, dynamic>> buildReminderSessions(
  Timetable timetable,
  AppSettings settings,
  DateTime now,
) {
  final today = dateOnly(now);
  final minutes = AppSettings.normalizeReminderMinutes(settings.reminderMinutes);
  final out = <Map<String, dynamic>>[];

  for (var offset = 0; offset < classReminderHorizonDays; offset++) {
    final date = addDays(today, offset);
    if (isHolidayDate(settings.holidays, date)) continue;

    final week = weekOfDate(date, timetable.semester.startMonday);
    if (week < 1 || week > timetable.semester.totalWeeks) continue;

    final slots = timetable.slotsForDate(date);
    final entries = timetable.entriesAt(week, date.weekday);
    for (final entry in entries) {
      final startSlot = _slotOf(slots, entry.session.startPeriod);
      if (startSlot == null) continue;
      final endSlot = _slotOf(slots, entry.session.endPeriod) ?? startSlot;

      final startAt = _combine(date, startSlot.start);
      if (startAt == null) continue;
      // 提醒时刻必须还在未来，否则这条提醒没有意义。
      if (!startAt.subtract(Duration(minutes: minutes)).isAfter(now)) continue;

      out.add({
        'date': formatDateKey(date),
        'start': startSlot.start,
        'end': endSlot.end,
        'name': entry.course.name,
        'location': entry.session.location ?? '',
      });
    }
  }

  out.sort((a, b) {
    final byDate = (a['date'] as String).compareTo(b['date'] as String);
    if (byDate != 0) return byDate;
    return (a['start'] as String).compareTo(b['start'] as String);
  });
  return out;
}

/// 把当前课表 + 设置同步到原生排程器。
///
/// 关闭提醒时等价于 [ClassReminderService.cancelAll]。
/// 可重复调用（原生侧会先取消旧闹钟再重排），适合在课表/设置变化后调用。
Future<void> syncFromTimetable(
  Timetable timetable,
  AppSettings settings, {
  DateTime? now,
  ClassReminderService? service,
}) async {
  final reminderService = service ?? ClassReminderService();
  if (!settings.classReminderEnabled) {
    await reminderService.cancelAll();
    return;
  }
  final sessions = buildReminderSessions(
    timetable,
    settings,
    now ?? DateTime.now(),
  );
  await reminderService.syncSchedule(
    sessions,
    reminderMinutes: AppSettings.normalizeReminderMinutes(settings.reminderMinutes),
    style: AppSettings.normalizeNotificationStyle(settings.notificationStyle),
  );
}

TimeSlot? _slotOf(List<TimeSlot> slots, int period) {
  for (final slot in slots) {
    if (slot.period == period) return slot;
  }
  return null;
}

DateTime? _combine(DateTime date, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0].trim());
  final minute = int.tryParse(parts[1].trim());
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}
