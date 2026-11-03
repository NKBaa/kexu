import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/repositories/settings_repository.dart';
import 'package:course_timetable/data/sync/sync_config.dart';
import 'package:course_timetable/data/sync/sync_provider.dart';
import 'package:course_timetable/data/sync/sync_service.dart';
import 'package:course_timetable/data/sync/sync_state.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/sync/providers/sync_controller.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假的传输层：只记录调用，不发网络请求。
class _FakeProvider implements SyncProvider {
  _FakeProvider();

  RemoteDocument? remote;
  int uploadCount = 0;
  int downloadCount = 0;
  String? lastUploaded;

  @override
  String get displayName => 'Fake';

  @override
  Future<void> testConnection() async {}

  @override
  Future<RemoteDocument?> download() async {
    downloadCount++;
    return remote;
  }

  @override
  Future<void> upload(String content) async {
    uploadCount++;
    lastUploaded = content;
    remote = RemoteDocument(content: content);
  }

  @override
  void dispose() {}
}

class _FixedSyncConfig extends SyncConfigController {
  _FixedSyncConfig(this._config);
  final SyncConfig _config;

  @override
  Future<SyncConfig> build() async => _config;
}

class _FixedTimetable extends TimetableController {
  _FixedTimetable(this._timetable);
  final Timetable _timetable;

  @override
  Future<Timetable> build() async => _timetable;
}

Timetable _sample() => Timetable(
      semester: Semester(
        id: 'sem',
        name: '2026 春季学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: const [
        Course(
          id: 'c1',
          semesterId: 'sem',
          name: '高等数学',
          colorIndex: 0,
          sessions: [
            Session(
              id: 's1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1, 3, 5, 7],
              location: 'A101',
            ),
          ],
        ),
      ],
    );

SyncConfig _config({bool enabled = true, bool autoSync = true}) => SyncConfig(
      enabled: enabled,
      autoSync: autoSync,
      backend: SyncBackend.webdav,
      deviceId: 'test-device',
      webdav: const WebDavConfig(
        url: 'https://example.invalid/dav/',
        remotePath: '/t/timetable.json',
      ),
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('autosync_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer containerWith({
    required _FakeProvider fake,
    SyncConfig? config,
    Timetable? timetable,
  }) {
    final c = ProviderContainer(
      overrides: [
        syncConfigProvider.overrideWith(() => _FixedSyncConfig(config ?? _config())),
        timetableProvider.overrideWith(() => _FixedTimetable(timetable ?? _sample())),
        // markSynced() 会经设置仓储落盘；不注入的话会走真实 path_provider，
        // 在测试环境里没有平台通道处理器（只会落到降级链并打印噪音日志）。
        settingsRepositoryProvider.overrideWithValue(
          SettingsRepository(
            store: DocumentStore('settings.json', baseDirectory: tmp),
          ),
        ),
        syncServiceProvider.overrideWithValue(
          SyncService(
            providerFactory: (_) => fake,
            stateStore: SyncStateStore(
              store: DocumentStore('sync_state.json', baseDirectory: tmp),
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('启动自动同步（回归测试）', () {
    // 这个用例守的是一个**曾经静默失效**的缺陷：
    // onAppStart 早期用 `valueOrNull` 读尚未加载完成的异步 provider，
    // 拿到 null 就直接返回，导致「启动自动同步」永远不执行、且不报任何错。
    // 修复方式是 await provider 的 future。这个测试确保它不会退化。
    test('配置已启用时，启动会自动执行一次同步（首次会推送到远端）', () async {
      final fake = _FakeProvider();
      final container = containerWith(fake: fake);

      await container.read(autoSyncProvider).onAppStart();

      expect(fake.uploadCount, 1, reason: '远端为空时，启动同步应把本地课表推上去');
      expect(fake.downloadCount, 1);
    });

    test('未启用同步时，启动不做任何请求', () async {
      final fake = _FakeProvider();
      final container = containerWith(fake: fake, config: _config(enabled: false));

      await container.read(autoSyncProvider).onAppStart();

      expect(fake.uploadCount, 0);
      expect(fake.downloadCount, 0);
    });

    test('配置不完整时（缺地址）不做请求', () async {
      final fake = _FakeProvider();
      final container = containerWith(
        fake: fake,
        config: const SyncConfig(enabled: true, autoSync: true, deviceId: 'd'),
      );

      await container.read(autoSyncProvider).onAppStart();

      expect(fake.uploadCount, 0);
      expect(fake.downloadCount, 0);
    });
  });

  group('自动同步：变更触发与去重', () {
    test('课表变更后触发同步（防抖后执行）', () async {
      final fake = _FakeProvider();
      final container = containerWith(fake: fake);

      container.read(autoSyncProvider).onTimetableChanged();

      // 防抖窗口内不应立刻发请求
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(fake.downloadCount, 0, reason: '防抖窗口内不应发请求');

      // 等过防抖窗口
      await Future<void>.delayed(AutoSyncCoordinator.debounceDelay + const Duration(seconds: 1));
      expect(fake.downloadCount, 1, reason: '防抖结束后应执行一次同步');
    });

    test('内容未变化时不重复同步（避免同步抖动）', () async {
      final fake = _FakeProvider();
      final container = containerWith(fake: fake);

      final coordinator = container.read(autoSyncProvider);
      await coordinator.onAppStart();
      final afterFirst = fake.downloadCount;

      // 内容没变，再次触发应被内容哈希去重挡掉
      coordinator.onTimetableChanged();
      await Future<void>.delayed(AutoSyncCoordinator.debounceDelay + const Duration(seconds: 1));

      expect(fake.downloadCount, afterFirst, reason: '内容未变不应再发请求');
    });
  });
}
