import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/bell_schedule_template.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/onboarding/onboarding_wizard_page.dart';
import 'package:course_timetable/features/settings/providers/schedule_template_provider.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable _seedTimetable() => Timetable(
      semester: Semester(
        id: 's1',
        name: '2025 秋季学期',
        startMonday: DateTime(2025, 9, 1),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: const [],
    );

class _FakeTimetableController extends TimetableController {
  @override
  Future<Timetable> build() async => _seedTimetable();
}

class _FakeSettingsController extends SettingsController {
  _FakeSettingsController(this.current);

  AppSettings current;

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> save(AppSettings settings) async {
    current = settings;
    state = AsyncData(settings);
  }
}

void main() {
  testWidgets('使用向导五步可前进，AI 步骤可跳过，完成后标记 onboardingCompleted',
      (tester) async {
    final settings = _FakeSettingsController(const AppSettings());
    final catalog = BellScheduleTemplateCatalog(
      schools: [
        SchoolBellTemplates(
          school: '测试大学',
          templates: [
            BellScheduleTemplate(
              id: 't1',
              school: '测试大学',
              name: '标准作息',
              slots: const [
                TimeSlot(period: 1, start: '08:00', end: '08:45'),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          timetableProvider.overrideWith(() => _FakeTimetableController()),
          scheduleTemplateCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingWizardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设置学期与作息'), findsOneWidget);
    expect(find.text('测试大学'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_open_semester')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('配置大模型 API'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_skip_ai')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('onboarding_skip_ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding_skip_ai')));
    await tester.pumpAndSettle();
    expect(find.text('设置节假日（可选）'), findsOneWidget);
    expect(find.text('还没有添加节假日。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('开始添加课程'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('课表编辑与新增'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(settings.current.onboardingCompleted, isTrue);
  });

  testWidgets('回看教程以「使用教程」打开，可随时关闭', (tester) async {
    final settings = _FakeSettingsController(
      const AppSettings(onboardingCompleted: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          timetableProvider.overrideWith(() => _FakeTimetableController()),
          scheduleTemplateCatalogProvider.overrideWith(
            (ref) async => const BellScheduleTemplateCatalog(schools: []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OnboardingWizardPage(replay: true),
                    ),
                  ),
                  child: const Text('打开教程'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开教程'));
    await tester.pumpAndSettle();

    expect(find.text('使用教程'), findsOneWidget);
    expect(find.text('认识课表'), findsWidgets);
    expect(find.text('第 1 节 / 共 6 节'), findsOneWidget);
    expect(find.text('你可以这样做'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    expect(find.text('添加课程'), findsWidgets);
    expect(find.text('第 2 节 / 共 6 节'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding_skip_all')));
    await tester.pumpAndSettle();
    expect(find.text('打开教程'), findsOneWidget);
  });

  testWidgets('宽屏教程显示目录，可直接跳到最后一节', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = _FakeSettingsController(
      const AppSettings(onboardingCompleted: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          timetableProvider.overrideWith(() => _FakeTimetableController()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingWizardPage(replay: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tutorial_chapter_0')), findsOneWidget);
    expect(find.byKey(const Key('tutorial_chapter_5')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorial_chapter_5')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 6 节 / 共 6 节'), findsOneWidget);
    expect(find.text('设置与数据'), findsWidgets);
    expect(find.text('完成教程'), findsOneWidget);
  });

  testWidgets('向导的节假日入口打开「学期与作息」', (tester) async {
    final settings = _FakeSettingsController(const AppSettings());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          timetableProvider.overrideWith(() => _FakeTimetableController()),
          scheduleTemplateCatalogProvider.overrideWith(
            (ref) async => const BellScheduleTemplateCatalog(schools: []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingWizardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding_next')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('onboarding_skip_ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding_skip_ai')));
    await tester.pumpAndSettle();

    expect(find.text('设置节假日（可选）'), findsOneWidget);
    expect(find.textContaining('设置 → 学期与作息'), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('onboarding_open_holidays')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding_open_holidays')));
    await tester.pumpAndSettle();

    expect(find.text('学期与作息'), findsOneWidget);
  });

  testWidgets('顶部跳过会直接完成向导', (tester) async {
    final settings = _FakeSettingsController(const AppSettings());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => settings),
          timetableProvider.overrideWith(() => _FakeTimetableController()),
          scheduleTemplateCatalogProvider.overrideWith((ref) async =>
              const BellScheduleTemplateCatalog(schools: [])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingWizardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboarding_skip_all')));
    await tester.pumpAndSettle();
    expect(settings.current.onboardingCompleted, isTrue);
  });
}
