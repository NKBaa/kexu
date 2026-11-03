/// OpenAI 兼容的 Chat Completions 客户端。
///
/// 只做一件事：把「系统提示 + 用户文本（+ 可选图片）」发给模型，拿回正文文本。
/// 不依赖任何第三方 SDK，直接走 `POST {baseUrl}/chat/completions`，因此
/// DeepSeek / 智谱 / 通义千问 / OpenAI / 本地 Ollama 等都能用同一套代码。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/utils/json_utils.dart';
import '../../data/models/ai_config.dart';
import 'ai_exception.dart';
import 'ai_message.dart';

export 'ai_message.dart' show AiChatMessage, AiImageAttachment;

/// 图片 MIME 类型推断：优先按文件头判断，其次信任调用方给的提示。
///
/// 很多相册/剪贴板来源拿不到可靠的 MIME，而 data URL 必须带对类型，
/// 所以这里用「魔术字节」兜底，默认按 JPEG 处理。
String resolveImageMimeType(Uint8List bytes, {String? hint}) {
  final sniffed = _sniffMimeType(bytes);
  if (sniffed != null) return sniffed;

  final h = (hint ?? '').trim().toLowerCase();
  if (h.isNotEmpty) {
    if (h.startsWith('image/')) return h;
    switch (h) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
      case 'heif':
        return 'image/heic';
    }
  }
  return 'image/jpeg';
}

String? _sniffMimeType(Uint8List b) {
  bool startsWith(List<int> sig, [int offset = 0]) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith(const [0x42, 0x4D])) return 'image/bmp';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
      startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  // HEIC/HEIF: 第 4~7 字节为 "ftyp"
  if (b.length >= 12 && startsWith(const [0x66, 0x74, 0x79, 0x70], 4)) {
    return 'image/heic';
  }
  return null;
}

/// AI 客户端。
///
/// 一个实例可复用多次请求；图片导入与自然语言改课表共用同一个客户端即可。
/// [config] 支持在设置变更后直接赋值，无需重建客户端。
class AiClient {
  AiClient({required this.config, http.Client? httpClient})
      : _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// 当前配置（可随时替换，如用户改了 API Key）。
  AiModelConfig config;

  final http.Client _http;
  final bool _ownsHttpClient;
  bool _disposed = false;

  /// 文本对话。返回模型正文（已 trim）。
  Future<String> chatText(String prompt, {String? system}) {
    final messages = <Map<String, dynamic>>[
      if (_nonEmpty(system)) {'role': 'system', 'content': system!.trim()},
      {'role': 'user', 'content': prompt},
    ];
    return _chat(messages);
  }

  /// 多轮纯文本对话：由调用方提供完整消息列表（可含 system）。
  ///
  /// 「一句话改课表」的追问/补充流程需要把历史对话原样带给模型，
  /// 否则模型会忘记上一轮已经确认过的信息（比如用户已经回答过「哪门课」）。
  /// 空消息会被跳过；全部为空时直接报错，避免发出一个无意义的请求。
  Future<String> chatMessages(List<AiChatMessage> messages, {String? system}) async {
    final list = <Map<String, dynamic>>[
      if (_nonEmpty(system)) {'role': 'system', 'content': system!.trim()},
      for (final m in messages)
        if (_nonEmpty(m.text)) m.toJson(),
    ];
    if (list.isEmpty || (list.length == 1 && list.first['role'] == 'system')) {
      throw AiException.invalidInput('没有可发送的对话内容，请先输入要修改的内容。');
    }
    return _chat(list);
  }

  /// 多模态对话：**多张图片** + 一段提示词，一次请求发给模型。
  ///
  /// 图片会以 data URL（base64）按顺序放进同一条 user 消息：
  /// 模型因此能看到多张图之间的关系（例如「单周」「双周」两张截图、
  /// 或同一张课表被分屏截成两张），从而把它们合并成一份课表，
  /// 而不是各识别一遍再由客户端硬拼。
  ///
  /// 任一图片为空都会在发请求前失败，避免浪费一次昂贵的视觉调用。
  Future<String> chatWithImages({
    required List<AiImageAttachment> images,
    required String prompt,
    String? system,
    List<AiChatMessage> history = const [],
  }) async {
    if (images.isEmpty) {
      throw AiException.invalidInput('请至少选择一张图片。');
    }
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      if (image.isEmpty) {
        throw AiException.invalidInput('第 ${i + 1} 张图片内容为空，请重新选择后再试。');
      }
      final mime = resolveImageMimeType(image.bytes, hint: image.mimeType);
      content.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(image.bytes)}'},
      });
    }
    final messages = <Map<String, dynamic>>[
      if (_nonEmpty(system)) {'role': 'system', 'content': system!.trim()},
      for (final m in history)
        if (_nonEmpty(m.text)) m.toJson(),
      {'role': 'user', 'content': content},
    ];
    return _chat(messages);
  }

  /// 获取服务端可用模型列表（`GET {baseUrl}/models`）。
  ///
  /// 不同网关/中转站的模型名经常变化，手填容易拼错；配置页用它自动填充候选列表。
  /// 兼容 `{"data":[{"id":"..."}]}`、`{"models":[...]}`、`{"result":[...]}`
  /// 以及直接返回字符串数组的写法，结果去重并按字母排序。
  /// 服务端不支持该接口时抛 [AiException]，由调用方给出可操作提示。
  Future<List<String>> listModels() async {
    if (_disposed) {
      throw StateError('AiClient 已释放，请重新创建实例。');
    }
    final cfg = config;
    final url = cfg.modelsUrl;
    if (url.isEmpty) {
      throw AiException.notConfigured('baseUrl 为空');
    }

    final headers = <String, String>{'Accept': 'application/json'};
    if (cfg.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${cfg.apiKey.trim()}';
    }
    final timeoutSeconds = cfg.timeoutSeconds > 0 ? cfg.timeoutSeconds : 120;

    final http.Response response;
    try {
      response = await _http
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      throw AiException.timeout(timeoutSeconds);
    } on http.ClientException catch (e) {
      throw AiException.network(e);
    } catch (e) {
      // 包含 SocketException / HandshakeException / 非法 URL 等
      throw AiException.network(e);
    }

    final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw AiException.http(
        statusCode: status,
        bodySnippet: AiException.truncateBody(_extractErrorMessage(bodyText)),
      );
    }

    final decoded = tryDecodeJson(bodyText);
    final ids = <String>[];

    void addId(dynamic item) {
      if (item is Map) {
        for (final key in const ['id', 'name', 'model']) {
          final s = asString(item[key]).trim();
          if (s.isNotEmpty) {
            ids.add(s);
            return;
          }
        }
        return;
      }
      final s = asString(item).trim();
      if (s.isNotEmpty) ids.add(s);
    }

    if (decoded is List) {
      for (final item in decoded) {
        addId(item);
      }
    } else if (decoded is Map) {
      final raw = decoded['data'] ?? decoded['models'] ?? decoded['result'];
      for (final item in asList(raw)) {
        addId(item);
      }
    }

    if (ids.isEmpty) {
      throw AiException.badResponse(
        '没有从 /models 响应里解析到模型列表，可能该服务不支持此接口，请手动填写模型名。',
        bodySnippet: AiException.truncateBody(bodyText),
      );
    }
    final unique = ids.toSet().toList()..sort();
    return unique;
  }

  /// 释放底层连接。之后该实例不可再用。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHttpClient) _http.close();
  }

  // ------------------------------------------------------------------ 内部实现

  Future<String> _chat(List<Map<String, dynamic>> messages) async {
    if (_disposed) {
      throw StateError('AiClient 已释放，请重新创建实例。');
    }
    final cfg = config;
    if (!cfg.isConfigured) {
      throw AiException.notConfigured(
        'baseUrl="${cfg.baseUrl}", model="${cfg.model}", '
        'hasApiKey=${cfg.apiKey.trim().isNotEmpty}',
      );
    }
    final url = cfg.chatCompletionsUrl;
    if (url.isEmpty) {
      throw AiException.notConfigured('baseUrl 为空');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    if (cfg.apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${cfg.apiKey.trim()}';
    }

    // 温度夹到合法区间、超时兜底，避免用户误填（0 / 负数 / 过大）导致请求异常。
    final temperature = cfg.temperature.clamp(0.0, 2.0);
    final timeoutSeconds = cfg.timeoutSeconds > 0 ? cfg.timeoutSeconds : 120;

    final payload = <String, dynamic>{
      'model': cfg.model.trim(),
      'messages': messages,
      'temperature': temperature,
    };

    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      throw AiException.timeout(timeoutSeconds);
    } on http.ClientException catch (e) {
      throw AiException.network(e);
    } catch (e) {
      // 包含 SocketException / HandshakeException / 非法 URL 等
      throw AiException.network(e);
    }

    final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
    final status = response.statusCode;

    if (status < 200 || status >= 300) {
      throw AiException.http(
        statusCode: status,
        bodySnippet: AiException.truncateBody(_extractErrorMessage(bodyText)),
      );
    }

    if (bodyText.trim().isEmpty) {
      throw AiException.badResponse('AI 服务返回了空响应体（HTTP $status），请稍后重试。');
    }

    final decoded = tryDecodeJson(bodyText);
    if (decoded is! Map) {
      throw AiException.badResponse(
        'AI 服务返回的内容不是 JSON 对象，无法解析（请确认 baseUrl 指向 OpenAI 兼容接口）。',
        bodySnippet: AiException.truncateBody(bodyText),
      );
    }
    final json = Map<String, dynamic>.from(decoded);

    // 少数服务商会用 HTTP 200 + {"error": {...}} 表示失败
    final error = json['error'];
    if (error != null) {
      throw AiException.badResponse(
        'AI 服务返回错误：${_errorMessageOf(error)}',
        bodySnippet: AiException.truncateBody(bodyText),
      );
    }

    final choices = asList(json['choices']);
    if (choices.isEmpty) {
      throw AiException.badResponse(
        'AI 响应缺少 choices 字段，可能不是 Chat Completions 接口。',
        bodySnippet: AiException.truncateBody(bodyText),
      );
    }

    final choice = asMap(choices.first);
    final finishReason = asString(choice['finish_reason']).toLowerCase();
    var content = _contentToText(asMap(choice['message'])['content']);
    if (content.isEmpty) {
      // 兼容极少见的旧式 completions 返回
      content = _contentToText(choice['text']);
    }
    if (content.isEmpty) {
      if (finishReason == 'content_filter') {
        throw AiException.badResponse('模型因内容安全策略拒绝输出，请更换图片或换一个模型。');
      }
      if (finishReason == 'length') {
        throw AiException.badResponse('模型输出被截断（达到长度上限），请重试或简化图片内容。');
      }
      throw AiException.badResponse(
        '模型返回了空内容（finish_reason=$finishReason），请稍后重试。',
        bodySnippet: AiException.truncateBody(bodyText),
      );
    }
    return content;
  }

  /// 把 messages[].content 的多种形态统一成纯文本。
  ///
  /// 兼容：字符串、`[{"type":"text","text":"..."}]` 数组、以及数组里直接放字符串。
  static String _contentToText(dynamic content) {
    if (content is String) return content.trim();
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is String) {
          final s = item.trim();
          if (s.isNotEmpty) parts.add(s);
        } else if (item is Map) {
          final text = asString(item['text']);
          if (text.isNotEmpty) {
            parts.add(text);
          } else {
            final s = asString(item['content']);
            if (s.isNotEmpty) parts.add(s);
          }
        }
      }
      return parts.join('\n').trim();
    }
    return '';
  }

  /// 从错误响应体里尽量提取可读的错误信息。
  static String _extractErrorMessage(String body) {
    final decoded = tryDecodeJson(body);
    if (decoded is Map) {
      final err = decoded['error'];
      if (err != null) return _errorMessageOf(err);
      final msg = asString(decoded['message']);
      if (msg.isNotEmpty) return msg;
      final msgCn = asString(decoded['msg']);
      if (msgCn.isNotEmpty) return msgCn;
    }
    return body;
  }

  static String _errorMessageOf(dynamic error) {
    if (error is String) return error;
    if (error is Map) {
      final msg = asString(error['message']);
      if (msg.isNotEmpty) return msg;
      final msgCn = asString(error['msg']);
      if (msgCn.isNotEmpty) return msgCn;
      final code = asString(error['code']);
      if (code.isNotEmpty) return code;
      final type = asString(error['type']);
      if (type.isNotEmpty) return type;
      return error.toString();
    }
    return error.toString();
  }

  static bool _nonEmpty(String? s) => s != null && s.trim().isNotEmpty;
}

