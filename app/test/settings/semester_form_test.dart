import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/core/utils/week_utils.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/features/settings/widgets/semester_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 学期表单：并排字段高度对齐 + 「按今天第 N 周定位」。
void main() {
  final initialSemester = Semester(
    id: 's1',
    name: '2026 学年秋季学期',
    startMonday: DateTime(2026, 8, 31),
    totalWeeks: 16,
  );

  Future<void> pumpForm(
    WidgetTester tester, {
    Semester? initial,
    ValueChanged<Semester>? onChanged,
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SemesterForm(
              semester: initial ?? initialSemester,
              onChanged: onChanged ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('窄屏下「第 1 周周一」与「总周数」输入框高度一致', (tester) async {
    await pumpForm(tester);

    expect(tester.takeException(), isNull);
    final start = tester.getSize(find.byKey(const Key('semester_start_field')));
    final weeks = tester.getSize(find.byKey(const Key('semester_weeks_field')));
    expect(start.height, closeTo(weeks.height, 0.01));
  });

  testWidgets('按今天第 N 周定位会反推第 1 周周一', (tester) async {
    Semester? changed;
    await pumpForm(tester, onChanged: (s) => changed = s);

    await tester.enterText(
      find.byKey(const Key('semester_current_week_field')),
      '5',
    );
    await tester.tap(find.byKey(const Key('semester_apply_current_week')));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.startMonday, startMondayForWeek(DateTime.now(), 5));
    expect(changed!.startMonday.weekday, DateTime.monday);
    expect(find.textContaining('已按「今天第 5 周」定位'), findsOneWidget);
  });

  testWidgets('定位输入的周次非法时给出提示且不修改学期', (tester) async {
    Semester? changed;
    await pumpForm(tester, onChanged: (s) => changed = s);

    await tester.enterText(
      find.byKey(const Key('semester_current_week_field')),
      '99',
    );
    await tester.tap(find.byKey(const Key('semester_apply_current_week')));
    await tester.pumpAndSettle();

    expect(changed, isNull);
    expect(find.text('请输入 1~60 之间的周数'), findsOneWidget);
  });
}
