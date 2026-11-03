import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/repositories/timetable_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable _t(String name) => Timetable(
      semester: Semester(
        id: 's1',
        name: name,
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
    );

void main() {
  late Directory root;
  late DocumentStore store;
  late TimetableHistoryRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kexu_history_test_');
    store = DocumentStore('history.json', baseDirectory: root);
    repo = TimetableHistoryRepository(store: store);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('push 保存修改前快照，连续相同内容会去重', () async {
    await repo.push(_t('A'), next: _t('B'));
    await repo.push(_t('B'), next: _t('C'));
    // 内容没变化的保存不记录
    await repo.push(_t('C'), next: _t('C'));

    final entries = await repo.load();
    expect(
      entries.map((e) => e.timetable.semester.name).toList(),
      ['A', 'B'],
    );
  });

  test('最多保留 20 条，超出后丢弃最旧', () async {
    for (var i = 0; i < 25; i++) {
      await repo.push(_t('v$i'), next: _t('v${i + 1}'));
    }
    final entries = await repo.load();
    expect(entries.length, TimetableHistoryRepository.defaultMaxEntries);
    expect(entries.first.timetable.semester.name, 'v5');
    expect(entries.last.timetable.semester.name, 'v24');
  });

  test('undoLatest 弹出最新快照，没有历史时返回 null', () async {
    await repo.push(_t('A'), next: _t('B'));
    await repo.push(_t('B'), next: _t('C'));

    final first = await repo.undoLatest();
    expect(first!.timetable.semester.name, 'B');
    expect((await repo.load()).length, 1);

    expect((await repo.undoLatest())!.timetable.semester.name, 'A');
    expect(await repo.undoLatest(), isNull);
  });

  test('历史文件损坏时按空历史处理，不影响课表', () async {
    final f = await store.file();
    await f.writeAsString('{not-json');
    expect(await repo.load(), isEmpty);
  });
}
