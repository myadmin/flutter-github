import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 原生安装通道调用结果状态
enum AppInstallStatus {
  /// 已成功拉起系统包安装器界面
  launched,

  /// 尚未授予“安装未知来源应用”权限，已引导跳转至系统授权页
  needsPermission,

  /// 非 Android 平台不支持直接安装 APK
  unsupported,
}

/// 当前 Android 设备的安装包安装环境信息
class AndroidInstallEnvironment {
  const AndroidInstallEnvironment({
    required this.cacheDir,
    required this.supportedAbis,
    required this.canRequestPackageInstalls,
  });

  final String cacheDir;
  final List<String> supportedAbis;
  final bool canRequestPackageInstalls;
}

/// 封装与 Android `MainActivity` 通信的轻量级安装器桥接（零三方插件依赖）
class AppInstaller {
  const AppInstaller._();

  /// 原生通道名称，与 Android `MainActivity.kt` 中声明保持一致
  static const MethodChannel channel = MethodChannel(
    'com.example.gh_explorer/app_installer',
  );

  /// 查询当前平台的更新缓存目录与设备支持的 CPU ABI 列表
  static Future<AndroidInstallEnvironment?> getEnvironment() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    final raw = await channel.invokeMapMethod<String, dynamic>(
      'getPlatformInstallInfo',
    );
    if (raw == null) return null;
    final abis = (raw['supportedAbis'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    return AndroidInstallEnvironment(
      cacheDir: raw['cacheDir']?.toString() ?? '',
      supportedAbis: abis,
      canRequestPackageInstalls: raw['canRequestPackageInstalls'] == true,
    );
  }

  /// 调用 Android FileProvider 与系统包安装器安装本地 `.apk` 文件
  static Future<AppInstallStatus> installApk(String filePath) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AppInstallStatus.unsupported;
    }
    final result = await channel.invokeMethod<String>('installApk', {
      'filePath': filePath,
    });
    switch (result) {
      case 'needs_permission':
        return AppInstallStatus.needsPermission;
      case 'launched':
        return AppInstallStatus.launched;
      default:
        return AppInstallStatus.unsupported;
    }
  }
}
