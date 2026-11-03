import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/timetable.dart';
import '../timetable/providers/timetable_provider.dart';
import 'pages/about_settings_page.dart';
import 'pages/ai_settings_page.dart';
import 'pages/data_settings_page.dart';
import 'pages/holiday_reminder_page.dart';
import 'pages/semester_settings_page.dart';
import 'pages/theme_center_page.dart';
import 'pages/update_settings_page.dart';
import 'pages/widget_settings_page.dart';

/// 设置中心里的一个分类。
///
/// 新增设置分类时**只需要往 [settingsSections] 里加一条**：
/// 写标题、图标与目标页面即可，不需要改动本页布局。
/// 这就是「二级菜单方便后续按功能添加分类」的落点。
class SettingsSection {
  /// 稳定标识（测试与深链接用）。
  final String id;

  /// 分类标题。
  final String title;

  /// 一句话说明（让用户知道点进去能做什么）。
  final String subtitle;

  final IconData icon;

  /// 目标页面构造器。
  final WidgetBuilder builder;

  /// 是否危险操作（用错误色强调）。
  final bool danger;

  const SettingsSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
    this.danger = false,
  });
}

/// 设置分类注册表。
///
/// 后续要加「震动反馈」「课程提醒」「导入模板」等，只在这里追加一条即可。
List<SettingsSection> settingsSections() => <SettingsSection>[
      SettingsSection(
        id: 'semester',
        title: '学期与作息',
        subtitle: '学期起止、总周数、每节课的上下课时间',
        icon: Icons.calendar_month_outlined,
        builder: (_) => const SemesterSettingsPage(),
      ),
      SettingsSection(
        id: 'ai',
        title: '大模型配置',
        subtitle: '图片转课表、一句话改课表所用的 API',
        icon: Icons.auto_awesome_outlined,
        builder: (_) => const AiSettingsPage(),
      ),
      SettingsSection(
        id: 'holiday',
        title: '上课提醒',
        subtitle: '上课前系统通知、提前分钟与通知样式',
        icon: Icons.notifications_active_outlined,
        builder: (_) => const HolidayReminderPage(),
      ),
      SettingsSection(
        id: 'widget',
        title: '桌面小组件',
        subtitle: '在桌面查看今日课程与节假日（Android）',
        icon: Icons.widgets_outlined,
        builder: (_) => const WidgetSettingsPage(),
      ),
      SettingsSection(
        id: 'data',
        title: '数据管理',
        subtitle: '导入导出、网盘同步、本地备份与清空',
        icon: Icons.storage_outlined,
        builder: (_) => const DataSettingsPage(),
      ),
      SettingsSection(
        id: 'theme',
        title: '主题中心',
        subtitle: '内置主题、自己写主题代码、GitHub 主题市场',
        icon: Icons.palette_outlined,
        builder: (_) => const ThemeCenterPage(),
      ),
      SettingsSection(
        id: 'update',
        title: '检查更新',
        subtitle: '从 GitHub Releases 获取新版本，支持国内镜像加速',
        icon: Icons.system_update,
        builder: (_) => const UpdateSettingsPage(),
      ),
      SettingsSection(
        id: 'about',
        title: '关于',
        subtitle: '版本信息与使用说明',
        icon: Icons.info_outline,
        builder: (_) => const AboutSettingsPage(),
      ),
    ];

/// 设置中心：二级菜单入口页。
class SettingsHomePage extends ConsumerWidget {
  const SettingsHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timetableProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              async.when(
                loading: () => const SizedBox.shrink(),
                error: (e, st) => const SizedBox.shrink(),
                data: (timetable) => _buildOverview(context, timetable),
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < settingsSections().length; i++) ...[
                      _buildSectionTile(context, ref, settingsSections()[i]),
                      if (i < settingsSections().length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  '$appName v$versionLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTile(BuildContext context, WidgetRef ref, SettingsSection s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      key: Key('settings_section_${s.id}'),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: s.danger ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          s.icon,
          size: 20,
          color: s.danger ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
      title: Text(s.title),
      subtitle: Text(s.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: s.builder),
      ),
    );
  }

  Widget _buildOverview(BuildContext context, Timetable timetable) {
    final theme = Theme.of(context);
    final sem = timetable.semester;
    final endDate = addDays(sem.startMonday, sem.totalWeeks * 7 - 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.school_outlined,
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sem.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_fmtDate(sem.startMonday)} 起 · 共 ${sem.totalWeeks} 周'
                    ' · 截止 ${_fmtDate(endDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${timetable.courses.length} 门课程 · ${timetable.sessionCount} 个时段',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
