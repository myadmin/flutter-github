import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/pages/Footprint/index.dart';
import 'package:gh_explorer/pages/Login/index.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/MyRepos/index.dart';
import 'package:gh_explorer/pages/MyStars/index.dart';
import 'package:gh_explorer/pages/Notifications/index.dart';
import 'package:gh_explorer/pages/RepoCommits/index.dart';
import 'package:gh_explorer/pages/RepoDetail/index.dart';
import 'package:gh_explorer/pages/RepoFileView/index.dart';
import 'package:gh_explorer/pages/RepoFiles/index.dart';
import 'package:gh_explorer/pages/RepoIssueDetail/index.dart';
import 'package:gh_explorer/pages/RepoIssues/index.dart';
import 'package:gh_explorer/pages/Unknown/index.dart';
import 'package:gh_explorer/pages/UserDetail/index.dart';
import 'package:gh_explorer/pages/UserFollows/index.dart';
import 'package:gh_explorer/routes/app_routes.dart';

/// 根 Widget 与主题配置（对齐 hm_shop routes/index.dart）
Widget getRootWidget() {
  return MaterialApp(
    title: 'GitHub 探索',
    debugShowCheckedModeBanner: false,
    routes: getRootRoutes(),
    onGenerateRoute: buildRoute,
    onGenerateInitialRoutes: buildInitialRoutes,
    onUnknownRoute: buildUnknownRoute,
    builder: clampTextScale,
    theme: buildAppTheme(),
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

/// 构造全局 Material 主题，确保未显式设色的基础控件风格统一
ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    splashFactory: InkSparkle.splashFactory,
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

/// 静态命名路由映射表（集中注册全部页面与查询参数解包逻辑）
Map<String, Widget Function(BuildContext)> getRootRoutes() {
  return {
    AppRoutes.home: (_) => const MainPage(),
    AppRoutes.login: (_) => const LoginPage(),
    AppRoutes.repoDetailPath: (context) {
      final p = _readParams(context);
      return RepoDetailPage(owner: p['owner'] ?? '', repoName: p['name'] ?? '');
    },
    AppRoutes.repoFilesPath: (context) {
      final p = _readParams(context);
      return RepoFilesPage(
        owner: p['owner'] ?? '',
        repoName: p['name'] ?? '',
        branch: p['ref'] ?? '',
        path: p['path'] ?? '',
      );
    },
    AppRoutes.repoFileViewPath: (context) {
      final p = _readParams(context);
      return RepoFileViewPage(
        owner: p['owner'] ?? '',
        repoName: p['name'] ?? '',
        path: p['path'] ?? '',
        branch: p['ref'] ?? '',
      );
    },
    AppRoutes.repoIssuesPath: (context) {
      final p = _readParams(context);
      return RepoIssuesPage(owner: p['owner'] ?? '', repoName: p['name'] ?? '');
    },
    AppRoutes.repoIssueDetailPath: (context) {
      final p = _readParams(context);
      return RepoIssueDetailPage(
        owner: p['owner'] ?? '',
        repoName: p['name'] ?? '',
        number: int.tryParse(p['number'] ?? '') ?? 0,
      );
    },
    AppRoutes.repoCommitsPath: (context) {
      final p = _readParams(context);
      return RepoCommitsPage(
        owner: p['owner'] ?? '',
        repoName: p['name'] ?? '',
        branch: p['branch'] ?? '',
      );
    },
    AppRoutes.userDetailPath: (context) {
      final p = _readParams(context);
      return UserDetailPage(login: p['login'] ?? '');
    },
    AppRoutes.userFollowsPath: (context) {
      final p = _readParams(context);
      return UserFollowsPage(
        login: p['login'] ?? '',
        initialTab: p['tab'] ?? 'followers',
      );
    },
    AppRoutes.myReposPath: (_) => const MyReposPage(),
    AppRoutes.myStarsPath: (_) => const MyStarsPage(),
    AppRoutes.notificationsPath: (_) => const NotificationsPage(),
    AppRoutes.footprintPath: (_) => const FootprintPage(),
  };
}
