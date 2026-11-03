import 'package:course_timetable/core/utils/holiday_utils.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/holiday.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/settings/pages/holiday_reminder_page.dart';
import 'package:course_timetable/features/settings/pages/semester_settings_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 节假日模型 / 日期匹配 / 设置 JSON 往返 的单元测试。
void main() {
  group('Holiday 模型', () {
    test('toJson / fromJson 往返后 id、日期、名称保持一致', () {
      final holiday = Holiday(
        id: 'h1',
        date: DateTime(2026, 10, 1),
        name: '国庆节',
      );

      final json = holiday.toJson();
      expect(json['id'], 'h1');
      expect(json['date'], '2026-10-01');
      expect(json['name'], '国庆节');

      final restored = Holiday.fromJson(json);
      expect(restored, holiday);
      expect(restored.dateKey, '2026-10-01');
    });

    test('构造时把日期归一化到当天零点', () {
      final holiday = Holiday(
        id: 'h2',
        date: DateTime(2026, 10, 1, 18, 30, 45),
        name: '国庆节',
      );
      expect(holiday.date, DateTime(2026, 10, 1));
      expect(holiday.date.hour, 0);
      expect(holiday.date.minute, 0);
      expect(holiday.date.second, 0);
    });

    test('fromJson 容错：缺少 id 自动补齐，缺少名称回退为「节假日」', () {
      final restored = Holiday.fromJson({'date': '2026-01-01'});
      expect(restored.id, isNotEmpty);
      expect(restored.name, '节假日');
      expect(restored.dateKey, '2026-01-01');
    });

    test('fromJson 支持完整 ISO 时间字符串，并只保留年月日', () {
      final restored = Holiday.fromJson({
        'id': 'h3',
        'date': '2026-05-01T08:30:00.000',
        'name': '劳动节',
      });
      expect(restored.dateKey, '2026-05-01');
      expect(restored.date, DateTime(2026, 5, 1));
    });
  });

  group('节假日日期匹配', () {
    final holidays = [
      Holiday(id: 'h1', date: DateTime(2026, 10, 1), name: '国庆节'),
      Holiday(id: 'h2', date: DateTime(2026, 9, 7), name: '校运会'),
    ];

    test('holidayForDate 命中同一天，忽略时分秒', () {
      final hit = holidayForDate(holidays, DateTime(2026, 10, 1, 23, 59));
      expect(hit, isNotNull);
      expect(hit!.name, '国庆节');
    });

    test('isHolidayDate 对相邻日期返回 false', () {
      expect(isHolidayDate(holidays, DateTime(2026, 10, 2)), isFalse);
      expect(isHolidayDate(holidays, DateTime(2026, 9, 30)), isFalse);
      expect(isHolidayDate(holidays, DateTime(2026, 9, 7)), isTrue);
    });

    test('空列表时不匹配任何日期', () {
      expect(holidayForDate(const [], DateTime(2026, 10, 1)), isNull);
      expect(isHolidayDate(const [], DateTime(2026, 10, 1)), isFalse);
    });

    test('sortHolidays 按日期升序，不修改入参', () {
      final sorted = sortHolidays(holidays);
      expect(sorted.map((h) => h.dateKey).toList(), ['2026-09-07', '2026-10-01']);
      // 入参顺序保持原样
      expect(holidays.first.id, 'h1');
    });

    test('normalizeHolidays 去掉同一天重复项', () {
      final normalized = normalizeHolidays([
        Holiday(id: 'a', date: DateTime(2026, 10, 1), name: '国庆节'),
        Holiday(id: 'b', date: DateTime(2026, 10, 1, 12), name: '重复项'),
      ]);
      expect(normalized.length, 1);
      expect(normalized.single.id, 'a');
    });

    test('formatDateKey / parseDateKey 往返', () {
      expect(formatDateKey(DateTime(2026, 3, 9, 15, 4)), '2026-03-09');
      expect(parseDateKey('2026-03-09'), DateTime(2026, 3, 9));
      expect(parseDateKey('不是日期'), isNull);
      expect(parseDateKey(null), isNull);
    });
  });

  group('AppSettings 节假日与提醒字段', () {
    test('默认值：无节假日、提醒关闭、提前 10 分钟、系统通知', () {
      const settings = AppSettings();
      expect(settings.holidays, isEmpty);
      expect(settings.classReminderEnabled, isFalse);
      expect(settings.reminderMinutes, 10);
      expect(settings.notificationStyle, 'system');
    });

    test('JSON 往返保留全部新增字段', () {
      final settings = AppSettings(
        holidays: [
          Holiday(id: 'h1', date: DateTime(2026, 10, 1), name: '国庆节'),
          Holiday(id: 'h2', date: DateTime(2026, 10, 2), name: '国庆假期'),
        ],
        classReminderEnabled: true,
        reminderMinutes: 30,
        notificationStyle: 'vendor',
      );

      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.holidays.length, 2);
      expect(restored.holidays.first.dateKey, '2026-10-01');
      expect(restored.holidays.last.name, '国庆假期');
      expect(restored.classReminderEnabled, isTrue);
      expect(restored.reminderMinutes, 30);
      expect(restored.notificationStyle, 'vendor');
    });

    test('缺失或非法字段回退到默认值', () {
      final restored = AppSettings.fromJson({
        'reminderMinutes': 7,
        'notificationStyle': 'unknown',
        'classReminderEnabled': 'yes',
        'holidays': 'oops',
      });
      expect(restored.reminderMinutes, 10);
      expect(restored.notificationStyle, 'system');
      expect(restored.classReminderEnabled, isFalse);
      expect(restored.holidays, isEmpty);
    });

    test('copyWith 可以单独更新节假日与提醒字段', () {
      const base = AppSettings();
      final updated = base.copyWith(
        holidays: [Holiday(id: 'h1', date: DateTime(2026, 10, 1), name: '国庆节')],
        classReminderEnabled: true,
        reminderMinutes: 5,
        notificationStyle: 'vendor',
      );
      expect(updated.holidays.length, 1);
      expect(updated.classReminderEnabled, isTrue);
      expect(updated.reminderMinutes, 5);
      expect(updated.notificationStyle, 'vendor');
      // 未指定的字段保持原值
      expect(updated.themeMode, base.themeMode);
      expect(updated.showWeekend, base.showWeekend);
    });
  });

  group('SettingsController 节假日/提醒 setter', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_FakeSettingsController.new),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('addHoliday 自动去重并排序，removeHoliday 按 id 删除', () async {
      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.addHoliday(
        Holiday(id: 'h2', date: DateTime(2026, 10, 2), name: '国庆假期'),
      );
      await notifier.addHoliday(
        Holiday(id: 'h1', date: DateTime(2026, 10, 1), name: '国庆节'),
      );
      // 同一天再添加一次：覆盖名称而不是新增一条
      await notifier.addHoliday(
        Holiday(id: 'h1b', date: DateTime(2026, 10, 1), name: '国庆节（改）'),
      );

      final settings = container.read(settingsProvider).valueOrNull!;
      expect(settings.holidays.length, 2);
      expect(settings.holidays.first.dateKey, '2026-10-01');
      expect(settings.holidays.first.name, '国庆节（改）');
      expect(settings.holidays.last.dateKey, '2026-10-02');

      await notifier.removeHoliday(settings.holidays.first.id);
      expect(container.read(settingsProvider).valueOrNull!.holidays.length, 1);
    });

    test('提醒开关、分钟数与通知样式 setter 生效且非法值回退', () async {
      await container.read(settingsProvider.future);
      final notifier = container.read(settingsProvider.notifier);

      await notifier.setClassReminderEnabled(true);
      await notifier.setReminderMinutes(30);
      await notifier.setNotificationStyle('vendor');

      var settings = container.read(settingsProvider).valueOrNull!;
      expect(settings.classReminderEnabled, isTrue);
      expect(settings.reminderMinutes, 30);
      expect(settings.notificationStyle, 'vendor');

      // 非法值回退
      await notifier.setReminderMinutes(7);
      await notifier.setNotificationStyle('unknown');
      settings = container.read(settingsProvider).valueOrNull!;
      expect(settings.reminderMinutes, 10);
      expect(settings.notificationStyle, 'system');
    });
  });

  group('「上课提醒」页面', () {
    testWidgets('页面可渲染，默认显示提醒开关', (tester) async {
      final container = _testContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HolidayReminderPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上课提醒'), findsWidgets);
      expect(find.byKey(const Key('holiday_add_button')), findsNothing);
      expect(find.byKey(const Key('class_reminder_switch')), findsOneWidget);
      expect(find.byKey(const Key('notification_permission_button')),
          findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
      // 提醒默认关闭，样式选项不显示
      expect(find.byKey(const Key('notification_style_vendor')), findsNothing);
    });

    testWidgets('学期与作息页包含节假日管理', (tester) async {
      final container = _testContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SemesterSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('holiday_add_button')), findsOneWidget);
      expect(find.byKey(const Key('holiday_ai_button')), findsOneWidget);
    });

    testWidgets('打开提醒开关后会显示提前分钟与通知样式选项', (tester) async {
      final container = _testContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HolidayReminderPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('class_reminder_switch')));
      await tester.pumpAndSettle();

      final settings = container.read(settingsProvider).valueOrNull!;
      expect(settings.classReminderEnabled, isTrue);
      expect(find.byKey(const Key('reminder_minutes_10')), findsOneWidget);
      expect(find.byKey(const Key('notification_style_vendor')), findsOneWidget);
      expect(
        find.text('未来 7 天暂时没有需要提醒的课程（可能已放假或学期结束）。'),
        findsOneWidget,
      );
    });
  });
}

ProviderContainer _testContainer() {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_FakeSettingsController.new),
      timetableProvider.overrideWith(_FakeTimetableController.new),
    ],
  );
}

/// 只更新内存状态的假 controller，避免测试依赖本地文件与 path_provider。
class _FakeSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
  }
}

/// 空课表（只有学期），用于页面冒烟测试。
class _FakeTimetableController extends TimetableController {
  @override
  Future<Timetable> build() async => Timetable(
        semester: Semester(
          id: 's1',
          name: '测试学期',
          startMonday: DateTime(2026, 9, 7),
          totalWeeks: 16,
        ),
      );
}
