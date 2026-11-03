import 'dart:convert';

import '../models/timetable.dart';
import 'sync_config.dart';
import 'sync_engine.dart';
import 'sync_provider.dart';
import 'sync_state.dart';
import 'webdav_provider.dart';

/// 一次同步的结果。
class SyncResult {
  /// 是否向远端写了数据。
  final bool uploaded;

  /// 是否从远端拉到了数据。
  final bool downloaded;

  /// 人类可读摘要。
  final String summary;

  /// 冲突说明（每条一句中文）。
  final List<String> conflicts;

  /// 完成时间。
  final DateTime at;

  /// 合并后的课表（调用方需要用它更新本地数据）。
  final Timetable merged;

  /// 合并结果是否与本地不同。
  final bool changedLocal;

  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.summary,
    required this.merged,
    required this.changedLocal,
    this.conflicts = const [],
    required this.at,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// 同步编排：把「传输层」与「合并引擎」串起来，并维护基线状态。
///
/// 一次同步的完整流程：
/// 1. 读取上次同步的基线快照
/// 2. 从远端下载课表（不存在则把本地推上去，首次同步即完成）
/// 3. 三方合并（本地 / 远端 / 基线）
/// 4. 合并结果与本地不同 → 回调让调用方落库
/// 5. 合并结果与远端不同 → 上传
/// 6. 更新基线
class SyncService {
  SyncService({
    SyncEngine? engine,
    SyncStateStore? stateStore,
    SyncProvider Function(SyncConfig config)? providerFactory,
  })  : _engine = engine ?? const SyncEngine(),
        _stateStore = stateStore ?? SyncStateStore(),
        _providerFactory = providerFactory ?? defaultProviderFactory;

  final SyncEngine _engine;
  final SyncStateStore _stateStore;
  final SyncProvider Function(SyncConfig config) _providerFactory;

  /// 默认的传输层工厂：按配置里的后端类型选择实现。
  static SyncProvider defaultProviderFactory(SyncConfig config) {
    switch (config.backend) {
      case SyncBackend.webdav:
        return WebDavProvider(config: config.webdav);
    }
  }

  SyncStateStore get stateStore => _stateStore;

  /// 清除基线（「重置同步状态」）。
  Future<void> resetState() => _stateStore.clear();

  /// 测试连接。
  Future<SyncConfig> testConnection(SyncConfig config) async {
    if (!config.isConfigured) {
      throw const SyncException('同步配置不完整，请先填写网盘信息。');
    }
    final provider = _providerFactory(config);
    try {
      await provider.testConnection();
      return config;
    } finally {
      provider.dispose();
    }
  }

  /// 执行一次同步。
  ///
  /// [onRemoteMerged] 在「合并结果与本地不同」时被调用，
  /// 由调用方负责把合并后的课表写入本地仓储（保持本服务不直接依赖仓储）。
  Future<SyncResult> sync({
    required Timetable local,
    required SyncConfig config,
    Future<void> Function(Timetable merged)? onRemoteMerged,
  }) async {
    if (!config.isConfigured) {
      throw const SyncException('同步配置不完整，请先填写网盘信息。');
    }

    final provider = _providerFactory(config);
    try {
      final state = await _stateStore.load();

      // ---- 1. 下载远端 ----
      final RemoteDocument? remote;
      try {
        remote = await provider.download();
      } on SyncException {
        rethrow;
      } catch (e) {
        throw SyncException('读取远端课表失败', detail: '$e');
      }

      // ---- 2. 远端还没有文件：把本地推上去，完成首次同步 ----
      if (remote == null) {
        try {
          await provider.upload(_encode(local));
        } on SyncException {
          rethrow;
        } catch (e) {
          throw SyncException('上传课表失败', detail: '$e');
        }
        await _stateStore.save(
          state.withBase(local, deviceId: config.deviceId),
        );
        return SyncResult(
          uploaded: true,
          downloaded: false,
          summary: '远端还没有课表，已把本机课表上传作为初始版本',
          merged: local,
          changedLocal: false,
          at: DateTime.now(),
        );
      }

      // ---- 3. 解析远端 ----
      final remoteTimetable = _decode(remote.content);

      // ---- 4. 三方合并 ----
      final base = state.baseTimetable;
      final mergeResult = _engine.merge(
        local: local,
        remote: remoteTimetable,
        base: base,
      );

      // ---- 5. 合并结果与本地不同 → 交给调用方落库 ----
      if (mergeResult.differsFromLocal && onRemoteMerged != null) {
        await onRemoteMerged(mergeResult.merged);
      }

      // ---- 6. 合并结果与远端不同 → 上传 ----
      var uploaded = false;
      if (mergeResult.differsFromRemote) {
        try {
          await provider.upload(_encode(mergeResult.merged));
          uploaded = true;
        } on SyncException {
          rethrow;
        } catch (e) {
          throw SyncException('上传合并结果失败', detail: '$e');
        }
      }

      // ---- 7. 更新基线 ----
      await _stateStore.save(
        state.withBase(
          mergeResult.merged,
          remoteVersionTag: remote.versionTag,
          deviceId: config.deviceId,
        ),
      );

      return SyncResult(
        uploaded: uploaded,
        downloaded: true,
        summary: mergeResult.summary,
        conflicts: mergeResult.conflicts.map((c) => c.toString()).toList(),
        merged: mergeResult.merged,
        changedLocal: mergeResult.differsFromLocal,
        at: DateTime.now(),
      );
    } finally {
      provider.dispose();
    }
  }

  String _encode(Timetable t) => const JsonEncoder.withIndent('  ').convert(t.toJson());

  Timetable _decode(String text) {
    if (text.trim().isEmpty) {
      throw const SyncException('远端课表文件是空的，可能是上传中断导致的。');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw SyncException(
        '远端文件不是合法的 JSON，无法解析为课表。',
        detail: '$e',
      );
    }
    if (decoded is! Map) {
      throw const SyncException('远端文件结构不是课表对象，请确认同步路径指向的是本 App 的课表文件。');
    }
    try {
      return Timetable.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      throw SyncException('远端课表结构无法识别，可能来自不兼容的版本。', detail: '$e');
    }
  }
}
