import '../../core/utils/ids.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/week_utils.dart';

/// 调课类型。
///
/// 大学里「不规律」的另一大来源就是临时调整，因此这里显式建模：
/// - [move]：某次课换时间/换教室（原日期 -> 新日期）
/// - [cancel]：某次课停上（如放假、老师出差）
/// - [add]：额外补课（原课表里没有的一次）
enum AdjustmentType { move, cancel, add }

AdjustmentType adjustmentTypeFromString(String? s) {
  switch ((s ?? '').toLowerCase().trim()) {
    case 'cancel':
    case '停课':
    case '取消':
      return AdjustmentType.cancel;
    case 'add':
    case '补课':
    case '加课':
      return AdjustmentType.add;
    case 'move':
    case 'swap':
    case '调课':
    case '调整':
    default:
      return AdjustmentType.move;
  }
}

/// 一次性的课表调整记录。
class Adjustment {
  final String id;
  final AdjustmentType type;

  /// 原定上课日期（[AdjustmentType.add] 时可为空）。
  final DateTime? fromDate;

  /// 调整后的上课日期（[AdjustmentType.cancel] 时可为空）。
  final DateTime? toDate;

  /// 调整后的节次区间（为空表示沿用原节次）。
  final int? startPeriod;
  final int? endPeriod;

  /// 调整后的地点（为空表示沿用原地点）。
  final String? location;

  final String? note;

  const Adjustment({
    required this.id,
    required this.type,
    this.fromDate,
    this.toDate,
    this.startPeriod,
    this.endPeriod,
    this.location,
    this.note,
  });

  Adjustment copyWith({
    AdjustmentType? type,
    DateTime? fromDate,
    DateTime? toDate,
    int? startPeriod,
    int? endPeriod,
    String? location,
    String? note,
  }) =>
      Adjustment(
        id: id,
        type: type ?? this.type,
        fromDate: fromDate ?? this.fromDate,
        toDate: toDate ?? this.toDate,
        startPeriod: startPeriod ?? this.startPeriod,
        endPeriod: endPeriod ?? this.endPeriod,
        location: location ?? this.location,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'fromDate': fromDate?.toIso8601String(),
        'toDate': toDate?.toIso8601String(),
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'location': location,
        'note': note,
      };

  static Adjustment fromJson(Map<String, dynamic> j) => Adjustment(
        id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
        type: adjustmentTypeFromString(asString(j['type'])),
        fromDate: DateTime.tryParse(asString(j['fromDate'])),
        toDate: DateTime.tryParse(asString(j['toDate'])),
        startPeriod: asInt(j['startPeriod']),
        endPeriod: asInt(j['endPeriod']),
        location: asString(j['location']).isEmpty ? null : asString(j['location']),
        note: asString(j['note']).isEmpty ? null : asString(j['note']),
      );

  String describe() {
    String d(DateTime? x) => x == null ? '—' : '${x.month}/${x.day}';
    switch (type) {
      case AdjustmentType.cancel:
        return '停课：${d(fromDate)}${note == null ? '' : '（$note）'}';
      case AdjustmentType.add:
        return '补课：${d(toDate)}${location == null ? '' : ' @$location'}';
      case AdjustmentType.move:
        return '调课：${d(fromDate)} → ${d(toDate)}${location == null ? '' : ' @$location'}';
    }
  }
}

/// 一门课的一个上课时段。
///
/// 「一门课多个时段」是刚需（比如周一 1-2 节 + 周三 5-6 节），
/// 而 [weeks] 用显式列表表达，因此「3-5 周和 7-9 周上课、6 周不上」
/// 这种真正不规律的安排也能精确表示。
class Session {
  final String id;

  /// 1=周一 … 7=周日。
  final int dayOfWeek;

  /// 起始节次（从 1 开始）。
  final int startPeriod;

  /// 结束节次（含）。
  final int endPeriod;

  /// 生效周次，如 `[1,3,5,7]`。
  final List<int> weeks;

  final String? location;

  /// 该时段单独的教师（为空则用课程默认教师）。
  final String? teacher;

  const Session({
    required this.id,
    required this.dayOfWeek,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.location,
    this.teacher,
  });

  Session copyWith({
    int? dayOfWeek,
    int? startPeriod,
    int? endPeriod,
    List<int>? weeks,
    String? location,
    String? teacher,
    bool clearLocation = false,
    bool clearTeacher = false,
  }) =>
      Session(
        id: id,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startPeriod: startPeriod ?? this.startPeriod,
        endPeriod: endPeriod ?? this.endPeriod,
        weeks: weeks ?? this.weeks,
        location: clearLocation ? null : (location ?? this.location),
        teacher: clearTeacher ? null : (teacher ?? this.teacher),
      );

  /// 覆盖的节次数（用于课表网格中纵向跨行）。
  int get span => (endPeriod - startPeriod).abs() + 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayOfWeek': dayOfWeek,
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'weeks': weeks,
        'location': location,
        'teacher': teacher,
      };

  static Session fromJson(Map<String, dynamic> j) {
    final p = normalizePeriods(asInt(j['startPeriod']) ?? 1, asInt(j['endPeriod']) ?? 1);
    return Session(
      id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
      dayOfWeek: (asInt(j['dayOfWeek']) ?? 1).clamp(1, 7),
      startPeriod: p.start,
      endPeriod: p.end,
      weeks: asList(j['weeks']).map(asInt).whereType<int>().toList()..sort(),
      location: asString(j['location']).isEmpty ? null : asString(j['location']),
      teacher: asString(j['teacher']).isEmpty ? null : asString(j['teacher']),
    );
  }

  /// 展示用，如 `周一 1-2节 1-16周(单) @A101`。
  String describe() {
    final buf = StringBuffer()
      ..write(weekdayName(dayOfWeek))
      ..write(' ')
      ..write(startPeriod == endPeriod ? '第$startPeriod节' : '第$startPeriod-$endPeriod节');
    if (weeks.isNotEmpty) buf.write(' ${formatWeeks(weeks)}');
    if (location != null && location!.isNotEmpty) buf.write(' @$location');
    return buf.toString();
  }
}

/// 一门课程。
class Course {
  final String id;
  final String semesterId;
  final String name;
  final String? teacher;
  final String? courseCode;
  final double? credit;
  final String? note;

  /// 颜色索引，对应主题调色板。
  final int colorIndex;

  /// 该课程的所有上课时段。
  final List<Session> sessions;

  /// 针对该课程的一次性调整（调课/停课/补课）。
  final List<Adjustment> adjustments;

  const Course({
    required this.id,
    required this.semesterId,
    required this.name,
    this.teacher,
    this.courseCode,
    this.credit,
    this.note,
    this.colorIndex = 0,
    this.sessions = const [],
    this.adjustments = const [],
  });

  Course copyWith({
    String? name,
    String? teacher,
    String? courseCode,
    double? credit,
    String? note,
    int? colorIndex,
    List<Session>? sessions,
    List<Adjustment>? adjustments,
    bool clearTeacher = false,
    bool clearNote = false,
  }) =>
      Course(
        id: id,
        semesterId: semesterId,
        name: name ?? this.name,
        teacher: clearTeacher ? null : (teacher ?? this.teacher),
        courseCode: courseCode ?? this.courseCode,
        credit: credit ?? this.credit,
        note: clearNote ? null : (note ?? this.note),
        colorIndex: colorIndex ?? this.colorIndex,
        sessions: sessions ?? this.sessions,
        adjustments: adjustments ?? this.adjustments,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'semesterId': semesterId,
        'name': name,
        'teacher': teacher,
        'courseCode': courseCode,
        'credit': credit,
        'note': note,
        'colorIndex': colorIndex,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'adjustments': adjustments.map((a) => a.toJson()).toList(),
      };

  static Course fromJson(Map<String, dynamic> j) => Course(
        id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
        semesterId: asString(j['semesterId']),
        name: asString(j['name'], fallback: '未命名课程'),
        teacher: asString(j['teacher']).isEmpty ? null : asString(j['teacher']),
        courseCode: asString(j['courseCode']).isEmpty ? null : asString(j['courseCode']),
        credit: asDouble(j['credit']),
        note: asString(j['note']).isEmpty ? null : asString(j['note']),
        colorIndex: asInt(j['colorIndex']) ?? 0,
        sessions: asList(j['sessions'])
            .map((e) => Session.fromJson(asMap(e)))
            .toList(growable: true),
        adjustments: asList(j['adjustments'])
            .map((e) => Adjustment.fromJson(asMap(e)))
            .toList(growable: true),
      );

  /// 汇总展示，如 `高等数学（张老师）`。
  String get displayName =>
      teacher == null || teacher!.isEmpty ? name : '$name（$teacher）';
}
