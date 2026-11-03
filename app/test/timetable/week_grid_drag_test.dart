import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/timetable/widgets/course_card.dart';
import 'package:course_timetable/features/timetable/widgets/week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Timetable _timetable() => Timetable(
      semester: Semester(
        id: 's1',
        name: '测试学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: [
        Course(
          id: 'c1',
          semesterId: 's1',
          name: '高等数学',
          teacher: '张老师',
          colorIndex: 0,
          sessions: const [
            Session(
              id: 's1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1],
              location: 'A101',
            ),
          ],
        ),
      ],
    );

void main() {
  group('resolveDraggedPeriods 拖动落点换算', () {
    test('落点换算成新的起始节次，保持跨节数不变', () {
      final p = resolveDraggedPeriods(
        dropTopDy: 240,
        rowHeight: 60,
        originalStart: 1,
        originalEnd: 2,
        maxPeriod: 12,
      );
      expect(p.start, 5);
      expect(p.end, 6);
    });

    test('跨多节的课程保持原跨度', () {
      final p = resolveDraggedPeriods(
        dropTopDy: 120,
        rowHeight: 60,
        originalStart: 3,
        originalEnd: 5,
        maxPeriod: 12,
      );
      expect(p.start, 3);
      expect(p.end, 5);
    });

    test('拖出上下边界时贴边', () {
      final top = resolveDraggedPeriods(
        dropTopDy: -100,
        rowHeight: 60,
        originalStart: 5,
        originalEnd: 6,
        maxPeriod: 12,
      );
      expect(top.start, 1);
      expect(top.end, 2);

      final bottom = resolveDraggedPeriods(
        dropTopDy: 2000,
        rowHeight: 60,
        originalStart: 5,
        originalEnd: 6,
        maxPeriod: 12,
      );
      expect(bottom.start, 11);
      expect(bottom.end, 12);
    });
  });

  testWidgets('拖动时可跨天并显示目标时间段预览', (tester) async {
    Course? changedCourse;
    int? newStart;
    int? newEnd;
    int? targetDay;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 764,
            child: WeekGrid(
              timetable: _timetable(),
              week: 1,
              minRowHeight: 60,
              onPeriodsChanged: (course, session, start, end, day) {
                changedCourse = course;
                newStart = start;
                newEnd = end;
                targetDay = day;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey('course_drag_handle_s1'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    // 向右一列（800-时间轴 64 后 7 列，每列约 105）+ 向下 240px（4 节）。
    await gesture.moveBy(const Offset(105, 240));
    await tester.pump();

    // 拖动经过目标列时显示预览标签，明确会落到第 5-6 节。
    expect(find.text('第5-6节'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(changedCourse?.name, '高等数学');
    expect(targetDay, 2);
    expect(newStart, 5);
    expect(newEnd, 6);
  });

  testWidgets('拖动课程卡片到其他节次会回调新的起止节次', (tester) async {
    Course? changedCourse;
    Session? changedSession;
    int? newStart;
    int? newEnd;
    int? targetDay;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 764,
            child: WeekGrid(
              timetable: _timetable(),
              week: 1,
              minRowHeight: 60,
              onPeriodsChanged: (course, session, start, end, day) {
                changedCourse = course;
                changedSession = session;
                newStart = start;
                newEnd = end;
                targetDay = day;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);

    // 直接拖卡片正文不应触发拖动（防止课表滚动时误触）。
    await tester.drag(find.byType(CourseCard), const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(changedCourse, isNull);

    // 只有右下角拖动柄能发起拖动：60px/节，向下拖 4 节（240px），1-2 节应变成 5-6 节。
    await tester.drag(
      find.byKey(const ValueKey('course_drag_handle_s1')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();

    expect(changedCourse?.name, '高等数学');
    expect(changedSession?.id, 's1');
    expect(targetDay, 1);
    expect(newStart, 5);
    expect(newEnd, 6);
  });
}
