package com.coursetable.course_timetable

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 上课提醒的 Flutter ↔ 原生桥。
 *
 * Dart 侧对应 `lib/features/notifications/class_reminder_service.dart`，
 * 通道名 `com.coursetable.course_timetable/notifications`。
 *
 * 支持的方法：
 * - `permissionStatus`：读取通知权限状态，返回 `granted` / `denied`
 * - `requestPermission`：Android 13+ 弹出 POST_NOTIFICATIONS 授权框
 * - `syncSchedule`：{ sessions, reminderMinutes, style } → 交给
 *   [ClassReminderScheduler] 排未来 7 天的闹钟
 * - `cancelAll`：取消全部提醒
 * - `openNotificationSettings`：跳到系统的「本应用通知设置」页
 *
 * **接线方式（MainActivity 需要改一行）**：
 * ```kotlin
 * override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
 *     super.configureFlutterEngine(flutterEngine)
 *     NotificationBridge.attach(this, flutterEngine)
 * }
 * ```
 *
 * 注意：`requestPermission` 是**异步**的系统弹窗，方法调用会立刻返回
 * 当前状态；用户点完「允许」后，Dart 侧会在 App 回到前台时重新查询
 * `permissionStatus`（设置页已实现自动刷新）。
 */
object NotificationBridge {
    private const val TAG = "NotificationBridge"

    /** 与 Dart 约定的 MethodChannel 名。 */
    const val CHANNEL = "com.coursetable.course_timetable/notifications"

    /** 系统通知渠道（默认样式）。 */
    const val CHANNEL_SYSTEM = "class_reminder_system"

    /** 厂商活动卡片样式使用的独立高优先级渠道。 */
    const val CHANNEL_VENDOR = "class_reminder_vendor"

    const val STYLE_SYSTEM = "system"
    const val STYLE_VENDOR = "vendor"

    /** 通知强调色（与 App 主题的主色一致）。 */
    const val NOTIFICATION_COLOR = 0xFF4F5D86.toInt()

    /** POST_NOTIFICATIONS 的请求码。 */
    const val REQUEST_NOTIFICATIONS = 4301

    private const val PERMISSION_GRANTED = "granted"
    private const val PERMISSION_DENIED = "denied"

    /**
     * 注册通知通道（MainActivity 在 `configureFlutterEngine` 里调用）。
     *
     * @param activity 当前 Activity（请求权限、跳系统设置需要）
     * @param engine   FlutterEngine（创建 MethodChannel）
     */
    fun attach(activity: Activity, engine: FlutterEngine) {
        ensureChannels(activity.applicationContext)

        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionStatus" -> result.success(permissionStatus(activity))
                    "requestPermission" -> {
                        requestPermission(activity)
                        result.success(permissionStatus(activity))
                    }
                    "syncSchedule" -> handleSyncSchedule(activity, call, result)
                    "cancelAll" -> {
                        ClassReminderScheduler.cancelAll(activity.applicationContext)
                        result.success(true)
                    }
                    "openNotificationSettings" ->
                        result.success(openNotificationSettings(activity))
                    else -> result.notImplemented()
                }
            }
    }

    /** 当前通知权限状态：`granted` / `denied`。 */
    fun permissionStatus(context: Context): String {
        val notificationsEnabled =
            NotificationManagerCompat.from(context).areNotificationsEnabled()
        val runtimeGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return if (runtimeGranted && notificationsEnabled) {
            PERMISSION_GRANTED
        } else {
            PERMISSION_DENIED
        }
    }

    /**
     * 请求通知权限（Android 13+）。
     *
     * 低于 Android 13 或已经授权时直接返回，不发系统弹窗。
     */
    fun requestPermission(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return
        try {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATIONS,
            )
        } catch (e: Exception) {
            Log.w(TAG, "请求通知权限失败：${e.message}")
        }
    }

    /** 按通知样式选择渠道 id。 */
    fun channelIdFor(style: String?): String {
        return if (style?.trim()?.lowercase() == STYLE_VENDOR) {
            CHANNEL_VENDOR
        } else {
            CHANNEL_SYSTEM
        }
    }

    /**
     * 创建通知渠道（幂等）。
     *
     * 两个渠道都是 IMPORTANCE_HIGH（会弹出横幅/提示音）。
     * 注意：**渠道创建后重要性由用户/系统控制，代码无法再改高**；
     * 用户如果手动把它降成「静默」，提醒就只会静静躺在通知栏里。
     */
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return

        if (manager.getNotificationChannel(CHANNEL_SYSTEM) == null) {
            val channel = NotificationChannel(
                CHANNEL_SYSTEM,
                "上课提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "上课前的课程提醒（系统通知样式）"
                applyHighPriorityStyle()
            }
            manager.createNotificationChannel(channel)
        }

        if (manager.getNotificationChannel(CHANNEL_VENDOR) == null) {
            val channel = NotificationChannel(
                CHANNEL_VENDOR,
                "课序活动提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "上课提醒的独立高优先级渠道，尽量争取横幅/活动卡片展示"
                applyHighPriorityStyle()
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun NotificationChannel.applyHighPriorityStyle() {
        enableVibration(true)
        vibrationPattern = longArrayOf(0, 250, 200, 250)
        enableLights(true)
        lightColor = NOTIFICATION_COLOR
        setShowBadge(true)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        setSound(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build(),
        )
    }

    /** 打开系统的「本应用通知设置」页；失败时返回 false。 */
    fun openNotificationSettings(context: Context): Boolean {
        val candidates = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            candidates.add(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            )
        }
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            )
        )
        candidates.add(Intent(Settings.ACTION_SETTINGS))

        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "打开通知设置失败：${e.message}")
            }
        }
        return false
    }

    // ------------------------------------------------------------ 内部实现

    private fun handleSyncSchedule(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val rawSessions = call.argument<List<Any?>>("sessions").orEmpty()
            val sessions = rawSessions.mapNotNull { item ->
                val map = item as? Map<*, *> ?: return@mapNotNull null
                val date = (map["date"] as? String)?.trim().orEmpty()
                val start = (map["start"] as? String)?.trim().orEmpty()
                val name = (map["name"] as? String)?.trim().orEmpty()
                if (date.isEmpty() || start.isEmpty() || name.isEmpty()) {
                    null
                } else {
                    ClassReminderScheduler.Session(
                        date = date,
                        start = start,
                        end = (map["end"] as? String)?.trim().orEmpty(),
                        name = name,
                        location = (map["location"] as? String)?.trim().orEmpty(),
                    )
                }
            }
            val minutes = call.argument<Int>("reminderMinutes") ?: 10
            val style = call.argument<String>("style") ?: STYLE_SYSTEM

            ClassReminderScheduler.schedule(
                activity.applicationContext,
                sessions,
                minutes,
                style,
            )
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "同步上课提醒失败", e)
            result.error("SYNC_FAILED", e.message ?: "同步上课提醒失败", null)
        }
    }
}
