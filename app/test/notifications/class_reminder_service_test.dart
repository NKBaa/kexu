import 'package:course_timetable/features/notifications/class_reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart ↔ 原生通知桥的协议测试：验证方法名、参数与降级行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockHandler(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
      ClassReminderService.methodChannel,
      handler,
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(
      ClassReminderService.methodChannel,
      null,
    );
  });

  test('通道名与原生约定一致', () {
    expect(
      ClassReminderService.channelName,
      'com.coursetable.course_timetable/notifications',
    );
  });

  test('permissionStatus 透传并归一化原生返回值', () async {
    MethodCall? captured;
    mockHandler((call) async {
      captured = call;
      return 'granted';
    });

    final status = await ClassReminderService().permissionStatus();
    expect(captured!.method, 'permissionStatus');
    expect(status, ClassReminderService.permissionGranted);
  });

  test('permissionStatus 对未知返回值返回 unknown', () async {
    mockHandler((call) async => 'whatever');
    expect(
      await ClassReminderService().permissionStatus(),
      ClassReminderService.permissionUnknown,
    );
  });

  test('requestPermission 调用原生并返回状态', () async {
    mockHandler((call) async {
      expect(call.method, 'requestPermission');
      return 'denied';
    });
    expect(
      await ClassReminderService().requestPermission(),
      ClassReminderService.permissionDenied,
    );
  });

  test('syncSchedule 传参正确并返回原生结果', () async {
    MethodCall? captured;
    mockHandler((call) async {
      captured = call;
      return true;
    });

    final sessions = [
      {
        'date': '2026-09-07',
        'start': '08:00',
        'end': '09:40',
        'name': '高等数学',
        'location': 'A101',
      },
    ];
    final ok = await ClassReminderService().syncSchedule(
      sessions,
      reminderMinutes: 15,
      style: 'vendor',
    );

    expect(ok, isTrue);
    expect(captured!.method, 'syncSchedule');
    final args = captured!.arguments as Map<Object?, Object?>;
    expect(args['reminderMinutes'], 15);
    expect(args['style'], 'vendor');
    final passedSessions = args['sessions'] as List<Object?>;
    expect(passedSessions.length, 1);
    expect(
      (passedSessions.single as Map<Object?, Object?>)['name'],
      '高等数学',
    );
  });

  test('cancelAll 调用原生 cancelAll', () async {
    MethodCall? captured;
    mockHandler((call) async {
      captured = call;
      return true;
    });
    await ClassReminderService().cancelAll();
    expect(captured!.method, 'cancelAll');
  });

  test('openNotificationSettings 返回原生结果', () async {
    mockHandler((call) async {
      expect(call.method, 'openNotificationSettings');
      return true;
    });
    expect(await ClassReminderService().openNotificationSettings(), isTrue);
  });

  test('通道未实现时安全降级（Windows 桌面 / 未接线）', () async {
    mockHandler((call) async => throw MissingPluginException());

    final service = ClassReminderService();
    expect(
      await service.permissionStatus(),
      ClassReminderService.permissionUnknown,
    );
    expect(
      await service.syncSchedule(const [], reminderMinutes: 10, style: 'system'),
      isFalse,
    );
    expect(await service.openNotificationSettings(), isFalse);
    // cancelAll 不抛异常即视为成功
    await service.cancelAll();
  });

  test('原生返回 PlatformException 时安全降级', () async {
    mockHandler((call) async {
      throw PlatformException(code: 'SYNC_FAILED', message: 'boom');
    });

    final service = ClassReminderService();
    expect(
      await service.syncSchedule(const [], reminderMinutes: 10, style: 'system'),
      isFalse,
    );
    expect(await service.permissionStatus(), ClassReminderService.permissionUnknown);
  });
}
