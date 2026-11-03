package com.coursetable.course_timetable

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 「今日课表」桌面小组件的原生实现。
 *
 * 数据流：
 *
 * ```
 * Flutter (TimetableWidgetService.updateWidget)
 *   -> MethodChannel 'com.coursetable.course_timetable/widget'
 *   -> WidgetBridge (写入 SharedPreferences + 调用 updateAllWidgets)
 *   -> TimetableWidgetProvider.render() 读快照渲染 RemoteViews
 * ```
 *
 * 为什么要把快照落盘：桌面启动器随时可能请求 `onUpdate`（开机、系统重启、
 * 用户重新添加小组件、30 分钟周期刷新），而此时 Flutter 引擎多半没有运行。
 * 只要上次同步过快照，小组件就能独立渲染，不依赖 App 进程存活。
 *
 * 渲染规则（与 Flutter 侧 `buildWidgetSnapshot` 的字段一一对应）：
 * - `date` 不是今天 -> 显示「打开课序查看今日课程」，不展示过期课程；
 * - `week` <= 0 -> 不显示「第 N 周」（未开学 / 学期已结束）；
 * - `holiday` 非空 -> 顶部显示节假日名称；
 * - `sessions` 最多显示 4 条（时间 + 课程名 + 地点/教师），
 *   「正在上课」那条高亮，超出的用「还有 N 门课」提示；
 * - 没有课也没有节假日 -> 「今天没有课」；
 * - 点击任意位置 -> 打开课序。
 */
class TimetableWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) {
            render(context, appWidgetManager, widgetId)
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        updateAllWidgets(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // 自定义刷新动作：目前没有定时任务用它，保留给后续「立即刷新」入口
        // （例如桌面长按菜单或 MainActivity 回到前台时主动刷新）。
        if (intent.action == ACTION_REFRESH) {
            updateAllWidgets(context)
        }
    }

    /** 用户拉伸/缩小小组件时立即按新尺寸重排。 */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val TAG = "TimetableWidget"

        /** 主动刷新小组件的广播 action。 */
        const val ACTION_REFRESH = "com.coursetable.course_timetable.widget.ACTION_REFRESH"

        /** 快照落盘的 SharedPreferences 文件名（WidgetBridge 写、Provider 读）。 */
        const val PREFS_NAME = "timetable_widget"

        /** 快照 JSON 的 key。 */
        const val KEY_SNAPSHOT = "snapshot"

        /** 布局里固定 4 行课程。 */
        private const val MAX_SESSIONS = 4

        private val SESSION_ROWS = intArrayOf(
            R.id.session_row_1,
            R.id.session_row_2,
            R.id.session_row_3,
            R.id.session_row_4,
        )
        private val SESSION_TIMES = intArrayOf(
            R.id.session_time_1,
            R.id.session_time_2,
            R.id.session_time_3,
            R.id.session_time_4,
        )
        private val SESSION_NAMES = intArrayOf(
            R.id.session_name_1,
            R.id.session_name_2,
            R.id.session_name_3,
            R.id.session_name_4,
        )
        private val SESSION_METAS = intArrayOf(
            R.id.session_meta_1,
            R.id.session_meta_2,
            R.id.session_meta_3,
            R.id.session_meta_4,
        )
        private val SESSION_ACCENTS = intArrayOf(
            R.id.session_accent_1,
            R.id.session_accent_2,
            R.id.session_accent_3,
            R.id.session_accent_4,
        )
        private val SESSION_BADGES = intArrayOf(
            R.id.session_badge_1,
            R.id.session_badge_2,
            R.id.session_badge_3,
            R.id.session_badge_4,
        )

        private val COLOR_ACCENT = 0xFF1A73E8.toInt()
        private val COLOR_INACTIVE_ACCENT = 0xFFDADCE0.toInt()
        private val COLOR_PRIMARY = 0xFF1A1C1E.toInt()
        private val COLOR_SECONDARY = 0xFF5F6368.toInt()

        /** 把 Flutter 推来的快照 JSON 落盘；真正的刷新由 [updateAllWidgets] 做。 */
        fun saveSnapshot(context: Context, json: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_SNAPSHOT, json)
                .apply()
        }

        /** 刷新桌面上的所有「今日课表」小组件实例。 */
        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TimetableWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids == null || ids.isEmpty()) return
            for (widgetId in ids) {
                render(context, manager, widgetId)
            }
        }

        /** 渲染单个小组件实例。 */
        private fun render(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_timetable)
            val maxSessions = maxSessionsFor(appWidgetManager.getAppWidgetOptions(widgetId))
            val snapshot = loadSnapshot(context)
            if (snapshot == null) {
                // 还没同步过任何数据（用户刚添加小组件、还没打开 App）
                views.setTextViewText(R.id.widget_date_week, "")
                showMessage(views, "打开课序查看今日课程")
            } else {
                bindSnapshot(views, snapshot, maxSessions)
            }
            bindClick(context, views)
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        /** 根据小组件实际高度决定显示几门课，避免 4x3 小尺寸下 4 张卡片挤在一起。 */
        private fun maxSessionsFor(options: Bundle): Int {
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            return when {
                minHeight <= 0 -> MAX_SESSIONS
                minHeight >= 230 -> 4
                minHeight >= 180 -> 3
                else -> 2
            }
        }

        /** 读 SharedPreferences 里的快照；没有或损坏时返回 null。 */
        private fun loadSnapshot(context: Context): JSONObject? {
            val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_SNAPSHOT, null)
            if (raw.isNullOrBlank()) return null
            return try {
                JSONObject(raw)
            } catch (e: Exception) {
                // 快照损坏（例如写入过程被中断）：按「没有数据」处理，
                // 等下次 Flutter 侧推送覆盖即可。
                android.util.Log.w(TAG, "小组件快照解析失败：${e.message}")
                null
            }
        }

        private fun bindSnapshot(views: RemoteViews, snapshot: JSONObject, maxSessions: Int) {
            val date = snapshot.optString("date", "")
            val weekday = snapshot.optString("weekday", "")
            val week = snapshot.optInt("week", 0)

            // 顶部：日期 · 星期；课程数与周次放到副标题，避免右上角过长。
            val headerParts = mutableListOf<String>()
            if (date.isNotEmpty()) headerParts.add(date)
            if (weekday.isNotEmpty()) headerParts.add(weekday)
            views.setTextViewText(R.id.widget_date_week, headerParts.joinToString(" · "))

            // 快照不是今天的：不展示过期课程，提示用户打开 App 刷新。
            if (date != todayLabel()) {
                showMessage(views, "打开课序查看今日课程")
                return
            }
            views.setViewVisibility(R.id.widget_stale, View.GONE)
            views.setViewVisibility(R.id.widget_sessions, View.VISIBLE)

            val sessions = snapshot.optJSONArray("sessions")
            val total = sessions?.length() ?: 0

            // 节假日行
            val holiday = if (snapshot.isNull("holiday")) {
                ""
            } else {
                snapshot.optString("holiday", "")
            }
            val subtitle = buildString {
                if (holiday.isNotBlank()) {
                    append("今天放假")
                } else {
                    append(if (total == 0) "今天没有课" else "$total 门课")
                }
                if (week > 0) append(" · 第 $week 周")
            }
            views.setTextViewText(R.id.widget_subtitle, subtitle)
            if (holiday.isNotBlank()) {
                views.setTextViewText(R.id.widget_holiday, "今天放假 · $holiday")
                views.setViewVisibility(R.id.widget_holiday, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_holiday, View.GONE)
            }

            // 课程行：节假日时不展示课程，改显示空状态。
            val shown = if (holiday.isBlank()) minOf(total, maxSessions) else 0
            val nowMinutes = currentMinutes()
            var nextIndex = -1
            if (holiday.isBlank()) {
                for (index in 0 until shown) {
                    val start = sessions?.optJSONObject(index)?.optString("start", "") ?: ""
                    val startMinutes = parseMinutes(start) ?: continue
                    if (startMinutes > nowMinutes) {
                        nextIndex = index
                        break
                    }
                }
            }

            for (index in 0 until MAX_SESSIONS) {
                val rowId = SESSION_ROWS[index]
                val badgeId = SESSION_BADGES[index]
                if (index >= shown) {
                    views.setViewVisibility(rowId, View.GONE)
                    views.setViewVisibility(badgeId, View.GONE)
                    continue
                }
                val item = sessions?.optJSONObject(index) ?: continue
                views.setViewVisibility(rowId, View.VISIBLE)
                views.setViewVisibility(SESSION_ACCENTS[index], View.VISIBLE)

                val start = item.optString("start", "")
                val end = item.optString("end", "")
                val name = item.optString("name", "")
                val location = if (item.isNull("location")) "" else item.optString("location", "")
                val teacher = if (item.isNull("teacher")) "" else item.optString("teacher", "")

                views.setTextViewText(
                    SESSION_TIMES[index],
                    if (start.isNotEmpty() && end.isNotEmpty()) "$start-$end" else "",
                )
                views.setTextViewText(SESSION_NAMES[index], name)
                views.setTextViewText(
                    SESSION_METAS[index],
                    listOf(location, teacher).filter { it.isNotBlank() }.joinToString(" · "),
                )

                // 「正在上课」优先用当前时钟重新判断（快照可能是上次同步时生成的），
                // 时间解析失败时再退回快照里的 isNow。
                val ongoing = isOngoing(start, end, nowMinutes)
                    ?: item.optBoolean("isNow", false)
                val isNext = !ongoing && index == nextIndex
                views.setInt(
                    rowId,
                    "setBackgroundResource",
                    if (ongoing) R.drawable.widget_session_active else R.drawable.widget_session_bg,
                )
                views.setInt(
                    SESSION_ACCENTS[index],
                    "setBackgroundColor",
                    if (ongoing || isNext) COLOR_ACCENT else COLOR_INACTIVE_ACCENT,
                )
                views.setTextColor(
                    SESSION_TIMES[index],
                    if (ongoing) COLOR_ACCENT else COLOR_SECONDARY,
                )
                views.setTextColor(
                    SESSION_NAMES[index],
                    if (ongoing) COLOR_ACCENT else COLOR_PRIMARY,
                )
                if (ongoing || isNext) {
                    views.setTextViewText(badgeId, if (ongoing) "进行中" else "下一节")
                    views.setViewVisibility(badgeId, View.VISIBLE)
                } else {
                    views.setViewVisibility(badgeId, View.GONE)
                }
            }

            // 空状态：没有课，或今天是节假日。
            val showEmpty = shown == 0
            if (showEmpty) {
                views.setTextViewText(
                    R.id.widget_empty,
                    if (holiday.isNotBlank()) "好好休息" else "今天没有课",
                )
            }
            views.setViewVisibility(
                R.id.widget_empty,
                if (showEmpty) View.VISIBLE else View.GONE,
            )

            // 超过当前高度可显示的课程数时提示还剩几门
            if (holiday.isBlank() && total > maxSessions) {
                views.setTextViewText(R.id.widget_more, "还有 ${total - maxSessions} 门课")
                views.setViewVisibility(R.id.widget_more, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_more, View.GONE)
            }

            // 底部：快照更新时间
            val updatedLabel = formatUpdatedAt(snapshot.optString("updatedAt", ""))
            if (updatedLabel.isNotEmpty()) {
                views.setTextViewText(R.id.widget_footer, "更新于 $updatedLabel")
                views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_footer, View.GONE)
            }
        }

        /** 展示一条提示文案，并把课程/节假日/空状态等区域全部隐藏。 */
        private fun showMessage(views: RemoteViews, message: String) {
            views.setTextViewText(R.id.widget_subtitle, "")
            views.setTextViewText(R.id.widget_stale, message)
            views.setViewVisibility(R.id.widget_stale, View.VISIBLE)
            views.setViewVisibility(R.id.widget_sessions, View.GONE)
            views.setViewVisibility(R.id.widget_holiday, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            views.setViewVisibility(R.id.widget_more, View.GONE)
            views.setViewVisibility(R.id.widget_footer, View.GONE)
            for (rowId in SESSION_ROWS) {
                views.setViewVisibility(rowId, View.GONE)
            }
        }

        /** 整个小组件可点击：打开课序主界面。 */
        private fun bindClick(context: Context, views: RemoteViews) {
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: return
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            // minSdk 24 > M(23)，FLAG_IMMUTABLE 恒定可用；必须显式声明可变性，
            // 否则 Android 12+ 会直接抛 IllegalArgumentException。
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pendingIntent = PendingIntent.getActivity(context, 0, launch, flags)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        }

        private fun todayLabel(): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(Date())

        private fun currentMinutes(): Int {
            val calendar = Calendar.getInstance()
            return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        }

        /**
         * [nowMinutes] 是否落在 `[start, end)` 内。
         *
         * 时间缺失/格式非法时返回 null，交给调用方退回快照里的 isNow。
         */
        private fun isOngoing(start: String, end: String, nowMinutes: Int): Boolean? {
            val startMinutes = parseMinutes(start) ?: return null
            val endMinutes = parseMinutes(end) ?: return null
            if (endMinutes <= startMinutes) return null
            return nowMinutes in startMinutes until endMinutes
        }

        /** 解析 `HH:mm` 为当天分钟数；格式不对返回 null。 */
        private fun parseMinutes(hhmm: String): Int? {
            val parts = hhmm.split(":")
            if (parts.size < 2) return null
            val hour = parts[0].toIntOrNull() ?: return null
            val minute = parts[1].toIntOrNull() ?: return null
            if (hour !in 0..23 || minute !in 0..59) return null
            return hour * 60 + minute
        }

        /** ISO 8601（`2025-11-03T12:30:00.000`）→ `12:30`；解析失败返回空串。 */
        private fun formatUpdatedAt(raw: String): String {
            if (raw.length >= 16 && raw[10] == 'T') {
                return raw.substring(11, 16)
            }
            return try {
                val parsed = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.CHINA)
                    .parse(raw) ?: return ""
                SimpleDateFormat("HH:mm", Locale.CHINA).format(parsed)
            } catch (e: Exception) {
                ""
            }
        }
    }
}
