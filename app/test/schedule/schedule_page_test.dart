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
  testWidgets('日程月历可收缩为单周，并保留左右滑月', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableProvider.overrideWith(() => _FakeTimetableController()),
          scheduleEventRepositoryProvider
              .overrideWithValue(_InMemoryScheduleRepository()),
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

    await tester.drag(pageView, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.getSize(pageView).height, 52);

    await tester.tap(find.byKey(const Key('schedule_calendar_toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(pageView).height, 52 * 6);

    final before = tester
        .widget<Text>(find.textContaining('年').first)
        .data;
    await tester.drag(pageView, const Offset(-360, 0));
    await tester.pumpAndSettle();
    final after = tester
        .widget<Text>(find.textContaining('年').first)
        .data;
    expect(after, isNot(before));
  });
}
