import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timetable/providers/timetable_provider.dart';
import '../../widget/timetable_widget_service.dart';
import '../providers/settings_provider.dart';

/// 「桌面小组件」设置页：说明如何添加，并支持手动刷新快照。
///
/// 小组件本身由 Android 原生 `TimetableWidgetProvider` 渲染；这里只负责
/// 引导用户到桌面添加，以及在课表/节假日改动后立即推送一次最新快照。
class WidgetSettingsPage extends ConsumerStatefulWidget {
  const WidgetSettingsPage({super.key});

  @override
  ConsumerState<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends ConsumerState<WidgetSettingsPage> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final timetable = ref.read(timetableProvider).valueOrNull;
      final settings = await ref.read(settingsProvider.future);
      if (timetable == null) {
        if (!mounted) return;
        _notice('课表还没加载完成，请稍后再试。');
        return;
      }
      final ok = await TimetableWidgetService()
          .updateFromTimetable(timetable, settings);
      if (!mounted) return;
      _notice(ok ? '已刷新桌面小组件。' : '当前设备暂不支持桌面小组件（仅 Android）。');
    } catch (e) {
      if (!mounted) return;
      _notice('刷新失败：$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.widgets_outlined,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '今日课表',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '在桌面直接查看今天的课程、教室与节假日',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '添加方法',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _Step(
                        index: 1,
                        text: '回到手机桌面，长按空白处（或双指捏合）。',
                      ),
                      const _Step(
                        index: 2,
                        text: '选择「小组件 / 卡片」，找到「课序」或「今日课表」。',
                      ),
                      const _Step(
                        index: 3,
                        text: '拖到桌面即可；打开 App 后小组件会自动更新。',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('widget_refresh_button'),
                          onPressed: _refreshing ? null : _refresh,
                          icon: _refreshing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: const Text('立即刷新小组件'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: scheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '说明：小组件目前仅支持 Android。桌面启动器可能限制刷新频率，'
                    '课表变化后打开一次 App 即可同步；如果桌面没有显示，请确认系统'
                    '允许课序创建桌面小组件。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
