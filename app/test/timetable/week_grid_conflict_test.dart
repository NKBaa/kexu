import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/timetable/widgets/course_card.dart';
import 'package:course_timetable/features/timetable/widgets/week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 网格的「同一格多课并存」行为：
/// 1. 同起始节次的 N 门课必须**并排**（N 列），全部可见，不能只露角标；
/// 2. 任何宽度下都不允许 RenderFlex / RenderBox 溢出；
/// 3. 冲突卡片带警告图标，非冲突卡片没有。
void main() {
  Semester semester() => Semester(
        id: 'sem1',
        name: '测试学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      );

  Course course(String id, String name, int colorIndex, Session session) =>
      Course(
        id: id,
        semesterId: 'sem1',
        name: name,
        colorIndex: colorIndex,
        sessions: [session],
      );

  /// 周一 1-2 节同时有两门课（周次相交 -> 时间冲突）。
  Timetable conflictingTimetable() => Timetable(
        semester: semester(),
        timeSlots: defaultTimeSlots(),
        courses: [
          course(
            'c1',
            '高等数学',
            0,
            const Session(
              id: 's1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1, 2, 3, 4],
              location: 'A101',
            ),
          ),
          course(
            'c2',
            '大学物理',
            1,
            const Session(
              id: 's2',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1, 2, 3, 4],
              location: 'B202',
            ),
          ),
        ],
      );

  /// 同节次但单双周错开：合法排课，第 1 周只显示单周课，不应标记冲突。
  Timetable oddEvenTimetable() => Timetable(
        semester: semester(),
        timeSlots: defaultTimeSlots(),
        courses: [
          course(
            'c1',
            '高等数学',
            0,
            const Session(
              id: 's1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1, 3, 5, 7],
              location: 'A101',
            ),
          ),
          course(
            'c2',
            '大学物理',
            1,
            const Session(
              id: 's2',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [2, 4, 6, 8],
              location: 'B202',
            ),
          ),
        ],
      );

  /// 先拦截 FlutterError，避免溢出（paint 阶段的 reportError）直接判失败，
  /// 同时让我们能断言「没有任何错误被上报」。
  Future<List<FlutterErrorDetails>> pumpCapturing(
    WidgetTester tester,
    Widget child,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );
      await tester.pump();
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Widget grid(Timetable timetable, double width) => SizedBox(
        width: width,
        height: 520,
        child: WeekGrid(timetable: timetable, week: 1),
      );

  testWidgets('同一格两门课并排显示：两个课程名都能找到，且无溢出', (tester) async {
    // 400 宽 - 时间轴 64 = 336，7 列 -> 每列约 48，并排两列各约 22 宽（触发紧凑降级）
    final errors = await pumpCapturing(tester, grid(conflictingTimetable(), 400));

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);
    expect(errors, isEmpty, reason: '窄列并排不允许渲染溢出：$errors');

    // 两张卡片位于同一行、左右并排，互不覆盖。
    final cards = find.byType(CourseCard);
    expect(cards, findsNWidgets(2));
    final first = tester.getRect(cards.at(0));
    final second = tester.getRect(cards.at(1));
    expect(first.top, closeTo(second.top, 0.5));
    expect(first.overlaps(second), isFalse, reason: '同一格的两张卡片不能重叠');
  });

  testWidgets('并排卡片在桌面宽度下同样完整可见且无溢出', (tester) async {
    final errors = await pumpCapturing(tester, grid(conflictingTimetable(), 1000));

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);
    expect(errors, isEmpty, reason: '$errors');
  });

  testWidgets('冲突课程出现警告高亮图标', (tester) async {
    await pumpCapturing(tester, grid(conflictingTimetable(), 400));

    // 两张冲突卡片各一个 + 周一表头一个
    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsAtLeastNWidgets(2));
  });

  testWidgets('单双周错开不误报冲突（第 1 周只有一门课、无警告图标）', (tester) async {
    await pumpCapturing(tester, grid(oddEvenTimetable(), 400));

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('三门课同格 -> 三门课名都在、三列并排、无溢出', (tester) async {
    final timetable = Timetable(
      semester: semester(),
      timeSlots: defaultTimeSlots(),
      courses: [
        course(
          'c1',
          '高等数学',
          0,
          const Session(
            id: 's1',
            dayOfWeek: 2,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [1, 2, 3],
            location: 'A101',
          ),
        ),
        course(
          'c2',
          '大学物理',
          1,
          const Session(
            id: 's2',
            dayOfWeek: 2,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [1, 2, 3],
            location: 'B202',
          ),
        ),
        course(
          'c3',
          '线性代数',
          2,
          const Session(
            id: 's3',
            dayOfWeek: 2,
            startPeriod: 3,
            endPeriod: 4,
            weeks: [1, 2, 3],
            location: 'C303',
          ),
        ),
      ],
    );

    final errors = await pumpCapturing(tester, grid(timetable, 1200));

    for (final name in ['高等数学', '大学物理', '线性代数']) {
      expect(find.text(name), findsOneWidget, reason: '$name 应完整可见');
    }
    expect(find.byType(CourseCard), findsNWidgets(3));

    final rects = [
      for (var i = 0; i < 3; i++) tester.getRect(find.byType(CourseCard).at(i)),
    ];
    expect(rects[0].overlaps(rects[1]), isFalse);
    expect(rects[1].overlaps(rects[2]), isFalse);
    expect(rects[0].overlaps(rects[2]), isFalse);
    expect(errors, isEmpty, reason: '$errors');
  });

  testWidgets('CourseCard conflicting 参数只加高亮、不改课程配色', (tester) async {
    const session = Session(
      id: 's1',
      dayOfWeek: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: [1, 2, 3],
      location: 'A101',
    );
    const c = Course(
      id: 'c1',
      semesterId: 'sem1',
      name: '高等数学',
      colorIndex: 3,
      sessions: [session],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 80,
              child: CourseCard(course: c, session: session, conflicting: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    // 背景仍是课程调色板颜色，而不是整块警告红。
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(CourseCard), matching: find.byType(Material)).first,
    );
    expect(material.color, CoursePalette.of(3));
  });

  testWidgets('同格内跨节数不同：各卡片高度按各自 rowSpan 计算', (tester) async {
    final timetable = Timetable(
      semester: semester(),
      timeSlots: defaultTimeSlots(),
      courses: [
        course(
          'c1',
          '高等数学',
          0,
          const Session(
            id: 's1',
            dayOfWeek: 3,
            startPeriod: 1,
            endPeriod: 2, // rowSpan 2
            weeks: [1, 2, 3],
            location: 'A101',
          ),
        ),
        course(
          'c2',
          '大学物理',
          1,
          const Session(
            id: 's2',
            dayOfWeek: 3,
            startPeriod: 1,
            endPeriod: 4, // rowSpan 4
            weeks: [1, 2, 3],
            location: 'B202',
          ),
        ),
      ],
    );

    await pumpCapturing(tester, grid(timetable, 1000));

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('大学物理'), findsOneWidget);

    final first = tester.getRect(find.byType(CourseCard).at(0));
    final second = tester.getRect(find.byType(CourseCard).at(1));
    // 同一起始行、顶端对齐，高度差恰为 2 行。
    expect(first.top, closeTo(second.top, 0.5));
    expect(second.height, greaterThan(first.height));
    expect(second.height - first.height, closeTo(2 * 52.0, 1.0));
    expect(first.overlaps(second), isFalse);
  });

  testWidgets('四门课同格也不叠加、不溢出（N 列并排）', (tester) async {
    final names = ['高等数学', '大学物理', '线性代数', '概率论'];
    final timetable = Timetable(
      semester: semester(),
      timeSlots: defaultTimeSlots(),
      courses: [
        for (var i = 0; i < names.length; i++)
          course(
            'c$i',
            names[i],
            i,
            Session(
              id: 's$i',
              dayOfWeek: 4,
              startPeriod: 5,
              endPeriod: 6,
              weeks: const [1, 2, 3],
              location: 'R$i',
            ),
          ),
      ],
    );

    final errors = await pumpCapturing(tester, grid(timetable, 900));

    for (final name in names) {
      expect(find.text(name), findsOneWidget, reason: '$name 应完整可见');
    }

    final cards = find.byType(CourseCard);
    expect(cards, findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        expect(
          tester.getRect(cards.at(i)).overlaps(tester.getRect(cards.at(j))),
          isFalse,
          reason: '第 $i 与第 $j 张卡片不应重叠',
        );
      }
    }
    expect(errors, isEmpty, reason: '$errors');
  });
}
