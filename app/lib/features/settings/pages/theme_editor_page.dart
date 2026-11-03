import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/app_theme_spec.dart';
import 'semester_settings_page.dart' show SettingsSubPage;

/// 主题代码编辑器：用 JSON 描述色板与圆角，保存后回到主题中心。
class ThemeEditorPage extends StatefulWidget {
  const ThemeEditorPage({super.key, this.initial});

  final AppThemeSpec? initial;

  @override
  State<ThemeEditorPage> createState() => _ThemeEditorPageState();
}

class _ThemeEditorPageState extends State<ThemeEditorPage> {
  late final TextEditingController _controller;
  AppThemeSpec? _preview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial?.code ?? AppThemeSpec.template,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  AppThemeSpec? _parse() {
    try {
      final spec = AppThemeSpec.fromCode(_controller.text);
      if (AppThemeSpec.builtIns.any((t) => t.id == spec.id)) {
        throw FormatException('id「${spec.id}」是内置主题，请换一个 id');
      }
      setState(() {
        _preview = spec;
        _error = null;
      });
      return spec;
    } on FormatException catch (e) {
      setState(() {
        _preview = null;
        _error = e.message;
      });
      return null;
    } catch (e) {
      setState(() {
        _preview = null;
        _error = '$e';
      });
      return null;
    }
  }

  void _save() {
    final spec = _parse();
    if (spec == null) return;
    Navigator.of(context).pop(spec);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return SettingsSubPage(
      title: widget.initial == null ? '新建主题' : '编辑主题',
      subtitle: '用 JSON 写色板与圆角，点「预览」可先看效果；保存后可在主题中心应用',
      actions: [
        TextButton(
          key: const Key('theme_editor_save'),
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.code, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '主题代码（JSON）',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        key: const Key('theme_editor_template'),
                        onPressed: () => _controller.text = AppThemeSpec.template,
                        child: const Text('插入模板'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('theme_editor_code'),
                    controller: _controller,
                    minLines: 14,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                    ),
                    decoration: const InputDecoration(
                      hintText: '在这里写 JSON 主题代码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonalIcon(
                        key: const Key('theme_editor_preview'),
                        onPressed: _parse,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('预览'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('theme_editor_save_button'),
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('保存并返回'),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: 12),
            Text(
              '预览',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Theme(
              data: AppTheme.custom(preview, Brightness.light),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preview.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview.description.isEmpty
                            ? '自定义主题'
                            : preview.description,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          _Swatch(color: preview.light.seedColor, label: '主色'),
                          _Swatch(color: preview.light.surfaceColor, label: '背景'),
                          _Swatch(color: preview.light.cardColor, label: '卡片'),
                          _Swatch(color: preview.light.inkColor, label: '文字'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('示例按钮'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
