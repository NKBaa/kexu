import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/bell_schedule_template.dart';
import '../../timetable/providers/timetable_provider.dart';
import '../providers/schedule_template_provider.dart';
import '../schedule_template_apply.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 作息模板页：先按学校展示，进入学校后查看详细作息并导入。
class ScheduleTemplatesPage extends ConsumerWidget {
  const ScheduleTemplatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(scheduleTemplateCatalogProvider);
    return SettingsSubPage(
      title: '作息模板',
      subtitle: '模板托管在 GitHub，先按学校选择，再查看详细作息；支持整套导入。',
      actions: [
        IconButton(
          key: const Key('schedule_template_search'),
          tooltip: '搜索学校或模板',
          icon: const Icon(Icons.search),
          onPressed: () async {
            final catalog = ref.read(scheduleTemplateCatalogProvider).valueOrNull;
            if (catalog == null) return;
            final selected = await showSearch<BellScheduleTemplate?>(
              context: context,
              delegate: _TemplateSearchDelegate(catalog),
            );
            if (selected == null || !context.mounted) return;
            final school = catalog.schools.firstWhere(
              (s) => s.school == selected.school,
              orElse: () => catalog.schools.first,
            );
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SchoolTemplatesPage(school: school),
              ),
            );
          },
        ),
        IconButton(
          key: const Key('schedule_template_refresh'),
          tooltip: '刷新模板',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(scheduleTemplateCatalogProvider),
        ),
      ],
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => _ErrorCard(
          message: '$e',
          onRetry: () => ref.invalidate(scheduleTemplateCatalogProvider),
        ),
        data: (catalog) => _CatalogBody(catalog: catalog),
      ),
    );
  }
}

class _CatalogBody extends StatelessWidget {
  const _CatalogBody({required this.catalog});

  final BellScheduleTemplateCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (catalog.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('模板目录为空。'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '模板来自 GitHub 仓库；共 ${catalog.schools.length} 所学校、'
                    '${catalog.allTemplates.length} 套作息。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final school in catalog.schools) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: Key('schedule_school_${school.school}'),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.account_balance_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                school.school,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${school.templates.length} 套作息'
                '${school.note.isEmpty ? '' : ' · ${school.note}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SchoolTemplatesPage(school: school),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// 某个学校的详细作息页。
class SchoolTemplatesPage extends ConsumerWidget {
  const SchoolTemplatesPage({super.key, required this.school});

  final SchoolBellTemplates school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SettingsSubPage(
      title: school.school,
      subtitle: school.note.isEmpty
          ? '查看各套作息，可单独应用或一次全部导入。'
          : '${school.note}\n可单独应用或一次全部导入。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (school.templates.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const Key('schedule_template_import_all'),
                onPressed: () => _importTemplates(
                  context,
                  ref,
                  school.templates,
                  allAtOnce: true,
                ),
                icon: const Icon(Icons.download_done, size: 18),
                label: Text('全部导入（${school.templates.length} 套）'),
              ),
            ),
          if (school.templates.length > 1) const SizedBox(height: 10),
          for (final template in school.templates) ...[
            _TemplateDetailCard(
              template: template,
              onApply: () => _importTemplates(context, ref, [template]),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '带生效日期范围的模板会按当前学期自动换算年份；'
              '没有日期范围的模板会作为常驻作息导入。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importTemplates(
    BuildContext context,
    WidgetRef ref,
    List<BellScheduleTemplate> templates, {
    bool allAtOnce = false,
  }) async {
    if (templates.isEmpty) return;
    final timetable = ref.read(timetableProvider).valueOrNull;
    if (timetable == null) return;

    if (allAtOnce) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('导入 ${templates.length} 套作息？'),
          content: const Text('将按学校模板新增多套作息，并自动套用生效日期范围。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('全部导入'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }

    final count = await applyScheduleTemplates(ref, templates);
    if (count == 0 || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            count == 1
                ? '已应用作息模板「${templates.single.name}」'
                : '已导入 $count 套作息',
          ),
        ),
      );
  }
}

class _TemplateDetailCard extends StatelessWidget {
  const _TemplateDetailCard({required this.template, required this.onApply});

  final BellScheduleTemplate template;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('schedule_template_detail_${template.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    template.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  key: Key('schedule_template_apply_${template.id}'),
                  onPressed: onApply,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('应用'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${template.rangeLabel} · ${template.slots.length} 节 · '
              '${template.firstStart}-${template.lastEnd}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (template.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(template.description, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final slot in template.slots)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '第${slot.period}节 ${slot.start}-${slot.end}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateSearchDelegate extends SearchDelegate<BellScheduleTemplate?> {
  _TemplateSearchDelegate(this.catalog);

  final BellScheduleTemplateCatalog catalog;

  @override
  String get searchFieldLabel => '搜索学校或作息模板';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: '返回',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final keyword = query.trim().toLowerCase();
    final rows = <Widget>[];
    for (final school in catalog.schools) {
      for (final template in school.templates) {
        final haystack =
            '${school.school} ${school.note} ${template.name} ${template.description}'
                .toLowerCase();
        if (keyword.isNotEmpty && !haystack.contains(keyword)) continue;
        rows.add(
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(template.name),
            subtitle: Text('${school.school} · ${template.rangeLabel} · '
                '${template.slots.length} 节'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => close(context, template),
          ),
        );
      }
    }
    if (rows.isEmpty) {
      return const Center(child: Text('没有找到匹配的学校或模板'));
    }
    return ListView(children: rows);
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 20, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text('模板加载失败', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('schedule_template_retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
