import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ai_config.dart';
import '../settings/providers/settings_provider.dart';
import 'ai_client.dart';

/// 图片转课表用的**视觉模型**客户端。
///
/// 配置变化时自动重建并释放旧连接（`ref.onDispose`），
/// 避免用户改了 API Key 之后仍用旧配置发请求。
final visionAiClientProvider = Provider<AiClient>((ref) {
  // 直接读 settingsProvider，而不是 aiConfigProvider：首次打开 AI 页面时
  // aiConfigProvider 可能还在 AsyncLoading，从它取 valueOrNull 会拿到空配置
  // 并缓存，导致用户必须去大模型配置页点一次保存才能使用。
  final config =
      ref.watch(settingsProvider).valueOrNull?.aiConfig ?? const AiConfig();
  final client = AiClient(config: config.vision);
  ref.onDispose(client.dispose);
  return client;
});

/// 一句话改课表用的**文本模型**客户端。
final textAiClientProvider = Provider<AiClient>((ref) {
  final config =
      ref.watch(settingsProvider).valueOrNull?.aiConfig ?? const AiConfig();
  final client = AiClient(config: config.text);
  ref.onDispose(client.dispose);
  return client;
});
