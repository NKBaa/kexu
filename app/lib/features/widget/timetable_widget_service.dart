/// Android 桌面小组件「今日课表」的 Flutter 侧实现。
///
/// 刻意分成两层职责：
///
/// 1. [buildWidgetSnapshot] 是**纯函数**：把课表 + 设置 + 当前时间压成原生
///    可渲染的 Map（snapshot）。它不碰平台通道，便于单元测试，也便于调用方
///    自己决定「什么时候生成快照」。
/// 2. [TimetableWidgetService] 只负责通道调用：把快照交给原生
///    `WidgetBridge.kt`，由原生写入 SharedPreferences 并刷新所有小组件实例。
///
/// 原生 `onUpdate` 渲染的是**上次写入的快照**，所以即使 Flutter 引擎没有
/// 运行（用户没打开 App），小组件也能显示内容；快照里的 `date` 不是今天时，
/// 原生会显示「打开课序查看今日课程」，避免展示过期的课程。
///
/// snapshot 结构（字段名与原生约定死，改动必须同步改
/// `TimetableWidgetProvider.kt`）：
///
/// ```text
/// {
///   "date": "2025-09-17",          // yyyy-MM-dd
///   "weekday": "周三",
///   "week": 3,                     // 教学周；0 表示不在学期内
///   "holiday": null,               // 节假日名称，可空
///   "sessions": [                  // 已按开始时间排序
///     {"name": "高等数学", "start": "10:00", "end": "11:40",
///      "location": "A101", "teacher": "张老师", "isNow": true}
///   ],
///   "updatedAt": "2025-09-17T10:00:00.000"
/// }
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/holiday_utils.dart';
import '../../core/utils/week_utils.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/semester.dart';
import '../../data/models/timetable.dart';

/// MethodChannel 名称，必须与 `WidgetBridge.CHANNEL` 完全一致。
const String timetableWidgetChannelName =
    'com.coursetable.course_timetable/widget';

/// 小组件最多展示的课程条数。
///
/// 原生布局固定 4 行；超出的课程原生用「还有 N 门课」提示。
const int timetableWidgetMaxSessions = 4;

/// 两位数字补零。
String _two(int value) => value.toString().padLeft(2, '0');

/// 生成 snapshot 里的 `date` 字段（`yyyy-MM-dd`，本地时区）。
String widgetDateLabel(DateTime now) =>
    '${now.year}-${_two(now.month)}-${_two(now.day)}';

/// 把 `HH:mm` 解析成「当天第几分钟」；格式不合法返回 null。
int? minutesOfDay(String? hhmm) {
  if (hhmm == null || hhmm.isEmpty) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// [now] 是否落在 `[start, end)` 之间（左闭右开）。
///
/// 时间缺失或格式不对时返回 false —— 宁可不高亮，也不要误报「正在上课」。
bool isSessionOngoing(String start, String end, DateTime now) {
  final startMinutes = minutesOfDay(start);
  final endMinutes = minutesOfDay(end);
  if (startMinutes == null || endMinutes == null) return false;
  if (endMinutes <= startMinutes) return false;
  final currentMinutes = now.hour * 60 + now.minute;
  return currentMinutes >= startMinutes && currentMinutes < endMinutes;
}

/// 生成桌面小组件快照（纯函数）。
///
/// - [now] 决定「今天」：日期、星期、教学周、当前/下一节课都由它换算；
/// - [settings] 提供节假日列表（`AppSettings.holidays`），用于判断今天是否放假；
/// - [holiday] 允许调用方直接指定今天的节假日名称（例如设置页已经算好），
///   优先级高于从 [settings] 解析出来的结果。
///
/// 不在学期内（未开学/已放假）时 `week` 为 0、`sessions` 为空，
/// 原生据此显示空状态。
Map<String, dynamic> buildWidgetSnapshot(
  Timetable timetable,
  AppSettings settings,
  DateTime now, {
  String? holiday,
}) {
  final rawWeek = weekOfDate(now, timetable.semester.startMonday);
  final inSemester = rawWeek >= 1 && rawWeek <= timetable.semester.totalWeeks;

  return <String, dynamic>{
    'date': widgetDateLabel(now),
    'weekday': weekdayName(now.weekday),
    'week': inSemester ? rawWeek : 0,
    'holiday': holiday ?? _holidayFromSettings(settings, now),
    'sessions': inSemester
        ? _todaySessions(timetable, rawWeek, now)
        : <Map<String, dynamic>>[],
    'updatedAt': now.toIso8601String(),
  };
}

/// 解析「今天」的节假日名称。
///
/// 数据来源是设置里的节假日列表（[AppSettings.holidays]），按日期精确匹配；
/// 今天不是节假日时返回 null，原生因此不显示节假日行。
String? _holidayFromSettings(AppSettings settings, DateTime now) {
  final holiday = holidayForDate(settings.holidays, now);
  return holiday?.name;
}

/// 取 [now] 当天、第 [week] 周的所有课程，按开始时间排序。
///
/// 节次 → 起止时间用的是**当天生效的作息**（[Timetable.slotsForDate]），
/// 这样夏季/冬季作息切换后小组件的时间也是对的。
List<Map<String, dynamic>> _todaySessions(
  Timetable timetable,
  int week,
  DateTime now,
) {
  final slotByPeriod = <int, TimeSlot>{
    for (final slot in timetable.slotsForDate(now)) slot.period: slot,
  };

  final sessions = <Map<String, dynamic>>[];
  for (final entry in timetable.entriesAt(week, now.weekday)) {
    final session = entry.session;
    final start = slotByPeriod[session.startPeriod]?.start ?? '';
    final end = slotByPeriod[session.endPeriod]?.end ?? '';
    sessions.add(<String, dynamic>{
      'name': entry.course.name,
      'start': start,
      'end': end,
      'location': session.location,
      'teacher': session.teacher ?? entry.course.teacher,
      'isNow': isSessionOngoing(start, end, now),
    });
  }

  // 按实际开始时间排序；同一时刻开始的课保持课表里的原始顺序（稳定排序）。
  final decorated = <MapEntry<int, Map<String, dynamic>>>[
    for (var i = 0; i < sessions.length; i++) MapEntry(i, sessions[i]),
  ];
  decorated.sort((a, b) {
    final ka = minutesOfDay(a.value['start'] as String?) ?? 24 * 60;
    final kb = minutesOfDay(b.value['start'] as String?) ?? 24 * 60;
    final byStart = ka.compareTo(kb);
    return byStart != 0 ? byStart : a.key.compareTo(b.key);
  });
  return <Map<String, dynamic>>[for (final entry in decorated) entry.value];
}

/// Flutter ↔ 原生小组件的通道封装。
///
/// 用法（由 app.dart 在课表/设置变化时调用）：
///
/// ```dart
/// final ok = await TimetableWidgetService().updateFromTimetable(
///   timetable,
///   settings,
/// );
/// ```
///
/// 非 Android 平台（Windows 桌面、测试）不会真正调用通道，直接返回 false，
/// 调用方无需自己判断平台。
class TimetableWidgetService {
  TimetableWidgetService({MethodChannel? channel, bool? isAndroid})
      : _channel = channel ?? const MethodChannel(timetableWidgetChannelName),
        _isAndroid = isAndroid ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final MethodChannel _channel;
  final bool _isAndroid;

  /// 当前平台是否可能支持桌面小组件（仅 Android）。
  bool get isSupportedPlatform => _isAndroid;

  /// 原生是否支持小组件。
  ///
  /// 通道未注册（例如 Windows、单元测试环境）时返回 false，不抛异常。
  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('查询桌面小组件支持情况失败：$e');
      return false;
    }
  }

  /// 把快照推给原生；原生写入 SharedPreferences 后刷新所有小组件实例。
  ///
  /// 返回是否成功。失败（平台不支持 / 原生异常）只返回 false，不抛异常，
  /// 避免小组件这种「非核心功能」把启动流程带崩。
  Future<bool> updateWidget(Map<String, dynamic> snapshot) async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('updateWidget', snapshot);
      return ok ?? false;
    } on MissingPluginException {
      // 原生桥还没接线（或运行在非 Android 平台）——静默失败即可。
      return false;
    } on PlatformException catch (e) {
      debugPrint('更新桌面小组件失败：$e');
      return false;
    }
  }

  /// 便捷方法：从课表 + 设置生成快照并推送。
  ///
  /// [now] 不传时取系统当前时间；[holiday] 可传入今天已知的节假日名称。
  Future<bool> updateFromTimetable(
    Timetable timetable,
    AppSettings settings, {
    DateTime? now,
    String? holiday,
  }) {
    final snapshot = buildWidgetSnapshot(
      timetable,
      settings,
      now ?? DateTime.now(),
      holiday: holiday,
    );
    return updateWidget(snapshot);
  }
}
