import '../../data/models/timetable.dart';
import 'ai_client.dart';
import 'ai_exception.dart';
import 'nl_edit.dart';

/// 图片改课表的结果：除了方案，还带回用于下一轮历史的用户文本。
class AiImageIntentResult {
  final NlEditTurn turn;
  final String historyText;

  const AiImageIntentResult({
    required this.turn,
    required this.historyText,
  });
}

/// 把「图片 + 一句话」变成改课表方案。
///
/// 策略：
/// - 有语言模型：图片直接发给语言模型（多模态）；
/// - 没有语言模型但有识图模型：先让识图模型把图片转述成文字，
///   再用识图模型按转述生成方案；
/// - 两者都没有：抛出可展示的异常。
class AiImageIntentService {
  static const String transcriptPrompt =
      '请把图片里与课表有关的信息完整转述成中文纯文本，包括课程名、星期、节次、周次、'
      '地点、教师、时间。多张图片请按顺序分别转述。看不清的内容写「看不清」，不要编造。';

  Future<AiImageIntentResult> plan({
    required String instruction,
    required Timetable current,
    required List<AiImageAttachment> images,
    required List<AiChatMessage> history,
    required AiClient textClient,
    required AiClient visionClient,
    required bool textConfigured,
    required bool visionConfigured,
    void Function(String status)? onStatus,
  }) async {
    if (images.isEmpty) {
      if (!textConfigured) {
        throw AiException.notConfigured('还没有配置语言模型。');
      }
      final turn = await NlEditService(client: textClient).planTurn(
        instruction,
        current: current,
        history: history,
      );
      return AiImageIntentResult(turn: turn, historyText: instruction);
    }

    if (textConfigured) {
      onStatus?.call('语言模型正在看图片…');
      final turn = await NlEditService(client: textClient).planTurn(
        instruction,
        current: current,
        history: history,
        images: images,
      );
      return AiImageIntentResult(turn: turn, historyText: instruction);
    }

    if (!visionConfigured) {
      throw AiException.notConfigured('还没有配置语言模型或识图模型。');
    }

    onStatus?.call('识图模型正在转述图片…');
    final transcript = await visionClient.chatWithImages(
      images: images,
      prompt: transcriptPrompt,
      system: '你是严谨的课表图片转述助手，只转述图片中真实存在的信息。',
    );
    onStatus?.call('正在根据转述生成方案…');
    final historyText =
        '$instruction\n\n[图片内容转述]\n${transcript.trim()}';
    final turn = await NlEditService(client: visionClient).planTurn(
      historyText,
      current: current,
      history: history,
    );
    return AiImageIntentResult(turn: turn, historyText: historyText);
  }
}
