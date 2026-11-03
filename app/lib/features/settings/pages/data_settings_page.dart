import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/timetable.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../import_export/import_export_page.dart';
import '../../sync/sync_page.dart';
import '../../timetable/providers/timetable_provider.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 数据管理页：备份、导入导出、网盘同步、清空。
class DataSettingsPage extends ConsumerStatefulWidget {
  const DataSettingsPage({super.key});

  @override
  ConsumerState<DataSettingsPage> createState() => _DataSettingsPageState();
}

class _DataSettingsPageState extends ConsumerState<DataSettingsPage> {
  bool _clearing = false;

  TimetableRepository get _repo => ref.read(timetableRepositoryProvider);

  late final Future<String> _dataPathFuture;

  @override
  void initState() {
    super.initState();
    _dataPathFuture = _repo.dataFilePath();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(timetableProvider);
    return SettingsSubPage(
      title: '数据管理',
      subtitle: '备份、导入导出、网盘同步与清空',
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, st) => Text('读取失败：$e'),
        data: (timetable) => _buildBody(context, timetable),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Timetable timetable) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.swap_vert,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('导入 / 导出', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '导出为 JSON 文件或复制到剪贴板，用于换机迁移与备份。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _openImportExport,
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: const Text('打开导入导出'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_sync_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('网盘同步', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '通过 WebDAV（坚果云 / Nextcloud / 群晖等）在手机与电脑之间同步课表。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _openSync,
                  icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                  label: const Text('配置网盘同步'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.save_alt,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('本地备份', style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _backupToAppDir(timetable),
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('备份到应用目录'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          timetable.courses.isEmpty || _clearing ? null : () => _clearAll(timetable),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: _clearing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_forever_outlined, size: 18),
                      label: const Text('清空所有课程'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FutureBuilder<String>(
                  future: _dataPathFuture,
                  builder: (context, snap) {
                    final path = snap.data;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.folder_outlined,
                            size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            path == null ? '数据文件位置读取中…' : '数据文件：$path',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openImportExport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => const ImportExportPage()),
    );
  }

  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SyncPage()),
    );
  }

  Future<void> _backupToAppDir(Timetable timetable) async {
    try {
      final path = await _repo.dataFilePath();
      final slash = path.lastIndexOf(RegExp(r'[\\/]'));
      final dir = slash > 0 ? path.substring(0, slash) : '.';
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .substring(0, 19);
      final sep = path.contains(r'\') ? r'\' : '/';
      final target = '$dir${sep}backup_$stamp.json';
      await _repo.exportToFile(timetable, target);
      if (!mounted) return;
      _toast('已备份到 $target');
    } catch (e) {
      if (!mounted) return;
      _toast('备份失败：$e', error: true);
    }
  }

  Future<void> _clearAll(Timetable timetable) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空所有课程？'),
        content: Text(
          '将删除全部 ${timetable.courses.length} 门课程及其 ${timetable.sessionCount} 个时段，'
          '学期与作息设置会保留。\n\n此操作不可撤销，建议先导出备份。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      await ref
          .read(timetableProvider.notifier)
          .deleteCourses(timetable.courses.map((c) => c.id).toSet());
      if (!mounted) return;
      setState(() => _clearing = false);
      _toast('已清空所有课程');
    } catch (e) {
      if (!mounted) return;
      setState(() => _clearing = false);
      _toast('清空失败：$e', error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ));
  }
}
