/// AI 对话的消息与图片附件模型。
///
/// 单独放一个文件，是因为「一句话改课表」的多轮对话与「图片转课表」的多图
/// 识别都需要这套结构，而 [AiClient] 本身只该关心「怎么发请求、怎么解析响应」。
library;

import 'dart:typed_data';

/// 一条 OpenAI 兼容的纯文本对话消息。
///
/// `role` 只取 `system` / `user` / `assistant` 三种；多模态图片不放在这里，
/// 而是由 [AiClient.chatWithImages] 统一组装，避免消息结构变得难以序列化。
class AiChatMessage {
  /// 角色：`system` / `user` / `assistant`。
  final String role;

  /// 正文。
  final String text;

  const AiChatMessage({required this.role, required this.text});

  const AiChatMessage.system(this.text) : role = 'system';

  const AiChatMessage.user(this.text) : role = 'user';

  const AiChatMessage.assistant(this.text) : role = 'assistant';

  /// 转成 `{"role": ..., "content": ...}`。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': text,
      };

  @override
  String toString() => 'AiChatMessage($role, ${text.length} chars)';
}

/// 一张待识别的图片（本地字节 + 可选 MIME 提示）。
///
/// [mimeType] 只是提示：真正的类型以文件头嗅探为准（见 `resolveImageMimeType`）。
class AiImageAttachment {
  /// 图片字节。
  final Uint8List bytes;

  /// MIME 提示，如 `image/png` 或文件扩展名 `png`。
  final String? mimeType;

  /// 文件名（仅用于提示与排错，不参与请求）。
  final String? name;

  const AiImageAttachment({required this.bytes, this.mimeType, this.name});

  bool get isEmpty => bytes.isEmpty;
}
