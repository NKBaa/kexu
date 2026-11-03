import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_info.dart';
import '../models/bell_schedule_template.dart';
import '../models/update_config.dart';

/// 作息模板拉取失败时抛出的异常（message 可直接展示给用户）。
class ScheduleTemplateException implements Exception {
  final String message;

  const ScheduleTemplateException(this.message);

  @override
  String toString() => message;
}

/// 从 GitHub 拉取按学校分组的作息模板。
///
/// 模板文件路径固定为 `templates/bell_schedules.json`，仓库沿用
/// 「设置 → 检查更新」里的 [UpdateConfig]；下载固定走内置加速镜像，
/// 用户不需要额外配置。
class ScheduleTemplateService {
  ScheduleTemplateService({http.Client? client}) : _defaultClient = client;

  final http.Client? _defaultClient;

  static const String templatePath = 'templates/bell_schedules.json';
  static const String _userAgent = 'Kexu/$fullVersion';

  Future<BellScheduleTemplateCatalog> fetch({
    required UpdateConfig config,
    http.Client? client,
  }) async {
    if (!config.isConfigured) {
      throw const ScheduleTemplateException(
        '还没有配置 GitHub 仓库，请先在「设置 → 检查更新」里填写 owner/repo。',
      );
    }

    final rawUrl =
        'https://raw.githubusercontent.com/${config.normalizedRepo}/main/$templatePath';
    final prefixes = <String>[];
    void add(String prefix) {
      if (!prefixes.contains(prefix)) prefixes.add(prefix);
    }

    // 模板固定走加速镜像，最后直连兜底；不读取用户的更新镜像设置。
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
            lastError = '模板格式不是 JSON 对象';
            continue;
          }
          return BellScheduleTemplateCatalog.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        } catch (e) {
          lastError = e;
        }
      }
    } finally {
      if (owned) httpClient.close();
    }

    throw ScheduleTemplateException(
      '暂时无法获取作息模板（仓库 ${config.normalizedRepo}）。'
      '请检查网络后重试。${lastError == null ? '' : ' 原因：$lastError'}',
    );
  }
}
