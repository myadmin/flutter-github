import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/pages/Footprint/index.dart';
import 'package:gh_explorer/pages/Login/index.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/MyRepos/index.dart';
import 'package:gh_explorer/pages/MyStars/index.dart';
import 'package:gh_explorer/pages/Notifications/index.dart';
import 'package:gh_explorer/pages/RepoCommitDetail/index.dart';
import 'package:gh_explorer/pages/RepoCommits/index.dart';
import 'package:gh_explorer/pages/RepoDetail/index.dart';
import 'package:gh_explorer/pages/RepoFileView/index.dart';
import 'package:gh_explorer/pages/RepoFiles/index.dart';
import 'package:gh_explorer/pages/RepoIssueCreate/index.dart';
import 'package:gh_explorer/pages/RepoIssueDetail/index.dart';
import 'package:gh_explorer/pages/RepoIssues/index.dart';
import 'package:gh_explorer/pages/RepoPeople/index.dart';
import 'package:gh_explorer/pages/RepoReleases/index.dart';
import 'package:gh_explorer/pages/Search/index.dart';
import 'package:gh_explorer/pages/Settings/index.dart';
import 'package:gh_explorer/pages/Unknown/index.dart';
import 'package:gh_explorer/pages/UserDetail/index.dart';
import 'package:gh_explorer/pages/UserFollows/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/stores/theme_controller.dart';

/// 根 Widget 与主题配置（对齐 hm_shop routes/index.dart，支持实时明/暗/跟随系统切换）
Widget getRootWidget() {
  final themeController = Get.isRegistered<ThemeController>()
      ? Get.find<ThemeController>()
      : Get.put(ThemeController(), permanent: true);

  return Obx(
    () => MaterialApp(
      title: 'GitHub 探索',
      debugShowCheckedModeBanner: false,
      routes: getRootRoutes(),
      onGenerateRoute: buildRoute,
      onGenerateInitialRoutes: buildInitialRoutes,
      onUnknownRoute: buildUnknownRoute,
      builder: clampTextScale,
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: themeController.themeMode.value,
    ),
  );
}

/// 限制系统字号缩放在 1.0 ~ 1.3，防止大字号下固定高度区域文字被裁切
Widget clampTextScale(BuildContext context, Widget? child) {
  return MediaQuery.withClampedTextScaling(
    minScaleFactor: 1,
    maxScaleFactor: 1.3,
    child: child ?? const SizedBox.shrink(),
  );
}

/// 解析查询串路由并生成对应页面
Route<dynamic> buildRoute(RouteSettings settings) {
  final name = settings.name ?? '/';
  final uri = Uri.tryParse(name);
  final path = uri != null && uri.path.isNotEmpty ? uri.path : name;
  final builder = getRootRoutes()[path];
  if (builder == null) {
    return buildUnknownRoute(settings);
  }
  final query = uri?.queryParameters ?? const <String, String>{};
  final arguments =
      settings.arguments ??
      (query.isEmpty ? null : <String, dynamic>{...query});
  return MaterialPageRoute<void>(
    builder: builder,
    settings: RouteSettings(name: name, arguments: arguments),
  );
}

/// 构造「首页 + 目标页」两层初始栈，防止深链返回时出现空参中间页
List<Route<dynamic>> buildInitialRoutes(String initialRoute) {
  final home = buildRoute(const RouteSettings(name: AppRoutes.home));
  final path = Uri.tryParse(initialRoute)?.path ?? initialRoute;
  if (path.isEmpty || path == AppRoutes.home) {
    return [home];
  }
  return [home, buildRoute(RouteSettings(name: initialRoute))];
}

/// 未知路由兜底处理（地址栏输入无效路径时展示提示页）
Route<dynamic> buildUnknownRoute(RouteSettings settings) {
  return MaterialPageRoute<void>(
    builder: (_) => UnknownRoutePage(location: settings.name),
    settings: settings,
  );
}

/// 构造全局 Material 主题，确保未显式设色的基础控件与自定义色板风格统一
ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final palette = isDark ? AppThemePalette.dark : AppThemePalette.light;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
      ).copyWith(
        primary: palette.primary,
        surface: palette.cardBackground,
        onSurface: palette.textPrimary,
        outline: palette.divider,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.pageBackground,
    dividerColor: palette.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.cardBackground,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.cardBackground,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      contentTextStyle: TextStyle(fontSize: 14, color: palette.textPrimary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.cardBackground,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.inputFill,
      selectedColor: palette.brandButtonBg,
      secondarySelectedColor: palette.brandButtonBg,
      labelStyle: TextStyle(color: palette.textPrimary, fontSize: 13),
      secondaryLabelStyle: TextStyle(
        color: palette.brandButtonFg,
        fontSize: 13,
      ),
      side: BorderSide.none,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: palette.cardBackground,
      selectedItemColor: palette.brandDark,
      unselectedItemColor: palette.textSecondary,
    ),
    splashFactory: InkSparkle.splashFactory,
    extensions: [palette],
  );
}

/// 从路由 arguments 中提取字符串参数表（兼容深链查询串转换后的 Map）
Map<String, String> _readParams(BuildContext context) {
  final arguments = ModalRoute.of(context)?.settings.arguments;
  if (arguments is Map) {
    return arguments.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }
  return const {};
}

/// 深链参数校验：必填参数缺失时回落到未知路由页，避免用空参数发起无效请求
Widget _guardedRoute(
  Map<String, String> params,
  List<String> requiredKeys,
  Widget Function(Map<String, String> params) builder,
) {
  final missing = requiredKeys
      .where((key) => (params[key] ?? '').trim().isEmpty)
      .toList(growable: false);
  if (missing.isNotEmpty) {
    return UnknownRoutePage(location: '缺少参数：${missing.join('、')}');
  }
  return builder(params);
}

/// 静态命名路由映射表（集中注册全部页面与查询参数解包逻辑）
Map<String, Widget Function(BuildContext)> getRootRoutes() {
  return {
    AppRoutes.home: (_) => const MainPage(),
    AppRoutes.login: (_) => const LoginPage(),
    AppRoutes.repoDetailPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) =>
            RepoDetailPage(owner: params['owner']!, repoName: params['name']!),
      );
    },
    AppRoutes.repoFilesPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) => RepoFilesPage(
          owner: params['owner']!,
          repoName: params['name']!,
          branch: params['ref'] ?? '',
          path: params['path'] ?? '',
        ),
      );
    },
    AppRoutes.repoFileViewPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name', 'path'],
        (params) => RepoFileViewPage(
          owner: params['owner']!,
          repoName: params['name']!,
          path: params['path']!,
          branch: params['ref'] ?? '',
        ),
      );
    },
    AppRoutes.repoIssuesPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) =>
            RepoIssuesPage(owner: params['owner']!, repoName: params['name']!),
      );
    },
    AppRoutes.repoIssueDetailPath: (context) {
      final p = _readParams(context);
      final number = int.tryParse(p['number'] ?? '') ?? 0;
      if (number <= 0) {
        return const UnknownRoutePage(location: '缺少参数：number');
      }
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) => RepoIssueDetailPage(
          owner: params['owner']!,
          repoName: params['name']!,
          number: number,
        ),
      );
    },
    AppRoutes.repoIssueCreatePath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) => RepoIssueCreatePage(
          owner: params['owner']!,
          repoName: params['name']!,
        ),
      );
    },
    AppRoutes.repoCommitsPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) => RepoCommitsPage(
          owner: params['owner']!,
          repoName: params['name']!,
          branch: params['branch'] ?? '',
        ),
      );
    },
    AppRoutes.repoCommitDetailPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name', 'sha'],
        (params) => RepoCommitDetailPage(
          owner: params['owner']!,
          repoName: params['name']!,
          sha: params['sha']!,
        ),
      );
    },
    AppRoutes.repoReleasesPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) => RepoReleasesPage(
          owner: params['owner']!,
          repoName: params['name']!,
        ),
      );
    },
    AppRoutes.repoCommunityPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['owner', 'name'],
        (params) => RepoCommunityPage(
          owner: params['owner']!,
          repoName: params['name']!,
          initialTab: p['tab'] ?? 'stargazers',
        ),
      );
    },
    AppRoutes.userDetailPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(p, const [
        'login',
      ], (params) => UserDetailPage(login: params['login']!));
    },
    AppRoutes.userFollowsPath: (context) {
      final p = _readParams(context);
      return _guardedRoute(
        p,
        const ['login'],
        (params) => UserFollowsPage(
          login: params['login']!,
          initialTab: params['tab'] ?? 'followers',
        ),
      );
    },
    AppRoutes.myReposPath: (_) => const MyReposPage(),
    AppRoutes.myStarsPath: (_) => const MyStarsPage(),
    AppRoutes.searchPath: (context) {
      final p = _readParams(context);
      return SearchPage(initialQuery: p['q'] ?? '');
    },
    AppRoutes.notificationsPath: (_) => const NotificationsPage(),
    AppRoutes.footprintPath: (_) => const FootprintPage(),
    AppRoutes.settingsPath: (_) => const SettingsPage(),
  };
}
