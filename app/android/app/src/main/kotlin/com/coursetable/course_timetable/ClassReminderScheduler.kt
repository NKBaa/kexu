package com.coursetable.course_timetable

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * 上课提醒排程器：把未来一段时间的课程提醒写进 [AlarmManager]。
 *
 * 为什么用 AlarmManager 而不是前台服务/WorkManager：
 * 上课提醒要求「到点就弹」，AlarmManager 是 Android 上唯一能精确唤醒的
 * 系统级机制，且不需要 App 常驻后台。WorkManager 的最小周期与延迟都不可控，
 * 不适合分钟级提醒。
 *
 * 兼容性策略：
 * - Android 12（S）起 `setExactAndAllowWhileIdle` 需要 SCHEDULE_EXACT_ALARM
 *   权限，未授予时系统会抛 SecurityException —— 这里**降级为不精确闹钟**
 *   （`setAndAllowWhileIdle`），可能晚几分钟，但提醒不会丢；
 * - Android 8（O）起通知必须挂在 channel 上，channel 由
 *   [NotificationBridge.ensureChannels] 统一创建；
 * - 每次同步都是「先取消全部旧闹钟，再按新列表重排」，因此可以安全地重复调用。
 *
 * 排程结果会持久化到 SharedPreferences，供 [ClassReminderBootReceiver]
 * 在开机/时区变化后恢复（AlarmManager 的闹钟在重启后会丢失）。
 */
object ClassReminderScheduler {
    private const val TAG = "ClassReminder"

    /** 持久化文件（保存待排程列表，供开机恢复）。 */
    const val PREFS_NAME = "class_reminder_prefs"

    private const val KEY_REQUEST_CODES = "request_codes"
    private const val KEY_SESSIONS = "sessions"
    private const val KEY_REMINDER_MINUTES = "reminder_minutes"
    private const val KEY_STYLE = "notification_style"

    private const val ALARM_ACTION = "com.coursetable.course_timetable.CLASS_REMINDER_ALARM"
    private const val REQUEST_CODE_BASE = 42000
    private const val MAX_ALARMS = 500

    /**
     * 一条待提醒的课程。
     *
     * [date] 形如 `2026-10-08`，[start]/[end] 形如 `08:00`，
     * 都由 Dart 侧按当天作息方案算好，原生侧只负责换算成时间戳。
     */
    data class Session(
        val date: String,
        val start: String,
        val end: String,
        val name: String,
        val location: String,
    )

    /** 取消旧闹钟并重新排程 [sessions]；[style] 决定通知走哪个 channel。 */
    fun schedule(
        context: Context,
        sessions: List<Session>,
        reminderMinutes: Int,
        style: String,
    ) {
        val appContext = context.applicationContext
        cancelAll(appContext)

        val alarmManager =
            appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager == null) {
            Log.w(TAG, "AlarmManager 不可用，跳过排程")
            return
        }

        val minutes = if (reminderMinutes > 0) reminderMinutes else 10
        val useExact = canScheduleExactAlarms(alarmManager)
        val now = System.currentTimeMillis()
        val scheduledCodes = mutableListOf<Int>()

        sessions.take(MAX_ALARMS).forEachIndexed { index, session ->
            val triggerAt = triggerAtMillis(session, minutes) ?: return@forEachIndexed
            if (triggerAt <= now) return@forEachIndexed

            val requestCode = REQUEST_CODE_BASE + index
            val pending = buildPendingIntent(appContext, requestCode, session, style)
            if (scheduleAlarm(alarmManager, triggerAt, pending, useExact)) {
                scheduledCodes.add(requestCode)
            } else {
                pending.cancel()
            }
        }

        persist(appContext, sessions, minutes, style, scheduledCodes)
        Log.i(TAG, "已排程 ${scheduledCodes.size} 条上课提醒（精确闹钟=$useExact）")
    }

    /** 取消全部已排程的上课提醒，并清空持久化的排程信息。 */
    fun cancelAll(context: Context) {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val codes = prefs.getStringSet(KEY_REQUEST_CODES, emptySet()).orEmpty()
        val alarmManager =
            appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

        if (alarmManager != null) {
            for (rawCode in codes) {
                val code = rawCode.toIntOrNull() ?: continue
                val pending = PendingIntent.getBroadcast(
                    appContext,
                    code,
                    baseIntent(appContext),
                    pendingFlags(noCreate = true),
                )
                if (pending != null) {
                    alarmManager.cancel(pending)
                    pending.cancel()
                }
            }
        }
        prefs.edit().clear().apply()
    }

    /**
     * 从持久化数据恢复排程（开机、时区变化、App 更新后调用）。
     *
     * AlarmManager 的闹钟在设备重启后会全部丢失，所以必须恢复一次。
     */
    fun rescheduleFromPrefs(context: Context) {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_SESSIONS, null) ?: return
        val sessions = parseSessions(raw)
        if (sessions.isEmpty()) return
        val minutes = prefs.getInt(KEY_REMINDER_MINUTES, 10)
        val style = prefs.getString(KEY_STYLE, NotificationBridge.STYLE_SYSTEM)
            ?: NotificationBridge.STYLE_SYSTEM
        schedule(appContext, sessions, minutes, style)
    }

    /** 当前是否允许使用精确闹钟（Android 12+ 需要用户/系统授予）。 */
    fun canScheduleExactAlarms(alarmManager: AlarmManager): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return try {
            alarmManager.canScheduleExactAlarms()
        } catch (e: Exception) {
            Log.w(TAG, "读取精确闹钟权限失败：${e.message}")
            false
        }
    }

    // ------------------------------------------------------------ 内部实现

    private fun baseIntent(context: Context): Intent =
        Intent(context, NotificationReceiver::class.java).setAction(ALARM_ACTION)

    private fun buildPendingIntent(
        context: Context,
        requestCode: Int,
        session: Session,
        style: String,
    ): PendingIntent {
        val body = buildBody(session)
        val intent = baseIntent(context).apply {
            putExtra(NotificationReceiver.EXTRA_TITLE, "上课提醒：${session.name}")
            putExtra(NotificationReceiver.EXTRA_BODY, body)
            putExtra(NotificationReceiver.EXTRA_STYLE, style)
            putExtra(NotificationReceiver.EXTRA_NOTIFICATION_ID, requestCode)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            pendingFlags(noCreate = false),
        )
    }

    private fun buildBody(session: Session): String {
        val time = if (session.end.isBlank()) {
            session.start
        } else {
            "${session.start}-${session.end}"
        }
        return if (session.location.isBlank()) {
            "$time 上课，别迟到"
        } else {
            "$time · ${session.location}，别迟到"
        }
    }

    private fun pendingFlags(noCreate: Boolean): Int {
        var flags = if (noCreate) PendingIntent.FLAG_NO_CREATE else PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun scheduleAlarm(
        alarmManager: AlarmManager,
        triggerAt: Long,
        pending: PendingIntent,
        useExact: Boolean,
    ): Boolean {
        return try {
            if (useExact) {
                setExact(alarmManager, triggerAt, pending)
            } else {
                setInexact(alarmManager, triggerAt, pending)
            }
            true
        } catch (e: SecurityException) {
            // Android 12+ 没有精确闹钟权限：降级为不精确闹钟，提醒可能晚几分钟。
            Log.w(TAG, "精确闹钟被系统拒绝，降级为不精确闹钟：${e.message}")
            try {
                setInexact(alarmManager, triggerAt, pending)
                true
            } catch (e2: Exception) {
                Log.w(TAG, "排程提醒失败：${e2.message}")
                false
            }
        } catch (e: Exception) {
            Log.w(TAG, "排程提醒失败：${e.message}")
            false
        }
    }

    private fun setExact(alarmManager: AlarmManager, triggerAt: Long, pending: PendingIntent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                pending,
            )
        } else {
            @Suppress("DEPRECATION")
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    private fun setInexact(alarmManager: AlarmManager, triggerAt: Long, pending: PendingIntent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                pending,
            )
        } else {
            @Suppress("DEPRECATION")
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }
    }

    private fun triggerAtMillis(session: Session, reminderMinutes: Int): Long? {
        return try {
            val format = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
            format.isLenient = false
            val parsed = format.parse("${session.date} ${session.start}") ?: return null
            parsed.time - reminderMinutes * 60_000L
        } catch (e: Exception) {
            Log.w(TAG, "解析上课时间失败：${session.date} ${session.start}（${e.message}）")
            null
        }
    }

    private fun persist(
        context: Context,
        sessions: List<Session>,
        reminderMinutes: Int,
        style: String,
        requestCodes: List<Int>,
    ) {
        val array = JSONArray()
        for (session in sessions) {
            array.put(
                JSONObject()
                    .put("date", session.date)
                    .put("start", session.start)
                    .put("end", session.end)
                    .put("name", session.name)
                    .put("location", session.location)
            )
        }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SESSIONS, array.toString())
            .putInt(KEY_REMINDER_MINUTES, reminderMinutes)
            .putString(KEY_STYLE, style)
            .putStringSet(KEY_REQUEST_CODES, requestCodes.map { it.toString() }.toSet())
            .apply()
    }

    private fun parseSessions(raw: String): List<Session> {
        return try {
            val array = JSONArray(raw)
            val out = mutableListOf<Session>()
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                val date = obj.optString("date")
                val start = obj.optString("start")
                val name = obj.optString("name")
                if (date.isBlank() || start.isBlank() || name.isBlank()) continue
                out.add(
                    Session(
                        date = date,
                        start = start,
                        end = obj.optString("end"),
                        name = name,
                        location = obj.optString("location"),
                    )
                )
            }
            out
        } catch (e: Exception) {
            Log.w(TAG, "读取已排程提醒失败：${e.message}")
            emptyList()
        }
    }
}
