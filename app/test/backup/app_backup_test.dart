import 'dart:convert';

import 'package:course_timetable/data/backup/app_backup.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/holiday.dart';
import 'package:course_timetable/data/models/schedule_event.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/repositories/timetable_history_repository.dart';
import 'package:course_timetable/data/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable _timetable() => Timetable(
      semester: Semester(
        id: 's1',
        name: '2026 秋季学期',
        startMonday: DateTime(2026, 9, 7),
        totalWeeks: 16,
      ),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '高等数学',
          sessions: const [
            Session(
              id: 'ss1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1, 2],
            ),
          ],
        ),
      ],
    );

void main() {
  test('完整备份往返保留课程之外的设置、日程、历史和同步状态', () {
    final timetable = _timetable();
    final backup = AppBackup.create(
      timetable: timetable,
      settings: AppSettings(
        themeMode: 'dark',
        activeThemeId: 'custom',
        showWeekend: false,
        onboardingCompleted: true,
        holidays: [
          Holiday(
            id: 'h1',
            date: DateTime(2026, 10, 1),
            name: '国庆节',
          ),
        ],
      ),
      scheduleEvents: [
        ScheduleEvent(
          id: 'e1',
          title: '交作业',
          date: DateTime(2026, 9, 20),
          note: '提交实验报告',
        ),
      ],
      history: [
        TimetableHistoryEntry(
          id: 'hist1',
          savedAt: DateTime(2026, 9, 1, 8),
          timetable: timetable,
          description: '添加课程',
        ),
      ],
      syncState: SyncState(
        baseJson: '{"version":1}',
        lastSyncAtMs: 123456,
        remoteVersionTag: 'etag-1',
        deviceId: 'device-a',
      ),
      now: DateTime(2026, 9, 2, 12),
    );

    final restored = AppBackup.tryDecode(backup.toJsonText());

    expect(restored, isNotNull);
    expect(restored!.toJson()['version'], AppBackup.formatVersion);
    expect(restored.appVersion, isNotEmpty);
    expect(restored.timetable.courses.single.name, '高等数学');
    expect(restored.settings.themeMode, 'dark');
    expect(restored.settings.showWeekend, isFalse);
    expect(restored.settings.holidays.single.name, '国庆节');
    expect(restored.scheduleEvents.single.title, '交作业');
    expect(restored.scheduleEvents.single.note, '提交实验报告');
    expect(restored.history.single.description, '添加课程');
    expect(restored.syncState.remoteVersionTag, 'etag-1');
    expect(restored.syncState.deviceId, 'device-a');
  });

  test('普通课表 JSON 不会被误认为完整备份', () {
    expect(AppBackup.tryDecode(_timetable().toJsonTextForTest()), isNull);
  });
}

extension on Timetable {
  String toJsonTextForTest() {
    const converter = JsonEncoder();
    return converter.convert(toJson());
  }
}
