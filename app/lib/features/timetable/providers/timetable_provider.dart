import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/week_utils.dart';
import '../../../data/models/bell_schedule.dart';
import '../../../data/models/course.dart';
import '../../../data/models/semester.dart';
import '../../../data/models/timetable.dart';
import '../../../data/repositories/timetable_history_repository.dart';
import '../../../data/repositories/timetable_repository.dart';

/// 课表仓储实例（测试时可 override 注入内存实现）。
final timetableRepositoryProvider = Provider<TimetableRepository>((ref) {
  return TimetableRepository();
});

/// 课表修改历史仓储（最近 20 次快照）。
final timetableHistoryRepositoryProvider =
    Provider<TimetableHistoryRepository>((ref) {
  return TimetableHistoryRepository();
});

/// 当前课表。UI 通过 `ref.watch(timetableProvider)` 读取。
final timetableProvider =
    AsyncNotifierProvider<TimetableController, Timetable>(TimetableController.new);

/// 课表状态控制器。
///
/// 所有写操作都遵循同一套模式：**先更新内存状态让 UI 立即响应，再异步落盘**。
/// 这样批量操作与 AI 批量修改在 UI 上都是「瞬间生效」，不会卡顿。
class TimetableController extends AsyncNotifier<Timetable> {
  TimetableRepository get _repo => ref.read(timetableRepositoryProvider);

  TimetableHistoryRepository get _history =>
      ref.read(timetableHistoryRepositoryProvider);

  /// 最近一次落盘失败的原因（为 null 表示一切正常）。
  ///
  /// 落盘失败时我们**保留内存中的改动**让用户继续操作，同时把原因暴露出来，
  /// 由设置页提示「改动未能保存」。这样比直接抛异常让界面崩掉更有用。
  String? lastPersistError;

  /// 撤销后的重做栈（只保存在内存，和 Word 的 redo 类似）。
  final List<_RedoEntry> _redoStack = <_RedoEntry>[];

  bool get canRedo => _redoStack.isNotEmpty;

  /// 下一次重做的说明（用于按钮 tooltip / 提示）。
  String? get redoDescription =>
      _redoStack.isEmpty ? null : _redoStack.last.description;

  /// 下一次撤销的说明；没有历史时返回 null。
  Future<String?> nextUndoDescription() async {
    final entries = await _history.load();
    return entries.isEmpty ? null : entries.last.description;
  }

  @override
  Future<Timetable> build() async {
    return _repo.load();
  }

  /// 用新的课表整体替换（导入、AI 批量应用等场景）。
  ///
  /// 默认会把「修改前的课表」记入历史（最近 20 次），供顶栏「回退」使用；
  /// [recordHistory] 为 false 时用于回退本身，避免回退动作又产生新历史。
  /// [description] 可传入更准确的修改说明；不传则自动比较前后课表生成。
  Future<void> replaceTimetable(
    Timetable next, {
    bool recordHistory = true,
    String? description,
  }) async {
    final previous = state.valueOrNull;
    state = AsyncData(next);
    // 新的编辑动作会截断 redo 时间线（与 Word 一致）。
    if (recordHistory) _redoStack.clear();
    if (recordHistory &&
        previous != null &&
        !TimetableHistoryRepository.sameTimetable(previous, next)) {
      try {
        await _history.push(
          previous,
          next: next,
          description: description ?? _describeChange(previous, next),
        );
      } catch (e) {
        // 历史记录失败不能影响课表保存
        debugPrint('记录课表修改历史失败：$e');
      }
    }
    try {
      await _repo.save(next);
      lastPersistError = null;
    } catch (e) {
      lastPersistError = '$e';
      debugPrint('课表保存失败（改动仍保留在内存中）：$e');
    }
  }

  /// 自动生成一句修改说明，供撤销/重做 tooltip 与提示使用。
  String _describeChange(Timetable previous, Timetable next) {
    if (jsonEncode(previous.semester.toJson()) !=
        jsonEncode(next.semester.toJson())) {
      return '修改学期设置';
    }
    if (jsonEncode(previous.schedules.map((s) => s.toJson()).toList()) !=
        jsonEncode(next.schedules.map((s) => s.toJson()).toList())) {
      return '修改作息时间';
    }

    final before = {for (final c in previous.courses) c.id: c};
    final after = {for (final c in next.courses) c.id: c};
    final added = [
      for (final c in next.courses)
        if (!before.containsKey(c.id)) c,
    ];
    final removed = [
      for (final c in previous.courses)
        if (!after.containsKey(c.id)) c,
    ];
    final updated = [
      for (final c in next.courses)
        if (before.containsKey(c.id) &&
            jsonEncode(before[c.id]!.toJson()) != jsonEncode(c.toJson()))
          c,
    ];
    final parts = <String>[
      if (added.isNotEmpty) '添加课程${_courseNames(added)}',
      if (removed.isNotEmpty) '删除课程${_courseNames(removed)}',
      if (updated.isNotEmpty) '修改课程${_courseNames(updated)}',
    ];
    return parts.isEmpty ? '修改课表' : parts.join('；');
  }

  String _courseNames(List<Course> courses) {
    final names = courses.take(2).map((c) => '「${c.name}」').join('、');
    return courses.length > 2 ? '$names 等 ${courses.length} 门' : names;
  }

  /// 撤销最近一次修改；没有历史或历史文件不可用时返回 false。
  Future<bool> undoLatestChange() async {
    try {
      final current = state.valueOrNull;
      final entry = await _history.undoLatest();
      if (entry == null) return false;
      if (current != null) {
        _redoStack.add(
          _RedoEntry(
            timetable: current,
            description: entry.description.isEmpty
                ? _describeChange(entry.timetable, current)
                : entry.description,
          ),
        );
        while (_redoStack.length > TimetableHistoryRepository.defaultMaxEntries) {
          _redoStack.removeAt(0);
        }
      }
      await replaceTimetable(entry.timetable, recordHistory: false);
      return true;
    } catch (e) {
      // 历史文件不可写等异常不应让界面崩溃，按「回退失败」处理。
      debugPrint('回退课表失败：$e');
      return false;
    }
  }

  /// 重做上一次撤销；没有 redo 时返回 false。
  Future<bool> redoLastChange() async {
    if (_redoStack.isEmpty) return false;
    try {
      final redo = _redoStack.removeLast();
      final current = state.valueOrNull;
      if (current != null) {
        // 把当前状态重新记入历史，撤销这次重做后还能再撤销回来。
        try {
          await _history.push(
            current,
            next: redo.timetable,
            description: redo.description,
          );
        } catch (e) {
          debugPrint('记录重做历史失败：$e');
        }
      }
      await replaceTimetable(redo.timetable, recordHistory: false);
      return true;
    } catch (e) {
      debugPrint('重做课表失败：$e');
      return false;
    }
  }

  /// 批量新增课程。
  Future<void> addCourses(List<Course> courses) async {
    if (courses.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(courses: [...current.courses, ...courses]);
    await replaceTimetable(next);
  }

  /// 更新单门课程（按 id 覆盖）。
  Future<void> updateCourse(Course course) => updateCourses([course]);

  /// 批量更新课程（按 id 覆盖）。
  Future<void> updateCourses(List<Course> courses) async {
    if (courses.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final byId = {for (final c in courses) c.id: c};
    final next = current.copyWith(
      courses: current.courses.map((c) => byId[c.id] ?? c).toList(),
    );
    await replaceTimetable(next);
  }

  /// 批量删除课程。
  Future<void> deleteCourses(Set<String> ids) async {
    if (ids.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final next = current.copyWith(
      courses: current.courses.where((c) => !ids.contains(c.id)).toList(),
    );
    await replaceTimetable(next);
  }

  /// 更新学期设置（改名/改开学日期/改总周数）。
  Future<void> setSemester(Semester semester) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await replaceTimetable(current.copyWith(semester: semester));
  }

  /// 整体替换作息方案列表（多套作息的核心写入接口）。
  Future<void> setSchedules(List<BellSchedule> schedules) async {
    final current = state.valueOrNull;
    if (current == null) return;
    await replaceTimetable(current.copyWith(schedules: schedules));
  }

  /// 新增或更新一套作息方案（按 id 匹配）。
  Future<void> upsertSchedule(BellSchedule schedule) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final list = <BellSchedule>[
      for (final s in current.schedules) s.id == schedule.id ? schedule : s,
    ];
    // 没匹配到就是新增
    if (!list.any((s) => s.id == schedule.id)) list.add(schedule);
    await setSchedules(list);
  }

  /// 删除一套作息方案。至少要保留一套，否则课表没有作息可用。
  Future<void> deleteSchedule(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.schedules.length <= 1) return;
    await setSchedules(
      current.schedules.where((s) => s.id != id).toList(),
    );
  }
}

/// redo 栈里的一项：要恢复的课表 + 这次撤销对应的操作说明。
class _RedoEntry {
  const _RedoEntry({required this.timetable, required this.description});

  final Timetable timetable;
  final String description;
}

/// 当前展示的周次（1-based）。
final currentWeekProvider =
    NotifierProvider<CurrentWeekController, int>(CurrentWeekController.new);

class CurrentWeekController extends Notifier<int> {
  @override
  int build() => 1;

  void setWeek(int week) {
    final total = ref.read(timetableProvider).valueOrNull?.semester.totalWeeks ?? 16;
    final clamped = week.clamp(1, total < 1 ? 1 : total);
    if (clamped != state) state = clamped;
  }

  void next() => setWeek(state + 1);

  void previous() => setWeek(state - 1);
}

/// 今天所处的教学周（不在学期内时返回 0）。
///
/// **读取系统时间**（`DateTime.now()`）确定当前日期，换算成教学周。
///
/// 这里必须复用 [weekOfDate] 而不是自己算：
/// 自己用 `today.difference(start).inDays ~/ 7 + 1` 时，
/// 若学期起始日不是周一（例如周日/周三开学），会**少算一周** ——
/// 因为 `difference` 没有把起始日归一到所在周的周一。
final academicWeekProvider = Provider<int>((ref) {
  final t = ref.watch(timetableProvider).valueOrNull;
  if (t == null) return 0;

  // 系统时间 → 当期日期
  final now = DateTime.now();
  final week = weekOfDate(now, t.semester.startMonday);

  if (week < 1 || week > t.semester.totalWeeks) return 0;
  return week;
});

/// 下一次撤销的说明；null 表示没有可撤销内容。
final undoDescriptionProvider = FutureProvider.autoDispose<String?>((ref) async {
  ref.watch(timetableProvider);
  return ref.read(timetableProvider.notifier).nextUndoDescription();
});

/// 下一次重做的说明；null 表示没有可重做内容。
final redoDescriptionProvider = Provider<String?>((ref) {
  ref.watch(timetableProvider);
  return ref.read(timetableProvider.notifier).redoDescription;
});
