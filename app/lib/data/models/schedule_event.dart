import '../../core/utils/ids.dart';
import '../../core/utils/json_utils.dart';

/// 日程事件：与课表课程无关的个人事项（考试、作业截止、活动等）。
class ScheduleEvent {
  ScheduleEvent({
    required this.id,
    required this.title,
    required DateTime date,
    this.startTime,
    this.endTime,
    this.note = '',
  }) : date = DateTime(date.year, date.month, date.day);

  final String id;
  final String title;

  /// 只取年月日，避免时分秒影响按天分组。
  final DateTime date;

  /// `HH:mm`；为空表示全天。
  final String? startTime;
  final String? endTime;
  final String note;

  bool get allDay => startTime == null || startTime!.isEmpty;

  String get dateKey => ScheduleEvent.formatDateKey(date);
  ScheduleEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    String? startTime,
    String? endTime,
    String? note,
    bool clearTime = false,
  }) =>
      ScheduleEvent(
        id: id ?? this.id,
        title: title ?? this.title,
        date: date ?? this.date,
        startTime: clearTime ? null : (startTime ?? this.startTime),
        endTime: clearTime ? null : (endTime ?? this.endTime),
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': dateKey,
        if (!allDay) 'startTime': startTime,
        if (!allDay && endTime != null && endTime!.isNotEmpty) 'endTime': endTime,
        if (note.isNotEmpty) 'note': note,
      };

  static ScheduleEvent fromJson(Map<String, dynamic> j) {
    final rawDate = asString(j['date']);
    final parsed = DateTime.tryParse(rawDate) ?? DateTime.now();
    final start = asString(j['startTime']).trim();
    final end = asString(j['endTime']).trim();
    return ScheduleEvent(
      id: asString(j['id']).isEmpty ? newId() : asString(j['id']),
      title: asString(j['title']).trim().isEmpty
          ? '未命名日程'
          : asString(j['title']).trim(),
      date: parsed,
      startTime: start.isEmpty ? null : start,
      endTime: end.isEmpty ? null : end,
      note: asString(j['note']).trim(),
    );
  }

  static String formatDateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
