import 'dart:convert';

import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/holiday.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/timetable/timetable_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable _timetable() {
  return Timetable(
    semester: Semester(
      id: 's1',
      name: '2026 秋季学期',
      startMonday: DateTime(2026, 9, 7),
      totalWeeks: 16,
    ),
    courses: [
      Course(
        id: 'c1',
        semesterId: 's1',
        name: '高等数学',
        teacher: '张老师',
        sessions: [
          Session(
            id: 'ss1',
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: const [1, 2],
            location: 'A101',
          ),
        ],
      ),
    ],
  );
}

void main() {
  const service = TimetableShareService();

  test('日历文件包含课程、时间、地点与唯一 UID', () {
    final ics = service.buildIcs(_timetable(), now: DateTime(2026, 9, 1, 10));
    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('BEGIN:VEVENT'));
    expect(ics, contains('SUMMARY:高等数学'));
    expect(ics, contains('LOCATION:A101'));
    expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260907T080000'));
    expect(ics, contains('DTEND;TZID=Asia/Shanghai:20260907T094000'));
    expect(ics, contains('kexu-c1-ss1-2026-09-07@kexu'));
    expect(ics, contains('kexu-c1-ss1-2026-09-14@kexu'));
    expect(ics, contains('END:VCALENDAR'));
  });

  test('节假日当天的课不写入日历', () {
    final ics = service.buildIcs(
      _timetable(),
      holidays: [
        Holiday(id: 'h1', date: DateTime(2026, 9, 7), name: '校运会'),
      ],
      now: DateTime(2026, 9, 1, 10),
    );
    expect(ics, isNot(contains('20260907T080000')));
    // 第 2 周不受影响
    expect(ics, contains('20260914T080000'));
  });

  test('JSON 导出可被课表模型重新解析', () {
    final json = service.buildJson(_timetable());
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final restored = Timetable.fromJson(decoded);
    expect(restored.semester.name, '2026 秋季学期');
    expect(restored.courses.single.name, '高等数学');
    expect(restored.courses.single.sessions.single.weeks, [1, 2]);
  });

  test('日历文本使用 CRLF 并折叠超长行', () {
    final ics = service.buildIcs(_timetable(), now: DateTime(2026, 9, 1, 10));
    expect(ics, contains('\r\n'));
    final longLine = ics
        .split('\r\n')
        .where((line) => line.isNotEmpty)
        .any((line) => utf8.encode(line).length > 75);
    expect(longLine, isFalse);
  });
}
