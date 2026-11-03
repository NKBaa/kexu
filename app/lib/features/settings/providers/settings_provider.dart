import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/holiday_utils.dart';
import '../../../data/models/ai_config.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/app_theme_spec.dart';
import '../../../data/models/holiday.dart';
import '../../../data/models/update_config.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/sync/sync_config.dart';

/// 设置仓储实例。
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// 应用设置。
final settingsProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  /// 最近一次保存失败的原因（为 null 表示正常）。
  String? lastPersistError;

  @override
  Future<AppSettings> build() async {
    try {
      return await _repo.load();
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
    try {
      await _repo.save(settings);
      lastPersistError = null;
    } catch (e) {
      // 配置写不进去时保留内存状态，让用户至少本次会话可用
      lastPersistError = '$e';
      debugPrint('设置保存失败：$e');
    }
  }

  Future<void> saveAiConfig(AiConfig config) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(aiConfig: config));
  }

  Future<void> saveSyncConfig(SyncConfig config) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(syncConfig: config));
  }

  Future<void> saveUpdateConfig(UpdateConfig config) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(updateConfig: config));
  }

  Future<void> setThemeMode(String mode) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(themeMode: mode));
  }

  /// 切换当前主题；找不到时回退到 default。
  Future<void> setActiveTheme(String id) async {
    final current = state.valueOrNull ?? const AppSettings();
    final exists = findTheme(current.customThemes, id) != null;
    await save(current.copyWith(activeThemeId: exists ? id : 'default'));
  }

  /// 新建或更新一个本地主题（按 id 覆盖）；不能覆盖内置主题。
  Future<void> upsertCustomTheme(AppThemeSpec theme) async {
    if (AppThemeSpec.builtIns.any((t) => t.id == theme.id)) {
      throw ArgumentError('不能覆盖内置主题 id：${theme.id}');
    }
    final current = state.valueOrNull ?? const AppSettings();
    final list = <AppThemeSpec>[
      for (final t in current.customThemes)
        if (t.id != theme.id) t,
      theme,
    ];
    await save(current.copyWith(customThemes: list));
  }

  /// 删除本地主题；如果正在使用则回退到 default。
  Future<void> removeCustomTheme(String id) async {
    final current = state.valueOrNull ?? const AppSettings();
    final list = current.customThemes.where((t) => t.id != id).toList();
    if (list.length == current.customThemes.length) return;
    await save(current.copyWith(
      customThemes: list,
      activeThemeId: current.activeThemeId == id ? 'default' : current.activeThemeId,
    ));
  }

  Future<void> setShowWeekend(bool value) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(showWeekend: value));
  }

  /// 整体替换节假日列表（会自动去重并按日期排序）。
  Future<void> setHolidays(List<Holiday> holidays) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(holidays: normalizeHolidays(holidays)));
  }

  /// 添加一个节假日；同一天已有记录时覆盖名称，避免重复。
  Future<void> addHoliday(Holiday holiday) async {
    final current = state.valueOrNull ?? const AppSettings();
    final next = current.holidays
        .where((h) => h.dateKey != holiday.dateKey)
        .toList()
      ..add(holiday);
    await save(current.copyWith(holidays: normalizeHolidays(next)));
  }

  /// 按 id 删除节假日。
  Future<void> removeHoliday(String id) async {
    final current = state.valueOrNull ?? const AppSettings();
    final next = current.holidays.where((h) => h.id != id).toList();
    if (next.length == current.holidays.length) return;
    await save(current.copyWith(holidays: normalizeHolidays(next)));
  }

  /// 是否开启上课提醒。
  Future<void> setClassReminderEnabled(bool value) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(classReminderEnabled: value));
  }

  /// 提前提醒的分钟数（只接受 5/10/15/30，其它值回退 10）。
  Future<void> setReminderMinutes(int minutes) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(
      current.copyWith(
        reminderMinutes: AppSettings.normalizeReminderMinutes(minutes),
      ),
    );
  }

  /// 通知样式：`system` 或 `vendor`（厂商活动卡片，实验）。
  Future<void> setNotificationStyle(String style) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(
      current.copyWith(
        notificationStyle: AppSettings.normalizeNotificationStyle(style),
      ),
    );
  }

  Future<void> completeOnboarding() async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(onboardingCompleted: true));
  }
}

/// 大模型配置（设置页与 AI 功能共用）。
///
/// 它从 [settingsProvider] 派生，但对外表现为独立的 `AsyncNotifier<AiConfig>`，
/// 这样设置页只需关心「保存 AI 配置」这一件事。
final aiConfigProvider =
    AsyncNotifierProvider<AiConfigController, AiConfig>(AiConfigController.new);

class AiConfigController extends AsyncNotifier<AiConfig> {
  @override
  Future<AiConfig> build() async {
    final settings = await ref.watch(settingsProvider.future);
    return settings.aiConfig;
  }

  Future<void> save(AiConfig config) async {
    state = AsyncData(config);
    await ref.read(settingsProvider.notifier).saveAiConfig(config);
  }
}

/// 主题模式（供 `MaterialApp.themeMode` 使用）。
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(settingsProvider).valueOrNull?.themeMode ?? 'system';
  switch (mode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});

/// 当前选中的自定义主题；null 表示使用内置暖白。
final activeThemeSpecProvider = Provider<AppThemeSpec?>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (settings == null) return null;
  if (settings.activeThemeId == 'default') return null;
  return findTheme(settings.customThemes, settings.activeThemeId);
});
