import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 上课提醒的 Dart 侧服务：只负责与 Android 原生通知桥通信。
///
/// 原生实现见 `android/app/src/main/kotlin/com/coursetable/course_timetable/`
/// 下的 `NotificationBridge.kt` / `ClassReminderScheduler.kt` /
/// `NotificationReceiver.kt`。
///
/// 设计原则：**所有平台差异都在原生侧消化**。Dart 侧只发命令、拿结果；
/// 遇到「当前平台没有实现」（Windows 桌面、单元测试）时静默降级，
/// 绝不因为通知功能不可用而让设置页崩溃。
class ClassReminderService {
  ClassReminderService({MethodChannel? channel})
      : _channel = channel ?? methodChannel;

  /// 与原生约定的通道名（MainActivity 里通过 `NotificationBridge.attach` 注册）。
  static const String channelName =
      'com.coursetable.course_timetable/notifications';

  /// 默认通道实例（测试里可替换 mock handler）。
  static const MethodChannel methodChannel = MethodChannel(channelName);

  /// 通知权限已授予。
  static const String permissionGranted = 'granted';

  /// 通知权限被拒绝（或系统级通知总开关被关）。
  static const String permissionDenied = 'denied';

  /// 当前平台没有通知桥（Windows 桌面等）。
  static const String permissionUnsupported = 'unsupported';

  /// 拿不到状态（通道异常）。
  static const String permissionUnknown = 'unknown';

  final MethodChannel _channel;

  /// 当前平台是否可能有系统通知能力。
  ///
  /// 只用于 UI 提示，不作为是否调用通道的硬开关：即使判断有误，
  /// 调用失败也会被 [_invoke] 兜住。
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 读取当前通知权限状态。
  Future<String> permissionStatus() async {
    final raw = await _invoke<String>('permissionStatus');
    return _normalizePermission(raw);
  }

  /// 请求通知权限（Android 13+ 弹系统授权框）。
  ///
  /// 系统授权框是异步的，返回值是**请求发出后立刻**的状态；
  /// 用户点完「允许」后请再次调用 [permissionStatus] 刷新
  /// （设置页会在 App 回到前台时自动刷新）。
  Future<String> requestPermission() async {
    final raw = await _invoke<String>('requestPermission');
    return _normalizePermission(raw);
  }

  /// 把未来一段时间的课程提醒同步给原生排程器。
  ///
  /// [sessions] 每项包含 `date`（yyyy-MM-dd）、`start`（HH:mm）、
  /// `end`（HH:mm）、`name`、`location`。
  /// 原生侧会先取消旧闹钟再按新列表重新排程，因此可重复调用。
  Future<bool> syncSchedule(
    List<Map<String, dynamic>> sessions, {
    required int reminderMinutes,
    required String style,
  }) async {
    final result = await _invoke<bool>('syncSchedule', {
      'sessions': sessions,
      'reminderMinutes': reminderMinutes,
      'style': style,
    });
    return result ?? false;
  }

  /// 取消全部已排程的上课提醒。
  Future<void> cancelAll() async {
    await _invoke<bool>('cancelAll');
  }

  /// 打开系统的「本应用通知设置」页，方便用户手动开启通知/自启动。
  Future<bool> openNotificationSettings() async {
    final result = await _invoke<bool>('openNotificationSettings');
    return result ?? false;
  }

  Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // 非 Android 平台（Windows 桌面、单元测试）没有原生实现。
      return null;
    } on PlatformException catch (e) {
      debugPrint('通知桥调用 $method 失败：${e.code} ${e.message}');
      return null;
    }
  }

  static String _normalizePermission(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case permissionGranted:
        return permissionGranted;
      case permissionDenied:
        return permissionDenied;
      case permissionUnsupported:
        return permissionUnsupported;
      default:
        return permissionUnknown;
    }
  }
}

/// 通知服务实例（测试里可 override 成假实现）。
final classReminderServiceProvider = Provider<ClassReminderService>((ref) {
  return ClassReminderService();
});
