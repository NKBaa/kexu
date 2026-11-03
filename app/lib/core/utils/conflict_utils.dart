/// 时间冲突检测（纯函数，不依赖任何 Flutter widget）。
///
/// 大学课表里「同一时段两门课」很常见，来源有两类：
/// - 教务系统硬排冲突（同周次、同节次）；
/// - 不同的周次安排恰好落在同一节次（如单周课与双周课）——这是**合法**排课。
///
/// 因此这里的判定非常严格：**星期相同 + 节次区间有交集 + 周次有交集**
/// 三者同时成立才算冲突，避免把单/双周这种正常排课误报成冲突。
library;

import '../../data/models/course.dart';
import '../../data/models/timetable.dart';

/// 判断两组周次是否有交集。
///
/// 空列表表示「没有任何周次生效」，与任何时段都不冲突。
bool weeksOverlap(List<int> a, List<int> b) {
  if (a.isEmpty || b.isEmpty) return false;
  // 用较短的一侧遍历、较长的一侧建集合，避免 O(n*m) 的双重循环。
  final List<int> iterate = a.length <= b.length ? a : b;
  final List<int> lookup = identical(iterate, a) ? b : a;
  final set = lookup.toSet();
  for (final week in iterate) {
    if (set.contains(week)) return true;
  }
  return false;
}

/// 两个时段是否时间冲突。
///
/// 同时满足以下三条才算冲突：
/// 1. 星期相同（[Session.dayOfWeek] 相等）；
/// 2. 节次区间有交集：`a.startPeriod <= b.endPeriod && b.startPeriod <= a.endPeriod`；
/// 3. 周次有交集：单周 vs 双周这种**完全不相交**的周次不算冲突。
bool sessionsConflict(Session a, Session b) {
  if (a.dayOfWeek != b.dayOfWeek) return false;
  if (a.startPeriod > b.endPeriod || b.startPeriod > a.endPeriod) return false;
  return weeksOverlap(a.weeks, b.weeks);
}

/// 一对时间冲突的时段。
class ConflictPair {
  const ConflictPair({required this.a, required this.b});

  final SessionEntry a;
  final SessionEntry b;

  @override
  String toString() => 'ConflictPair('
      '${a.course.name}#${a.session.id} × '
      '${b.course.name}#${b.session.id})';
}

/// 计算一批时段里所有冲突对。
///
/// 入参通常是「某周某天」的时段列表（[Timetable.entriesAt] 的返回值），
/// 但函数本身不关心来源：不同天的时段会被 [sessionsConflict] 自动排除。
/// 两个时段互相冲突时只产生一个 [ConflictPair]（不会重复 a×b / b×a）。
List<ConflictPair> findConflicts(List<SessionEntry> entries) {
  final pairs = <ConflictPair>[];
  for (var i = 0; i < entries.length; i++) {
    for (var j = i + 1; j < entries.length; j++) {
      final a = entries[i];
      final b = entries[j];
      if (identical(a, b)) continue;
      if (sessionsConflict(a.session, b.session)) {
        pairs.add(ConflictPair(a: a, b: b));
      }
    }
  }
  return pairs;
}

/// 快速查询：返回「与其它时段冲突」的所有时段 id。
///
/// 结果可直接用于网格卡片高亮：`conflictedSessionIds(dayEntries).contains(session.id)`。
Set<String> conflictedSessionIds(List<SessionEntry> entries) {
  final ids = <String>{};
  for (final pair in findConflicts(entries)) {
    ids
      ..add(pair.a.session.id)
      ..add(pair.b.session.id);
  }
  return ids;
}
