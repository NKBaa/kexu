import 'package:flutter/material.dart';

/// ColorOS 16 风格的局部配色。
///
/// 只用于日程页与日程编辑器：深色下是接近纯黑的背景 + 大圆角浮层，
/// 浅色下是浅灰背景 + 白色卡片；强调色统一为 ColorOS 蓝。
class ColorOsPalette {
  const ColorOsPalette({
    required this.background,
    required this.surface,
    required this.elevated,
    required this.text,
    required this.secondary,
    required this.accent,
    required this.accentSoft,
    required this.separator,
    required this.selected,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color elevated;
  final Color text;
  final Color secondary;
  final Color accent;
  final Color accentSoft;
  final Color separator;
  final Color selected;
  final Color danger;

  bool get isDark => background.computeLuminance() < 0.2;

  static ColorOsPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? dark
        : light;
  }

  static const ColorOsPalette dark = ColorOsPalette(
    background: Color(0xFF080808),
    surface: Color(0xFF141416),
    elevated: Color(0xFF1D1D20),
    text: Color(0xFFF5F5F7),
    secondary: Color(0xFF8E8E93),
    accent: Color(0xFF4C8DFF),
    accentSoft: Color(0xFF1B2C47),
    separator: Color(0xFF2A2A2E),
    selected: Color(0xFF2E4B75),
    danger: Color(0xFFFF5A5F),
  );

  static const ColorOsPalette light = ColorOsPalette(
    background: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFF7F8FA),
    text: Color(0xFF101012),
    secondary: Color(0xFF6B6B70),
    accent: Color(0xFF2F6BFF),
    accentSoft: Color(0xFFE7EEFF),
    separator: Color(0xFFE6E7EB),
    selected: Color(0xFF2F6BFF),
    danger: Color(0xFFE5484D),
  );
}

/// ColorOS 风格的大圆角卡片。
class ColorOsCard extends StatelessWidget {
  const ColorOsCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ColorOsPalette.of(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
