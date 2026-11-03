import '../../core/utils/week_utils.dart';
import '../../data/models/draft.dart';

/// 按图片日期过滤后的结果。
class ImageDateFilterResult {
  final List<DraftCourse> courses;
  final List<String> warnings;

  const ImageDateFilterResult({required this.courses, this.warnings = const []});
}

/// 当图片是「单日课表」时，只保留该日期当天的课程，并把周次限定到日期所在周。
///
/// [semesterStartMonday] 是当前学期的第 1 周周一；[totalWeeks] 用于判断日期是否在学期内。
ImageDateFilterResult filterDraftsByImageDate({
  required List<DraftCourse> courses,
  required DateTime? date,
  required DateTime semesterStartMonday,
  required int totalWeeks,
}) {
  if (date == null) {
    return ImageDateFilterResult(courses: courses);
  }

  final weekday = date.weekday;
  final week = weekOfDate(date, semesterStartMonday);
  final inTerm = week >= 1 && week <= (totalWeeks < 1 ? 16 : totalWeeks);
  final kept = <DraftCourse>[];
  var droppedCourses = 0;

  for (final course in courses) {
    final matching = course.sessions
        .where((s) => s.dayOfWeek == weekday)
        .toList();
    if (matching.isEmpty) {
      droppedCourses++;
      continue;
    }
    final normalized = [
      for (final s in matching)
        DraftSession(
          dayOfWeek: weekday,
          startPeriod: s.startPeriod,
          endPeriod: s.endPeriod,
          weeks: inTerm ? [week] : s.weeks,
          location: s.location,
          teacher: s.teacher,
        ),
    ];
    kept.add(course.copyWith(sessions: normalized));
  }

  String dateLabel(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  final warnings = <String>[
    '图片日期为 ${dateLabel(date)}（${weekdayName(weekday)}），'
        '${inTerm ? '已只保留当天课程并限定到第 $week 周' : '已只保留当天课程'}。',
    if (droppedCourses > 0) '已忽略 $droppedCourses 门不在该日期的课程。',
    if (!inTerm) '该日期不在当前学期范围内，周次保留原样，请在导入前核对。',
  ];

  return ImageDateFilterResult(courses: kept, warnings: warnings);
}
