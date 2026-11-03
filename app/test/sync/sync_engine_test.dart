import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Course course(
  String id,
  String name, {
  int day = 1,
  int start = 1,
  int end = 2,
  List<int> weeks = const [1, 2, 3],
  String? location,
  String? teacher,
}) =>
    Course(
      id: id,
      semesterId: 'sem',
      name: name,
      teacher: teacher,
      colorIndex: 0,
      sessions: [
        Session(
          id: '$id-s1',
          dayOfWeek: day,
          startPeriod: start,
          endPeriod: end,
          weeks: weeks,
          location: location,
        ),
      ],
    );

Timetable table(List<Course> courses, {String name = '2026 春季学期'}) => Timetable(
      semester: Semester(
        id: 'sem',
        name: name,
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: courses,
    );

void main() {
  const engine = SyncEngine();

  group('contentHash 内容哈希', () {
    test('相同内容得到相同哈希', () {
      expect(contentHash({'a': 1, 'b': [1, 2]}), contentHash({'a': 1, 'b': [1, 2]}));
    });

    test('不同内容得到不同哈希', () {
      expect(contentHash({'a': 1}), isNot(contentHash({'a': 2})));
    });

    test('中文内容稳定', () {
      expect(contentHash({'name': '高等数学'}), contentHash({'name': '高等数学'}));
      expect(contentHash({'name': '高等数学'}), isNot(contentHash({'name': '大学英语'})));
    });

    test('哈希为 8 位十六进制（且不为负）', () {
      expect(contentHash('x'), matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(contentHash({'name': '高等数学'}), matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(contentHash({'a': List.generate(50, (i) => i)}),
          matches(RegExp(r'^[0-9a-f]{8}$')));
    });
  });

  group('首次同步（无基线）', () {
    test('两端各自新增的课程会被合并到一起', () {
      final local = table([course('a', '本机新增课')]);
      final remote = table([course('b', '远端新增课')]);

      final r = engine.merge(local: local, remote: remote);

      expect(r.merged.courses.map((c) => c.name), containsAll(['本机新增课', '远端新增课']));
      expect(r.merged.courses.length, 2);
      expect(r.conflicts, isEmpty);
    });

    test('同 id 同内容不产生冲突', () {
      final c = course('a', '高等数学');
      final r = engine.merge(
        local: table([c]),
        remote: table([c]),
      );
      expect(r.merged.courses.length, 1);
      expect(r.conflicts, isEmpty);
      expect(r.differsFromLocal, isFalse);
      expect(r.differsFromRemote, isFalse);
    });
  });

  group('三方合并：只有一端改动', () {
    test('本机改了、远端没改 → 采用本机', () {
      final base = table([course('a', '高等数学', weeks: [1, 2, 3])]);
      final local = table([course('a', '高等数学', weeks: [1, 3, 5])]); // 改成单周
      final remote = table([course('a', '高等数学', weeks: [1, 2, 3])]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses.single.sessions.single.weeks, [1, 3, 5]);
      expect(r.conflicts, isEmpty);
      expect(r.differsFromRemote, isTrue, reason: '远端需要被更新');
      expect(r.differsFromLocal, isFalse);
    });

    test('远端改了、本机没改 → 采用远端', () {
      final base = table([course('a', '高等数学', location: 'A101')]);
      final local = table([course('a', '高等数学', location: 'A101')]);
      final remote = table([course('a', '高等数学', location: 'B203')]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses.single.sessions.single.location, 'B203');
      expect(r.conflicts, isEmpty);
      expect(r.differsFromLocal, isTrue, reason: '本地需要被更新');
      expect(r.differsFromRemote, isFalse);
      expect(r.tookRemote, 1);
    });
  });

  group('三方合并：并行修改不同课程（核心场景）', () {
    test('电脑加了一门课、手机删了另一门课，两者都不丢', () {
      final base = table([
        course('a', '高等数学'),
        course('b', '大学英语'),
      ]);
      // 本机（电脑）：删了 b
      final local = table([course('a', '高等数学')]);
      // 远端（手机）：加了 c
      final remote = table([
        course('a', '高等数学'),
        course('b', '大学英语'),
        course('c', '数据结构'),
      ]);

      final r = engine.merge(local: local, remote: remote, base: base);

      final names = r.merged.courses.map((c) => c.name).toSet();
      expect(names, contains('高等数学'));
      expect(names, contains('数据结构'), reason: '远端新增的课必须保留');
      expect(names, isNot(contains('大学英语')), reason: '本机的删除必须生效');
      expect(r.conflicts, isEmpty, reason: '并行修改不同课程不应算冲突');
    });

    test('两端各改一门不同的课，两处改动都保留', () {
      final base = table([
        course('a', '高等数学', location: 'A101'),
        course('b', '大学英语', location: 'C305'),
      ]);
      final local = table([
        course('a', '高等数学', location: 'A999'), // 本机改了 a 的地点
        course('b', '大学英语', location: 'C305'),
      ]);
      final remote = table([
        course('a', '高等数学', location: 'A101'),
        course('b', '大学英语', location: 'C888'), // 远端改了 b 的地点
      ]);

      final r = engine.merge(local: local, remote: remote, base: base);

      final byName = {for (final c in r.merged.courses) c.name: c};
      expect(byName['高等数学']!.sessions.single.location, 'A999');
      expect(byName['大学英语']!.sessions.single.location, 'C888');
      expect(r.conflicts, isEmpty);
    });
  });

  group('三方合并：删除语义', () {
    test('本机删除、远端没改 → 删除生效', () {
      final base = table([course('a', '高数'), course('b', '英语')]);
      final local = table([course('a', '高数')]);
      final remote = table([course('a', '高数'), course('b', '英语')]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses.length, 1);
      expect(r.localDeleted, 1);
      expect(r.conflicts, isEmpty);
    });

    test('远端删除、本机没改 → 删除生效', () {
      final base = table([course('a', '高数'), course('b', '英语')]);
      final local = table([course('a', '高数'), course('b', '英语')]);
      final remote = table([course('a', '高数')]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses.length, 1);
      expect(r.remoteDeleted, 1);
      expect(r.conflicts, isEmpty);
    });

    test('两端都删了 → 保持删除，不复活', () {
      final base = table([course('a', '高数'), course('b', '英语')]);
      final local = table([course('a', '高数')]);
      final remote = table([course('a', '高数')]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses.length, 1);
      expect(r.merged.courses.single.name, '高数');
    });
  });

  group('三方合并：真冲突（两端改同一门课）', () {
    test('两端都改同一门课 → 保留本机并记录冲突', () {
      final base = table([course('a', '高等数学', location: 'A101')]);
      final local = table([course('a', '高等数学', location: 'A-local')]);
      final remote = table([course('a', '高等数学', location: 'A-remote')]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses.single.sessions.single.location, 'A-local');
      expect(r.conflicts, hasLength(1));
      expect(r.conflicts.single.subject, '高等数学');
      expect(r.conflicts.single.resolvedBy, 'local');
      expect(r.hasConflicts, isTrue);
    });

    test('本机改了、远端删了 → 保留本机并记录冲突', () {
      final base = table([course('a', '高等数学')]);
      final local = table([course('a', '高等数学', weeks: [1, 3, 5])]);
      final remote = table([]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses, hasLength(1));
      expect(r.conflicts, hasLength(1));
      expect(r.conflicts.single.description, contains('远端已删除'));
    });

    test('远端改了、本机删了 → 保留远端并记录冲突（不丢远端新改动）', () {
      final base = table([course('a', '高等数学')]);
      final local = table([]);
      final remote = table([course('a', '高等数学', location: '新教室')]);

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.courses, hasLength(1));
      expect(r.merged.courses.single.sessions.single.location, '新教室');
      expect(r.conflicts, hasLength(1));
      expect(r.conflicts.single.resolvedBy, 'remote');
    });
  });

  group('学期与作息设置', () {
    test('只有一端改学期 → 采用改动的那端', () {
      final base = table([], name: '2026 春季学期');
      final local = table([], name: '2026 春季学期');
      final remote = table([], name: '2026 春季学期（改）');

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.semester.name, '2026 春季学期（改）');
    });

    test('两端都改学期 → 本机优先并记录冲突', () {
      final base = table([], name: '原始');
      final local = table([], name: '本机改的');
      final remote = table([], name: '远端改的');

      final r = engine.merge(local: local, remote: remote, base: base);

      expect(r.merged.semester.name, '本机改的');
      expect(r.conflicts.any((c) => c.subject == '学期设置'), isTrue);
    });
  });

  group('幂等性与稳定性（防止同步抖动）', () {
    test('合并结果再次合并不会继续变化（收敛）', () {
      final base = table([course('a', '高数')]);
      final local = table([course('a', '高数'), course('b', '英语')]);
      final remote = table([course('a', '高数'), course('c', '物理')]);

      final r1 = engine.merge(local: local, remote: remote, base: base);
      final r2 = engine.merge(local: r1.merged, remote: r1.merged, base: r1.merged);

      expect(r2.differsFromLocal, isFalse);
      expect(r2.differsFromRemote, isFalse);
      expect(r2.merged.courses.length, r1.merged.courses.length);
    });

    test('课程顺序稳定（同样的输入得到同样的顺序）', () {
      final local = table([
        course('z', 'Z课', day: 5, start: 7),
        course('a', 'A课', day: 1, start: 1),
        course('m', 'M课', day: 3, start: 5),
      ]);
      final remote = table([
        course('m', 'M课', day: 3, start: 5),
        course('z', 'Z课', day: 5, start: 7),
        course('a', 'A课', day: 1, start: 1),
      ]);

      final r = engine.merge(local: local, remote: remote);

      expect(r.merged.courses.map((c) => c.name).toList(), ['A课', 'M课', 'Z课']);
    });

    test('内容相同但顺序不同 → 不认为有差异', () {
      final a = table([course('x', 'X', day: 1), course('y', 'Y', day: 3)]);
      final b = table([course('y', 'Y', day: 3), course('x', 'X', day: 1)]);

      final r = engine.merge(local: a, remote: b);

      expect(r.differsFromLocal, isFalse, reason: '排序后应判定为一致');
      expect(r.differsFromRemote, isFalse);
    });
  });

  group('摘要文本', () {
    test('无改动时给出明确说明', () {
      final t = table([course('a', '高数')]);
      final r = engine.merge(local: t, remote: t);
      expect(r.summary, contains('一致'));
    });

    test('有新增时摘要包含统计', () {
      final r = engine.merge(
        local: table([course('a', '高数')]),
        remote: table([course('b', '英语')]),
      );
      expect(r.summary, contains('新增'));
    });
  });
}
