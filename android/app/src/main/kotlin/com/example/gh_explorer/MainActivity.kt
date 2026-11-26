package com.example.gh_explorer

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android 主 Activity：通过原生 MethodChannel 暴露更新包缓存目录、设备 ABI 与 APK 安装能力，
 * 避免引入重型第三方安装插件导致 Gradle / FileProvider 冲突。
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.example.gh_explorer/app_installer"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPlatformInstallInfo" -> {
                        val updateDir = File(cacheDir, "updates").apply { mkdirs() }
                        val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(
                            mapOf(
                                "cacheDir" to updateDir.absolutePath,
                                "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                                "canRequestPackageInstalls" to canInstall,
                            )
                        )
                    }

                    "installApk" -> {
                        val filePath = call.argument<String>("filePath").orEmpty()
                        handleInstallApk(filePath, result)
                    }

                    "openInstallPermissionSettings" -> {
                        openUnknownSourcesSettings()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun handleInstallApk(filePath: String, result: MethodChannel.Result) {
        if (filePath.isBlank()) {
            result.error("INVALID_PATH", "APK 文件路径为空", null)
            return
        }
        val apkFile = File(filePath)
        if (!apkFile.exists() || apkFile.length() <= 0L) {
            result.error("FILE_NOT_FOUND", "更新安装包不存在或已损坏", null)
            return
        }

        // Android 8.0+ 安装未知来源应用需要先获得系统授权；未授权时主动引导至本应用权限页
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            openUnknownSourcesSettings()
            result.success("needs_permission")
            return
        }

        try {
            val contentUri = FileProvider.getUriForFile(
                this,
                "$packageName.gh_explorer.fileprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(installIntent)
            result.success("launched")
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message ?: "无法调起系统安装器", null)
        }
    }

    private fun openUnknownSourcesSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(settingsIntent)
        }
    }
}
