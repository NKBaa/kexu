import 'dart:convert';

import '../../core/utils/ids.dart';
import '../../data/models/schedule_event.dart';
import '../ai/ai_client.dart';
import '../ai/ai_exception.dart';

/// 用语言模型把一句话变成日程事件。
///
/// 模型只负责解析，不直接写库；UI 让用户确认后再保存。
class ScheduleEventAiService {
  // ignore: prefer_initializing_formals
  ScheduleEventAiService({required AiClient client}) : _client = client;

  final AiClient _client;

  Future<List<ScheduleEvent>> plan(
    String instruction, {
    DateTime? now,
  }) async {
    final text = instruction.trim();
    if (text.isEmpty) {
      throw AiException.invalidInput('请先描述要添加什么日程。');
    }
    final base = now ?? DateTime.now();
    final today =
        '${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';
    final weekday = const ['一', '二', '三', '四', '五', '六', '日'][base.weekday - 1];
    final prompt = '''
你在帮用户把自然语言整理成「日程」列表。日程和课表无关，是考试、作业截止、活动、会议等个人事项。
今天是 $today（星期$weekday）。

用户的话：
$text

请只输出严格 JSON，不要 markdown 代码块，不要解释：
{"events":[{"title":"事项标题","date":"YYYY-MM-DD","startTime":"HH:mm 或 null","endTime":"HH:mm 或 null","note":"备注，可为空"}]}

规则：
1. 用户说「今天/明天/后天/本周X/下周X/下个月X号」时，必须按今天 $today 换算成具体日期。
2. 没有明确时间就写 startTime=null、endTime=null，表示全天。
3. 一句话里有多个事项时输出多条 events。
4. 日期必须落在合理范围；不确定的日期不要编造，可以在 note 里说明。
5. title 要简短明确，不要带日期时间。
''';
    final raw = await _client.chatText(
      prompt,
      system: '你是一个严谨的日程结构化助手，只输出可解析的 JSON。',
    );
    return parseEvents(raw);
  }

  static List<ScheduleEvent> parseEvents(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw AiException.parse('AI 没有返回可解析的日程 JSON。', rawOutput: raw);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw AiException.parse('AI 返回的日程 JSON 格式不正确。', rawOutput: raw);
    }
    if (decoded is! Map) {
      throw AiException.parse('AI 返回的日程格式不是 JSON 对象。', rawOutput: raw);
    }
    final list = decoded['events'];
    if (list is! List) {
      throw AiException.parse('AI 返回的日程缺少 events 数组。', rawOutput: raw);
    }
    final events = <ScheduleEvent>[];
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final title = (map['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final dateText = (map['date'] ?? '').toString().trim();
      final date = DateTime.tryParse(dateText);
      if (date == null) continue;
      final startTime = _normalizeTime(map['startTime']);
      final endTime = _normalizeTime(map['endTime']);
      events.add(
        ScheduleEvent(
          id: newId(),
          title: title,
          date: date,
          startTime: startTime,
          endTime: endTime,
          note: (map['note'] ?? '').toString().trim(),
        ),
      );
    }
    if (events.isEmpty) {
      throw AiException.parse('AI 没有解析出有效日程，请换一种说法再试。', rawOutput: raw);
    }
    return events;
  }

  static String? _normalizeTime(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
