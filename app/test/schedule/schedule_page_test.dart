import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/schedule_event.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/repositories/schedule_event_repository.dart';
import 'package:course_timetable/features/schedule/providers/schedule_events_provider.dart';
import 'package:course_timetable/features/schedule/schedule_page.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimetableController extends TimetableController {
  @override
  Future<Timetable> build() async => Timetable(
    semester: Semester(
      id: 's1',
      name: '2026 春季学期',
      startMonday: DateTime(2026, 2, 23),
      totalWeeks: 20,
    ),
    timeSlots: defaultTimeSlots(),
    courses: const [],
  );
}

class _InMemoryScheduleRepository extends ScheduleEventRepository {
  List<ScheduleEvent> events = <ScheduleEvent>[];

  @override
  Future<List<ScheduleEvent>> load() async => List<ScheduleEvent>.of(events);

  @override
  Future<void> save(List<ScheduleEvent> events) async {
    this.events = List<ScheduleEvent>.of(events);
  }
}

void main() {
  for (final count in [0, 1, 8]) {
    testWidgets('$count 条日程时日历连续收缩，标题固定且松手不回弹', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _InMemoryScheduleRepository()
        ..events = [
          for (var i = 0; i < count; i++)
            ScheduleEvent(
              id: 'e$i',
              title: '日程 $i',
              date: DateTime.now(),
              startTime: '${(9 + i).toString().padLeft(2, '0')}:00',
              endTime: '${(9 + i).toString().padLeft(2, '0')}:30',
            ),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timetableProvider.overrideWith(() => _FakeTimetableController()),
            scheduleEventRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const SchedulePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageView = find.byType(PageView);
      expect(pageView, findsOneWidget);
      expect(tester.getSize(pageView).height, 52 * 6);

      final title = find.textContaining('年').first;
      final titlePosition = tester.getTopLeft(title);
      final gesture = await tester.startGesture(
        tester.getBottomLeft(pageView) + const Offset(180, 90),
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      final partial = tester.getSize(pageView).height;
      expect(partial, lessThan(312));
      expect(partial, greaterThan(52));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.getSize(pageView).height, closeTo(partial, 0.1));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(tester.getSize(pageView).height, closeTo(partial + 20, 1));
      expect(tester.getTopLeft(title), titlePosition);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('schedule_list')),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(pageView).height, 52);

      await tester.tap(find.byKey(const Key('schedule_calendar_toggle')));
      await tester.pumpAndSettle();
      expect(tester.getSize(pageView).height, 52 * 6);

      final before = tester.widget<Text>(find.textContaining('年').first).data;
      await tester.drag(pageView, const Offset(-360, 0));
      await tester.pumpAndSettle();
      final after = tester.widget<Text>(find.textContaining('年').first).data;
      expect(after, isNot(before));
    });
  }
}
