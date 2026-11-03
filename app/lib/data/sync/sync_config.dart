/// 网盘同步的配置模型。
///
/// 传输层是可替换的（WebDAV / 百度网盘 / 未来其它网盘），
/// 但同步语义完全一致：把整份课表 JSON 作为文档读取/写入远端。
library;

import 'dart:math';

/// 支持的网盘后端。
enum SyncBackend {
  /// 通用 WebDAV：坚果云、Nextcloud、群晖、InfiniCLOUD 等。
  webdav,
}

SyncBackend syncBackendFromId(String? id) => SyncBackend.webdav;

String syncBackendLabel(SyncBackend b) {
  switch (b) {
    case SyncBackend.webdav:
      return 'WebDAV';
  }
}

/// WebDAV 连接参数。
class WebDavConfig {
  /// 服务器地址，如 `https://dav.jianguoyun.com/dav/`。
  final String url;

  final String username;

  /// 坚果云等使用「应用密码」，不是登录密码。
  final String password;

  /// 远端文件路径（相对 WebDAV 根），如 `/课表/timetable.json`。
  final String remotePath;

  const WebDavConfig({
    this.url = '',
    this.username = '',
    this.password = '',
    this.remotePath = '/course_timetable/timetable.json',
  });

  bool get isConfigured => url.trim().isNotEmpty && remotePath.trim().isNotEmpty;

  String get normalizedUrl {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (!u.endsWith('/')) u = '$u/';
    return u;
  }

  /// 拼出远端文件的完整 URL（对路径做编码，保留分隔符）。
  String get remoteFileUrl {
    final base = normalizedUrl;
    if (base.isEmpty) return '';
    final p = remotePath.trim().replaceFirst(RegExp(r'^/+'), '');
    final encoded = p.split('/').map(Uri.encodeComponent).join('/');
    return '$base$encoded';
  }

  /// 远端父目录 URL（WebDAV 的 MKCOL 需要逐级创建）。
  String get remoteDirUrl {
    final base = normalizedUrl;
    if (base.isEmpty) return '';
    final p = remotePath.trim().replaceFirst(RegExp(r'^/+'), '');
    final idx = p.lastIndexOf('/');
    if (idx < 0) return base;
    final dir = p.substring(0, idx);
    if (dir.isEmpty) return base;
    final encoded = dir.split('/').map(Uri.encodeComponent).join('/');
    return '$base$encoded/';
  }

  WebDavConfig copyWith({
    String? url,
    String? username,
    String? password,
    String? remotePath,
  }) =>
      WebDavConfig(
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
        remotePath: remotePath ?? this.remotePath,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'remotePath': remotePath,
      };

  static WebDavConfig fromJson(Map<String, dynamic> j) => WebDavConfig(
        url: (j['url'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        remotePath: (j['remotePath'] ?? '/course_timetable/timetable.json').toString(),
      );
}

/// 同步总配置。
class SyncConfig {
  /// 是否启用同步。
  final bool enabled;

  /// 是否在课表变更后自动上传、启动时自动拉取。
  final bool autoSync;

  final SyncBackend backend;

  /// 本机标识，用于冲突时区分「哪台设备改的」。
  final String deviceId;

  final WebDavConfig webdav;

  /// 上次成功同步的时间（毫秒），0 表示从未同步。
  final int lastSyncAtMs;

  const SyncConfig({
    this.enabled = false,
    this.autoSync = true,
    this.backend = SyncBackend.webdav,
    this.deviceId = '',
    this.webdav = const WebDavConfig(),
    this.lastSyncAtMs = 0,
  });

  /// 当前后端是否填够了必需信息。
  bool get isConfigured {
    switch (backend) {
      case SyncBackend.webdav:
        return webdav.isConfigured;
    }
  }

  /// 是否真的会执行同步。
  bool get isActive => enabled && isConfigured;

  String get lastSyncLabel {
    if (lastSyncAtMs <= 0) return '从未同步';
    final d = DateTime.fromMillisecondsSinceEpoch(lastSyncAtMs);
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return '刚刚同步';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前同步';
    if (diff.inHours < 24) return '${diff.inHours} 小时前同步';
    return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)} 同步';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  SyncConfig copyWith({
    bool? enabled,
    bool? autoSync,
    SyncBackend? backend,
    String? deviceId,
    WebDavConfig? webdav,
    int? lastSyncAtMs,
  }) =>
      SyncConfig(
        enabled: enabled ?? this.enabled,
        autoSync: autoSync ?? this.autoSync,
        backend: backend ?? this.backend,
        deviceId: deviceId ?? this.deviceId,
        webdav: webdav ?? this.webdav,
        lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'autoSync': autoSync,
        'backend': backend.name,
        'deviceId': deviceId,
        'webdav': webdav.toJson(),
        'lastSyncAtMs': lastSyncAtMs,
      };

  static SyncConfig fromJson(Map<String, dynamic> j) => SyncConfig(
        enabled: j['enabled'] == true,
        autoSync: j['autoSync'] is bool ? j['autoSync'] as bool : true,
        backend: syncBackendFromId((j['backend'] ?? '').toString()),
        deviceId: (j['deviceId'] ?? '').toString(),
        webdav: j['webdav'] is Map
            ? WebDavConfig.fromJson(Map<String, dynamic>.from(j['webdav'] as Map))
            : const WebDavConfig(),
        lastSyncAtMs: j['lastSyncAtMs'] is num ? (j['lastSyncAtMs'] as num).toInt() : 0,
      );

  /// 生成一个设备标识（首次启用同步时调用）。
  static String newDeviceId() {
    final r = Random();
    final alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buf = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buf.write(alphabet[r.nextInt(alphabet.length)]);
    }
    return buf.toString();
  }
}

/// 同步过程中的错误（配置缺失、鉴权失败、网络异常等），带可读中文说明。
class SyncException implements Exception {
  final String message;

  /// 底层细节，便于排查（界面上折叠显示）。
  final String? detail;

  const SyncException(this.message, {this.detail});

  @override
  String toString() => detail == null ? message : '$message（$detail）';
}
