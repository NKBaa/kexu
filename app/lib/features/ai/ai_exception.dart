/// AI 能力层的统一异常类型。
///
/// 设计目标：UI 层只需要捕获 [AiException]，就能拿到「给用户看的中文提示」
/// 与「给开发排查用的状态码/响应片段」，不必关心底层是 HTTP、超时还是 JSON 解析问题。
library;

/// AI 请求失败的原因分类，便于 UI 决定提示方式（如 401 时直接引导去填 Key）。
enum AiErrorKind {
  /// 尚未配置 baseUrl / apiKey / model。
  notConfigured,

  /// 参数非法（如空的图片字节、空指令）。
  invalidInput,

  /// 网络层错误（DNS、连接失败、代理等）。
  network,

  /// 请求超时。
  timeout,

  /// 服务端返回了非 2xx 状态码。
  http,

  /// 服务端 2xx，但响应体不符合 OpenAI 兼容协议（缺字段、纯文本等）。
  badResponse,

  /// 模型输出无法解析成目标结构（如不是 JSON、缺少 courses）。
  parse,

  /// 未归类错误。
  unknown,
}

/// AI 能力层所有异常的基类。
///
/// [message] 面向用户（中文、可直接展示），[detail] 面向排查（可折叠展示）。
class AiException implements Exception {
  final AiErrorKind kind;

  /// 给用户看的错误说明。
  final String message;

  /// 排查用的细节，如 URL、状态码、响应片段。
  final String? detail;

  /// HTTP 状态码（仅 [AiErrorKind.http] 时非空）。
  final int? statusCode;

  /// 服务端响应体片段（已截断）。
  final String? bodySnippet;

  const AiException(
    this.message, {
    this.kind = AiErrorKind.unknown,
    this.detail,
    this.statusCode,
    this.bodySnippet,
  });

  /// 尚未配置模型。
  factory AiException.notConfigured([String? detail]) => AiException(
        '尚未配置 AI 模型，请先在设置里填写服务地址、API Key 和模型名。',
        kind: AiErrorKind.notConfigured,
        detail: detail,
      );

  /// 入参非法。
  factory AiException.invalidInput(String message) =>
      AiException(message, kind: AiErrorKind.invalidInput);

  /// 网络层错误。
  factory AiException.network(Object error) => AiException(
        '无法连接到 AI 服务，请检查网络、服务地址（baseUrl）与 API Key 是否正确，'
        '以及是否需要代理。',
        kind: AiErrorKind.network,
        detail: error.toString(),
      );

  /// 请求超时。
  factory AiException.timeout(int timeoutSeconds) => AiException(
        'AI 请求超时（$timeoutSeconds 秒），可能是图片过大或网络较慢，请重试。',
        kind: AiErrorKind.timeout,
      );

  /// HTTP 非 2xx。
  ///
  /// 会按状态码给出更有针对性的建议：401/403 提示检查 Key，404 提示检查地址与模型名。
  factory AiException.http({
    required int statusCode,
    required String bodySnippet,
  }) {
    final String hint;
    switch (statusCode) {
      case 400:
        hint = '请求参数被拒绝，可能是模型名（model）不存在或该模型不支持图片输入。';
      case 401:
        hint = 'API Key 无效或已过期，请到设置里重新填写。';
      case 403:
        hint = 'API Key 没有调用该模型的权限，请检查账号额度与模型权限。';
      case 404:
        hint = '接口地址不存在，请检查服务地址（baseUrl）是否需要以 /v1 结尾。';
      case 413:
        hint = '图片过大被服务端拒绝，请压缩图片后重试。';
      case 429:
        hint = '请求过于频繁或额度不足，请稍后再试。';
      case 500:
      case 502:
      case 503:
      case 504:
        hint = 'AI 服务端暂时不可用，请稍后重试或更换服务商。';
      default:
        hint = 'AI 服务返回了错误状态码，请检查配置或稍后重试。';
    }
    return AiException(
      'AI 服务返回 HTTP $statusCode：$hint',
      kind: AiErrorKind.http,
      statusCode: statusCode,
      bodySnippet: bodySnippet,
      detail: 'HTTP $statusCode\n$bodySnippet',
    );
  }

  /// 2xx 但响应结构不符合 OpenAI 兼容协议。
  factory AiException.badResponse(String message, {String? bodySnippet}) =>
      AiException(
        message,
        kind: AiErrorKind.badResponse,
        bodySnippet: bodySnippet,
        detail: bodySnippet,
      );

  /// 模型输出无法解析。
  factory AiException.parse(String message, {String? rawOutput}) {
    final snippet = rawOutput == null ? null : _snippet(rawOutput);
    return AiException(
      message,
      kind: AiErrorKind.parse,
      bodySnippet: snippet,
      detail: snippet == null ? null : '模型原始输出片段：\n$snippet',
    );
  }

  /// 把响应体截断成便于展示的片段（去掉多余空白）。
  static String _snippet(String raw, {int maxLength = 600}) {
    final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.length <= maxLength) return s;
    return '${s.substring(0, maxLength)}…';
  }

  /// 截断任意响应文本，供其他异常构造使用。
  static String truncateBody(String raw, {int maxLength = 600}) =>
      _snippet(raw, maxLength: maxLength);

  @override
  String toString() {
    final buf = StringBuffer('AiException(${kind.name}): $message');
    if (statusCode != null) buf.write(' [HTTP $statusCode]');
    if (detail != null && detail!.trim().isNotEmpty) {
      buf.write('\n$detail');
    }
    return buf.toString();
  }
}
