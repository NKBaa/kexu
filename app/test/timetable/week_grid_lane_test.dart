import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/timetable/widgets/course_card.dart';
import 'package:course_timetable/features/timetable/widgets/week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionEntry _entry(String name, int start, int end) => SessionEntry(
      course: Course(
        id: name,
        semesterId: 's1',
        name: name,
        colorIndex: 0,
        sessions: [
          Session(
            id: '$name-$start',
            dayOfWeek: 1,
            startPeriod: start,
            endPeriod: end,
            weeks: const [1],
          ),
        ],
      ),
      session: Session(
        id: '$name-$start',
        dayOfWeek: 1,
        startPeriod: start,
        endPeriod: end,
        weeks: const [1],
      ),
    );

Timetable _timetableWith(List<SessionEntry> entries) => Timetable(
      semester: Semester(
        id: 's1',
        name: '测试学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: [for (final e in entries) e.course],
    );

void main() {
  group('layoutSessionLanes 冲突课程横向分栏', () {
    test('节次相交的课程分到不同 lane', () {
      final placed = layoutSessionLanes([
        _entry('高数', 1, 2),
        _entry('线代', 2, 3),
        _entry('英语', 3, 4),
      ]);
      expect(placed.map((p) => p.lane).toList(), [0, 1, 0]);
      expect(placed.map((p) => p.laneCount).toList(), [2, 2, 2]);
    });

    test('同一起点的多门课各自一栏', () {
      final placed = layoutSessionLanes([
        _entry('A', 1, 2),
        _entry('B', 1, 2),
        _entry('C', 1, 2),
      ]);
      expect(placed.map((p) => p.lane).toList(), [0, 1, 2]);
      expect(placed.map((p) => p.laneCount).toList(), [3, 3, 3]);
    });

    test('不相交的课程独占整列宽度（laneCount=1）', () {
      final placed = layoutSessionLanes([
        _entry('早课', 1, 2),
        _entry('晚课', 5, 6),
      ]);
      expect(placed.map((p) => p.lane).toList(), [0, 0]);
      expect(placed.map((p) => p.laneCount).toList(), [1, 1]);
    });

    test('多个重叠簇分别计算栏数', () {
      final placed = layoutSessionLanes([
        _entry('A', 1, 2),
        _entry('B', 2, 3),
        _entry('C', 6, 7),
        _entry('D', 6, 8),
      ]);
      expect(placed.map((p) => p.lane).toList(), [0, 1, 0, 1]);
      expect(placed.map((p) => p.laneCount).toList(), [2, 2, 2, 2]);
    });

    test('空列表返回空', () {
      expect(layoutSessionLanes(const []), isEmpty);
    });
  });

  testWidgets('冲突课程横向并排，不纵向叠在一起', (tester) async {
    final entries = [_entry('高数', 1, 2), _entry('线代', 2, 3)];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 764,
            child: WeekGrid(timetable: _timetableWith(entries), week: 1),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cards = find.byType(CourseCard);
    expect(cards, findsNWidgets(2));
    final a = tester.getRect(cards.at(0));
    final b = tester.getRect(cards.at(1));
    // 两张冲突课程卡片在横向上不重叠（各占半列）。
    expect(a.right <= b.left + 0.01 || b.right <= a.left + 0.01, isTrue);
  });
}
