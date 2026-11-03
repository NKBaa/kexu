import 'dart:io';

import 'package:course_timetable/core/app_info.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/update_config.dart';
import 'package:course_timetable/data/services/update_service.dart';
import 'package:course_timetable/features/settings/pages/update_settings_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 内存版设置 controller：不碰磁盘，方便 widget 测试。
class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this.current);

  AppSettings current;

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
    state = AsyncData(settings);
  }
}

/// 假更新服务：只实现页面用到的检查接口。
class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({this.result, this.error});

  UpdateCheckResult? result;
  Object? error;

  int checkCalls = 0;
  int downloadCalls = 0;
  int installCalls = 0;
  UpdateConfig? lastConfig;
  String? lastCurrentVersion;

  @override
  Future<UpdateCheckResult> checkForUpdate({
    required UpdateConfig config,
    required String currentVersion,
    http.Client? client,
    UpdatePlatform? platform,
  }) async {
    checkCalls++;
    lastConfig = config;
    lastCurrentVersion = currentVersion;
    final e = error;
    if (e != null) throw e;
    return result!;
  }

  @override
  Future<File> download({
    required ReleaseInfo release,
    required UpdateAsset asset,
    required UpdateConfig config,
    required void Function(int received, int? total) onProgress,
    http.Client? client,
    Directory? targetDir,
  }) async {
    downloadCalls++;
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}kexu-auto-install-test.apk',
    );
    onProgress(3, 3);
    return file;
  }

  @override
  Future<InstallResult> install(File file, {required ReleaseInfo release}) async {
    installCalls++;
    return const InstallResult(success: true, message: '已打开系统安装界面');
  }
}

UpdateCheckResult _upToDateResult() => UpdateCheckResult(
      currentVersion: fullVersion,
      latestVersion: fullVersion,
      updateAvailable: false,
      release: const ReleaseInfo(
        tagName: '1.1.0+2',
        htmlUrl: 'https://github.com/owner/repo/releases',
      ),
    );

UpdateCheckResult _newVersionResult() {
  const asset = UpdateAsset(
    name: 'kexu-v1.2.0-android.apk',
    browserDownloadUrl: 'https://example.com/kexu-v1.2.0-android.apk',
    size: 12 * 1024 * 1024,
  );
  return const UpdateCheckResult(
    currentVersion: '1.1.0+2',
    latestVersion: 'v1.2.0',
    updateAvailable: true,
    release: ReleaseInfo(
      tagName: 'v1.2.0',
      name: '课序 v1.2.0',
      body: '## 更新内容\n- 支持在线更新与国内镜像加速\n- 修复若干问题',
      htmlUrl: 'https://github.com/owner/repo/releases/tag/v1.2.0',
      publishedAt: '2026-10-01T08:30:00Z',
      assets: [asset],
    ),
    asset: asset,
  );
}

Widget _wrap(_FakeSettingsController settings, UpdateService service) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => settings),
      updateServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const UpdateSettingsPage(),
    ),
  );
}

void _bigWindow(WidgetTester tester, {double w = 1400, double h = 2400}) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('未配置仓库时展示引导，且不会发起检查', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: '')),
    );
    final service = _FakeUpdateService();

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    expect(find.byKey(updateUnconfiguredGuideKey), findsOneWidget);
    expect(find.textContaining('仓库地址被清空'), findsWidgets);

    // 未配置时「检查更新」按钮应禁用，避免用户点了只看到错误
    final button = tester.widget<FilledButton>(find.byKey(updateCheckButtonKey));
    expect(button.onPressed, isNull);
    expect(service.checkCalls, 0);
  });

  testWidgets('已是最新版本时给出明确提示', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: 'owner/repo')),
    );
    final service = _FakeUpdateService(result: _upToDateResult());

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(updateCheckButtonKey));
    await tester.pumpAndSettle();

    expect(service.checkCalls, 1);
    expect(service.lastConfig?.repo, 'owner/repo');
    expect(service.lastCurrentVersion, fullVersion);
    expect(find.byKey(updateResultCardKey), findsOneWidget);
    expect(find.textContaining('已是最新版本'), findsOneWidget);
    // 检查时间会被写回设置，下次打开页面能看到
    expect(settings.current.updateConfig.lastCheckedAt, isNotEmpty);
  });

  testWidgets('发现新版本时展示版本号、发布时间与更新说明', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: 'owner/repo')),
    );
    final service = _FakeUpdateService(result: _newVersionResult());

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(updateCheckButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(updateResultCardKey), findsOneWidget);
    expect(find.textContaining('发现新版本 v1.2.0'), findsOneWidget);
    expect(find.textContaining('2026-10-01'), findsOneWidget);
    expect(find.textContaining('支持在线更新与国内镜像加速'), findsOneWidget);
    expect(find.textContaining('kexu-v1.2.0-android.apk'), findsOneWidget);
    expect(find.byKey(updateDownloadButtonKey), findsOneWidget);
    expect(find.byKey(updateOpenGithubButtonKey), findsOneWidget);
  });

  testWidgets('下载完成后自动请求安装，不需要再点安装按钮', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: 'owner/repo')),
    );
    final service = _FakeUpdateService(result: _newVersionResult());

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(updateCheckButtonKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(updateDownloadButtonKey));
    await tester.tap(find.byKey(updateDownloadButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.downloadCalls, 1);
    expect(service.installCalls, 1);
    expect(find.text('已打开系统安装界面'), findsOneWidget);
  });

  testWidgets('忽略此版本会把版本号写进设置，并清掉结果卡', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: 'owner/repo')),
    );
    final service = _FakeUpdateService(result: _newVersionResult());

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(updateCheckButtonKey));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(updateIgnoreButtonKey));
    await tester.tap(find.byKey(updateIgnoreButtonKey));
    await tester.pumpAndSettle();

    expect(settings.current.updateConfig.ignoredVersion, 'v1.2.0');
    expect(find.byKey(updateResultCardKey), findsNothing);
    expect(find.textContaining('已忽略版本'), findsOneWidget);
  });

  testWidgets('检查失败时展示中文错误并可重试', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: 'owner/repo')),
    );
    final service = _FakeUpdateService(
      error: const UpdateException('检查更新失败：网络不可用', detail: 'HTTP 500'),
    );

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(updateCheckButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(updateErrorCardKey), findsOneWidget);
    expect(find.textContaining('检查更新失败：网络不可用'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 重试会再次调用服务
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(service.checkCalls, 2);
  });

  testWidgets('镜像下拉改动会立即保存到设置', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(
      const AppSettings(updateConfig: UpdateConfig(repo: 'owner/repo')),
    );
    final service = _FakeUpdateService();

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(updateMirrorDropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ghfast.top').last);
    await tester.pumpAndSettle();

    expect(settings.current.updateConfig.mirrorMode, 'preset');
    expect(settings.current.updateConfig.mirrorPresetId, 'ghfast');
  });

  testWidgets('仓库输入框提交后保存到设置', (tester) async {
    _bigWindow(tester);
    final settings = _FakeSettingsController(const AppSettings());
    final service = _FakeUpdateService();

    await tester.pumpWidget(_wrap(settings, service));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(updateRepoFieldKey), 'someone/kexu');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(settings.current.updateConfig.repo, 'someone/kexu');
  });
}
