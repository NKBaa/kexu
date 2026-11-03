import 'package:flutter/material.dart';

import '../../../core/widgets/hint_icon.dart';
import '../../../data/models/ai_config.dart';
import '../../../data/models/ai_model_catalog.dart';
import '../../ai/ai_client.dart';
import '../../ai/ai_exception.dart';

/// AI 配置表单：预设选择 + baseUrl / apiKey / model + 温度 / 超时 + 测试连接。
///
/// 设计要点：
/// - 顶部下拉由 [aiProviderPresets] 生成；选预设会自动填入 baseUrl 与 model，
///   但用户仍可任意手改（因此保存时以输入框为准，不反向覆盖）。
/// - apiKey 默认遮蔽，可一键显示。
/// - 「测试连接」直接调用 [AiClient] 发一句「你好」，把成功/失败结果就地展示，
///   失败时按 [AiException] 分类给出可操作的中文建议。
///
/// 本控件不依赖任何状态管理：由父级传入 [initial] 与 [onSave]（设置页负责接
/// `aiConfigProvider`），便于单独复用与测试。
class AiModelSectionForm extends StatefulWidget {
  const AiModelSectionForm({
    super.key,
    required this.isVision,
    required this.initial,
    required this.onSave,
    this.enabled = true,
    this.showHeader = true,
    this.clientFactory,
    this.catalogModels = builtInModels,
  });

  /// true = 视觉模型分区；false = 语言模型分区。
  final bool isVision;

  final AiModelConfig initial;

  /// 保存回调：设置页里接 `ref.read(aiConfigProvider.notifier).save(cfg)`。
  final Future<void> Function(AiModelConfig config) onSave;

  final bool enabled;

  /// 独立配置页已经展示标题时，可隐藏表单内部重复的标题。
  final bool showHeader;

  /// 测试用：注入假的 [AiClient]；生产环境为空，内部自己创建。
  final AiClient Function(AiModelConfig config)? clientFactory;

  /// 模型能力名单：默认内置；设置页会传入 GitHub/缓存版本。
  /// 只用于给「获取模型列表」里同名模型标注能力，不提供单独的选择入口。
  final List<AiModelInfo> catalogModels;

  @override
  State<AiModelSectionForm> createState() => AiModelSectionFormState();
}

class AiModelSectionFormState extends State<AiModelSectionForm> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  final FocusNode _baseUrlFocus = FocusNode();
  final FocusNode _apiKeyFocus = FocusNode();
  final FocusNode _modelFocus = FocusNode();

  double _temperature = 0.2;
  int _timeoutSeconds = 120;
  bool _obscureKey = true;
  String _presetId = 'custom';

  bool _saving = false;
  bool _testing = false;

  /// 测试连接结果（null 表示还没测过）。
  bool? _testOk;
  String? _testMessage;
  String? _testDetail;

  /// 服务端返回的模型列表（打开页面自动获取 / 点按钮刷新）。
  List<String> _models = const <String>[];
  bool _loadingModels = false;
  String? _modelsError;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(text: widget.initial.baseUrl);
    _apiKeyCtrl = TextEditingController(text: widget.initial.apiKey);
    _modelCtrl = TextEditingController(text: widget.initial.model);
    _temperature = widget.initial.temperature.clamp(0.0, 1.0);
    _timeoutSeconds = widget.initial.timeoutSeconds > 0 ? widget.initial.timeoutSeconds : 120;
    _presetId = _guessPresetId(widget.initial.baseUrl);

    // 打开页面时若已有地址与 Key，静默拉一次模型列表：
    // 模型名不用再手填，下拉里直接选（失败也不打扰用户，可手动点刷新）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cfg = _draftConfig();
      if (cfg.baseUrl.trim().isNotEmpty && cfg.apiKey.trim().isNotEmpty) {
        _fetchModels(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AiModelSectionForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部配置变了（例如从别的页面保存后回来），且用户没在编辑时同步。
    if (oldWidget.initial.baseUrl != widget.initial.baseUrl && !_baseUrlFocus.hasFocus) {
      _baseUrlCtrl.text = widget.initial.baseUrl;
    }
    if (oldWidget.initial.apiKey != widget.initial.apiKey && !_apiKeyFocus.hasFocus) {
      _apiKeyCtrl.text = widget.initial.apiKey;
    }
    if (oldWidget.initial.model != widget.initial.model && !_modelFocus.hasFocus) {
      _modelCtrl.text = widget.initial.model;
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _baseUrlFocus.dispose();
    _apiKeyFocus.dispose();
    _modelFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 工具

  static String _normalize(String s) {
    var v = s.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v.toLowerCase();
  }

  /// 根据当前 baseUrl 猜用户选的是哪个预设（用于让下拉显示得「对」）。
  String _guessPresetId(String baseUrl) {
    final target = _normalize(baseUrl);
    if (target.isEmpty) return 'custom';
    for (final p in aiProviderPresets) {
      if (p.defaultBaseUrl.isEmpty) continue;
      if (_normalize(p.defaultBaseUrl) == target) return p.id;
    }
    return 'custom';
  }

  AiProviderPreset? get _currentPreset {
    for (final p in aiProviderPresets) {
      if (p.id == _presetId) return p;
    }
    return null;
  }

  /// 当前输入框里的配置（测试连接与保存都用它，而不是 widget.initial）。
  AiModelConfig _draftConfig() => AiModelConfig(
        baseUrl: _baseUrlCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
        temperature: _temperature,
        timeoutSeconds: _timeoutSeconds,
      );

  void _applyPreset(String? id) {
    if (id == null) return;
    final preset = aiProviderPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => aiProviderPresets.last,
    );
    setState(() {
      _presetId = preset.id;
      // 「自定义」不覆盖用户已填内容；其它预设覆盖 baseUrl/model，Key 保留。
      if (preset.id != 'custom') {
        if (preset.defaultBaseUrl.isNotEmpty) _baseUrlCtrl.text = preset.defaultBaseUrl;
        final presetModel = widget.isVision ? preset.visionModel : preset.textModel;
        if (presetModel.isNotEmpty) _modelCtrl.text = presetModel;
      }
      _testOk = null;
      _testMessage = null;
      _testDetail = null;
    });
  }

  void _resetTestResult() {
    if (_testOk == null && _testMessage == null) return;
    setState(() {
      _testOk = null;
      _testMessage = null;
      _testDetail = null;
    });
  }

  // ------------------------------------------------------------------ 动作

  Future<void> _testConnection() async {
    if (_testing) return;
    final cfg = _draftConfig();
    if (cfg.baseUrl.isEmpty || cfg.model.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = '请先填写服务地址（baseUrl）与模型名（model）。';
        _testDetail = null;
      });
      return;
    }
    if (!cfg.isConfigured) {
      setState(() {
        _testOk = false;
        _testMessage = '配置不完整：非本地服务需要填写 API Key。';
        _testDetail = cfg.chatCompletionsUrl;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testOk = null;
      _testMessage = null;
      _testDetail = null;
    });

    final client = _createClient(cfg);
    try {
      final reply = await client.chatText(
        '你好',
        system: '你是连通性测试助手，请只回复“连接成功”四个字。',
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMessage = '连接成功，模型返回：${_shorten(reply)}';
        _testDetail = cfg.chatCompletionsUrl;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = e.message;
        _testDetail = e.detail;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMessage = '测试失败：$e';
        _testDetail = cfg.chatCompletionsUrl;
      });
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  static String _shorten(String s, {int max = 120}) {
    final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  /// 创建客户端：测试可注入假实现，生产环境走真实 HTTP。
  AiClient _createClient(AiModelConfig cfg) =>
      widget.clientFactory?.call(cfg) ?? AiClient(config: cfg);

  /// 自动获取服务端模型列表（`GET {baseUrl}/models`）。
  ///
  /// [silent] 为 true 时不弹错误提示（用于打开页面时的静默预取）。
  Future<void> _fetchModels({bool silent = false}) async {
    if (_loadingModels) return;
    final cfg = _draftConfig();
    if (cfg.baseUrl.trim().isEmpty) {
      if (!silent) setState(() => _modelsError = '请先填写服务地址（baseUrl）');
      return;
    }

    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });

    final client = _createClient(cfg);
    try {
      final models = await client.listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已获取 ${models.length} 个模型，可在下方选择')),
        );
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _modelsError = e.message;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (!mounted) return;
      final message = '获取模型列表失败：$e';
      setState(() {
        _loadingModels = false;
        _modelsError = message;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      client.dispose();
    }
  }

  void _pickModel(String model) {
    setState(() {
      _modelCtrl.text = model;
      _modelsError = null;
    });
    _resetTestResult();
    _modelFocus.unfocus();
  }

  Future<void> _openModelPicker() async {
    if (_models.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ModelPickerSheet(
        models: _models,
        selected: _modelCtrl.text.trim(),
        catalogModels: widget.catalogModels,
      ),
    );
    if (picked != null && mounted) _pickModel(picked);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_draftConfig());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preset = _currentPreset;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader) ...[
            Row(
              children: [
                Text(
                  widget.isVision ? '视觉模型（图片转课表）' : '语言模型（一句话改课表）',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 2),
                HintIcon(
                  message: [
                    widget.isVision
                        ? '必须是能看图的模型，如 glm-4v-flash / qwen-vl-max / gpt-4o-mini。'
                        : '纯文本任务，可用更便宜的模型，如 deepseek-chat / glm-4-flash。',
                    if (preset != null && preset.note.isNotEmpty) preset.note,
                  ].join('\n\n'),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          DropdownButtonFormField<String>(
            initialValue: _presetId,
            isDense: true,
            // 手机窄屏下预设名（如「自定义（任意 OpenAI 兼容服务）」）较长：
            // isExpanded 让下拉占满可用宽度，配合省略号避免文字顶出边框。
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: '服务商预设',
              prefixIcon: Icon(Icons.hub_outlined, size: 18),
            ),
            selectedItemBuilder: (context) => [
              for (final p in aiProviderPresets)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    p.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            items: [
              for (final p in aiProviderPresets)
                DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.supportsVision)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.image_outlined, size: 14),
                        ),
                      Flexible(child: Text(p.label, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
            ],
            onChanged: widget.enabled ? _applyPreset : null,
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          TextFormField(
            controller: _baseUrlCtrl,
            focusNode: _baseUrlFocus,
            enabled: widget.enabled,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onChanged: (_) => _resetTestResult(),
            onFieldSubmitted: (_) => _apiKeyFocus.requestFocus(),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return '请填写服务地址';
              final uri = Uri.tryParse(s);
              if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
                return '需以 http:// 或 https:// 开头';
              }
              return null;
            },
            decoration: const InputDecoration(
              isDense: true,
              labelText: '服务地址 baseUrl',
              hintText: 'https://api.deepseek.com/v1',
              prefixIcon: Icon(Icons.link, size: 18),
              suffixIcon: HintIcon(
                message: '不带 /chat/completions，程序会自动补全。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _apiKeyCtrl,
            focusNode: _apiKeyFocus,
            enabled: widget.enabled,
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _resetTestResult(),
            onFieldSubmitted: (_) => _modelFocus.requestFocus(),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'API Key',
              prefixIcon: const Icon(Icons.key_outlined, size: 18),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HintIcon(
                    message: '本地服务（Ollama 等）可留空 API Key。',
                  ),
                  IconButton(
                    tooltip: _obscureKey ? '显示' : '隐藏',
                    icon: Icon(
                      _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                  if (_apiKeyCtrl.text.isNotEmpty)
                    IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: widget.enabled
                          ? () {
                              _apiKeyCtrl.clear();
                              _resetTestResult();
                              setState(() {});
                            }
                          : null,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _modelCtrl,
            focusNode: _modelFocus,
            enabled: widget.enabled,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              _resetTestResult();
              setState(() {});
            },
            onFieldSubmitted: (_) {
              _modelFocus.unfocus();
              _save();
            },
            validator: (v) => (v ?? '').trim().isEmpty ? '请填写模型名' : null,
            decoration: InputDecoration(
              isDense: true,
              labelText: '模型名 model',
              hintText: 'deepseek-chat / glm-4v-flash / qwen-vl-max',
              prefixIcon: const Icon(Icons.memory_outlined, size: 18),
              suffixIcon: _loadingModels
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const HintIcon(
                          message: '可点右侧按钮自动获取服务端模型列表。',
                        ),
                        IconButton(
                          key: const ValueKey('ai_model_fetch_button'),
                          tooltip: '自动获取模型列表',
                          icon: const Icon(Icons.cloud_download_outlined, size: 18),
                          onPressed: widget.enabled ? () => _fetchModels() : null,
                        ),
                      ],
                    ),
            ),
          ),
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('ai_model_list_button'),
                onPressed: _openModelPicker,
                icon: const Icon(Icons.list_alt, size: 16),
                label: Text('选择模型（已获取 ${_models.length} 个）'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          if (_modelsError != null) ...[
            const SizedBox(height: 4),
            Text(
              _modelsError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildAdvanced(context),
          const SizedBox(height: 8),
          _buildRequestUrlPreview(context),
          if (_testMessage != null) ...[
            const SizedBox(height: 10),
            _buildTestResult(context),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: widget.enabled && !_testing ? _testConnection : null,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_testing ? '测试中…' : '测试连接'),
              ),
              FilledButton.icon(
                onPressed: widget.enabled && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? '保存中…' : '保存这套配置'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvanced(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text('高级参数', style: theme.textTheme.bodyMedium),
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        Row(
          children: [
            SizedBox(
              width: 96,
              child: Row(
                children: [
                  Text('温度', style: theme.textTheme.bodySmall),
                  const HintIcon(
                    message: '课表结构化任务建议 0~0.3，越低越稳定。',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Slider(
                value: _temperature,
                min: 0,
                max: 1,
                divisions: 20,
                label: _temperature.toStringAsFixed(2),
                onChanged: widget.enabled
                    ? (v) => setState(() => _temperature = v)
                    : null,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _temperature.toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  Text('超时（秒）', style: theme.textTheme.bodySmall),
                  const HintIcon(
                    message: '视觉模型（图片转课表）建议 ≥120 秒。',
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 100,
              child: DropdownButtonFormField<int>(
                initialValue: const [30, 60, 90, 120, 180, 300].contains(_timeoutSeconds)
                    ? _timeoutSeconds
                    : 120,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30')),
                  DropdownMenuItem(value: 60, child: Text('60')),
                  DropdownMenuItem(value: 90, child: Text('90')),
                  DropdownMenuItem(value: 120, child: Text('120')),
                  DropdownMenuItem(value: 180, child: Text('180')),
                  DropdownMenuItem(value: 300, child: Text('300')),
                ],
                onChanged: widget.enabled
                    ? (v) => setState(() => _timeoutSeconds = v ?? 120)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRequestUrlPreview(BuildContext context) {
    final theme = Theme.of(context);
    final url = _draftConfig().chatCompletionsUrl;
    if (url.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.alt_route, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: SelectableText(
            '实际请求：$url',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTestResult(BuildContext context) {
    final theme = Theme.of(context);
    final ok = _testOk == true;
    final bg = ok ? theme.colorScheme.primaryContainer : theme.colorScheme.errorContainer;
    final fg = ok ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _testMessage ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ),
            ],
          ),
          if (_testDetail != null && _testDetail!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 22),
              child: SelectableText(
                _testDetail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}





/// 可搜索的模型选择弹层。
class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.models,
    required this.selected,
    required this.catalogModels,
  });

  final List<String> models;
  final String selected;
  final List<AiModelInfo> catalogModels;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.models;
    return widget.models.where((m) => m.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = _filtered;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '选择模型',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.models.length} 个',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索模型名，如 deepseek / GLM / qwen',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: models.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '没有匹配的模型',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: models.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final model = models[index];
                        final selected = model == widget.selected;
                        final info = findModelInCatalog(widget.catalogModels, model);
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            leading: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                info?.vision == true
                                    ? Icons.image_outlined
                                    : Icons.smart_toy_outlined,
                                size: 18,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              model,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              info == null
                                  ? '点击选择此模型'
                                  : '${info.providerLabel} · ${info.capabilityLabel} · '
                                      '上下文 ${info.context}'
                                      '${info.free ? ' · 免费' : ''}\n${info.note}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Icon(Icons.check_circle,
                                    color: theme.colorScheme.primary)
                                : null,
                            onTap: () => Navigator.of(context).pop(model),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

