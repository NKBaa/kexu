import 'package:course_timetable/core/utils/week_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWeeks 解析各种不规律周次写法', () {
    test('连续区间', () {
      expect(parseWeeks('1-16'), List.generate(16, (i) => i + 1));
      expect(parseWeeks('第1-16周'), List.generate(16, (i) => i + 1));
    });

    test('断续区间（本项目的核心痛点）', () {
      expect(parseWeeks('3-5,7-9'), [3, 4, 5, 7, 8, 9]);
      expect(parseWeeks('1-8周,10-16周'), [
        1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16,
      ]);
    });

    test('零散单点', () {
      expect(parseWeeks('1,3,5'), [1, 3, 5]);
      expect(parseWeeks('1,3,5,7,9'), [1, 3, 5, 7, 9]);
    });

    test('单周 / 双周（带范围与不带范围）', () {
      expect(parseWeeks('1-8周(单)'), [1, 3, 5, 7]);
      expect(parseWeeks('1-8周(双)'), [2, 4, 6, 8]);
      expect(parseWeeks('单周'), [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(parseWeeks('双周'), [2, 4, 6, 8, 10, 12, 14, 16]);
    });

    test('全角符号与「至」等中文写法', () {
      expect(parseWeeks('１－４'), [1, 2, 3, 4]);
      expect(parseWeeks('3至5'), [3, 4, 5]);
      expect(parseWeeks('1，3，5'), [1, 3, 5]);
    });

    test('空值与无法识别的输入返回空列表', () {
      expect(parseWeeks(null), isEmpty);
      expect(parseWeeks(''), isEmpty);
      expect(parseWeeks('待定'), isEmpty);
    });
  });

  group('formatWeeks 压缩展示', () {
    test('连续区间', () {
      expect(formatWeeks([1, 2, 3, 4, 5, 6, 7, 8]), '1-8周');
    });

    test('全奇数区间标为单周', () {
      expect(formatWeeks([1, 3, 5, 7]), '1-7周(单)');
    });

    test('全偶数区间标为双周', () {
      expect(formatWeeks([2, 4, 6, 8]), '2-8周(双)');
    });

    test('多段区间', () {
      expect(formatWeeks([1, 2, 3, 5, 6]), '1-3,5-6周');
    });

    test('单个周次', () {
      expect(formatWeeks([3]), '3周');
    });

    test('空列表返回空串', () {
      expect(formatWeeks([]), '');
    });
  });

  group('解析与展示可往返', () {
    test('不规律周次往返一致', () {
      const raw = '1-4,6,8-10';
      final weeks = parseWeeks(raw);
      expect(weeks, [1, 2, 3, 4, 6, 8, 9, 10]);
      // 再解析回来应得到同一集合
      expect(parseWeeks(formatWeeks(weeks)), weeks);
    });

    test('单周往返一致', () {
      final weeks = parseWeeks('1-16周(单)');
      expect(weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(parseWeeks(formatWeeks(weeks)), weeks);
    });
  });

  group('日期换算', () {
    final start = DateTime(2026, 2, 23); // 周一

    test('第 1 周周一是开学日', () {
      expect(mondayOf(start), DateTime(2026, 2, 23));
      expect(weekOfDate(start, start), 1);
    });

    test('同一周内任意一天都算第 1 周', () {
      expect(weekOfDate(DateTime(2026, 2, 27), start), 1); // 周五
      expect(weekOfDate(DateTime(2026, 3, 1), start), 1); // 周日
      expect(weekOfDate(DateTime(2026, 3, 2), start), 2); // 下周一
    });

    test('按周次取具体日期', () {
      expect(dateOfWeekDay(start, 1, 1), DateTime(2026, 2, 23));
      expect(dateOfWeekDay(start, 1, 7), DateTime(2026, 3, 1));
      expect(dateOfWeekDay(start, 3, 3), DateTime(2026, 3, 11));
    });

    test('跨夏令时/月末仍按自然日计算', () {
      // 第 16 周周一 = 开学 + 15 周
      expect(dateOfWeekDay(start, 16, 1), DateTime(2026, 6, 8));
      expect(weekOfDate(DateTime(2026, 6, 8), start), 16);
    });
  });

  group('节次归一化', () {
    test('自动纠正起止颠倒', () {
      final p = normalizePeriods(5, 3);
      expect(p.start, 3);
      expect(p.end, 5);
    });

    test('下限为 1', () {
      final p = normalizePeriods(0, 2);
      expect(p.start, 1);
      expect(p.end, 2);
    });
  });

  test('weekdayName 输出中文星期', () {
    expect(weekdayName(1), '周一');
    expect(weekdayName(7), '周日');
  });

  test('startMondayForWeek：已知今天第 N 周反推第 1 周周一', () {
    // 2026-11-01 是周日，所在周周一是 2026-10-26。
    final today = DateTime(2026, 11, 1);
    expect(startMondayForWeek(today, 1), DateTime(2026, 10, 26));
    expect(startMondayForWeek(today, 2), DateTime(2026, 10, 19));
    expect(startMondayForWeek(today, 10), DateTime(2026, 8, 24));
    // 非法周次按第 1 周处理，保证永远能算出周一。
    expect(startMondayForWeek(today, 0), DateTime(2026, 10, 26));
  });
}
