import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/bell_schedule.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/holiday.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/widget/timetable_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2025-09-01 是周一，作为第 1 周；2025-09-17 是第 3 周周三。
Semester _semester({int totalWeeks = 16}) => Semester(
      id: 's1',
      name: '2025 秋季学期',
      startMonday: DateTime(2025, 9, 1),
      totalWeeks: totalWeeks,
    );

Session _session({
  required int dayOfWeek,
  required int startPeriod,
  required int endPeriod,
  required List<int> weeks,
  String? location,
  String? teacher,
}) =>
    Session(
      id: 'session-$dayOfWeek-$startPeriod',
      dayOfWeek: dayOfWeek,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      weeks: weeks,
      location: location,
      teacher: teacher,
    );

Course _course({
  required String name,
  required Session session,
  String? teacher,
}) =>
    Course(
      id: name,
      semesterId: 's1',
      name: name,
      teacher: teacher,
      sessions: [session],
    );

Timetable _timetable({List<Course> courses = const []}) => Timetable(
      semester: _semester(),
      courses: courses,
      timeSlots: defaultTimeSlots(),
    );

List<Map<String, dynamic>> _sessionsOf(Map<String, dynamic> snapshot) =>
    (snapshot['sessions'] as List).cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildWidgetSnapshot 今日课程', () {
    final timetable = _timetable(
      courses: [
        // 第 3 周周三第 1-2 节（08:00-09:40）
        _course(
          name: '大学物理',
          session: _session(
            dayOfWeek: 3,
            startPeriod: 1,
            endPeriod: 2,
            weeks: const [3],
            location: 'B202',
          ),
        ),
        // 第 3 周周三第 3-4 节（10:00-11:40），带时段级教师
        _course(
          name: '高等数学',
          session: _session(
            dayOfWeek: 3,
            startPeriod: 3,
            endPeriod: 4,
            weeks: const [3],
            location: 'A101',
            teacher: '张老师',
          ),
        ),
      ],
    );

    test('生成日期/星期/教学周，并按开始时间排序', () {
      final snapshot = buildWidgetSnapshot(
        timetable,
        const AppSettings(),
        DateTime(2025, 9, 17, 10, 0),
      );

      expect(snapshot['date'], '2025-09-17');
      expect(snapshot['weekday'], '周三');
      expect(snapshot['week'], 3);
      expect(snapshot['holiday'], isNull);
      expect(snapshot['updatedAt'], '2025-09-17T10:00:00.000');

      final sessions = _sessionsOf(snapshot);
      expect(sessions.length, 2);
      expect(sessions[0]['name'], '大学物理');
      expect(sessions[0]['start'], '08:00');
      expect(sessions[0]['end'], '09:40');
      expect(sessions[0]['location'], 'B202');
      expect(sessions[0]['teacher'], isNull);
      expect(sessions[0]['isNow'], isFalse);

      expect(sessions[1]['name'], '高等数学');
      expect(sessions[1]['start'], '10:00');
      expect(sessions[1]['end'], '11:40');
      expect(sessions[1]['location'], 'A101');
      expect(sessions[1]['teacher'], '张老师');
      // 10:00 正好是第 3 节开始，左闭右开 → 正在上课
      expect(sessions[1]['isNow'], isTrue);
    });

    test('课程级教师作为时段教师的兜底', () {
      final snapshot = buildWidgetSnapshot(
        _timetable(
          courses: [
            _course(
              name: '大学英语',
              teacher: '李老师',
              session: _session(
                dayOfWeek: 3,
                startPeriod: 1,
                endPeriod: 2,
                weeks: const [3],
              ),
            ),
          ],
        ),
        const AppSettings(),
        DateTime(2025, 9, 17, 8, 0),
      );
      expect(_sessionsOf(snapshot).single['teacher'], '李老师');
      expect(_sessionsOf(snapshot).single['isNow'], isTrue);
    });

    test('不在学期内（学期已结束）时 week=0 且没有课程', () {
      final snapshot = buildWidgetSnapshot(
        timetable,
        const AppSettings(),
        DateTime(2026, 2, 1, 10),
      );

      expect(snapshot['date'], '2026-02-01');
      expect(snapshot['weekday'], '周日');
      expect(snapshot['week'], 0);
      expect(_sessionsOf(snapshot), isEmpty);
    });

    test('没有课的日子 sessions 为空（原生据此显示空状态）', () {
      final snapshot = buildWidgetSnapshot(
        timetable,
        const AppSettings(),
        DateTime(2025, 9, 18, 10), // 周四，课表里没有课
      );
      expect(snapshot['week'], 3);
      expect(snapshot['weekday'], '周四');
      expect(_sessionsOf(snapshot), isEmpty);
    });

    test('显式传入 holiday 时写入快照', () {
      final snapshot = buildWidgetSnapshot(
        timetable,
        const AppSettings(),
        DateTime(2025, 9, 17, 10),
        holiday: '国庆节',
      );
      expect(snapshot['holiday'], '国庆节');
    });

    test('从设置的节假日列表里取当天节日名称', () {
      final settings = AppSettings(
        holidays: [
          Holiday(id: 'h1', date: DateTime(2025, 9, 17), name: '校运会'),
          Holiday(id: 'h2', date: DateTime(2025, 10, 1), name: '国庆节'),
        ],
      );
      final snapshot = buildWidgetSnapshot(
        timetable,
        settings,
        DateTime(2025, 9, 17, 10),
      );
      expect(snapshot['holiday'], '校运会');
    });

    test('节假日日期不匹配时 holiday 为 null', () {
      final settings = AppSettings(
        holidays: [Holiday(id: 'h2', date: DateTime(2025, 10, 1), name: '国庆节')],
      );
      final snapshot = buildWidgetSnapshot(
        timetable,
        settings,
        DateTime(2025, 9, 17, 10),
      );
      expect(snapshot['holiday'], isNull);
    });

    test('使用当天生效的作息方案计算起止时间', () {
      final summer = BellSchedule(
        id: 'summer',
        name: '夏季作息',
        startDate: DateTime(2025, 9, 1),
        endDate: DateTime(2025, 9, 30),
        slots: const [
          TimeSlot(period: 1, start: '08:30', end: '09:15'),
          TimeSlot(period: 2, start: '09:25', end: '10:10'),
        ],
      );
      final winter = BellSchedule(
        id: 'winter',
        name: '冬季作息',
        slots: const [
          TimeSlot(period: 1, start: '08:00', end: '08:45'),
          TimeSlot(period: 2, start: '08:55', end: '09:40'),
        ],
      );
      final timetableWithSchedules = Timetable(
        semester: _semester(),
        schedules: [summer, winter],
        courses: [
          _course(
            name: '高等数学',
            session: _session(
              dayOfWeek: 3,
              startPeriod: 1,
              endPeriod: 2,
              weeks: const [3, 6],
            ),
          ),
        ],
      );

      final inSummer = buildWidgetSnapshot(
        timetableWithSchedules,
        const AppSettings(),
        DateTime(2025, 9, 17, 8, 30),
      );
      expect(_sessionsOf(inSummer).single['start'], '08:30');
      expect(_sessionsOf(inSummer).single['end'], '10:10');
      expect(_sessionsOf(inSummer).single['isNow'], isTrue);

      // 第 6 周周三（2025-10-08）落在 10 月，改用冬季作息
      final inWinter = buildWidgetSnapshot(
        timetableWithSchedules,
        const AppSettings(),
        DateTime(2025, 10, 8, 8, 30),
      );
      expect(_sessionsOf(inWinter).single['start'], '08:00');
      expect(_sessionsOf(inWinter).single['end'], '09:40');
      expect(_sessionsOf(inWinter).single['isNow'], isTrue);
    });
  });

  group('isSessionOngoing 边界', () {
    test('左闭右开：开始时刻算上课中，结束时刻不算', () {
      expect(isSessionOngoing('08:00', '09:40', DateTime(2025, 9, 17, 8, 0)),
          isTrue);
      expect(isSessionOngoing('08:00', '09:40', DateTime(2025, 9, 17, 9, 39)),
          isTrue);
      expect(isSessionOngoing('08:00', '09:40', DateTime(2025, 9, 17, 9, 40)),
          isFalse);
      expect(isSessionOngoing('08:00', '09:40', DateTime(2025, 9, 17, 7, 59)),
          isFalse);
    });

    test('时间缺失或非法时不高亮', () {
      final now = DateTime(2025, 9, 17, 8, 0);
      expect(isSessionOngoing('', '', now), isFalse);
      expect(isSessionOngoing('08:00', '', now), isFalse);
      expect(isSessionOngoing('25:00', '26:00', now), isFalse);
      expect(isSessionOngoing('10:00', '09:00', now), isFalse);
    });

    test('minutesOfDay 解析 HH:mm', () {
      expect(minutesOfDay('08:00'), 480);
      expect(minutesOfDay('23:59'), 23 * 60 + 59);
      expect(minutesOfDay(null), isNull);
      expect(minutesOfDay('8'), isNull);
    });
  });

  group('TimetableWidgetService 通道调用', () {
    const channel = MethodChannel(timetableWidgetChannelName);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('updateWidget 把快照原样传给原生并返回 true', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });

      final snapshot = <String, dynamic>{
        'date': '2025-09-17',
        'weekday': '周三',
        'week': 3,
        'holiday': null,
        'sessions': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': '高等数学',
            'start': '10:00',
            'end': '11:40',
            'location': 'A101',
            'teacher': '张老师',
            'isNow': true,
          },
        ],
        'updatedAt': '2025-09-17T10:00:00.000',
      };

      final ok = await TimetableWidgetService(isAndroid: true)
          .updateWidget(snapshot);

      expect(ok, isTrue);
      expect(received?.method, 'updateWidget');
      expect(received?.arguments, snapshot);
    });

    test('isSupported 透传原生结果', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isSupported');
        return true;
      });

      expect(await TimetableWidgetService(isAndroid: true).isSupported(),
          isTrue);
    });

    test('原生抛 PlatformException 时返回 false，不向上抛', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'WIDGET_UPDATE_FAILED', message: 'boom');
      });

      final service = TimetableWidgetService(isAndroid: true);
      expect(await service.updateWidget(<String, dynamic>{}), isFalse);
      expect(await service.isSupported(), isFalse);
    });

    test('通道未注册（MissingPluginException）时返回 false', () async {
      final service = TimetableWidgetService(isAndroid: true);
      expect(await service.updateWidget(<String, dynamic>{}), isFalse);
      expect(await service.isSupported(), isFalse);
    });

    test('非 Android 平台不调用通道，直接返回 false', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return true;
      });

      final service = TimetableWidgetService(isAndroid: false);
      expect(service.isSupportedPlatform, isFalse);
      expect(await service.updateWidget(<String, dynamic>{}), isFalse);
      expect(await service.isSupported(), isFalse);
      expect(called, isFalse);
    });

    test('updateFromTimetable 用生成的快照调用通道', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        received = call;
        return true;
      });

      final timetable = _timetable(
        courses: [
          _course(
            name: '大学物理',
            session: _session(
              dayOfWeek: 3,
              startPeriod: 1,
              endPeriod: 2,
              weeks: const [3],
              location: 'B202',
            ),
          ),
        ],
      );

      final ok = await TimetableWidgetService(isAndroid: true)
          .updateFromTimetable(
        timetable,
        const AppSettings(),
        now: DateTime(2025, 9, 17, 8, 30),
      );

      expect(ok, isTrue);
      final args = received?.arguments as Map<Object?, Object?>?;
      expect(args?['date'], '2025-09-17');
      expect(args?['week'], 3);
      final sessions = (args?['sessions'] as List?)?.cast<Map<Object?, Object?>>();
      expect(sessions?.single['name'], '大学物理');
      expect(sessions?.single['isNow'], isTrue);
    });
  });
}
