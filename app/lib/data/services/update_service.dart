/// 在线更新服务：GitHub Releases 检查、镜像加速下载与安装。
///
/// 设计原则：
/// - **不依赖 UI**：只依赖 `http` / `path_provider` / `url_launcher` 与
///   Android 平台通道，方便单元测试直接注入 [http.Client]；
/// - **可注入**：所有网络方法都接受 `http.Client?`，测试用 `MockClient`
///   断言请求顺序（直连 → 镜像回退）；
/// - **失败可读**：统一抛 [UpdateException]，message 是可直接展示的中文。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../models/update_config.dart';

/// 更新目标平台。
enum UpdatePlatform {
  /// Android：优先 `.apk`。
  android,

  /// Windows：优先 `.exe`，其次 `.zip`。
  windows,

  /// 其它平台（暂不支持自动安装，只打开下载页）。
  other,
}

/// 当前运行平台。
UpdatePlatform currentUpdatePlatform() {
  if (Platform.isAndroid) return UpdatePlatform.android;
  if (Platform.isWindows) return UpdatePlatform.windows;
  return UpdatePlatform.other;
}

/// 解析后的版本号（语义化版本 + 可选构建号）。
///
/// 支持 `v1.1.0`、`1.1.0+2`、`v1.2.3-beta.1` 等写法。
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  /// 构建号（`+` 之后），没有则为 0。
  final int build;

  /// 预发布标记（`-` 之后），如 `beta.1`；空表示正式版。
  final String preRelease;

  const AppVersion(
    this.major,
    this.minor,
    this.patch, {
    this.build = 0,
    this.preRelease = '',
  });

  /// 宽松解析：容忍 `v` 前缀、前后空白与缺失的段（`1.2` → `1.2.0`）。
  static AppVersion parse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return const AppVersion(0, 0, 0);
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);

    var build = 0;
    final plus = s.indexOf('+');
    if (plus >= 0) {
      build = int.tryParse(s.substring(plus + 1).trim()) ?? 0;
      s = s.substring(0, plus);
    }

    var preRelease = '';
    final dash = s.indexOf('-');
    if (dash >= 0) {
      preRelease = s.substring(dash + 1).trim();
      s = s.substring(0, dash);
    }

    final parts = s.split('.');
    int at(int i) => i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) : 0;
    return AppVersion(at(0), at(1), at(2), build: build, preRelease: preRelease);
  }

  /// 是否预发布版（`1.2.0-beta` 这类）。
  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    var c = major.compareTo(other.major);
    if (c != 0) return c;
    c = minor.compareTo(other.minor);
    if (c != 0) return c;
    c = patch.compareTo(other.patch);
    if (c != 0) return c;
    // 同一版本号：正式版比预发布版新（1.0.0 > 1.0.0-beta）
    if (isPreRelease != other.isPreRelease) return isPreRelease ? -1 : 1;
    if (isPreRelease) {
      c = preRelease.compareTo(other.preRelease);
      if (c != 0) return c;
    }
    return build.compareTo(other.build);
  }

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build, preRelease);

  @override
  String toString() {
    final base = '$major.$minor.$patch${isPreRelease ? '-$preRelease' : ''}';
    return build > 0 ? '$base+$build' : base;
  }
}

/// [latest] 是否比 [current] 新；**相等不算更新**。
bool isNewerVersion(String latest, String current) {
  return AppVersion.parse(latest).compareTo(AppVersion.parse(current)) > 0;
}

/// Release 里的一个可下载资产。
class UpdateAsset {
  final String name;
  final String browserDownloadUrl;

  /// 字节数，0 表示未知。
  final int size;

  const UpdateAsset({
    required this.name,
    required this.browserDownloadUrl,
    this.size = 0,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> j) => UpdateAsset(
        name: (j['name'] ?? '').toString(),
        browserDownloadUrl: (j['browser_download_url'] ?? '').toString(),
        size: j['size'] is num ? (j['size'] as num).toInt() : 0,
      );

  /// 人类可读的文件大小，如 `12.3 MB`。
  String get sizeLabel {
    if (size <= 0) return '大小未知';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = size.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

/// GitHub Release 信息。
class ReleaseInfo {
  /// 发布标签，如 `v1.1.0`（版本比较时取它）。
  final String tagName;

  /// Release 标题。
  final String name;

  /// 更新说明（Markdown 原文）。
  final String body;

  /// 浏览器打开的 Release 页面地址。
  final String htmlUrl;

  /// 发布时间（ISO 字符串）。
  final String publishedAt;

  final List<UpdateAsset> assets;

  const ReleaseInfo({
    required this.tagName,
    this.name = '',
    this.body = '',
    this.htmlUrl = '',
    this.publishedAt = '',
    this.assets = const [],
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final rawAssets = j['assets'];
    final assets = <UpdateAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map) {
          assets.add(UpdateAsset.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return ReleaseInfo(
      tagName: (j['tag_name'] ?? j['name'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      htmlUrl: (j['html_url'] ?? '').toString(),
      publishedAt: (j['published_at'] ?? '').toString(),
      assets: assets,
    );
  }

  /// 标题或标签（界面优先显示标题）。
  String get displayName => name.trim().isEmpty ? tagName : name.trim();

  /// 发布时间的展示文本，如 `2026-10-01`。
  String get publishedLabel {
    final raw = publishedAt.trim();
    if (raw.isEmpty) return '发布时间未知';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

/// 按平台从资产列表里挑选最合适的安装包。
///
/// - Android：只认 `.apk`，多个时优先名字含 `android` / `arm64` 的；
/// - Windows：`.exe` 优先，其次 `.zip`，多个时优先名字含 `windows` / `win` 的；
/// - 其它平台：取第一个。
UpdateAsset? pickAssetForPlatform(
  List<UpdateAsset> assets,
  UpdatePlatform platform,
) {
  if (assets.isEmpty) return null;
  switch (platform) {
    case UpdatePlatform.android:
      final apks = assets
          .where((a) => a.name.toLowerCase().endsWith('.apk'))
          .toList(growable: false);
      if (apks.isEmpty) return null;
      return _preferNamed(apks, const ['android', 'arm64', 'universal']);
    case UpdatePlatform.windows:
      final exes = assets
          .where((a) => a.name.toLowerCase().endsWith('.exe'))
          .toList(growable: false);
      if (exes.isNotEmpty) {
        return _preferNamed(exes, const ['windows', 'win', 'setup', 'x64']);
      }
      final zips = assets
          .where((a) => a.name.toLowerCase().endsWith('.zip'))
          .toList(growable: false);
      if (zips.isNotEmpty) return _preferNamed(zips, const ['windows', 'win']);
      return null;
    case UpdatePlatform.other:
      return assets.first;
  }
}

UpdateAsset _preferNamed(List<UpdateAsset> candidates, List<String> keywords) {
  for (final keyword in keywords) {
    for (final asset in candidates) {
      if (asset.name.toLowerCase().contains(keyword)) return asset;
    }
  }
  return candidates.first;
}

/// 检查更新的结果。
class UpdateCheckResult {
  /// 当前版本（调用方传入）。
  final String currentVersion;

  /// 远端最新版本（Release 的 tag）。
  final String latestVersion;

  /// 是否有新版本（相等不算）。
  final bool updateAvailable;

  final ReleaseInfo release;

  /// 当前平台对应的安装包；没有匹配资产时为 null。
  final UpdateAsset? asset;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.release,
    this.asset,
  });
}

/// 安装结果（供 UI 提示）。
class InstallResult {
  /// 是否成功把安装动作交给系统。
  final bool success;

  /// 可直接展示给用户的中文说明。
  final String message;

  const InstallResult({
    required this.success,
    required this.message,
  });
}

/// 更新过程中的错误（配置缺失、网络异常、下载失败等），带可读中文说明。
class UpdateException implements Exception {
  final String message;

  /// 底层细节，便于排查（界面上折叠显示）。
  final String? detail;

  const UpdateException(this.message, {this.detail});

  @override
  String toString() {
    final d = detail;
    if (d == null || d.trim().isEmpty) return message;
    return '$message（$d）';
  }
}

/// 在线更新服务。
class UpdateService {
  UpdateService({http.Client? client}) : _defaultClient = client;

  /// 默认 HTTP 客户端（测试可注入；为 null 时按次创建并关闭）。
  final http.Client? _defaultClient;

  static const String _apiBase = 'https://api.github.com';

  // HTTP 头只允许 ASCII（Latin-1）字符，不能用中文 appName，否则
  // dart:io 会抛 `Invalid HTTP header field value`。
  static const String _userAgent = 'Kexu/$fullVersion';

  static const MethodChannel _channel =
      MethodChannel('com.coursetable.course_timetable/update');

  /// 检查 GitHub 上的最新 Release。
  ///
  /// 按 [UpdateConfig.apiPrefixes] 的顺序尝试（直连 → 能代理 API 的镜像），
  /// 全部失败才抛 [UpdateException]。
  Future<UpdateCheckResult> checkForUpdate({
    required UpdateConfig config,
    required String currentVersion,
    http.Client? client,
    UpdatePlatform? platform,
  }) async {
    if (!config.isConfigured) {
      throw const UpdateException(
        '还没有配置 GitHub 仓库，请先填写 owner/repo，例如 your-name/kexu。',
      );
    }
    final target = platform ?? currentUpdatePlatform();
    final prefixes = config.apiPrefixes;
    String? lastError;

    for (final prefix in prefixes) {
      final url = '$prefix$_apiBase/repos/${config.normalizedRepo}/releases/latest';
      final httpClient = client ?? _defaultClient ?? http.Client();
      final owned = client == null && _defaultClient == null;
      try {
        final response = await httpClient.get(
          Uri.parse(url),
          headers: <String, String>{
            'Accept': 'application/vnd.github+json',
            'User-Agent': _userAgent,
          },
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is! Map) {
            throw const UpdateException('GitHub 返回的数据格式无法识别。');
          }
          final release =
              ReleaseInfo.fromJson(Map<String, dynamic>.from(decoded));
          return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: release.tagName,
            updateAvailable: isNewerVersion(release.tagName, currentVersion),
            release: release,
            asset: pickAssetForPlatform(release.assets, target),
          );
        }
        lastError = response.statusCode == 404
            ? '仓库 ${config.normalizedRepo} 不存在，或还没有发布 Release'
            : 'HTTP ${response.statusCode}';
      } on UpdateException catch (e) {
        lastError = e.message;
      } catch (e) {
        lastError = _brief(e);
      } finally {
        if (owned) httpClient.close();
      }
    }

    throw UpdateException(
      '检查更新失败：无法连接 GitHub 或镜像，请检查网络后重试。',
      detail: lastError,
    );
  }

  /// 下载安装包到本地，返回下载好的文件。
  ///
  /// - 流式写入并回调进度 [onProgress]（total 未知时为 null）；
  /// - 镜像前缀按 [UpdateConfig.mirrorPrefixes] 顺序回退，下载失败换下一条线路；
  /// - Windows 存到「下载/课序更新」，Android 存到缓存目录 `updates/`
  ///   （与 `file_paths.xml` 的 FileProvider 映射一致）。
  Future<File> download({
    required ReleaseInfo release,
    required UpdateAsset asset,
    required UpdateConfig config,
    required void Function(int received, int? total) onProgress,
    http.Client? client,
    Directory? targetDir,
  }) async {
    if (asset.browserDownloadUrl.trim().isEmpty) {
      throw const UpdateException('这个 Release 没有可下载的安装包。');
    }
    final directory = targetDir ?? await _defaultDownloadDirectory();
    try {
      await directory.create(recursive: true);
    } catch (_) {
      // 目录已存在或创建失败时继续，写文件时会给出更具体的错误
    }
    final fileName = _safeFileName(asset.name);
    final prefixes = config.mirrorPrefixes;
    String? lastError;

    for (final prefix in prefixes) {
      final url = '$prefix${asset.browserDownloadUrl}';
      final httpClient = client ?? _defaultClient ?? http.Client();
      final owned = client == null && _defaultClient == null;
      final partFile = File(_join(directory.path, '$fileName.part'));
      IOSink? sink;
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers['User-Agent'] = _userAgent;
        final response = await httpClient
            .send(request)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          await response.stream.drain<void>();
          continue;
        }

        final output = partFile.openWrite();
        sink = output;
        final total = response.contentLength;
        var received = 0;
        await for (final chunk in response.stream) {
          output.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await output.flush();
        await output.close();
        sink = null;

        final target = File(_join(directory.path, fileName));
        if (await target.exists()) {
          try {
            await target.delete();
          } catch (_) {
            // 删不掉就尝试直接覆盖重命名
          }
        }
        final result = await partFile.rename(target.path);
        onProgress(received, total ?? received);
        return result;
      } catch (e) {
        lastError = _brief(e);
      } finally {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {
            // 忽略关闭失败
          }
        }
        try {
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {
          // 清理临时文件失败不影响结果
        }
        if (owned) httpClient.close();
      }
    }

    throw UpdateException(
      '下载失败：所有线路都不可用，请稍后重试或换一个镜像。',
      detail: lastError,
    );
  }

  /// 安装已下载的包。
  ///
  /// - Windows：`.exe` 直接启动安装程序；`.zip` 等打开所在目录让用户手动处理；
  /// - Android：走 MethodChannel 的 `installApk`（FileProvider + ACTION_VIEW），
  ///   原生层不可用时降级为浏览器打开 Release 页面。
  Future<InstallResult> install(File file, {required ReleaseInfo release}) async {
    if (!await file.exists()) {
      throw UpdateException('安装包不存在，可能已被系统清理：${file.path}');
    }

    if (Platform.isWindows) {
      try {
        if (file.path.toLowerCase().endsWith('.exe')) {
          await Process.start(
            file.path,
            const <String>[],
            mode: ProcessStartMode.detached,
          );
          return const InstallResult(
            success: true,
            message: '已启动安装程序，请按提示完成安装。',
          );
        }
        await Process.start(
          'explorer.exe',
          <String>['/select,', file.path],
          mode: ProcessStartMode.detached,
        );
        return const InstallResult(
          success: true,
          message: '已打开安装包所在文件夹，请解压后运行。',
        );
      } catch (e) {
        throw UpdateException(
          '无法启动安装程序，请手动打开下载目录运行。',
          detail: _brief(e),
        );
      }
    }

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('installApk', <String, dynamic>{
          'path': file.path,
        });
        return const InstallResult(
          success: true,
          message: '已打开系统安装界面，请按提示完成安装。',
        );
      } on PlatformException catch (e) {
        final reason = (e.message ?? '').trim();
        final opened = await openReleasePage(release);
        return InstallResult(
          success: false,
          message: opened
              ? '无法直接安装${reason.isEmpty ? '' : '（$reason）'}，已用浏览器打开下载页，可手动下载安装。'
              : '无法直接安装${reason.isEmpty ? '' : '（$reason）'}，请到 GitHub 下载页手动安装。',
        );
      } on MissingPluginException {
        final opened = await openReleasePage(release);
        return InstallResult(
          success: false,
          message: opened
              ? '当前环境不支持直接安装，已用浏览器打开下载页。'
              : '当前环境不支持直接安装，请到 GitHub 下载页手动安装。',
        );
      }
    }

    final opened = await openReleasePage(release);
    return InstallResult(
      success: false,
      message: opened ? '当前平台不支持自动安装，已用浏览器打开下载页。' : '当前平台不支持自动安装。',
    );
  }

  /// 在资源管理器里定位文件（Windows 的「打开下载目录」）。
  Future<void> revealFile(File file) async {
    try {
      if (Platform.isWindows) {
        await Process.start(
          'explorer.exe',
          <String>['/select,', file.path],
          mode: ProcessStartMode.detached,
        );
        return;
      }
      final dir = file.parent;
      if (Platform.isMacOS) {
        await Process.start('open', <String>[dir.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', <String>[dir.path]);
      }
    } catch (e) {
      throw UpdateException('无法打开下载目录。', detail: _brief(e));
    }
  }

  /// 用浏览器打开 Release 页面；返回是否成功唤起浏览器。
  Future<bool> openReleasePage(ReleaseInfo release) async {
    final url = release.htmlUrl.trim();
    if (url.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// 清理已经安装过的旧安装包。
  ///
  /// 文件名里带版本号（如 `kexu-v1.1.51.apk`），只删除版本 <= 当前 App 版本的文件；
  /// 比当前版本新的安装包（刚下载还没安装）会保留，避免用户重启后又要重新下载。
  /// 同时清掉中断下载留下的 `.part` 临时文件。
  Future<int> cleanupOldInstallers({
    required String currentVersion,
    Directory? targetDir,
  }) async {
    final directory = targetDir ?? await _defaultDownloadDirectory();
    if (!await directory.exists()) return 0;

    final current = _versionParts(currentVersion);
    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      final lower = name.toLowerCase();
      final isPart = lower.endsWith('.part');
      final isInstaller = lower.endsWith('.apk') ||
          lower.endsWith('.exe') ||
          lower.endsWith('.zip') ||
          lower.endsWith('.msi');
      if (!isPart && !isInstaller) continue;

      var shouldDelete = isPart;
      if (!shouldDelete && current != null) {
        final fileVersion = _versionParts(name);
        if (fileVersion != null) {
          shouldDelete = _compareVersion(fileVersion, current) <= 0;
        }
      }
      if (!shouldDelete) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // 文件被系统占用时忽略，下次启动再试。
      }
    }
    return removed;
  }

  static List<int>? _versionParts(String text) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
    if (m == null) return null;
    return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
  }

  static int _compareVersion(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }

  /// 默认下载目录。
  Future<Directory> _defaultDownloadDirectory() async {
    if (Platform.isAndroid) {
      final tmp = await getTemporaryDirectory();
      return Directory(_join(tmp.path, 'updates'));
    }
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    return Directory(_join(base.path, '课序更新'));
  }
}

String _join(String base, String name) {
  if (base.endsWith('/') || base.endsWith(r'\')) return '$base$name';
  return '$base${Platform.pathSeparator}$name';
}

/// 文件名清洗：去掉路径分隔符与 Windows 非法字符，避免写到目录外。
String _safeFileName(String raw) {
  var name = raw.trim();
  if (name.isEmpty) name = 'update.bin';
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (name.length > 120) {
    name = name.substring(name.length - 120);
  }
  return name;
}

String _brief(Object error) {
  final text = error.toString().replaceAll('\n', ' ').trim();
  if (text.length <= 160) return text;
  return '${text.substring(0, 160)}…';
}
