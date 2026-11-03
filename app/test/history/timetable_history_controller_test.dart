import 'dart:io';

import 'package:course_timetable/data/local/document_store.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/repositories/timetable_history_repository.dart';
import 'package:course_timetable/data/repositories/timetable_repository.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 内存版课表仓储，避免测试碰真实文件。
class _InMemoryTimetableRepository extends TimetableRepository {
  _InMemoryTimetableRepository(this.current);

  Timetable current;

  @override
  Future<Timetable> load() async => current;

  @override
  Future<void> save(Timetable timetable) async => current = timetable;
}

void main() {
  test('替换课表会记录历史，undoLatestChange 能逐步回退', () async {
    final root = await Directory.systemTemp.createTemp('kexu_history_ctrl_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final history = TimetableHistoryRepository(
      store: DocumentStore('history.json', baseDirectory: root),
    );

    final container = ProviderContainer(
      overrides: [
        timetableRepositoryProvider
            .overrideWithValue(_InMemoryTimetableRepository(_t('A'))),
        timetableHistoryRepositoryProvider.overrideWithValue(history),
      ],
    );
    addTearDown(container.dispose);

    await container.read(timetableProvider.future);
    final controller = container.read(timetableProvider.notifier);

    await controller.replaceTimetable(_t('B'));
    await controller.replaceTimetable(_t('C'));
    expect((await history.load()).length, 2);
    expect(await controller.nextUndoDescription(), '修改学期设置');
    expect(controller.redoDescription, isNull);

    expect(await controller.undoLatestChange(), isTrue);
    expect(container.read(timetableProvider).value!.semester.name, 'B');
    expect((await history.load()).length, 1);
    expect(controller.redoDescription, '修改学期设置');
    expect(await controller.nextUndoDescription(), '修改学期设置');

    expect(await controller.undoLatestChange(), isTrue);
    expect(container.read(timetableProvider).value!.semester.name, 'A');
    expect(await controller.undoLatestChange(), isFalse);

    // Word 式重做：撤销后可以按相反顺序恢复。
    expect(controller.canRedo, isTrue);
    expect(await controller.redoLastChange(), isTrue);
    expect(container.read(timetableProvider).value!.semester.name, 'B');
    expect(await controller.redoLastChange(), isTrue);
    expect(container.read(timetableProvider).value!.semester.name, 'C');
    expect(await controller.redoLastChange(), isFalse);
  });

  test('新的编辑会清空重做栈', () async {
    final root = await Directory.systemTemp.createTemp('kexu_history_redo_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final history = TimetableHistoryRepository(
      store: DocumentStore('history.json', baseDirectory: root),
    );
    final container = ProviderContainer(
      overrides: [
        timetableRepositoryProvider
            .overrideWithValue(_InMemoryTimetableRepository(_t('A'))),
        timetableHistoryRepositoryProvider.overrideWithValue(history),
      ],
    );
    addTearDown(container.dispose);
    await container.read(timetableProvider.future);
    final controller = container.read(timetableProvider.notifier);

    await controller.replaceTimetable(_t('B'));
    expect(await controller.undoLatestChange(), isTrue);
    expect(controller.canRedo, isTrue);

    await controller.replaceTimetable(_t('C'));
    expect(controller.canRedo, isFalse);
    expect(await controller.redoLastChange(), isFalse);
    expect(container.read(timetableProvider).value!.semester.name, 'C');
  });

  test('内容未变化的替换不会产生历史', () async {
    final root = await Directory.systemTemp.createTemp('kexu_history_same_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final history = TimetableHistoryRepository(
      store: DocumentStore('history.json', baseDirectory: root),
    );
    final container = ProviderContainer(
      overrides: [
        timetableRepositoryProvider
            .overrideWithValue(_InMemoryTimetableRepository(_t('A'))),
        timetableHistoryRepositoryProvider.overrideWithValue(history),
      ],
    );
    addTearDown(container.dispose);

    await container.read(timetableProvider.future);
    await container.read(timetableProvider.notifier).replaceTimetable(_t('A'));
    expect(await history.load(), isEmpty);
  });
}
