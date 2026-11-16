import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup/app_backup.dart';
import '../../data/sync/sync_state.dart';
import '../../data/models/timetable.dart';
import '../schedule/providers/schedule_events_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../timetable/providers/timetable_provider.dart';

/// 同步状态的本地存储（完整备份导出/恢复也会使用）。
final syncStateStoreProvider = Provider<SyncStateStore>((ref) {
  return SyncStateStore();
});

/// 从当前各 Riverpod 状态收集一份完整备份。
Future<AppBackup> collectAppBackup(
  WidgetRef ref,
  Timetable timetable, {
  DateTime? now,
}) async {
  final settings = ref.read(settingsProvider).valueOrNull ??
      await ref.read(settingsRepositoryProvider).load();
  final scheduleEvents = ref.read(scheduleEventsProvider).valueOrNull ??
      await ref.read(scheduleEventRepositoryProvider).load();
  final history = await ref.read(timetableHistoryRepositoryProvider).load();
  final syncState = await ref.read(syncStateStoreProvider).load();
  return AppBackup.create(
    timetable: timetable,
    settings: settings,
    scheduleEvents: scheduleEvents,
    history: history,
    syncState: syncState,
    now: now,
  );
}

/// 恢复完整备份；先写设置和日程，再替换课表，最后恢复历史与同步基线。
Future<void> restoreAppBackup(WidgetRef ref, AppBackup backup) async {
  await ref.read(settingsProvider.notifier).save(backup.settings);
  await ref
      .read(scheduleEventsProvider.notifier)
      .replaceAll(backup.scheduleEvents);
  await ref.read(timetableProvider.notifier).replaceTimetable(
        backup.timetable,
        recordHistory: false,
      );
  await ref
      .read(timetableHistoryRepositoryProvider)
      .replaceAll(backup.history);
  await ref.read(syncStateStoreProvider).save(backup.syncState);
}
