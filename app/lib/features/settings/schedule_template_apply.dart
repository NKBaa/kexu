import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ids.dart';
import '../../../data/models/bell_schedule.dart';
import '../../../data/models/bell_schedule_template.dart';
import '../../../data/models/semester.dart';
import '../timetable/providers/timetable_provider.dart';

/// 把作息模板写入当前课表，返回实际导入的套数。
///
/// 这是模板页与使用向导共用的纯应用逻辑；UI 提示由调用方负责。
Future<int> applyScheduleTemplates(
  WidgetRef ref,
  List<BellScheduleTemplate> templates,
) async {
  if (templates.isEmpty) return 0;
  final timetable = ref.read(timetableProvider).valueOrNull;
  if (timetable == null) return 0;

  final usedNames = timetable.schedules.map((s) => s.name).toSet();
  final imported = <BellSchedule>[];
  for (final template in templates) {
    final range = materializeTemplateRange(template, timetable.semester);
    final name = uniqueScheduleName(template.name, usedNames);
    usedNames.add(name);
    imported.add(
      BellSchedule(
        id: newId(),
        name: name,
        slots: template.slots,
        startDate: range?.start,
        endDate: range?.end,
      ),
    );
  }

  final existingDated =
      timetable.schedules.where((s) => !s.isAlwaysOn).toList();
  final existingAlways =
      timetable.schedules.where((s) => s.isAlwaysOn).toList();
  final importedDated = imported.where((s) => !s.isAlwaysOn).toList();
  // 新导入的常驻模板放在旧默认作息之前，保证应用后立即生效。
  final importedAlways = imported.where((s) => s.isAlwaysOn).toList();
  await ref.read(timetableProvider.notifier).setSchedules([
    ...existingDated,
    ...importedDated,
    ...importedAlways,
    ...existingAlways,
  ]);
  return imported.length;
}

String uniqueScheduleName(String base, Set<String> used) {
  if (!used.contains(base)) return base;
  var index = 2;
  while (used.contains('$base（$index）')) {
    index++;
  }
  return '$base（$index）';
}

/// 把模板的 `MM-dd` 范围换算成本学年内的具体日期。
///
/// 例如秋季学期从 2026-09 开始时：
/// - 10-01 ~ 05-01 → 2026-10-01 ~ 2027-05-01
/// - 05-01 ~ 10-01 → 2027-05-01 ~ 2027-10-01
({DateTime start, DateTime end})? materializeTemplateRange(
  BellScheduleTemplate template,
  Semester semester,
) {
  if (!template.hasDateRange) return null;
  DateTime parse(String value, int year) {
    final parts = value.split('-');
    return DateTime(year, int.parse(parts[0]), int.parse(parts[1]));
  }

  final start = parse(template.startMonthDay!, 2000);
  final end = parse(template.endMonthDay!, 2000);
  final academicStartYear = semester.startMonday.month >= 8
      ? semester.startMonday.year
      : semester.startMonday.year - 1;
  // 8 月以后开始的区间属于本学年秋季；5~7 月开始的区间属于下一年的春季。
  final startYear = start.month >= 8 ? academicStartYear : academicStartYear + 1;
  final endYear = end.month <= start.month ? startYear + 1 : startYear;
  return (
    start: DateTime(startYear, start.month, start.day),
    end: DateTime(endYear, end.month, end.day),
  );
}
