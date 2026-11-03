import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../data/models/course.dart';
import '../../data/models/timetable.dart';
import '../../data/repositories/timetable_repository.dart';
import '../timetable/providers/timetable_provider.dart';

/// 数据导入导出页：JSON 文件 + 剪贴板双通道。
///
/// 为什么两种通道都要：Windows 端用文件最方便，Android 端把文本丢进微信/网盘
/// 或者直接粘贴一段 JSON 反而更快；AI 生成的 JSON 也常常是「复制粘贴」场景。
/// 所有覆盖式导入都必须二次确认，且导入前会先展示解析结果摘要。
class ImportExportPage extends ConsumerStatefulWidget {
  const ImportExportPage({super.key});

  @override
  ConsumerState<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends ConsumerState<ImportExportPage> {
  /// 用全局注入的仓储实例（测试可 override）。
  TimetableRepository get _repo => ref.read(timetableRepositoryProvider);

  /// 手动/剪贴板/文件读入的待导入文本。
  final TextEditingController _textCtrl = TextEditingController();

  bool _busy = false;
  bool _advancedOpen = false;

  /// 最近一次解析成功的预览。
  Timetable? _preview;
  String? _previewError;
  String? _previewSource;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 导出

  String _fileStamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
  }

  String _buildJson(Timetable timetable) => _repo.exportToJsonText(timetable);

  Future<void> _exportToFile(Timetable timetable) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final jsonText = _buildJson(timetable);
      final fileName = '课表备份_${_fileStamp()}.json';
      final uri = await FilePicker.saveFile(
        dialogTitle: '导出课表 JSON',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
        // 插件会把 bytes 直接写入用户选定的位置（Android/iOS 必需）；
        // Windows 上我们再按返回的路径补写一次（见下）。
        bytes: Uint8List.fromList(utf8.encode(jsonText)),
      );
      if (uri == null) {
        // 用户取消
        return;
      }
      final path = uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
      // Windows 的保存对话框一般会自己带上扩展名，但用户可能手动删掉，兜一下。
      final target = path.toLowerCase().endsWith('.json') ? path : '$path.json';
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await _repo.exportToFile(timetable, target);
      }
      if (!mounted) return;
      _toast('已导出到 $target');
    } catch (e) {
      if (!mounted) return;
      _toast('导出失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToClipboard(Timetable timetable) async {
    try {
      await Clipboard.setData(ClipboardData(text: _buildJson(timetable)));
      if (!mounted) return;
      _toast('课表 JSON 已复制到剪贴板（${timetable.courses.length} 门课程）');
    } catch (e) {
      if (!mounted) return;
      _toast('复制失败：$e', error: true);
    }
  }

  // ------------------------------------------------------------------ 导入

  /// 从文件读取文本：优先进程内路径，拿不到再退回 bytes（Android 常见）。
  Future<void> _pickFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择课表 JSON 文件',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      String? text;
      // 能拿到本地路径就直接读文件，否则退回读字节（Android 常见）
      final path = file.path;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) text = await f.readAsString();
      }
      if (text == null || text.trim().isEmpty) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          text = utf8.decode(bytes, allowMalformed: true);
        }
      }
      if (text == null || text.trim().isEmpty) {
        _toast('文件是空的或无法读取', error: true);
        return;
      }
      _textCtrl.text = text;
      _parseText(text, source: file.name);
    } catch (e) {
      if (!mounted) return;
      _toast('读取文件失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        if (!mounted) return;
        _toast('剪贴板里没有文本', error: true);
        return;
      }
      _textCtrl.text = text;
      _parseText(text, source: '剪贴板');
    } catch (e) {
      if (!mounted) return;
      _toast('读取剪贴板失败：$e', error: true);
    }
  }

  /// 解析文本并展示预览。解析失败只提示，不改动现有数据。
  void _parseText(String text, {String? source}) {
    try {
      final t = _repo.importFromJsonText(text);
      setState(() {
        _preview = t;
        _previewError = null;
        _previewSource = source;
      });
      _showPreviewDialog(t, source);
    } catch (e) {
      setState(() {
        _preview = null;
        _previewError = e.toString();
        _previewSource = source;
      });
      _toast('解析失败：$e', error: true);
    }
  }

  Future<void> _showPreviewDialog(Timetable preview, String? source) async {
    final action = await showDialog<_ImportAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解析成功'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (source != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('来源：$source', style: Theme.of(ctx).textTheme.bodySmall),
                ),
              _kv(ctx, '学期', preview.semester.name),
              _kv(ctx, '起始', _fmtDate(preview.semester.startMonday)),
              _kv(ctx, '总周数', '${preview.semester.totalWeeks} 周'),
              _kv(ctx, '课程', '${preview.courses.length} 门'),
              _kv(ctx, '时段', '${preview.sessionCount} 个'),
              _kv(ctx, '作息', '${preview.timeSlots.length} 节'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '「覆盖导入」会用这份数据替换当前全部课表（含学期与作息）。\n'
                  '「合并导入」只把课程追加进来，学期与作息保持当前设置。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_ImportAction.merge),
            child: const Text('合并导入'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(_ImportAction.replace),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == _ImportAction.replace) {
      await _replaceImport(preview);
    } else {
      await _mergeImport(preview);
    }
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              k,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(v, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  Future<void> _replaceImport(Timetable preview) async {
    final ok = await _confirm(
      title: '确认覆盖当前课表？',
      message: '当前 ${_currentSummary()} 将被删除，替换为「${preview.semester.name}」'
          '的 ${preview.courses.length} 门课程。\n\n此操作不可撤销。',
      confirmText: '覆盖导入',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(timetableProvider.notifier).replaceTimetable(preview);
      if (!mounted) return;
      _toast('已覆盖导入 ${preview.courses.length} 门课程');
      setState(() => _preview = null);
    } catch (e) {
      if (!mounted) return;
      _toast('导入失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mergeImport(Timetable preview) async {
    final current = ref.read(timetableProvider).valueOrNull;
    if (current == null) {
      _toast('当前课表尚未加载', error: true);
      return;
    }
    // 合并时重新分配 id，避免与现有课程冲突；学期统一用当前的。
    final courses = preview.courses
        .map(
          (c) => Course(
            id: newId(),
            semesterId: current.semester.id,
            name: c.name,
            teacher: c.teacher,
            courseCode: c.courseCode,
            credit: c.credit,
            note: c.note,
            colorIndex: c.colorIndex,
            sessions: c.sessions
                .map(
                  (s) => Session(
                    id: newId(),
                    dayOfWeek: s.dayOfWeek,
                    startPeriod: s.startPeriod,
                    endPeriod: s.endPeriod,
                    weeks: s.weeks,
                    location: s.location,
                    teacher: s.teacher,
                  ),
                )
                .toList(),
            adjustments: const [],
          ),
        )
        .toList();

    if (courses.isEmpty) {
      _toast('这份数据里没有课程');
      return;
    }

    final ok = await _confirm(
      title: '确认合并导入？',
      message: '将把 ${courses.length} 门课程追加到当前课表'
          '（当前已有 ${current.courses.length} 门）。\n\n同名课程不会被去重，请自行确认。',
      confirmText: '合并导入',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(timetableProvider.notifier).addCourses(courses);
      if (!mounted) return;
      _toast('已合并导入 ${courses.length} 门课程');
      setState(() => _preview = null);
    } catch (e) {
      if (!mounted) return;
      _toast('合并失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _currentSummary() {
    final t = ref.read(timetableProvider).valueOrNull;
    if (t == null) return '课表';
    return '${t.courses.length} 门课程 / ${t.sessionCount} 个时段';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final asyncTimetable = ref.watch(timetableProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入 / 导出'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: asyncTimetable.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('读取课表失败：$e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(timetableProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (timetable) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            _buildSummaryCard(context, timetable),
            const SizedBox(height: 12),
            _buildExportCard(context, timetable),
            const SizedBox(height: 12),
            _buildImportCard(context),
            const SizedBox(height: 12),
            _buildAdvancedCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, Timetable timetable) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '当前课表',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${timetable.semester.name} · ${_fmtDate(timetable.semester.startMonday)} 起 · '
              '${timetable.semester.totalWeeks} 周',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${timetable.courses.length} 门课程 / ${timetable.sessionCount} 个时段 / '
              '${timetable.timeSlots.length} 节作息',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportCard(BuildContext context, Timetable timetable) {
    final theme = Theme.of(context);
    final json = _buildJson(timetable);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(context, Icons.ios_share, '导出', '备份成 JSON，可在另一台设备导入'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _exportToFile(timetable),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导出为 JSON 文件'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _copyToClipboard(timetable),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('复制到剪贴板'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '文件内容约 ${(json.length / 1024).toStringAsFixed(1)} KB，'
              '包含学期、作息与全部课程（含调课记录）。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(context, Icons.file_upload_outlined, '导入', '支持文件与剪贴板，导入前会先预览'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: const Text('选择 JSON 文件'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_outlined, size: 18),
                  label: const Text('从剪贴板导入'),
                ),
              ],
            ),
            if (_previewError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '上次解析失败：$_previewError',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '已解析：${_preview!.semester.name} · ${_preview!.courses.length} 门课程'
                        ' · ${_preview!.sessionCount} 个时段',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showPreviewDialog(_preview!, _previewSource),
                      child: const Text('再次导入'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '支持本 App 导出的 JSON；也兼容只含 courses / semester 字段的手写 JSON。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
              child: Row(
                children: [
                  Icon(Icons.code, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '手动粘贴 / 编辑 JSON',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(_advancedOpen ? Icons.expand_less : Icons.expand_more, size: 20),
                ],
              ),
            ),
            if (_advancedOpen) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _textCtrl,
                minLines: 8,
                maxLines: 16,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '在此粘贴课表 JSON，然后点「解析」',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final text = _textCtrl.text.trim();
                      if (text.isEmpty) {
                        _toast('请先粘贴 JSON 文本', error: true);
                        return;
                      }
                      _parseText(text, source: '手动输入');
                    },
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: const Text('解析'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _textCtrl.clear();
                      _preview = null;
                      _previewError = null;
                    }),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('清空'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cardTitle(BuildContext context, IconData icon, String title, String subtitle) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
      ],
    );
  }

  // ------------------------------------------------------------------ 工具

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
          duration: Duration(seconds: error ? 5 : 3),
        ),
      );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Theme.of(ctx).colorScheme.error),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

enum _ImportAction { replace, merge }