import 'package:course_timetable/data/models/bell_schedule.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/ai/now_context.dart';
import 'package:flutter_test/flutter_test.dart';

Semester _semester({int totalWeeks = 16}) => Semester(
      id: 's1',
      name: '2025 秋季学期',
      startMonday: DateTime(2025, 9, 1),
      totalWeeks: totalWeeks,
    );

Timetable _timetable({List<BellSchedule>? schedules}) => Timetable(
      semester: _semester(),
      schedules: schedules,
      timeSlots: defaultTimeSlots(),
    );

void main() {
  group('NowContext 教学周计算', () {
    test('学期内：按 weekOfDate 算出当前教学周与下一周', () {
      // 2025-09-01 是第 1 周周一，09-17 是第 3 周周三。
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 9, 17, 14, 30),
      );
      expect(ctx.academicWeek, 3);
      expect(ctx.totalWeeks, 16);
      expect(ctx.inSemester, isTrue);
      expect(ctx.nextAcademicWeek, 4);
      expect(ctx.weekMonday, DateTime(2025, 9, 15));
      expect(ctx.dateOfThisWeek(1), DateTime(2025, 9, 15));
      expect(ctx.dateOfThisWeek(7), DateTime(2025, 9, 21));
    });

    test('周日也属于当前教学周（dayOfWeek=7）', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 9, 21, 9),
      );
      expect(ctx.academicWeek, 3);
      expect(ctx.weekdayLabel, '周日');
      expect(ctx.nextAcademicWeek, 4);
      // 周日之后是第 4 周周一
      expect(ctx.nextWeekMonday, DateTime(2025, 9, 22));
    });

    test('学期还没开始时返回 0，并给出下一教学周 = 第 1 周', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 8, 25, 10),
      );
      expect(ctx.academicWeek, 0);
      expect(ctx.inSemester, isFalse);
      expect(ctx.nextAcademicWeek, 1);
      expect(ctx.toPromptText(), contains('学期还没开始'));
    });

    test('学期已结束时返回 0，且没有下一教学周', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2026, 2, 1, 10),
      );
      expect(ctx.academicWeek, 0);
      expect(ctx.inSemester, isFalse);
      expect(ctx.nextAcademicWeek, 0);
      expect(ctx.toPromptText(), contains('学期已结束'));
    });

    test('最后一周没有下一教学周', () {
      // 第 16 周周一是 2025-12-15。
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 12, 18, 10),
      );
      expect(ctx.academicWeek, 16);
      expect(ctx.nextAcademicWeek, 0);
      expect(ctx.toPromptText(), contains('本周是学期最后一周'));
    });
  });

  group('NowContext.toPromptText', () {
    test('包含当前日期时间、教学周、本周日期与下一教学周', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 9, 17, 14, 30),
      );
      final text = ctx.toPromptText();

      expect(text, contains('现在的时间上下文'));
      expect(text, contains('当前日期时间：2025-09-17 14:30（周三）'));
      expect(text, contains('当前教学周：第 3 周（学期共 16 周）'));
      expect(text, contains('本周每天对应日期：'));
      expect(text, contains('周一 2025-09-15'));
      expect(text, contains('周三 2025-09-17'));
      expect(text, contains('周日 2025-09-21'));
      expect(text, contains('下一教学周：第 4 周（2025-09-22 起）'));
      expect(text, contains('明天 / 后天：周四 2025-09-18（第 3 周）；周五 2025-09-19（第 3 周）'));
    });

    test('包含今天各节次起止时间', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 9, 17, 8),
      );
      final text = ctx.toPromptText();
      expect(text, contains('今天各节次时间：'));
      expect(text, contains('第1节 08:00-08:45'));
      expect(text, contains('第5节 14:00-14:45'));
      expect(text, contains('第12节 21:45-22:30'));
    });

    test('按当天作息把上午/下午/晚上映射到节次', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2025, 9, 17, 8),
      );
      final text = ctx.toPromptText();
      expect(text, contains('「上午」指第1-4节（08:00 开始）'));
      expect(text, contains('「下午」指第5-8节（14:00 开始）'));
      expect(text, contains('「晚上」指第9-12节（19:00 开始）'));
    });

    test('slots 使用当天生效的作息方案（夏季/冬季作息不同）', () {
      final summer = BellSchedule(
        id: 'summer',
        name: '夏季作息',
        startDate: DateTime(2025, 9, 1),
        endDate: DateTime(2025, 9, 30),
        slots: const [
          TimeSlot(period: 1, start: '08:30', end: '09:15'),
          TimeSlot(period: 5, start: '14:30', end: '15:15'),
        ],
      );
      final winter = BellSchedule(
        id: 'winter',
        name: '冬季作息',
        slots: const [
          TimeSlot(period: 1, start: '08:00', end: '08:45'),
          TimeSlot(period: 5, start: '14:00', end: '14:45'),
        ],
      );

      final inSummer = NowContext.fromTimetable(
        _timetable(schedules: [summer, winter]),
        now: DateTime(2025, 9, 17, 8),
      );
      expect(inSummer.slots.first.start, '08:30');
      expect(inSummer.toPromptText(), contains('第1节 08:30-09:15'));

      final inWinter = NowContext.fromTimetable(
        _timetable(schedules: [summer, winter]),
        now: DateTime(2025, 11, 5, 8),
      );
      expect(inWinter.slots.first.start, '08:00');
      expect(inWinter.toPromptText(), contains('第1节 08:00-08:45'));
    });

    test('学期外仍然给出本周日期，但教学周说明不在学期内', () {
      final ctx = NowContext.fromTimetable(
        _timetable(),
        now: DateTime(2026, 2, 1, 10),
      );
      final text = ctx.toPromptText();
      expect(text, contains('本周每天对应日期：'));
      expect(text, contains('当前教学周：不在学期内'));
      expect(text, contains('下一教学周：没有'));
    });
  });
}
