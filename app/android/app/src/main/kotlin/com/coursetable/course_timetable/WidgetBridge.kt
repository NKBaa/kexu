package com.coursetable.course_timetable

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Flutter ↔ 原生桌面小组件的桥。
 *
 * 由 MainActivity 在 `configureFlutterEngine` 里加一行调用即可：
 *
 * ```kotlin
 * WidgetBridge.register(flutterEngine)
 * ```
 *
 * 通道名：`com.coursetable.course_timetable/widget`，方法：
 * - `updateWidget(Map snapshot)`：把快照转成 JSON 写入 SharedPreferences
 *   （`timetable_widget` / `snapshot`），随后刷新所有小组件实例，返回 true；
 * - `isSupported()`：当前平台是否支持小组件（Android 恒为 true）。
 *
 * 为什么用 [FlutterPlugin] 而不是在 register 里直接建通道：MethodChannel 的
 * 回调需要 `Context` 来读写 SharedPreferences / 刷新 AppWidget，而
 * [FlutterEngine] 本身不暴露 applicationContext；通过
 * `FlutterPluginBinding.applicationContext` 拿到 Context 是最稳妥的方式，
 * 同时引擎销毁时会自动解绑，避免通道回调泄漏。
 */
object WidgetBridge {

    /** 与 Flutter 侧 `timetableWidgetChannelName` 必须完全一致。 */
    const val CHANNEL = "com.coursetable.course_timetable/widget"

    /**
     * 注册小组件通道。可重复调用（同一引擎只注册一次）。
     *
     * 由 MainActivity 调用；未接线时 Flutter 侧调用会得到
     * MissingPluginException，服务层会静默降级为 false。
     */
    fun register(engine: FlutterEngine) {
        if (engine.plugins.has(WidgetPlugin::class.java)) return
        engine.plugins.add(WidgetPlugin())
    }

    /** 真正的通道实现；生命周期由 Flutter 引擎的 PluginRegistry 管理。 */
    private class WidgetPlugin : FlutterPlugin {

        private var channel: MethodChannel? = null

        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            val context = binding.applicationContext
            val methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL)
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        val arguments = call.arguments
                        if (arguments !is Map<*, *>) {
                            result.error(
                                "INVALID_ARGUMENTS",
                                "updateWidget 需要一个 Map 快照",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            // Flutter 的 StandardMessageCodec 解出来是
                            // HashMap/ArrayList，JSONObject 的 wrap 逻辑会
                            // 递归处理嵌套的 Map/List。
                            val json = JSONObject(arguments).toString()
                            TimetableWidgetProvider.saveSnapshot(context, json)
                            TimetableWidgetProvider.updateAllWidgets(context)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "WIDGET_UPDATE_FAILED",
                                "写入小组件快照失败：${e.message ?: e.javaClass.simpleName}",
                                null,
                            )
                        }
                    }

                    "isSupported" -> result.success(true)

                    else -> result.notImplemented()
                }
            }
            channel = methodChannel
        }

        override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            channel?.setMethodCallHandler(null)
            channel = null
        }
    }
}
