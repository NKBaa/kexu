import 'dart:convert';

import 'package:flutter/material.dart';

/// 一套主题的浅色/深色色板。
class AppThemePalette {
  final int seed;
  final int surface;
  final int card;
  final int ink;

  const AppThemePalette({
    required this.seed,
    required this.surface,
    required this.card,
    required this.ink,
  });

  Color get seedColor => Color(seed);
  Color get surfaceColor => Color(surface);
  Color get cardColor => Color(card);
  Color get inkColor => Color(ink);

  /// 输入框底色：在 surface 上叠一点 ink，避免和卡片完全同色。
  Color get fieldColor => Color.alphaBlend(
        Color(ink).withValues(alpha: 0.06),
        Color(surface),
      );

  Map<String, dynamic> toJson() => {
        'seed': _hex(seed),
        'surface': _hex(surface),
        'card': _hex(card),
        'ink': _hex(ink),
      };

  static AppThemePalette fromJson(
    dynamic raw, {
    required AppThemePalette fallback,
  }) {
    if (raw is! Map) return fallback;
    final j = Map<String, dynamic>.from(raw);
    return AppThemePalette(
      seed: _parseColor(j['seed']) ?? fallback.seed,
      surface: _parseColor(j['surface']) ?? fallback.surface,
      card: _parseColor(j['card']) ?? fallback.card,
      ink: _parseColor(j['ink']) ?? fallback.ink,
    );
  }
}

/// 用户可编写/从市场安装的主题定义。
///
/// 主题用 JSON 描述（主题中心里可直接编辑代码）：
/// ```json
/// {
///   "id": "sakura",
///   "name": "樱花",
///   "author": "you",
///   "description": "粉色暖白",
///   "radius": 22,
///   "light": {"seed": "#C45C7C", "surface": "#FFF7FA", "card": "#FFFFFF", "ink": "#2A1B22"},
///   "dark":  {"seed": "#E8A2BC", "surface": "#1A1216", "card": "#241A1F", "ink": "#F5E7EC"}
/// }
/// ```
class AppThemeSpec {
  final String id;
  final String name;
  final String author;
  final String description;
  final double radius;
  final AppThemePalette light;
  final AppThemePalette dark;
  final bool builtIn;

  const AppThemeSpec({
    required this.id,
    required this.name,
    this.author = '',
    this.description = '',
    this.radius = 24,
    required this.light,
    required this.dark,
    this.builtIn = false,
  });

  /// 内置主题：不写入 settings，选中时用 id 记录。
  static const List<AppThemeSpec> builtIns = <AppThemeSpec>[
    AppThemeSpec(
      id: 'default',
      name: '黑灰牛皮纸（默认）',
      author: '课序',
      description: '黑灰文字 + 牛皮纸黄背景 + 白卡片，安静耐看。',
      light: AppThemePalette(
        seed: 0xFFB99A6B,
        surface: 0xFFEFE6D6,
        card: 0xFFFFFDF8,
        ink: 0xFF1C1C1C,
      ),
      dark: AppThemePalette(
        seed: 0xFFD9C29A,
        surface: 0xFF171717,
        card: 0xFF232323,
        ink: 0xFFF2EFE8,
      ),
      builtIn: true,
    ),
    AppThemeSpec(
      id: 'midnight',
      name: '午夜蓝',
      author: '课序',
      description: '冷色深蓝，夜间更安静。',
      light: AppThemePalette(
        seed: 0xFF3E5C99,
        surface: 0xFFF4F7FF,
        card: 0xFFFFFFFF,
        ink: 0xFF101828,
      ),
      dark: AppThemePalette(
        seed: 0xFF8FB0FF,
        surface: 0xFF0B1020,
        card: 0xFF141B2D,
        ink: 0xFFE6EDF8,
      ),
      builtIn: true,
    ),
    AppThemeSpec(
      id: 'sakura',
      name: '樱花',
      author: '课序',
      description: '粉色暖白，柔和但不刺眼。',
      radius: 22,
      light: AppThemePalette(
        seed: 0xFFC45C7C,
        surface: 0xFFFFF7FA,
        card: 0xFFFFFFFF,
        ink: 0xFF2A1B22,
      ),
      dark: AppThemePalette(
        seed: 0xFFE8A2BC,
        surface: 0xFF1A1216,
        card: 0xFF241A1F,
        ink: 0xFFF5E7EC,
      ),
      builtIn: true,
    ),
    AppThemeSpec(
      id: 'forest',
      name: '森林',
      author: '课序',
      description: '低饱和绿色，适合长时间看课表。',
      light: AppThemePalette(
        seed: 0xFF2F6B4F,
        surface: 0xFFF4FAF5,
        card: 0xFFFFFFFF,
        ink: 0xFF142019,
      ),
      dark: AppThemePalette(
        seed: 0xFF7FC8A9,
        surface: 0xFF0D1712,
        card: 0xFF16241C,
        ink: 0xFFE4F1E9,
      ),
      builtIn: true,
    ),
    AppThemeSpec(
      id: 'contrast',
      name: '高对比',
      author: '课序',
      description: '黑白高对比，强光下更清楚。',
      light: AppThemePalette(
        seed: 0xFF1A73E8,
        surface: 0xFFFFFFFF,
        card: 0xFFFFFFFF,
        ink: 0xFF000000,
      ),
      dark: AppThemePalette(
        seed: 0xFF8AB4F8,
        surface: 0xFF000000,
        card: 0xFF111111,
        ink: 0xFFFFFFFF,
      ),
      builtIn: true,
    ),
  ];

  AppThemePalette paletteFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 给主题编辑器/市场使用的可编辑 JSON 代码。
  String get code => const JsonEncoder.withIndent('  ').convert(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (author.isNotEmpty) 'author': author,
        if (description.isNotEmpty) 'description': description,
        'radius': radius,
        'light': light.toJson(),
        'dark': dark.toJson(),
      };

  /// 解析主题代码；格式不对时抛出 [FormatException]，message 可直接展示。
  static AppThemeSpec fromCode(String code) {
    dynamic decoded;
    try {
      decoded = jsonDecode(code);
    } catch (e) {
      throw FormatException('主题代码不是合法 JSON：$e');
    }
    if (decoded is! Map) {
      throw const FormatException('主题代码必须是一个 JSON 对象');
    }
    return fromJson(Map<String, dynamic>.from(decoded));
  }

  static AppThemeSpec fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString().trim();
    final name = (j['name'] ?? '').toString().trim();
    if (id.isEmpty) throw const FormatException('缺少 id');
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(id)) {
      throw const FormatException('id 只能包含字母、数字、下划线和短横线（最多 40 个字符）');
    }
    if (name.isEmpty) throw const FormatException('缺少 name');
    final radius = (j['radius'] is num)
        ? (j['radius'] as num).toDouble()
        : 24.0;
    final light = AppThemePalette.fromJson(
      j['light'],
      fallback: builtIns.first.light,
    );
    final dark = AppThemePalette.fromJson(
      j['dark'],
      fallback: builtIns.first.dark,
    );
    return AppThemeSpec(
      id: id,
      name: name,
      author: (j['author'] ?? '').toString().trim(),
      description: (j['description'] ?? '').toString().trim(),
      radius: radius.clamp(0, 40),
      light: light,
      dark: dark,
    );
  }

  AppThemeSpec copyWith({
    String? id,
    String? name,
    String? author,
    String? description,
    double? radius,
    AppThemePalette? light,
    AppThemePalette? dark,
  }) =>
      AppThemeSpec(
        id: id ?? this.id,
        name: name ?? this.name,
        author: author ?? this.author,
        description: description ?? this.description,
        radius: radius ?? this.radius,
        light: light ?? this.light,
        dark: dark ?? this.dark,
      );

  /// 编辑器默认模板。
  static const String template = '''
{
  "id": "my-theme",
  "name": "我的主题",
  "author": "我",
  "description": "一句话介绍",
  "radius": 24,
  "light": {
    "seed": "#4F5D86",
    "surface": "#F8F6EE",
    "card": "#FEFCF7",
    "ink": "#1B1B1F"
  },
  "dark": {
    "seed": "#B9C5F2",
    "surface": "#121214",
    "card": "#1C1C20",
    "ink": "#EDEAE2"
  }
}
''';
}

/// 所有可用主题：内置 + 用户本地主题。
List<AppThemeSpec> allThemes(List<AppThemeSpec> custom) => <AppThemeSpec>[
      ...AppThemeSpec.builtIns,
      ...custom,
    ];

/// 按 id 查找主题。
AppThemeSpec? findTheme(List<AppThemeSpec> custom, String id) {
  for (final theme in allThemes(custom)) {
    if (theme.id == id) return theme;
  }
  return null;
}

String _hex(int color) =>
    '#${color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

int? _parseColor(dynamic raw) {
  if (raw is int) {
    if (raw <= 0xFFFFFF) return 0xFF000000 | raw;
    return raw;
  }
  var text = (raw ?? '').toString().trim();
  if (text.isEmpty) return null;
  if (text.startsWith('#')) text = text.substring(1);
  if (text.startsWith('0x') || text.startsWith('0X')) {
    text = text.substring(2);
  }
  if (text.length == 6) text = 'FF$text';
  if (text.length != 8) return null;
  final value = int.tryParse(text, radix: 16);
  return value;
}
