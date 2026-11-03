import '../../data/models/course.dart';
import '../../data/models/draft.dart';

/// 课程名归一化：忽略首尾空格、大小写、中间空白、零宽字符，
/// 并把全角括号统一成半角，用于判断「是否已导入」。
String normalizeCourseName(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u200B\u200C\u200D\uFEFF]+'), '')
    .replaceAll('（', '(')
    .replaceAll('）', ')');

/// 已导入课程名集合（用于草稿列表标记与批量导入判断）。
Set<String> existingCourseNameKeys(Iterable<Course> courses) =>
    {for (final c in courses) normalizeCourseName(c.name)};

/// 合并同名导入课程，避免一次识别/导入产生两门同名课程。
///
/// 同名课程会合并成一个 [Course]：保留第一条的元信息，时段取并集。
/// 这样即使用户勾选了识别结果里的重复条目，覆盖导入后也只会剩一门课。
List<Course> mergeIncomingCourses(List<Course> courses) {
  final byName = <String, Course>{};
  for (final course in courses) {
    final key = normalizeCourseName(course.name);
    final previous = byName[key];
    if (previous == null) {
      byName[key] = course;
      continue;
    }
    final sessions = <Session>[...previous.sessions];
    for (final session in course.sessions) {
      final exists = sessions.any((s) => _sameSession(s, session));
      if (!exists) sessions.add(session);
    }
    byName[key] = previous.copyWith(
      teacher: _nonEmpty(previous.teacher) ? previous.teacher : course.teacher,
      courseCode:
          _nonEmpty(previous.courseCode) ? previous.courseCode : course.courseCode,
      credit: previous.credit ?? course.credit,
      note: _nonEmpty(previous.note) ? previous.note : course.note,
      sessions: sessions,
    );
  }
  return byName.values.toList(growable: false);
}

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

bool _sameSession(Session a, Session b) =>
    a.dayOfWeek == b.dayOfWeek &&
    a.startPeriod == b.startPeriod &&
    a.endPeriod == b.endPeriod &&
    a.weeks.join(',') == b.weeks.join(',');

/// 覆盖导入：移除与 [incoming] 同名的已有课程，再追加新课程。
List<Course> overwriteCoursesByName({
  required List<Course> existing,
  required List<Course> incoming,
}) {
  final merged = mergeIncomingCourses(incoming);
  final incomingNames = existingCourseNameKeys(merged);
  final kept = existing
      .where((c) => !incomingNames.contains(normalizeCourseName(c.name)))
      .toList();
  return [...kept, ...merged];
}

/// 当前勾选的草稿中，哪些下标与已有课程重名。
List<int> duplicateDraftIndices({
  required List<DraftCourse> drafts,
  required Set<int> selected,
  required Iterable<Course> existingCourses,
}) {
  final existing = existingCourseNameKeys(existingCourses);
  return [
    for (var i = 0; i < drafts.length; i++)
      if (selected.contains(i) && existing.contains(normalizeCourseName(drafts[i].name)))
        i,
  ];
}
