import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/core/widgets/apple_pickers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('苹果风格时间选择器使用滚轮并提供取消/完成', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showAppleTimePicker(
                    context,
                    initial: const TimeOfDay(hour: 9, minute: 30),
                  );
                },
                child: const Text('选时间'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('选时间'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.hour, 9);
    expect(result!.minute, 30);
  });

  testWidgets('苹果风格日期选择器返回日期', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showAppleDatePicker(
                    context,
                    initial: DateTime(2026, 11, 4),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                },
                child: const Text('选日期'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('选日期'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 4));
  });
}
