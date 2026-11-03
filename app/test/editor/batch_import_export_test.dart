import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/batch/batch_ops_page.dart';
import 'package:course_timetable/features/import_export/import_export_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
        Course(
          id: 'c2',
          semesterId: 's1',
          name: '大学英语',
          colorIndex: 2,
          sessions: [
            Session(
              id: 'x2',
              dayOfWeek: 3,
              startPeriod: 5,
              endPeriod: 6,
              weeks: const [2, 4, 6],
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

void _bigWindow(WidgetTester tester, {double w = 1500, double h = 2400}) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('批量操作：列出课程、全选后显示已选数量', (tester) async {
    _bigWindow(tester);
    await tester.pumpWidget(_wrap(const BatchOpsPage(), _FakeTimetableController(_seed())));
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学英语'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 2 门课程'), findsOneWidget);
  });

  testWidgets('批量操作：批量改地点作用于所有选中时段', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());
    await tester.pumpWidget(_wrap(const BatchOpsPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('改地点'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '新地点'), 'B203');
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    final locations =
        controller.current.courses.expand((c) => c.sessions).map((s) => s.location).toSet();
    expect(locations, {'B203'});
  });

  testWidgets('批量操作：批量改周次支持替换为双周', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());
    await tester.pumpWidget(_wrap(const BatchOpsPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('改周次'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('双周').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    final weeks = controller.current.courses
        .expand((c) => c.sessions)
        .map((s) => s.weeks.join(','))
        .toSet();
    expect(weeks, {'2,4,6,8,10,12,14,16'});
  });

  testWidgets('批量操作：删除需要二次确认', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());
    await tester.pumpWidget(_wrap(const BatchOpsPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('确认批量删除？'), findsOneWidget);
    // 先取消，数据不该变
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.current.courses.length, 2);

    // 再确认删除
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除 2 门'));
    await tester.pumpAndSettle();
    expect(controller.current.courses, isEmpty);
  });

  testWidgets('导入导出：粘贴 JSON 后合并导入追加课程', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());
    await tester.pumpWidget(_wrap(const ImportExportPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('手动粘贴 / 编辑 JSON'));
    await tester.pumpAndSettle();

    const jsonText = '{"semester":{"id":"s2","name":"导入的学期",'
        '"startMonday":"2025-09-01T00:00:00.000","totalWeeks":16},'
        '"timeSlots":[{"period":1,"start":"08:00","end":"08:45"}],'
        '"courses":[{"id":"n1","semesterId":"s2","name":"数据结构",'
        '"sessions":[{"id":"ns1","dayOfWeek":2,"startPeriod":3,"endPeriod":4,'
        '"weeks":[1,2,3],"location":"C301"}]}]}';
    await tester.enterText(find.byType(TextField).first, jsonText);
    await tester.pumpAndSettle();
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();

    expect(find.text('解析成功'), findsOneWidget);
    await tester.tap(find.text('合并导入'));
    await tester.pumpAndSettle();

    expect(find.text('确认合并导入？'), findsOneWidget);
    await tester.tap(find.text('合并导入').last);
    await tester.pumpAndSettle();

    expect(controller.current.courses.length, 3);
    expect(controller.current.courses.last.name, '数据结构');
    // 合并导入沿用当前学期，不覆盖学期设置
    expect(controller.current.semester.name, '2025 秋季学期');
  });

  testWidgets('导入导出：覆盖导入需要二次确认并替换学期', (tester) async {
    _bigWindow(tester);
    final controller = _FakeTimetableController(_seed());
    await tester.pumpWidget(_wrap(const ImportExportPage(), controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('手动粘贴 / 编辑 JSON'));
    await tester.pumpAndSettle();

    const jsonText = '{"semester":{"id":"s9","name":"覆盖后的学期",'
        '"startMonday":"2026-02-23T00:00:00.000","totalWeeks":18},'
        '"timeSlots":[{"period":1,"start":"08:00","end":"08:45"}],"courses":[]}';
    await tester.enterText(find.byType(TextField).first, jsonText);
    await tester.pumpAndSettle();
    await tester.tap(find.text('解析'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖导入'));
    await tester.pumpAndSettle();

    expect(find.text('确认覆盖当前课表？'), findsOneWidget);
    await tester.tap(find.text('覆盖导入').last);
    await tester.pumpAndSettle();

    expect(controller.current.semester.name, '覆盖后的学期');
    expect(controller.current.semester.totalWeeks, 18);
    expect(controller.current.courses, isEmpty);
  });

  testWidgets('批量操作窄屏下筛选与搜索同一行不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(const BatchOpsPage(), _FakeTimetableController(_seed())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('batch_filter_button')), findsOneWidget);
    expect(find.text('筛选'), findsOneWidget);

    await tester.tap(find.byKey(const Key('batch_filter_button')));
    await tester.pumpAndSettle();
    expect(find.text('全部星期'), findsOneWidget);
    expect(find.text('全部周次'), findsOneWidget);
    expect(find.byKey(const Key('batch_clear_filters')), findsOneWidget);
  });
}
