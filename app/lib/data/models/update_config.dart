/// 在线更新的配置模型。
///
/// 更新走 GitHub Releases：**默认指向本仓库 [defaultUpdateRepo]（开箱即用）**，
/// 也可以在设置里改成自己的 fork；国内网络可以走镜像前缀加速。
///
/// 镜像规则很简单：**镜像地址 = 前缀 + 原始 GitHub 地址**，
/// 例如 `https://ghfast.top/https://github.com/owner/repo/releases/...`，
/// API 同理 `https://ghfast.top/https://api.github.com/repos/owner/repo/releases/latest`。
library;

/// 一个镜像加速预设。
///
/// [mode] 决定选择它时写进 [UpdateConfig.mirrorMode] 的值：
/// `auto` / `direct` 直接用同名模式，其余预设统一用 `preset` + [id]。
class UpdateMirrorPreset {
  /// 稳定标识（存进 settings.json，不要随意改）。
  final String id;

  /// 下拉框里显示的中文名称。
  final String label;

  /// 一句话说明，让用户知道这个选项的取舍。
  final String description;

  /// 镜像前缀，如 `https://ghfast.top/`；直连与自定义为空。
  final String prefix;

  /// 选择该预设时写入的 [UpdateConfig.mirrorMode]。
  final String mode;

  const UpdateMirrorPreset({
    required this.id,
    required this.label,
    required this.description,
    this.prefix = '',
    required this.mode,
  });
}

/// 内置镜像预设（顺序即下拉框顺序）。
const List<UpdateMirrorPreset> updateMirrorPresets = <UpdateMirrorPreset>[
  UpdateMirrorPreset(
    id: 'auto',
    label: '自动（推荐）',
    description: '直连 GitHub 优先，失败后依次尝试国内镜像',
    mode: 'auto',
  ),
  UpdateMirrorPreset(
    id: 'direct',
    label: '直连 GitHub',
    description: '不经过任何镜像，适合能直连的网络',
    mode: 'direct',
  ),
  UpdateMirrorPreset(
    id: 'ghfast',
    label: 'ghfast.top',
    description: '国内加速节点，镜像地址 = 前缀 + 原 GitHub 地址',
    prefix: 'https://ghfast.top/',
    mode: 'preset',
  ),
  UpdateMirrorPreset(
    id: 'ghproxy',
    label: 'ghproxy.net',
    description: '国内加速节点，适合 ghfast 不可用时兜底',
    prefix: 'https://ghproxy.net/',
    mode: 'preset',
  ),
  UpdateMirrorPreset(
    id: 'ghproxy_com',
    label: 'gh-proxy.com',
    description: '国内加速节点，备用线路',
    prefix: 'https://gh-proxy.com/',
    mode: 'preset',
  ),
  UpdateMirrorPreset(
    id: 'custom',
    label: '自定义前缀',
    description: '填写自己的加速前缀，例如 https://ghfast.top/',
    mode: 'custom',
  ),
];

/// 内置的默认更新仓库：App 开箱即用指向本项目。
///
/// 这是**唯一**硬编码仓库名的地方；fork 后可在设置里改掉，或改这个常量。
const String defaultUpdateRepo = 'NKBaa/kexu';

/// 自动模式依次尝试的国内镜像（按可用性排序）。
const List<String> autoMirrorPrefixes = <String>[
  'https://ghfast.top/',
  'https://ghproxy.net/',
  'https://gh-proxy.com/',
];

/// 模板/名单/主题市场固定使用的加速前缀。
///
/// 这些资源是只读 JSON，和「检查更新」的镜像设置无关：
/// 先走加速节点，最后再用 GitHub 直连兜底。用户不需要知道或配置。
const List<String> templateMirrorPrefixes = <String>[
  'https://ghfast.top/',
  'https://ghproxy.net/',
  'https://gh-proxy.com/',
];

/// **能代理 GitHub API（`api.github.com`）的镜像前缀**。
///
/// 实测（2026-11）：`ghfast.top` 与 `ghproxy.net` 只代理
/// `github.com` 的 releases/raw/archive，对 `api.github.com` 返回 403；
/// `gh-proxy.com` 同时支持 API 与下载。
///
/// 所以「检查更新」不能直接复用下载用的镜像顺序，否则用户选了
/// ghfast.top 就会永远检查失败。这里把已知可用的 API 镜像单独列出来，
/// 下载仍然按用户选择的镜像走（见 [UpdateConfig.mirrorPrefixes]）。
const List<String> apiMirrorPrefixes = <String>[
  'https://gh-proxy.com/',
];

/// 按 id 查预设；找不到返回 null。
UpdateMirrorPreset? findMirrorPreset(String id) {
  for (final preset in updateMirrorPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// 把用户填的前缀规范化：去空白、补协议、补结尾 `/`。
///
/// 用户可能直接填 `ghfast.top` 或 `https://ghfast.top`，这里统一成
/// `https://ghfast.top/`，避免拼出 `ghfast.tophttps://...` 这种坏地址。
String normalizeMirrorPrefix(String raw) {
  var p = raw.trim();
  if (p.isEmpty) return '';
  if (!p.startsWith('http://') && !p.startsWith('https://')) {
    p = 'https://$p';
  }
  if (!p.endsWith('/')) p = '$p/';
  return p;
}

/// 在线更新配置（随 [AppSettings] 一起存进 `settings.json`）。
class UpdateConfig {
  /// GitHub 仓库，形如 `owner/repo`。
  ///
  /// 默认是 [defaultUpdateRepo]（本仓库）；清空表示不检查更新。
  final String repo;

  /// 镜像模式：`auto` / `direct` / `preset` / `custom`。
  final String mirrorMode;

  /// `mirrorMode == 'preset'` 时使用的预设 id。
  final String mirrorPresetId;

  /// `mirrorMode == 'custom'` 时的前缀，如 `https://ghfast.top/`。
  final String customMirrorPrefix;

  /// 启动时是否自动检查更新。
  final bool autoCheck;

  /// 用户选择「忽略此版本」时记下的版本号；空表示不忽略。
  final String ignoredVersion;

  /// 上次检查时间（ISO 字符串）；空表示从未检查。
  final String lastCheckedAt;

  const UpdateConfig({
    this.repo = defaultUpdateRepo,
    this.mirrorMode = 'auto',
    this.mirrorPresetId = 'ghfast',
    this.customMirrorPrefix = '',
    this.autoCheck = true,
    this.ignoredVersion = '',
    this.lastCheckedAt = '',
  });

  /// 合法的镜像模式集合。
  static const Set<String> validMirrorModes = <String>{
    'auto',
    'direct',
    'preset',
    'custom',
  };

  /// 规范化后的仓库名：容忍用户粘贴 `https://github.com/owner/repo` 或带结尾斜杠。
  String get normalizedRepo {
    var r = repo.trim();
    final lower = r.toLowerCase();
    if (lower.startsWith('https://github.com/')) {
      r = r.substring('https://github.com/'.length);
    } else if (lower.startsWith('http://github.com/')) {
      r = r.substring('http://github.com/'.length);
    } else if (lower.startsWith('github.com/')) {
      r = r.substring('github.com/'.length);
    }
    return r.replaceAll(RegExp(r'/+$'), '');
  }

  /// 仓库是否形如 `owner/repo`。
  bool get isConfigured =>
      RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(normalizedRepo);

  /// 按 [mirrorMode] 生成**按尝试顺序**排列的前缀列表。
  ///
  /// 返回的每一项都可以直接拼在 GitHub 原始地址前面（直连是空串）。
  /// 列表已去重，保证不会对同一个地址请求两次。
  List<String> get mirrorPrefixes {
    final result = <String>[];
    void add(String raw) {
      final prefix = normalizeMirrorPrefix(raw);
      if (result.contains(prefix)) return;
      result.add(prefix);
    }

    switch (mirrorMode) {
      case 'direct':
        add('');
      case 'preset':
        final preset = findMirrorPreset(mirrorPresetId);
        add(preset?.prefix ?? 'https://ghfast.top/');
      case 'custom':
        add(customMirrorPrefix);
      default: // auto：直连优先，再依次尝试国内镜像
        add('');
        for (final prefix in autoMirrorPrefixes) {
          add(prefix);
        }
    }
    return result;
  }

  /// 「检查更新」用的前缀顺序。
  ///
  /// 与 [mirrorPrefixes]（下载用）的区别：API 检查必须走**能代理
  /// `api.github.com` 的镜像**（见 [apiMirrorPrefixes]）。因此这里把已知可用
  /// 的 API 镜像插到下载镜像之前，并保留直连兜底 —— 即使下载选了
  /// ghfast.top，检查更新也能通过 gh-proxy.com 完成，不会「永远检查失败」。
  List<String> get apiPrefixes {
    final result = <String>[];
    void add(String raw) {
      final prefix = normalizeMirrorPrefix(raw);
      if (result.contains(prefix)) return;
      result.add(prefix);
    }

    switch (mirrorMode) {
      case 'direct':
        add('');
      case 'preset':
        add(findMirrorPreset(mirrorPresetId)?.prefix ?? 'https://ghfast.top/');
        add('');
        for (final prefix in apiMirrorPrefixes) {
          add(prefix);
        }
      case 'custom':
        add(customMirrorPrefix);
        add('');
        for (final prefix in apiMirrorPrefixes) {
          add(prefix);
        }
      default: // auto：直连优先，再走 API 镜像，最后才试只能下载的镜像
        add('');
        for (final prefix in apiMirrorPrefixes) {
          add(prefix);
        }
        for (final prefix in autoMirrorPrefixes) {
          add(prefix);
        }
    }
    return result;
  }

  UpdateConfig copyWith({
    String? repo,
    String? mirrorMode,
    String? mirrorPresetId,
    String? customMirrorPrefix,
    bool? autoCheck,
    String? ignoredVersion,
    String? lastCheckedAt,
  }) =>
      UpdateConfig(
        repo: repo ?? this.repo,
        mirrorMode: mirrorMode ?? this.mirrorMode,
        mirrorPresetId: mirrorPresetId ?? this.mirrorPresetId,
        customMirrorPrefix: customMirrorPrefix ?? this.customMirrorPrefix,
        autoCheck: autoCheck ?? this.autoCheck,
        ignoredVersion: ignoredVersion ?? this.ignoredVersion,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      );

  Map<String, dynamic> toJson() => {
        'repo': repo,
        'mirrorMode': mirrorMode,
        'mirrorPresetId': mirrorPresetId,
        'customMirrorPrefix': customMirrorPrefix,
        'autoCheck': autoCheck,
        'ignoredVersion': ignoredVersion,
        'lastCheckedAt': lastCheckedAt,
      };

  /// 从 JSON 读取；缺字段一律回退默认值，保证旧版 `settings.json` 能直接升级。
  static UpdateConfig fromJson(Map<String, dynamic> j) {
    final rawMode = (j['mirrorMode'] ?? 'auto').toString();
    final mode = validMirrorModes.contains(rawMode) ? rawMode : 'auto';
    final rawPreset = (j['mirrorPresetId'] ?? 'ghfast').toString();
    return UpdateConfig(
      repo: (j['repo'] ?? defaultUpdateRepo).toString(),
      mirrorMode: mode,
      mirrorPresetId: findMirrorPreset(rawPreset)?.mode == 'preset' ? rawPreset : 'ghfast',
      customMirrorPrefix: (j['customMirrorPrefix'] ?? '').toString(),
      autoCheck: j['autoCheck'] is bool ? j['autoCheck'] as bool : true,
      ignoredVersion: (j['ignoredVersion'] ?? '').toString(),
      lastCheckedAt: (j['lastCheckedAt'] ?? '').toString(),
    );
  }
}
