import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/repositories/timetable_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('timetable_test_');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  Timetable sampleTimetable() => Timetable(
        semester: Semester(
          id: 'sem1',
          name: '2026 春季学期',
          startMonday: DateTime(2026, 2, 23),
          totalWeeks: 16,
        ),
        timeSlots: defaultTimeSlots(),
        courses: [
          Course(
            id: 'c1',
            semesterId: 'sem1',
            name: '高等数学',
            teacher: '张老师',
            colorIndex: 3,
            sessions: const [
              Session(
                id: 'ss1',
                dayOfWeek: 1,
                startPeriod: 1,
                endPeriod: 2,
                // 刻意用一个不规律的周次组合
                weeks: [1, 3, 5, 7, 9],
                location: 'A101',
              ),
            ],
          ),
        ],
      );

  group('DocumentStore 读写', () {
    test('文件不存在时返回 null', () async {
      final store = DocumentStore('t.json', baseDirectory: root);
      expect(await store.readJson(), isNull);
    });

    test('写入后可原样读出', () async {
      final store = DocumentStore('t.json', baseDirectory: root);
      await store.writeJson({'a': 1, 'nested': {'b': [1, 2, 3]}});
      final back = await store.readJson();
      expect(back, isNotNull);
      expect(back!['a'], 1);
      expect((back['nested'] as Map)['b'], [1, 2, 3]);
    });

    test('重复写入会保留备份文件', () async {
      final store = DocumentStore('t.json', baseDirectory: root, backupKeep: 5);
      await store.writeJson({'v': 1});
      await store.writeJson({'v': 2});
      await store.writeJson({'v': 3});
      final backups = await store.listBackups();
      expect(backups.length, greaterThanOrEqualTo(2));
      // 最新内容应是第 3 次写入
      expect((await store.readJson())!['v'], 3);
    });

    test('备份数量受 backupKeep 限制', () async {
      final store = DocumentStore('t.json', baseDirectory: root, backupKeep: 3);
      for (var i = 0; i < 10; i++) {
        await store.writeJson({'v': i});
      }
      final backups = await store.listBackups();
      expect(backups.length, lessThanOrEqualTo(3));
    });

    test('文件内容损坏时可从备份恢复', () async {
      final store = DocumentStore('t.json', baseDirectory: root);
      await store.writeJson({'v': 'good'});
      await store.writeJson({'v': 'newer'}); // 产生一份备份

      // 把主文件写坏
      final f = File('${(await store.directory()).path}${Platform.pathSeparator}t.json');
      await f.writeAsString('{ this is not valid json');

      final recovered = await store.readJson();
      expect(recovered, isNotNull, reason: '应从备份恢复而不是返回 null');
      expect(recovered!['v'], 'good');
    });

    test('delete 会移除数据文件', () async {
      final store = DocumentStore('t.json', baseDirectory: root);
      await store.writeJson({'v': 1});
      await store.delete();
      expect(await store.readJson(), isNull);
    });

    test('absolutePath 返回真实路径', () async {
      final store = DocumentStore('t.json', baseDirectory: root);
      final p = await store.absolutePath();
      expect(p, contains('course_timetable'));
      expect(p, endsWith('t.json'));
    });
  });

  group('TimetableRepository 持久化往返', () {
    test('保存后重新加载得到相同数据', () async {
      final repo = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      final original = sampleTimetable();
      await repo.save(original);

      // 用全新的仓储实例模拟「重启应用」
      final reloaded = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      final loaded = await reloaded.load();

      expect(loaded.semester.name, '2026 春季学期');
      expect(loaded.semester.totalWeeks, 16);
      expect(loaded.courses.length, 1);
      expect(loaded.courses.single.name, '高等数学');
      expect(loaded.courses.single.colorIndex, 3);
      expect(loaded.courses.single.sessions.single.weeks, [1, 3, 5, 7, 9]);
      expect(loaded.courses.single.sessions.single.location, 'A101');
    });

    test('首次运行返回默认课表（16 周、无课程）', () async {
      final repo = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      final t = await repo.load();
      expect(t.courses, isEmpty);
      expect(t.semester.totalWeeks, 16);
      expect(t.timeSlots, isNotEmpty);
    });

    test('导出 JSON 文本后能再导入', () async {
      final repo = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      final original = sampleTimetable();
      final text = repo.exportToJsonText(original);

      final imported = repo.importFromJsonText(text);
      expect(imported.courses.single.name, '高等数学');
      expect(imported.courses.single.sessions.single.weeks, [1, 3, 5, 7, 9]);
    });

    test('合并导入时重分配 id，避免与现有数据冲突', () async {
      final repo = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      final text = repo.exportToJsonText(sampleTimetable());

      final merged = repo.importFromJsonText(text, replaceIds: true);
      // id 必须与原数据不同
      expect(merged.courses.single.id, isNot('c1'));
      expect(merged.courses.single.sessions.single.id, isNot('ss1'));
      // 内容保持一致
      expect(merged.courses.single.name, '高等数学');
    });

    test('导出到文件并可再读回', () async {
      final repo = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      final outPath = '${root.path}${Platform.pathSeparator}export.json';
      await repo.exportToFile(sampleTimetable(), outPath);

      expect(await File(outPath).exists(), isTrue);
      final back = repo.importFromJsonText(await File(outPath).readAsString());
      expect(back.courses.single.name, '高等数学');
    });

    test('导入非法内容时抛出 FormatException', () {
      final repo = TimetableRepository(
        store: DocumentStore('timetable.json', baseDirectory: root),
      );
      expect(
        () => repo.importFromJsonText('[1,2,3]'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
