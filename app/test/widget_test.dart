import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/features/timetable/widgets/course_card.dart';
import 'package:course_timetable/features/timetable/widgets/week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = Course(
  id: 'c1',
  semesterId: 's1',
  name: '高等数学',
  teacher: '张老师',
  colorIndex: 2,
  sessions: [
    Session(
      id: 'ss1',
      dayOfWeek: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: [1, 3, 5],
      location: 'A101',
    ),
  ],
);

const _session = Session(
  id: 'ss1',
  dayOfWeek: 1,
  startPeriod: 1,
  endPeriod: 2,
  weeks: [1, 3, 5],
  location: 'A101',
);

Timetable _timetable() => Timetable(
      semester: Semester(
        id: 's1',
        name: '测试学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: const [_course],
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 400, height: 400, child: child)),
    );

void main() {
  testWidgets('CourseCard 渲染课程名与地点', (tester) async {
    await tester.pumpWidget(_wrap(
      const CourseCard(course: _course, session: _session),
    ));

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.textContaining('A101'), findsOneWidget);
  });

  testWidgets('CourseCard 把不规律周次压缩成可读标签', (tester) async {
    await tester.pumpWidget(_wrap(
      const CourseCard(course: _course, session: _session),
    ));

    // weeks = [1,3,5] -> "1-5周(单)"
    expect(find.textContaining('单'), findsOneWidget);
  });

  testWidgets('CourseCard 显示该时段的作息时间', (tester) async {
    await tester.pumpWidget(_wrap(
      const CourseCard(
        course: _course,
        session: _session,
        timeLabel: '08:00-09:40',
      ),
    ));

    expect(find.text('08:00-09:40'), findsOneWidget);
  });

  testWidgets('CourseCard 点击回调带出课程与时段', (tester) async {
    Course? tappedCourse;
    Session? tappedSession;

    await tester.pumpWidget(_wrap(
      CourseCard(
        course: _course,
        session: _session,
        onTap: (c, s) {
          tappedCourse = c;
          tappedSession = s;
        },
      ),
    ));

    await tester.tap(find.byType(CourseCard));
    await tester.pumpAndSettle();

    expect(tappedCourse?.name, '高等数学');
    expect(tappedSession?.id, 'ss1');
  });

  testWidgets('CourseCard 长按回调带出课程与时段（用于编辑课程信息）', (tester) async {
    Course? pressedCourse;
    Session? pressedSession;

    await tester.pumpWidget(_wrap(
      CourseCard(
        course: _course,
        session: _session,
        onLongPress: (c, s) {
          pressedCourse = c;
          pressedSession = s;
        },
      ),
    ));

    await tester.longPress(find.byType(CourseCard));
    await tester.pumpAndSettle();

    expect(pressedCourse?.name, '高等数学');
    expect(pressedSession?.id, 'ss1');
  });

  testWidgets('今天高亮只出现在今天所在的教学周，不会跨周重复', (tester) async {
    final theme = AppTheme.light();
    final primaryContainer = theme.colorScheme.primaryContainer;
    final today = DateTime(2026, 2, 23); // 第 1 周周一
    bool isTodayHeader(Widget w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == primaryContainer;

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: WeekGrid(timetable: _timetable(), week: 1, today: today),
      ),
    ));
    expect(find.byWidgetPredicate(isTodayHeader), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: WeekGrid(timetable: _timetable(), week: 2, today: today),
      ),
    ));
    expect(find.byWidgetPredicate(isTodayHeader), findsNothing);
  });

  testWidgets('WeekGrid 长按空白单元格回调星期与节次', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? tappedDay;
    int? tappedStart;
    int? tappedEnd;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 800,
          child: WeekGrid(
            timetable: _timetable(),
            week: 1,
            onBlankRangeSelected: (day, start, end) {
              tappedDay = day;
              tappedStart = start;
              tappedEnd = end;
            },
          ),
        ),
      ),
    ));

    final rect = tester.getRect(find.byType(WeekGrid));
    const axis = 64.0;
    const header = 44.0;
    final rowHeight = (rect.height - header) / 10;
    final dayWidth = (rect.width - axis) / 7;
    // 周二第 5 节：该位置没有课程卡片，应命中空白长按。
    await tester.longPressAt(
      Offset(
        rect.left + axis + dayWidth * 1.5,
        rect.top + header + rowHeight * 4 + rowHeight / 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(tappedDay, 2);
    expect(tappedStart, isNotNull);
    expect(tappedEnd, isNotNull);
    expect(tappedStart, inInclusiveRange(1, 10));
    expect(tappedEnd, inInclusiveRange(1, 10));
  });

  testWidgets('WeekGrid 长按空白后拖动可选择连续节次', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int? start;
    int? end;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 800,
          child: WeekGrid(
            timetable: _timetable(),
            week: 1,
            onBlankRangeSelected: (day, s, e) {
              start = s;
              end = e;
            },
          ),
        ),
      ),
    ));

    final rect = tester.getRect(find.byType(WeekGrid));
    const axis = 64.0;
    const header = 44.0;
    final rowHeight = (rect.height - header) / 10;
    final dayWidth = (rect.width - axis) / 7;
    final x = rect.left + axis + dayWidth * 2.5; // 周三
    final startPoint = Offset(x, rect.top + header + rowHeight * 2.5);
    final gesture = await tester.startGesture(startPoint);
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(Offset(x, startPoint.dy + rowHeight * 3));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(start, isNotNull);
    expect(end, isNotNull);
    expect(end!, greaterThan(start!));
  });

  testWidgets('WeekGrid 渲染星期表头与当周课程', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: WeekGrid(timetable: _timetable(), week: 1)),
    ));

    for (final d in ['一', '二', '三', '四', '五', '六', '日']) {
      expect(find.textContaining(d), findsWidgets, reason: '缺少星期$d 表头');
    }
    expect(find.text('高等数学'), findsOneWidget);
  });

  testWidgets('WeekGrid 在课程不生效的周次不显示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      // 该课程 weeks = [1,3,5]，第 2 周不应出现
      home: Scaffold(body: WeekGrid(timetable: _timetable(), week: 2)),
    ));

    expect(find.text('高等数学'), findsNothing);
  });

  testWidgets('WeekGrid 节假日列显示「节假日」并隐藏当天课程', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: WeekGrid(
          timetable: _timetable(),
          week: 1,
          holidayDays: const {1},
        ),
      ),
    ));

    expect(find.text('高等数学'), findsNothing);
    expect(find.text('节假日'), findsOneWidget);
  });

  testWidgets('关闭「显示周六、周日」后只渲染周一到周五 5 列', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: WeekGrid(timetable: _timetable(), week: 1, showWeekend: false),
      ),
    ));

    expect(find.text('五'), findsOneWidget);
    expect(find.text('六'), findsNothing);
    expect(find.text('日'), findsNothing);
  });

  testWidgets('手机竖屏下课程名保持正常字号（不再被缩成小字）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: 430,
          height: 800,
          child: WeekGrid(timetable: _timetable(), week: 1),
        ),
      ),
    ));

    // 手机竖屏单列卡净宽约 48~58：必须按正常字号（14sp）换行显示，
    // 而不是像修复前那样整体 FittedBox 等比缩小到 5~6sp。
    final name = tester.widget<Text>(find.text('高等数学'));
    expect(
      name.style?.fontSize,
      greaterThanOrEqualTo(13),
      reason: '手机竖屏的课程名不能被缩放成小字',
    );
    expect(
      find.byType(FittedBox),
      findsNothing,
      reason: '课程名不再使用 FittedBox 等比缩小，改为换行 + 省略号',
    );
    // 教师与教室默认显示在卡片上，不需要点开详情。
    expect(find.text('张老师'), findsOneWidget);
    expect(find.text('A101'), findsOneWidget);
  });
}
