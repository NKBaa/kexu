import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/week_utils.dart';
import '../../core/widgets/app_notice.dart';
import '../../data/models/schedule_event.dart';
import '../ai/ai_edit_page.dart';
import 'providers/schedule_events_provider.dart';
import 'schedule_event_editor_page.dart';

/// 日程页：月历 + 当天事项。
///
/// 与课表无关：这里记录考试、作业截止、活动、会议等个人日程，
/// 支持手动新建/编辑/删除，也支持用 AI 从一句话解析。
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
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

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scheduleEventsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          IconButton(
            key: const Key('schedule_ai_button'),
            tooltip: '打开 AI 助手（课表 / 日程）',
            onPressed: _openAi,
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            key: const Key('schedule_today_button'),
            tooltip: '回到今天',
            onPressed: _goToday,
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('schedule_add_button'),
        heroTag: 'schedule_add_fab',
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('日程'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('读取日程失败：$e')),
        data: (events) => ListView(
          key: const Key('schedule_list'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            _MonthHeader(
              month: _month,
              onPrevious: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              onNext: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
            ),
            const SizedBox(height: 8),
            _MonthGrid(
              month: _month,
              selected: _selected,
              events: events,
              onSelect: (date) => setState(() => _selected = date),
            ),
            const SizedBox(height: 16),
            _SelectedDayHeader(
              date: _selected,
              onAdd: () => _openEditor(),
            ),
            const SizedBox(height: 8),
            _buildDayEvents(events),
          ],
        ),
      ),
    );
  }

  Widget _buildDayEvents(List<ScheduleEvent> events) {
    final key = ScheduleEvent.formatDateKey(_selected);
    final dayEvents = events.where((e) => e.dateKey == key).toList()
      ..sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));
    final theme = Theme.of(context);
    if (dayEvents.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              '这一天还没有日程。\n点右下角「日程」或右上角 AI 添加。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final event in dayEvents) ...[
          _EventCard(
            event: event,
            onTap: () => _openEditor(event: event),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          key: const Key('schedule_prev_month'),
          tooltip: '上个月',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${month.year} 年 ${month.month} 月',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          key: const Key('schedule_next_month'),
          tooltip: '下个月',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.events,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final List<ScheduleEvent> events;
  final ValueChanged<DateTime> onSelect;

  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();
    final todayKey = ScheduleEvent.formatDateKey(today);
    final eventKeys = {for (final e in events) e.dateKey};

    return Column(
      children: [
        Row(
          children: [
            for (final name in _weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.9,
          ),
          itemCount: cells,
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > daysInMonth) {
              return const SizedBox.shrink();
            }
            final date = DateTime(month.year, month.month, day);
            final key = ScheduleEvent.formatDateKey(date);
            final isSelected = key == ScheduleEvent.formatDateKey(selected);
            final isToday = key == todayKey;
            final hasEvents = eventKeys.contains(key);
            return InkWell(
              key: Key('schedule_day_$key'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelect(date),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primaryContainer
                      : (isToday
                          ? scheme.primary.withValues(alpha: 0.08)
                          : null),
                  borderRadius: BorderRadius.circular(12),
                  border: isToday && !isSelected
                      ? Border.all(color: scheme.primary, width: 1)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight:
                            isSelected || isToday ? FontWeight.w800 : null,
                        color: isSelected
                            ? scheme.onPrimaryContainer
                            : (isToday ? scheme.primary : null),
                      ),
                    ),
                    if (hasEvents)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? scheme.primary : scheme.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SelectedDayHeader extends StatelessWidget {
  const _SelectedDayHeader({required this.date, required this.onAdd});

  final DateTime date;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '${date.month} 月 ${date.day} 日 · ${weekdayName(date.weekday)}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加'),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final ScheduleEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = event.allDay
        ? '全天'
        : '${event.startTime}${event.endTime == null ? '' : '-${event.endTime}'}';
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        title: Text(event.title),
        subtitle: event.note.isEmpty
            ? null
            : Text(
                event.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
