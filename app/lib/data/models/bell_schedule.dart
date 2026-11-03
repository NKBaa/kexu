import 'semester.dart';

/// 一套作息方案（例如「夏季作息」「秋季作息」）。
///
/// 为什么需要「多套」：不少学校夏季与冬季的上课时间不同
/// （比如夏季下午 14:30 上课、冬季 14:00 上课）。如果只有一个全局作息，
/// 用户要么记错时间，要么每年手动改两次。
///
/// 这里用「生效日期区间」来描述切换规则：
/// - [startDate]/[endDate] 都为 null 表示**不限日期**（常驻方案）；
/// - 只给 startDate 表示「从这天起生效」；
/// - 两个都给表示「这段时间内生效」。
/// 判定时按列表顺序取第一个命中项，因此把「有日期的专用方案」排在
/// 「不限日期的默认方案」前面即可。
class BellSchedule {
  final String id;

  /// 展示名，如「夏季作息」「秋季作息」。
  final String name;

  /// 该方案下每节课的起止时间。
  final List<TimeSlot> slots;

  /// 生效起始日期（含当天）；null 表示不限。
  final DateTime? startDate;

  /// 生效结束日期（含当天）；null 表示不限。
  final DateTime? endDate;

  const BellSchedule({
    required this.id,
    required this.name,
    required this.slots,
    this.startDate,
    this.endDate,
  });

  /// 是否常驻（不限日期）。
  bool get isAlwaysOn => startDate == null && endDate == null;

  /// [date] 是否落在本方案的有效期内。
  bool appliesOn(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (startDate != null) {
      final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
      if (d.isBefore(s)) return false;
    }
    if (endDate != null) {
      final e = DateTime(endDate!.year, endDate!.month, endDate!.day);
      if (d.isAfter(e)) return false;
    }
    return true;
  }

  /// 生效区间的可读描述。
  String get rangeLabel {
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (isAlwaysOn) return '不限日期';
    if (startDate != null && endDate != null) {
      return '${fmt(startDate!)} ~ ${fmt(endDate!)}';
    }
    if (startDate != null) return '${fmt(startDate!)} 起';
    return '至 ${fmt(endDate!)}';
  }

  int get maxPeriod =>
      slots.isEmpty ? 12 : slots.map((s) => s.period).reduce((a, b) => a > b ? a : b);

  BellSchedule copyWith({
    String? name,
    List<TimeSlot>? slots,
    DateTime? startDate,
    DateTime? endDate,
    bool clearStart = false,
    bool clearEnd = false,
  }) =>
      BellSchedule(
        id: id,
        name: name ?? this.name,
        slots: slots ?? this.slots,
        startDate: clearStart ? null : (startDate ?? this.startDate),
        endDate: clearEnd ? null : (endDate ?? this.endDate),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slots': slots.map((s) => s.toJson()).toList(),
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
      };

  static BellSchedule fromJson(Map<String, dynamic> j) {
    List<TimeSlot> slots = (j['slots'] as List?)
            ?.map((e) => TimeSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        const <TimeSlot>[];
    if (slots.isEmpty) slots = defaultTimeSlots();
    return BellSchedule(
      id: (j['id'] ?? '').toString().isEmpty ? 'default' : j['id'].toString(),
      name: (j['name'] ?? '').toString().isEmpty ? '默认作息' : j['name'].toString(),
      slots: slots,
      startDate: DateTime.tryParse((j['startDate'] ?? '').toString()),
      endDate: DateTime.tryParse((j['endDate'] ?? '').toString()),
    );
  }
}

/// 在 [schedules] 中找出 [date] 当天生效的方案。
///
/// 顺序语义：按列表顺序取第一个命中的方案，因此「限定日期的方案」应排在前面。
/// 若没有任何方案命中（例如日期落在所有限定区间之外），
/// 回退到第一个「常驻方案」，再回退到列表第一个，保证永远有作息可用。
BellSchedule? resolveScheduleFor(List<BellSchedule> schedules, DateTime date) {
  if (schedules.isEmpty) return null;

  for (final s in schedules) {
    if (!s.isAlwaysOn && s.appliesOn(date)) return s;
  }
  for (final s in schedules) {
    if (s.isAlwaysOn) return s;
  }
  return schedules.first;
}
