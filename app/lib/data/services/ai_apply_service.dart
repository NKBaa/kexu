import '../../core/utils/ids.dart';
import '../../core/utils/json_utils.dart';
import '../../core/utils/week_utils.dart';
import '../models/ai_ops.dart';
import '../models/bell_schedule.dart';
import '../models/course.dart';
import '../models/draft.dart';
import '../models/semester.dart';
import '../models/timetable.dart';

/// 单条操作的应用结果。
class OpOutcome {
  final AiOp op;
  final bool applied;

  /// 失败/跳过原因（[applied] 为 false 时有值）。
  final String? reason;

  /// 成功时的可读说明。
  final String? detail;

  const OpOutcome({
    required this.op,
    required this.applied,
    this.reason,
    this.detail,
  });

  String describe() {
    if (applied) {
      return detail ?? '已执行：${op.describe()}';
    }
    return '已跳过「${op.describe()}」：$reason';
  }
}

/// 一次应用的整体结果。
class ApplyReport {
  final Timetable timetable;
  final List<OpOutcome> outcomes;

  const ApplyReport({required this.timetable, required this.outcomes});

  int get appliedCount => outcomes.where((o) => o.applied).length;
  int get skippedCount => outcomes.where((o) => !o.applied).length;

  List<String> get appliedDetails =>
      outcomes.where((o) => o.applied).map((o) => o.describe()).toList();

  List<String> get skippedDetails =>
      outcomes.where((o) => !o.applied).map((o) => o.describe()).toList();

  /// 面向用户的一句话总结。
  String get summary {
    if (outcomes.isEmpty) return '没有需要执行的改动。';
    final buf = StringBuffer('成功应用 $appliedCount 项改动');
    if (skippedCount > 0) buf.write('，跳过 $skippedCount 项');
    buf.write('。');
    return buf.toString();
  }
}

/// 把大模型给出的结构化操作应用到课表上。
///
/// 这是「AI 改课表」的最后一公里：模型只负责理解意图并输出 [AiOp]，
/// 真正的定位（按课程名找 id）、字段合并、周次解析都在这里完成。
/// 整个过程是**纯函数**：输入旧课表 + 操作计划，输出新课表 + 执行报告，
/// 不碰数据库，因此可以安全地用于「预览」和单元测试。
class AiApplyService {
  const AiApplyService();

  ApplyReport apply(Timetable base, AiEditPlan plan) {
    var current = base;
    final outcomes = <OpOutcome>[];

    for (final op in plan.ops) {
      final result = _applyOne(current, op);
      current = result.$1;
      outcomes.add(result.$2);
    }

    return ApplyReport(timetable: current, outcomes: outcomes);
  }

  /// 返回 (新课表, 执行结果)。
  (Timetable, OpOutcome) _applyOne(Timetable t, AiOp op) {
    switch (op.kind) {
      case AiOpKind.addCourse:
        return _addCourse(t, op);
      case AiOpKind.deleteCourse:
        return _deleteCourse(t, op);
      case AiOpKind.updateCourse:
        return _updateCourse(t, op);
      case AiOpKind.addSession:
        return _addSession(t, op);
      case AiOpKind.deleteSession:
        return _deleteSession(t, op);
      case AiOpKind.updateSession:
        return _updateSession(t, op, move: false);
      case AiOpKind.moveSession:
        return _updateSession(t, op, move: true);
      case AiOpKind.updatePeriod:
        return _updatePeriod(t, op);
      case AiOpKind.shiftSchedule:
        return _shiftSchedule(t, op);
      case AiOpKind.unknown:
        return (t, OpOutcome(op: op, applied: false, reason: '无法识别的操作类型'));
    }
  }

  // ------------------------------------------------------------- 课程级操作

  (Timetable, OpOutcome) _addCourse(Timetable t, AiOp op) {
    final name = op.courseName.trim().isEmpty
        ? pickNonEmpty([
            (op.args['name'] ?? '').toString(),
            (op.args['courseName'] ?? '').toString(),
          ])
        : op.courseName.trim();
    if (name.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '缺少课程名'));
    }

    // 已存在同名课程时，退化为「给它加时段」，避免产生重复课程
    final existing = t.findCourses(name);
    if (existing.length == 1) {
      final merged = _mergeSessions(t, existing.first, op);
      if (merged != null) return merged;
    }

    final defaultWeeks = t.semester.allWeeks;
    final draft = DraftCourse.fromAiJson(
      <String, dynamic>{
        'name': name,
        'teacher': op.args['teacher'] ?? op.args['instructor'],
        'note': op.args['note'],
        'sessions': op.args['sessions'] ?? _inlineSession(op),
      },
      defaultWeeks: defaultWeeks,
    );

    if (draft.sessions.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '没有可用的上课时段信息'));
    }

    final course = Course(
      id: newId(),
      semesterId: t.semester.id,
      name: draft.name,
      teacher: draft.teacher,
      courseCode: draft.courseCode,
      credit: draft.credit,
      note: draft.note,
      colorIndex: _nextColorIndex(t),
      sessions: draft.sessions.map(_toSession).toList(),
    );

    return (
      t.copyWith(courses: [...t.courses, course]),
      OpOutcome(op: op, applied: true, detail: '已新增课程「${course.name}」'),
    );
  }

  /// 把 op 里的时段信息组装成 sessions 数组（当模型直接给了 day/period 字段时）。
  List<Map<String, dynamic>>? _inlineSession(AiOp op) {
    final day = op.args['dayOfWeek'] ?? op.args['day'];
    final period = op.args['startPeriod'] ?? op.args['period'] ?? op.args['start'];
    if (day == null && period == null) return null;
    return [op.args];
  }

  (Timetable, OpOutcome) _deleteCourse(Timetable t, AiOp op) {
    final matched = t.findCourses(op.courseName);
    if (matched.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '课表中找不到课程「${op.courseName}」'));
    }
    final ids = matched.map((c) => c.id).toSet();
    final names = matched.map((c) => c.name).join('、');
    return (
      t.copyWith(courses: t.courses.where((c) => !ids.contains(c.id)).toList()),
      OpOutcome(op: op, applied: true, detail: '已删除课程「$names」'),
    );
  }

  (Timetable, OpOutcome) _updateCourse(Timetable t, AiOp op) {
    final matched = t.findCourses(op.courseName);
    if (matched.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '课表中找不到课程「${op.courseName}」'));
    }
    final patch = op.patchSpec;
    final newName = pickNonEmpty([
      (patch['newName'] ?? '').toString(),
      (patch['name'] ?? '').toString(),
    ]);
    final newTeacher = pickNonEmpty([
      (patch['teacher'] ?? '').toString(),
      (patch['instructor'] ?? '').toString(),
    ]);
    final newNote = (patch['note'] ?? '').toString();

    if (newName.isEmpty && newTeacher.isEmpty && newNote.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '没有可识别的修改字段'));
    }

    final ids = matched.map((c) => c.id).toSet();
    final updated = t.courses.map((c) {
      if (!ids.contains(c.id)) return c;
      return c.copyWith(
        name: newName.isEmpty ? null : newName,
        teacher: newTeacher.isEmpty ? null : newTeacher,
        note: newNote.isEmpty ? null : newNote,
      );
    }).toList();

    final what = [
      if (newName.isNotEmpty) '名称→$newName',
      if (newTeacher.isNotEmpty) '教师→$newTeacher',
      if (newNote.isNotEmpty) '备注已更新',
    ].join('，');

    return (
      t.copyWith(courses: updated),
      OpOutcome(op: op, applied: true, detail: '已修改「${op.courseName}」：$what'),
    );
  }

  // ------------------------------------------------------------- 时段级操作

  (Timetable, OpOutcome) _addSession(Timetable t, AiOp op) {
    final matched = t.findCourses(op.courseName);
    if (matched.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '课表中找不到课程「${op.courseName}」'));
    }
    final merged = _mergeSessions(t, matched.first, op);
    if (merged == null) {
      return (t, OpOutcome(op: op, applied: false, reason: '时段信息不完整（需要星期与节次）'));
    }
    return merged;
  }

  /// 给指定课程追加 op 描述的时段；信息不足时返回 null。
  (Timetable, OpOutcome)? _mergeSessions(Timetable t, Course course, AiOp op) {
    final spec = op.matchSpec;
    final day = parseDayOfWeek(spec['dayOfWeek'] ?? spec['day'] ?? spec['weekday']);
    final start = _asIntOrNull(spec['startPeriod'] ?? spec['start'] ?? spec['period']);
    if (start == null) return null;
    final end = _asIntOrNull(spec['endPeriod'] ?? spec['end']) ?? start;

    final weeks = op.weeks ?? t.semester.allWeeks;
    final p = normalizePeriods(start, end);

    final session = Session(
      id: newId(),
      dayOfWeek: day,
      startPeriod: p.start,
      endPeriod: p.end,
      weeks: weeks,
      location: op.location,
      teacher: op.teacher,
    );

    final updated = course.copyWith(sessions: [...course.sessions, session]);
    final next = t.copyWith(
      courses: t.courses.map((c) => c.id == course.id ? updated : c).toList(),
    );
    return (
      next,
      OpOutcome(
        op: op,
        applied: true,
        detail: '已为「${course.name}」新增时段 ${session.describe()}',
      ),
    );
  }

  (Timetable, OpOutcome) _deleteSession(Timetable t, AiOp op) {
    final matched = t.findCourses(op.courseName);
    if (matched.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '课表中找不到课程「${op.courseName}」'));
    }
    final course = matched.first;
    final targets = _matchSessions(course, _explicitMatch(op) ?? op.args);
    if (targets.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '没有匹配到要删除的时段'));
    }
    final ids = targets.map((s) => s.id).toSet();
    final updated = course.copyWith(
      sessions: course.sessions.where((s) => !ids.contains(s.id)).toList(),
    );
    final next = t.copyWith(
      courses: t.courses.map((c) => c.id == course.id ? updated : c).toList(),
    );
    return (
      next,
      OpOutcome(
        op: op,
        applied: true,
        detail: '已从「${course.name}」删除 ${targets.length} 个时段',
      ),
    );
  }

  (Timetable, OpOutcome) _updateSession(Timetable t, AiOp op, {required bool move}) {
    final matched = t.findCourses(op.courseName);
    if (matched.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '课表中找不到课程「${op.courseName}」'));
    }
    final course = matched.first;

    // 定位策略（关键）：
    // - 模型给了显式 `match`/`from` 子对象：用它定位。
    // - 调课（move）且没给来源：args 里的星期/节次是「调到哪」，不是「从哪调」，
    //   因此语义是「把该课程整体挪到新时间」，匹配全部时段。
    // - 修改（update）且没给来源：args 里的星期/节次当作定位条件
    //   （如「把周三 5-6 节的地点改到 B203」）；周次字段不能当定位条件，
    //   因为它通常是「要改成的新周次」，拿它做重叠过滤会让「双周改单周」匹配不到。
    final criteria = _explicitMatch(op) ??
        (move ? const <String, dynamic>{} : _positionalCriteria(op.args));
    final targets = _matchSessions(course, criteria);
    if (targets.isEmpty) {
      return (t, OpOutcome(op: op, applied: false, reason: '没有匹配到要修改的时段'));
    }
    final targetIds = targets.map((s) => s.id).toSet();
    final patch = op.patchSpec;

    final newDay = _asIntOrNull(patch['dayOfWeek'] ?? patch['day'] ?? patch['weekday']);
    final newStart = _asIntOrNull(patch['startPeriod'] ?? patch['start'] ?? patch['period']);
    final newEnd = _asIntOrNull(patch['endPeriod'] ?? patch['end']);
    final newWeeks = op.weeks;
    final newLocation = op.location;

    if (newDay == null &&
        newStart == null &&
        newEnd == null &&
        newWeeks == null &&
        newLocation == null) {
      return (t, OpOutcome(op: op, applied: false, reason: '没有可识别的修改字段'));
    }

    final updatedSessions = course.sessions.map((s) {
      if (!targetIds.contains(s.id)) return s;
      final start = newStart ?? s.startPeriod;
      final end = newEnd ?? newStart ?? s.endPeriod;
      final p = normalizePeriods(start, end);
      return s.copyWith(
        dayOfWeek: newDay ?? s.dayOfWeek,
        startPeriod: p.start,
        endPeriod: p.end,
        weeks: newWeeks ?? s.weeks,
        location: newLocation ?? s.location,
      );
    }).toList();

    final updated = course.copyWith(sessions: updatedSessions);
    final next = t.copyWith(
      courses: t.courses.map((c) => c.id == course.id ? updated : c).toList(),
    );
    final verb = move ? '调课' : '修改时段';
    return (
      next,
      OpOutcome(
        op: op,
        applied: true,
        detail: '已$verb「${course.name}」的 ${targets.length} 个时段',
      ),
    );
  }

  // ------------------------------------------------------------- 作息级操作

  /// 把口语时间规范成 `HH:mm`，无法识别时返回 null。
  ///
  /// 模型（和用户）可能给出各种写法，这里统一收口：
  /// `8:10`、`08:10`、`8：10`（全角冒号）、`8点10分`、`8点`、`8时10分`、`8`。
  /// 秒会被忽略（`08:10:00` → `08:10`）。抽成 public static 便于单测。
  static String? normalizeTime(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    // 中文输入法的全角冒号/数字先转半角，否则正则匹配不到。
    s = s.replaceAll('：', ':');
    s = s.replaceAllMapped(
      RegExp(r'[０-９]'),
      (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFEE0),
    );

    var m = RegExp(r'^(\d{1,2}):(\d{1,2})(?::\d{1,2})?$').firstMatch(s);
    // 8点10分 / 8点 / 8时10分 / 8点10
    m ??= RegExp(r'^(\d{1,2})\s*[点时]\s*(\d{1,2})?\s*分?$').firstMatch(s);
    if (m == null) {
      // 只给了整点：8 / 08
      final h = RegExp(r'^(\d{1,2})$').firstMatch(s);
      final hour = h == null ? null : int.tryParse(h.group(1)!);
      if (hour == null || hour > 23) return null;
      return '${_two(hour)}:00';
    }

    final hour = int.tryParse(m.group(1)!);
    final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (hour == null || hour > 23 || minute > 59) return null;
    return '${_two(hour)}:${_two(minute)}';
  }

  /// 修改某一节作息时间的上下课时间。
  ///
  /// 只改指定节次的 [TimeSlot]，其余节次与方案顺序保持不变；
  /// 落回时用 [BellSchedule.copyWith] + [Timetable.copyWith] 保持纯函数语义。
  (Timetable, OpOutcome) _updatePeriod(Timetable t, AiOp op) {
    final o = _flattened(op);
    final period = o.period;
    if (period == null || period <= 0) {
      return (t, OpOutcome(op: op, applied: false, reason: '缺少要修改的节次（第几节）'));
    }

    final schedule = _resolveSchedule(t, o);
    if (schedule == null) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '找不到作息方案「${o.scheduleName}」'),
      );
    }
    final index = schedule.slots.indexWhere((s) => s.period == period);
    if (index < 0) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '「${schedule.name}」里没有第$period节'),
      );
    }

    final rawStart = o.startTime;
    final rawEnd = o.endTime;
    if (rawStart == null && rawEnd == null) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '没有说明第$period节要改成什么时间'),
      );
    }
    final start = rawStart == null ? null : normalizeTime(rawStart);
    final end = rawEnd == null ? null : normalizeTime(rawEnd);
    if ((rawStart != null && start == null) || (rawEnd != null && end == null)) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '无法识别的时间：${rawStart ?? rawEnd}'),
      );
    }

    final old = schedule.slots[index];
    final newStart = start ?? old.start;
    final newEnd = end ?? old.end;
    if (_minutesOf(newStart) >= _minutesOf(newEnd)) {
      return (
        t,
        OpOutcome(
          op: op,
          applied: false,
          reason: '开始时间必须早于结束时间（$newStart-$newEnd）',
        ),
      );
    }

    final slots = List<TimeSlot>.from(schedule.slots);
    slots[index] = old.copyWith(start: newStart, end: newEnd);
    return (
      _replaceSchedule(t, schedule.copyWith(slots: slots)),
      OpOutcome(
        op: op,
        applied: true,
        detail: '已把「${schedule.name}」第$period节改为 $newStart-$newEnd',
      ),
    );
  }

  /// 整套作息整体平移若干分钟（正数推迟、负数提前）。
  ///
  /// 平移会跨过 00:00（例如 23:50 再推迟 10 分钟）时，整份方案放弃调整：
  /// 只平移一部分节次会让作息自相矛盾，宁可整条操作跳过并说明原因。
  (Timetable, OpOutcome) _shiftSchedule(Timetable t, AiOp op) {
    final o = _flattened(op);
    final minutes = o.shiftMinutes;
    if (minutes == null || minutes == 0) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '缺少要平移的分钟数（如推迟 10 分钟）'),
      );
    }

    final schedule = _resolveSchedule(t, o);
    if (schedule == null) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '找不到作息方案「${o.scheduleName}」'),
      );
    }
    if (schedule.slots.isEmpty) {
      return (
        t,
        OpOutcome(op: op, applied: false, reason: '「${schedule.name}」还没有任何节次时间'),
      );
    }

    // 可选节次范围：「下午的课推迟 10 分钟」只平移下午那几节，不动上午。
    final from = o.fromPeriod;
    final to = o.toPeriod;
    final hasRange = from != null || to != null;
    if (from != null && to != null && from > to) {
      return (
        t,
        OpOutcome(
          op: op,
          applied: false,
          reason: '节次范围不合法（第$from-$to节），已跳过',
        ),
      );
    }
    final targets = hasRange
        ? schedule.slots
            .where((s) =>
                (from == null || s.period >= from) && (to == null || s.period <= to))
            .toList()
        : schedule.slots;
    if (targets.isEmpty) {
      final rangeText = _rangeText(from, to);
      return (
        t,
        OpOutcome(
          op: op,
          applied: false,
          reason: '「${schedule.name}」里没有$rangeText的作息',
        ),
      );
    }
    final targetPeriods = {for (final s in targets) s.period};

    final slots = <TimeSlot>[];
    for (final slot in schedule.slots) {
      if (!hasRange || targetPeriods.contains(slot.period)) {
        final start = _shiftTime(slot.start, minutes);
        final end = _shiftTime(slot.end, minutes);
        if (start == null || end == null) {
          return (
            t,
            OpOutcome(
              op: op,
              applied: false,
              reason: '平移后第${slot.period}节会跨过 00:00，已跳过本次调整',
            ),
          );
        }
        slots.add(slot.copyWith(start: start, end: end));
      } else {
        slots.add(slot);
      }
    }

    final verb = minutes > 0 ? '推迟' : '提前';
    final scope = hasRange ? _rangeText(from, to) : '整体';
    return (
      _replaceSchedule(t, schedule.copyWith(slots: slots)),
      OpOutcome(
        op: op,
        applied: true,
        detail: '已把「${schedule.name}」$scope$verb ${minutes.abs()} 分钟',
      ),
    );
  }

  /// 「第5-8节」「第5节及以后」「第8节及以前」的中文描述。
  static String _rangeText(int? from, int? to) {
    if (from != null && to != null) return '第$from-$to节';
    if (from != null) return '第$from节及以后';
    if (to != null) return '第$to节及以前';
    return '整体';
  }

  /// 找到本次作息操作的目标方案。
  ///
  /// 优先级：模型给出的方案名（先精确、再包含匹配）→ 只有一套作息时就是它
  /// → 当前日期生效的方案（[Timetable.activeSchedule]）。
  /// 指定了方案名却找不到时返回 null，由调用方给出「找不到作息方案」的中文原因。
  BellSchedule? _resolveSchedule(Timetable t, AiOp op) {
    final name = (op.scheduleName ?? '').trim();
    if (name.isNotEmpty) {
      for (final s in t.schedules) {
        if (s.name == name) return s;
      }
      for (final s in t.schedules) {
        if (s.name.contains(name) || name.contains(s.name)) return s;
      }
      return null;
    }
    if (t.schedules.length == 1) return t.schedules.first;
    return t.activeSchedule;
  }

  /// 用改好的方案替换原方案（按 id 匹配，保持列表顺序与其余方案不变）。
  Timetable _replaceSchedule(Timetable t, BellSchedule updated) => t.copyWith(
        schedules: [
          for (final s in t.schedules) s.id == updated.id ? updated : s,
        ],
      );

  /// 把 `patch` / `set` / `to` 子对象平铺到 args 顶层。
  ///
  /// 模型有时把新值写在 `patch` 里（如 `{"period":3,"patch":{"start":"10:05"}}`），
  /// 应用层读的是顶层 getter，因此先做一次无损平铺。
  AiOp _flattened(AiOp op) {
    final patch = op.patchSpec;
    if (patch.isEmpty || identical(patch, op.args)) return op;
    return AiOp(
      kind: op.kind,
      courseName: op.courseName,
      args: <String, dynamic>{...op.args, ...patch},
      summary: op.summary,
    );
  }

  /// `HH:mm` → 当天的分钟数，用于比较先后。
  static int _minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  /// 把 `HH:mm` 平移 [minutes] 分钟；跨过 00:00 时返回 null。
  static String? _shiftTime(String time, int minutes) {
    final norm = normalizeTime(time);
    if (norm == null) return null;
    final parts = norm.split(':');
    final base = DateTime(
      2000,
      1,
      1,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
    final shifted = base.add(Duration(minutes: minutes));
    // DateTime 会顺延到前一天/后一天，这里用日期判断是否跨过了 00:00。
    if (shifted.day != 1) return null;
    return '${_two(shifted.hour)}:${_two(shifted.minute)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 取模型显式给出的「匹配目标」子对象（`match` / `from` / `where` / `filter`）。
  /// 没有显式子对象时返回 null。
  Map<String, dynamic>? _explicitMatch(AiOp op) {
    for (final key in ['match', 'from', 'where', 'filter']) {
      final m = asMap(op.args[key]);
      if (m.isNotEmpty) return m;
    }
    return null;
  }

  /// 只提取「位置类」定位键（星期 / 起始节次），忽略周次等可能表示新值的字段。
  Map<String, dynamic> _positionalCriteria(Map<String, dynamic> args) {
    final out = <String, dynamic>{};
    for (final key in ['dayOfWeek', 'day', 'weekday', 'startPeriod', 'start', 'period']) {
      final v = args[key];
      if (v != null) out[key] = v;
    }
    return out;
  }

  /// 从任意 map 中解析周次条件。
  List<int>? _weeksOf(Map<String, dynamic> m) {
    final raw = m['weeks'];
    if (raw is List) {
      final list = raw
          .map((e) => _asIntOrNull(e))
          .whereType<int>()
          .where((w) => w > 0)
          .toSet()
          .toList()
        ..sort();
      if (list.isNotEmpty) return list;
    }
    final text = pickNonEmpty([
      asString(m['weeks']),
      asString(m['weekRange']),
      asString(m['weekType']),
    ]);
    if (text.isEmpty) return null;
    final parsed = parseWeeks(text);
    return parsed.isEmpty ? null : parsed;
  }

  /// 按 [criteria] 找出目标时段；条件为空时返回该课程的全部时段。
  List<Session> _matchSessions(Course course, Map<String, dynamic> criteria) {
    if (criteria.isEmpty) return course.sessions.toList();

    final day = _asIntOrNull(criteria['dayOfWeek'] ?? criteria['day'] ?? criteria['weekday']);
    final start = _asIntOrNull(criteria['startPeriod'] ?? criteria['start'] ?? criteria['period']);
    final weeks = _weeksOf(criteria);

    // 三个条件都没有时，视为「未指定」，匹配全部
    if (day == null && start == null && (weeks == null || weeks.isEmpty)) {
      return course.sessions.toList();
    }

    return course.sessions.where((s) {
      if (day != null && s.dayOfWeek != day) return false;
      if (start != null && s.startPeriod != start) return false;
      if (weeks != null && weeks.isNotEmpty) {
        if (!s.weeks.any(weeks.contains)) return false;
      }
      return true;
    }).toList();
  }

  Session _toSession(DraftSession d) => Session(
        id: newId(),
        dayOfWeek: d.dayOfWeek,
        startPeriod: d.startPeriod,
        endPeriod: d.endPeriod,
        weeks: d.weeks,
        location: d.location,
        teacher: d.teacher,
      );

  int _nextColorIndex(Timetable t) {
    final used = {for (final c in t.courses) c.colorIndex};
    var i = 0;
    while (used.contains(i)) {
      i++;
    }
    return i;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) {
      final m = RegExp(r'\d+').firstMatch(v);
      if (m != null) return int.tryParse(m.group(0)!);
    }
    return null;
  }
}
