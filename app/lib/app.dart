import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:showcaseview/showcaseview.dart';

import 'core/app_info.dart';
import 'core/theme.dart';
import 'features/ai/ai_edit_page.dart';
import 'features/ai/ai_import_page.dart';
import 'features/editor/course_editor_page.dart';
import 'features/onboarding/onboarding_wizard_page.dart';
import 'features/onboarding/timetable_tour.dart';
import 'features/notifications/class_reminder_sessions.dart';
import 'features/schedule/schedule_page.dart';
import 'features/settings/pages/update_settings_page.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/settings_home_page.dart';
import 'features/sync/providers/sync_controller.dart';
import 'features/timetable/providers/timetable_provider.dart';
import 'features/timetable/timetable_page.dart';
import 'features/widget/timetable_widget_service.dart';

/// 应用根组件。
class CourseTimetableApp extends ConsumerWidget {
  const CourseTimetableApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(activeThemeSpecProvider);
    return MaterialApp(
      title: '课序',
      debugShowCheckedModeBanner: false,
      theme: spec == null
          ? AppTheme.light()
          : AppTheme.custom(spec, Brightness.light),
      darkTheme: spec == null
          ? AppTheme.dark()
          : AppTheme.custom(spec, Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      // 让日期选择器、文本选择菜单等 Material 组件显示中文
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AppEntry(),
    );
  }
}

/// 从 AI 悬浮按钮中心向全屏扩散的渐变揭示动画。
class _AiRevealRoute extends PageRouteBuilder<void> {
  _AiRevealRoute({required Offset origin})
      : super(
          transitionDuration: const Duration(milliseconds: 900),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const AiEditPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutQuart,
              reverseCurve: Curves.easeInCubic,
            );
            return AnimatedBuilder(
              animation: curved,
              builder: (context, _) {
                final size = MediaQuery.sizeOf(context);
                final radius = size.longestSide * 1.5 * curved.value;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipPath(
                      clipper: _CircleRevealClipper(
                        origin: origin,
                        radius: radius,
                      ),
                      child: child,
                    ),
                    if (curved.value < 0.999)
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _RevealGlowPainter(
                            origin: origin,
                            radius: radius,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        );
}

class _CircleRevealClipper extends CustomClipper<Path> {
  const _CircleRevealClipper({required this.origin, required this.radius});

  final Offset origin;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..addOval(Rect.fromCircle(center: origin, radius: radius));

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) =>
      oldClipper.origin != origin || oldClipper.radius != radius;
}

class _RevealGlowPainter extends CustomPainter {
  const _RevealGlowPainter({
    required this.origin,
    required this.radius,
    required this.color,
  });

  final Offset origin;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: origin, radius: radius);
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: 0),
        color.withValues(alpha: 0.22),
        color.withValues(alpha: 0),
      ],
      stops: const [0.62, 0.9, 1],
    ).createShader(rect);
    canvas.drawCircle(origin, radius, Paint()..shader = shader);
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_RevealGlowPainter oldDelegate) =>
      oldDelegate.origin != origin ||
      oldDelegate.radius != radius ||
      oldDelegate.color != color;
}

/// 首次启动先进入使用向导；完成后恢复正常主界面。
class _AppEntry extends ConsumerWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settingsProvider);
    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => const HomeShell(),
      data: (settings) => settings.onboardingCompleted
          ? const HomeShell()
          : const OnboardingWizardPage(),
    );
  }
}

/// 主框架：课表 / 批量操作 / 设置 三个页签。
///
/// 宽屏（Windows、平板）用 `NavigationRail`，窄屏（手机）用底部 `NavigationBar`，
/// 这是 Flutter 官方推荐的响应式导航做法，一套代码同时适配两端。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _tourScheduled = false;
  final GlobalKey _aiFabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    ShowcaseView.register(
      globalTooltipActionConfig: const TooltipActionConfig(
        position: TooltipActionPosition.inside,
        alignment: MainAxisAlignment.spaceBetween,
      ),
      globalTooltipActions: [
        TooltipActionButton(
          type: TooltipDefaultActionType.previous,
          name: '上一步',
          hideActionWidgetForShowcase: [TimetableTutorialKeys.weekTitle],
        ),
        TooltipActionButton(
          type: TooltipDefaultActionType.next,
          name: '下一步',
          hideActionWidgetForShowcase: [TimetableTutorialKeys.grid],
        ),
      ],
    );
    // 启动后：先按用户设置跳到当前教学周，再触发一次自动同步
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _jumpToCurrentWeekIfNeeded();
      if (!mounted) return;
      await _cleanupOldInstallers();
      if (!mounted) return;
      await _syncClassReminders();
      if (!mounted) return;
      await _syncHomeWidget();
      if (!mounted) return;
      ref.read(autoSyncProvider).onAppStart();
      await _checkUpdateSilently();
    });
  }

  /// 更新安装完成后，下次启动自动清理旧安装包。
  Future<void> _cleanupOldInstallers() async {
    try {
      await ref
          .read(updateServiceProvider)
          .cleanupOldInstallers(currentVersion: appVersion);
    } catch (_) {
      // 清理失败不影响启动。
    }
  }

  /// 把课表 + 节假日设置同步给原生通知排程器；失败静默。
  Future<void> _syncClassReminders() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      final timetable = await ref.read(timetableProvider.future);
      await syncFromTimetable(timetable, settings);
    } catch (_) {
      // 通知不是核心功能，失败不影响课表使用。
    }
  }

  /// 把今日课表推送到 Android 桌面小组件；非 Android/失败时静默。
  Future<void> _syncHomeWidget() async {
    try {
      final timetable = ref.read(timetableProvider).valueOrNull;
      if (timetable == null) return;
      final settings = await ref.read(settingsProvider.future);
      await TimetableWidgetService().updateFromTimetable(timetable, settings);
    } catch (_) {
      // 小组件不是核心功能，失败不影响 App。
    }
  }

  /// 启动时静默检查更新。
  ///
  /// 只在用户填了 GitHub 仓库且开启「启动时自动检查」时执行；
  /// 失败一律静默（网络波动很常见，不该打扰用户），
  /// 只有发现新版本、且不是用户忽略过的版本时，才用 SnackBar 提示一次。
  Future<void> _checkUpdateSilently() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      final config = settings.updateConfig;
      if (!config.autoCheck || !config.isConfigured) return;
      final result = await ref.read(updateServiceProvider).checkForUpdate(
            config: config,
            currentVersion: fullVersion,
          );
      if (!mounted || !result.updateAvailable) return;
      if (result.latestVersion == config.ignoredVersion) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('发现新版本 ${result.latestVersion}'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () {
                if (!mounted) return;
                _open(const UpdateSettingsPage());
              },
            ),
          ),
        );
    } catch (_) {
      // 自动检查失败静默处理：手动检查时才展示错误与重试
    }
  }

  /// 若用户开启「启动时自动定位到当前教学周」，把展示周次切到本周。
  ///
  /// 这个开关此前只存在于设置里、没有任何代码读取，属于静默失效；
  /// 这里补上实现：只有当前确实落在学期周次范围内才跳转，
  /// 假期或学期外保持第 1 周，避免把用户丢到一个空周次。
  Future<void> _jumpToCurrentWeekIfNeeded() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      if (!settings.autoJumpToCurrentWeek) return;
      await ref.read(timetableProvider.future);
      if (!mounted) return;
      final week = ref.read(academicWeekProvider);
      if (week >= 1) {
        ref.read(currentWeekProvider.notifier).setWeek(week);
      }
    } catch (_) {
      // 设置或课表尚未就绪时忽略，不影响启动
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _openNewCourse() => _open(const CourseEditorPage());

  void _openImageImport() => _open(const AiImportPage());

  void _openAiEdit() {
    final box = _aiFabKey.currentContext?.findRenderObject() as RenderBox?;
    final center = box != null && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset(
            MediaQuery.sizeOf(context).width - 64,
            MediaQuery.sizeOf(context).height - 100,
          );
    Navigator.of(context).push(_AiRevealRoute(origin: center));
  }

  /// 统一的「添加」面板：手动添加、图片转课表。
  ///
  /// 入口在课表顶栏；右下角悬浮按钮改为 AI 助手。
  /// 「一句话改课表」和图片上传都在 AI 助手里。
  Future<void> _showCreateSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('图片转课表'),
              subtitle: const Text('上传课表截图，由大模型识别成课程'),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('手动添加课程'),
              subtitle: const Text('逐个填写课程与上课时段'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    switch (action) {
      case 'manual':
        _openNewCourse();
      case 'image':
        _openImageImport();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 课表内容变化后触发自动同步（内部有防抖与内容哈希去重，
    // 连续编辑不会反复请求网盘）
    ref.listen(timetableProvider, (previous, next) {
      final hadData = previous?.valueOrNull != null;
      if (hadData && next.valueOrNull != null) {
        ref.read(autoSyncProvider).onTimetableChanged();
        unawaited(_syncClassReminders());
        unawaited(_syncHomeWidget());
      }
    });
    ref.listen(settingsProvider, (previous, next) {
      if (next.valueOrNull != null) {
        unawaited(_syncClassReminders());
        unawaited(_syncHomeWidget());
      }
    });

    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 900;

    if (ref.watch(timetableTourRequestProvider) && !_tourScheduled) {
      _tourScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        ref.read(timetableTourRequestProvider.notifier).state = false;
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) await startTimetableTour();
        _tourScheduled = false;
      });
    }

    final pages = <Widget>[
      TimetablePage(
        onAddRequested: _showCreateSheet,
      ),
      const SchedulePage(),
      const SettingsHomePage(),
    ];

    final body = IndexedStack(index: _index, children: pages);

    return Scaffold(
      body: useRail
          ? Row(
              children: [
                NavigationRail(
                  extended: width >= 1200,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: width >= 1200
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.calendar_view_week_outlined),
                      selectedIcon: Icon(Icons.calendar_view_week),
                      label: Text('课表'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.event_note_outlined),
                      selectedIcon: Icon(Icons.event_note),
                      label: Text('日程'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_view_week_outlined),
                  selectedIcon: Icon(Icons.calendar_view_week),
                  label: '课表',
                ),
                NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note),
                  label: '日程',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '设置',
                ),
              ],
            ),
      // AI 助手移到右下角悬浮按钮，添加入口放到顶栏。
      floatingActionButton: _index == 0
          ? Showcase(
              key: TimetableTutorialKeys.aiButton,
              title: 'AI 助手',
              description: '点这里可以一句话改课表，也可以发课表截图给 AI 看。',
              child: KeyedSubtree(
                key: const Key('home_ai_fab'),
                child: FloatingActionButton.extended(
                  key: _aiFabKey,
                  heroTag: 'ai_assistant_fab',
                  onPressed: _openAiEdit,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('AI'),
                  tooltip: 'AI 助手：一句话改课表、发图片',
                ),
              ),
            )
          : null,
    );
  }
}

