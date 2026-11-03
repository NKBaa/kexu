import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_notice.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/app_theme_spec.dart';
import '../../../data/services/theme_market_service.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_market_provider.dart';
import 'semester_settings_page.dart' show SettingsSubPage;
import 'theme_editor_page.dart';

/// 主题中心：主题模式、内置主题、我的主题、GitHub 主题市场。
class ThemeCenterPage extends ConsumerWidget {
  const ThemeCenterPage({super.key});

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    AppThemeSpec spec,
  ) async {
    await ref.read(settingsProvider.notifier).setActiveTheme(spec.id);
    if (context.mounted) showAppNotice(context, '已应用主题：${spec.name}');
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AppThemeSpec? initial,
  ) async {
    final spec = await Navigator.of(context).push<AppThemeSpec>(
      MaterialPageRoute<AppThemeSpec>(
        builder: (_) => ThemeEditorPage(initial: initial),
      ),
    );
    if (spec == null || !context.mounted) return;
    try {
      await ref.read(settingsProvider.notifier).upsertCustomTheme(spec);
      await ref.read(settingsProvider.notifier).setActiveTheme(spec.id);
      if (context.mounted) showAppNotice(context, '已保存并应用主题：${spec.name}');
    } catch (e) {
      if (context.mounted) showAppNotice(context, '保存失败：$e');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppThemeSpec spec,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除主题'),
        content: Text('确定删除「${spec.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(settingsProvider.notifier).removeCustomTheme(spec.id);
    if (context.mounted) showAppNotice(context, '已删除主题：${spec.name}');
  }

  Future<void> _install(
    BuildContext context,
    WidgetRef ref,
    AppThemeSpec spec,
  ) async {
    try {
      await ref.read(settingsProvider.notifier).upsertCustomTheme(spec);
      if (context.mounted) showAppNotice(context, '已安装主题：${spec.name}');
    } catch (e) {
      if (context.mounted) showAppNotice(context, '安装失败：$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final marketAsync = ref.watch(themeMarketProvider);
    final theme = Theme.of(context);

    return SettingsSubPage(
      title: '主题中心',
      subtitle: '选择内置主题、自己写主题代码，或从 GitHub 主题市场安装',
      child: settingsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Text('读取主题设置失败：$e'),
        data: (settings) {
          final custom = settings.customThemes;
          final active = findTheme(custom, settings.activeThemeId) ??
              AppThemeSpec.builtIns.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildModeCard(context, ref, settings),
              const SizedBox(height: 12),
              _buildCurrentCard(context, ref, active),
              const SizedBox(height: 18),
              _SectionHeader(
                title: '内置主题',
                subtitle: '点击立即应用',
              ),
              const SizedBox(height: 8),
              _ThemeGrid(
                themes: AppThemeSpec.builtIns,
                activeId: active.id,
                onTap: (spec) => _apply(context, ref, spec),
              ),
              const SizedBox(height: 18),
              _SectionHeader(
                title: '我的主题',
                subtitle: '用 JSON 代码自己写，或从市场安装',
                trailing: FilledButton.tonalIcon(
                  key: const Key('theme_new_button'),
                  onPressed: () => _edit(context, ref, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建'),
                ),
              ),
              const SizedBox(height: 8),
              if (custom.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '还没有自定义主题。点「新建」写一段 JSON 主题代码，'
                      '或从下方主题市场安装。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                for (final spec in custom) ...[
                  _ThemeListTile(
                    spec: spec,
                    active: spec.id == active.id,
                    onApply: () => _apply(context, ref, spec),
                    onEdit: () => _edit(context, ref, spec),
                    onDelete: () => _delete(context, ref, spec),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 10),
              _SectionHeader(
                title: '主题市场',
                subtitle: marketAsync.valueOrNull?.updatedAt.isNotEmpty == true
                    ? 'GitHub · ${marketAsync.valueOrNull!.updatedAt}'
                    : '托管在 GitHub，更新主题无需发版',
                trailing: IconButton(
                  key: const Key('theme_market_refresh'),
                  tooltip: '刷新主题市场',
                  onPressed: () => ref.invalidate(themeMarketProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(height: 8),
              _buildMarket(context, ref, marketAsync, custom),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题模式'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'system', label: Text('跟随系统')),
                  ButtonSegment(value: 'light', label: Text('浅色')),
                  ButtonSegment(value: 'dark', label: Text('深色')),
                ],
                selected: <String>{
                  ['system', 'light', 'dark'].contains(settings.themeMode)
                      ? settings.themeMode
                      : 'system'
                },
                onSelectionChanged: (s) =>
                    ref.read(settingsProvider.notifier).setThemeMode(s.first),
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.weekend_outlined),
            title: const Text('显示周六、周日'),
            subtitle: const Text('关闭后周视图只显示周一到周五'),
            value: settings.showWeekend,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setShowWeekend(v),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.code, color: Colors.transparent),
            title: Text(
              '主题代码支持修改主色、背景、卡片、文字与圆角',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCard(
    BuildContext context,
    WidgetRef ref,
    AppThemeSpec active,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _ThemePreview(spec: active, size: 62),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前主题 · ${active.name}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active.description.isEmpty ? '自定义主题' : active.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (active.id != 'default')
              TextButton(
                onPressed: () =>
                    _apply(context, ref, AppThemeSpec.builtIns.first),
                child: const Text('恢复默认'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarket(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ThemeMarketCatalog> marketAsync,
    List<AppThemeSpec> installed,
  ) {
    final theme = Theme.of(context);
    return marketAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('主题市场加载失败', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('$e', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => ref.invalidate(themeMarketProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (catalog) {
        if (catalog.themes.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('主题市场暂时为空。'),
            ),
          );
        }
        return Column(
          children: [
            for (final spec in catalog.themes) ...[
              _ThemeListTile(
                spec: spec,
                active: false,
                installed: installed.any((t) => t.id == spec.id),
                onApply: () => _apply(context, ref, spec),
                onInstall: () => _install(context, ref, spec),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({
    required this.themes,
    required this.activeId,
    required this.onTap,
  });

  final List<AppThemeSpec> themes;
  final String activeId;
  final ValueChanged<AppThemeSpec> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final spec in themes)
          _ThemeCard(
            spec: spec,
            active: spec.id == activeId,
            onTap: () => onTap(spec),
          ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.spec,
    required this.active,
    required this.onTap,
  });

  final AppThemeSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 156,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: active ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ThemePreview(spec: spec, size: 44),
                const SizedBox(height: 8),
                Text(
                  spec.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  active ? '使用中' : spec.author.isEmpty ? '点击应用' : spec.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeListTile extends StatelessWidget {
  const _ThemeListTile({
    required this.spec,
    required this.active,
    this.installed = false,
    this.onApply,
    this.onInstall,
    this.onEdit,
    this.onDelete,
  });

  final AppThemeSpec spec;
  final bool active;
  final bool installed;
  final VoidCallback? onApply;
  final VoidCallback? onInstall;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _ThemePreview(spec: spec, size: 40),
        title: Text(spec.name),
        subtitle: Text(
          spec.description.isEmpty
              ? (spec.author.isEmpty ? '自定义主题' : spec.author)
              : spec.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            if (active)
              const Chip(label: Text('使用中'))
            else if (onApply != null)
              TextButton(
                onPressed: onApply,
                child: const Text('应用'),
              ),
            if (onInstall != null)
              TextButton(
                onPressed: installed ? null : onInstall,
                child: Text(installed ? '已安装' : '安装'),
              ),
            if (onEdit != null)
              IconButton(
                tooltip: '编辑代码',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            if (onDelete != null)
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.spec, required this.size});

  final AppThemeSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = spec.paletteFor(Brightness.light);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Center(
        child: Container(
          width: size * 0.46,
          height: size * 0.46,
          decoration: BoxDecoration(
            color: p.cardColor,
            borderRadius: BorderRadius.circular(size * 0.18),
            border: Border.all(color: p.seedColor, width: 2),
          ),
        ),
      ),
    );
  }
}
