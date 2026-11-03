import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/app_info.dart';
import '../models/ai_model_catalog.dart';
import '../models/update_config.dart';

/// 模型名单拉取失败时抛出（message 可直接展示给用户）。
class AiModelCatalogException implements Exception {
  final String message;

  const AiModelCatalogException(this.message);

  @override
  String toString() => message;
}

/// 从 GitHub 拉取模型能力名单，并缓存到本地。
///
/// 名单文件固定为 `templates/ai_models.json`，仓库沿用
/// 「设置 → 检查更新」里的 [UpdateConfig]；下载固定走内置加速镜像，
/// 用户不需要额外配置。
class AiModelCatalogService {
  AiModelCatalogService({http.Client? client, Directory? cacheDirectory})
      : _defaultClient = client,
        // ignore: prefer_initializing_formals
        _cacheDirectory = cacheDirectory;

  final http.Client? _defaultClient;
  final Directory? _cacheDirectory;

  static const String catalogPath = 'templates/ai_models.json';
  static const String cacheFileName = 'ai_models_cache.json';
  static const String _userAgent = 'Kexu/$fullVersion';

  /// 按镜像顺序拉取名单；全部失败时抛 [AiModelCatalogException]。
  Future<AiModelCatalog> fetch({
    required UpdateConfig config,
    http.Client? client,
  }) async {
    if (!config.isConfigured) {
      throw const AiModelCatalogException(
        '还没有配置 GitHub 仓库，请先在「设置 → 检查更新」里填写 owner/repo。',
      );
    }

    final rawUrl =
        'https://raw.githubusercontent.com/${config.normalizedRepo}/main/$catalogPath';
    final prefixes = <String>[];
    void add(String prefix) {
      if (!prefixes.contains(prefix)) prefixes.add(prefix);
    }

    // 名单固定走加速镜像，最后直连兜底；不读取用户的更新镜像设置。
    for (final prefix in templateMirrorPrefixes) {
      add(prefix);
    }
    add('');

    final httpClient = client ?? _defaultClient ?? http.Client();
    final owned = client == null && _defaultClient == null;
    Object? lastError;
    try {
      for (final prefix in prefixes) {
        final url = '$prefix$rawUrl';
        try {
          final response = await httpClient.get(
            Uri.parse(url),
            headers: <String, String>{
              'Accept': 'application/json',
              'User-Agent': _userAgent,
            },
          ).timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) {
            lastError = 'HTTP ${response.statusCode}';
            continue;
          }
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is! Map) {
            lastError = '名单格式不是 JSON 对象';
            continue;
          }
          final catalog = AiModelCatalog.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          return catalog.copyWith(source: 'github');
        } catch (e) {
          lastError = e;
        }
      }
    } finally {
      if (owned) httpClient.close();
    }

    throw AiModelCatalogException(
      '暂时无法获取模型名单（仓库 ${config.normalizedRepo}）。'
      '请检查网络后重试。'
      '${lastError == null ? '' : ' 原因：$lastError'}',
    );
  }

  /// 读取本地缓存；没有缓存或格式损坏时返回 null。
  Future<AiModelCatalog?> loadCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return AiModelCatalog.fromJson(Map<String, dynamic>.from(decoded))
          .copyWith(source: 'cache');
    } catch (_) {
      return null;
    }
  }

  /// 把成功拉取的名单写入本地缓存；失败静默。
  Future<void> saveCache(AiModelCatalog catalog) async {
    try {
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(catalog.toJson()),
        flush: true,
      );
    } catch (_) {
      // 缓存失败不影响本次使用。
    }
  }

  Future<File> _cacheFile() async {
    final dir = _cacheDirectory ?? await _defaultCacheDirectory();
    return File('${dir.path}${Platform.pathSeparator}$cacheFileName');
  }

  Future<Directory> _defaultCacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}course_timetable');
  }
}
