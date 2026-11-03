import 'dart:convert';

import '../local/document_store.dart';
import '../models/timetable.dart';

/// 同步的本地状态：上次同步的**基线快照**与元信息。
///
/// 为什么需要基线：三方合并需要知道「上次同步时两端一致的样子」，
/// 才能判断某门课到底是「本机改了」还是「远端改了」。
/// 只比较本地与远端两份数据是无法区分「谁改的」的。
class SyncState {
  /// 上次成功同步后的课表 JSON 文本（基线）。为空表示从未同步过。
  final String baseJson;

  /// 上次同步完成时间（毫秒）。
  final int lastSyncAtMs;

  /// 上次同步时的远端版本标记（WebDAV ETag / 百度网盘 md5）。
  final String? remoteVersionTag;

  /// 本机标识（与 SyncConfig.deviceId 保持一致，便于排查）。
  final String deviceId;

  const SyncState({
    this.baseJson = '',
    this.lastSyncAtMs = 0,
    this.remoteVersionTag,
    this.deviceId = '',
  });

  bool get hasBase => baseJson.trim().isNotEmpty;

  /// 解析基线课表；无基线或解析失败时返回 null。
  Timetable? get baseTimetable {
    if (!hasBase) return null;
    try {
      final decoded = jsonDecode(baseJson);
      if (decoded is! Map) return null;
      return Timetable.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 基线损坏时当作「没有基线」处理：下一次同步会退化为保守合并，
      // 这比因为一份坏快照而彻底无法同步要好。
      return null;
    }
  }

  SyncState copyWith({
    String? baseJson,
    int? lastSyncAtMs,
    String? remoteVersionTag,
    String? deviceId,
  }) =>
      SyncState(
        baseJson: baseJson ?? this.baseJson,
        lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
        remoteVersionTag: remoteVersionTag ?? this.remoteVersionTag,
        deviceId: deviceId ?? this.deviceId,
      );

  /// 用一份课表刷新基线。
  SyncState withBase(Timetable timetable, {String? remoteVersionTag, String? deviceId}) =>
      SyncState(
        baseJson: const JsonEncoder().convert(timetable.toJson()),
        lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
        remoteVersionTag: remoteVersionTag ?? this.remoteVersionTag,
        deviceId: deviceId ?? this.deviceId,
      );

  Map<String, dynamic> toJson() => {
        'baseJson': baseJson,
        'lastSyncAtMs': lastSyncAtMs,
        'remoteVersionTag': remoteVersionTag,
        'deviceId': deviceId,
      };

  static SyncState fromJson(Map<String, dynamic> j) => SyncState(
        baseJson: (j['baseJson'] ?? '').toString(),
        lastSyncAtMs: j['lastSyncAtMs'] is num ? (j['lastSyncAtMs'] as num).toInt() : 0,
        remoteVersionTag: j['remoteVersionTag']?.toString(),
        deviceId: (j['deviceId'] ?? '').toString(),
      );
}

/// 同步状态的本地存储（`sync_state.json`）。
///
/// 与课表/设置分开存：同步基线属于「派生数据」，
/// 清空它只影响下一次同步的策略，不该影响用户的课表与配置。
class SyncStateStore {
  SyncStateStore({DocumentStore? store})
      : _store = store ?? DocumentStore('sync_state.json', backupKeep: 3);

  final DocumentStore _store;

  Future<SyncState> load() async {
    try {
      final json = await _store.readJson();
      if (json == null) return const SyncState();
      return SyncState.fromJson(json);
    } catch (_) {
      return const SyncState();
    }
  }

  Future<void> save(SyncState state) async {
    await _store.writeJson(state.toJson());
  }

  /// 清除基线（「重置同步状态」用）。
  Future<void> clear() async {
    try {
      await _store.delete();
    } catch (_) {
      // 删不掉也不算致命，下次同步仍会覆盖
    }
  }
}
