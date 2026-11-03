import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/schedule_event.dart';
import '../ai/ai_client_provider.dart';
import '../ai/ai_exception.dart';
import '../settings/providers/settings_provider.dart';
import 'providers/schedule_events_provider.dart';
import 'schedule_event_ai.dart';

Future<bool> showScheduleAiSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const ScheduleAiSheet(),
  );
  return result == true;
}

class ScheduleAiSheet extends ConsumerStatefulWidget {
  const ScheduleAiSheet({super.key});

  @override
  ConsumerState<ScheduleAiSheet> createState() => _ScheduleAiSheetState();
}

class _ScheduleAiSheetState extends ConsumerState<ScheduleAiSheet> {
  final TextEditingController _controller = TextEditingController();
  final List<ScheduleEvent> _preview = [];
  bool _busy = false;
  String? _error;

  static const List<String> _examples = [
    '下周三下午 3 点交高数作业',
    '明天晚上 7 点社团例会，地点活动中心',
    '下个月 5 号全天：英语四级报名截止',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '先描述要添加什么日程。');
      return;
    }
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.aiConfig.textConfigured) {
      setState(() => _error = '还没有配置语言模型。请到「设置 → 大模型配置 → 语言模型」里填写。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _preview.clear();
    });
    try {
      final events = await ScheduleEventAiService(
        client: ref.read(textAiClientProvider),
      ).plan(text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview.addAll(events);
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'AI 设置日程失败：$e';
      });
    }
  }

  Future<void> _addAll() async {
    if (_preview.isEmpty) return;
    await ref.read(scheduleEventsProvider.notifier).addEvents(_preview);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '用 AI 添加日程',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('schedule_ai_input'),
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如：下周三下午 3 点交高数作业',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final example in _examples)
                  ActionChip(
                    label: Text(example, style: const TextStyle(fontSize: 12)),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _controller.text = example),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('schedule_ai_run'),
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_busy ? '正在解析…' : 'AI 识别'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (_preview.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '将添加 ${_preview.length} 个日程',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final event in _preview)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined, size: 20),
                        title: Text(event.title),
                        subtitle: Text(
                          '${event.dateKey}'
                          '${event.allDay ? ' · 全天' : ' · ${event.startTime}${event.endTime == null ? '' : '-${event.endTime}'}'}'
                          '${event.note.isEmpty ? '' : ' · ${event.note}'}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('schedule_ai_apply'),
                onPressed: _addAll,
                child: Text('添加 ${_preview.length} 个日程'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
