import 'package:course_timetable/features/settings/holiday_ai.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI 节假日解析', () {
    test('日期范围展开为逐天草稿', () {
      final plan = parseHolidayAiOutput(
        '{"summary":"国庆放假","holidays":[{"name":"国庆节",'
        '"startDate":"2026-10-01","endDate":"2026-10-07"}]}',
        fallbackYear: 2026,
      );
      expect(plan.summary, '国庆放假');
      expect(plan.drafts, hasLength(1));
      expect(plan.drafts.single.name, '国庆节');
      expect(plan.drafts.single.dates, hasLength(7));
      expect(plan.drafts.single.dates.first, DateTime(2026, 10, 1));
      expect(plan.drafts.single.dates.last, DateTime(2026, 10, 7));
    });

    test('兼容数组、中文日期与单天日期', () {
      final plan = parseHolidayAiOutput(
        '[{"name":"校运会","date":"11月6日"},'
        '{"name":"元旦","date":"1/1"}]',
        fallbackYear: 2026,
      );
      expect(plan.drafts, hasLength(2));
      expect(plan.drafts.first.dates.single, DateTime(2026, 11, 6));
      expect(plan.drafts.last.dates.single, DateTime(2026, 1, 1));
    });

    test('同一日期去重', () {
      final plan = parseHolidayAiOutput(
        '{"holidays":[{"name":"国庆节","date":"2026-10-01"},'
        '{"name":"国庆节","date":"2026-10-01"}]}',
        fallbackYear: 2026,
      );
      expect(plan.drafts.single.dates, hasLength(1));
    });

    test('无 JSON 或空日期时抛 FormatException', () {
      expect(
        () => parseHolidayAiOutput('好的，我来帮你设置', fallbackYear: 2026),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseHolidayAiOutput(
          '{"holidays":[{"name":"国庆节"}]}',
          fallbackYear: 2026,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('提示词包含当前年份和用户描述', () {
      final prompt = buildHolidayAiPrompt(
        instruction: '国庆放假 7 天',
        today: DateTime(2026, 9, 1),
      );
      expect(prompt, contains('2026-09-01'));
      expect(prompt, contains('国庆放假 7 天'));
      expect(prompt, contains('yyyy-MM-dd'));
    });
  });
}
