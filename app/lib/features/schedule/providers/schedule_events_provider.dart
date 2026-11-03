import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/schedule_event.dart';
import '../../../data/repositories/schedule_event_repository.dart';

final scheduleEventRepositoryProvider = Provider<ScheduleEventRepository>((ref) {
  return ScheduleEventRepository();
});

/// 日程事件列表（按日期、时间排序）。
final scheduleEventsProvider =
    AsyncNotifierProvider<ScheduleEventsController, List<ScheduleEvent>>(
  ScheduleEventsController.new,
);

class ScheduleEventsController extends AsyncNotifier<List<ScheduleEvent>> {
  ScheduleEventRepository get _repo =>
      ref.read(scheduleEventRepositoryProvider);

  @override
  Future<List<ScheduleEvent>> build() async {
    final events = await _repo.load();
    return _sorted(events);
  }

  static List<ScheduleEvent> _sorted(List<ScheduleEvent> events) {
    final list = List<ScheduleEvent>.of(events);
    list.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return (a.startTime ?? '').compareTo(b.startTime ?? '');
    });
    return list;
  }

  Future<void> _save(List<ScheduleEvent> events) async {
    final sorted = _sorted(events);
    state = AsyncData(sorted);
    await _repo.save(sorted);
  }

  Future<void> addEvents(List<ScheduleEvent> events) async {
    if (events.isEmpty) return;
    final current = state.valueOrNull ?? const <ScheduleEvent>[];
    await _save([...current, ...events]);
  }

  Future<void> upsert(ScheduleEvent event) async {
    final current = state.valueOrNull ?? const <ScheduleEvent>[];
    await _save([
      for (final e in current)
        if (e.id != event.id) e,
      event,
    ]);
  }

  Future<void> remove(String id) async {
    final current = state.valueOrNull ?? const <ScheduleEvent>[];
    await _save(current.where((e) => e.id != id).toList());
  }
}
