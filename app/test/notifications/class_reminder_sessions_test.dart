import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/holiday.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/notifications/class_reminder_service.dart';
import 'package:course_timetable/features/notifications/class_reminder_sessions.dart';
import 'package:flutter_test/flutter_test.dart';

/// 提醒计划生成（纯函数）与同步入口的单元测试。
///
/// 时间基准：2026-09-07 是周一（第 1 周周一）。
void main() {
  Timetable buildTimetable() => Timetable(
        semester: Semester(
          id: 's1',
          name: '2026 秋季学期',
          startMonday: DateTime(2026, 9, 7),
          totalWeeks: 16,
        ),
        timeSlots: defaultTimeSlots(),
        courses: [
          Course(
            id: 'c1',
            semesterId: 's1',
            name: '高等数学',
            sessions: [
              Session(
                id: 'x1',
                dayOfWeek: DateTime.monday,
                startPeriod: 1,
                endPeriod: 2,
                weeks: List<int>.generate(16, (i) => i + 1),
                location: 'A101',
              ),
            ],
          ),
          Course(
            id: 'c2',
            semesterId: 's1',
            name: '大学英语',
            sessions: [
              Session(
                id: 'x2',
                dayOfWeek: DateTime.wednesday,
                startPeriod: 3,
                endPeriod: 4,
                weeks: List<int>.generate(16, (i) => i + 1),
                location: 'B202',
              ),
            ],
          ),
        ],
      );

  test('生成未来 7 天的提醒，字段完整且按日期时间排序', () {
    final sessions = buildReminderSessions(
      buildTimetable(),
      const AppSettings(classReminderEnabled: true),
      DateTime(2026, 9, 7, 7, 0),
    );

    expect(sessions.length, 2);
    expect(sessions.first, {
      'date': '2026-09-07',
      'start': '08:00',
      'end': '09:40',
      'name': '高等数学',
      'location': 'A101',
    });
    expect(sessions.last['date'], '2026-09-09');
    expect(sessions.last['start'], '10:00');
    expect(sessions.last['end'], '11:40');
    expect(sessions.last['name'], '大学英语');
    expect(sessions.last['location'], 'B202');
  });

  test('节假日当天整天不安排提醒', () {
    final settings = AppSettings(
      classReminderEnabled: true,
      holidays: [Holiday(id: 'h1', date: DateTime(2026, 9, 7), name: '校运会')],
    );
    final sessions = buildReminderSessions(
      buildTimetable(),
      settings,
      DateTime(2026, 9, 7, 7, 0),
    );
    expect(sessions.length, 1);
    expect(sessions.single['date'], '2026-09-09');
  });

  test('提醒时刻已经过去的课程不再排程', () {
    // 07:55 时，周一 08:00 的课「提前 10 分钟」应在 07:50 提醒，已过去；
    // 周三的课仍应保留。
    final sessions = buildReminderSessions(
      buildTimetable(),
      const AppSettings(classReminderEnabled: true),
      DateTime(2026, 9, 7, 7, 55),
    );
    expect(sessions.length, 1);
    expect(sessions.single['date'], '2026-09-09');
  });

  test('提前 30 分钟时更早的课会被判定为已过点', () {
    // 07:35 时，周一 08:00 提前 30 分钟 = 07:30，已过去。
    final sessions = buildReminderSessions(
      buildTimetable(),
      const AppSettings(classReminderEnabled: true, reminderMinutes: 30),
      DateTime(2026, 9, 7, 7, 35),
    );
    expect(sessions.length, 1);
    expect(sessions.single['date'], '2026-09-09');
  });

  test('不在学期周次范围内的日期不排程', () {
    // 2026-12-28 已经超过第 16 周。
    final sessions = buildReminderSessions(
      buildTimetable(),
      const AppSettings(classReminderEnabled: true),
      DateTime(2026, 12, 28, 7, 0),
    );
    expect(sessions, isEmpty);
  });

  test('课程周次不包含当前周时不提醒', () {
    final timetable = Timetable(
      semester: Semester(
        id: 's1',
        name: '2026 秋季学期',
        startMonday: DateTime(2026, 9, 7),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '只在第 2 周上的课',
          sessions: [
            Session(
              id: 'x1',
              dayOfWeek: DateTime.monday,
              startPeriod: 1,
              endPeriod: 2,
              weeks: const [2],
            ),
          ],
        ),
      ],
    );
    final sessions = buildReminderSessions(
      timetable,
      const AppSettings(classReminderEnabled: true),
      DateTime(2026, 9, 7, 7, 0),
    );
    expect(sessions, isEmpty);
  });

  test('关闭提醒时 syncFromTimetable 只取消，不排程', () async {
    final service = _FakeReminderService();
    await syncFromTimetable(
      buildTimetable(),
      const AppSettings(classReminderEnabled: false),
      now: DateTime(2026, 9, 7, 7, 0),
      service: service,
    );
    expect(service.cancelled, isTrue);
    expect(service.syncedSessions, isNull);
  });

  test('开启提醒时 syncFromTimetable 传入提醒分钟数与通知样式', () async {
    final service = _FakeReminderService();
    await syncFromTimetable(
      buildTimetable(),
      const AppSettings(
        classReminderEnabled: true,
        reminderMinutes: 15,
        notificationStyle: 'vendor',
      ),
      now: DateTime(2026, 9, 7, 7, 0),
      service: service,
    );
    expect(service.cancelled, isFalse);
    expect(service.syncedSessions, isNotNull);
    expect(service.syncedSessions!.length, 2);
    expect(service.syncedMinutes, 15);
    expect(service.syncedStyle, 'vendor');
  });
}

class _FakeReminderService extends ClassReminderService {
  bool cancelled = false;
  List<Map<String, dynamic>>? syncedSessions;
  int? syncedMinutes;
  String? syncedStyle;

  @override
  Future<bool> syncSchedule(
    List<Map<String, dynamic>> sessions, {
    required int reminderMinutes,
    required String style,
  }) async {
    syncedSessions = sessions;
    syncedMinutes = reminderMinutes;
    syncedStyle = style;
    return true;
  }

  @override
  Future<void> cancelAll() async {
    cancelled = true;
  }
}
