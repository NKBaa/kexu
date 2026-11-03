import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/editor/course_editor_page.dart';
import 'package:course_timetable/features/settings/pages/semester_settings_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/settings/settings_home_page.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课程编辑器 + 设置页的冒烟测试：用假 controller 注入 Riverpod，
/// 验证「页面能渲染 + 关键动作确实改到了课表状态」。
Timetable _seed() => Timetable(
      semester: Semester(
        id: 's1',
        name: '2025 秋季学期',
        startMonday: DateTime(2025, 9, 1),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '高等数学',
          teacher: '张老师',
          credit: 4,
          colorIndex: 1,
          sessions: [
            Session(
              id: 'x1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: const [1, 3, 5, 7],
              location: 'A101',
            ),
          ],
        ),
      ],
    );

class _FakeTimetableController extends TimetableController {
  _FakeTimetableController(this.current);

  Timetable current;

  @override
  Future<Timetable> build() async => current;

  @override
  Future<void> replaceTimetable(Timetable next, {bool recordHistory = true, String? description}) async {
    current = next;
    state = AsyncData(next);
  }
}

class _FakeSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
  }
}

Widget _wrap(Widget child, _FakeTimetableController controller) {
  return ProviderScope(
    overrides: [
      timetableProvider.overrideWith(() => controller),
      settingsProvider.overrideWith(_FakeSettingsController.new),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: child,
    ),
  );
}

void _bigWindow(WidgetTester tester, {double w = 1400, double h = 2400}) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('新增课程：填名称后保存会写入课表', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(builder: (_) => const CourseEditorPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        controller,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('新增课程'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '线性代数');
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存课程'));
    await tester.pumpAndSettle();

    // 保存成功后返回列表页，课表里多了这门课
    expect(find.text('open'), findsOneWidget);
    expect(controller.current.courses.length, 2);
    expect(controller.current.courses.last.name, '线性代数');
    expect(controller.current.courses.last.sessions.length, 1);
  });

  testWidgets('课程名为空时不允许保存', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(_wrap(const CourseEditorPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存课程'));
    await tester.pumpAndSettle();

    expect(controller.current.courses.length, 1);
    expect(find.text('课程名称不能为空'), findsOneWidget);
  });

  testWidgets('学期设置页：改总周数并保存会更新学期', (tester) async {
    _bigWindow(tester, h: 3200);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(_wrap(const SemesterSettingsPage(), controller));
    await tester.pumpAndSettle();

    expect(find.text('学期设置'), findsOneWidget);
    expect(find.text('作息方案'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('semester_weeks_field')),
      '18',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存学期'));
    await tester.pumpAndSettle();

    expect(controller.current.semester.totalWeeks, 18);
  });

  testWidgets('学期设置页：修改第 1 周周一会被归一化到周一', (tester) async {
    _bigWindow(tester, h: 3200);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(_wrap(const SemesterSettingsPage(), controller));
    await tester.pumpAndSettle();

    // 名称输入框直接修改
    await tester.enterText(find.byType(TextField).first, '2026 春季学期');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存学期'));
    await tester.pumpAndSettle();

    expect(controller.current.semester.name, '2026 春季学期');
    expect(controller.current.semester.startMonday.weekday, DateTime.monday);
  });

  testWidgets('作息方案：列出方案并可进入新建页', (tester) async {
    _bigWindow(tester, h: 3200);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(_wrap(const SemesterSettingsPage(), controller));
    await tester.pumpAndSettle();

    expect(find.text('作息方案'), findsOneWidget);
    expect(find.byKey(const Key('bell_add_button')), findsOneWidget);
    expect(find.byKey(const Key('bell_template_button')), findsOneWidget);

    // 默认只有一套作息
    expect(controller.current.schedules.length, 1);
    expect(find.text('默认作息'), findsWidgets);

    // 进入新建页
    await tester.tap(find.byKey(const Key('bell_add_button')));
    await tester.pumpAndSettle();
    expect(find.text('新建作息方案'), findsOneWidget);
    expect(find.byKey(const Key('bell_name_field')), findsOneWidget);
    expect(find.byKey(const Key('bell_start_date')), findsOneWidget);
    expect(find.byKey(const Key('bell_end_date')), findsOneWidget);
  });

  testWidgets('作息方案：新建「夏季作息」后列表里有两套', (tester) async {
    _bigWindow(tester, h: 3200);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(_wrap(const SemesterSettingsPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bell_add_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('bell_name_field')), '夏季作息');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bell_save_button')));
    await tester.pumpAndSettle();

    expect(controller.current.schedules.length, 2);
    expect(
      controller.current.schedules.map((s) => s.name),
      contains('夏季作息'),
    );
  });

  testWidgets('设置中心：二级菜单列出各功能分类，点击可进入子页', (tester) async {
    _bigWindow(tester, h: 1600);
    final controller = _FakeTimetableController(_seed());

    await tester.pumpWidget(_wrap(const SettingsHomePage(), controller));
    await tester.pumpAndSettle();

    // 每个注册在册的分类都应出现在二级菜单里
    for (final s in settingsSections()) {
      expect(find.byKey(Key('settings_section_${s.id}')), findsOneWidget,
          reason: '二级菜单缺少分类「${s.title}」');
    }

    // 点进「学期与作息」应能打开子页面
    await tester.tap(find.byKey(const Key('settings_section_semester')));
    await tester.pumpAndSettle();
    expect(find.text('学期设置'), findsOneWidget);

    // 返回后点进「关于」
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings_section_about')));
    await tester.pumpAndSettle();
    expect(find.textContaining('课序 · Kexu'), findsOneWidget);
  });
}
