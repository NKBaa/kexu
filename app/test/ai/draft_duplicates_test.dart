import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/draft.dart';
import 'package:course_timetable/features/ai/draft_duplicates.dart';
import 'package:flutter_test/flutter_test.dart';

DraftCourse _draft(String name) => DraftCourse(name: name);

Course _course(String name) => Course(
      id: name,
      semesterId: 's1',
      name: name,
    );

void main() {
  test('课程名归一化忽略空格与大小写', () {
    expect(normalizeCourseName(' 高等数学 '), '高等数学');
    expect(normalizeCourseName('Data  Structure'), 'datastructure');
    expect(normalizeCourseName('高等数学（上）'), normalizeCourseName('高等数学(上)'));
    expect(normalizeCourseName('高\u200B等数学'), '高等数学');
  });

  test('同名导入课程会合并为一门，时段取并集', () {
    final merged = mergeIncomingCourses([
      Course(
        id: 'a',
        semesterId: 's1',
        name: '高等数学',
        teacher: '张老师',
        sessions: const [
          Session(
            id: 's1',
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: [1, 2, 3],
          ),
        ],
      ),
      Course(
        id: 'b',
        semesterId: 's1',
        name: '高等数学',
        sessions: const [
          Session(
            id: 's2',
            dayOfWeek: 3,
            startPeriod: 5,
            endPeriod: 6,
            weeks: [1, 2, 3],
          ),
          Session(
            id: 's3',
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: [1, 2, 3],
          ),
        ],
      ),
    ]);

    expect(merged, hasLength(1));
    expect(merged.single.teacher, '张老师');
    expect(merged.single.sessions, hasLength(2));
    expect(merged.single.sessions.map((s) => s.dayOfWeek), containsAll([1, 3]));
  });

  test('覆盖导入会移除同名旧课程，只保留新课程', () {
    final existing = [
      _course('高等数学(上)'),
      _course('线性代数'),
    ];
    final incoming = [
      _course('高等数学（上）'),
    ];

    final result = overwriteCoursesByName(
      existing: existing,
      incoming: incoming,
    );

    expect(result, hasLength(2));
    expect(result.map((c) => c.name), containsAll(['高等数学（上）', '线性代数']));
    // 半角/全角括号按同一门课处理，不会留下重复的「高等数学（上）」。
    expect(result.where((c) => c.name.contains('高等数学')), hasLength(1));
  });

  test('只标记勾选且与已有课程重名的草稿', () {
    final drafts = [
      _draft('高等数学'),
      _draft('数据结构'),
      _draft('大学英语'),
    ];
    final existing = [_course('高等数学'), _course('Data Structure')];

    expect(
      duplicateDraftIndices(
        drafts: drafts,
        selected: {0, 1, 2},
        existingCourses: existing,
      ),
      [0],
    );
    expect(
      duplicateDraftIndices(
        drafts: drafts,
        selected: {1},
        existingCourses: existing,
      ),
      isEmpty,
    );
  });
}
