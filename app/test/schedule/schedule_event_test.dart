import 'package:course_timetable/data/models/schedule_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('日程 JSON 往返保留日期、时间与备注', () {
    final event = ScheduleEvent(
      id: 'e1',
      title: '交高数作业',
      date: DateTime(2026, 11, 5, 18, 30),
      startTime: '15:00',
      endTime: '16:00',
      note: '教三 201',
    );
    final restored = ScheduleEvent.fromJson(event.toJson());
    expect(restored.id, 'e1');
    expect(restored.title, '交高数作业');
    expect(restored.dateKey, '2026-11-05');
    expect(restored.startTime, '15:00');
    expect(restored.endTime, '16:00');
    expect(restored.note, '教三 201');
  });

  test('全天日程不写时间，缺失标题有兜底', () {
    final event = ScheduleEvent.fromJson({
      'id': 'e2',
      'date': '2026-11-06',
    });
    expect(event.title, '未命名日程');
    expect(event.allDay, isTrue);
    expect(event.toJson().containsKey('startTime'), isFalse);
  });
}
