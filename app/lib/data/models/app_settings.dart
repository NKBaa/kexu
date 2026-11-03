import '../../core/utils/json_utils.dart';
import 'ai_config.dart';
import 'app_theme_spec.dart';
import 'holiday.dart';
import 'update_config.dart';
import '../sync/sync_config.dart';

/// 应用级设置（与课表数据分开存储，避免清空课表时丢掉 API Key）。
class AppSettings {
  /// 大模型接入配置。
  final AiConfig aiConfig;

  /// 网盘同步配置。
  final SyncConfig syncConfig;

  /// 在线更新配置（GitHub 仓库、镜像、自动检查）。
  final UpdateConfig updateConfig;

  /// 主题模式：`system` / `light` / `dark`。
  final String themeMode;

  /// 当前主题 id；`default` 表示内置暖白。
  final String activeThemeId;

  /// 用户自建/从市场安装的主题。
  final List<AppThemeSpec> customThemes;

  /// 课表是否显示周六、周日。
  final bool showWeekend;

  /// 启动时是否自动定位到当前教学周。
  final bool autoJumpToCurrentWeek;

  /// 是否已完成首次使用向导。
  final bool onboardingCompleted;

  /// 节假日列表（放假当天不排上课提醒）。
  final List<Holiday> holidays;

  /// 是否开启上课提醒（Android 通知）。
  final bool classReminderEnabled;

  /// 提前多少分钟提醒，只允许 [reminderMinuteOptions] 里的值。
  final int reminderMinutes;

  /// 通知样式：`system`（系统通知）/ `vendor`（厂商活动卡片，实验）。
  final String notificationStyle;

  /// 提前提醒的合法选项（分钟）。
  static const List<int> reminderMinuteOptions = [5, 10, 15, 30];

  /// 通知样式的合法取值。
  static const List<String> notificationStyleOptions = ['system', 'vendor'];

  const AppSettings({
    this.aiConfig = const AiConfig(),
    this.syncConfig = const SyncConfig(),
    this.updateConfig = const UpdateConfig(),
    this.themeMode = 'system',
    this.activeThemeId = 'default',
    this.customThemes = const [],
    this.showWeekend = true,
    this.autoJumpToCurrentWeek = true,
    this.onboardingCompleted = false,
    this.holidays = const [],
    this.classReminderEnabled = false,
    this.reminderMinutes = 10,
    this.notificationStyle = 'system',
  });

  /// 把任意分钟数收敛到合法选项，非法时回退到 10 分钟。
  static int normalizeReminderMinutes(int? value) {
    if (value == null) return 10;
    return reminderMinuteOptions.contains(value) ? value : 10;
  }

  /// 把任意样式字符串收敛到合法取值，非法时回退到 `system`。
  static String normalizeNotificationStyle(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return notificationStyleOptions.contains(v) ? v : 'system';
  }

  AppSettings copyWith({
    AiConfig? aiConfig,
    SyncConfig? syncConfig,
    UpdateConfig? updateConfig,
    String? themeMode,
    String? activeThemeId,
    List<AppThemeSpec>? customThemes,
    bool? showWeekend,
    bool? autoJumpToCurrentWeek,
    bool? onboardingCompleted,
    List<Holiday>? holidays,
    bool? classReminderEnabled,
    int? reminderMinutes,
    String? notificationStyle,
  }) =>
      AppSettings(
        aiConfig: aiConfig ?? this.aiConfig,
        syncConfig: syncConfig ?? this.syncConfig,
        updateConfig: updateConfig ?? this.updateConfig,
        themeMode: themeMode ?? this.themeMode,
        activeThemeId: activeThemeId ?? this.activeThemeId,
        customThemes: customThemes ?? this.customThemes,
        showWeekend: showWeekend ?? this.showWeekend,
        autoJumpToCurrentWeek: autoJumpToCurrentWeek ?? this.autoJumpToCurrentWeek,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
        holidays: holidays ?? this.holidays,
        classReminderEnabled: classReminderEnabled ?? this.classReminderEnabled,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        notificationStyle: notificationStyle ?? this.notificationStyle,
      );

  Map<String, dynamic> toJson() => {
        'aiConfig': aiConfig.toJson(),
        'syncConfig': syncConfig.toJson(),
        'updateConfig': updateConfig.toJson(),
        'themeMode': themeMode,
        'activeThemeId': activeThemeId,
        'customThemes': [for (final t in customThemes) t.toJson()],
        'showWeekend': showWeekend,
        'autoJumpToCurrentWeek': autoJumpToCurrentWeek,
        'onboardingCompleted': onboardingCompleted,
        'holidays': holidays.map((h) => h.toJson()).toList(),
        'classReminderEnabled': classReminderEnabled,
        'reminderMinutes': reminderMinutes,
        'notificationStyle': notificationStyle,
      };

  static List<AppThemeSpec> _themesFromJson(dynamic raw) {
    final themes = <AppThemeSpec>[];
    for (final item in asList(raw)) {
      if (item is! Map) continue;
      try {
        themes.add(AppThemeSpec.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // 单个主题损坏不影响其它主题。
      }
    }
    return themes;
  }

  static AppSettings fromJson(Map<String, dynamic> j) {
    final ai = j['aiConfig'];
    final sync = j['syncConfig'];
    final update = j['updateConfig'];
    return AppSettings(
      aiConfig: ai is Map
          ? AiConfig.fromJson(Map<String, dynamic>.from(ai))
          : const AiConfig(),
      syncConfig: sync is Map
          ? SyncConfig.fromJson(Map<String, dynamic>.from(sync))
          : const SyncConfig(),
      updateConfig: update is Map
          ? UpdateConfig.fromJson(Map<String, dynamic>.from(update))
          : const UpdateConfig(),
      themeMode: (j['themeMode'] ?? 'system').toString(),
      activeThemeId: (j['activeThemeId'] ?? 'default').toString(),
      customThemes: _themesFromJson(j['customThemes']),
      showWeekend: j['showWeekend'] is bool ? j['showWeekend'] as bool : true,
      autoJumpToCurrentWeek:
          j['autoJumpToCurrentWeek'] is bool ? j['autoJumpToCurrentWeek'] as bool : true,
      onboardingCompleted:
          j['onboardingCompleted'] is bool ? j['onboardingCompleted'] as bool : false,
      holidays: asList(j['holidays'])
          .map((e) => Holiday.fromJson(asMap(e)))
          .toList(growable: false),
      classReminderEnabled: j['classReminderEnabled'] is bool
          ? j['classReminderEnabled'] as bool
          : false,
      reminderMinutes: normalizeReminderMinutes(asInt(j['reminderMinutes'])),
      notificationStyle:
          normalizeNotificationStyle(asString(j['notificationStyle'])),
    );
  }
}
