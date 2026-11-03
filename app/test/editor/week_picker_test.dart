import 'package:course_timetable/core/utils/week_utils.dart';
import 'package:course_timetable/features/editor/widgets/session_editor.dart';
import 'package:course_timetable/features/editor/widgets/week_picker.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 周次选择器是全局交互最复杂的控件，这里锁定它的核心契约：
/// 网格点选 / 文本输入 / 快捷按钮 三种方式互相同步，且回调总是「已排序、去重」。
void main() {
  Widget host({required List<int> weeks, required ValueChanged<List<int>> onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WeekPicker(
            totalWeeks: 16,
            selectedWeeks: weeks,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('点选网格直接切换选中状态', (tester) async {
    List<int> latest = const [];
    await tester.pumpWidget(host(weeks: const [], onChanged: (v) => latest = v));

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(latest, [3]);

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(latest, [3, 5]);

    // 再点一次取消
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(latest, [5]);
  });

  testWidgets('文本输入解析断续周次并同步网格', (tester) async {
    List<int> latest = const [];
    await tester.pumpWidget(host(weeks: const [], onChanged: (v) => latest = v));

    await tester.enterText(find.byType(TextField).first, '1-4,7');
    await tester.pumpAndSettle();
    expect(latest, [1, 2, 3, 4, 7]);
  });

  testWidgets('单双周快捷按钮与格式串回读都能正常工作', (tester) async {
    List<int> latest = const [];
    await tester.pumpWidget(host(weeks: const [], onChanged: (v) => latest = v));

    await tester.tap(find.text('单周'));
    await tester.pumpAndSettle();
    expect(latest, [1, 3, 5, 7, 9, 11, 13, 15]);

    await tester.tap(find.text('双周'));
    await tester.pumpAndSettle();
    expect(latest, [2, 4, 6, 8, 10, 12, 14, 16]);

    // 反向：把 formatWeeks 的输出原样输回输入框，应得到同一集合。
    final text = formatWeeks([1, 3, 5, 7, 9, 11, 13, 15]);
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pumpAndSettle();
    expect(latest, [1, 3, 5, 7, 9, 11, 13, 15]);
  });

  testWidgets('反选 / 清空 / 全选', (tester) async {
    List<int> latest = const [];
    await tester.pumpWidget(host(weeks: const [2, 4], onChanged: (v) => latest = v));

    await tester.tap(find.text('反选'));
    await tester.pumpAndSettle();
    expect(latest.length, 14);
    expect(latest.contains(2), isFalse);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(latest, isEmpty);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(latest.length, 16);
  });

  testWidgets('超出总周数的输入被裁剪并提示', (tester) async {
    List<int> latest = const [];
    await tester.pumpWidget(host(weeks: const [], onChanged: (v) => latest = v));

    await tester.enterText(find.byType(TextField).first, '18');
    await tester.pumpAndSettle();
    expect(latest, isEmpty);
    await tester.tap(find.byTooltip('查看提示').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('已忽略超出总周数'), findsOneWidget);
  });

  testWidgets('时段编辑器：改星期/节次/地点都会回调新 Session', (tester) async {
    Session? latest;
    const session = Session(
      id: 's1',
      dayOfWeek: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: [1, 2, 3],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SessionEditor(
              index: 0,
              session: session,
              timeSlots: defaultTimeSlots(),
              totalWeeks: 16,
              onChanged: (s) => latest = s,
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 摘要行与回显行都会展示不规律周次
    expect(find.textContaining('1-3周'), findsWidgets);

    // 改地点
    final locationField = find.widgetWithText(TextField, '地点');
    await tester.enterText(locationField, 'A101');
    await tester.pumpAndSettle();
    expect(latest?.location, 'A101');
    expect(latest?.id, 's1');
  });

  testWidgets('时段编辑器的节次下拉显示对应作息时间', (tester) async {
    const session = Session(
      id: 's1',
      dayOfWeek: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: [1],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SessionEditor(
              index: 0,
              session: session,
              timeSlots: defaultTimeSlots(),
              totalWeeks: 16,
              onChanged: (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
    await tester.pumpAndSettle();
    expect(find.text('第1节 08:00-08:45'), findsOneWidget);
    expect(find.text('第2节 08:55-09:40'), findsOneWidget);
  });
}
