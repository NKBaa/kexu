/// 周次 / 日期 / 节次相关的纯函数工具。
///
/// 大学课表最大的痛点是「不规律」：单周、双周、断续周次（3-5,7-9周）、
/// 一门课一周上多次、临时调课补课。因此本文件的核心策略是：
/// **周次一律用显式的 `List<int>` 表示**（如 `[1,2,3,...,16]`、`[1,3,5,7]`），
/// 而不是用「起始周 + 单双周」这种有损压缩表示。这样任何不规律组合都能精确表达，
/// 只在展示与解析时再压缩成人能读的字符串。
library;

/// 把任意日期归一化到「当天零点」。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 计算两个日期之间相差的自然天数（用 UTC 归一化，规避夏令时导致的 23/25 小时问题）。
int daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// 给定日期所在周的周一（零点）。
DateTime mondayOf(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 在周一的基础上加上 [days] 天，返回归一化后的本地日期。
DateTime addDays(DateTime base, int days) {
  final u = DateTime.utc(base.year, base.month, base.day).add(Duration(days: days));
  return DateTime(u.year, u.month, u.day);
}

/// 计算 [date] 落在第几周（第 1 周从 [semesterStartMonday] 所在周算起）。
///
/// 早于开学周会返回 <= 0 的值，调用方自行判断。
int weekOfDate(DateTime date, DateTime semesterStartMonday) {
  final start = mondayOf(semesterStartMonday);
  return daysBetween(start, date) ~/ 7 + 1;
}

/// 计算第 [week] 周、星期 [dayOfWeek]（1=周一 … 7=周日）对应的具体日期。
DateTime dateOfWeekDay(DateTime semesterStartMonday, int week, int dayOfWeek) {
  final start = mondayOf(semesterStartMonday);
  return addDays(start, (week - 1) * 7 + (dayOfWeek - 1));
}

/// 已知「今天」是第 [week] 周，反推第 1 周的周一。
///
/// 设置学期时，用户常常只记得「现在是第几周」，却不知道开学那周的周一是哪天。
/// 这个函数把「今天第 N 周」换算成学期起始周，设置页据此一键定位学期范围。
/// [week] <= 0 时按第 1 周处理（即今天所在周的周一）。
DateTime startMondayForWeek(DateTime today, int week) {
  final w = week < 1 ? 1 : week;
  return addDays(mondayOf(today), -(w - 1) * 7);
}

/// 把周次列表压缩成人类可读字符串。
///
/// 规则：
/// - 连续区间用 `a-b`，零散用逗号，如 `[1,2,3,5,6]` -> `1-3,5-6`
/// - 若某个连续区间内全是奇数或全是偶数，追加 `(单)` / `(双)`，
///   如 `[1,3,5,7]` -> `1-7周(单)`
/// - 空列表返回空串
String formatWeeks(List<int> weeks, {String suffix = '周'}) {
  final sorted = weeks.where((w) => w > 0).toSet().toList()..sort();
  if (sorted.isEmpty) return '';

  final parts = <String>[];
  var i = 0;
  while (i < sorted.length) {
    // 1) 优先取「连续周」区间（步长 1），这是最常见的形态。
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] - sorted[j] == 1) {
      j++;
    }
    if (j > i) {
      parts.add('${sorted[i]}-${sorted[j]}');
      i = j + 1;
      continue;
    }

    // 2) 再考虑「单/双周」（步长 2）。
    //    要求至少 3 个元素，否则像 [6,8,9,10] 里的 6、8 会被误判成「双周」，
    //    而正确读法是「6,8-10 周」。
    var k = i;
    while (k + 1 < sorted.length && sorted[k + 1] - sorted[k] == 2) {
      k++;
    }
    if (k - i + 1 >= 3) {
      final first = sorted[i];
      final last = sorted[k];
      final marker = first.isOdd ? '单' : '双';
      parts.add('$first-$last$suffix($marker)');
      i = k + 1;
      continue;
    }

    parts.add('${sorted[i]}');
    i++;
  }

  final body = parts.join(',');
  // 带「(单)/(双)」的片段已经自带「周」字，只有普通片段需要补后缀。
  final hasPlain = parts.any((p) => !p.contains('('));
  return hasPlain ? '$body$suffix' : body;
}

/// 解析人类/AI 写出的周次描述为显式周次列表。
///
/// 支持的形式举例：
/// - `1-16`、`1-16周`、`第1-16周`
/// - `1,3,5`、`3-5,7-9`
/// - `1-16周(单)`、`1-16单周`、`单周`、`双周`
/// - `1-8周,10-16周`（多段）
/// - 空 / 无法识别时返回 `[]`
///
/// [singleOddEvenHint] 用于「只说单周/双周、没给范围」的场景，默认按 1-16 周推算。
List<int> parseWeeks(String? raw, {int maxWeek = 16}) {
  if (raw == null) return const <int>[];
  var s = raw.trim();
  if (s.isEmpty) return const <int>[];

  // 全角数字转半角（如「１－４」这种从 PDF/网页复制来的写法）
  s = s.replaceAllMapped(
    RegExp('[\uFF10-\uFF19]'),
    (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
  );

  // 全角转半角，去掉中文修饰
  s = s
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('~', '-')
      .replaceAll('～', '-')
      .replaceAll('至', '-')
      .replaceAll('，', ',')
      .replaceAll('、', ',')
      .replaceAll('；', ',')
      .replaceAll(';', ',')
      .replaceAll(' ', '')
      .replaceAll('第', '')
      .replaceAll('周次', '')
      .replaceAll('周', '');

  // 是否带「单」/「双」标记。
  //
  // 单段表达式里的标记修饰整体：`1-8周(单)`、`1-8单周`、`单周`。
  // 多段表达式（含逗号）里标记只作用于紧邻的那一段，属于罕见写法，
  // 此时不做全局奇偶过滤（AI 通常会直接给出显式 weeks 数组）。
  final parenless = s.replaceAll('(', '').replaceAll(')', '').replaceAll('（', '').replaceAll('）', '');
  final singleSegment = !s.contains(',');
  final oddOnly = singleSegment && s.contains('单');
  final evenOnly = singleSegment && s.contains('双');
  s = parenless.replaceAll('单', '').replaceAll('双', '');

  final out = <int>{};
  // 先解析所有 a-b 区间，再解析逗号分隔的单点
  for (final seg in s.split(',')) {
    if (seg.isEmpty) continue;
    final m = RegExp(r'^(\d+)-(\d+)$').firstMatch(seg);
    if (m != null) {
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) continue;
      final lo = a <= b ? a : b;
      final hi = a <= b ? b : a;
      for (var w = lo; w <= hi && w <= 60; w++) {
        out.add(w);
      }
      continue;
    }
    final single = int.tryParse(seg);
    if (single != null && single > 0) out.add(single);
  }

  // 没有具体范围但出现了「单周/双周」：按默认总周数展开
  if (out.isEmpty && (oddOnly || evenOnly)) {
    for (var w = 1; w <= maxWeek; w++) {
      if (oddOnly && w.isOdd) out.add(w);
      if (evenOnly && w.isEven) out.add(w);
    }
    return out.toList()..sort();
  }

  if (oddOnly) out.removeWhere((w) => w.isEven);
  if (evenOnly) out.removeWhere((w) => w.isOdd);

  return out.toList()..sort();
}

/// 星期几的中文短称（1=周一）。
const List<String> weekdayShortNames = ['一', '二', '三', '四', '五', '六', '日'];

/// 星期的展示名，如「周一」。
String weekdayName(int dayOfWeek) {
  if (dayOfWeek < 1 || dayOfWeek > 7) return '?';
  return '周${weekdayShortNames[dayOfWeek - 1]}';
}

/// 归一化节次：保证 start <= end 且都 >= 1。
({int start, int end}) normalizePeriods(int a, int b) {
  final s = a < 1 ? 1 : a;
  final e = b < 1 ? s : b;
  return s <= e ? (start: s, end: e) : (start: e, end: s);
}
