/// 节假日相关的纯函数工具。
///
/// 节假日只关心「哪一天放假」，因此所有比较都先把日期归一化到年月日，
/// 避免调用方传入带时分秒的 [DateTime] 时匹配失败。
library;

import '../../data/models/holiday.dart';
import 'week_utils.dart';

/// 把任意日期格式化成 `yyyy-MM-dd` 的日期键。
String formatDateKey(DateTime date) => Holiday.formatDateKey(date);

/// 解析 `yyyy-MM-dd`（或完整 ISO 字符串）为当天零点；无法解析时返回 null。
DateTime? parseDateKey(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return null;
  return dateOnly(parsed);
}

/// 查找 [date] 当天对应的节假日；不是节假日时返回 null。
///
/// 同一日期存在多条记录时返回第一条（列表本身应已去重）。
Holiday? holidayForDate(List<Holiday> holidays, DateTime date) {
  if (holidays.isEmpty) return null;
  final key = formatDateKey(date);
  for (final holiday in holidays) {
    if (holiday.dateKey == key) return holiday;
  }
  return null;
}

/// [date] 当天是否是节假日。
bool isHolidayDate(List<Holiday> holidays, DateTime date) =>
    holidayForDate(holidays, date) != null;

/// 按日期升序排序（同一天按名称），返回新列表，不修改入参。
List<Holiday> sortHolidays(Iterable<Holiday> holidays) {
  final out = List<Holiday>.from(holidays);
  out.sort((a, b) {
    final byDate = a.dateKey.compareTo(b.dateKey);
    return byDate != 0 ? byDate : a.name.compareTo(b.name);
  });
  return out;
}

/// 从 [from] 当天（含）开始的节假日，按日期升序。
List<Holiday> upcomingHolidays(List<Holiday> holidays, DateTime from) {
  final start = dateOnly(from);
  return sortHolidays(
    holidays.where((h) => !h.date.isBefore(start)),
  );
}

/// 去掉重复日期（保留先出现的一条），并按日期排序。
List<Holiday> normalizeHolidays(Iterable<Holiday> holidays) {
  final seen = <String>{};
  final out = <Holiday>[];
  for (final holiday in holidays) {
    if (seen.add(holiday.dateKey)) out.add(holiday);
  }
  return sortHolidays(out);
}
