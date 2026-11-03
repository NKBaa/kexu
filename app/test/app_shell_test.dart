import 'package:course_timetable/app.dart';
import 'package:course_timetable/core/theme.dart';
import 'package:course_timetable/data/models/app_settings.dart';
import 'package:course_timetable/data/models/course.dart';
import 'package:course_timetable/data/models/semester.dart';
import 'package:course_timetable/data/models/timetable.dart';
import 'package:course_timetable/data/models/update_config.dart';
import 'package:course_timetable/data/repositories/settings_repository.dart';
import 'package:course_timetable/data/repositories/timetable_history_repository.dart';
import 'package:course_timetable/data/repositories/timetable_repository.dart';
import 'package:course_timetable/data/services/update_service.dart';
import 'package:course_timetable/features/settings/pages/update_settings_page.dart';
import 'package:course_timetable/features/settings/providers/settings_provider.dart';
import 'package:course_timetable/features/timetable/providers/timetable_provider.dart';
import 'package:course_timetable/features/timetable/widgets/week_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 假更新服务：HomeShell 启动时会自动检查更新（默认仓库已写死），
/// widget 测试里必须拦掉，避免真的发网络请求。
class _NoopUpdateService extends UpdateService {
  @override
  Future<UpdateCheckResult> checkForUpdate({
    required UpdateConfig config,
    required String currentVersion,
    http.Client? client,
    UpdatePlatform? platform,
  }) async =>
      UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        updateAvailable: false,
        release: const ReleaseInfo(tagName: 'v0.0.0'),
      );
}

/// 内存版课表仓储。
///
/// **为什么需要它**：`flutter_test` 在伪异步时钟下运行，真实文件 I/O 的 Future
/// 不会完成（除非用 `tester.runAsync`）。若直接注入基于 `dart:io` 的仓储，
/// 页面会永远停在 loading 态，`pumpAndSettle` 会因为加载动画而无限等待。
/// 用内存实现既避开了这个问题，也让测试更快、更纯粹。
class InMemoryTimetableRepository extends TimetableRepository {
  InMemoryTimetableRepository([this._current]);

  Timetable? _current;

  @override
  Future<Timetable> load() async =>
      _current ?? Timetable(semester: _defaultSemester(), timeSlots: defaultTimeSlots());

  @override
  Future<void> save(Timetable timetable) async {
    _current = timetable;
  }

  static Semester _defaultSemester() => Semester(
        id: 'default',
        name: '默认学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      );
}

/// 内存版设置仓储。
class InMemorySettingsRepository extends SettingsRepository {
  InMemorySettingsRepository([
    this._current = const AppSettings(onboardingCompleted: true),
  ]);

  AppSettings _current;

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
  }
}

/// 内存版修改历史仓储（避免测试碰 path_provider / 真实文件）。
class InMemoryTimetableHistoryRepository extends TimetableHistoryRepository {
  final List<TimetableHistoryEntry> entries = <TimetableHistoryEntry>[];

  @override
  Future<List<TimetableHistoryEntry>> load() async =>
      List<TimetableHistoryEntry>.of(entries);

  @override
  Future<void> push(
    Timetable previous, {
    Timetable? next,
    DateTime? at,
    String? description,
  }) async {
    if (next != null && TimetableHistoryRepository.sameTimetable(previous, next)) {
      return;
    }
    if (entries.isNotEmpty &&
        TimetableHistoryRepository.sameTimetable(entries.last.timetable, previous)) {
      return;
    }
    entries.add(
      TimetableHistoryEntry(
        id: 'h${entries.length}',
        savedAt: at ?? DateTime.now(),
        timetable: previous,
        description: (description ?? '').trim(),
      ),
    );
    while (entries.length > TimetableHistoryRepository.defaultMaxEntries) {
      entries.removeAt(0);
    }
  }

  @override
  Future<TimetableHistoryEntry?> undoLatest() async =>
      entries.isEmpty ? null : entries.removeLast();
}

/// 一份「不规律课表」样本：单周课 + 断续周次课。
Timetable sampleTimetable() => Timetable(
      semester: Semester(
        id: 'sem1',
        name: '2026 春季学期',
        startMonday: DateTime(2026, 2, 23),
        totalWeeks: 16,
      ),
      timeSlots: defaultTimeSlots(),
      courses: [
        Course(
          id: 'c1',
          semesterId: 'sem1',
          name: '高等数学',
          teacher: '张老师',
          colorIndex: 0,
          sessions: const [
            Session(
              id: 's1',
              dayOfWeek: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: [1, 3, 5, 7, 9, 11, 13, 15], // 单周
              location: 'A101',
            ),
          ],
        ),
        Course(
          id: 'c2',
          semesterId: 'sem1',
          name: '数据结构',
          teacher: '李老师',
          colorIndex: 1,
          sessions: const [
            Session(
              id: 's2',
              dayOfWeek: 3,
              startPeriod: 5,
              endPeriod: 6,
              weeks: [3, 4, 5, 7, 8, 9], // 断续周次
              location: 'B203',
            ),
          ],
        ),
      ],
    );

void main() {
  /// 用固定的若干帧推进，而不是 `pumpAndSettle`。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpApp(WidgetTester tester, {Timetable? seed}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider
              .overrideWithValue(InMemoryTimetableRepository(seed)),
          settingsRepositoryProvider
              .overrideWithValue(InMemorySettingsRepository()),
          timetableHistoryRepositoryProvider
              .overrideWithValue(InMemoryTimetableHistoryRepository()),
          updateServiceProvider.overrideWithValue(_NoopUpdateService()),
        ],
        child: const CourseTimetableApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpShellOnly(WidgetTester tester, {Timetable? seed}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timetableRepositoryProvider
              .overrideWithValue(InMemoryTimetableRepository(seed)),
          settingsRepositoryProvider
              .overrideWithValue(InMemorySettingsRepository()),
          timetableHistoryRepositoryProvider
              .overrideWithValue(InMemoryTimetableHistoryRepository()),
          updateServiceProvider.overrideWithValue(_NoopUpdateService()),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const HomeShell()),
      ),
    );
    await settle(tester);
  }

  testWidgets('首次运行（无数据）能正常进入主界面，不崩溃', (tester) async {
    await pumpApp(tester);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('课表'), findsWidgets);
  });

  testWidgets('顶栏撤销/重做按钮在没有历史时禁用', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('timetable_undo_button')), findsOneWidget);
    expect(find.byKey(const Key('timetable_redo_button')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('timetable_undo_button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('timetable_redo_button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('修改后可撤销并重做', (tester) async {
    await pumpApp(tester, seed: sampleTimetable());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    final before = container.read(timetableProvider).value!;
    await container
        .read(timetableProvider.notifier)
        .replaceTimetable(before.copyWith(courses: const []));
    await settle(tester);
    expect(
      find.byTooltip('撤销：删除课程「高等数学」、「数据结构」'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('timetable_undo_button')));
    await tester.pumpAndSettle();
    expect(container.read(timetableProvider).value!.courses, hasLength(2));
    expect(
      find.byTooltip('重做：删除课程「高等数学」、「数据结构」'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('timetable_redo_button')));
    await tester.pumpAndSettle();
    expect(container.read(timetableProvider).value!.courses, isEmpty);
    // 让撤销/重做提示的 SnackBar 计时器结束，避免测试结束时仍有 pending timer。
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('第 1 周只显示当周有课的课程（不规律周次生效）', (tester) async {
    await pumpApp(tester, seed: sampleTimetable());

    // 高等数学 weeks=[1,3,...,15] -> 第 1 周有课
    expect(find.text('高等数学'), findsWidgets);
    // 数据结构 weeks=[3,4,5,7,8,9] -> 第 1 周无课，不应出现
    expect(find.text('数据结构'), findsNothing);
  });

  testWidgets('左右划动课表可切换周次', (tester) async {
    await pumpApp(tester, seed: sampleTimetable());

    expect(find.textContaining('第 1 周'), findsOneWidget);
    expect(find.text('第 1 周'), findsOneWidget);
    expect(find.textContaining('学期结束'), findsNothing);

    // 向左滑 -> 下一周；向右滑 -> 上一周。
    await tester.fling(find.byType(WeekGrid), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(find.text('第 2 周'), findsOneWidget);

    // 顶栏「回到本周」可直接跳回。
    await tester.tap(find.byKey(const Key('timetable_this_week')));
    await settle(tester);
    expect(find.text('第 1 周'), findsOneWidget);

    await tester.fling(find.byType(WeekGrid), const Offset(400, 0), 1200);
    await settle(tester);
    expect(find.textContaining('第 1 周'), findsOneWidget);
  });

  testWidgets('拖动柄横向跨天不会误触发周次切换', (tester) async {
    await pumpApp(tester, seed: sampleTimetable());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    final beforeWeek = container.read(currentWeekProvider);

    final handle = find.byKey(const ValueKey('course_drag_handle_s1'));
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(105, 0));
    await settle(tester);

    final timetable = container.read(timetableProvider).value!;
    final session = timetable.courses.first.sessions.first;
    expect(session.dayOfWeek, 2, reason: '拖动柄应能在同一周内跨天移动');
    expect(container.read(currentWeekProvider), beforeWeek, reason: '拖动课程不应切换周次');
    final notice = find.byKey(const ValueKey('app_notice'));
    expect(notice, findsOneWidget);
    final noticeRect = tester.getRect(notice);
    expect(noticeRect.top, greaterThan(kToolbarHeight));
    expect(noticeRect.top, lessThan(200),
        reason: '提示条应位于星期表头下方');
    // 让提示条自动消失，避免测试结束时还有未完成的 Timer。
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('切到第 3 周后两门课都显示', (tester) async {
    await pumpApp(tester, seed: sampleTimetable());

    // 点标题打开周次选择，直接选第 3 周。
    await tester.tap(find.byKey(const Key('timetable_week_title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('week_picker_3')));
    await settle(tester);

    expect(find.text('高等数学'), findsWidgets);
    expect(find.text('数据结构'), findsWidgets);
  });

  testWidgets('单周课显示为「1-15周(单)」这类可读标签', (tester) async {
    // 周次标签在卡片过窄时会自动隐藏（窄列优先保住课程名），
    // 所以这里用宽窗口来验证标签本身能正确渲染。
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    // 不规律周次必须被压缩展示，而不是罗列 1,3,5,...
    expect(find.textContaining('单'), findsWidgets);
  });

  testWidgets('窄屏使用底部导航栏，宽屏使用侧边导航栏', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump();
    await settle(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('批量修改收在更多菜单，日程页签列出课程', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    await tester.tap(find.byKey(const Key('timetable_more_button')));
    await tester.pumpAndSettle();
    expect(find.text('批量修改'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timetable_batch_button')));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('日程'));
    await tester.pumpAndSettle();
    expect(find.text('日程'), findsWidgets);
    expect(find.text('高等数学'), findsWidgets);
  });

  testWidgets('切换到「设置」页签能正常渲染', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    await tester.tap(find.text('设置'));
    await settle(tester);

    expect(find.textContaining('学期'), findsWidgets);
  });

  testWidgets('深色主题下主界面可正常渲染', (tester) async {
    await pumpShellOnly(tester, seed: sampleTimetable());

    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('空课表时显示引导空状态', (tester) async {
    await pumpApp(tester);

    // 空状态应给出「添加课程 / 导入课表」的引导
    expect(find.textContaining('添加'), findsWidgets);
  });

  testWidgets('「添加」收在更多菜单中', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    await tester.tap(find.byKey(const Key('timetable_more_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('timetable_add_button')),
      findsOneWidget,
      reason: '添加入口应在更多菜单里',
    );
    expect(find.text('添加课程'), findsOneWidget);
  });

  testWidgets('窄屏下「添加」仍在更多菜单中', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    await tester.tap(find.byKey(const Key('timetable_more_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timetable_add_button')), findsOneWidget);
    expect(find.text('添加课程'), findsOneWidget);
  });

  testWidgets('课表顶栏分享按钮提供日历与 JSON 两种文件', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    expect(find.byKey(const Key('timetable_more_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('timetable_more_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timetable_share_button')));
    await tester.pumpAndSettle();

    expect(find.text('分享日历文件（.ics）'), findsOneWidget);
    expect(find.text('分享 JSON 文件'), findsOneWidget);
    expect(find.byKey(const Key('share_ics_option')), findsOneWidget);
    expect(find.byKey(const Key('share_json_option')), findsOneWidget);
  });

  testWidgets('更多菜单提供重启教程按钮', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());
    await tester.tap(find.byKey(const Key('timetable_more_button')));
    await tester.pumpAndSettle();
    expect(find.text('重启教程'), findsOneWidget);
    expect(find.byKey(const Key('timetable_tutorial_button')), findsOneWidget);
  });

  testWidgets('AI 助手在右下角悬浮按钮，添加在更多菜单', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    expect(find.byKey(const Key('home_ai_fab')), findsOneWidget);
    expect(find.byKey(const Key('home_add_fab')), findsNothing);
    await tester.tap(find.byKey(const Key('timetable_more_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timetable_add_button')), findsOneWidget);
  });

  testWidgets('AI 悬浮按钮以扩散动画打开 AI 界面', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());
    await tester.tap(find.byKey(const Key('home_ai_fab')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(find.text('课序 AI'), findsOneWidget);
    expect(find.textContaining('一句话改课表'), findsWidgets);
  });

  testWidgets('非课表页签不显示 AI 悬浮按钮', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());
    expect(find.byKey(const Key('home_ai_fab')), findsOneWidget);

    await tester.tap(find.text('设置'));
    await settle(tester);
    expect(find.byKey(const Key('home_ai_fab')), findsNothing,
        reason: 'AI 悬浮按钮只在课表页出现');
  });

  testWidgets('手机竖屏一屏放下 7 天，不需要横向滑动', (tester) async {
    // 1264×2780 @3x ≈ 421dp 宽，是常见手机竖屏宽度。
    tester.view.physicalSize = const Size(1264, 2780);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpApp(tester, seed: sampleTimetable());

    // 七个星期表头都必须完整落在屏幕内（若退化横向滚动，周日会排到屏幕右侧外面）。
    for (final name in ['一', '二', '三', '四', '五', '六', '日']) {
      final rect = tester.getRect(find.text(name));
      expect(
        rect.right,
        lessThanOrEqualTo(422),
        reason: '星期$name 应在一屏内，不应需要横向滑动',
      );
    }
  });
}
