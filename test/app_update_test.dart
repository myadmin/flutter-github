import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/api/release.dart';
import 'package:gh_explorer/components/common/gh_update_dialog.dart';
import 'package:gh_explorer/models/app_release.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/Mine/index.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/services/app_installer.dart';
import 'package:gh_explorer/services/app_update_service.dart';
import 'package:gh_explorer/stores/token_manager.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 应用内自动检查更新与 APK 下载安装链路测试
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await tokenManager.init();
    DioRequest.onUnauthorized = null;
    registerTestControllers();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppInstaller.channel, null);
  });

  Map<String, dynamic> releaseJson({
    String tagName = 'v1.0.0-build.5',
    String body = '- 支持应用内自动下载安装包',
  }) {
    return {
      'tag_name': tagName,
      'body': body,
      'html_url':
          'https://github.com/myadmin/flutter-github/releases/tag/$tagName',
      'assets': [
        {
          'name': 'app-armeabi-v7a-release.apk',
          'browser_download_url':
              'https://github.com/myadmin/flutter-github/releases/download/$tagName/app-armeabi-v7a-release.apk',
          'size': 16 * 1024 * 1024,
        },
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url':
              'https://github.com/myadmin/flutter-github/releases/download/$tagName/app-arm64-v8a-release.apk',
          'size': 18 * 1024 * 1024,
        },
        {
          'name': 'app-release.aab',
          'browser_download_url':
              'https://github.com/myadmin/flutter-github/releases/download/$tagName/app-release.aab',
          'size': 50 * 1024 * 1024,
        },
      ],
    };
  }

  test('版本解析、大小比较与 ABI 安装包挑选逻辑准确', () {
    expect(compareReleaseVersions('v1.0.0-build.5', '1.0.0+1'), greaterThan(0));
    expect(
      compareReleaseVersions('v1.0.0-build.5', 'v1.0.0-build.5'),
      equals(0),
    );
    expect(
      compareReleaseVersions('v1.0.0-build.4', 'v1.0.0-build.5'),
      lessThan(0),
    );
    expect(compareReleaseVersions('v1.0.1', 'v1.0.0-build.99'), greaterThan(0));
    expect(compareReleaseVersions('v1.0.1', '1.0.1+5'), equals(0));

    final release = AppRelease.fromJson(releaseJson());
    expect(release.versionName, '1.0.0');
    expect(release.buildNumber, 5);
    expect(release.displayVersion, 'v1.0.0 (build 5)');

    final arm64 = release.pickAndroidApkAsset(supportedAbis: ['arm64-v8a']);
    expect(arm64?.name, 'app-arm64-v8a-release.apk');
    expect(arm64?.sizeText, '18.0 MB');

    final arm32 = release.pickAndroidApkAsset(supportedAbis: ['armeabi-v7a']);
    expect(arm32?.name, 'app-armeabi-v7a-release.apk');
  });

  test('fetchLatestReleaseAPI 正确请求 GitHub latest release 接口', () async {
    final mock = installMock((options) {
      expect(options.path, '/repos/myadmin/flutter-github/releases/latest');
      return jsonResponse(releaseJson());
    });

    final release = await fetchLatestReleaseAPI();
    expect(release?.tagName, 'v1.0.0-build.5');
    expect(release?.assets.length, 3);
    expect(mock.requests.length, 1);
  });

  test('AppUpdateService 节流冷却、跳过版本与强制手动刷新行为正确', () async {
    var fetchCount = 0;
    final service = AppUpdateService(
      autoCheckEnabled: true,
      currentVersionLoader: () async => 'v1.0.0-build.3',
      releaseFetcher: () async {
        fetchCount++;
        return AppRelease.fromJson(releaseJson(tagName: 'v1.0.0-build.5'));
      },
    );

    // 首次检测返回新版并写入冷却时间戳
    final first = await service.check();
    expect(first?.tagName, 'v1.0.0-build.5');
    expect(fetchCount, 1);

    // 冷却期内静默检测不再发请求
    final second = await service.check();
    expect(second, isNull);
    expect(fetchCount, 1);

    // 跳过该版本后即使手动/过冷却也不在静默检测返回
    await service.skip(first!);
    final forcedAfterSkip = await service.check(force: true);
    expect(forcedAfterSkip?.tagName, 'v1.0.0-build.5');
    expect(fetchCount, 2);

    // 模拟断网：静默检测吞掉异常，手动检测抛出异常
    final errorService = AppUpdateService(
      autoCheckEnabled: true,
      currentVersionLoader: () async => 'v1.0.0-build.3',
      releaseFetcher: () async => throw Exception('Network Error'),
    );
    expect(await errorService.check(), isNull);
    await expectLater(errorService.check(force: true), throwsException);
  });

  test('AppUpdateService 下载并安装 APK 选中匹配设备 ABI', () async {
    String? downloadedUrl;
    String? installedPath;

    final service = AppUpdateService(
      autoCheckEnabled: true,
      environmentLoader: () async => const AndroidInstallEnvironment(
        cacheDir: '/tmp/updates',
        supportedAbis: ['armeabi-v7a'],
        canRequestPackageInstalls: true,
      ),
      apkDownloader:
          ({
            required String url,
            required String directoryPath,
            required String fileName,
            ApkDownloadProgressCallback? onProgress,
            CancelToken? cancelToken,
          }) async {
            downloadedUrl = url;
            onProgress?.call(512, 1024);
            return '$directoryPath/$fileName';
          },
      apkInstaller: (filePath) async {
        installedPath = filePath;
        return AppInstallStatus.launched;
      },
    );

    final release = AppRelease.fromJson(releaseJson());
    var lastReceived = 0;
    final path = await service.downloadApk(
      release,
      onProgress: (received, total) => lastReceived = received,
    );
    expect(downloadedUrl, contains('app-armeabi-v7a-release.apk'));
    expect(lastReceived, 512);

    final status = await service.installApk(path);
    expect(status, AppInstallStatus.launched);
    expect(installedPath, path);
  });

  testWidgets('更新弹窗展示下载进度条并在未授权未知来源时引导继续安装', (tester) async {
    final downloadCompleter = Completer<String>();
    void Function(int received, int total)? capturedProgress;
    var installCalls = 0;

    final service = AppUpdateService(
      autoCheckEnabled: true,
      currentVersionLoader: () async => 'v1.0.0-build.3',
      releaseFetcher: () async => AppRelease.fromJson(releaseJson()),
      environmentLoader: () async => const AndroidInstallEnvironment(
        cacheDir: '/tmp/updates',
        supportedAbis: ['arm64-v8a'],
        canRequestPackageInstalls: false,
      ),
      apkDownloader:
          ({
            required String url,
            required String directoryPath,
            required String fileName,
            ApkDownloadProgressCallback? onProgress,
            CancelToken? cancelToken,
          }) {
            capturedProgress = onProgress;
            return downloadCompleter.future;
          },
      apkInstaller: (filePath) async {
        installCalls++;
        // 首次触发授权引导，第二次触发已授权安装
        return installCalls == 1
            ? AppInstallStatus.needsPermission
            : AppInstallStatus.launched;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  final release = AppRelease.fromJson(releaseJson());
                  await showGhUpdateDialog(
                    context,
                    release: release,
                    currentVersion: 'v1.0.0-build.3',
                    service: service,
                    inAppInstallOverride: true,
                  );
                },
                child: const Text('打开更新'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v1.0.0 (build 5)'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);

    await tester.tap(find.text('立即更新'));
    await tester.pump();

    expect(find.text('正在下载新版安装包，请保持应用在前台'), findsOneWidget);
    capturedProgress?.call(9 * 1024 * 1024, 18 * 1024 * 1024);
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);

    downloadCompleter.complete('/tmp/updates/app.apk');
    await tester.pumpAndSettle();

    // 首次未授权未知来源权限，提示继续安装
    expect(find.text('安装包已下载完成！'), findsOneWidget);
    expect(find.text('继续安装'), findsOneWidget);

    await tester.tap(find.text('继续安装'));
    await tester.pumpAndSettle();
    expect(find.text('安装包已就绪，正在调起系统安装界面…'), findsOneWidget);
    expect(installCalls, 2);
  });

  testWidgets('下载失败时支持重试下载与浏览器兜底', (tester) async {
    var failOnce = true;
    Uri? openedBrowserUrl;

    final service = AppUpdateService(
      autoCheckEnabled: true,
      environmentLoader: () async => const AndroidInstallEnvironment(
        cacheDir: '/tmp/updates',
        supportedAbis: ['arm64-v8a'],
        canRequestPackageInstalls: true,
      ),
      apkDownloader:
          ({
            required String url,
            required String directoryPath,
            required String fileName,
            ApkDownloadProgressCallback? onProgress,
            CancelToken? cancelToken,
          }) async {
            if (failOnce) {
              failOnce = false;
              throw Exception('连接超时');
            }
            return '/tmp/updates/app.apk';
          },
      urlLauncher: (uri) async {
        openedBrowserUrl = uri;
        return true;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showGhUpdateDialog(
                context,
                release: AppRelease.fromJson(releaseJson()),
                currentVersion: 'v1.0.0-build.3',
                service: service,
                inAppInstallOverride: true,
              ),
              child: const Text('测试失败弹窗'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('测试失败弹窗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();

    expect(find.text('重试下载'), findsOneWidget);
    expect(find.text('浏览器下载'), findsOneWidget);

    await tester.tap(find.text('浏览器下载'));
    await tester.pumpAndSettle();
    expect(openedBrowserUrl.toString(), contains('releases'));
  });

  testWidgets('MainPage 启动自动检测发现新版弹窗，MineView 手动检查更新响应最新状态', (tester) async {
    installMock((options) {
      if (options.path == '/search/repositories') {
        return jsonResponse(searchReposJson());
      }
      if (options.path == '/rate_limit') {
        return jsonResponse(rateLimitJson());
      }
      return jsonResponse(<String, dynamic>{});
    });

    final hasNewService = AppUpdateService(
      autoCheckEnabled: true,
      currentVersionLoader: () async => 'v1.0.0-build.3',
      releaseFetcher: () async => AppRelease.fromJson(releaseJson()),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(updateService: hasNewService),
        onGenerateRoute: buildRoute,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v1.0.0 (build 5)'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    // 验证 MineView 在已是最新版本时提示 Toast
    final upToDateService = AppUpdateService(
      autoCheckEnabled: true,
      currentVersionLoader: () async => 'v1.0.0-build.5',
      releaseFetcher: () async => AppRelease.fromJson(releaseJson()),
    );
    await tester.pumpWidget(
      buildTestApp(Scaffold(body: MineView(updateService: upToDateService))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前已是最新版本'), findsOneWidget);
  });

  test('MethodChannel 在 Android 与非 Android 平台上分别返回对应安装状态', () async {
    expect(AppInstaller.channel.name, 'com.example.gh_explorer/app_installer');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppInstaller.channel, (
          MethodCall call,
        ) async {
          if (call.method == 'getPlatformInstallInfo') {
            return <String, dynamic>{
              'cacheDir': '/data/cache/updates',
              'supportedAbis': <String>['arm64-v8a'],
              'canRequestPackageInstalls': true,
            };
          }
          if (call.method == 'installApk') {
            final args = call.arguments as Map<dynamic, dynamic>?;
            return args?['filePath'] == '/need_perm.apk'
                ? 'needs_permission'
                : 'launched';
          }
          return null;
        });

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final env = await AppInstaller.getEnvironment();
      expect(env?.cacheDir, '/data/cache/updates');
      expect(env?.supportedAbis, ['arm64-v8a']);
      expect(env?.canRequestPackageInstalls, isTrue);
      expect(
        await AppInstaller.installApk('/ok.apk'),
        AppInstallStatus.launched,
      );
      expect(
        await AppInstaller.installApk('/need_perm.apk'),
        AppInstallStatus.needsPermission,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    // 非 Android 平台安全降级返回 null 与 unsupported
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      expect(await AppInstaller.getEnvironment(), isNull);
      expect(
        await AppInstaller.installApk('/tmp/a.apk'),
        AppInstallStatus.unsupported,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
