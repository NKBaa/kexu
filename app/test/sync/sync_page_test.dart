import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/repositories/settings_repository.dart';
import 'package:course_timetable/data/sync/sync_config.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/sync/providers/sync_controller.dart';
import 'package:course_timetable/features/sync/sync_page.dart';
import 'package:course_timetable/features/sync/widgets/webdav_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存版设置仓储。
///
/// **为什么必须注入它**：`flutter_test` 运行在伪异步时钟下，真实文件 I/O 的
/// Future 不会完成（除非用 `tester.runAsync`）。若走默认的 `SettingsRepository`
/// （内部是 `path_provider` + `dart:io`），页面会永远停在 loading 态。
class InMemorySettingsRepository extends SettingsRepository {
  InMemorySettingsRepository([this.current = const AppSettings()]);

  AppSettings current;

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
  }
}

/// 固定帧数的推进，代替会挂死的 `pumpAndSettle`。
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 取出某个文案所在的按钮（`FilledButton.icon` 之类的工厂构造返回的是私有
/// 子类，`find.byType` 匹配不到，所以用 `bySubtype`）。
ButtonStyleButton _button(WidgetTester tester, String label) {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  );
  return tester.widget<ButtonStyleButton>(finder.first);
}

/// 同步状态桩：用于模拟「同步进行中」「有冲突」等状态。
class _FakeSyncStatusController extends SyncStatusController {
  _FakeSyncStatusController(this.initial);

  final SyncStatus initial;

  @override
  SyncStatus build() => initial;
}

/// 同步控制器桩：模拟测试连接失败。
class _FailingSyncController extends SyncController {
  _FailingSyncController(super.ref);

  @override
  Future<void> testConnection(SyncConfig config) async {
    throw const SyncException('鉴权失败：401 Unauthorized（坚果云请填应用密码）');
  }
}

const AppSettings _emptySettings = AppSettings();

/// 一份「已保存」的 WebDAV 配置：用于验证密钥回填与 URL 预览。
const AppSettings _savedWebdavSettings = AppSettings(
  syncConfig: SyncConfig(
    enabled: true,
    autoSync: true,
    backend: SyncBackend.webdav,
    deviceId: 'dev1234567890',
    webdav: WebDavConfig(
      url: 'https://dav.jianguoyun.com/dav/',
      username: 'me@example.com',
      password: 'jianguo-app-pass',
      remotePath: '/course_timetable/timetable.json',
    ),
  ),
);

Future<InMemorySettingsRepository> _pumpPage(
  WidgetTester tester, {
  AppSettings settings = _emptySettings,
  ThemeData? theme,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = InMemorySettingsRepository(settings);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        ...overrides,
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const SyncPage(),
      ),
    ),
  );
  await _settle(tester);
  return repo;
}

void main() {
  testWidgets('同步页能渲染：状态卡、开关、WebDAV 表单与操作按钮', (tester) async {
    await _pumpPage(tester);

    expect(find.text('同步状态'), findsOneWidget);
    expect(find.text('未启用'), findsOneWidget);
    expect(find.text('启用网盘同步'), findsOneWidget);
    expect(find.text('自动同步'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('立即同步'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
    expect(find.text('重置同步状态'), findsOneWidget);

    // 只提供 WebDAV 一种传输方式
    expect(find.byKey(webdavUrlFieldKey), findsOneWidget);
    expect(find.text('百度网盘'), findsNothing, reason: '百度网盘适配已移除');

    expect(tester.takeException(), isNull);
  });

  testWidgets('未启用同步时「自动同步」开关置灰', (tester) async {
    await _pumpPage(tester);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.length, 2);
    expect(switches[0].value, isFalse, reason: '默认不启用同步');
    expect(switches[1].onChanged, isNull, reason: 'enabled 关闭时自动同步应置灰');

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    final after = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(after[0].value, isTrue);
    expect(after[1].onChanged, isNotNull);
  });

  testWidgets('WebDAV 表单实时拼出完整远端 URL', (tester) async {
    await _pumpPage(tester);

    await tester.enterText(
      find.byKey(webdavUrlFieldKey),
      'https://dav.jianguoyun.com/dav',
    );
    await tester.pump();

    final preview = tester.widget<SelectableText>(find.byKey(webdavFullUrlTextKey));
    expect(
      preview.data,
      '完整远端 URL：https://dav.jianguoyun.com/dav/course_timetable/timetable.json',
      reason: '末尾缺少的斜杠应由 WebDavConfig.normalizedUrl 自动补齐',
    );

    await tester.enterText(
      find.byKey(webdavRemotePathFieldKey),
      '/timetable/课表.json',
    );
    await tester.pump();

    final preview2 = tester.widget<SelectableText>(find.byKey(webdavFullUrlTextKey));
    expect(
      preview2.data,
      contains('https://dav.jianguoyun.com/dav/timetable/%E8%AF%BE%E8%A1%A8.json'),
      reason: '中文路径应被逐段编码，同时保留 / 分隔符',
    );
  });

  testWidgets('密码字段默认遮蔽，已保存的值会回填且点眼睛后可见', (tester) async {
    await _pumpPage(tester, settings: _savedWebdavSettings);

    TextField passwordField() => tester.widget<TextField>(
          find.descendant(
            of: find.byKey(webdavPasswordFieldKey),
            matching: find.byType(TextField),
          ),
        );

    // 已保存的密钥以圆点回填，而不是被清空
    expect(passwordField().controller?.text, 'jianguo-app-pass');
    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byKey(webdavPasswordToggleKey));
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
    expect(passwordField().controller?.text, 'jianguo-app-pass');

    // 已保存的地址也应拼出完整 URL
    final preview = tester.widget<SelectableText>(find.byKey(webdavFullUrlTextKey));
    expect(
      preview.data,
      '完整远端 URL：https://dav.jianguoyun.com/dav/course_timetable/timetable.json',
    );
    expect(find.textContaining('应用密码'), findsWidgets);
  });

  testWidgets('改动后提示「有未保存的改动」，保存后落库', (tester) async {
    final repo = await _pumpPage(tester);

    expect(find.byKey(syncDirtyBannerKey), findsNothing);

    await tester.enterText(
      find.byKey(webdavUrlFieldKey),
      'https://dav.jianguoyun.com/dav/',
    );
    await tester.pump();

    expect(find.byKey(syncDirtyBannerKey), findsOneWidget);
    expect(find.text('有未保存的改动'), findsOneWidget);

    await tester.tap(find.text('保存配置'));
    await _settle(tester);

    expect(repo.current.syncConfig.webdav.url, 'https://dav.jianguoyun.com/dav/');
    expect(repo.current.syncConfig.backend, SyncBackend.webdav);
    expect(find.byKey(syncDirtyBannerKey), findsNothing);
    expect(find.text('同步配置已保存'), findsOneWidget);

    // 让 SnackBar 的计时器走完，避免测试结束时有未完成的定时器
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('同步进行中显示进度并禁用操作按钮', (tester) async {
    await _pumpPage(
      tester,
      overrides: [
        syncStatusProvider.overrideWith(
          () => _FakeSyncStatusController(const SyncStatus(running: true)),
        ),
      ],
    );

    expect(find.byKey(syncProgressKey), findsOneWidget);
    expect(find.text('同步中…'), findsWidgets);
    expect(_button(tester, '测试连接').onPressed, isNull);
    expect(_button(tester, '同步中…').onPressed, isNull);
    expect(_button(tester, '重置同步状态').onPressed, isNull);
  });

  testWidgets('存在冲突时用警示卡片列出，并说明已保留本机版本', (tester) async {
    await _pumpPage(
      tester,
      overrides: [
        syncStatusProvider.overrideWith(
          () => _FakeSyncStatusController(
            const SyncStatus(
              conflicts: ['高等数学：两端都修改了这门课（采用本机版本）'],
            ),
          ),
        ),
      ],
    );

    expect(find.byKey(syncConflictCardKey), findsOneWidget);
    expect(find.text('同步冲突（1）'), findsOneWidget);
    expect(find.textContaining('已保留本机版本'), findsOneWidget);
    expect(find.textContaining('高等数学'), findsOneWidget);
  });

  testWidgets('测试连接失败时显示红色错误卡片（SyncException.message）', (tester) async {
    await _pumpPage(
      tester,
      settings: _savedWebdavSettings,
      overrides: [
        syncControllerProvider.overrideWith((ref) => _FailingSyncController(ref)),
      ],
    );

    await tester.tap(find.text('测试连接'));
    await _settle(tester);

    expect(find.byKey(syncTestErrorKey), findsOneWidget);
    expect(
      find.textContaining('连接失败：鉴权失败：401 Unauthorized'),
      findsOneWidget,
    );
  });

  testWidgets('深色主题下可正常渲染', (tester) async {
    await _pumpPage(tester, theme: AppTheme.dark());

    expect(find.text('同步状态'), findsOneWidget);
    expect(find.byKey(webdavUrlFieldKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}


