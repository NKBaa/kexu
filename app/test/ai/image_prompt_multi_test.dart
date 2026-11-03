import 'package:course_timetable/features/ai/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildImageToTimetablePrompt 多图规则', () {
    test('默认参数（单图）不出现多图说明，且与显式 imageCount=1 完全一致', () {
      final byDefault = buildImageToTimetablePrompt(totalWeeks: 16);
      final explicit = buildImageToTimetablePrompt(
        totalWeeks: 16,
        imageCount: 1,
        imageOffset: 0,
      );
      expect(byDefault, explicit);
      expect(byDefault, isNot(contains('本次一次提供了')));
      expect(byDefault, isNot(contains('分批识别')));

      // 原有输出契约不受影响
      expect(byDefault, contains('"date"'));
      expect(byDefault, contains('"courses"'));
      expect(byDefault, contains('1~16'));
      expect(byDefault, contains('dayOfWeek'));
      expect(byDefault, contains('sessions'));
      expect(byDefault, contains('单周'));
      expect(byDefault, contains('双周'));
    });

    test('多图时要求合并成一份课表，并说明单周/双周周次合并', () {
      final p = buildImageToTimetablePrompt(totalWeeks: 18, imageCount: 3);
      expect(p, contains('3 张图片'));
      expect(p, contains('第 1-3 张'));
      expect(p, contains('同一份课表'));
      expect(p, contains('合并'));
      expect(p, contains('单周'));
      expect(p, contains('双周'));
      expect(p, contains('并集'));
      expect(p, contains('sessions'));
      expect(p, contains('1~18'));
    });

    test('分批偏移量体现在提示词里', () {
      final p = buildImageToTimetablePrompt(
        totalWeeks: 16,
        imageCount: 2,
        imageOffset: 4,
      );
      expect(p, contains('2 张图片'));
      expect(p, contains('第 5-6 张'));
    });

    test('单张续批（offset>0、imageCount=1）提示这是分批识别之一', () {
      final p = buildImageToTimetablePrompt(
        totalWeeks: 16,
        imageCount: 1,
        imageOffset: 4,
      );
      expect(p, contains('第 5 张'));
      expect(p, contains('分批'));
      expect(p, isNot(contains('本次一次提供了')));
    });

    test('多图说明与补充说明可以共存', () {
      final p = buildImageToTimetablePrompt(
        totalWeeks: 16,
        imageCount: 2,
        extraHint: '这是 2026 春季学期，共 16 周',
      );
      expect(p, contains('2 张图片'));
      expect(p, contains('这是 2026 春季学期'));
      expect(p, contains('用户补充说明'));
    });

    test('非法参数回退：imageCount<=0 按单图、imageOffset<0 按 0', () {
      final p = buildImageToTimetablePrompt(
        totalWeeks: 16,
        imageCount: 0,
        imageOffset: -3,
      );
      expect(p, isNot(contains('本次一次提供了')));
      expect(p, isNot(contains('分批识别')));
      expect(p, contains('1~16'));
    });
  });
}
