import 'dart:convert';
import 'dart:io';

import 'package:course_timetable/data/models/update_config.dart';
import 'package:course_timetable/data/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 构造一个 UTF-8 的 JSON 响应（避免中文乱码）。
http.Response _jsonResponse(Object body, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

const _repoConfig = UpdateConfig(repo: 'owner/repo');

Map<String, dynamic> _releaseJson({
  String tag = 'v1.2.0',
  List<Map<String, dynamic>>? assets,
}) =>
    <String, dynamic>{
      'tag_name': tag,
      'name': '课序 $tag',
      'body': '## 更新内容\n- 支持在线更新\n- 修复若干问题',
      'html_url': 'https://github.com/owner/repo/releases/tag/$tag',
      'published_at': '2026-10-01T08:30:00Z',
      'assets': assets ??
          <Map<String, dynamic>>[
            {
              'name': 'kexu-$tag-android.apk',
              'browser_download_url':
                  'https://github.com/owner/repo/releases/download/$tag/kexu-$tag-android.apk',
              'size': 12 * 1024 * 1024,
              'content_type': 'application/vnd.android.package-archive',
            },
            {
              'name': 'kexu-$tag-windows.exe',
              'browser_download_url':
                  'https://github.com/owner/repo/releases/download/$tag/kexu-$tag-windows.exe',
              'size': 30 * 1024 * 1024,
              'content_type': 'application/octet-stream',
            },
          ],
    };

UpdateAsset _asset(String name, {String url = ''}) => UpdateAsset(
      name: name,
      browserDownloadUrl:
          url.isEmpty ? 'https://github.com/o/r/releases/download/v1/$name' : url,
      size: 1024,
    );

void main() {
  group('版本解析与比较', () {
    test('parse 支持 v 前缀、构建号与预发布标记', () {
      final v1 = AppVersion.parse('v1.1.0');
      expect(v1, const AppVersion(1, 1, 0));
      expect(v1.toString(), '1.1.0');

      final v2 = AppVersion.parse('1.1.0+2');
      expect(v2.build, 2);
      expect(v2.toString(), '1.1.0+2');

      final v3 = AppVersion.parse('v1.2.3-beta.1');
      expect(v3.preRelease, 'beta.1');
      expect(v3.isPreRelease, isTrue);

      // 宽松解析：段数不足按 0 补
      expect(AppVersion.parse('1.2'), const AppVersion(1, 2, 0));
      expect(AppVersion.parse(''), const AppVersion(0, 0, 0));
    });

    test('isNewerVersion：带 v 前缀、构建号、相等与降级', () {
      expect(isNewerVersion('v1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('1.2.0', 'v1.1.0+2'), isTrue);
      expect(isNewerVersion('1.1.0+3', '1.1.0+2'), isTrue);
      // 相等不算更新
      expect(isNewerVersion('1.1.0+2', '1.1.0+2'), isFalse);
      expect(isNewerVersion('v1.1.0', '1.1.0'), isFalse);
      // 降级不算更新
      expect(isNewerVersion('1.0.0', '1.1.0'), isFalse);
      // 预发布版比同版本正式版旧
      expect(isNewerVersion('1.0.0-beta.1', '1.0.0'), isFalse);
      expect(isNewerVersion('v1.0.0', '1.0.0-beta.1'), isTrue);
    });

    test('资产大小展示为可读单位', () {
      expect(_asset('a.apk').sizeLabel, '1.0 KB');
      expect(
        const UpdateAsset(name: 'b.apk', browserDownloadUrl: '', size: 0).sizeLabel,
        '大小未知',
      );
    });
  });

  group('平台资产选择', () {
    test('Android 优先 .apk，多个时优先名字含 android 的', () {
      final assets = <UpdateAsset>[
        _asset('kexu-windows.exe'),
        _asset('kexu-ios.ipa'),
        _asset('kexu.apk'),
        _asset('kexu-android.apk'),
      ];
      expect(pickAssetForPlatform(assets, UpdatePlatform.android)?.name,
          'kexu-android.apk');
      expect(pickAssetForPlatform(assets, UpdatePlatform.windows)?.name,
          'kexu-windows.exe');
      // 只有 .apk 之外的文件时返回 null（界面提示去 GitHub 手动下载）
      expect(
        pickAssetForPlatform(
          <UpdateAsset>[_asset('kexu-windows.exe')],
          UpdatePlatform.android,
        ),
        isNull,
      );
    });

    test('Windows 优先 .exe，其次 .zip；都没有则 null', () {
      final exeAndZip = <UpdateAsset>[
        _asset('kexu.zip'),
        _asset('kexu-setup.exe'),
      ];
      expect(pickAssetForPlatform(exeAndZip, UpdatePlatform.windows)?.name,
          'kexu-setup.exe');

      final onlyZip = <UpdateAsset>[_asset('kexu-windows.zip')];
      expect(pickAssetForPlatform(onlyZip, UpdatePlatform.windows)?.name,
          'kexu-windows.zip');

      final neither = <UpdateAsset>[_asset('kexu.apk')];
      expect(pickAssetForPlatform(neither, UpdatePlatform.windows), isNull);
    });

    test('ReleaseInfo.fromJson 解析字段并按平台取资产', () {
      final release = ReleaseInfo.fromJson(_releaseJson());
      expect(release.tagName, 'v1.2.0');
      expect(release.name, '课序 v1.2.0');
      expect(release.body, contains('支持在线更新'));
      expect(release.htmlUrl, contains('/releases/tag/v1.2.0'));
      expect(release.publishedLabel, '2026-10-01');
      expect(release.assets.length, 2);
      expect(pickAssetForPlatform(release.assets, UpdatePlatform.android)?.name,
          'kexu-v1.2.0-android.apk');
      expect(pickAssetForPlatform(release.assets, UpdatePlatform.windows)?.name,
          'kexu-v1.2.0-windows.exe');
    });
  });

  group('checkForUpdate', () {
    test('请求 GitHub API 并解析出可更新版本', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _jsonResponse(_releaseJson());
      });
      final service = UpdateService();
      final result = await service.checkForUpdate(
        config: _repoConfig,
        currentVersion: '1.1.0+2',
        client: client,
        platform: UpdatePlatform.android,
      );

      expect(captured.method, 'GET');
      expect(
        captured.url.toString(),
        'https://api.github.com/repos/owner/repo/releases/latest',
      );
      expect(captured.headers['Accept'], 'application/vnd.github+json');
      final userAgent = captured.headers['User-Agent']!;
      expect(userAgent, startsWith('Kexu/'));
      // dart:io 只允许 ASCII/Latin-1 头，中文会抛 FormatException。
      expect(userAgent.codeUnits.every((c) => c < 128), isTrue);

      expect(result.currentVersion, '1.1.0+2');
      expect(result.latestVersion, 'v1.2.0');
      expect(result.updateAvailable, isTrue);
      expect(result.release.body, contains('在线更新'));
      expect(result.asset?.name, 'kexu-v1.2.0-android.apk');
    });

    test('版本相同不算更新', () async {
      final client = MockClient((request) async {
        return _jsonResponse(_releaseJson(tag: 'v1.1.0'));
      });
      final result = await UpdateService().checkForUpdate(
        config: _repoConfig,
        currentVersion: '1.1.0',
        client: client,
        platform: UpdatePlatform.android,
      );
      expect(result.updateAvailable, isFalse);
    });

    test('auto 模式按「直连 → 可代理 API 的镜像」顺序回退', () async {
      final urls = <String>[];
      final client = MockClient((request) async {
        urls.add(request.url.toString());
        if (urls.length == 1) return http.Response('boom', 500);
        return _jsonResponse(_releaseJson());
      });
      final result = await UpdateService().checkForUpdate(
        config: const UpdateConfig(repo: 'owner/repo'), // auto
        currentVersion: '1.1.0',
        client: client,
      );
      expect(result.updateAvailable, isTrue);
      expect(urls, <String>[
        'https://api.github.com/repos/owner/repo/releases/latest',
        'https://gh-proxy.com/https://api.github.com/repos/owner/repo/releases/latest',
      ]);
    });

    test('preset 选了只能下载的镜像时，API 检查仍能回退到可用镜像', () async {
      // ghfast.top 对 api.github.com 返回 403、直连也失败，
      // 最后通过 gh-proxy.com 的 API 代理成功 —— 不能因为下载选了 ghfast 就永远检查失败。
      final urls = <String>[];
      final client = MockClient((request) async {
        urls.add(request.url.toString());
        if (request.url.host == 'ghfast.top' || request.url.host == 'api.github.com') {
          return http.Response('forbidden', 403);
        }
        return _jsonResponse(_releaseJson());
      });
      final result = await UpdateService().checkForUpdate(
        config: const UpdateConfig(
          repo: 'owner/repo',
          mirrorMode: 'preset',
          mirrorPresetId: 'ghfast',
        ),
        currentVersion: '1.1.0',
        client: client,
      );
      expect(result.updateAvailable, isTrue);
      expect(urls, <String>[
        'https://ghfast.top/https://api.github.com/repos/owner/repo/releases/latest',
        'https://api.github.com/repos/owner/repo/releases/latest',
        'https://gh-proxy.com/https://api.github.com/repos/owner/repo/releases/latest',
      ]);
    });

    test('direct 模式只请求直连，不会走镜像', () async {
      final urls = <String>[];
      final client = MockClient((request) async {
        urls.add(request.url.toString());
        return http.Response('not found', 404);
      });
      await expectLater(
        UpdateService().checkForUpdate(
          config: const UpdateConfig(repo: 'owner/repo', mirrorMode: 'direct'),
          currentVersion: '1.1.0',
          client: client,
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(urls, <String>[
        'https://api.github.com/repos/owner/repo/releases/latest',
      ]);
    });

    test('全部失败时抛中文 UpdateException，detail 含最后一次错误', () async {
      final client = MockClient((request) async => http.Response('boom', 500));
      await expectLater(
        UpdateService().checkForUpdate(
          config: _repoConfig,
          currentVersion: '1.1.0',
          client: client,
        ),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.message, 'message', contains('检查更新失败'))
              .having((e) => e.detail, 'detail', contains('HTTP 500')),
        ),
      );
    });

    test('未配置仓库时不发请求，直接抛中文错误', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return _jsonResponse(_releaseJson());
      });
      await expectLater(
        UpdateService().checkForUpdate(
          config: const UpdateConfig(repo: ''),
          currentVersion: '1.1.0',
          client: client,
        ),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.message, 'message', contains('GitHub 仓库')),
        ),
      );
      expect(called, isFalse);
    });

    test('当前平台没有匹配资产时 asset 为 null（界面会引导去 GitHub）', () async {
      final client = MockClient((request) async {
        return _jsonResponse(_releaseJson(assets: <Map<String, dynamic>>[
          {
            'name': 'kexu-windows.exe',
            'browser_download_url': 'https://example.com/kexu-windows.exe',
            'size': 100,
          },
        ]));
      });
      final result = await UpdateService().checkForUpdate(
        config: _repoConfig,
        currentVersion: '1.1.0',
        client: client,
        platform: UpdatePlatform.android,
      );
      expect(result.asset, isNull);
      expect(result.updateAvailable, isTrue);
    });
  });

  group('download', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kexu_update_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('流式下载并回调进度，写入指定目录', () async {
      const content = 'hello update payload';
      final client = MockClient((request) async {
        return http.Response(content, 200);
      });
      final asset = _asset('kexu-android.apk');
      final release = ReleaseInfo.fromJson(_releaseJson());
      final progress = <int>[];

      final file = await UpdateService().download(
        release: release,
        asset: asset,
        config: _repoConfig,
        onProgress: (received, total) => progress.add(received),
        client: client,
        targetDir: tempDir,
      );

      expect(await file.exists(), isTrue);
      expect(file.path, endsWith('kexu-android.apk'));
      expect(await file.readAsString(), content);
      expect(progress, isNotEmpty);
      expect(progress.last, content.length);
    });

    test('直连失败后自动换镜像重试', () async {
      final urls = <String>[];
      final client = MockClient((request) async {
        urls.add(request.url.toString());
        if (urls.length == 1) return http.Response('boom', 500);
        return http.Response('mirror ok', 200);
      });
      final file = await UpdateService().download(
        release: ReleaseInfo.fromJson(_releaseJson()),
        asset: _asset('kexu.apk'),
        config: _repoConfig,
        onProgress: (_, _) {},
        client: client,
        targetDir: tempDir,
      );
      expect(await file.readAsString(), 'mirror ok');
      expect(urls.length, 2);
      expect(urls.first, 'https://github.com/o/r/releases/download/v1/kexu.apk');
      expect(
        urls.last,
        'https://ghfast.top/https://github.com/o/r/releases/download/v1/kexu.apk',
      );
    });

    test('所有线路失败时抛中文 UpdateException，不留下 .part 残留', () async {
      final client = MockClient((request) async => http.Response('boom', 503));
      await expectLater(
        UpdateService().download(
          release: ReleaseInfo.fromJson(_releaseJson()),
          asset: _asset('kexu.apk'),
          config: _repoConfig,
          onProgress: (_, _) {},
          client: client,
          targetDir: tempDir,
        ),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.message, 'message', contains('下载失败')),
        ),
      );
      final leftovers = tempDir.listSync().map((e) => e.path).toList();
      expect(leftovers, isEmpty, reason: '失败后不应留下 .part 临时文件');
    });

    test('文件名里的路径分隔符会被清洗，避免写出目录', () async {
      final client = MockClient((request) async => http.Response('ok', 200));
      final file = await UpdateService().download(
        release: ReleaseInfo.fromJson(_releaseJson()),
        asset: _asset('kexu/evil.apk'),
        config: _repoConfig,
        onProgress: (_, _) {},
        client: client,
        targetDir: tempDir,
      );
      // 分隔符被替换成下划线：文件仍然落在 tempDir 里，不会跑到子目录
      expect(file.parent.path, tempDir.path);
      expect(file.uri.pathSegments.last, 'kexu_evil.apk');
    });
  });

  group('cleanupOldInstallers', () {
    test('只删除当前及更旧版本，保留未安装的新版本', () async {
      final dir = await Directory.systemTemp.createTemp('kexu_cleanup_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      for (final name in [
        'kexu-v1.1.50.apk',
        'kexu-v1.1.51.apk',
        'kexu-v1.1.52.apk',
        'random.apk',
        'kexu-v1.1.52.apk.part',
      ]) {
        await File('${dir.path}${Platform.pathSeparator}$name')
            .writeAsString('x');
      }

      final removed = await UpdateService().cleanupOldInstallers(
        currentVersion: '1.1.51',
        targetDir: dir,
      );

      expect(removed, 3); // 1.1.50、1.1.51、.part
      final left = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(left, {'kexu-v1.1.52.apk', 'random.apk'});
    });
  });
}
