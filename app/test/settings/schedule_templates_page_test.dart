import 'package:course_timetable/data/models/bell_schedule_template.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/features/settings/pages/schedule_templates_page.dart';
import 'package:course_timetable/features/settings/providers/schedule_template_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('作息模板页先展示学校，进入学校后显示详细作息', (tester) async {
    final catalog = BellScheduleTemplateCatalog(
      schools: [
        SchoolBellTemplates(
          school: '测试大学',
          note: '学校说明',
          templates: [
            BellScheduleTemplate(
              id: 't1',
              school: '测试大学',
              name: '标准作息',
              slots: const [
                TimeSlot(period: 1, start: '08:00', end: '08:45'),
                TimeSlot(period: 2, start: '08:55', end: '09:40'),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleTemplateCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: const MaterialApp(home: ScheduleTemplatesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('schedule_template_search')), findsOneWidget);
    expect(find.text('测试大学'), findsOneWidget);
    // 主页只显示学校卡片，不直接展开全部模板
    expect(find.text('标准作息'), findsNothing);

    await tester.tap(find.text('测试大学'));
    await tester.pumpAndSettle();
    expect(find.text('标准作息'), findsOneWidget);
    expect(find.text('第1节 08:00-08:45'), findsOneWidget);
    expect(find.byKey(const Key('schedule_template_apply_t1')), findsOneWidget);
  });
}
