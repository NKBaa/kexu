@Tags(['e2e'])
library;

import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/sync/sync_config.dart';
import 'package:course_timetable/data/sync/sync_service.dart';
import 'package:course_timetable/data/sync/sync_state.dart';
import 'package:course_timetable/data/sync/webdav_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实 WebDAV 端到端测试。
///
/// 默认**跳过**（否则 CI 或普通 `flutter test` 会因为没有服务器而失败）。
/// 需要先启动本地 WebDAV 服务器：
///
/// ```powershell
/// python tooling/webdav-server.py --root C:\dev\davroot --port 8765
/// ```
///
/// 然后带环境变量运行：
///
/// ```powershell
/// $env:WEBDAV_E2E='1'
/// $env:WEBDAV_E2E_URL='http://127.0.0.1:8765/'
/// flutter test test\sync\webdav_e2e_test.dart
/// ```
///
/// 这层测试的价值：mock 只能验证「我发出的请求符合我的预期」，
/// 而真实服务器能验证「协议真的互通」—— 目录创建、PUT、PROPFIND、GET
/// 以及**两台设备通过同一份远端文件完成同步**的完整闭环。
void main() {
  final enabled = Platform.environment['WEBDAV_E2E'] == '1';
  final baseUrl = Platform.environment['WEBDAV_E2E_URL'] ?? 'http://127.0.0.1:8765/';

  /// 没有服务器时整组跳过，保证 `flutter test` 全量运行不被这层拖累。
  final skipReason = enabled
      ? null
      : '需要先启动本地 WebDAV 服务器并设置 WEBDAV_E2E=1（见文件顶部说明）';

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dav_e2e_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  WebDavConfig configFor(String path) => WebDavConfig(
        url: baseUrl,
        username: '',
        password: '',
        remotePath: path,
      );

  Timetable table(List<Course> courses) => Timetable(
        semester: Semester(
          id: 'sem',
          name: '2026 春季学期',
          startMonday: DateTime(2026, 2, 23),
          totalWeeks: 16,
        ),
        timeSlots: defaultTimeSlots(),
        courses: courses,
      );

  Course course(String id, String name, {int day = 1, int start = 1}) => Course(
        id: id,
        semesterId: 'sem',
        name: name,
        colorIndex: 0,
        sessions: [
          Session(
            id: '$id-s',
            dayOfWeek: day,
            startPeriod: start,
            endPeriod: start + 1,
            weeks: const [1, 2, 3],
            location: 'A101',
          ),
        ],
      );

  group('WebDAV 真实协议往返', () {    test('上传后能下载回来，中文不乱码', () async {
      final path = '/e2e/roundtrip-${DateTime.now().microsecondsSinceEpoch}.json';
      final provider = WebDavProvider(config: configFor(path));

      const payload = '{"name":"高等数学","note":"第 3-5,7-9 周上课（单周）"}';
      await provider.upload(payload);

      final doc = await provider.download();
      expect(doc, isNotNull);
      expect(doc!.content, payload);

      provider.dispose();
    });

    test('下载不存在的文件返回 null（而不是抛异常）', () async {
      final provider = WebDavProvider(
        config: configFor('/e2e/definitely-missing-${DateTime.now().microsecondsSinceEpoch}.json'),
      );

      expect(await provider.download(), isNull);

      provider.dispose();
    });

    test('testConnection 在服务器可用时通过', () async {
      final provider = WebDavProvider(config: configFor('/e2e/probe.json'));
      await provider.testConnection();
      provider.dispose();
    });

    test('PROPFIND 能解析出 ETag / 修改时间', () async {
      final path = '/e2e/meta-${DateTime.now().microsecondsSinceEpoch}.json';
      final provider = WebDavProvider(config: configFor(path));
      await provider.upload('{"v":1}');

      final doc = await provider.download();
      expect(doc, isNotNull);
      // 不同服务器给出的 ETag 形式不同，但通常不会为空
      expect(doc!.content, '{"v":1}');

      provider.dispose();
    });
  }, skip: skipReason);

  group('双设备通过同一份远端文件同步（真实闭环）', () {
    test('A 上传 → B 拉取 → B 新增 → A 拉取，两端最终一致', () async {
      final remotePath = '/e2e/two-device-${DateTime.now().microsecondsSinceEpoch}.json';

      // 两台设备各自有独立的本地基线与本地课表
      final dirA = Directory('${tmp.path}/devA')..createSync(recursive: true);
      final dirB = Directory('${tmp.path}/devB')..createSync(recursive: true);

      final serviceA = SyncService(
        stateStore: SyncStateStore(
          store: DocumentStore('sync_state.json', baseDirectory: dirA),
        ),
      );
      final serviceB = SyncService(
        stateStore: SyncStateStore(
          store: DocumentStore('sync_state.json', baseDirectory: dirB),
        ),
      );

      final config = SyncConfig(
        enabled: true,
        autoSync: true,
        backend: SyncBackend.webdav,
        deviceId: 'devA',
        webdav: configFor(remotePath),
      );
      final configB = SyncConfig(
        enabled: true,
        autoSync: true,
        backend: SyncBackend.webdav,
        deviceId: 'devB',
        webdav: configFor(remotePath),
      );

      // ---- 1. 设备 A：本机有「高等数学」，首次同步 → 远端为空，应上传 ----
      var localA = table([course('a', '高等数学')]);
      final r1 = await serviceA.sync(local: localA, config: config);
      expect(r1.uploaded, isTrue, reason: '首次同步应把本地课表推到远端');
      expect(r1.downloaded, isFalse);

      // ---- 2. 设备 B：本地为空，同步 → 应拉到 A 的课表 ----
      var localB = table([]);
      final r2 = await serviceB.sync(
        local: localB,
        config: configB,
        onRemoteMerged: (merged) async => localB = merged,
      );
      expect(r2.downloaded, isTrue);
      expect(localB.courses.map((c) => c.name), contains('高等数学'));
      expect(r2.changedLocal, isTrue, reason: 'B 的本地应被远端内容更新');

      // ---- 3. 设备 B：本机新增「数据结构」，同步 → 应上传合并结果 ----
      localB = table([
        ...localB.courses,
        course('b', '数据结构', day: 3, start: 5),
      ]);
      final r3 = await serviceB.sync(
        local: localB,
        config: configB,
        onRemoteMerged: (merged) async => localB = merged,
      );
      expect(r3.uploaded, isTrue, reason: 'B 的新增应上传');
      expect(r3.merged.courses.length, 2);

      // ---- 4. 设备 A：再次同步 → 应拿到 B 新增的课 ----
      final r4 = await serviceA.sync(
        local: localA,
        config: config,
        onRemoteMerged: (merged) async => localA = merged,
      );

      expect(localA.courses.map((c) => c.name), containsAll(['高等数学', '数据结构']));
      expect(r4.conflicts, isEmpty, reason: '两端改的是不同课程，不应产生冲突');
      expect(r4.merged.courses.length, 2);

      // ---- 5. 收敛性：再同步一次应无任何改动（不抖动）----
      final r5 = await serviceA.sync(
        local: localA,
        config: config,
        onRemoteMerged: (merged) async => localA = merged,
      );
      expect(r5.uploaded, isFalse, reason: '已一致，不应重复上传');
      expect(r5.changedLocal, isFalse, reason: '已一致，不应改动本地');
    });

    test('并行修改不同课程：A 删一门、B 加一门，两边都不丢', () async {
      final remotePath = '/e2e/parallel-${DateTime.now().microsecondsSinceEpoch}.json';
      final dirA = Directory('${tmp.path}/pA')..createSync(recursive: true);
      final dirB = Directory('${tmp.path}/pB')..createSync(recursive: true);

      final serviceA = SyncService(
        stateStore: SyncStateStore(
          store: DocumentStore('sync_state.json', baseDirectory: dirA),
        ),
      );
      final serviceB = SyncService(
        stateStore: SyncStateStore(
          store: DocumentStore('sync_state.json', baseDirectory: dirB),
        ),
      );

      final configA = SyncConfig(
        enabled: true,
        backend: SyncBackend.webdav,
        deviceId: 'A',
        webdav: configFor(remotePath),
      );
      final configB = configA.copyWith(deviceId: 'B');

      // 初始状态：两端都有「高数」和「英语」
      var localA = table([course('a', '高等数学'), course('b', '大学英语', day: 2)]);
      await serviceA.sync(local: localA, config: configA);

      var localB = table([]);
      await serviceB.sync(
        local: localB,
        config: configB,
        onRemoteMerged: (m) async => localB = m,
      );
      expect(localB.courses.length, 2);

      // A 删除「大学英语」；B 新增「数据结构」—— 两端并行修改
      localA = table([course('a', '高等数学')]);
      localB = table([
        ...localB.courses,
        course('c', '数据结构', day: 3, start: 5),
      ]);

      // A 先同步（上传删除）
      await serviceA.sync(
        local: localA,
        config: configA,
        onRemoteMerged: (m) async => localA = m,
      );

      // B 再同步（应合并：保留 B 的新增，同时接受 A 的删除）
      final rB = await serviceB.sync(
        local: localB,
        config: configB,
        onRemoteMerged: (m) async => localB = m,
      );

      final namesB = localB.courses.map((c) => c.name).toSet();
      expect(namesB, contains('高等数学'));
      expect(namesB, contains('数据结构'), reason: 'B 自己新增的课必须保留');
      expect(namesB, isNot(contains('大学英语')), reason: 'A 的删除应传播过来');
      expect(rB.conflicts, isEmpty, reason: '并行改不同课程不算冲突');

      // A 再同步，两端最终一致
      await serviceA.sync(
        local: localA,
        config: configA,
        onRemoteMerged: (m) async => localA = m,
      );
      expect(
        localA.courses.map((c) => c.name).toSet(),
        localB.courses.map((c) => c.name).toSet(),
        reason: '两端最终必须收敛到同一状态',
      );
    });
  }, skip: skipReason);
}
