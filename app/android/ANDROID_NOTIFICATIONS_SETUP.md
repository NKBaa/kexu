# 上课提醒（Android 通知）接线说明

> 给 Lead 的接线清单。Dart/原生代码已经写好，**这里列出的 manifest、MainActivity、
> app.dart、settings_home_page.dart 的改动需要 Lead 来落地**（本任务约定不改这些文件）。

**当前状态（写本文档时）**：以下接线已在仓库中就位，可直接对照核对：

- `MainActivity.kt` → `NotificationBridge.attach(this, flutterEngine)` ✅
- `AndroidManifest.xml` → `POST_NOTIFICATIONS` / `SCHEDULE_EXACT_ALARM` /
  `RECEIVE_BOOT_COMPLETED` + 两个 receiver ✅
- `app.dart` → 启动时与 `timetableProvider` / `settingsProvider` 变化时调用
  `syncFromTimetable(timetable, settings)` ✅
- `settings_home_page.dart` → 「节假日与提醒」二级菜单入口 ✅

下面的第 2–5 节保留为核对清单与背景说明（若后续重装工程/回滚可照此重接）。

## 1. 代码清单（已实现，无需再改）

Dart：

| 文件 | 作用 |
| --- | --- |
| `lib/data/models/holiday.dart` | `Holiday` 模型（id/date/name，date 只取年月日） |
| `lib/core/utils/holiday_utils.dart` | `holidayForDate` / `isHolidayDate` / 排序等纯函数 |
| `lib/data/models/app_settings.dart` | 新增 `holidays` / `classReminderEnabled` / `reminderMinutes` / `notificationStyle` |
| `lib/features/settings/providers/settings_provider.dart` | 新增 setter（addHoliday / removeHoliday / setClassReminderEnabled / setReminderMinutes / setNotificationStyle） |
| `lib/features/settings/pages/holiday_reminder_page.dart` | 「节假日与提醒」设置页 |
| `lib/features/notifications/class_reminder_service.dart` | MethodChannel 封装（`com.coursetable.course_timetable/notifications`） |
| `lib/features/notifications/class_reminder_sessions.dart` | `buildReminderSessions`（纯函数）+ `syncFromTimetable` |

Kotlin（`android/app/src/main/kotlin/com/coursetable/course_timetable/`）：

| 文件 | 作用 |
| --- | --- |
| `NotificationBridge.kt` | MethodChannel 注册、通知权限、渠道创建、系统设置跳转 |
| `ClassReminderScheduler.kt` | AlarmManager 排未来 7 天提醒（精确闹钟降级、持久化、开机恢复） |
| `NotificationReceiver.kt` | `NotificationReceiver`（发通知）+ `ClassReminderBootReceiver`（开机/时区变化恢复） |

## 2. AndroidManifest.xml 需要新增的权限

在 `<manifest>` 下（`INTERNET` 等已有权限旁边）追加：

```xml
<!-- Android 13+ 发送通知必须的运行时权限 -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- Android 12+ 精确闹钟（用户可在系统设置里撤销；未授予时代码会自动降级为不精确闹钟） -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>

<!-- 可选：声明「闹钟/日历类」应用可直接使用精确闹钟。
     仅当确认要上架 Google Play 且符合其政策时再加，否则保持注释。 -->
<!-- <uses-permission android:name="android.permission.USE_EXACT_ALARM"/> -->

<!-- 开机后恢复提醒排程（AlarmManager 的闹钟在重启后会丢失） -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

## 3. AndroidManifest.xml 需要新增的 receiver

放在 `<application>` 内、`<activity>` 之后（与 `<provider>` 同级）：

```xml
<!-- 上课提醒：闹钟到点后发通知。只接收本 App 的 PendingIntent，不对外暴露 -->
<receiver
    android:name=".NotificationReceiver"
    android:exported="false"/>

<!-- 开机 / App 更新 / 时区或时间变化后恢复提醒排程。
     exported=false 仍能收到系统广播（系统不受 exported 限制）。 -->
<receiver
    android:name=".ClassReminderBootReceiver"
    android:enabled="true"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.TIMEZONE_CHANGED"/>
        <action android:name="android.intent.action.TIME_SET"/>
    </intent-filter>
</receiver>
```

> `TIME_SET` 对应 Kotlin 里的 `Intent.ACTION_TIME_CHANGED`（两者字符串一致），
> manifest 里必须写 `android.intent.action.TIME_SET`。

## 4. MainActivity.kt 接线（一行）

在 `configureFlutterEngine` 里注册通知桥（与现有 `update` 通道并列）：

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    // 上课提醒：注册通知桥（内部会创建通知渠道 + 挂 MethodChannel）
    NotificationBridge.attach(this, flutterEngine)

    // ……现有的 update 通道保持不变……
}
```

**方法签名**：`NotificationBridge.attach(activity: Activity, engine: FlutterEngine)`

- 必须传 `this`（Activity），因为 Android 13 的权限弹窗和跳系统设置都需要 Activity；
- 必须在 `super.configureFlutterEngine` 之后调用；
- `NotificationBridge` 与 `MainActivity` 同包，不需要额外 import。

## 5. Dart 侧接线

### 5.1 设置页入口（settings_home_page.dart）

在 `settingsSections()` 里追加一条（放在「学期与作息」后面比较自然）：

```dart
SettingsSection(
  id: 'holiday',
  title: '节假日与提醒',
  subtitle: '放假日期、上课提醒、通知权限',
  icon: Icons.notifications_active_outlined,
  builder: (_) => const HolidayReminderPage(),
),
```

并 `import 'pages/holiday_reminder_page.dart';`。

### 5.2 自动同步（app.dart）

在 `_HomeShellState.build` 里、现有 `ref.listen(timetableProvider, ...)` 旁边加监听，
课表或设置变化后重新排程（`syncFromTimetable` 内部是「先取消再重排」，可重复调用）：

```dart
void _syncClassReminders() {
  final timetable = ref.read(timetableProvider).valueOrNull;
  final settings = ref.read(settingsProvider).valueOrNull;
  if (timetable == null || settings == null) return;
  syncFromTimetable(timetable, settings).catchError((Object e) {
    debugPrint('同步上课提醒失败：$e');
  });
}

// build 里：
ref.listen(timetableProvider, (previous, next) {
  if (next.valueOrNull != null) _syncClassReminders();
});
ref.listen(settingsProvider, (previous, next) {
  if (next.valueOrNull != null) _syncClassReminders();
});
```

并在 `initState` 的启动流程里调用一次（首次安装/升级后把提醒排上）。
import：`import 'features/notifications/class_reminder_sessions.dart';`

> 说明：设置页自己也会在每次改动后同步一次，所以即使暂时不加这里的监听，
> 在设置页里改开关/时间也能生效；app.dart 的监听负责覆盖「课表被 AI/导入修改」
> 这类不经过设置页的变化。

## 6. 通知渠道与厂商卡片（重要限制）

两个渠道都是 `IMPORTANCE_HIGH`，都在 `NotificationBridge.ensureChannels()` 里创建：

| style | channel id | 渠道名 | 说明 |
| --- | --- | --- | --- |
| `system`（默认） | `class_reminder_system` | 上课提醒 | 标准系统通知 |
| `vendor` | `class_reminder_vendor` | 课序活动提醒 | 独立高优先级渠道，用于「厂商活动卡片（实验）」 |

必须如实告知用户（设置页已写）：

- **「厂商活动卡片」不保证一定出现。** OPPO / vivo / 小米等系统是否把一条通知
  渲染成横幅、活动卡片或锁屏卡片，由**系统自己的通知策略**决定，
  第三方 App 只能通过「独立渠道 + 高优先级 + category=event + 允许横幅」尽量争取。
- 渠道重要性在创建后**无法由代码改高**；用户手动把它降为「静默」后，
  只能引导用户去系统设置里改回来。
- 国产 ROM 常见的额外拦截项：**自启动、后台运行、锁屏通知、横幅通知、
  「通知智能管理」**。设置页的「打开系统通知设置」按钮只能打开系统通知页，
  自启动权限通常要用户自己在「手机管家 / 权限管理」里开。
- Android 12+ 未授予精确闹钟权限时，代码会**降级为不精确闹钟**
  （`setAndAllowWhileIdle`），提醒可能晚几分钟，不会丢。
- Android 13+ 未授予 `POST_NOTIFICATIONS` 时通知根本不会展示；
  设置页会显示「未授权」并提供请求按钮。

## 7. 验证步骤

1. 安装后进入「设置 → 节假日与提醒」：
   - 添加一个明天的节假日，确认列表出现、可删除；
   - 打开「开启上课提醒」，选「提前 5 分钟」，切到「厂商活动卡片（实验）」；
   - 点「请求通知权限」，允许后状态应变成「已授权」。
2. 把系统时间调到某节课开始前 6 分钟，等待 1 分钟，应收到通知
   （或把手机时间调到提醒时刻后观察）。
3. 命令行核对排程：
   ```bash
   adb shell dumpsys alarm | grep -i coursertable   # 或 grep course_timetable
   adb shell dumpsys notification --noredact | grep -i "class_reminder"
   ```
   应能看到 `class_reminder_system` / `class_reminder_vendor` 渠道，
   以及若干 `com.coursetable.course_timetable.CLASS_REMINDER_ALARM` 闹钟。
4. 重启手机，再次执行第 3 步，闹钟应被 `ClassReminderBootReceiver` 恢复。

## 8. 已知取舍

- 通知小图标用的是 App 的 launcher 图标（`applicationInfo.icon`），
  在部分 ROM 上会显示成白色剪影。若想要更标准的通知栏图标，
  后续可加一个单色 `drawable/ic_notification.xml` 并改
  `NotificationReceiver.smallIconRes()`，属于纯资源改动。
- 排程只覆盖未来 7 天（由 Dart 侧 `classReminderHorizonDays` 决定），
  需要 App 至少每 7 天被打开一次才能持续排程；这是为了避免长期占用
  AlarmManager 配额与耗电。
- 课表里的「调课/停课」调整（`Adjustment`）目前不参与提醒计算，
  只按常规周次排程；如需支持，可后续在 `buildReminderSessions` 里叠加。
