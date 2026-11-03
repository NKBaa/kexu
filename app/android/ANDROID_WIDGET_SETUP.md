# Android 桌面小组件接线说明（Lead 用）

> **接线状态**：Lead 已完成第 2、3、4 节的接线
> （`AndroidManifest.xml` 的 receiver、`MainActivity.configureFlutterEngine`
> 里的 `WidgetBridge.register(flutterEngine)`、`app.dart` 的
> `_syncHomeWidget()` 启动同步 + 课表/设置监听同步）。以下内容作为
> 复核与后续维护参考。

本文档说明「今日课表」桌面小组件的原生实现，以及 **Lead 需要在
`AndroidManifest.xml` / `MainActivity.kt` / `app.dart` 里补的接线**。

本任务没有改动 `MainActivity.kt` 和 `AndroidManifest.xml`（按约定由 Lead 统一接线）。

## 1. 新增文件

| 文件 | 作用 |
| --- | --- |
| `app/android/app/src/main/res/layout/widget_timetable.xml` | RemoteViews 布局：标题/日期·星期·第几周/节假日/4 行课程/空状态/更新时间 |
| `app/android/app/src/main/res/xml/timetable_widget_info.xml` | AppWidgetProviderInfo：默认 4x3 单元格、30 分钟周期刷新、可缩放 |
| `app/android/app/src/main/kotlin/com/coursetable/course_timetable/TimetableWidgetProvider.kt` | `AppWidgetProvider`：`onUpdate` 读快照渲染、点击打开 App、`saveSnapshot`/`updateAllWidgets` |
| `app/android/app/src/main/kotlin/com/coursetable/course_timetable/WidgetBridge.kt` | MethodChannel 桥：`object WidgetBridge { fun register(engine: FlutterEngine) }` |
| `app/lib/features/widget/timetable_widget_service.dart` | Flutter 侧：纯函数 `buildWidgetSnapshot` + `TimetableWidgetService`（MethodChannel） |
| `app/test/widget/timetable_widget_service_test.dart` | Dart 单测（纯函数 + MethodChannel mock） |

## 2. AndroidManifest.xml：加一个 receiver

在 `<application>` 里（和现有 `MainActivity`、`FileProvider` 同级）加：

```xml
<!-- 桌面小组件「今日课表」：系统通过 APPWIDGET_UPDATE 广播驱动更新。 -->
<receiver
    android:name=".TimetableWidgetProvider"
    android:exported="false"
    android:label="今日课表">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/timetable_widget_info" />
</receiver>
```

- 不需要新增任何权限；
- `android:exported="false"`：APPWIDGET_UPDATE 由系统以显式广播发给本组件，
  Android 12+ 的官方模板也用 false；如果测试机上老系统（Android 8 及以下）
  添加小组件后不刷新，可临时改成 `true` 验证；
- 若想用「立即刷新」广播，可加
  `<action android:name="com.coursetable.course_timetable.widget.ACTION_REFRESH" />`
  （对应 `TimetableWidgetProvider.ACTION_REFRESH`，可选）。

## 3. MainActivity.kt：加一行调用

`MainActivity.configureFlutterEngine` 里已有在线更新的通道注册，在
`super.configureFlutterEngine(flutterEngine)` 之后追加一行即可（同包，无需 import）：

```kotlin
override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    // 在线更新通道（已有，保持不动）
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
        .setMethodCallHandler { /* ... */ }

    // 桌面小组件桥（新增一行）
    WidgetBridge.register(flutterEngine)
}
```

`WidgetBridge.register(engine: FlutterEngine)` 是唯一入口，可重复调用
（同一引擎只注册一次），内部通过 `FlutterPlugin` 拿到 `applicationContext`，
引擎销毁时自动解绑。

## 4. app.dart：把快照推给原生

纯函数签名（已按 Lead 要求实现）：

```dart
Map<String, dynamic> buildWidgetSnapshot(
  Timetable timetable,
  AppSettings settings,
  DateTime now, {
  String? holiday, // 可选：调用方已知今天节假日时直接传入，优先级最高
});
```

`settings.holidays`（节假日列表）会自动按日期匹配今天的节日名称；
`holiday` 参数只在调用方已经算好时用来覆盖它。

推荐接线位置（`HomeShell` 的 `initState` postFrameCallback 里、课表/设置变化时）：

```dart
import 'features/widget/timetable_widget_service.dart';

// 首次/数据变化后同步一次（内部已吞掉异常，失败返回 false）
Future<void> _syncWidget() async {
  try {
    final timetable = ref.read(timetableProvider).valueOrNull;
    if (timetable == null) return;
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;
    await TimetableWidgetService().updateFromTimetable(timetable, settings);
  } catch (_) {
    // 小组件不是核心功能，失败不影响 App
  }
}
```

触发点建议：

1. `initState` 的 postFrameCallback 里调一次（App 启动即有数据）；
2. `ref.listen(timetableProvider, ...)` 课表变化后调（可 300~500ms 防抖）；
3. 设置页保存后调（节假日配置等）。

也可以绕过服务直接用纯函数：

```dart
final snapshot = buildWidgetSnapshot(timetable, settings, DateTime.now());
await TimetableWidgetService().updateWidget(snapshot);
```

## 5. 通道协议（Flutter ↔ 原生）

通道名：`com.coursetable.course_timetable/widget`

| 方法 | 参数 | 返回 | 说明 |
| --- | --- | --- | --- |
| `updateWidget` | `Map<String, dynamic> snapshot` | `bool` | 原生写入 SharedPreferences 并刷新所有小组件实例 |
| `isSupported` | 无 | `bool` | Android 恒为 true；Flutter 侧在非 Android 直接返回 false，不调通道 |

snapshot 字段（原生按这些 key 解析，改动必须同步改两侧）：

```json
{
  "date": "2025-09-17",
  "weekday": "周三",
  "week": 3,
  "holiday": null,
  "sessions": [
    {
      "name": "高等数学",
      "start": "10:00",
      "end": "11:40",
      "location": "A101",
      "teacher": "张老师",
      "isNow": true
    }
  ],
  "updatedAt": "2025-09-17T10:00:00.000"
}
```

- `date`：`yyyy-MM-dd`，原生与本地当天比较，不等就显示「打开课序查看今日课程」；
- `week`：教学周，`0` 表示不在学期内（原生不显示「第 N 周」）；
- `holiday`：节假日名称，`null` 表示没有；
- `sessions`：已按开始时间排序，时间来自**当天生效作息**；原生最多展示 4 条，
  超出显示「还有 N 门课」；
- `updatedAt`：ISO 8601，原生截取 `HH:mm` 显示「更新于 …」。

## 6. 原生侧行为

- 快照存于 SharedPreferences：文件名 `timetable_widget`，key `snapshot`（JSON 字符串）；
- `onUpdate` / `onEnabled` / 30 分钟周期刷新都只读快照渲染，**不依赖 Flutter 引擎运行**；
- 「正在上课」高亮用**当前时钟**重新判断（快照可能是上次同步时生成的），
  时间解析失败才退回快照里的 `isNow`；
- 点击小组件任意位置 → `packageManager.getLaunchIntentForPackage` 打开课序主界面
  （不直接引用 MainActivity，避免和现有 Activity 配置耦合）；
- 还没有任何快照（刚添加小组件、从未打开 App）时显示「打开课序查看今日课程」。

## 7. 验证

```powershell
cd C:\dev\kt
C:\dev\flutter\bin\flutter.bat analyze
C:\dev\flutter\bin\flutter.bat test test\widget
```

真机/模拟器：

1. 安装新 APK → 打开一次 App（触发首次 `updateWidget`）；
2. 桌面长按 → 小组件 → 找到「课序 / 今日课表」添加；
3. 验证：日期·星期·第几周、节假日行（有数据时）、4 条课程、正在上课高亮、
   点击打开 App；
4. 改系统日期到明天（或等第二天）→ 小组件应显示「打开课序查看今日课程」；
5. 强制停止 App → 小组件仍显示上次快照（说明不依赖引擎）。

## 8. 已知限制 / 遗留风险

1. **节假日依赖「节假日 / 上课提醒」任务的数据模型**：`buildWidgetSnapshot`
   已经接入 `AppSettings.holidays` + `holidayForDate`（来自
   `lib/core/utils/holiday_utils.dart`），设置页保存节假日后面板会显示；
   两个任务需要一起合并，若只合入本任务而 `AppSettings.holidays` 不存在，
   Dart 侧会编译失败；
2. **App 不开不会自动刷新**：30 分钟周期刷新只能重新渲染**已有快照**并更新
   「正在上课」高亮；课程数据变化必须等 App 运行后推送。若要求后台每日自动
   更新，需要再加 WorkManager/AlarmManager + 独立数据源（属于后续增强）；
3. **小组件无圆角背景**：本任务写入范围只含 `res/layout`、`res/xml`，
   不能新增 `res/drawable`，因此根布局用了纯色 `#F7F8FA`。Android 12+ 系统会
   自动给小组件加圆角；如要老系统也有圆角，Lead 可加
   `res/drawable/widget_background.xml`（`<shape>` + `<corners radius="16dp"/>`）
   并把布局根节点 `android:background` 改过去；
4. **启动入口**：用 `getLaunchIntentForPackage` 打开的是 Launcher Activity；
   若以后加了启动页/Splash，仍会正常进入；
5. **多用户/工作资料**：SharedPreferences 是应用级，多用户各自独立，无额外处理；
6. 小组件文案、颜色目前是硬编码（布局/Provider 内），未走主题色；
   后续要跟随深色模式可再抽 `values-night`（需要改 `res/values*`，本任务范围外）。
