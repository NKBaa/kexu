import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunar/lunar.dart';

import '../../core/coloros_theme.dart';
import '../../core/utils/week_utils.dart';
import '../../core/widgets/app_notice.dart';
import '../../data/models/schedule_event.dart';
import '../ai/ai_edit_page.dart';
import '../timetable/providers/timetable_provider.dart';
import 'providers/schedule_events_provider.dart';
import 'schedule_event_editor_page.dart';

/// 日程页：ColorOS 16 风格的月历 + 当天事项。
///
/// 月历支持左右滑动切月、上下拖动/点箭头在「整月」和「单周」之间收缩，
/// 下方展示选中日期的相对天数、农历与当天日程。
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  static const int _firstYear = 2000;
  static const int _monthCount = 2400;
  static const double _collapsedHeight = 52;
  static const double _expandedHeight = 52 * 6;

  late DateTime _month;
  late DateTime _selected;
  late final PageController _pageController;
  bool _expanded = true;
  bool _dragging = false;
  double _calendarHeight = _expandedHeight;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    _pageController = PageController(initialPage: _indexOf(_month));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _indexOf(DateTime date) =>
      (date.year - _firstYear) * 12 + date.month - 1;

  DateTime _monthAt(int index) =>
      DateTime(_firstYear + index ~/ 12, index % 12 + 1);

  void _onPageChanged(int index) {
    final month = _monthAt(index);
    final days = DateTime(month.year, month.month + 1, 0).day;
    setState(() {
      _month = month;
      _selected = DateTime(
        month.year,
        month.month,
        _selected.day.clamp(1, days),
      );
    });
  }

  void _changeMonth(int delta) {
    final next = _indexOf(_month) + delta;
    if (next < 0 || next >= _monthCount) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToday() {
    final now = DateTime.now();
    final index = _indexOf(now);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    setState(() {
      _month = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
  }

  Future<void> _openEditor({ScheduleEvent? event}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ScheduleEventEditorPage(
          initialDate: _selected,
          initial: event,
        ),
      ),
    );
    if (changed == true && mounted) {
      showAppNotice(context, event == null ? '日程已添加' : '日程已更新');
    }
  }

  Future<void> _openAi() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AiEditPage()),
    );
  }

  Future<void> _mergeDuplicates(List<ScheduleEvent> events) async {
    final seen = <String>{};
    final duplicates = <ScheduleEvent>[];
    for (final event in events) {
      final key = '${event.dateKey}|${event.title}|${event.startTime ?? ''}';
      if (seen.add(key)) continue;
      duplicates.add(event);
    }
    if (duplicates.isEmpty) return;
    for (final event in duplicates) {
      await ref.read(scheduleEventsProvider.notifier).remove(event.id);
    }
    if (mounted) showAppNotice(context, '已合并 ${duplicates.length} 条重复日程');
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorOsPalette.of(context);
    final async = ref.watch(scheduleEventsProvider);
    final timetable = ref.watch(timetableProvider).valueOrNull;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => Center(
            child: CircularProgressIndicator(color: palette.accent),
          ),
          error: (e, st) => Center(
            child: Text(
              '读取日程失败：$e',
              style: TextStyle(color: palette.secondary),
            ),
          ),
          data: (events) => _buildBody(palette, events, timetable),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('schedule_add_button'),
        heroTag: 'schedule_add_fab',
        onPressed: () => _openEditor(),
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Widget _buildBody(
    ColorOsPalette palette,
    List<ScheduleEvent> events,
    dynamic timetable,
  ) {
    final week = timetable == null
        ? null
        : weekOfDate(_selected, timetable.semester.startMonday);
    final duplicates = _duplicateCount(events);
    return ListView(
      key: const Key('schedule_list'),
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _buildHeader(palette, week, duplicates > 0),
        const SizedBox(height: 4),
        _buildCalendar(palette, events),
        const SizedBox(height: 6),
        _buildDaySummary(palette),
        if (duplicates > 0) ...[
          const SizedBox(height: 10),
          _buildDuplicateBanner(palette, duplicates, events),
        ],
        const SizedBox(height: 18),
        _buildDayEvents(palette, events),
      ],
    );
  }

  Widget _buildHeader(ColorOsPalette palette, int? week, bool hasDuplicates) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 4),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.chevron_left,
            tooltip: '上个月',
            onTap: () => _changeMonth(-1),
            palette: palette,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        '${_month.year}年${_month.month}月',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    if (week != null && week > 0) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '第 $week 周',
                          style: TextStyle(
                            color: palette.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_selected.month}月${_selected.day}日 · ${weekdayName(_selected.weekday)}',
                  style: TextStyle(color: palette.secondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('schedule_ai_button'),
            tooltip: '打开 AI 助手（课表 / 日程）',
            onPressed: _openAi,
            icon: Icon(Icons.auto_awesome, color: palette.text, size: 22),
          ),
          PopupMenuButton<String>(
            key: const Key('schedule_more_button'),
            tooltip: '更多',
            color: palette.elevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            icon: Badge(
              isLabelVisible: hasDuplicates,
              backgroundColor: palette.danger,
              smallSize: 7,
              child: Icon(Icons.more_vert, color: palette.text),
            ),
            onSelected: (value) {
              if (value == 'today') _goToday();
              if (value == 'merge') _mergeDuplicates(ref.read(scheduleEventsProvider).valueOrNull ?? const []);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'today',
                child: Text('回到今天', style: TextStyle(color: palette.text)),
              ),
              PopupMenuItem(
                value: 'merge',
                enabled: hasDuplicates,
                child: Text(
                  '合并重复日程',
                  style: TextStyle(
                    color: hasDuplicates ? palette.text : palette.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleCalendar() {
    setState(() {
      _expanded = !_expanded;
      _calendarHeight = _expanded ? _expandedHeight : _collapsedHeight;
    });
  }

  Widget _buildCalendar(ColorOsPalette palette, List<ScheduleEvent> events) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              for (final name in const ['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Center(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: palette.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragUpdate: (details) {
            setState(() {
              _calendarHeight = (_calendarHeight + details.delta.dy)
                  .clamp(_collapsedHeight, _expandedHeight);
            });
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            final midpoint = (_collapsedHeight + _expandedHeight) / 2;
            final expand = velocity.abs() > 220
                ? velocity > 0
                : _calendarHeight > midpoint;
            setState(() {
              _expanded = expand;
              _calendarHeight = expand ? _expandedHeight : _collapsedHeight;
              _dragging = false;
            });
          },
          child: AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: _calendarHeight,
            child: ClipRect(
              child: PageView.builder(
                key: ValueKey<bool>(_expanded),
                controller: _pageController,
                itemCount: _monthCount,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: _MonthGrid(
                      month: _monthAt(index),
                      selected: _selected,
                      events: events,
                      expanded: _expanded,
                      palette: palette,
                      onSelect: (date) => setState(() => _selected = date),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        _CalendarToggle(
          palette: palette,
          expanded: _expanded,
          onTap: _toggleCalendar,
        ),
      ],
    );
  }

  Widget _buildDaySummary(ColorOsPalette palette) {
    final lunar = Lunar.fromDate(_selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        children: [
          Text(
            '${_relativeDays(_selected)}  ${_selected.month}月${_selected.day}日',
            style: TextStyle(
              color: palette.secondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '农历${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}',
            style: TextStyle(color: palette.secondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateBanner(
    ColorOsPalette palette,
    int count,
    List<ScheduleEvent> events,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: palette.accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '日历中存在 $count 条重复日程',
                style: TextStyle(color: palette.text, fontSize: 13),
              ),
            ),
            FilledButton(
              key: const Key('schedule_merge_duplicates'),
              onPressed: () => _mergeDuplicates(events),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              child: const Text('合并'),
            ),
            IconButton(
              tooltip: '忽略',
              onPressed: () {},
              icon: Icon(Icons.close, color: palette.secondary, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayEvents(ColorOsPalette palette, List<ScheduleEvent> events) {
    final key = ScheduleEvent.formatDateKey(_selected);
    final dayEvents = events.where((e) => e.dateKey == key).toList()
      ..sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));
    if (dayEvents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ColorOsCard(
          color: palette.surface,
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: Column(
            children: [
              Icon(Icons.event_available_outlined,
                  color: palette.secondary, size: 32),
              const SizedBox(height: 10),
              Text(
                '这一天还没有日程',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '点右下角 + 新建，或点右上角 AI 说一句话',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.secondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '当天日程',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${dayEvents.length}',
                style: TextStyle(color: palette.secondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final event in dayEvents) ...[
            _EventCard(
              event: event,
              palette: palette,
              onTap: () => _openEditor(event: event),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  int _duplicateCount(List<ScheduleEvent> events) {
    final seen = <String>{};
    var duplicates = 0;
    for (final event in events) {
      final key = '${event.dateKey}|${event.title}|${event.startTime ?? ''}';
      if (!seen.add(key)) duplicates++;
    }
    return duplicates;
  }

  String _relativeDays(DateTime date) {
    final days = daysBetween(DateTime.now(), date);
    if (days == 0) return '今天';
    if (days > 0) return '$days天后';
    return '${-days}天前';
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.events,
    required this.expanded,
    required this.palette,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final List<ScheduleEvent> events;
  final bool expanded;
  final ColorOsPalette palette;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final eventKeys = {for (final e in events) e.dateKey};
    final todayKey = ScheduleEvent.formatDateKey(DateTime.now());
    final selectedKey = ScheduleEvent.formatDateKey(selected);
    final dates = expanded ? _monthDates() : _weekDates();
    final rows = <Widget>[];
    for (var row = 0; row < dates.length / 7; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final index = row * 7 + col;
        final date = index < dates.length ? dates[index] : null;
        cells.add(
          Expanded(
            child: date == null
                ? const SizedBox.shrink()
                : _DayCell(
                    date: date,
                    selected: ScheduleEvent.formatDateKey(date) == selectedKey,
                    today: ScheduleEvent.formatDateKey(date) == todayKey,
                    hasEvent: eventKeys.contains(ScheduleEvent.formatDateKey(date)),
                    palette: palette,
                    onTap: () => onSelect(date),
                  ),
          ),
        );
      }
      rows.add(SizedBox(height: 52, child: Row(children: cells)));
    }
    return Column(children: rows);
  }

  List<DateTime?> _monthDates() {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return List<DateTime?>.generate(42, (index) {
      final day = index - offset + 1;
      if (day < 1 || day > days) return null;
      return DateTime(month.year, month.month, day);
    });
  }

  List<DateTime> _weekDates() {
    final start = selected.subtract(Duration(days: selected.weekday % 7));
    return List<DateTime>.generate(7, (i) => addDays(start, i));
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.today,
    required this.hasEvent,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool hasEvent;
  final ColorOsPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lunar = _lunarLabel(date);
    return InkWell(
      key: Key('schedule_day_${ScheduleEvent.formatDateKey(date)}'),
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? palette.selected : Colors.transparent,
              border: today && !selected
                  ? Border.all(color: palette.accent, width: 1.2)
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                color: selected ? Colors.white : palette.text,
                fontSize: 16,
                fontWeight: selected || today ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            lunar,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: selected ? palette.text : palette.secondary,
              fontSize: 9,
              height: 1.1,
            ),
          ),
          if (hasEvent)
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? Colors.white : palette.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarToggle extends StatelessWidget {
  const _CalendarToggle({
    required this.palette,
    required this.expanded,
    required this.onTap,
  });

  final ColorOsPalette palette;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('schedule_calendar_toggle'),
      onTap: onTap,
      child: Container(
        height: 24,
        alignment: Alignment.center,
        child: AnimatedRotation(
          turns: expanded ? 0 : 0.5,
          duration: const Duration(milliseconds: 220),
          child: Icon(
            Icons.keyboard_arrow_up,
            size: 22,
            color: palette.secondary,
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.palette,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ColorOsPalette palette;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: palette.surface,
        foregroundColor: palette.text,
        minimumSize: const Size(42, 42),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.palette,
    required this.onTap,
  });

  final ScheduleEvent event;
  final ColorOsPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = event.allDay
        ? '全天'
        : '${event.startTime}${event.endTime == null ? '' : '\n${event.endTime}'}';
    return ColorOsCard(
      onTap: onTap,
      color: palette.surface,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (event.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    event.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.secondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: palette.secondary, size: 20),
        ],
      ),
    );
  }
}

String _lunarLabel(DateTime date) {
  final key = ScheduleEvent.formatDateKey(date);
  final cached = _lunarCache[key];
  if (cached != null) return cached;
  final lunar = Lunar.fromDate(date);
  final festivals = <String>[
    ...lunar.getFestivals(),
    ...lunar.getSolar().getFestivals(),
  ];
  final label = festivals.isNotEmpty
      ? festivals.first
      : (lunar.getJieQi().isNotEmpty
          ? lunar.getJieQi()
          : (date.day == 1
              ? '${lunar.getMonthInChinese()}月'
              : lunar.getDayInChinese()));
  _lunarCache[key] = label;
  return label;
}

final Map<String, String> _lunarCache = <String, String>{};
