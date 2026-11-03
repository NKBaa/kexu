/// 内置模型能力目录。
///
/// 目标不是维护一份「永远最新」的模型清单，而是给用户一个**可比较的起点**：
/// 哪些模型能看图、哪些只能文本、是否免费、上下文多大、适合什么任务。
/// 服务端模型列表仍然是最终依据；这里选中的模型名如果已被服务商下线，
/// 可在详情页点「获取模型列表」重新选择。
///
/// 能力标签说明：
/// - [vision]：能理解图片，可用于「图片转课表」；
/// - [text]：能对话/文本生成，可用于「一句话改课表」；
/// - [free]：服务商公开的免费模型（可能有额度/频率限制）。
class AiModelInfo {
  final String providerId;
  final String providerLabel;
  final String id;
  final bool vision;
  final bool text;
  final bool free;

  /// 上下文长度的人类可读描述，如 `128K`、`1M`、`约 64K`。
  final String context;

  /// 适合什么任务 / 选型建议。
  final String note;

  const AiModelInfo({
    required this.providerId,
    required this.providerLabel,
    required this.id,
    required this.vision,
    required this.text,
    this.free = false,
    this.context = '—',
    this.note = '',
  });

  bool supports({required bool vision}) => vision ? this.vision : text;

  String get capabilityLabel {
    if (vision && text) return '图片 + 文本';
    if (vision) return '仅图片';
    return '仅文本';
  }

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerLabel': providerLabel,
        'id': id,
        'vision': vision,
        'text': text,
        'free': free,
        'context': context,
        'note': note,
      };

  /// 容错解析：缺省布尔值按 false，文本字段去空白。
  factory AiModelInfo.fromJson(Map<String, dynamic> j) {
    String str(String key) => (j[key] ?? '').toString().trim();
    bool flag(String key) => j[key] == true;
    return AiModelInfo(
      providerId: str('providerId'),
      providerLabel: str('providerLabel'),
      id: str('id'),
      vision: flag('vision'),
      text: flag('text'),
      free: flag('free'),
      context: str('context').isEmpty ? '—' : str('context'),
      note: str('note'),
    );
  }
}

/// 一份模型名单（内置或从 GitHub 拉取）。
class AiModelCatalog {
  final int version;
  final String updatedAt;
  final List<AiModelInfo> models;

  /// 来源：`github` / `cache` / `builtin`。
  final String source;

  /// 拉取失败时的说明（用于 UI 提示）；成功时为空。
  final String warning;

  const AiModelCatalog({
    required this.models,
    this.version = 1,
    this.updatedAt = '',
    this.source = 'builtin',
    this.warning = '',
  });

  bool get isEmpty => models.isEmpty;

  /// 内置兜底名单：保证离线/接口不可用时仍可选模型。
  factory AiModelCatalog.builtIn() => AiModelCatalog(
        models: builtInModels,
        updatedAt: '内置名单',
        source: 'builtin',
      );

  factory AiModelCatalog.fromJson(Map<String, dynamic> j) {
    final raw = j['models'];
    if (raw is! List) {
      throw const FormatException('模型名单缺少 models 数组');
    }
    final models = <AiModelInfo>[];
    for (final item in raw) {
      if (item is Map) {
        final model = AiModelInfo.fromJson(Map<String, dynamic>.from(item));
        if (model.id.isNotEmpty && model.providerId.isNotEmpty) {
          models.add(model);
        }
      }
    }
    if (models.isEmpty) {
      throw const FormatException('模型名单为空');
    }
    return AiModelCatalog(
      models: models,
      version: (j['version'] is num) ? (j['version'] as num).toInt() : 1,
      updatedAt: (j['updatedAt'] ?? '').toString().trim(),
      source: (j['source'] ?? 'github').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'updatedAt': updatedAt,
        'models': [for (final model in models) model.toJson()],
      };

  AiModelCatalog copyWith({
    int? version,
    String? updatedAt,
    List<AiModelInfo>? models,
    String? source,
    String? warning,
  }) =>
      AiModelCatalog(
        version: version ?? this.version,
        updatedAt: updatedAt ?? this.updatedAt,
        models: models ?? this.models,
        source: source ?? this.source,
        warning: warning ?? this.warning,
      );
}

/// 在给定名单里按模型 id 精确查找（忽略首尾空白与大小写）。
AiModelInfo? findModelInCatalog(List<AiModelInfo> models, String modelId) {
  final key = modelId.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final model in models) {
    if (model.id.toLowerCase() == key) return model;
  }
  return null;
}

/// 内置模型目录。按服务商分组。
const List<AiModelInfo> builtInModels = <AiModelInfo>[
  // ---------------------------------------------------------------- 硅基流动
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'Qwen/Qwen2.5-VL-72B-Instruct',
    vision: true,
    text: true,
    context: '128K',
    note: '课表截图/表格识别能力强，视觉首选；价格比小模型高。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'Qwen/Qwen2.5-VL-32B-Instruct',
    vision: true,
    text: true,
    context: '128K',
    note: '视觉能力够用、成本更低，适合日常课表截图。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'Qwen/Qwen2.5-VL-7B-Instruct',
    vision: true,
    text: true,
    context: '32K',
    note: '轻量视觉模型，适合清晰、简单的课表截图。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'deepseek-ai/DeepSeek-V3',
    vision: false,
    text: true,
    context: '64K',
    note: '中文文本与指令理解强，适合一句话改课表。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'deepseek-ai/DeepSeek-R1',
    vision: false,
    text: true,
    context: '64K',
    note: '推理更强但更慢，适合复杂、多条件的改课表指令。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'Qwen/Qwen2.5-72B-Instruct',
    vision: false,
    text: true,
    context: '128K',
    note: '通用中文文本模型，性价比高。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'Qwen/Qwen2.5-7B-Instruct',
    vision: false,
    text: true,
    context: '32K',
    note: '轻量文本模型，适合简单指令、响应快。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'Qwen/Qwen3-8B',
    vision: false,
    text: true,
    context: '32K',
    note: '较新的轻量中文模型，适合低成本的日常改课表。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'moonshotai/Kimi-K2-Instruct',
    vision: false,
    text: true,
    context: '128K',
    note: '长上下文，适合一次描述很多条改课表要求。',
  ),
  AiModelInfo(
    providerId: 'siliconflow',
    providerLabel: '硅基流动',
    id: 'zai-org/GLM-4.5V',
    vision: true,
    text: true,
    context: '64K',
    note: 'GLM 视觉模型，作为 Qwen-VL 之外的备选。',
  ),

  // -------------------------------------------------------------------- 智谱
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-4v-flash',
    vision: true,
    text: true,
    free: true,
    context: '16K',
    note: '免费视觉模型，图片转课表性价比首选；复杂截图可能不如 72B。',
  ),
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-4v-plus',
    vision: true,
    text: true,
    context: '16K',
    note: '视觉能力比 flash 强，适合复杂表格/低清截图。',
  ),
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-4v',
    vision: true,
    text: true,
    context: '8K',
    note: '较早的视觉模型，兼容旧账号。',
  ),
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-4-flash',
    vision: false,
    text: true,
    free: true,
    context: '128K',
    note: '免费文本模型，一句话改课表首选低成本方案。',
  ),
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-4-plus',
    vision: false,
    text: true,
    context: '128K',
    note: '文本能力更强，适合复杂指令。',
  ),
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-4-air',
    vision: false,
    text: true,
    context: '128K',
    note: '轻量文本模型，速度快、成本低。',
  ),
  AiModelInfo(
    providerId: 'zhipu',
    providerLabel: '智谱 GLM',
    id: 'glm-z1-air',
    vision: false,
    text: true,
    context: '128K',
    note: '带推理能力的轻量模型，适合多步改课表。',
  ),

  // ---------------------------------------------------------------- 通义千问
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen-vl-max',
    vision: true,
    text: true,
    context: '32K',
    note: '视觉旗舰，识别课表截图与表格稳定。',
  ),
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen-vl-plus',
    vision: true,
    text: true,
    context: '32K',
    note: '视觉能力均衡，价格比 max 低。',
  ),
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen2.5-vl-72b-instruct',
    vision: true,
    text: true,
    context: '128K',
    note: '开源视觉模型，适合自建/兼容网关。',
  ),
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen-plus',
    vision: false,
    text: true,
    context: '128K',
    note: '文本能力与价格均衡，适合一句话改课表。',
  ),
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen-turbo',
    vision: false,
    text: true,
    context: '128K',
    note: '速度快、成本低，适合简单指令。',
  ),
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen-max',
    vision: false,
    text: true,
    context: '32K',
    note: '文本旗舰，复杂指令更稳。',
  ),
  AiModelInfo(
    providerId: 'qwen',
    providerLabel: '通义千问',
    id: 'qwen-long',
    vision: false,
    text: true,
    context: '10M',
    note: '超长上下文，适合一次塞入大量课表说明。',
  ),

  // ------------------------------------------------------------------ OpenAI
  AiModelInfo(
    providerId: 'openai',
    providerLabel: 'OpenAI',
    id: 'gpt-4o',
    vision: true,
    text: true,
    context: '128K',
    note: '视觉与文本都强，适合复杂课表；国内访问可能需代理。',
  ),
  AiModelInfo(
    providerId: 'openai',
    providerLabel: 'OpenAI',
    id: 'gpt-4o-mini',
    vision: true,
    text: true,
    context: '128K',
    note: '便宜、够用的多模态模型，日常首选。',
  ),
  AiModelInfo(
    providerId: 'openai',
    providerLabel: 'OpenAI',
    id: 'gpt-4.1',
    vision: true,
    text: true,
    context: '1M',
    note: '长上下文、指令遵循强，适合复杂改课表。',
  ),
  AiModelInfo(
    providerId: 'openai',
    providerLabel: 'OpenAI',
    id: 'gpt-4.1-mini',
    vision: true,
    text: true,
    context: '1M',
    note: '成本更低的 4.1 小模型，适合批量任务。',
  ),
  AiModelInfo(
    providerId: 'openai',
    providerLabel: 'OpenAI',
    id: 'o3-mini',
    vision: false,
    text: true,
    context: '200K',
    note: '推理模型，适合复杂逻辑；不支持图片。',
  ),

  // ---------------------------------------------------------------- DeepSeek
  AiModelInfo(
    providerId: 'deepseek',
    providerLabel: 'DeepSeek',
    id: 'deepseek-chat',
    vision: false,
    text: true,
    context: '64K',
    note: '文本推理强、价格低，一句话改课表首选。',
  ),
  AiModelInfo(
    providerId: 'deepseek',
    providerLabel: 'DeepSeek',
    id: 'deepseek-reasoner',
    vision: false,
    text: true,
    context: '64K',
    note: '推理更强但更慢，适合复杂多条件指令。',
  ),

  // ---------------------------------------------------------------- Moonshot
  AiModelInfo(
    providerId: 'moonshot',
    providerLabel: 'Moonshot Kimi',
    id: 'moonshot-v1-8k',
    vision: false,
    text: true,
    context: '8K',
    note: '短文本，响应快。',
  ),
  AiModelInfo(
    providerId: 'moonshot',
    providerLabel: 'Moonshot Kimi',
    id: 'moonshot-v1-32k',
    vision: false,
    text: true,
    context: '32K',
    note: '长文本理解好，适合批量调整。',
  ),
  AiModelInfo(
    providerId: 'moonshot',
    providerLabel: 'Moonshot Kimi',
    id: 'moonshot-v1-128k',
    vision: false,
    text: true,
    context: '128K',
    note: '超长文本，适合一次处理整份课表说明。',
  ),

  // --------------------------------------------------------------- CottonAPI
  AiModelInfo(
    providerId: 'cotton',
    providerLabel: 'CottonAPI',
    id: 'gemini-3.8-flash',
    vision: true,
    text: true,
    context: '1M',
    note: '多模态网关默认模型，图片与文本都能接；模型名以账号实际支持为准。',
  ),
];
