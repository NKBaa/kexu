import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_notice.dart';
import '../../../core/widgets/hint_icon.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/timetable.dart';
import '../../notifications/class_reminder_service.dart';
import '../../notifications/class_reminder_sessions.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../providers/settings_provider.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 「节假日与提醒」设置页。
///
/// 两件事放在一起的原因：它们都影响「哪一天、几点该提醒你上课」。
/// - 节假日：放假当天不排提醒；
/// - 上课提醒：开关、提前分钟、通知样式与权限。
///
/// 所有改动即时保存（与设置中心其它页面一致），保存后立刻把提醒重新
/// 同步给原生排程器；原生侧是「先取消再重排」，因此重复调用是安全的。
class HolidayReminderPage extends ConsumerStatefulWidget {
  const HolidayReminderPage({super.key});

  @override
  ConsumerState<HolidayReminderPage> createState() => _HolidayReminderPageState();
}

class _HolidayReminderPageState extends ConsumerState<HolidayReminderPage>
    with WidgetsBindingObserver {
  String _permission = ClassReminderService.permissionUnknown;
  bool _requesting = false;
  Timer? _permissionPoll;
  int _pollTicks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshPermission();
    });
  }

  @override
  void dispose() {
    _permissionPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统权限弹窗/系统设置返回时刷新一次，保证状态是最新的。
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final service = ref.read(classReminderServiceProvider);
    if (!service.isSupported) {
      if (mounted) {
        setState(() => _permission = ClassReminderService.permissionUnsupported);
      }
      return;
    }
    final status = await service.permissionStatus();
    if (!mounted) return;
    setState(() => _permission = status);
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    final service = ref.read(classReminderServiceProvider);
    if (!service.isSupported) {
      showAppNotice(context, '当前平台暂不支持系统通知');
      return;
    }
    setState(() => _requesting = true);
    final status = await service.requestPermission();
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _permission = status;
    });
    if (status == ClassReminderService.permissionGranted) {
      showAppNotice(context, '通知权限已开启');
      return;
    }
    showAppNotice(context, '已发出权限请求，请在系统弹窗中选择「允许」');
    _startPermissionPoll();
  }

  /// 系统授权弹窗是异步的：短时间内轮询几次，用户点完「允许」后界面立刻更新。
  void _startPermissionPoll() {
    _permissionPoll?.cancel();
    _pollTicks = 0;
    _permissionPoll = Timer.periodic(const Duration(milliseconds: 600), (timer) async {
      _pollTicks++;
      if (_pollTicks > 15 || !mounted) {
        timer.cancel();
        return;
      }
      final status = await ref.read(classReminderServiceProvider).permissionStatus();
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _permission = status);
      if (status == ClassReminderService.permissionGranted) {
        timer.cancel();
        showAppNotice(context, '通知权限已开启');
      }
    });
  }

  Future<void> _openSystemSettings() async {
    final ok = await ref.read(classReminderServiceProvider).openNotificationSettings();
    if (!mounted) return;
    if (!ok) {
      showAppNotice(context, '无法打开系统通知设置，请手动到系统设置里找到「课序」');
    }
  }

  /// 把当前课表 + 设置同步给原生排程器（幂等）。
  Future<void> _syncReminders() async {
    final timetable = ref.read(timetableProvider).valueOrNull;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (timetable == null || settings == null) return;
    try {
      await syncFromTimetable(timetable, settings);
    } catch (e) {
      debugPrint('同步上课提醒失败：$e');
    }
  }

  Future<void> _onToggleReminder(bool value) async {
    await ref.read(settingsProvider.notifier).setClassReminderEnabled(value);
    await _syncReminders();
    if (!mounted) return;
    if (!value) {
      showAppNotice(context, '已关闭上课提醒');
      return;
    }
    if (_permission == ClassReminderService.permissionGranted ||
        _permission == ClassReminderService.permissionUnsupported) {
      showAppNotice(context, '已开启上课提醒');
    } else {
      showAppNotice(context, '已开启上课提醒，还需要允许通知权限才能收到提醒');
    }
  }

  Future<void> _onMinutesChanged(int minutes) async {
    await ref.read(settingsProvider.notifier).setReminderMinutes(minutes);
    await _syncReminders();
    if (!mounted) return;
    showAppNotice(context, '已改为提前 $minutes 分钟提醒');
  }

  Future<void> _onStyleChanged(String style) async {
    await ref.read(settingsProvider.notifier).setNotificationStyle(style);
    await _syncReminders();
    if (!mounted) return;
    showAppNotice(
      context,
      style == 'vendor' ? '已切换到「厂商活动卡片（实验）」' : '已切换到「系统通知」',
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final timetableAsync = ref.watch(timetableProvider);

    return SettingsSubPage(
      title: '上课提醒',
      subtitle: '上课前用系统通知叫你；节假日管理已移到「学期与作息」',
      child: settingsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Text('读取设置失败：$e'),
        data: (settings) => _buildBody(
          context,
          settings,
          timetableAsync.valueOrNull,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppSettings settings,
    Timetable? timetable,
  ) {
    final preview = settings.classReminderEnabled && timetable != null
        ? buildReminderSessions(timetable, settings, DateTime.now())
        : const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReminderCard(context, settings, preview),
        const SizedBox(height: 12),
        _buildPermissionCard(context),
      ],
    );
  }

  // ---------------------------------------------------------------- 提醒卡片

  Widget _buildReminderCard(
    BuildContext context,
    AppSettings settings,
    List<Map<String, dynamic>> preview,
  ) {
    final theme = Theme.of(context);
    final enabled = settings.classReminderEnabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('上课提醒', style: theme.textTheme.titleSmall),
                const SizedBox(width: 2),
                const HintIcon(
                  message: '开启后 App 会用系统闹钟安排未来 7 天的课程提醒，'
                      '到点由系统弹出通知，不需要 App 一直开着。',
                ),
              ],
            ),
            SwitchListTile(
              key: const Key('class_reminder_switch'),
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: _onToggleReminder,
              title: const Text('开启上课提醒'),
              subtitle: const Text('上课前用系统通知提醒你，App 不需要常驻后台'),
            ),
            if (!enabled)
              Text(
                '开启后会自动排程未来 7 天的课程提醒；放假当天会跳过。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              const Divider(height: 20),
              Text('提前多久提醒', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in AppSettings.reminderMinuteOptions)
                    ChoiceChip(
                      key: Key('reminder_minutes_$minutes'),
                      label: Text('提前 $minutes 分钟'),
                      selected: settings.reminderMinutes == minutes,
                      onSelected: (_) => _onMinutesChanged(minutes),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('通知样式', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _NotificationStyleTile(
                key: const Key('notification_style_system'),
                selected: settings.notificationStyle == 'system',
                icon: Icons.notifications_none,
                title: '系统通知',
                description: '标准通知栏提醒，稳定可靠',
                onTap: () => _onStyleChanged('system'),
              ),
              const SizedBox(height: 8),
              _NotificationStyleTile(
                key: const Key('notification_style_vendor'),
                selected: settings.notificationStyle == 'vendor',
                icon: Icons.campaign_outlined,
                title: '厂商活动卡片（实验）',
                description: '独立的高优先级渠道「课序活动提醒」',
                onTap: () => _onStyleChanged('vendor'),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '「厂商活动卡片」只是把通知放到单独的高优先级渠道，'
                        '尽量争取横幅/卡片样式。OPPO、vivo 等系统是否真的把它显示成'
                        '活动卡片，由系统自己的通知策略决定，课序无法保证。'
                        '如果没显示，请到系统设置里允许「课序」的通知、横幅与自启动。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                preview.isEmpty
                    ? '未来 7 天暂时没有需要提醒的课程（可能已放假或学期结束）。'
                    : '未来 7 天将提醒 ${preview.length} 节课'
                        '（最近一节：${preview.first['date']} '
                        '${preview.first['start']} ${preview.first['name']}）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 权限卡片

  Widget _buildPermissionCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _permission;
    final granted = status == ClassReminderService.permissionGranted;
    final unsupported = status == ClassReminderService.permissionUnsupported;

    final (String label, Color bg, Color fg) = switch (status) {
      ClassReminderService.permissionGranted => (
          '已授权',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      ClassReminderService.permissionDenied => (
          '未授权',
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      ClassReminderService.permissionUnsupported => (
          '当前平台不支持',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      _ => ('未知', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    final String description = switch (status) {
      ClassReminderService.permissionGranted =>
        '通知已开启。部分系统（OPPO / vivo / 小米）还需要允许「横幅」「锁屏通知」'
            '和「自启动」，否则提醒可能被系统拦截。',
      ClassReminderService.permissionDenied =>
        '通知未开启，上课提醒不会弹出。点击下方按钮请求权限，'
            '或到系统设置里手动允许「课序」的通知。',
      ClassReminderService.permissionUnsupported =>
        '当前平台（如 Windows 桌面）暂不支持系统通知；'
            '节假日设置仍会保存，并在课表里生效。',
      _ => '暂时无法读取通知权限状态，可以尝试点击下方按钮重新检查。',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('通知权限', style: theme.textTheme.titleSmall),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('notification_permission_button'),
                  onPressed: unsupported || _requesting
                      ? null
                      : _requestPermission,
                  icon: _requesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notifications_active_outlined, size: 18),
                  label: Text(_requesting ? '请求中…' : '请求通知权限'),
                ),
                OutlinedButton.icon(
                  key: const Key('notification_settings_button'),
                  onPressed: unsupported ? null : _openSystemSettings,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('打开系统通知设置'),
                ),
              ],
            ),
            if (granted) ...[
              const SizedBox(height: 8),
              Text(
                '收不到提醒时，优先检查系统的「自启动」「后台运行」权限。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 通知样式的单选项（不用 RadioListTile，避免 Material 版本差异）。
class _NotificationStyleTile extends StatelessWidget {
  const _NotificationStyleTile({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
