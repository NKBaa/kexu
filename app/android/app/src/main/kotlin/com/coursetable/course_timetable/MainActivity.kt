package com.coursetable.course_timetable

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android 侧宿主 Activity。
 *
 * 除默认的 Flutter 启动流程外，额外注册一条平台通道
 * `com.coursetable.course_timetable/update`，供「在线更新」调用：
 * `installApk(path)` 用 FileProvider 把缓存目录里的 APK 包成 content:// URI，
 * 再交给系统安装器（ACTION_VIEW + application/vnd.android.package-archive）。
 *
 * 注意：Android 8.0+ 不允许直接 file:// 分享，必须走 FileProvider；
 * 对应的 `file_paths.xml` 映射了 cacheDir/updates，与 Flutter 侧
 * `getTemporaryDirectory()/updates` 保持一致。
 */
class MainActivity : FlutterActivity() {
    private val updateChannelName = "com.coursetable.course_timetable/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }

        // 桌面小组件：注册 updateWidget / isSupported 通道。
        WidgetBridge.register(flutterEngine)

        // 上课提醒：注册通知权限、渠道与排程通道。
        NotificationBridge.attach(this, flutterEngine)
    }

    /** 拉起系统安装界面；失败时通过 result.error 返回可读原因。 */
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENTS", "缺少安装包路径", null)
            return
        }
        try {
            val apkFile = File(path)
            if (!apkFile.exists()) {
                result.error("FILE_NOT_FOUND", "安装包不存在：$path", null)
                return
            }
            val authority = "$packageName.fileprovider"
            val uri = FileProvider.getUriForFile(this, authority, apkFile)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            // 例如用户关闭了「允许安装未知来源应用」、没有安装器 Activity 等
            result.error(
                "INSTALL_FAILED",
                "无法启动安装界面：${e.message ?: e.javaClass.simpleName}",
                null
            )
        }
    }
}
