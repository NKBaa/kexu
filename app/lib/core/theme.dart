import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/models/app_theme_spec.dart';
import 'coloros_theme.dart';

/// 全局圆角规格。
///
/// ColorOS 16 风格：卡片/弹窗 24px，按钮与输入框为胶囊/18px。
class AppRadius {
  const AppRadius._();

  static const double card = 24;
  static const double pill = 999;

  static const BorderRadius cardBorder = BorderRadius.all(Radius.circular(card));
  static const BorderRadius pillBorder = BorderRadius.all(Radius.circular(pill));

  static const OutlinedBorder pillShape = StadiumBorder();
}

/// 课程配色板。
///
/// 低饱和、偏粉彩的底色配深色文字，保留每门课的辨识度。
class CoursePalette {
  const CoursePalette._();

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

  static Color of(int index) {
    if (colors.isEmpty) return const Color(0xFFDCE7FF);
    final i = index % colors.length;
    return colors[i < 0 ? i + colors.length : i];
  }
}

/// 全局主题：ColorOS 16 风格的深色/浅色配色。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// 用用户主题/市场主题构建 ThemeData：保留默认排版与组件风格，
  /// 只替换色板与圆角。
  static ThemeData custom(AppThemeSpec spec, Brightness brightness) {
    if (spec.id == 'default') return _build(brightness);
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
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(radius),
      borderSide: BorderSide.none,
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
    final palette = isDark ? ColorOsPalette.dark : ColorOsPalette.light;
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
    );
    final scheme = baseScheme.copyWith(
      primary: palette.accent,
      onPrimary: Colors.white,
      primaryContainer: palette.accentSoft,
      onPrimaryContainer: isDark ? const Color(0xFFD6E6FF) : palette.accent,
      secondary: palette.secondary,
      secondaryContainer: palette.elevated,
      onSecondaryContainer: palette.text,
      surface: palette.background,
      onSurface: palette.text,
      surfaceTint: Colors.transparent,
      surfaceContainerHighest: palette.surface,
      surfaceContainerHigh: palette.elevated,
      surfaceContainerLow: palette.elevated,
      surfaceContainerLowest: palette.background,
      outline: palette.separator,
      outlineVariant: palette.separator,
      inverseSurface: isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D20),
      onInverseSurface: isDark ? const Color(0xFF1D1D20) : const Color(0xFFF5F5F7),
      error: palette.danger,
      onError: Colors.white,
    );

    final textTheme = base.textTheme.copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
    );

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.background,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.text,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: palette.text,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
        ),
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: palette.separator,
        thickness: 0.7,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
        filled: true,
        fillColor: palette.elevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: palette.elevated,
          foregroundColor: palette.text,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: palette.elevated,
        labelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: palette.text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.accentSoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? palette.accent : palette.secondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? palette.accent : palette.secondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.surface,
        indicatorColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: palette.accent),
        unselectedIconTheme: IconThemeData(color: palette.secondary),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: palette.accent,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: palette.secondary,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          side: const WidgetStatePropertyAll(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? palette.accentSoft
                : palette.elevated;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? palette.accent
                : palette.secondary;
          }),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        extendedTextStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        iconColor: palette.secondary,
        textColor: palette.text,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: palette.secondary,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.elevated,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(color: palette.text, fontSize: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.accent
              : palette.separator;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.elevated,
        contentTextStyle: TextStyle(color: palette.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: palette.accent,
        barBackgroundColor: palette.surface,
        scaffoldBackgroundColor: palette.background,
        textTheme: CupertinoTextThemeData(
          primaryColor: palette.accent,
          textStyle: textTheme.bodyMedium,
        ),
      ),
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}
