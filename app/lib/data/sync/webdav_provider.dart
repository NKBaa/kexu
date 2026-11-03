import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'sync_config.dart';
import 'sync_provider.dart';

/// WebDAV 传输层实现（坚果云 / Nextcloud / 群晖 / InfiniCLOUD 等通用）。
///
/// 只负责三件事：测连通性、读文档、写文档；合并与冲突处理全在 SyncEngine，
/// 与具体网盘无关。
///
/// 协议要点：
/// * 所有请求带 HTTP Basic 认证（用户名与密码都为空时不带）；
/// * 读取时先 `PROPFIND`（`Depth: 1`）拿 `getlastmodified` / `getetag`，
///   再 `GET` 取正文 —— 这样版本标记与修改时间都能拿到；
/// * 写入时对父目录逐级 `MKCOL`（目录已存在时服务器返回 405，视为成功），
///   因为 `PUT` 不会自动创建中间目录；
/// * 响应一律按 `bodyBytes` + `utf8.decode(allowMalformed: true)` 解码，
///   避免中文课表名乱码。
///
/// 所有失败都抛 [SyncException]，`message` 为可操作的中文提示。
class WebDavProvider implements SyncProvider {
  /// [config] 为连接参数；[httpClient] 仅用于测试注入（如 MockClient），
  /// 不传时内部自建并在 [dispose] 时关闭。
  WebDavProvider({required this.config, http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  /// 连接参数（URL、凭据、远端文件路径）。
  final WebDavConfig config;

  final http.Client _http;
  final bool _ownsHttpClient;
  bool _disposed = false;

  /// 请求超时（连接与读取各自最多 20 秒）。
  static const Duration _timeout = Duration(seconds: 20);

  /// PROPFIND 请求体：只要三样 —— 修改时间、ETag、资源类型。
  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<D:propfind xmlns:D="DAV:"><D:prop>'
      '<D:getlastmodified/><D:getetag/><D:resourcetype/>'
      '</D:prop></D:propfind>';

  static const String _xmlContentType = 'application/xml; charset=utf-8';
  static const String _jsonContentType = 'application/json; charset=utf-8';

  @override
  String get displayName => 'WebDAV';

  // ------------------------------------------------------------------ 公开 API

  /// 测试地址、凭据与远端目录是否可用。
  ///
  /// 对**父目录**做 `PROPFIND`（而不是文件本身）：首次同步时文件还不存在，
  /// 若探测文件会把「正常」误判成「路径不存在」。
  @override
  Future<void> testConnection() async {
    _ensureUsable();
    final dirUri = _uri(config.remoteDirUrl, 'WebDAV 地址');
    final response = await _guard(
      '测试连接',
      () => _send('PROPFIND', dirUri, depth: '0'),
    );
    final status = response.statusCode;

    if (status == 404 || status == 410) {
      throw SyncException(
        '远端路径不存在，请检查 WebDAV 地址与远端目录是否填写正确',
        detail: 'HTTP $status · ${dirUri.toString()}',
      );
    }
    // 少数服务器不允许对目录 PROPFIND，但能收到 405 说明地址与凭据已被接受。
    if (status == 405) return;
    if (!_isSuccess(status)) throw _httpError(status, '测试连接', dirUri);
  }

  /// 读取远端文档；文件不存在（404 / 409 / 410）时返回 null。
  @override
  Future<RemoteDocument?> download() async {
    _ensureUsable();
    final fileUri = _uri(config.remoteFileUrl, 'WebDAV 地址');

    final meta = await _propfind(fileUri);
    if (!meta.exists) return null;

    final response = await _guard('下载', () => _send('GET', fileUri));
    final status = response.statusCode;
    if (status == 404 || status == 409 || status == 410) return null;
    if (!_isSuccess(status)) throw _httpError(status, '下载', fileUri);

    return RemoteDocument(
      content: _decodeBody(response.bodyBytes),
      modifiedAt: meta.modifiedAt,
      versionTag: meta.etag,
    );
  }

  /// 覆盖写入远端文档，必要时逐级创建父目录。
  @override
  Future<void> upload(String content) async {
    _ensureUsable();
    final fileUri = _uri(config.remoteFileUrl, 'WebDAV 地址');

    await _ensureParentDirs();

    final response = await _guard(
      '上传',
      () => _send('PUT', fileUri, contentType: _jsonContentType, body: content),
    );
    final status = response.statusCode;
    if (_isSuccess(status)) return;
    if (status == 409) {
      throw SyncException(
        '远端目录不存在或无法创建，请检查远端文件路径',
        detail: 'HTTP 409 · ${fileUri.toString()}',
      );
    }
    throw _httpError(status, '上传', fileUri);
  }

  /// 释放底层连接。注入的 [http.Client] 由调用方负责关闭。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHttpClient) _http.close();
  }

  // ------------------------------------------------------------------ 请求

  Future<http.Response> _send(
    String method,
    Uri url, {
    String? depth,
    String? contentType,
    String? body,
  }) async {
    final request = http.Request(method, url);
    final auth = _basicAuthHeader;
    if (auth != null) request.headers['Authorization'] = auth;
    request.headers['Accept'] = '*/*';
    if (depth != null) request.headers['Depth'] = depth;
    if (contentType != null) request.headers['Content-Type'] = contentType;
    if (body != null) request.bodyBytes = utf8.encode(body);

    final streamed = await _http.send(request).timeout(_timeout);
    return http.Response.fromStream(streamed).timeout(_timeout);
  }

  /// `Basic base64(username:password)`；用户名与密码都为空时不带认证头。
  String? get _basicAuthHeader {
    if (config.username.isEmpty && config.password.isEmpty) return null;
    final raw = '${config.username}:${config.password}';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  Future<_RemoteMeta> _propfind(Uri fileUri) async {
    final response = await _guard(
      '读取文件信息',
      () => _send(
        'PROPFIND',
        fileUri,
        depth: '1',
        contentType: _xmlContentType,
        body: _propfindBody,
      ),
    );
    final status = response.statusCode;
    if (status == 404 || status == 409 || status == 410) {
      return const _RemoteMeta.absent();
    }
    if (!_isSuccess(status)) throw _httpError(status, '读取文件信息', fileUri);

    return _parsePropFind(_decodeBody(response.bodyBytes), fileUri);
  }

  /// 逐级创建 `remoteDirUrl` 对应的目录；已存在（405）也算成功。
  Future<void> _ensureParentDirs() async {
    for (final dirUri in _parentDirUris()) {
      final response = await _guard('创建远端目录', () => _send('MKCOL', dirUri));
      final status = response.statusCode;
      if (_isSuccess(status) || status == 405) continue;
      if (status == 409) {
        throw SyncException(
          '远端目录创建失败，请检查远端文件路径',
          detail: 'HTTP 409 · ${dirUri.toString()}',
        );
      }
      throw _httpError(status, '创建远端目录', dirUri);
    }
  }

  /// 从 `remoteDirUrl` 推出需要逐级创建的目录 URL 列表（由浅到深）。
  ///
  /// 只补建 base 之后的层级：`https://host/dav/` 视为已存在。
  List<Uri> _parentDirUris() {
    final base = config.normalizedUrl;
    final dir = config.remoteDirUrl;
    if (base.isEmpty || dir.isEmpty) return const <Uri>[];

    final rel = dir.startsWith(base)
        ? dir.substring(base.length)
        : _relativeDirPath();
    final uris = <Uri>[];
    var current = base;
    for (final segment in rel.split('/')) {
      if (segment.trim().isEmpty) continue;
      current = '$current$segment/';
      uris.add(_uri(current, 'WebDAV 地址'));
    }
    return uris;
  }

  /// `remoteDirUrl` 与 base 对不上时的兜底：直接从 `remotePath` 推目录。
  String _relativeDirPath() {
    final path = config.remotePath.trim().replaceFirst(RegExp(r'^/+'), '');
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '';
    final encoded = path
        .substring(0, idx)
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return '$encoded/';
  }

  // ------------------------------------------------------------------ 解析

  /// 从 PROPFIND 的多状态响应里解析目标文件是否存在、修改时间与 ETag。
  ///
  /// 不引入 xml 包：命名空间前缀（`D:` / `ns0:` / 无前缀）都用正则兼容。
  _RemoteMeta _parsePropFind(String xml, Uri fileUri) {
    _RemoteMeta? fallback;
    for (final match in _responseRe.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final href = _unescapeXml(_firstTag(block, 'href') ?? '').trim();
      final etag = _emptyToNull(
        _unescapeXml(_firstTag(block, 'getetag') ?? ''),
      );
      final modified = _parseHttpDate(
        _firstTag(block, 'getlastmodified') ?? '',
      );
      final matchesTarget = _hrefMatches(href, fileUri);

      if (_blockIsMissing(block)) {
        if (matchesTarget) return const _RemoteMeta.absent();
        continue;
      }
      if (matchesTarget) {
        return _RemoteMeta(exists: true, modifiedAt: modified, etag: etag);
      }
      // href 对不上（例如服务器顺带返回了父目录）：只在带版本信息时兜底，
      // 真伪最终由随后的 GET 判定，不会产生错误内容。
      if (etag != null || modified != null) {
        fallback ??= _RemoteMeta(
          exists: true,
          modifiedAt: modified,
          etag: etag,
        );
      }
    }
    return fallback ?? const _RemoteMeta.absent();
  }

  /// 该 response 块里的状态是否全部表示「不存在」。
  bool _blockIsMissing(String block) {
    final codes = _statusRe
        .allMatches(block)
        .map((m) => int.tryParse(m.group(1) ?? ''))
        .whereType<int>()
        .toList();
    if (codes.isEmpty) return false;
    return codes.every((code) => code == 404 || code == 410);
  }

  /// 比较 PROPFIND 返回的 href 是否指向目标文件（比较最后一段路径）。
  bool _hrefMatches(String href, Uri fileUri) {
    var value = href;
    final query = value.indexOf('?');
    if (query >= 0) value = value.substring(0, query);
    final hrefSegment = _lastSegment(value);
    final fileSegment = fileUri.pathSegments.isEmpty
        ? ''
        : fileUri.pathSegments.last;
    if (hrefSegment.isEmpty || fileSegment.isEmpty) return false;
    return hrefSegment == fileSegment ||
        _safeDecode(hrefSegment) == _safeDecode(fileSegment);
  }

  static String _lastSegment(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? '' : parts.last;
  }

  /// 解析 WebDAV 的修改时间：RFC 1123（`Mon, 19 Oct 2026 11:58:19 GMT`）
  /// 或部分服务器返回的 ISO 8601。统一返回 UTC。
  DateTime? _parseHttpDate(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso.toUtc();

    final match = _httpDateRe.firstMatch(text);
    if (match == null) return null;
    final month = _months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  /// 取出第一个 `<tag>...</tag>` 的内容，兼容任意命名空间前缀。
  static String? _firstTag(String xml, String tag) {
    final re = RegExp(
      r'<(?:\w+:)?' + tag + r'\b[^>]*>(.*?)</(?:\w+:)?' + tag + r'\s*>',
      dotAll: true,
      caseSensitive: false,
    );
    return re.firstMatch(xml)?.group(1);
  }

  static String _unescapeXml(String value) {
    if (!value.contains('&')) return value;
    final decoded = value
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        )
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    return decoded.replaceAll('&amp;', '&');
  }

  static String _safeDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _decodeBody(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);

  static bool _isSuccess(int status) => status >= 200 && status < 300;

  // ------------------------------------------------------------------ 错误

  void _ensureUsable() {
    if (_disposed) {
      throw const SyncException('WebDAV 客户端已释放，请重新创建后再试');
    }
    if (config.normalizedUrl.isEmpty) {
      throw const SyncException('请先填写 WebDAV 服务器地址');
    }
    if (config.remotePath.trim().isEmpty) {
      throw const SyncException('请先填写远端文件路径');
    }
  }

  Uri _uri(String raw, String label) {
    final text = raw.trim();
    if (text.isEmpty) throw SyncException('请先填写 $label');
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw SyncException('$label 格式不正确：$text');
    }
    return uri;
  }

  /// 把底层异常统一翻译成带中文提示的 [SyncException]。
  Future<http.Response> _guard(
    String action,
    Future<http.Response> Function() run,
  ) async {
    try {
      return await run();
    } on SyncException {
      rethrow;
    } on TimeoutException catch (e) {
      throw SyncException(
        '网络请求超时（${_timeout.inSeconds} 秒），请检查网络后重试',
        detail: '$action：${e.toString()}',
      );
    } on SocketException catch (e) {
      throw SyncException(
        '网络连接失败，请检查网络或服务器地址是否正确',
        detail: '$action：${e.message}',
      );
    } on HandshakeException catch (e) {
      throw SyncException(
        'HTTPS 证书校验失败，请检查服务器证书',
        detail: '$action：${e.message}',
      );
    } on http.ClientException catch (e) {
      throw SyncException(
        '网络连接失败，请检查网络或服务器地址是否正确',
        detail: '$action：${e.message}',
      );
    } on FormatException catch (e) {
      throw SyncException('WebDAV 返回内容无法解析', detail: '$action：${e.message}');
    }
  }

  SyncException _httpError(int status, String action, Uri url) {
    final String message;
    if (status == 401 || status == 403) {
      message = '账号或密码错误，坚果云请使用「应用密码」';
    } else if (status == 404 || status == 410) {
      message = '远端路径不存在，请检查 WebDAV 地址与远端文件路径';
    } else if (status == 405) {
      message = '服务器拒绝了该操作（HTTP 405），请检查远端路径是否为目录';
    } else if (status == 409) {
      message = '远端目录不存在或存在冲突（HTTP 409），请检查远端路径';
    } else if (status == 507) {
      message = '网盘空间不足，请清理空间后重试';
    } else if (status >= 500) {
      message = 'WebDAV 服务器错误（HTTP $status），请稍后重试';
    } else {
      message = 'WebDAV $action失败（HTTP $status）';
    }
    return SyncException(
      message,
      detail: '$action · HTTP $status · ${url.toString()}',
    );
  }

  static final RegExp _responseRe = RegExp(
    r'<(?:\w+:)?response\b[^>]*>(.*?)</(?:\w+:)?response\s*>',
    dotAll: true,
    caseSensitive: false,
  );

  static final RegExp _statusRe = RegExp(
    r'<(?:\w+:)?status\b[^>]*>\s*HTTP/[\d.]+\s+(\d{3})',
    caseSensitive: false,
  );

  static final RegExp _httpDateRe = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
  );

  static const Map<String, int> _months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
}

/// PROPFIND 解析结果（内部使用）。
class _RemoteMeta {
  const _RemoteMeta({required this.exists, this.modifiedAt, this.etag});

  const _RemoteMeta.absent() : exists = false, modifiedAt = null, etag = null;

  final bool exists;
  final DateTime? modifiedAt;
  final String? etag;
}
