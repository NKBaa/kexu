import '../../core/utils/json_utils.dart';

/// 学期：定义「第 1 周的周一」和总周数，是所有周次/日期换算的基准。
class Semester {
  final String id;
  final String name;

  /// 第 1 周的周一（零点）。
  final DateTime startMonday;

  /// 学期总周数，常见 16~20 周。
  final int totalWeeks;

  const Semester({
    required this.id,
    required this.name,
    required this.startMonday,
    this.totalWeeks = 16,
  });

  Semester copyWith({String? name, DateTime? startMonday, int? totalWeeks}) {
    return Semester(
      id: id,
      name: name ?? this.name,
      startMonday: startMonday ?? this.startMonday,
      totalWeeks: totalWeeks ?? this.totalWeeks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startMonday': startMonday.toIso8601String(),
        'totalWeeks': totalWeeks,
      };

  static Semester fromJson(Map<String, dynamic> j) {
    final raw = asString(j['startMonday']);
    return Semester(
      id: asString(j['id']),
      name: asString(j['name'], fallback: '未命名学期'),
      startMonday: DateTime.tryParse(raw) ?? DateTime.now(),
      totalWeeks: asInt(j['totalWeeks']) ?? 16,
    );
  }

  /// 全部周次，如 [1,2,...,16]。
  List<int> get allWeeks => List<int>.generate(totalWeeks, (i) => i + 1);
}

/// 一节课（「第 N 节」）的时间定义，由学校作息决定，可在设置里改。
class TimeSlot {
  final int period;

  /// `HH:mm` 形式，如 `08:00`。
  final String start;

  /// `HH:mm` 形式，如 `08:45`。
  final String end;

  const TimeSlot({required this.period, required this.start, required this.end});

  TimeSlot copyWith({int? period, String? start, String? end}) => TimeSlot(
        period: period ?? this.period,
        start: start ?? this.start,
        end: end ?? this.end,
      );

  Map<String, dynamic> toJson() => {'period': period, 'start': start, 'end': end};

  static TimeSlot fromJson(Map<String, dynamic> j) => TimeSlot(
        period: asInt(j['period']) ?? 1,
        start: asString(j['start'], fallback: '08:00'),
        end: asString(j['end'], fallback: '08:45'),
      );

  /// 展示用，如 `08:00-08:45`。
  String get label => '$start-$end';
}

/// 中国大陆高校最常见的 12 节作息，作为默认值。
List<TimeSlot> defaultTimeSlots() => const [
      TimeSlot(period: 1, start: '08:00', end: '08:45'),
      TimeSlot(period: 2, start: '08:55', end: '09:40'),
      TimeSlot(period: 3, start: '10:00', end: '10:45'),
      TimeSlot(period: 4, start: '10:55', end: '11:40'),
      TimeSlot(period: 5, start: '14:00', end: '14:45'),
      TimeSlot(period: 6, start: '14:55', end: '15:40'),
      TimeSlot(period: 7, start: '16:00', end: '16:45'),
      TimeSlot(period: 8, start: '16:55', end: '17:40'),
      TimeSlot(period: 9, start: '19:00', end: '19:45'),
      TimeSlot(period: 10, start: '19:55', end: '20:40'),
      TimeSlot(period: 11, start: '20:50', end: '21:35'),
      TimeSlot(period: 12, start: '21:45', end: '22:30'),
    ];
