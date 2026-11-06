import 'package:flutter/cupertino.dart';
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

  /// 卡片/弹窗圆角（苹果分组卡片风格）。
  static const double card = 16;

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

  static const Color _seed = Color(0xFF007AFF);
  static const Color _ink = Color(0xFF000000);
  static const Color _warmSurface = Color(0xFFF2F2F7);
  static const Color _warmCard = Color(0xFFFFFFFF);
  static const Color _warmField = Color(0xFFFFFFFF);

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
      primary: isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF),
      onPrimary: Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF0A2A4A) : const Color(0xFFD6E9FF),
      onPrimaryContainer:
          isDark ? const Color(0xFFD6E9FF) : const Color(0xFF003A75),
      secondary: isDark ? const Color(0xFFAEAEB2) : const Color(0xFF8E8E93),
      secondaryContainer:
          isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      onSecondaryContainer:
          isDark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
      surface: isDark ? const Color(0xFF000000) : _warmSurface,
      onSurface: isDark ? const Color(0xFFFFFFFF) : _ink,
      surfaceTint: Colors.transparent,
      outline: isDark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8),
      outlineVariant: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD1D1D6),
      inverseSurface: isDark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
      onInverseSurface: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
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
      scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : _warmSurface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 60,
        backgroundColor: isDark ? const Color(0xFF000000) : _warmSurface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        color: isDark ? const Color(0xFF1C1C1E) : _warmCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.7,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1C1C1E) : _warmField,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide.none,
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
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
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : _warmCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : _warmCard,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF9F9F9),
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF9F9F9),
        indicatorColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.primary,
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
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? const Color(0xFF34C759)
              : (isDark ? const Color(0xFF39393D) : const Color(0xFFE5E5EA));
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: scheme.primary,
        barBackgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF9F9F9),
        scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : _warmSurface,
        textTheme: CupertinoTextThemeData(
          primaryColor: scheme.primary,
          textStyle: textTheme.bodyMedium,
        ),
      ),
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}
