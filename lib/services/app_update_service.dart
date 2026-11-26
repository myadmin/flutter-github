import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gh_explorer/api/release.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/app_release.dart';
import 'package:gh_explorer/services/apk_downloader.dart';
import 'package:gh_explorer/services/app_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// 进度回调签名（`received` 已接收字节数，`total` 总字节数，未知时为 `-1`）
typedef ApkDownloadProgressCallback = void Function(int received, int total);

/// 应用版本更新服务：检查 GitHub Releases 最新版本、下载对应架构 APK 并拉起系统安装器
class AppUpdateService {
  AppUpdateService({
    Future<String> Function()? currentVersionLoader,
    Future<AppRelease?> Function()? releaseFetcher,
    Future<AndroidInstallEnvironment?> Function()? environmentLoader,
    Future<String> Function({
      required String url,
      required String directoryPath,
      required String fileName,
      String expectedSha256,
      int expectedSize,
      ApkDownloadProgressCallback? onProgress,
      CancelToken? cancelToken,
    })?
    apkDownloader,
    Future<AppInstallStatus> Function(String filePath)? apkInstaller,
    Future<bool> Function(Uri url)? urlLauncher,
    this.cacheTtl = const Duration(hours: GlobalConstants.updateCheckHours),
    bool? autoCheckEnabled,
  }) : _loadCurrentVersion = currentVersionLoader ?? _readCurrentVersionTag,
       _fetchRelease = releaseFetcher ?? fetchLatestReleaseAPI,
       _loadEnvironment = environmentLoader ?? AppInstaller.getEnvironment,
       _downloadApk = apkDownloader ?? downloadApkToFile,
       _installApk = apkInstaller ?? AppInstaller.installApk,
       _launchUrl = urlLauncher ?? _launchExternal,
       autoCheckEnabled = autoCheckEnabled ?? (!kDebugMode && !kIsWeb);

  /// 全局默认单例，测试时可替换为注入了 Mock 的实例
  static AppUpdateService instance = AppUpdateService();

  /// 是否允许在冷启动时静默自动检测更新（Debug 构建默认关闭）
  final bool autoCheckEnabled;

  /// 两次静默检测之间的最小冷却间隔
  final Duration cacheTtl;

  final Future<String> Function() _loadCurrentVersion;
  final Future<AppRelease?> Function() _fetchRelease;
  final Future<AndroidInstallEnvironment?> Function() _loadEnvironment;
  final Future<String> Function({
    required String url,
    required String directoryPath,
    required String fileName,
    String expectedSha256,
    int expectedSize,
    ApkDownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  })
  _downloadApk;
  final Future<AppInstallStatus> Function(String filePath) _installApk;
  final Future<bool> Function(Uri url) _launchUrl;

  /// 检查是否有更新版本；无新版本、冷却期命中或已跳过返回 null
  ///
  /// - [force] 为 `false`（冷启动静默检测）时：遇异常静默返回 null，且受 6 小时冷却和跳过版本约束；
  /// - [force] 为 `true`（用户手动点击「检查更新」）时：忽略冷却与跳过状态，若网络异常则抛出交由界面提示。
  Future<AppRelease?> check({bool force = false}) async {
    if (!force && !autoCheckEnabled) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!force && _checkedRecently(prefs)) {
      return null;
    }

    // 无论请求是否成功均先记录检查时间，防止网络不可达时每次启动反复打满配额
    await prefs.setString(
      GlobalConstants.updateLastCheckKey,
      DateTime.now().toIso8601String(),
    );

    AppRelease? release;
    try {
      release = await _fetchRelease();
    } catch (e) {
      debugPrint('检查 GitHub Release 更新失败: $e');
      if (force) rethrow;
      return null;
    }
    if (release == null || release.tagName.isEmpty) {
      return null;
    }

    if (!force &&
        prefs.getString(GlobalConstants.updateSkipTagKey) == release.tagName) {
      return null;
    }

    final current = await _loadCurrentVersion();
    if (current.isEmpty) {
      return null;
    }
    final remoteCompareTarget = release.tagName;
    return compareReleaseVersions(remoteCompareTarget, current) > 0
        ? release
        : null;
  }

  /// 读取当前应用展示用版本号（去掉 `v` 前缀，带构建号时展示 `+build`）
  Future<String> currentVersion() => _loadCurrentVersion();

  /// 将本次最新 Release Tag 记录为跳过，之后静默检查不再打扰
  Future<void> skip(AppRelease release) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(GlobalConstants.updateSkipTagKey, release.tagName);
  }

  /// 当前设备是否支持应用内下载并直接安装 APK（仅 Android 原生端）
  bool get supportsInAppApkInstall =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 在 Android 端挑选最匹配的 APK 产物，并下载到应用专属缓存目录
  Future<String> downloadApk(
    AppRelease release, {
    ApkDownloadProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) async {
    final env = await _loadEnvironment();
    if (env == null || env.cacheDir.isEmpty) {
      throw UnsupportedError('当前环境不支持应用内下载安装包');
    }
    final asset = release.pickAndroidApkAsset(
      supportedAbis: env.supportedAbis.isEmpty
          ? const ['arm64-v8a', 'armeabi-v7a', 'x86_64']
          : env.supportedAbis,
    );
    if (asset == null || asset.downloadUrl.isEmpty) {
      throw StateError('该版本未附带可用的 Android APK 安装包');
    }
    final targetName = 'gh_explorer_${release.tagName}_${asset.name}';
    return _downloadApk(
      url: asset.downloadUrl,
      directoryPath: env.cacheDir,
      fileName: targetName,
      expectedSha256: asset.sha256Digest,
      expectedSize: asset.size,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// 调起 Android 系统包安装器安装已下载好的本地 APK
  Future<AppInstallStatus> installApk(String filePath) {
    return _installApk(filePath);
  }

  /// 在浏览器中打开对应 APK 直链或 Release 详情页（非 Android 端与兜底用）
  Future<bool> openDownloadPage(AppRelease release) async {
    final fallbackAsset = release.pickAndroidApkAsset();
    final target = supportsInAppApkInstall
        ? (fallbackAsset?.downloadUrl ?? release.htmlUrl)
        : (release.htmlUrl.isNotEmpty
              ? release.htmlUrl
              : GlobalConstants.releasesPageUrl);
    if (target.isEmpty) return false;
    final uri = Uri.tryParse(target);
    // 仅允许跳转 HTTPS 的 GitHub 域名，避免恶意 Release 正文注入任意链接
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'github.com' ||
            uri.host == 'objects.githubusercontent.com')) {
      return false;
    }
    try {
      return await _launchUrl(uri);
    } catch (e) {
      debugPrint('打开更新下载页失败: $e');
      return false;
    }
  }

  bool _checkedRecently(SharedPreferences prefs) {
    final raw = prefs.getString(GlobalConstants.updateLastCheckKey);
    if (raw == null || raw.isEmpty) return false;
    final last = DateTime.tryParse(raw);
    if (last == null) return false;
    return DateTime.now().difference(last) < cacheTtl;
  }

  /// 优先读取 CI 注入的 `GH_RELEASE_TAG`，本地无注入时回退读取包信息
  static Future<String> _readCurrentVersionTag() async {
    const tagged = GlobalConstants.appReleaseTag;
    if (tagged.isNotEmpty) {
      return tagged;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final ver = normalizeVersion(info.version);
      final rawBuild = int.tryParse(info.buildNumber.trim()) ?? 0;
      // Flutter --split-per-abi 会在 versionCode 上加 1000 * ABI_INDEX 偏移量
      final cleanBuild = rawBuild >= 1000 ? rawBuild % 1000 : rawBuild;
      return cleanBuild > 0 ? '$ver+$cleanBuild' : ver;
    } catch (e) {
      debugPrint('读取本机版本信息失败: $e');
      return '';
    }
  }

  static Future<bool> _launchExternal(Uri url) {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
