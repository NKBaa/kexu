import 'package:flutter/material.dart';

import '../data/models/app_theme_spec.dart';

/// 全局圆角规格。
///
/// 设计采用 Material 3 Expressive 风格：
/// - **卡片、弹窗**用更大的 24px 圆角，视觉更柔和；
/// - **按钮、输入框、Chip** 保持胶囊圆角（StadiumBorder）；
/// - 小徽标/缩略图等次级元素可用 12px 圆角。
///
/// 新页面请优先复用这里的常量，不要再散落魔法数字。
class AppRadius {
  const AppRadius._();

  /// 卡片/弹窗圆角（Expressive 风格偏大）。
  static const double card = 24;

  /// 胶囊圆角（半径取一个足够大的值，视觉上等于 50% 高度）。
  static const double pill = 999;

  static const BorderRadius cardBorder = BorderRadius.all(Radius.circular(card));
  static const BorderRadius pillBorder = BorderRadius.all(Radius.circular(pill));

  static const OutlinedBorder pillShape = StadiumBorder();
}

/// 课程配色板。
///
/// 柔和色彩：低饱和、偏粉彩的底色配深色文字，
/// 既保留每门课的辨识度，也不会在暖白背景上显得刺眼。
class CoursePalette {
  const CoursePalette._();

  /// 可选课程颜色（按 [Course.colorIndex] 取模使用）。
  static const List<Color> colors = <Color>[
    Color(0xFFDCE7FF), // 雾蓝
    Color(0xFFD8F3E8), // 薄荷
    Color(0xFFFFE3CF), // 杏桃
    Color(0xFFFFDDE8), // 樱粉
    Color(0xFFE6DEFF), // 薰衣草
    Color(0xFFD8F1F4), // 浅青
    Color(0xFFFFF0C2), // 奶油
    Color(0xFFE2F5D8), // 嫩绿
    Color(0xFFFFE1EC), // 玫瑰
    Color(0xFFDDE5FF), // 长春
    Color(0xFFF3DDF8), // 紫丁香
    Color(0xFFD8F4E4), // 翡翠
    Color(0xFFFFE2D1), // 珊瑚
    Color(0xFFDCEFFF), // 天空
    Color(0xFFEDF8CF), // 青柠
    Color(0xFFEADDF8), // 葡萄
  ];

  /// 按索引取色（自动取模，永不越界）。
  static Color of(int index) {
    if (colors.isEmpty) return const Color(0xFFDCE7FF);
    final i = index % colors.length;
    return colors[i < 0 ? i + colors.length : i];
  }
}

/// 全局主题：暖白 + 黑字 + 深蓝强调，采用 Material 3 Expressive。
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF4F5D86);
  static const Color _ink = Color(0xFF1B1B1F);
  static const Color _warmSurface = Color(0xFFF8F6EE);
  static const Color _warmCard = Color(0xFFFEFCF7);
  static const Color _warmField = Color(0xFFF1EEE4);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// 用用户主题/市场主题构建 ThemeData：保留默认排版与组件风格，
  /// 只替换色板与圆角。
  static ThemeData custom(AppThemeSpec spec, Brightness brightness) {
    final base = _build(brightness);
    final palette = spec.paletteFor(brightness);
    final generated = ColorScheme.fromSeed(
      seedColor: palette.seedColor,
      brightness: brightness,
    );
    final scheme = generated.copyWith(
      surface: palette.surfaceColor,
      onSurface: palette.inkColor,
      surfaceContainerHighest: palette.fieldColor,
      outline: palette.inkColor.withValues(alpha: 0.24),
      outlineVariant: palette.inkColor.withValues(alpha: 0.13),
    );
    final radius = Radius.circular(spec.radius.clamp(0, 40));
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(radius),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(radius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.surfaceColor,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: palette.surfaceColor,
        foregroundColor: palette.inkColor,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          color: palette.inkColor,
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: palette.cardColor,
        shape: cardShape,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: palette.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(radius),
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: palette.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: radius),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: palette.fieldColor,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: palette.surfaceColor,
        indicatorColor: scheme.primaryContainer,
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: palette.surfaceColor,
        indicatorColor: scheme.primaryContainer,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.fieldColor,
      ),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: isDark ? const Color(0xFFB9C5F2) : const Color(0xFF4F5D86),
      onPrimary: isDark ? const Color(0xFF1A2138) : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF35415F) : const Color(0xFFDDE5F7),
      onPrimaryContainer:
          isDark ? const Color(0xFFE3E8FA) : const Color(0xFF1D2A4B),
      secondary: isDark ? const Color(0xFFD8D2C2) : const Color(0xFF6B6455),
      secondaryContainer:
          isDark ? const Color(0xFF403B31) : const Color(0xFFF0EAD9),
      onSecondaryContainer:
          isDark ? const Color(0xFFF4EFE1) : const Color(0xFF2A251B),
      surface: isDark ? const Color(0xFF121214) : _warmSurface,
      onSurface: isDark ? const Color(0xFFEDEAE2) : _ink,
      surfaceTint: Colors.transparent,
      outline: isDark ? const Color(0xFF46464C) : const Color(0xFFD6D0C2),
      outlineVariant: isDark ? const Color(0xFF333338) : const Color(0xFFE7E2D7),
      inverseSurface: isDark ? const Color(0xFFEDEAE2) : const Color(0xFF2C2C31),
      onInverseSurface: isDark ? const Color(0xFF2C2C31) : const Color(0xFFF8F6EE),
    );

    final textTheme = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF121214) : _warmSurface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        backgroundColor: isDark ? const Color(0xFF121214) : _warmSurface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        color: isDark ? const Color(0xFF1C1C20) : _warmCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.75),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: AppRadius.pillBorder,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.pillBorder,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.pillBorder,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.pillBorder,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.pillBorder,
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF242426) : _warmField,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: AppRadius.pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: AppRadius.pillShape,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: AppRadius.pillShape,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFEDE8DB),
        labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ),
        width: 300,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C20) : _warmCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C20) : _warmCard,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF18181B) : _warmSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF18181B) : _warmSurface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant;
          }),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        shape: AppRadius.pillShape,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),
    );
  }
}
