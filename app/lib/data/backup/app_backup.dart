import 'dart:convert';

import '../../core/app_info.dart';
import '../models/app_settings.dart';
import '../models/schedule_event.dart';
import '../models/timetable.dart';
import '../repositories/timetable_history_repository.dart';
import '../sync/sync_state.dart';

/// 课序完整数据备份。
///
/// 与旧的“纯课表 JSON”不同，该格式同时保存设置、主题、节假日、AI 与同步
/// 配置、日程事件、撤销历史和同步状态，可在导入页整体恢复。
class AppBackup {
  const AppBackup({
    required this.exportedAt,
    required this.appVersion,
    required this.timetable,
    required this.settings,
    required this.scheduleEvents,
    required this.history,
    required this.syncState,
  });

  static const String formatName = 'kexu-full-backup';
  static const int formatVersion = 1;

  final DateTime exportedAt;
  final String appVersion;
  final Timetable timetable;
  final AppSettings settings;
  final List<ScheduleEvent> scheduleEvents;
  final List<TimetableHistoryEntry> history;
  final SyncState syncState;

  factory AppBackup.create({
    required Timetable timetable,
    required AppSettings settings,
    required List<ScheduleEvent> scheduleEvents,
    required List<TimetableHistoryEntry> history,
    required SyncState syncState,
    DateTime? now,
  }) =>
      AppBackup(
        exportedAt: now ?? DateTime.now(),
        appVersion: fullVersion,
        timetable: timetable,
        settings: settings,
        scheduleEvents: List<ScheduleEvent>.unmodifiable(scheduleEvents),
        history: List<TimetableHistoryEntry>.unmodifiable(history),
        syncState: syncState,
      );

  Map<String, dynamic> toJson() => {
        'format': formatName,
        'version': formatVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersion': appVersion,
        'data': {
          'timetable': timetable.toJson(),
          'settings': settings.toJson(),
          'scheduleEvents': [
            for (final event in scheduleEvents) event.toJson(),
          ],
          'history': [for (final entry in history) entry.toJson()],
          'syncState': syncState.toJson(),
        },
      };

  String toJsonText() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  static AppBackup fromJson(Map<String, dynamic> json) {
    if (json['format'] != formatName) {
      throw const FormatException('不是课序完整备份文件');
    }
    final version = json['version'];
    if (version != formatVersion) {
      throw FormatException('不支持的完整备份版本：$version');
    }
    final data = json['data'];
    if (data is! Map) {
      throw const FormatException('完整备份缺少 data 字段');
    }
    final dataMap = Map<String, dynamic>.from(data);
    final timetableRaw = dataMap['timetable'];
    final settingsRaw = dataMap['settings'];
    final eventsRaw = dataMap['scheduleEvents'];
    final historyRaw = dataMap['history'];
    final syncStateRaw = dataMap['syncState'];
    if (timetableRaw is! Map || settingsRaw is! Map) {
      throw const FormatException('完整备份缺少课表或设置数据');
    }
    if (eventsRaw is! List || historyRaw is! List || syncStateRaw is! Map) {
      throw const FormatException('完整备份中的日程、历史或同步状态格式无效');
    }

    final history = <TimetableHistoryEntry>[];
    for (final item in historyRaw) {
      if (item is! Map) continue;
      final entry = TimetableHistoryEntry.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (entry != null) history.add(entry);
    }

    return AppBackup(
      exportedAt:
          DateTime.tryParse((json['exportedAt'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: (json['appVersion'] ?? '').toString(),
      timetable: Timetable.fromJson(Map<String, dynamic>.from(timetableRaw)),
      settings: AppSettings.fromJson(Map<String, dynamic>.from(settingsRaw)),
      scheduleEvents: [
        for (final item in eventsRaw)
          if (item is Map)
            ScheduleEvent.fromJson(Map<String, dynamic>.from(item)),
      ],
      history: history,
      syncState: SyncState.fromJson(Map<String, dynamic>.from(syncStateRaw)),
    );
  }

  /// 仅在文本确实是完整备份时返回对象；普通课表 JSON 返回 null。
  static AppBackup? tryDecode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['format'] != formatName) return null;
    return AppBackup.fromJson(Map<String, dynamic>.from(decoded));
  }
}
