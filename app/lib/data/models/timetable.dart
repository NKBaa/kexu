import '../../core/utils/week_utils.dart';
import 'bell_schedule.dart';
import 'course.dart';
import 'semester.dart';

/// 课表中的一个格子：某门课的一个时段。
class SessionEntry {
  final Course course;
  final Session session;

  const SessionEntry({required this.course, required this.session});

  /// 该时段在网格中占用的行数。
  int get rowSpan => session.span;
}

/// 完整课表聚合：学期 + 课程 + 作息（可多套）。
///
/// 这是整个 App 的数据根，也是 AI 层与 UI 层共享的读模型。
///
/// 作息支持**多套方案**（如夏季/秋季作息），每套可带生效日期区间，
/// 展示时按「当前周所在日期」自动选中对应方案。
class Timetable {
  final Semester semester;
  final List<Course> courses;

  /// 作息方案列表（顺序即优先级：限定日期的方案应排在前面）。
  final List<BellSchedule> schedules;

  const Timetable._({
    required this.semester,
    required this.courses,
    required this.schedules,
  });

  /// 隐式默认作息方案的固定 id。
  ///
  /// **必须是确定性的**，不能用 `newId()` 随机生成：
  /// 同步层是按内容哈希判断「有没有改动」的，如果同一份课表每次构造
  /// 都得到不同的作息 id，就会被一直误判成「本地改了」而反复上传，
  /// 而且两端也无法判定为一致。
  static const String defaultScheduleId = 'default';

  /// 构造课表。
  ///
  /// [timeSlots] 是**兼容旧代码**的入口：传它就等于「只有一套不限日期的作息」。
  /// [schedules] 优先；两者都没传时用默认 12 节作息。
  factory Timetable({
    required Semester semester,
    List<Course> courses = const [],
    List<BellSchedule>? schedules,
    List<TimeSlot>? timeSlots,
  }) {
    List<BellSchedule> resolved;
    if (schedules != null && schedules.isNotEmpty) {
      resolved = List<BellSchedule>.from(schedules);
    } else if (timeSlots != null && timeSlots.isNotEmpty) {
      resolved = [
        BellSchedule(
          id: defaultScheduleId,
          name: '默认作息',
          slots: List<TimeSlot>.from(timeSlots),
        ),
      ];
    } else {
      resolved = [
        BellSchedule(
          id: defaultScheduleId,
          name: '默认作息',
          slots: defaultTimeSlots(),
        ),
      ];
    }
    return Timetable._(
      semester: semester,
      courses: List<Course>.unmodifiable(courses),
      schedules: List<BellSchedule>.unmodifiable(resolved),
    );
  }

  /// 兼容旧代码：默认（第一套）作息。
  ///
  /// 注意：周视图请用 [slotsForWeek]，它会按周次日期挑选真正生效的方案。
  List<TimeSlot> get timeSlots => schedules.first.slots;

  /// 当前日期下生效的作息方案。
  BellSchedule get activeSchedule => resolveScheduleFor(schedules, DateTime.now()) ?? schedules.first;

  /// [date] 当天生效的作息方案。
  BellSchedule scheduleForDate(DateTime date) =>
      resolveScheduleFor(schedules, date) ?? schedules.first;

  /// [date] 当天生效的作息时间表。
  List<TimeSlot> slotsForDate(DateTime date) => scheduleForDate(date).slots;

  /// 第 [week] 周（按周一的日期判定）生效的作息时间表。
  List<TimeSlot> slotsForWeek(int week) {
    final monday = dateOfWeekDay(semester.startMonday, week < 1 ? 1 : week, 1);
    return slotsForDate(monday);
  }

  Timetable copyWith({
    Semester? semester,
    List<Course>? courses,
    List<BellSchedule>? schedules,
    List<TimeSlot>? timeSlots,
  }) =>
      Timetable(
        semester: semester ?? this.semester,
        courses: courses ?? this.courses,
        // 传 timeSlots 时表示「把默认那套作息改掉」，其余方案保留
        schedules: schedules ??
            (timeSlots == null
                ? this.schedules
                : [
                    for (var i = 0; i < this.schedules.length; i++)
                      i == 0 ? this.schedules[i].copyWith(slots: timeSlots) : this.schedules[i],
                  ]),
        timeSlots: timeSlots,
      );

  /// 某个周次、星期几的所有时段，按起始节次排序。
  List<SessionEntry> entriesAt(int week, int dayOfWeek) {
    final out = <SessionEntry>[];
    for (final c in courses) {
      for (final s in c.sessions) {
        if (s.dayOfWeek == dayOfWeek && s.weeks.contains(week)) {
          out.add(SessionEntry(course: c, session: s));
        }
      }
    }
    out.sort((a, b) => a.session.startPeriod.compareTo(b.session.startPeriod));
    return out;
  }

  /// 整周的所有时段，用于周视图一次性布局。
  Map<int, List<SessionEntry>> byDayForWeek(int week) {
    return {
      for (var d = 1; d <= 7; d++) d: entriesAt(week, d),
    };
  }

  /// 按名称模糊查找课程（AI 指令里通常只给课程名）。
  List<Course> findCourses(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return const [];
    final exact = courses.where((c) => c.name == k).toList();
    if (exact.isNotEmpty) return exact;
    return courses.where((c) => c.name.contains(k) || k.contains(c.name)).toList();
  }

  /// 课程总数与时段总数，用于概览统计。
  int get sessionCount => courses.fold<int>(0, (sum, c) => sum + c.sessions.length);

  /// 课程使用的最大节次（用于网格行数）。
  ///
  /// 要取**所有作息方案**的最大值：夏季作息可能是 12 节、冬季 10 节，
  /// 只在某一套下渲染会漏掉另一个方案的节次。
  int get maxPeriod {
    var m = 0;
    for (final c in courses) {
      for (final s in c.sessions) {
        if (s.endPeriod > m) m = s.endPeriod;
      }
    }
    for (final schedule in schedules) {
      final sp = schedule.maxPeriod;
      if (sp > m) m = sp;
    }
    return m > 0 ? m : 12;
  }

  /// 序列化为可持久化/可导出的 JSON。
  ///
  /// 同时写出 `schedules`（新格式）与 `timeSlots`（旧格式的默认作息），
  /// 这样旧版本 App 或旧备份仍能读到一份可用的作息。
  Map<String, dynamic> toJson() => {
        'version': 2,
        'semester': semester.toJson(),
        'schedules': schedules.map((s) => s.toJson()).toList(),
        'timeSlots': timeSlots.map((t) => t.toJson()).toList(),
        'courses': courses.map((c) => c.toJson()).toList(),
      };

  static Timetable fromJson(Map<String, dynamic> j) {
    final semJson = j['semester'];

    // 新格式：schedules；旧格式：只有 timeSlots —— 自动包装成一套方案。
    final rawSchedules = j['schedules'];
    List<BellSchedule>? schedules;
    if (rawSchedules is List && rawSchedules.isNotEmpty) {
      schedules = rawSchedules
          .map((e) => BellSchedule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    List<TimeSlot>? legacySlots;
    final rawSlots = j['timeSlots'];
    if (rawSlots is List) {
      final parsed = rawSlots
          .map((e) => TimeSlot.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (parsed.isNotEmpty) legacySlots = parsed;
    }

    return Timetable(
      semester: semJson is Map
          ? Semester.fromJson(Map<String, dynamic>.from(semJson))
          : Semester(
              id: 'default',
              name: '默认学期',
              startMonday: DateTime.now(),
              totalWeeks: 16,
            ),
      schedules: schedules,
      timeSlots: legacySlots,
      courses: (j['courses'] as List?)
              ?.map((e) => Course.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }
}
