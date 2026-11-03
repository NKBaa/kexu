import 'package:course_timetable/data/models/bell_schedule.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:flutter_test/flutter_test.dart';

List<TimeSlot> slotSet(int count, {String start = '08:00'}) => [
      for (var i = 1; i <= count; i++) TimeSlot(period: i, start: start, end: '08:45'),
    ];

BellSchedule summer() => BellSchedule(
      id: 'summer',
      name: '夏季作息',
      slots: slotSet(12, start: '14:30'),
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 9, 30),
    );

BellSchedule winter() => BellSchedule(
      id: 'winter',
      name: '冬季作息',
      slots: slotSet(10, start: '14:00'),
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2027, 4, 30),
    );

Semester sem() => Semester(
      id: 's',
      name: '2026-2027 学年',
      startMonday: DateTime(2026, 2, 23),
      totalWeeks: 20,
    );

void main() {
  group('BellSchedule 生效判断', () {
    test('常驻方案：任何日期都生效', () {
      final always = BellSchedule(id: 'a', name: '常驻', slots: slotSet(12));
      expect(always.isAlwaysOn, isTrue);
      expect(always.appliesOn(DateTime(2020, 1, 1)), isTrue);
      expect(always.appliesOn(DateTime(2030, 12, 31)), isTrue);
    });
    test('限定区间：区间外不生效', () {
      final s = summer();
      expect(s.appliesOn(DateTime(2026, 4, 30)), isFalse);
      expect(s.appliesOn(DateTime(2026, 5, 1)), isTrue, reason: '起始当天生效');
      expect(s.appliesOn(DateTime(2026, 9, 30)), isTrue, reason: '结束当天生效');
      expect(s.appliesOn(DateTime(2026, 10, 1)), isFalse);
    });

    test('只给起始日期：从这天起一直生效', () {
      final s = BellSchedule(
        id: 'x',
        name: '从十月起',
        slots: slotSet(10),
        startDate: DateTime(2026, 10, 1),
      );
      expect(s.appliesOn(DateTime(2026, 9, 30)), isFalse);
      expect(s.appliesOn(DateTime(2027, 6, 1)), isTrue);
    });

    test('区间描述可读', () {
      expect(summer().rangeLabel, '05-01 ~ 09-30');
      expect(
        BellSchedule(id: 'a', name: 'n', slots: slotSet(2)).rangeLabel,
        '不限日期',
      );
    });
  });

  group('resolveScheduleFor 选择生效方案', () {
    test('按日期选中对应方案', () {
      final list = [summer(), winter()];
      expect(resolveScheduleFor(list, DateTime(2026, 6, 1))!.name, '夏季作息');
      expect(resolveScheduleFor(list, DateTime(2026, 12, 1))!.name, '冬季作息');
    });

    test('限定日期的方案优先于常驻方案', () {
      final fallback = BellSchedule(id: 'd', name: '默认', slots: slotSet(12));
      final list = [fallback, summer()]; // 常驻排在前面也应被专用方案覆盖
      expect(resolveScheduleFor(list, DateTime(2026, 6, 1))!.name, '夏季作息');
    });

    test('都不命中时回退到常驻方案', () {
      final fallback = BellSchedule(id: 'd', name: '默认', slots: slotSet(12));
      final list = [summer(), fallback];
      // 2026-03-01 不在夏季区间内
      expect(resolveScheduleFor(list, DateTime(2026, 3, 1))!.name, '默认');
    });

    test('没有任何常驻方案且都不命中时，回退到第一个', () {
      final list = [summer(), winter()];
      // 2027-06-01 两套都不在区间内
      final r = resolveScheduleFor(list, DateTime(2027, 6, 1));
      expect(r, isNotNull);
      expect(r!.name, '夏季作息');
    });

    test('空列表返回 null', () {
      expect(resolveScheduleFor(const [], DateTime(2026, 1, 1)), isNull);
    });
  });

  group('Timetable 多套作息', () {
    Timetable withSchedules() => Timetable(
          semester: sem(),
          schedules: [summer(), winter()],
          courses: const [
            Course(
              id: 'c1',
              semesterId: 's',
              name: '高等数学',
              sessions: [
                Session(
                  id: 'x',
                  dayOfWeek: 1,
                  startPeriod: 1,
                  endPeriod: 2,
                  weeks: [1, 2, 3],
                ),
              ],
            ),
          ],
        );

    test('slotsForDate 按日期返回对应作息', () {
      final t = withSchedules();
      expect(t.slotsForDate(DateTime(2026, 6, 1)).first.start, '14:30');
      expect(t.slotsForDate(DateTime(2026, 12, 1)).first.start, '14:00');
    });

    test('slotsForWeek 按该周周一的日期判定', () {
      final t = withSchedules();
      // 第 15 周周一 = 2026-02-23 + 14*7 = 2026-06-01 → 落在夏季区间
      expect(t.slotsForWeek(15).first.start, '14:30');
    });

    test('周次日期不落在任何区间时，回退到第一套（不会没作息可用）', () {
      final t = withSchedules();
      // 第 1 周周一 = 2026-02-23，既不在夏季(05-01~)也不在冬季(10-01~)区间
      expect(t.slotsForWeek(1).first.start, '14:30', reason: '回退到第一套方案');
    });

    test('学期起始在冬季区间内时，第 1 周用冬季作息', () {
      final t = Timetable(
        semester: Semester(
          id: 's2',
          name: '秋季学期',
          startMonday: DateTime(2026, 10, 5), // 落在冬季区间 10-01~2027-04-30
          totalWeeks: 20,
        ),
        schedules: [summer(), winter()],
      );
      expect(t.slotsForWeek(1).first.start, '14:00');
    });

    test('maxPeriod 取所有方案的最大节次（不只看第一套）', () {
      final t = Timetable(
        semester: sem(),
        schedules: [
          BellSchedule(id: 'a', name: '少', slots: slotSet(8)),
          BellSchedule(id: 'b', name: '多', slots: slotSet(14)),
        ],
      );
      expect(t.maxPeriod, 14);
    });

    test('作息只有 11 节且课程不到 12 节时，不额外补第 12 行', () {
      final t = Timetable(
        semester: sem(),
        schedules: [BellSchedule(id: 'a', name: '十一节', slots: slotSet(11))],
      );
      expect(t.maxPeriod, 11);
    });

    test('activeSchedule 依据今天', () {
      final t = withSchedules();
      final active = t.activeSchedule;
      expect(['夏季作息', '冬季作息'], contains(active.name));
    });
  });

  group('JSON 序列化与向后兼容', () {
    test('多套作息可往返', () {
      final t = Timetable(
        semester: sem(),
        schedules: [summer(), winter()],
      );
      final back = Timetable.fromJson(t.toJson());

      expect(back.schedules.length, 2);
      expect(back.schedules.map((s) => s.name), containsAll(['夏季作息', '冬季作息']));
      final s = back.schedules.firstWhere((x) => x.name == '夏季作息');
      expect(s.startDate, DateTime(2026, 5, 1));
      expect(s.endDate, DateTime(2026, 9, 30));
      expect(s.slots.length, 12);
    });

    test('旧数据（只有 timeSlots）能自动升级为单套作息', () {
      final legacy = {
        'version': 1,
        'semester': sem().toJson(),
        'timeSlots': slotSet(12).map((s) => s.toJson()).toList(),
        'courses': <Map<String, dynamic>>[],
      };

      final t = Timetable.fromJson(legacy);
      expect(t.schedules.length, 1, reason: '旧格式应升级为一套作息');
      expect(t.schedules.single.slots.length, 12);
      expect(t.schedules.single.isAlwaysOn, isTrue);
      expect(t.timeSlots.length, 12, reason: '旧接口仍应可读');
    });

    test('兼容构造：直接传 timeSlots 等价于一套常驻作息', () {
      final t = Timetable(semester: sem(), timeSlots: slotSet(9));
      expect(t.schedules.length, 1);
      expect(t.schedules.single.isAlwaysOn, isTrue);
      expect(t.timeSlots.length, 9);
    });

    test('copyWith(timeSlots:) 只改第一套，其余方案保留', () {
      final t = Timetable(semester: sem(), schedules: [summer(), winter()]);
      final next = t.copyWith(timeSlots: slotSet(6));

      expect(next.schedules.length, 2);
      expect(next.schedules.first.slots.length, 6);
      expect(next.schedules.last.slots.length, 10, reason: '第二套不应被改动');
    });

    test('导出仍写出 timeSlots 以兼容旧版本', () {
      final t = Timetable(semester: sem(), schedules: [summer(), winter()]);
      final json = t.toJson();
      expect(json['schedules'], isNotNull);
      expect(json['timeSlots'], isNotNull, reason: '旧版 App 需要读到一份作息');
    });
  });
}
