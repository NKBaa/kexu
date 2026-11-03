import 'package:course_timetable/core/utils/conflict_utils.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:flutter_test/flutter_test.dart';

/// 冲突判定是「同一时段多课并存」功能的基石，这里锁定它的精确语义：
/// 星期相同 + 节次相交 + 周次相交，三者缺一不可。
///
/// 特别地：单周课与双周课同节次是**合法排课**，绝不能误报成冲突。
void main() {
  const allWeeks = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
  const oddWeeks = [1, 3, 5, 7, 9, 11, 13, 15];
  const evenWeeks = [2, 4, 6, 8, 10, 12, 14, 16];

  Session session({
    required String id,
    int dayOfWeek = 1,
    int startPeriod = 1,
    int endPeriod = 2,
    List<int> weeks = allWeeks,
    String? location,
  }) =>
      Session(
        id: id,
        dayOfWeek: dayOfWeek,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        weeks: weeks,
        location: location,
      );

  Course course(String id, String name, int colorIndex) => Course(
        id: id,
        semesterId: 'sem1',
        name: name,
        colorIndex: colorIndex,
      );

  SessionEntry entry(Session s, {Course? c}) => SessionEntry(
        course: c ?? course('c-${s.id}', '课程${s.id}', 0),
        session: s,
      );

  group('sessionsConflict 判定规则', () {
    test('同天同节次且周次相交 -> 冲突', () {
      expect(
        sessionsConflict(
          session(id: 'a', startPeriod: 1, endPeriod: 2),
          session(id: 'b', startPeriod: 1, endPeriod: 2),
        ),
        isTrue,
      );
    });

    test('同天同节次但周次不相交（单周 vs 双周）-> 不冲突', () {
      expect(
        sessionsConflict(
          session(id: 'odd', weeks: oddWeeks),
          session(id: 'even', weeks: evenWeeks),
        ),
        isFalse,
      );
    });

    test('同天节次部分重叠（1-2 与 2-3）-> 冲突', () {
      expect(
        sessionsConflict(
          session(id: 'a', startPeriod: 1, endPeriod: 2),
          session(id: 'b', startPeriod: 2, endPeriod: 3),
        ),
        isTrue,
      );
      // 对称，且参数顺序无关
      expect(
        sessionsConflict(
          session(id: 'b', startPeriod: 2, endPeriod: 3),
          session(id: 'a', startPeriod: 1, endPeriod: 2),
        ),
        isTrue,
      );
    });

    test('同天节次完全包含（1-4 与 2-3）-> 冲突', () {
      expect(
        sessionsConflict(
          session(id: 'a', startPeriod: 1, endPeriod: 4),
          session(id: 'b', startPeriod: 2, endPeriod: 3),
        ),
        isTrue,
      );
    });

    test('同天节次完全不相邻（1-2 与 5-6）-> 不冲突', () {
      expect(
        sessionsConflict(
          session(id: 'a', startPeriod: 1, endPeriod: 2),
          session(id: 'b', startPeriod: 5, endPeriod: 6),
        ),
        isFalse,
      );
    });

    test('不同天即使节次与周次都相同 -> 不冲突', () {
      expect(
        sessionsConflict(
          session(id: 'a', dayOfWeek: 1),
          session(id: 'b', dayOfWeek: 2),
        ),
        isFalse,
      );
    });

    test('节次相交但周次只有部分交集 -> 冲突', () {
      expect(
        sessionsConflict(
          session(id: 'a', weeks: [1, 2, 3]),
          session(id: 'b', weeks: [3, 4, 5]),
        ),
        isTrue,
      );
    });

    test('周次列表为空时永远不算冲突（该时段不生效）', () {
      expect(
        sessionsConflict(
          session(id: 'a', weeks: const []),
          session(id: 'b', weeks: allWeeks),
        ),
        isFalse,
      );
    });
  });

  group('weeksOverlap 周次交集', () {
    test('有交集 / 无交集 / 空列表', () {
      expect(weeksOverlap([1, 3, 5], [5, 7]), isTrue);
      expect(weeksOverlap(oddWeeks, evenWeeks), isFalse);
      expect(weeksOverlap(const [], allWeeks), isFalse);
      expect(weeksOverlap(allWeeks, const []), isFalse);
    });
  });

  group('findConflicts 冲突对', () {
    test('两门课撞车 -> 恰好一个冲突对', () {
      final a = entry(session(id: 'a'));
      final b = entry(session(id: 'b'));
      final pairs = findConflicts([a, b]);

      expect(pairs, hasLength(1));
      expect({pairs.single.a.session.id, pairs.single.b.session.id}, {'a', 'b'});
    });

    test('单双周同节次 -> 没有冲突对', () {
      final odd = entry(session(id: 'odd', weeks: oddWeeks));
      final even = entry(session(id: 'even', weeks: evenWeeks));

      expect(findConflicts([odd, even]), isEmpty);
    });

    test('相邻但不重叠（1-2 与 3-4）-> 没有冲突对', () {
      final a = entry(session(id: 'a', startPeriod: 1, endPeriod: 2));
      final b = entry(session(id: 'b', startPeriod: 3, endPeriod: 4));

      expect(findConflicts([a, b]), isEmpty);
    });

    test('三门课同时撞车 -> 识别出全部 3 个冲突对（不重复计数）', () {
      final a = entry(session(id: 'a', startPeriod: 1, endPeriod: 2));
      final b = entry(session(id: 'b', startPeriod: 1, endPeriod: 3));
      final c = entry(session(id: 'c', startPeriod: 2, endPeriod: 4));

      final pairs = findConflicts([a, b, c]);

      expect(pairs, hasLength(3));
      final pairIds = pairs.map((p) => {p.a.session.id, p.b.session.id}).toList();
      expect(pairIds, containsAll(<Set<String>>[
        {'a', 'b'},
        {'a', 'c'},
        {'b', 'c'},
      ]));
    });

    test('不相关的时段不会产生冲突对', () {
      final a = entry(session(id: 'a', startPeriod: 1, endPeriod: 2));
      final b = entry(session(id: 'b', startPeriod: 1, endPeriod: 2));
      final c = entry(session(id: 'c', startPeriod: 5, endPeriod: 6));
      final d = entry(session(id: 'd', dayOfWeek: 2));

      final pairs = findConflicts([a, b, c, d]);

      expect(pairs, hasLength(1));
      expect({pairs.single.a.session.id, pairs.single.b.session.id}, {'a', 'b'});
    });

    test('空列表 -> 空结果', () {
      expect(findConflicts(const []), isEmpty);
    });
  });

  group('conflictedSessionIds 快速查询', () {
    test('只返回真正冲突的时段 id', () {
      final a = entry(session(id: 'a', startPeriod: 1, endPeriod: 2));
      final b = entry(session(id: 'b', startPeriod: 2, endPeriod: 3));
      final lonely = entry(session(id: 'lonely', startPeriod: 8, endPeriod: 9));
      final otherDay = entry(session(id: 'otherDay', dayOfWeek: 3));

      final ids = conflictedSessionIds([a, b, lonely, otherDay]);

      expect(ids, {'a', 'b'});
    });

    test('三门课撞车时三段 id 都在集合里', () {
      final ids = conflictedSessionIds([
        entry(session(id: 'a', startPeriod: 1, endPeriod: 2)),
        entry(session(id: 'b', startPeriod: 1, endPeriod: 3)),
        entry(session(id: 'c', startPeriod: 2, endPeriod: 4)),
      ]);

      expect(ids, {'a', 'b', 'c'});
    });

    test('只有单双周错开 -> 空集合（不能误报）', () {
      final ids = conflictedSessionIds([
        entry(session(id: 'odd', weeks: oddWeeks)),
        entry(session(id: 'even', weeks: evenWeeks)),
      ]);

      expect(ids, isEmpty);
    });

    test('同一个 Session 出现在列表里两次不算自冲突', () {
      final s = entry(session(id: 'dup'));

      expect(conflictedSessionIds([s, s]), isEmpty);
    });
  });
}
