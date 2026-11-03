import '../local/document_store.dart';
import '../models/schedule_event.dart';

/// 日程事件仓储：整份 JSON 读写，独立于课表文件。
class ScheduleEventRepository {
  ScheduleEventRepository({DocumentStore? store})
      : _store = store ?? DocumentStore('schedule_events.json');

  final DocumentStore _store;

  Future<List<ScheduleEvent>> load() async {
    try {
      final json = await _store.readJson();
      if (json == null) return const [];
      final raw = json['events'];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            ScheduleEvent.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<ScheduleEvent> events) async {
    await _store.writeJson({
      'version': 1,
      'events': [for (final event in events) event.toJson()],
    });
  }
}
