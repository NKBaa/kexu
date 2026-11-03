package com.coursetable.course_timetable

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * 上课提醒的广播接收器：闹钟到点时由 AlarmManager 触发，在这里发通知。
 *
 * 通知要点：
 * - channel 由 [NotificationBridge.channelIdFor] 按 style 选择，
 *   `vendor` 走独立的「课序活动提醒」高优先级渠道；
 * - `BigTextStyle` 保证长文本（课程名 + 时间 + 地点）能完整展开；
 * - `category = event` 告诉系统这是日程类通知，部分 ROM 会据此决定
 *   是否允许横幅/卡片展示；
 * - 点击通知直接打开 App（MainActivity 是 singleTop，不会重复压栈）。
 *
 * 注意：能否显示为横幅/厂商活动卡片最终由系统通知策略决定，
 * 这里只负责把通知以最高优先级、正确的类别发出去。
 */
class NotificationReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ClassReminderReceiver"

        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_STYLE = "style"
        const val EXTRA_NOTIFICATION_ID = "notification_id"

        /** 通知小图标：使用单色矢量图标，避免 launcher 彩色图标在状态栏显示成白块。 */
        private fun smallIconRes(context: Context): Int {
            return R.drawable.ic_stat_class
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        NotificationBridge.ensureChannels(appContext)

        val title = intent.getStringExtra(EXTRA_TITLE)
            ?.takeIf { it.isNotBlank() }
            ?: "上课提醒"
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val style = intent.getStringExtra(EXTRA_STYLE) ?: NotificationBridge.STYLE_SYSTEM
        val rawId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        val notificationId = if (rawId != 0) {
            rawId
        } else {
            (System.currentTimeMillis() % 100_000L).toInt()
        }

        val builder = NotificationCompat.Builder(
            appContext,
            NotificationBridge.channelIdFor(style),
        )
            .setSmallIcon(smallIconRes(appContext))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setColor(NotificationBridge.NOTIFICATION_COLOR)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

        val launchIntent = appContext.packageManager
            .getLaunchIntentForPackage(appContext.packageName)
        if (launchIntent != null) {
            launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            builder.setContentIntent(
                PendingIntent.getActivity(appContext, notificationId, launchIntent, flags)
            )
        }

        try {
            NotificationManagerCompat.from(appContext)
                .notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            // 用户关掉了通知权限时，系统会拒绝发通知；这里静默失败即可。
            Log.w(TAG, "通知权限不足，提醒未展示：${e.message}")
        }
    }
}

/**
 * 开机 / 时区变化 / App 更新后的恢复接收器。
 *
 * AlarmManager 的闹钟在设备重启后全部丢失，所以开机后必须按
 * [ClassReminderScheduler] 持久化的排程数据重新排一遍。
 *
 * 需要在 AndroidManifest.xml 里注册（见 `app/android/ANDROID_NOTIFICATIONS_SETUP.md`），
 * 并声明 `RECEIVE_BOOT_COMPLETED` 权限。
 */
class ClassReminderBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ClassReminderBoot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val interested = action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == Intent.ACTION_TIMEZONE_CHANGED ||
            action == Intent.ACTION_TIME_CHANGED
        if (!interested) return

        Log.i(TAG, "收到 $action，尝试恢复上课提醒排程")
        try {
            ClassReminderScheduler.rescheduleFromPrefs(context.applicationContext)
        } catch (e: Exception) {
            Log.w(TAG, "恢复上课提醒排程失败：${e.message}")
        }
    }
}
