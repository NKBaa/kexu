import '../../core/utils/json_utils.dart';
import '../../data/models/holiday.dart';

/// AI 解析出的一组节假日草稿（同一条可能覆盖多天，如国庆 7 天）。
class HolidayDraft {
  final String name;
  final List<DateTime> dates;

  const HolidayDraft({required this.name, required this.dates});

  String get dateLabel {
    if (dates.isEmpty) return '';
    final first = dates.first;
    final last = dates.last;
    String fmt(DateTime d) =>
        '${d.month}月${d.day}日';
    if (dates.length == 1) return fmt(first);
    return '${fmt(first)} - ${fmt(last)}（${dates.length} 天）';
  }
}

/// 一次 AI 节假日解析结果。
class HolidayAiPlan {
  final String summary;
  final List<HolidayDraft> drafts;
  final List<String> warnings;

  const HolidayAiPlan({
    this.summary = '',
    this.drafts = const [],
    this.warnings = const [],
  });

  bool get isEmpty => drafts.isEmpty;
}

/// 生成给模型的提示词：要求只输出 JSON，日期统一 yyyy-MM-dd。
String buildHolidayAiPrompt({
  required String instruction,
  required DateTime today,
  List<Holiday> existing = const [],
}) {
  String d(DateTime x) =>
      '${x.year.toString().padLeft(4, '0')}-'
      '${x.month.toString().padLeft(2, '0')}-'
      '${x.day.toString().padLeft(2, '0')}';
  final existingText = existing.isEmpty
      ? '无'
      : existing.map((h) => '${d(h.date)} ${h.name}').join('；');
  return '''
今天是 ${d(today)}。请把用户描述的放假安排解析成 JSON：
{"summary":"一句话总结","holidays":[{"name":"国庆节","startDate":"${today.year}-10-01","endDate":"${today.year}-10-07"}]}

规则：
- 日期必须输出 yyyy-MM-dd；跨天用 startDate/endDate，单天用 date；
- 名称用用户说的节日名，没说就写「节假日」；
- 只输出 JSON，不要解释，不要 Markdown；
- 已有节假日：$existingText
- 用户描述：$instruction
''';
}

/// 解析模型返回的节假日 JSON。
///
/// 兼容：
/// - `{"holidays":[{"name":"国庆节","startDate":"2026-10-01","endDate":"2026-10-07"}]}`
/// - 直接数组 `[...]`
/// - `{"days":[{"name":"校运会","date":"2026-11-06"}]}`
/// - 日期可写 `2026-10-01`、`10-01`、`10月1日`、`10/1`。
HolidayAiPlan parseHolidayAiOutput(
  String raw, {
  required int fallbackYear,
}) {
  final block = extractJsonBlock(raw);
  if (block == null) {
    throw const FormatException('模型没有返回可识别的 JSON，请重试。');
  }
  final decoded = tryDecodeJson(block);
  if (decoded == null) {
    throw const FormatException('模型返回的 JSON 格式有误，请重试。');
  }

  List<dynamic> items = const [];
  String summary = '';
  if (decoded is List) {
    items = decoded;
  } else if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    summary = pickFirstString(map, const ['summary', 'reply', 'message']);
    for (final key in const ['holidays', 'days', 'dates', 'list']) {
      final value = map[key];
      if (value is List) {
        items = value;
        break;
      }
    }
  } else {
    throw const FormatException('模型返回的 JSON 既不是对象也不是数组。');
  }

  final drafts = <HolidayDraft>[];
  final warnings = <String>[];
  final seenDates = <String>{};
  for (final rawItem in items) {
    if (rawItem is! Map) continue;
    final item = Map<String, dynamic>.from(rawItem);
    final name = pickFirstString(item, const ['name', 'holiday', 'title', '节日'])
        .trim();
    final dates = _datesFromItem(item, fallbackYear);
    if (dates.isEmpty) {
      warnings.add('跳过了一条没有有效日期的节假日');
      continue;
    }
    final unique = <DateTime>[];
    for (final date in dates) {
      final key = Holiday.formatDateKey(date);
      if (!seenDates.add(key)) continue;
      unique.add(date);
    }
    if (unique.isEmpty) continue;
    unique.sort();
    drafts.add(HolidayDraft(
      name: name.isEmpty ? '节假日' : name,
      dates: unique,
    ));
  }

  if (drafts.isEmpty) {
    throw const FormatException('没有解析出有效的放假日期，请换一种说法。');
  }
  return HolidayAiPlan(
    summary: summary,
    drafts: drafts,
    warnings: warnings,
  );
}

String pickFirstString(Map<String, dynamic> j, List<String> keys) {
  for (final key in keys) {
    final value = asString(j[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<DateTime> _datesFromItem(Map<String, dynamic> item, int year) {
  final dates = <DateTime>[];
  for (final raw in asList(item['dates'])) {
    final parsed = _parseDate(raw, year);
    if (parsed != null) dates.add(parsed);
  }
  final single = _parseDate(
    item['date'] ?? item['day'] ?? item['startDate'] ?? item['start'],
    year,
  );
  if (single != null) dates.add(single);

  final start = _parseDate(item['startDate'] ?? item['start'], year);
  final end = _parseDate(item['endDate'] ?? item['end'], year);
  if (start != null && end != null && !end.isBefore(start)) {
    final span = end.difference(start).inDays;
    if (span > 60) return const <DateTime>[];
    for (var i = 0; i <= span; i++) {
      dates.add(DateTime(start.year, start.month, start.day + i));
    }
  }
  return dates;
}

DateTime? _parseDate(dynamic raw, int fallbackYear) {
  final text = asString(raw);
  if (text.isEmpty) return null;
  final full = DateTime.tryParse(text);
  if (full != null) return DateTime(full.year, full.month, full.day);

  final match = RegExp(r'(\d{1,2})\s*[月/\-.]\s*(\d{1,2})').firstMatch(text);
  if (match == null) return null;
  final month = int.tryParse(match.group(1)!);
  final day = int.tryParse(match.group(2)!);
  if (month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(fallbackYear, month, day);
  if (date.month != month || date.day != day) return null;
  return date;
}
