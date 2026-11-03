import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/timetable.dart';
import '../../../data/sync/sync_config.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../data/sync/sync_service.dart';
import '../../settings/providers/settings_provider.dart';
import '../../timetable/providers/timetable_provider.dart';

/// 同步服务实例（测试可 override 注入假传输层）。
final syncServiceProvider = Provider<SyncService>((ref) => SyncService());

/// 网盘同步配置。
final syncConfigProvider =
    AsyncNotifierProvider<SyncConfigController, SyncConfig>(SyncConfigController.new);

class SyncConfigController extends AsyncNotifier<SyncConfig> {
  @override
  Future<SyncConfig> build() async {
    final settings = await ref.watch(settingsProvider.future);
    var config = settings.syncConfig;
    // 首次启用同步时补一个设备标识，用于冲突时区分设备
    if (config.deviceId.isEmpty) {
      config = config.copyWith(deviceId: SyncConfig.newDeviceId());
      await ref.read(settingsProvider.notifier).saveSyncConfig(config);
    }
    return config;
  }

  Future<void> save(SyncConfig config) async {
    state = AsyncData(config);
    await ref.read(settingsProvider.notifier).saveSyncConfig(config);
  }

  /// 记录一次成功同步的时间。
  Future<void> markSynced() async {
    final current = state.valueOrNull ?? const SyncConfig();
    await save(current.copyWith(lastSyncAtMs: DateTime.now().millisecondsSinceEpoch));
  }
}

/// 同步运行状态（供界面展示）。
class SyncStatus {
  final bool running;
  final SyncResult? lastResult;
  final String? error;
  final List<String> conflicts;
  final String? info;

  const SyncStatus({
    this.running = false,
    this.lastResult,
    this.error,
    this.conflicts = const [],
    this.info,
  });

  SyncStatus copyWith({
    bool? running,
    SyncResult? lastResult,
    String? error,
    List<String>? conflicts,
    String? info,
    bool clearError = false,
    bool clearInfo = false,
  }) =>
      SyncStatus(
        running: running ?? this.running,
        lastResult: lastResult ?? this.lastResult,
        error: clearError ? null : (error ?? this.error),
        conflicts: conflicts ?? this.conflicts,
        info: clearInfo ? null : (info ?? this.info),
      );
}

final syncStatusProvider =
    NotifierProvider<SyncStatusController, SyncStatus>(SyncStatusController.new);

class SyncStatusController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  void setRunning(bool running) {
    state = state.copyWith(running: running, clearError: running);
  }

  void setResult(SyncResult result) {
    state = SyncStatus(
      running: false,
      lastResult: result,
      conflicts: result.conflicts,
      info: result.summary,
    );
  }

  void setError(String message) {
    state = SyncStatus(running: false, error: message, lastResult: state.lastResult);
  }

  void clear() {
    state = const SyncStatus();
  }
}

/// 执行同步的入口（界面通过它触发）。
final syncControllerProvider = Provider<SyncController>(SyncController.new);

class SyncController {
  SyncController(this._ref);

  final Ref _ref;

  SyncService get _service => _ref.read(syncServiceProvider);

  /// 测试连接；失败时抛 [SyncException]（由界面捕获展示）。
  Future<void> testConnection(SyncConfig config) async {
    await _service.testConnection(config);
  }

  /// 立即同步。
  ///
  /// 合并结果如果与本地不同，会写回本地课表仓储。
  /// 返回 null 表示配置未启用同步。
  Future<SyncResult?> syncNow() async {
    final config = await _ref.read(syncConfigProvider.future);
    if (!config.isConfigured) {
      throw const SyncException('同步配置不完整，请先填写网盘信息。');
    }

    final status = _ref.read(syncStatusProvider.notifier);
    status.setRunning(true);

    try {
      final local = await _ref.read(timetableProvider.future);

      final result = await _service.sync(
        local: local,
        config: config,
        onRemoteMerged: (merged) async {
          await _ref.read(timetableProvider.notifier).replaceTimetable(merged);
        },
      );

      // 百度网盘刷新后会轮换 token，必须回写，否则下次同步鉴权失败
      await _ref.read(syncConfigProvider.notifier).markSynced();
      status.setResult(result);
      return result;
    } on SyncException catch (e) {
      status.setError(e.message);
      rethrow;
    } catch (e) {
      status.setError('同步失败：$e');
      rethrow;
    }
  }

  /// 重置同步基线（下次同步会以远端为准重新比对）。
  Future<void> resetSyncState() async {
    await _service.resetState();
    final config = _ref.read(syncConfigProvider).valueOrNull;
    if (config != null) {
      await _ref.read(syncConfigProvider.notifier).save(config.copyWith(lastSyncAtMs: 0));
    }
    _ref.read(syncStatusProvider.notifier).clear();
  }
}

/// 自动同步：课表内容变化后延迟上传（防抖），避免连续编辑时频繁请求网盘。
final autoSyncProvider = Provider<AutoSyncCoordinator>((ref) {
  final coordinator = AutoSyncCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

class AutoSyncCoordinator {
  AutoSyncCoordinator(this._ref);

  final Ref _ref;
  bool _disposed = false;
  String? _lastSyncedHash;
  bool _inFlight = false;
  Timer? _debounce;

  /// 编辑一门课往往连续触发多次状态更新，等手停下来再同步。
  static const Duration debounceDelay = Duration(seconds: 4);

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
  }

  /// 在课表变更后调用（已做防抖）。
  ///
  /// 用「内容哈希去重」而不是「每次都同步」：连续编辑时避免反复请求网盘，
  /// 既省流量也避免触发服务商频率限制。
  void onTimetableChanged() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () {
      if (!_disposed) _runSync();
    });
  }

  /// 启动时拉取一次。
  ///
  /// 注意：这里**必须 await provider 的 future**，不能用 `valueOrNull`。
  /// 启动瞬间设置还在异步加载，`valueOrNull` 是 null，
  /// 用它会直接提前返回，导致「启动自动同步」静默失效。
  Future<void> onAppStart() async {
    await _runSync(force: true);
  }

  Future<void> _runSync({bool force = false}) async {
    if (_disposed || _inFlight) return;

    final SyncConfig config;
    try {
      config = await _ref.read(syncConfigProvider.future);
    } catch (_) {
      return; // 设置读取失败时静默跳过
    }
    if (!config.isActive) return;
    // 自动拉取只在 autoSync 开启时进行；force 表示启动时的那次
    if (!config.autoSync && !force) return;

    final Timetable timetable;
    try {
      timetable = await _ref.read(timetableProvider.future);
    } catch (_) {
      return;
    }

    final hash = contentHash(timetable.toJson());
    if (!force && hash == _lastSyncedHash) return;

    _inFlight = true;
    try {
      await _ref.read(syncControllerProvider).syncNow();
      _lastSyncedHash = hash;
    } catch (e) {
      // 自动同步失败不打扰用户：原因已记录在 syncStatusProvider，
      // 用户打开同步页即可看到。
      debugPrint('自动同步失败：$e');
    } finally {
      _inFlight = false;
    }
  }
}
