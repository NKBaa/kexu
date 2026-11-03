import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/course.dart';
import '../../data/models/timetable.dart';
import '../editor/course_editor_page.dart';
import '../editor/widgets/week_picker.dart';
import '../timetable/providers/timetable_provider.dart';

/// 批量操作页：多选课程后批量改周次 / 改地点 / 设颜色 / 复制到别的周次 / 删除。
///
/// 为什么需要这一页：大学课表里「第 10 周放假」「一半课程换教室」「前八周单双周
/// 不同」这类需求，逐门编辑会疯掉，所以这里把「筛选 -> 多选 -> 一次改一批」
/// 作为一等公民。所有破坏性操作（删除）必须二次确认。
class BatchOpsPage extends ConsumerStatefulWidget {
  const BatchOpsPage({super.key});

  @override
  ConsumerState<BatchOpsPage> createState() => _BatchOpsPageState();
}

class _BatchOpsPageState extends ConsumerState<BatchOpsPage> {
  final Set<String> _selected = <String>{};

  String _query = '';
  int? _filterDay;
  List<int>? _filterWeeks;
  bool _busy = false;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 数据

  List<Course> _visibleCourses(List<Course> all) {
    final q = _query.trim();
    var list = all.where((c) {
      if (_filterDay != null && !c.sessions.any((s) => s.dayOfWeek == _filterDay)) {
        return false;
      }
      if (_filterWeeks != null && _filterWeeks!.isNotEmpty) {
        final target = _filterWeeks!.toSet();
        if (!c.sessions.any((s) => s.weeks.any(target.contains))) return false;
      }
      if (q.isNotEmpty) {
        final hay = '${c.name} ${c.teacher ?? ''} ${c.courseCode ?? ''}'.toLowerCase();
        if (!hay.contains(q.toLowerCase())) return false;
      }
      return true;
    }).toList();

    // 按「最早的上课时段」排序，接近课表阅读顺序。
    list.sort((a, b) {
      final ka = _sortKey(a);
      final kb = _sortKey(b);
      final cmp = ka.compareTo(kb);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });
    return list;
  }

  static int _sortKey(Course c) {
    if (c.sessions.isEmpty) return 9999;
    var day = 8;
    var period = 99;
    for (final s in c.sessions) {
      if (s.dayOfWeek < day || (s.dayOfWeek == day && s.startPeriod < period)) {
        day = s.dayOfWeek;
        period = s.startPeriod;
      }
    }
    return day * 100 + period;
  }

  List<Course> _selectedCourses(List<Course> all) =>
      all.where((c) => _selected.contains(c.id)).toList();

  // ------------------------------------------------------------------ 工具

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? theme.colorScheme.error : null,
          duration: Duration(seconds: error ? 5 : 3),
        ),
      );
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _selectAllVisible(List<Course> visible) {
    setState(() => _selected.addAll(visible.map((c) => c.id)));
  }

  void _clearSelection() => setState(_selected.clear);

  void _invertVisible(List<Course> visible) {
    setState(() {
      for (final c in visible) {
        if (!_selected.remove(c.id)) _selected.add(c.id);
      }
    });
  }

  /// 统一执行批量写操作：包住异常、忙碌态与结果提示。
  Future<void> _run(
    String successMessage,
    Future<void> Function() action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _toast(successMessage);
    } catch (e) {
      _toast('操作失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------- 批量改周次

  Future<void> _batchEditWeeks(List<Course> courses) async {
    final targets = _selectedCourses(courses);
    if (targets.isEmpty) return;
    final table = ref.read(timetableProvider).valueOrNull;
    final totalWeeks = table?.semester.totalWeeks ?? 16;

    // 默认值：选中课程里出现过的周次并集（让用户看到现状）。
    final union = <int>{};
    for (final c in targets) {
      for (final s in c.sessions) {
        union.addAll(s.weeks);
      }
    }
    final initial = union.toList()..sort();

    final result = await showDialog<_WeekEditResult>(
      context: context,
      builder: (ctx) => _BatchWeekDialog(
        totalWeeks: totalWeeks,
        initialWeeks: initial,
      ),
    );
    if (result == null || !mounted) return;

    if (result.weeks.isEmpty) {
      _toast('请至少选择一个周次', error: true);
      return;
    }

    var changedCourses = 0;
    var changedSessions = 0;
    final updated = <Course>[];
    for (final c in targets) {
      final newSessions = <Session>[];
      var touched = false;
      for (final s in c.sessions) {
        final nextWeeks = _applyWeekMode(s.weeks, result);
        final same = const ListEquality<int>().equals(nextWeeks, s.weeks);
        if (same) {
          newSessions.add(s);
        } else {
          touched = true;
          changedSessions++;
          newSessions.add(s.copyWith(weeks: nextWeeks));
        }
      }
      if (touched) {
        changedCourses++;
        updated.add(c.copyWith(sessions: newSessions));
      }
    }

    if (updated.isEmpty) {
      _toast('周次没有变化（所选模式下所有时段都不受影响）');
      return;
    }

    await _run(
      '已更新 $changedCourses 门课程、$changedSessions 个时段的周次',
      () => ref.read(timetableProvider.notifier).updateCourses(updated),
    );
  }

  List<int> _applyWeekMode(List<int> current, _WeekEditResult r) {
    final target = r.weeks.toSet();
    final cur = current.toSet();
    final Set<int> out;
    switch (r.mode) {
      case _WeekMode.set:
        out = {...target};
      case _WeekMode.union:
        out = {...cur, ...target};
      case _WeekMode.intersect:
        out = cur.intersection(target);
      case _WeekMode.remove:
        out = cur.difference(target);
    }
    final list = out.toList()..sort();
    return list;
  }

  // ------------------------------------------------------------- 批量改地点

  Future<void> _batchEditLocation(List<Course> courses) async {
    final targets = _selectedCourses(courses);
    if (targets.isEmpty) return;
    final result = await showDialog<_LocationEditResult>(
      context: context,
      builder: (ctx) => _BatchLocationDialog(
        currentLocations: {
          for (final c in targets)
            for (final s in c.sessions)
              if ((s.location ?? '').isNotEmpty) s.location!,
        }.toList(),
      ),
    );
    if (result == null || !mounted) return;

    var changedSessions = 0;
    final updated = <Course>[];
    for (final c in targets) {
      final newSessions = <Session>[];
      var touched = false;
      for (final s in c.sessions) {
        final newLoc = result.clear ? null : result.location;
        final oldLoc = s.location;
        final same = (newLoc ?? '') == (oldLoc ?? '');
        if (same) {
          newSessions.add(s);
        } else {
          touched = true;
          changedSessions++;
          newSessions.add(
            s.copyWith(location: newLoc, clearLocation: newLoc == null),
          );
        }
      }
      if (touched) updated.add(c.copyWith(sessions: newSessions));
    }

    if (updated.isEmpty) {
      _toast('地点没有变化');
      return;
    }
    await _run(
      result.clear
          ? '已清空 $changedSessions 个时段的地点'
          : '已把 $changedSessions 个时段的地点改为「${result.location}」',
      () => ref.read(timetableProvider.notifier).updateCourses(updated),
    );
  }

  // ------------------------------------------------------------- 批量设颜色

  Future<void> _batchSetColor(List<Course> courses) async {
    final targets = _selectedCourses(courses);
    if (targets.isEmpty) return;
    final index = await showDialog<int>(
      context: context,
      builder: (ctx) => const _ColorPickerDialog(),
    );
    if (index == null || !mounted) return;

    final updated = [
      for (final c in targets)
        if (c.colorIndex != index) c.copyWith(colorIndex: index),
    ];
    if (updated.isEmpty) {
      _toast('颜色没有变化');
      return;
    }
    await _run(
      '已把 ${updated.length} 门课程的颜色改为第 ${index + 1} 号色',
      () => ref.read(timetableProvider.notifier).updateCourses(updated),
    );
  }

  // --------------------------------------------------------- 复制到周次范围

  Future<void> _copyToWeekRange(List<Course> courses) async {
    final targets = _selectedCourses(courses);
    if (targets.isEmpty) return;
    final table = ref.read(timetableProvider).valueOrNull;
    final totalWeeks = table?.semester.totalWeeks ?? 16;

    final union = <int>{};
    for (final c in targets) {
      for (final s in c.sessions) {
        union.addAll(s.weeks);
      }
    }
    final source = union.toList()..sort();

    final result = await showDialog<_CopyWeekResult>(
      context: context,
      builder: (ctx) => _CopyWeekDialog(
        totalWeeks: totalWeeks,
        sourceWeeks: source,
      ),
    );
    if (result == null || !mounted) return;
    if (result.targetWeeks.isEmpty) {
      _toast('请先选择目标周次', error: true);
      return;
    }

    final sourceSet = result.sourceWeeks.toSet();
    var addedSessions = 0;
    var movedSessions = 0;
    final updated = <Course>[];

    for (final c in targets) {
      final newSessions = <Session>[];
      var touched = false;
      for (final s in c.sessions) {
        // 只处理与「源周次」有交集的时段；源周次为空时视为全部。
        final covered = sourceSet.isEmpty || s.weeks.any(sourceSet.contains);
        if (!covered) {
          newSessions.add(s);
          continue;
        }
        if (result.move) {
          // 移动：把源周次替换成目标周次，保留其余周次。
          final next = <int>{
            ...s.weeks.where((w) => !sourceSet.contains(w)),
            ...result.targetWeeks,
          }.toList()
            ..sort();
          if (const ListEquality<int>().equals(next, s.weeks)) {
            newSessions.add(s);
          } else {
            touched = true;
            movedSessions++;
            newSessions.add(s.copyWith(weeks: next));
          }
        } else {
          // 复制：原有周次保留，另外新增一个只有目标周次的时段。
          newSessions.add(s);
          final dupWeeks = result.targetWeeks.toSet().toList()..sort();
          final exists = newSessions.any(
            (x) =>
                x.dayOfWeek == s.dayOfWeek &&
                x.startPeriod == s.startPeriod &&
                x.endPeriod == s.endPeriod &&
                const ListEquality<int>().equals(x.weeks, dupWeeks),
          );
          if (!exists) {
            touched = true;
            addedSessions++;
            newSessions.add(
              Session(
                id: newId(),
                dayOfWeek: s.dayOfWeek,
                startPeriod: s.startPeriod,
                endPeriod: s.endPeriod,
                weeks: dupWeeks,
                location: s.location,
                teacher: s.teacher,
              ),
            );
          }
        }
      }
      if (touched) updated.add(c.copyWith(sessions: newSessions));
    }

    if (updated.isEmpty) {
      _toast('没有可调整的时段');
      return;
    }

    final msg = result.move
        ? '已把 $movedSessions 个时段的周次移到 ${formatWeeks(result.targetWeeks)}'
        : '已新增 $addedSessions 个时段（周次 ${formatWeeks(result.targetWeeks)}）';
    await _run(msg, () => ref.read(timetableProvider.notifier).updateCourses(updated));
  }

  // ---------------------------------------------------------------- 批量删除

  Future<void> _batchDelete(List<Course> courses) async {
    final targets = _selectedCourses(courses);
    if (targets.isEmpty) return;
    final names = targets.take(4).map((c) => '「${c.name}」').join('、');
    final more = targets.length > 4 ? ' 等 ${targets.length} 门课程' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Theme.of(ctx).colorScheme.error),
        title: const Text('确认批量删除？'),
        content: Text('将删除 $names$more，共 ${targets.length} 门课程及其全部时段。\n\n此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('删除 ${targets.length} 门'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final ids = targets.map((c) => c.id).toSet();
    await _run(
      '已删除 ${ids.length} 门课程',
      () => ref.read(timetableProvider.notifier).deleteCourses(ids),
    );
    if (mounted) setState(() => _selected.removeAll(ids));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final asyncTimetable = ref.watch(timetableProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: asyncTimetable.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => _ErrorView(
            message: '读取课表失败：$e',
            onRetry: () => ref.invalidate(timetableProvider),
          ),
          data: (timetable) => Column(
            children: [
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _buildBody(context, timetable)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: asyncTimetable.maybeWhen(
        data: (timetable) => _buildActionBar(context, timetable.courses),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Timetable timetable) {
    final all = timetable.courses;
    final visible = _visibleCourses(all);
    final selectedCount = all.where((c) => _selected.contains(c.id)).length;

    return Column(
      children: [
        _buildFilterBar(context, all, visible, selectedCount),
        Expanded(
          child: all.isEmpty
              ? _EmptyView(
                  title: '还没有任何课程',
                  detail: '先去「新增课程」录入几门课，再回来批量调整。',
                )
              : visible.isEmpty
                  ? _EmptyView(
                      title: '当前筛选没有匹配的课程',
                      detail: '试试把筛选条件放宽，或点右上角重置。',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                      itemBuilder: (context, i) => _buildCourseTile(context, visible[i]),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    List<Course> all,
    List<Course> visible,
    int selectedCount,
  ) {
    final theme = Theme.of(context);
    final allSelected = visible.isNotEmpty && visible.every((c) => _selected.contains(c.id));
    final compact = MediaQuery.sizeOf(context).width < 480;

    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: compact ? '搜索课程' : '搜索课程名 / 教师 / 编号',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 132 : 220),
                  child: OutlinedButton.icon(
                    key: const Key('batch_filter_button'),
                    onPressed: () => _showFilterSheet(context),
                    icon: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: Text(
                      _filterSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已选 $selectedCount 门 / 显示 ${visible.length} 门 / 共 ${all.length} 门',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: visible.isEmpty ? null : () => _selectAllVisible(visible),
                  child: Text(allSelected ? '已全选' : '全选'),
                ),
                TextButton(
                  onPressed: visible.isEmpty ? null : () => _invertVisible(visible),
                  child: const Text('反选'),
                ),
                if (selectedCount > 0)
                  TextButton(
                    onPressed: _clearSelection,
                    child: const Text('清空'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _filterSummary {
    final parts = <String>[
      if (_filterDay != null) weekdayName(_filterDay!),
      if (_filterWeeks != null) formatWeeks(_filterWeeks!),
    ];
    return parts.isEmpty ? '筛选' : parts.join(' · ');
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void sync(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          final table = ref.read(timetableProvider).valueOrNull;
          final totalWeeks = table?.semester.totalWeeks ?? 16;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '筛选课程',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        key: const Key('batch_clear_filters'),
                        onPressed: () => sync(() {
                          _filterDay = null;
                          _filterWeeks = null;
                        }),
                        child: const Text('取消筛选'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('星期', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('全部星期'),
                        selected: _filterDay == null,
                        onSelected: (_) => sync(() => _filterDay = null),
                      ),
                      for (var d = 1; d <= 7; d++)
                        ChoiceChip(
                          label: Text(weekdayName(d)),
                          selected: _filterDay == d,
                          onSelected: (_) => sync(() => _filterDay = d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('周次', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const Key('batch_week_filter'),
                      onPressed: () async {
                        final result = await showDialog<List<int>>(
                          context: context,
                          builder: (ctx) => _WeekFilterDialog(
                            totalWeeks: totalWeeks,
                            initial: _filterWeeks ?? const [],
                          ),
                        );
                        if (result == null || !mounted) return;
                        sync(() => _filterWeeks = result.isEmpty ? null : result);
                      },
                      icon: const Icon(Icons.date_range_outlined, size: 18),
                      label: Text(
                        _filterWeeks == null ? '全部周次' : formatWeeks(_filterWeeks!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCourseTile(BuildContext context, Course course) {
    final theme = Theme.of(context);
    final selected = _selected.contains(course.id);
    final color = CoursePalette.of(course.colorIndex);
    return CheckboxListTile(
      value: selected,
      onChanged: (_) => _toggle(course.id),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: onLongPressMenu(context, course),
      title: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Text(
              course.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (course.credit != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '${_fmtCredit(course.credit!)}分',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          course.sessions.isEmpty
              ? '暂无时段'
              : course.sessions.map((s) => s.describe()).join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static String _fmtCredit(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// 单门课程的快捷操作（长按/右侧菜单）。
  Widget onLongPressMenu(BuildContext context, Course course) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (v) async {
        switch (v) {
          case 'only':
            setState(() {
              _selected
                ..clear()
                ..add(course.id);
            });
          case 'select':
            _toggle(course.id);
          case 'edit':
            await _openEditor(course);
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'select', child: Text('选中/取消')),
        const PopupMenuItem(value: 'only', child: Text('只选这一门')),
        const PopupMenuItem(value: 'edit', child: Text('单独编辑')),
      ],
    );
  }

  Future<void> _openEditor(Course course) async {
    if (!mounted) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => CourseEditorPage(course: course),
      ),
    );
    if (result == true && mounted) _toast('已保存');
  }

  Widget _buildActionBar(BuildContext context, List<Course> all) {
    final theme = Theme.of(context);
    final count = all.where((c) => _selected.contains(c.id)).length;
    final enabled = count > 0 && !_busy;

    return SafeArea(
      child: Material(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    count == 0 ? Icons.check_box_outline_blank : Icons.check_box,
                    size: 16,
                    color: count == 0
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    count == 0 ? '请先选择课程（可全选或按条件筛选后全选）' : '已选 $count 门课程',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: count == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary,
                      fontWeight: count == 0 ? null : FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _actionButton(
                      icon: Icons.date_range_outlined,
                      label: '改周次',
                      onPressed: enabled ? () => _batchEditWeeks(all) : null,
                    ),
                    _actionButton(
                      icon: Icons.place_outlined,
                      label: '改地点',
                      onPressed: enabled ? () => _batchEditLocation(all) : null,
                    ),
                    _actionButton(
                      icon: Icons.palette_outlined,
                      label: '设颜色',
                      onPressed: enabled ? () => _batchSetColor(all) : null,
                    ),
                    _actionButton(
                      icon: Icons.copy_all_outlined,
                      label: '复制到周次',
                      onPressed: enabled ? () => _copyToWeekRange(all) : null,
                    ),
                    _actionButton(
                      icon: Icons.delete_outline,
                      label: '删除',
                      danger: true,
                      onPressed: enabled ? () => _batchDelete(all) : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          side: color == null ? null : BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

/// 简单的 List 相等比较（避免引入 collection 包的额外依赖）。
class ListEquality<T> {
  const ListEquality();

  bool equals(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ------------------------------------------------------------------ 对话框

enum _WeekMode { set, union, intersect, remove }

class _WeekEditResult {
  const _WeekEditResult(this.mode, this.weeks);
  final _WeekMode mode;
  final List<int> weeks;
}

class _BatchWeekDialog extends StatefulWidget {
  const _BatchWeekDialog({required this.totalWeeks, required this.initialWeeks});

  final int totalWeeks;
  final List<int> initialWeeks;

  @override
  State<_BatchWeekDialog> createState() => _BatchWeekDialogState();
}

class _BatchWeekDialogState extends State<_BatchWeekDialog> {
  late List<int> _weeks;
  _WeekMode _mode = _WeekMode.set;

  @override
  void initState() {
    super.initState();
    _weeks = [...widget.initialWeeks];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('批量修改周次'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('对选中课程的所有时段生效。', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              SegmentedButton<_WeekMode>(
                segments: const [
                  ButtonSegment(value: _WeekMode.set, label: Text('替换'), icon: Icon(Icons.swap_horiz, size: 14)),
                  ButtonSegment(value: _WeekMode.union, label: Text('追加'), icon: Icon(Icons.add, size: 14)),
                  ButtonSegment(value: _WeekMode.intersect, label: Text('取交集'), icon: Icon(Icons.join_inner, size: 14)),
                  ButtonSegment(value: _WeekMode.remove, label: Text('排除'), icon: Icon(Icons.remove_circle_outline, size: 14)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 6),
              Text(
                _modeHint(_mode),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              WeekPicker(
                totalWeeks: widget.totalWeeks,
                selectedWeeks: _weeks,
                onChanged: (v) => setState(() => _weeks = v),
                label: '周次',
                dense: true,
                maxGridHeight: 150,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_WeekEditResult(_mode, _weeks)),
          child: const Text('应用'),
        ),
      ],
    );
  }

  static String _modeHint(_WeekMode m) {
    switch (m) {
      case _WeekMode.set:
        return '替换：所有时段的周次都改成下面所选（适合「整门课只上前 8 周」）。';
      case _WeekMode.union:
        return '追加：把下面所选周次并入原周次（适合「第 17 周补课」）。';
      case _WeekMode.intersect:
        return '取交集：只保留与原周次重叠的部分（适合「只留前 8 周」）。';
      case _WeekMode.remove:
        return '排除：从原周次里去掉下面所选的周（适合「第 10 周放假」）。';
    }
  }
}

class _LocationEditResult {
  const _LocationEditResult({required this.location, required this.clear});
  final String location;
  final bool clear;
}

class _BatchLocationDialog extends StatefulWidget {
  const _BatchLocationDialog({required this.currentLocations});

  final List<String> currentLocations;

  @override
  State<_BatchLocationDialog> createState() => _BatchLocationDialogState();
}

class _BatchLocationDialogState extends State<_BatchLocationDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _clear = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = widget.currentLocations.where((e) => e.trim().isNotEmpty).toSet().take(8).toList();
    return AlertDialog(
      title: const Text('批量修改地点'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('对选中课程的所有时段生效。', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              enabled: !_clear,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_clear) {
                  Navigator.of(context).pop(
                    _LocationEditResult(location: _ctrl.text.trim(), clear: false),
                  );
                }
              },
              decoration: const InputDecoration(
                isDense: true,
                labelText: '新地点',
                hintText: '如 A101 / 线上',
                prefixIcon: Icon(Icons.place_outlined, size: 18),
              ),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final loc in recent)
                    ActionChip(
                      label: Text(loc, style: const TextStyle(fontSize: 12)),
                      onPressed: _clear
                          ? null
                          : () => setState(() => _ctrl.text = loc),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _clear,
              onChanged: (v) => setState(() => _clear = v),
              title: const Text('清空地点'),
              subtitle: const Text('把选中课程所有时段的地点置空', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _LocationEditResult(location: _ctrl.text.trim(), clear: _clear),
          ),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('批量设置颜色'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选中课程会统一换成该颜色。', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < CoursePalette.colors.length; i++)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(i),
                    borderRadius: BorderRadius.circular(999),
                    child: Tooltip(
                      message: '颜色 ${i + 1}',
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: CoursePalette.of(i),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      ],
    );
  }
}

class _CopyWeekResult {
  const _CopyWeekResult({
    required this.sourceWeeks,
    required this.targetWeeks,
    required this.move,
  });

  final List<int> sourceWeeks;
  final List<int> targetWeeks;
  final bool move;
}

class _CopyWeekDialog extends StatefulWidget {
  const _CopyWeekDialog({required this.totalWeeks, required this.sourceWeeks});

  final int totalWeeks;
  final List<int> sourceWeeks;

  @override
  State<_CopyWeekDialog> createState() => _CopyWeekDialogState();
}

class _CopyWeekDialogState extends State<_CopyWeekDialog> {
  late List<int> _source;
  List<int> _target = [];
  bool _move = false;

  @override
  void initState() {
    super.initState();
    _source = [...widget.sourceWeeks];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('复制 / 移动到另一个周次范围'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _move,
                onChanged: (v) => setState(() => _move = v),
                title: Text(_move ? '移动：把源周次改成目标周次' : '复制：保留原时段，另加目标周次的时段'),
                subtitle: Text(
                  _move
                      ? '原周次会被移除，目标周次生效（适合学期整体顺延一周）。'
                      : '原周次不变，额外新增一份目标周次的时段（适合补课/二轮课）。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const Divider(),
              WeekPicker(
                totalWeeks: widget.totalWeeks,
                selectedWeeks: _source,
                onChanged: (v) => setState(() => _source = v),
                label: '源周次',
                helperText: '留空 = 所有时段',
                dense: true,
                maxGridHeight: 120,
              ),
              const Divider(),
              WeekPicker(
                totalWeeks: widget.totalWeeks,
                selectedWeeks: _target,
                onChanged: (v) => setState(() => _target = v),
                label: '目标周次',
                helperText: '必选',
                dense: true,
                maxGridHeight: 120,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: _target.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _CopyWeekResult(
                      sourceWeeks: _source,
                      targetWeeks: _target,
                      move: _move,
                    ),
                  ),
          child: Text(_move ? '移动' : '复制'),
        ),
      ],
    );
  }
}

class _WeekFilterDialog extends StatefulWidget {
  const _WeekFilterDialog({required this.totalWeeks, required this.initial});

  final int totalWeeks;
  final List<int> initial;

  @override
  State<_WeekFilterDialog> createState() => _WeekFilterDialogState();
}

class _WeekFilterDialogState extends State<_WeekFilterDialog> {
  late List<int> _weeks;

  @override
  void initState() {
    super.initState();
    _weeks = [...widget.initial];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('按周次筛选课程'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '只显示在这些周次里「有课」的课程。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            WeekPicker(
              totalWeeks: widget.totalWeeks,
              selectedWeeks: _weeks,
              onChanged: (v) => setState(() => _weeks = v),
              label: '周次',
              dense: true,
              maxGridHeight: 150,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(<int>[]),
          child: const Text('清除筛选'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_weeks),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ 小组件

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}