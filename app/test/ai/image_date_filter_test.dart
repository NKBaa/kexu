import 'package:course_timetable/data/models/draft.dart';
import 'package:course_timetable/features/ai/image_date_filter.dart';
import 'package:course_timetable/features/ai/image_to_timetable.dart';
import 'package:flutter_test/flutter_test.dart';

DraftSession _session(int day, int start, int end, {List<int>? weeks}) => DraftSession(
      dayOfWeek: day,
      startPeriod: start,
      endPeriod: end,
      weeks: weeks ?? const [1, 2, 3],
    );

void main() {
  test('从模型顶层 JSON 解析单日课表日期', () {
    final date = ImageToTimetableService.parseImageDate(
      '{"date":"2026-11-02","courses":[]}',
    );
    expect(date, isNotNull);
    expect(date!.year, 2026);
    expect(date.month, 11);
    expect(date.day, 2);
  });

  test('整周课表没有 date 时不当作单日课表', () {
    expect(
      ImageToTimetableService.parseImageDate('{"courses":[]}'),
      isNull,
    );
  });

  test('单日课表只保留该日期课程，并把周次限定到该周', () {
    final result = filterDraftsByImageDate(
      date: DateTime(2026, 11, 4), // 周三
      semesterStartMonday: DateTime(2026, 9, 7),
      totalWeeks: 16,
      courses: [
        DraftCourse(
          name: '高等数学',
          sessions: [
            _session(1, 1, 2),
            _session(3, 5, 6),
          ],
        ),
        DraftCourse(name: '大学英语', sessions: [_session(3, 7, 8)]),
        DraftCourse(name: '体育', sessions: [_session(4, 1, 2)]),
      ],
    );

    expect(result.courses.map((c) => c.name), ['高等数学', '大学英语']);
    expect(result.courses.first.sessions, hasLength(1));
    expect(result.courses.first.sessions.first.dayOfWeek, 3);
    expect(result.courses.first.sessions.first.weeks, [9]);
    expect(result.warnings.join(), contains('已忽略 1 门'));
  });

  test('没有日期时保持原识别结果', () {
    final courses = [
      DraftCourse(name: '高等数学', sessions: [_session(1, 1, 2)]),
    ];
    final result = filterDraftsByImageDate(
      date: null,
      semesterStartMonday: DateTime(2026, 9, 7),
      totalWeeks: 16,
      courses: courses,
    );
    expect(result.courses, same(courses));
    expect(result.warnings, isEmpty);
  });
}
