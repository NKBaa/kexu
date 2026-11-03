import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_info.dart';
import '../models/app_theme_spec.dart';
import '../models/update_config.dart';

class ThemeMarketException implements Exception {
  final String message;

  const ThemeMarketException(this.message);

  @override
  String toString() => message;
}

/// 主题市场目录（GitHub 上的 `templates/themes.json`）。
class ThemeMarketCatalog {
  final List<AppThemeSpec> themes;
  final String updatedAt;

  const ThemeMarketCatalog({this.themes = const [], this.updatedAt = ''});

  factory ThemeMarketCatalog.fromJson(Map<String, dynamic> j) {
    final raw = j['themes'];
    if (raw is! List) {
      throw const FormatException('主题市场文件缺少 themes 数组');
    }
    final themes = <AppThemeSpec>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        themes.add(AppThemeSpec.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // 单个主题损坏不影响其它主题。
      }
    }
    return ThemeMarketCatalog(
      themes: themes,
      updatedAt: (j['updatedAt'] ?? '').toString().trim(),
    );
  }
}

/// 从 GitHub 拉取主题市场；仓库沿用「设置 → 检查更新」配置，
/// 下载固定走内置加速镜像，用户不需要额外配置。
class ThemeMarketService {
  ThemeMarketService({http.Client? client}) : _defaultClient = client;

  final http.Client? _defaultClient;

  static const String marketPath = 'templates/themes.json';
  static const String _userAgent = 'Kexu/$fullVersion';

  Future<ThemeMarketCatalog> fetch({
    required UpdateConfig config,
    http.Client? client,
  }) async {
    if (!config.isConfigured) {
      throw const ThemeMarketException(
        '还没有配置 GitHub 仓库，请先在「设置 → 检查更新」里填写 owner/repo。',
      );
    }
    final rawUrl =
        'https://raw.githubusercontent.com/${config.normalizedRepo}/main/$marketPath';
    final prefixes = <String>[];
    void add(String prefix) {
      if (!prefixes.contains(prefix)) prefixes.add(prefix);
    }

    // 主题市场固定走加速镜像，最后直连兜底；不读取用户的更新镜像设置。
    for (final prefix in templateMirrorPrefixes) {
      add(prefix);
    }
    add('');

    final httpClient = client ?? _defaultClient ?? http.Client();
    final owned = client == null && _defaultClient == null;
    Object? lastError;
    try {
      for (final prefix in prefixes) {
        try {
          final response = await httpClient.get(
            Uri.parse('$prefix$rawUrl'),
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
            lastError = '主题市场格式不是 JSON 对象';
            continue;
          }
          return ThemeMarketCatalog.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        } catch (e) {
          lastError = e;
        }
      }
    } finally {
      if (owned) httpClient.close();
    }

    throw ThemeMarketException(
      '暂时无法获取主题市场（仓库 ${config.normalizedRepo}）。'
      '请检查网络后重试。'
      '${lastError == null ? '' : ' 原因：$lastError'}',
    );
  }
}
