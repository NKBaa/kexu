/// 大模型接入配置。
///
/// 设计原则：**协议统一走 OpenAI 兼容的 `/chat/completions`**。
/// 国内主流服务（DeepSeek、智谱 GLM、通义千问、Moonshot）都提供兼容端点，
/// 因此用户只要填 baseUrl + apiKey + model 就能用，无需为每家写适配器。
/// 预设只是「省事」，不限制用户自定义。
///
/// ## 为什么分成「视觉模型」和「语言模型」两套
/// App 里有两类 AI 任务，需要的模型能力完全不同：
/// - **图片转课表**需要**能看图的视觉模型**（glm-4v / qwen-vl / gpt-4o …）；
/// - **一句话改课表**是纯文本任务，用便宜的文本模型即可（deepseek-chat / glm-4-flash）。
///
/// 现实中用户往往想混搭：视觉用免费的 glm-4v-flash，文本用推理更强的 deepseek-chat。
/// 所以这两套配置**各自独立**（可以有各自的 baseUrl、apiKey、模型与参数）。
library;

/// 一个模型服务预设。
class AiProviderPreset {
  /// 内部标识。
  final String id;

  /// 展示名。
  final String label;

  /// 默认 API 根地址（不含 `/chat/completions`）。
  final String defaultBaseUrl;

  /// 该服务默认的**视觉**模型（用于图片转课表）；为空表示不做视觉。
  final String visionModel;

  /// 该服务默认的**文本**模型（用于一句话改课表）。
  final String textModel;

  /// 给用户看的说明。
  final String note;

  const AiProviderPreset({
    required this.id,
    required this.label,
    required this.defaultBaseUrl,
    required this.visionModel,
    required this.textModel,
    this.note = '',
  });

  /// 该预设是否提供视觉模型。
  bool get supportsVision => visionModel.trim().isNotEmpty;
}

/// 内置预设。
///
/// 同一个预设会同时给出「视觉模型」与「文本模型」的默认值，
/// 用户选中后两边都会自动填好，再按需微调。
const List<AiProviderPreset> aiProviderPresets = <AiProviderPreset>[
  AiProviderPreset(
    id: 'siliconflow',
    label: '硅基流动 SiliconFlow（推荐）',
    defaultBaseUrl: 'https://api.siliconflow.cn/v1',
    visionModel: 'Qwen/Qwen2.5-VL-72B-Instruct',
    textModel: 'deepseek-ai/DeepSeek-V3',
    note: '硅基流动的 API Key 需要在官网注册/登录后创建；模型名可点「获取模型列表」'
        '按账号可用模型选择。注册、充值与 API Key 均在硅基流动官网完成，'
        '课序只保存你填写的 Key，不接触账号密码。',
  ),
  AiProviderPreset(
    id: 'cotton',
    label: 'CottonAPI（推荐）',
    defaultBaseUrl: 'https://api.cottonapi.cloud/v1',
    visionModel: 'gemini-3.8-flash',
    textModel: 'gemini-3.8-flash',
    note: 'OpenAI 兼容网关，视觉与文本都能接；模型名可改成自己账号支持的（如 gemini-3.8-flash）。',
  ),
  AiProviderPreset(
    id: 'zhipu',
    label: '智谱 GLM（视觉 + 文本）',
    defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    visionModel: 'glm-4v-flash',
    textModel: 'glm-4-flash',
    note: 'glm-4v-flash 免费且支持图片识别，适合「图片转课表」；文本用 glm-4-flash 更便宜。',
  ),
  AiProviderPreset(
    id: 'qwen',
    label: '通义千问 Qwen（视觉 + 文本）',
    defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    visionModel: 'qwen-vl-max',
    textModel: 'qwen-plus',
    note: 'qwen-vl 系列识别课表截图效果较好；纯文本可用 qwen-plus。',
  ),
  AiProviderPreset(
    id: 'openai',
    label: 'OpenAI（视觉 + 文本）',
    defaultBaseUrl: 'https://api.openai.com/v1',
    visionModel: 'gpt-4o-mini',
    textModel: 'gpt-4o-mini',
    note: 'gpt-4o / gpt-4o-mini 同时支持图片与文本。国内访问可能需要代理。',
  ),
  AiProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek（仅文本）',
    defaultBaseUrl: 'https://api.deepseek.com/v1',
    visionModel: '',
    textModel: 'deepseek-chat',
    note: '文本推理强、价格低，适合「一句话改课表」；官方接口不支持图片，'
        '图片转课表请另配一个视觉模型（可以和服务商不同）。',
  ),
  AiProviderPreset(
    id: 'moonshot',
    label: 'Moonshot Kimi（仅文本）',
    defaultBaseUrl: 'https://api.moonshot.cn/v1',
    visionModel: '',
    textModel: 'moonshot-v1-8k',
    note: '长文本理解好，适合批量调整指令。',
  ),
  AiProviderPreset(
    id: 'custom',
    label: '自定义（任意 OpenAI 兼容服务）',
    defaultBaseUrl: '',
    visionModel: '',
    textModel: '',
    note: '填写兼容 /chat/completions 的地址，例如本地 Ollama、vLLM、one-api 网关等。',
  ),
];

/// 单个模型的连接配置（视觉或文本各持一份）。
class AiModelConfig {
  /// API 根地址，例如 `https://api.deepseek.com/v1`。
  final String baseUrl;

  /// API Key。
  final String apiKey;

  /// 模型名，例如 `glm-4v-flash`。
  final String model;

  /// 采样温度，课表结构化任务建议低一些（0~0.3）。
  final double temperature;

  /// 单次请求超时（秒）。视觉任务耗时较长，默认给足。
  final int timeoutSeconds;

  const AiModelConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.temperature = 0.2,
    this.timeoutSeconds = 120,
  });

  /// 是否已填够「能发请求」的最小信息。
  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// 是否填了 Key（部分本地服务不需要 Key）。
  bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// 是否完全空白（用于判断「用户还没配过」）。
  bool get isEmpty =>
      baseUrl.trim().isEmpty && model.trim().isEmpty && apiKey.trim().isEmpty;

  /// 归一化后的请求地址（补上 `/chat/completions`，且不重复拼接）。
  String get chatCompletionsUrl {
    var b = baseUrl.trim();
    if (b.isEmpty) return '';
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/chat/completions')) return b;
    return '$b/chat/completions';
  }

  /// 归一化后的模型列表地址（`{baseUrl}/models`）。
  ///
  /// 用于「大模型配置」页的「自动获取模型列表」：不同网关的模型名经常变化，
  /// 手填容易拼错。若用户把完整的 `/chat/completions` 地址粘进 baseUrl，
  /// 这里会先剥掉再拼 `/models`，避免出现 `.../chat/completions/models`。
  String get modelsUrl {
    var b = baseUrl.trim();
    if (b.isEmpty) return '';
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (b.endsWith('/models')) return b;
    if (b.endsWith('/chat/completions')) {
      b = b.substring(0, b.length - '/chat/completions'.length);
    }
    return '$b/models';
  }

  AiModelConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    int? timeoutSeconds,
  }) =>
      AiModelConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'timeoutSeconds': timeoutSeconds,
      };

  static AiModelConfig fromJson(Map<String, dynamic> j) => AiModelConfig(
        baseUrl: (j['baseUrl'] ?? '').toString(),
        apiKey: (j['apiKey'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        temperature: (j['temperature'] is num)
            ? (j['temperature'] as num).toDouble()
            : double.tryParse('${j['temperature']}') ?? 0.2,
        timeoutSeconds: (j['timeoutSeconds'] is num)
            ? (j['timeoutSeconds'] as num).toInt()
            : int.tryParse('${j['timeoutSeconds']}') ?? 120,
      );
}

/// 应用的大模型配置：视觉模型 + 语言模型，各自独立。
class AiConfig {
  /// 图片转课表用的视觉模型。
  final AiModelConfig vision;

  /// 一句话改课表用的文本模型。
  final AiModelConfig text;

  const AiConfig({
    this.vision = const AiModelConfig(),
    this.text = const AiModelConfig(),
  });

  /// 至少有一项可用。
  bool get isConfigured => vision.isConfigured || text.isConfigured;

  /// 图片转课表是否可用。
  bool get visionConfigured => vision.isConfigured;

  /// 一句话改课表是否可用。
  bool get textConfigured => text.isConfigured;

  AiConfig copyWith({AiModelConfig? vision, AiModelConfig? text}) =>
      AiConfig(vision: vision ?? this.vision, text: text ?? this.text);

  Map<String, dynamic> toJson() => {
        'vision': vision.toJson(),
        'text': text.toJson(),
      };

  /// 反序列化，并**兼容旧版单模型配置**。
  ///
  /// 旧格式把 baseUrl/apiKey/model 直接放在顶层；读到这种结构时，
  /// 把它同时当作视觉与文本配置，用户升级后不会突然「AI 失效」。
  static AiConfig fromJson(Map<String, dynamic> j) {
    final visionJson = j['vision'];
    final textJson = j['text'];
    if (visionJson is Map || textJson is Map) {
      return AiConfig(
        vision: visionJson is Map
            ? AiModelConfig.fromJson(Map<String, dynamic>.from(visionJson))
            : const AiModelConfig(),
        text: textJson is Map
            ? AiModelConfig.fromJson(Map<String, dynamic>.from(textJson))
            : const AiModelConfig(),
      );
    }

    // 旧格式：顶层就是单个模型配置
    if (j.containsKey('baseUrl') || j.containsKey('model')) {
      final legacy = AiModelConfig.fromJson(j);
      return AiConfig(vision: legacy, text: legacy);
    }

    return const AiConfig();
  }
}
