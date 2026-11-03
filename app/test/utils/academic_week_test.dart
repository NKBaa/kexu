import 'package:course_timetable/core/utils/week_utils.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「读取系统时间确定当前日期」的换算逻辑测试。
///
/// 关注点：把「今天」（`DateTime.now()` 给出的系统时间）正确映射到
/// **教学周次**与**星期**，这是课表「本周/今天」显示的基础。
void main() {
  group('weekOfDate：日期 → 教学周', () {
    test('起始日是周一时，逐周换算正确', () {
      final start = DateTime(2026, 10, 12); // 周一
      for (var w = 1; w <= 10; w++) {
        final monday = start.add(Duration(days: (w - 1) * 7));
        expect(weekOfDate(monday, start), w, reason: '第 $w 周的周一');
        expect(weekOfDate(monday.add(const Duration(days: 6)), start), w,
            reason: '第 $w 周的周日');
      }
    });

    test('起始日不是周一时，会归一到所在周的周一', () {
      final startWednesday = DateTime(2026, 10, 14); // 周三
      expect(weekOfDate(DateTime(2026, 10, 12), startWednesday), 1,
          reason: '该周周一属于第 1 周');
      expect(weekOfDate(DateTime(2026, 10, 18), startWednesday), 1,
          reason: '周日仍属第 1 周');
      expect(weekOfDate(DateTime(2026, 10, 19), startWednesday), 2);
    });

    test('早于开学周返回 <= 0，由调用方判断', () {
      final start = DateTime(2026, 10, 12);
      expect(weekOfDate(DateTime(2026, 10, 5), start), lessThan(1));
    });

    test('时间部分不影响结果（系统时间带时分秒也正确）', () {
      final start = DateTime(2026, 10, 12);
      for (final h in [0, 9, 12, 23]) {
        final t = DateTime(2026, 10, 19, h, 59, 59);
        expect(weekOfDate(t, start), 2,
            reason: '第 2 周任意时刻都应是第 2 周（$h 时）');
      }
    });

    test('跨年学期换算正确', () {
      final start = DateTime(2026, 12, 28); // 周一
      expect(weekOfDate(DateTime(2027, 1, 11), start), 3);
      expect(weekOfDate(DateTime(2027, 2, 22), start), 9);
    });
  });

  group('dateOfWeekDay：周次 + 星期 → 具体日期', () {
    test('第 1 周周一就是起始周一', () {
      final start = DateTime(2026, 10, 12);
      expect(dateOfWeekDay(start, 1, 1), DateTime(2026, 10, 12));
    });

    test('第 2 周周五', () {
      final start = DateTime(2026, 10, 12);
      expect(dateOfWeekDay(start, 2, 5), DateTime(2026, 10, 23));
    });

    test('与 weekOfDate 互为逆运算', () {
      final start = DateTime(2026, 10, 12);
      for (var w = 1; w <= 8; w++) {
        for (var d = 1; d <= 7; d++) {
          final date = dateOfWeekDay(start, w, d);
          expect(weekOfDate(date, start), w,
              reason: '第 $w 周星期 $d 反算周次应一致');
          expect(date.weekday, d, reason: '星期应是 $d');
        }
      }
    });
  });

  group('academicWeekProvider 的换算（已修复）', () {
    /// 修复后的实现：复用 weekOfDate（会把起始日归一到周一）。
    int fixedWay(DateTime today, DateTime start) => weekOfDate(today, start);

    /// 修复前的实现：直接用 difference，不归一（有 bug）。
    int oldWay(DateTime today, DateTime start) {
      final s = DateTime(start.year, start.month, start.day);
      final t = DateTime(today.year, today.month, today.day);
      return t.difference(s).inDays ~/ 7 + 1;
    }

    test('起始日是周一时，两者完全一致（修复不影响常规情况）', () {
      final start = DateTime(2026, 10, 12);
      for (var w = 1; w <= 10; w++) {
        for (var d = 0; d < 7; d++) {
          final day = start.add(Duration(days: (w - 1) * 7 + d));
          expect(fixedWay(day, start), oldWay(day, start), reason: '$day');
        }
      }
    });

    test('修复前周日开学会把第 2 周错算成第 1 周', () {
      final startSunday = DateTime(2026, 10, 18); // 周日开学
      final nextMonday = DateTime(2026, 10, 19); // 下周一是第 2 周

      expect(fixedWay(nextMonday, startSunday), 2, reason: '修复后正确');
      expect(oldWay(nextMonday, startSunday), 1,
          reason: '修复前少算一周 —— 这就是被修掉的 bug');
    });

    test('修复后跨周换算始终递增且正确', () {
      final startSunday = DateTime(2026, 10, 18);
      for (var w = 1; w <= 8; w++) {
        final date = dateOfWeekDay(startSunday, w, 1);
        expect(fixedWay(date, startSunday), w,
            reason: '第 $w 周周一应算出 $w');
      }
    });
  });

  group('Semester 模型', () {
    test('totalWeeks 与 allWeeks 一致', () {
      final s = Semester(
        id: 's1',
        name: '测试学期',
        startMonday: DateTime(2026, 10, 12),
        totalWeeks: 20,
      );
      expect(s.allWeeks.first, 1);
      expect(s.allWeeks.last, 20);
      expect(s.allWeeks.length, 20);
    });
  });
}
