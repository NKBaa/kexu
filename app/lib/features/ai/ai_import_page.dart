import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/course.dart';
import '../../data/models/draft.dart';
import '../settings/providers/settings_provider.dart';
import '../timetable/providers/timetable_provider.dart';
import 'ai_client.dart';
import 'ai_client_provider.dart';
import 'ai_exception.dart';
import 'draft_duplicates.dart';
import 'image_date_filter.dart';
import 'image_to_timetable.dart';

/// 「图片转课表」页面。
///
/// 完整流程：选图（可多选/追加）→ 大模型识别 → 草稿预览（可逐门勾选）→ 确认导入。
/// 关键设计：
/// - **识别结果不直接落库**，必须先经过用户确认，因为视觉模型对课表这种密集表格
///   难免出错，让用户过一眼再入库才安全；
/// - **支持多张图片**：分页截图、单周/双周两张截图可以一次选完、一次识别，
///   由 [ImageToTimetableService.parseImages] 在客户端跨图合并。
class AiImportPage extends ConsumerStatefulWidget {
  const AiImportPage({super.key});

  @override
  ConsumerState<AiImportPage> createState() => _AiImportPageState();
}

class _AiImportPageState extends ConsumerState<AiImportPage> {
  /// 已选择的图片（一次多选或分多次追加）。
  final List<AiImageAttachment> _images = <AiImageAttachment>[];

  /// 单次识别最多选择的图片张数：再多请求体过大，视觉模型也容易漏看。
  static const int _maxImages = 9;

  bool _recognizing = false;
  bool _importing = false;
  String? _error;

  /// 批次级告警（如「第 2 批（第 5-6 张）识别失败：……」），
  /// 来自 [ImageParseResult.warnings]，与每门课自己的 warnings 分开显示。
  List<String> _warnings = const [];

  /// 识别出的草稿课程，以及每门课是否被勾选。
  List<DraftCourse> _drafts = const [];
  final Set<int> _selected = <int>{};

  final TextEditingController _hintCtrl = TextEditingController();

  @override
  void dispose() {
    _hintCtrl.dispose();
    super.dispose();
  }

  /// 选择图片。[append] 为 true 时追加到已有列表，否则清空后重选。
  Future<void> _pickImages({required bool append}) async {
    if (_recognizing) return;
    setState(() => _error = null);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择课表截图（可多选）',
        type: FileType.image,
      );
      if (files.isEmpty) return;

      final room = _maxImages - (append ? _images.length : 0);
      if (room <= 0) {
        setState(() => _error = '最多支持 $_maxImages 张图片，请先删掉一些再添加。');
        return;
      }

      final picked = <AiImageAttachment>[];
      for (final file in files) {
        if (picked.length >= room) break;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        picked.add(AiImageAttachment(
          bytes: bytes,
          mimeType: file.extension,
          name: file.name,
        ));
      }
      if (picked.isEmpty) {
        setState(() => _error = '无法读取所选图片，请换一张试试。');
        return;
      }

      final skipped = files.length - picked.length;
      setState(() {
        if (append) {
          _images.addAll(picked);
        } else {
          _images
            ..clear()
            ..addAll(picked);
        }
        _drafts = const [];
        _selected.clear();
        _warnings = const [];
        _error = skipped > 0
            ? '已选择 ${picked.length} 张图片；最多支持 $_maxImages 张，其余 $skipped 张未加入。'
            : null;
      });
    } catch (e) {
      setState(() => _error = '选择图片失败：$e');
    }
  }

  /// 删除第 [index] 张图片。
  void _removeImage(int index) {
    if (_recognizing) return;
    if (index < 0 || index >= _images.length) return;
    setState(() {
      _images.removeAt(index);
      // 图片变了，旧识别结果不再对应，清掉避免误导入。
      _drafts = const [];
      _selected.clear();
      _warnings = const [];
      _error = null;
    });
  }

  Future<void> _recognize() async {
    if (_images.isEmpty) return;

    final settings = await ref.read(settingsProvider.future);
    final config = settings.aiConfig;
    if (!config.visionConfigured) {
      setState(() => _error = '还没有配置视觉模型。图片转课表需要能看图的模型，请到「设置 → 大模型配置 → 视觉模型」里填写。');
      return;
    }

    setState(() {
      _recognizing = true;
      _error = null;
      _drafts = const [];
      _selected.clear();
      _warnings = const [];
    });

    try {
      final timetable = ref.read(timetableProvider).valueOrNull;
      final totalWeeks = timetable?.semester.totalWeeks ?? 16;
      final client = ref.read(visionAiClientProvider);
      final service = ImageToTimetableService(client: client);
      final result = await service.parseImages(
        List<AiImageAttachment>.of(_images),
        totalWeeks: totalWeeks,
        extraHint: _hintCtrl.text.trim().isEmpty ? null : _hintCtrl.text.trim(),
      );
      final filtered = filterDraftsByImageDate(
        courses: result.courses,
        date: result.detectedDate,
        semesterStartMonday:
            timetable?.semester.startMonday ?? DateTime.now(),
        totalWeeks: totalWeeks,
      );

      if (!mounted) return;
      setState(() {
        _drafts = filtered.courses;
        _warnings = [...result.warnings, ...filtered.warnings];
        _selected
          ..clear()
          ..addAll(
            List<int>.generate(filtered.courses.length, (i) => i)
                .where((i) => filtered.courses[i].isValid),
          );
        _recognizing = false;
        if (filtered.courses.isEmpty) {
          _error = result.detectedDate != null
              ? '图片是单日课表，但没有识别出该日期当天的课程。请核对图片日期或换图重试。'
              : '模型没有识别出任何课程。可以补充「学校/学期」等提示后重试，或换用视觉能力更强的模型。';
        }
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recognizing = false;
        _error = '识别失败：$e';
      });
    }
  }

  Future<void> _importSelected() async {
    final timetable = ref.read(timetableProvider).valueOrNull;
    if (timetable == null) return;

    final picked = <DraftCourse>[
      for (var i = 0; i < _drafts.length; i++)
        if (_selected.contains(i)) _drafts[i],
    ];
    if (picked.isEmpty) {
      setState(() => _error = '请至少勾选一门课程。');
      return;
    }

    final duplicateIndices = duplicateDraftIndices(
      drafts: _drafts,
      selected: _selected,
      existingCourses: timetable.courses,
    );
    _DuplicateAction? duplicateAction;
    if (duplicateIndices.isNotEmpty) {
      duplicateAction = await _askDuplicateAction(duplicateIndices);
      if (duplicateAction == null || !mounted) return;
    }

    setState(() {
      _importing = true;
      _error = null;
    });

    // 颜色尽量与已有课程错开
    final used = {for (final c in timetable.courses) c.colorIndex};
    var color = 0;
    final imported = <Course>[];
    for (final d in picked) {
      while (used.contains(color)) {
        color++;
      }
      used.add(color);
      imported.add(draftToCourse(d, timetable.semester.id, colorIndex: color));
      color++;
    }
    // 同一次识别可能给出同名课程；先合并，覆盖导入时只保留一门。
    final courses = mergeIncomingCourses(imported);

    if (duplicateAction == _DuplicateAction.overwrite) {
      final nextCourses = overwriteCoursesByName(
        existing: timetable.courses,
        incoming: courses,
      );
      await ref.read(timetableProvider.notifier).replaceTimetable(
            timetable.copyWith(courses: nextCourses),
          );
    } else {
      await ref.read(timetableProvider.notifier).addCourses(courses);
    }

    if (!mounted) return;
    setState(() => _importing = false);
    final message = duplicateAction == _DuplicateAction.overwrite
        ? '已覆盖并导入 ${courses.length} 门课程'
        : '已导入 ${courses.length} 门课程';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  Future<_DuplicateAction?> _askDuplicateAction(List<int> duplicateIndices) {
    final theme = Theme.of(context);
    final names = duplicateIndices.take(6).map((i) => _drafts[i].name).toList();
    final more = duplicateIndices.length > names.length;
    return showDialog<_DuplicateAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('ai_import_duplicate_dialog'),
        title: Text('发现 ${duplicateIndices.length} 门已导入课程'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('这些课程已经在课表里：'),
            const SizedBox(height: 6),
            for (final name in names)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('· $name', style: theme.textTheme.bodySmall),
              ),
            if (more)
              Text('…等 ${duplicateIndices.length} 门', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            const Text('要覆盖已有课程，还是保留两份同时存在？'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('ai_import_keep_both'),
            onPressed: () => Navigator.pop(ctx, _DuplicateAction.keepBoth),
            child: const Text('同时存在'),
          ),
          FilledButton(
            key: const Key('ai_import_overwrite'),
            onPressed: () => Navigator.pop(ctx, _DuplicateAction.overwrite),
            child: const Text('覆盖已有'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _images.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片转课表'),
        actions: [
          if (_drafts.isNotEmpty)
            TextButton.icon(
              onPressed: _importing ? null : _importSelected,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done),
              label: Text('导入 ${_selected.length} 门'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildIntro(),
          const SizedBox(height: 12),
          _buildImageArea(),
          const SizedBox(height: 12),
          _buildHintField(),
          const SizedBox(height: 12),
          _buildActionBar(hasImage),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _buildError(_error!),
          ],
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildWarnings(),
          ],
          if (_recognizing) ...[
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('正在识别 ${_images.length} 张图片…视觉模型通常需要 5~30 秒'),
                ],
              ),
            ),
          ],
          if (_drafts.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildDraftHeader(),
            const SizedBox(height: 8),
            for (var i = 0; i < _drafts.length; i++) _buildDraftTile(i),
          ],
        ],
      ),
    );
  }

  Widget _buildIntro() {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('ai_import_intro'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
          leading: Icon(
            Icons.tips_and_updates_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text('使用说明', style: theme.textTheme.titleSmall),
          subtitle: Text(
            '支持多选；分页、单双周截图会自动合并',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          children: const [
            Text(
              '上传教务系统截图或课表照片（可一次多选），大模型会自动识别课程名、教师、'
              '上课时间、周次与地点。分页截图、单周/双周两张截图会自动合并成一份课表。'
              '如果截图是带日期的单日课表，只会导入该日期当天的课程。'
              '识别结果会先展示出来供你核对，确认后再写入课表。',
            ),
          ],
        ),
      ),
    );
  }

  /// 图片区：没选图时是点击区，选了图后是横向缩略图列表（可删除、可继续追加）。
  Widget _buildImageArea() {
    final theme = Theme.of(context);
    if (_images.isEmpty) {
      return InkWell(
        onTap: _recognizing ? null : () => _pickImages(append: false),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              const Text('点击选择课表截图（可多选）'),
              const SizedBox(height: 4),
              Text(
                '支持 PNG / JPG / WebP，最多 $_maxImages 张',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '已选择 ${_images.length} 张图片（最多 $_maxImages 张）',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => _buildThumb(index),
          ),
        ),
      ],
    );
  }

  Widget _buildThumb(int index) {
    final theme = Theme.of(context);
    final image = _images[index];
    return SizedBox(
      width: 108,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    child: Image.memory(
                      image.bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    tooltip: '删除这张图片',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _recognizing ? null : () => _removeImage(index),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            image.name ?? '图片 ${index + 1}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildHintField() {
    return TextField(
      controller: _hintCtrl,
      decoration: const InputDecoration(
        labelText: '补充说明（可选）',
        hintText: '例如：这是 2026 春季学期，第 1 周从 2 月 23 日开始，共 16 周',
        prefixIcon: Icon(Icons.edit_note_outlined),
      ),
      maxLines: 2,
      minLines: 1,
      textInputAction: TextInputAction.done,
    );
  }

  Widget _buildActionBar(bool hasImage) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _recognizing ? null : () => _pickImages(append: false),
          icon: const Icon(Icons.image_outlined),
          label: Text(hasImage ? '清空重选' : '选择图片'),
        ),
        if (hasImage)
          OutlinedButton.icon(
            onPressed: _recognizing ? null : () => _pickImages(append: true),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('添加图片'),
          ),
        FilledButton.icon(
          onPressed: (!hasImage || _recognizing) ? null : _recognize,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('开始识别'),
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  /// 批次级告警：部分图片识别失败时，成功的批次照常展示，这里说明哪批没成功。
  Widget _buildWarnings() {
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: onColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('部分图片识别失败', style: TextStyle(color: onColor)),
                const SizedBox(height: 4),
                for (final w in _warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '· $w',
                      style: theme.textTheme.bodySmall?.copyWith(color: onColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftHeader() {
    final allSelected = _selected.length == _drafts.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            '识别结果（${_drafts.length} 门）',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            if (allSelected) {
              _selected.clear();
            } else {
              _selected
                ..clear()
                ..addAll(List<int>.generate(_drafts.length, (i) => i));
            }
          }),
          child: Text(allSelected ? '全不选' : '全选'),
        ),
      ],
    );
  }

  Widget _buildDraftTile(int index) {
    final d = _drafts[index];
    final theme = Theme.of(context);
    final checked = _selected.contains(index);
    final existingNames = existingCourseNameKeys(
      ref.read(timetableProvider).valueOrNull?.courses ?? const [],
    );
    final wasImported = existingNames.contains(normalizeCourseName(d.name));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: checked,
        onChanged: d.isValid
            ? (v) => setState(() {
                  if (v == true) {
                    _selected.add(index);
                  } else {
                    _selected.remove(index);
                  }
                })
            : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: CoursePalette.of(index),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                d.name.isEmpty ? '（未识别到课程名）' : d.name,
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (wasImported) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '已导入',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (d.teacher != null)
              Text(d.teacher!, style: theme.textTheme.bodySmall),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (d.sessions.isEmpty)
              Text('无有效时段', style: TextStyle(color: theme.colorScheme.error))
            else
              for (final s in d.sessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· ${s.describe()}'),
                ),
            if (d.warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  d.warnings.join('；'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
        isThreeLine: d.sessions.length > 1,
      ),
    );
  }
}

enum _DuplicateAction { keepBoth, overwrite }
