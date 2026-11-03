/// 「现在」的时间上下文：把系统时间换算成教学周、本周日期与当天作息。
///
/// 大模型本身不知道「今天」是哪一天：用户说「明天的课」「下周三」「这周」时，
/// 只有把当前时间、教学周、本周每天对应日期一并喂给它，它才能算出
/// 显式的 `dayOfWeek + weeks`。因此 [NowContext.toPromptText] 的输出是
/// 提示词的一部分，必须稳定、无歧义（中文星期 + 数字日期）。
///
/// 本文件是**纯函数、无 IO**：只依赖传入的 [Timetable] 与 [DateTime]，
/// 便于单元测试，也保证提示词可以复现。
library;

import '../../core/utils/week_utils.dart';
import '../../data/models/semester.dart';
import '../../data/models/timetable.dart';

/// 一次请求时的「现在」快照。
class NowContext {
  const NowContext({
    required this.now,
    required this.academicWeek,
    required this.totalWeeks,
    required this.semesterStartMonday,
    required this.slots,
  });

  /// 从课表与（可选的）当前时间构造。
  ///
  /// [academicWeek] 用 [weekOfDate] 计算：0 表示不在学期内（未开学或已放假）。
  /// [slots] 取**当天生效**的作息（[Timetable.slotsForDate]），
  /// 这样夏季/冬季作息切换时，「下午」映射到的节次才是对的。
  factory NowContext.fromTimetable(Timetable t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final week = weekOfDate(n, t.semester.startMonday);
    final inSemester = week >= 1 && week <= t.semester.totalWeeks;
    return NowContext(
      now: n,
      academicWeek: inSemester ? week : 0,
      totalWeeks: t.semester.totalWeeks,
      semesterStartMonday: mondayOf(t.semester.startMonday),
      slots: List<TimeSlot>.unmodifiable(t.slotsForDate(n)),
    );
  }

  /// 当前日期时间（含时分，便于判断「晚上」「现在」这类说法）。
  final DateTime now;

  /// 当前教学周；0 表示不在学期内。
  final int academicWeek;

  /// 学期总周数。
  final int totalWeeks;

  /// 第 1 周周一（已归一化到周一零点）。
  final DateTime semesterStartMonday;

  /// 今天生效的作息时间表。
  final List<TimeSlot> slots;

  /// 今天是否落在学期内。
  bool get inSemester => academicWeek >= 1;

  /// 今天所在周的周一。
  DateTime get weekMonday => mondayOf(now);

  /// 下一周（自然周，不一定在学期内）的周一。
  DateTime get nextWeekMonday => addDays(weekMonday, 7);

  /// 下一教学周编号；0 表示没有下一教学周（学期已结束 / 本周是最后一周）。
  int get nextAcademicWeek {
    if (inSemester) return academicWeek < totalWeeks ? academicWeek + 1 : 0;
    // 还没开学时，下一个教学周就是第 1 周；学期结束后没有下一教学周。
    final raw = weekOfDate(now, semesterStartMonday);
    return raw < 1 ? 1 : 0;
  }

  /// 本周 [dayOfWeek]（1=周一 … 7=周日）对应的日期。
  DateTime dateOfThisWeek(int dayOfWeek) => addDays(weekMonday, dayOfWeek - 1);

  /// 星期几的中文标签，如「周日」。
  String get weekdayLabel => weekdayName(now.weekday);

  /// `MM-DD` 形式的日期，用于顶部信息条。
  String get monthDayLabel => '${_two(now.month)}-${_two(now.day)}';

  /// `HH:mm` 形式的时间。
  String get timeLabel => '${_two(now.hour)}:${_two(now.minute)}';

  /// `yyyy-MM-dd HH:mm` 形式的完整时间。
  String get dateTimeLabel => '${now.year}-${_two(now.month)}-${_two(now.day)} $timeLabel';

  /// 顶部信息条用的教学周标签，如「第 5 教学周（共 16 周）」。
  String get weekLabel =>
      inSemester ? '第 $academicWeek 教学周（共 $totalWeeks 周）' : '不在学期内';

  /// 按当天作息划分出的「上午」节次（12:00 之前开始）。
  List<int> get _morningPeriods => _periodsWhere((h) => h < 12);

  /// 按当天作息划分出的「下午」节次（12:00~18:00 开始）。
  List<int> get _afternoonPeriods => _periodsWhere((h) => h >= 12 && h < 18);

  /// 按当天作息划分出的「晚上」节次（18:00 之后开始）。
  List<int> get _eveningPeriods => _periodsWhere((h) => h >= 18);

  /// 给大模型的时间上下文文本（纯函数，便于单测）。
  String toPromptText() {
    final buf = StringBuffer()
      ..writeln('现在的时间上下文（用户说的「今天/明天/本周/下周」都必须按这里换算，不要凭空猜日期）：')
      ..writeln('- 当前日期时间：$dateTimeLabel（$weekdayLabel）')
      ..writeln('- 当前教学周：${_weekDescription()}')
      ..writeln('- 本周每天对应日期：${_weekDatesText()}')
      ..writeln('- 明天 / 后天：${_relativeDayText(1)}；${_relativeDayText(2)}')
      ..writeln('- 下一教学周：${_nextWeekDescription()}')
      ..writeln('- 今天各节次时间：${_todaySlotsText()}');
    final partRule = _partOfDayRuleText();
    if (partRule.isNotEmpty) buf.writeln('- 按今天作息，$partRule');
    return buf.toString().trimRight();
  }

  // ---------------------------------------------------------------- 内部实现

  String _weekDescription() {
    if (inSemester) return '第 $academicWeek 周（学期共 $totalWeeks 周）';
    final raw = weekOfDate(now, semesterStartMonday);
    if (raw < 1) {
      return '不在学期内（学期还没开始；第 1 周周一是 ${_date(semesterStartMonday)}，学期共 $totalWeeks 周）';
    }
    return '不在学期内（学期已结束；今天是第 $raw 周，学期共 $totalWeeks 周）';
  }

  String _weekDatesText() => [
        for (var d = 1; d <= 7; d++) '${weekdayName(d)} ${_date(dateOfThisWeek(d))}',
      ].join('、');

  String _nextWeekDescription() {
    final next = nextAcademicWeek;
    if (next > 0) return '第 $next 周（${_date(nextWeekMonday)} 起）';
    if (inSemester && academicWeek >= totalWeeks) {
      return '没有（本周是学期最后一周）';
    }
    return '没有（学期已结束）';
  }

  String _relativeDayText(int offset) {
    final d = addDays(now, offset);
    final w = weekOfDate(d, semesterStartMonday);
    final inSem = w >= 1 && w <= totalWeeks;
    final weekPart = inSem ? '第 $w 周' : '不在学期内';
    return '${weekdayName(d.weekday)} ${_date(d)}（$weekPart）';
  }

  String _todaySlotsText() {
    if (slots.isEmpty) return '今天没有可用的作息时间（作息表为空）';
    return [
      for (final s in slots) '第${s.period}节 ${s.start}-${s.end}',
    ].join('；');
  }

  String _partOfDayRuleText() {
    final parts = <String>[];
    final morning = _periodRangeText(_morningPeriods);
    if (morning.isNotEmpty) {
      parts.add('「上午」指$morning（${_firstStart(_morningPeriods)} 开始）');
    }
    final afternoon = _periodRangeText(_afternoonPeriods);
    if (afternoon.isNotEmpty) {
      parts.add('「下午」指$afternoon（${_firstStart(_afternoonPeriods)} 开始）');
    }
    final evening = _periodRangeText(_eveningPeriods);
    if (evening.isNotEmpty) {
      parts.add('「晚上」指$evening（${_firstStart(_eveningPeriods)} 开始）');
    }
    return parts.join('；');
  }

  /// 把节次列表压缩成「第1-4节」「第1-2、5节」这类可读文本。
  String _periodRangeText(List<int> periods) {
    if (periods.isEmpty) return '';
    final sorted = periods.toSet().toList()..sort();
    final parts = <String>[];
    var i = 0;
    while (i < sorted.length) {
      var j = i;
      while (j + 1 < sorted.length && sorted[j + 1] - sorted[j] == 1) {
        j++;
      }
      parts.add(j > i ? '第${sorted[i]}-${sorted[j]}节' : '第${sorted[i]}节');
      i = j + 1;
    }
    return parts.join('、');
  }

  String _firstStart(List<int> periods) {
    if (periods.isEmpty) return '';
    final target = periods.reduce((a, b) => a < b ? a : b);
    for (final s in slots) {
      if (s.period == target) return s.start;
    }
    return '';
  }

  List<int> _periodsWhere(bool Function(int hour) test) {
    final out = <int>[];
    for (final s in slots) {
      final hour = int.tryParse(s.start.split(':').first);
      if (hour == null) continue;
      if (test(hour)) out.add(s.period);
    }
    out.sort();
    return out;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
}
