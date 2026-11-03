import '../../core/utils/ids.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/week_utils.dart';
import 'course.dart';

/// AI 图片转课表 / 自然语言改课表产出的「草稿」类型。
///
/// 设计要点：草稿**不是**持久化模型。AI 输出的所有内容先落成草稿，
/// 由用户在预览界面确认/勾选后再写入数据库。这样即使模型幻觉，
/// 也不会污染真实课表。草稿中还保留 [DraftCourse.warnings]，
/// 把「缺失字段、周次解析失败」等问题显式暴露给用户。

/// 按顺序返回第一个非空字符串。
String pickNonEmpty(List<String?> values) {
  for (final v in values) {
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

/// 草稿中的单个上课时段。
class DraftSession {
  /// 1=周一 … 7=周日。
  final int dayOfWeek;
  final int startPeriod;
  final int endPeriod;

  /// 显式周次列表。
  final List<int> weeks;

  final String? location;
  final String? teacher;

  const DraftSession({
    required this.dayOfWeek,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.location,
    this.teacher,
  });

  bool get isValid =>
      dayOfWeek >= 1 &&
      dayOfWeek <= 7 &&
      startPeriod >= 1 &&
      endPeriod >= startPeriod &&
      weeks.isNotEmpty;

  String describe() {
    final buf = StringBuffer()
      ..write(weekdayName(dayOfWeek))
      ..write(' ')
      ..write(startPeriod == endPeriod ? '第$startPeriod节' : '第$startPeriod-$endPeriod节');
    if (weeks.isNotEmpty) buf.write(' ${formatWeeks(weeks)}');
    if (location != null && location!.isNotEmpty) buf.write(' @$location');
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'dayOfWeek': dayOfWeek,
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'weeks': weeks,
        'location': location,
        'teacher': teacher,
      };

  /// 从 AI 返回的 JSON 解析；周次字段兼容 `weeks`/`weekRange`/`weekType` 等多种写法。
  ///
  /// [defaultWeeks] 用于模型没给周次时的回退（通常取学期全部周次）。
  static DraftSession fromAiJson(Map<String, dynamic> j, {List<int>? defaultWeeks}) {
    final startRaw = asInt(j['startPeriod']) ?? asInt(j['start']) ?? asInt(j['periodStart']) ?? 1;
    final endRaw = asInt(j['endPeriod']) ??
        asInt(j['end']) ??
        asInt(j['periodEnd']) ??
        asInt(j['startPeriod']) ??
        startRaw;
    final p = normalizePeriods(startRaw, endRaw);

    var weeks = <int>[];
    final rawWeeks = j['weeks'];
    if (rawWeeks is List) {
      weeks = rawWeeks
          .map(asInt)
          .whereType<int>()
          .where((w) => w > 0)
          .toSet()
          .toList()
        ..sort();
    }
    if (weeks.isEmpty) {
      final range = pickNonEmpty([asString(j['weekRange']), asString(j['weeks'])]);
      weeks = parseWeeks(range);
    }
    if (weeks.isEmpty) {
      final weekType = pickNonEmpty([asString(j['weekType']), asString(j['weekTypeText'])]);
      if (weekType.isNotEmpty) weeks = parseWeeks(weekType);
    }
    if (weeks.isEmpty && defaultWeeks != null) weeks = List<int>.from(defaultWeeks);

    return DraftSession(
      dayOfWeek: parseDayOfWeek(j['dayOfWeek'] ?? j['day'] ?? j['weekday']),
      startPeriod: p.start,
      endPeriod: p.end,
      weeks: weeks,
      location: pickNonEmpty([asString(j['location']), asString(j['place']), asString(j['classroom'])]),
      teacher: pickNonEmpty([asString(j['teacher']), asString(j['instructor'])]),
    );
  }
}

/// 兼容 `"周一"`/`"星期一"`/`"Mon"`/`1..7` 等多种星期写法。
int parseDayOfWeek(dynamic v) {
  if (v is int) return v.clamp(1, 7);
  final s = asString(v);
  if (s.isEmpty) return 1;

  // 纯数字（含 "3"、"第3天"）
  if (RegExp(r'^\s*\d+\s*$').hasMatch(s)) {
    final n = int.tryParse(s.trim());
    if (n != null) return n.clamp(1, 7);
  }

  const zh = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
  for (final e in zh.entries) {
    if (s.contains(e.key)) return e.value;
  }

  const en = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};
  final low = s.toLowerCase();
  for (final e in en.entries) {
    if (low.startsWith(e.key)) return e.value;
  }
  return 1;
}

/// 草稿课程。
class DraftCourse {
  final String name;
  final String? teacher;
  final String? courseCode;
  final double? credit;
  final String? note;
  final List<DraftSession> sessions;

  /// 解析过程中发现的问题（如「周次缺失，已按 1-16 周处理」）。
  final List<String> warnings;

  const DraftCourse({
    required this.name,
    this.teacher,
    this.courseCode,
    this.credit,
    this.note,
    this.sessions = const [],
    this.warnings = const [],
  });

  bool get isValid => name.trim().isNotEmpty && sessions.any((s) => s.isValid);

  DraftCourse copyWith({
    String? name,
    String? teacher,
    String? courseCode,
    double? credit,
    String? note,
    List<DraftSession>? sessions,
    List<String>? warnings,
  }) =>
      DraftCourse(
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        courseCode: courseCode ?? this.courseCode,
        credit: credit ?? this.credit,
        note: note ?? this.note,
        sessions: sessions ?? this.sessions,
        warnings: warnings ?? this.warnings,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'teacher': teacher,
        'courseCode': courseCode,
        'credit': credit,
        'note': note,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'warnings': warnings,
      };

  static DraftCourse fromAiJson(Map<String, dynamic> j, {List<int>? defaultWeeks}) {
    final warnings = <String>[];
    final name = pickNonEmpty([asString(j['name']), asString(j['courseName']), asString(j['course'])]);

    final sessions = <DraftSession>[];
    for (final raw in asList(j['sessions'])) {
      final ds = DraftSession.fromAiJson(asMap(raw), defaultWeeks: defaultWeeks);
      if (ds.isValid) {
        sessions.add(ds);
      } else {
        warnings.add('丢弃了一个无效时段（星期/节次/周次不完整）');
      }
    }

    // 兼容「课程对象直接带 day/period 字段」的扁平结构
    if (sessions.isEmpty && j.containsKey('dayOfWeek')) {
      final ds = DraftSession.fromAiJson(j, defaultWeeks: defaultWeeks);
      if (ds.isValid) {
        sessions.add(ds);
      } else {
        warnings.add('该课程未解析出有效上课时段');
      }
    }

    if (name.isEmpty) warnings.add('课程名缺失');
    if (sessions.isEmpty) warnings.add('没有解析到任何上课时段');

    return DraftCourse(
      name: name,
      teacher: _nullable(pickNonEmpty([asString(j['teacher']), asString(j['instructor'])])),
      courseCode: _nullable(pickNonEmpty([asString(j['courseCode']), asString(j['code'])])),
      credit: asDouble(j['credit']) ?? asDouble(j['credits']),
      note: _nullable(pickNonEmpty([asString(j['note']), asString(j['remark'])])),
      sessions: sessions,
      warnings: warnings,
    );
  }

  static String? _nullable(String s) => s.trim().isEmpty ? null : s.trim();
}

/// 把草稿课程转成真正的 [Course]。
Course draftToCourse(DraftCourse d, String semesterId, {int colorIndex = 0}) {
  return Course(
    id: newId(),
    semesterId: semesterId,
    name: d.name.trim(),
    teacher: d.teacher,
    courseCode: d.courseCode,
    credit: d.credit,
    note: d.note,
    colorIndex: colorIndex,
    sessions: d.sessions
        .where((s) => s.isValid)
        .map((s) => Session(
              id: newId(),
              dayOfWeek: s.dayOfWeek,
              startPeriod: s.startPeriod,
              endPeriod: s.endPeriod,
              weeks: s.weeks,
              location: s.location,
              teacher: s.teacher,
            ))
        .toList(),
  );
}
