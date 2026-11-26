import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/pages/Main/index.dart';
import 'package:gh_explorer/pages/Settings/index.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/stores/theme_controller.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
  });

  tearDown(() {
    Get.reset();
    DioRequest.onResourceRateLimitUpdate = null;
  });

  test('ThemeController 支持序列化、解析、持久化加载与恢复默认', () async {
    expect(ThemeController.serializeMode(ThemeMode.light), 'light');
    expect(ThemeController.serializeMode(ThemeMode.dark), 'dark');
    expect(ThemeController.serializeMode(ThemeMode.system), 'system');

    expect(ThemeController.parseMode('light'), ThemeMode.light);
    expect(ThemeController.parseMode(' DARK '), ThemeMode.dark);
    expect(ThemeController.parseMode('system'), ThemeMode.system);
    expect(ThemeController.parseMode('unknown'), ThemeMode.system);
    expect(ThemeController.parseMode(null), ThemeMode.system);

    expect(ThemeController.labelOf(ThemeMode.light), '亮色');
    expect(ThemeController.labelOf(ThemeMode.dark), '暗色');
    expect(ThemeController.labelOf(ThemeMode.system), '跟随系统');

    SharedPreferences.setMockInitialValues({
      GlobalConstants.themeModeKey: 'dark',
    });
    final controller = ThemeController();
    await controller.ensureLoaded();
    expect(controller.themeMode.value, ThemeMode.dark);
    expect(controller.currentLabel, '暗色');
    expect(controller.descriptionFor(Brightness.light), '已固定为暗色主题');

    await controller.setThemeMode(ThemeMode.light);
    expect(controller.themeMode.value, ThemeMode.light);
    expect(controller.descriptionFor(Brightness.dark), '已固定为亮色主题');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(GlobalConstants.themeModeKey), 'light');

    // 重复写入相同模式不破坏状态
    await controller.setThemeMode(ThemeMode.light);
    expect(controller.themeMode.value, ThemeMode.light);

    await controller.resetDefault();
    expect(controller.themeMode.value, ThemeMode.system);
    expect(controller.descriptionFor(Brightness.dark), '跟随系统色（当前为暗色）');
    expect(controller.descriptionFor(Brightness.light), '跟随系统色（当前为亮色）');
    expect(prefs.getString(GlobalConstants.themeModeKey), 'system');
  });

  test('AppThemePalette 支持 copyWith 与 lerp 平滑插值', () {
    final copied = AppThemePalette.light.copyWith(primary: Colors.teal);
    expect(copied.primary, Colors.teal);
    expect(copied.cardBackground, AppThemePalette.light.cardBackground);

    final mid = AppThemePalette.light.lerp(AppThemePalette.dark, 0.5);
    expect(mid.isDark, isTrue);
    expect(mid.pageBackground, isNot(AppThemePalette.light.pageBackground));
    expect(mid.pageBackground, isNot(AppThemePalette.dark.pageBackground));
  });

  testWidgets('设置页可切换亮色/暗色/跟随系统并实时更新主题，支持恢复默认', (tester) async {
    registerTestControllers();
    installMock((options) {
      if (options.path == '/search/repositories') {
        return jsonResponse(searchReposJson());
      }
      if (options.path == '/rate_limit') {
        return jsonResponse(rateLimitJson());
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(buildTestApp(const MainPage()));
    await tester.pumpAndSettle();

    // 切到「我的」页可见设置入口中的当前主题提示与已选标签计数
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.textContaining('跟随系统'), findsOneWidget);
    expect(find.text('已选 10 项'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('外观主题色'), findsOneWidget);

    // 切换为「暗色」并验证上下文色板、字体颜色、AppThemePalette 与持久化生效
    await tester.tap(find.text('暗色'));
    await tester.pumpAndSettle();

    final controller = Get.find<ThemeController>();
    expect(controller.themeMode.value, ThemeMode.dark);
    final darkContext = tester.element(find.byType(SettingsPage));
    expect(Theme.of(darkContext).brightness, Brightness.dark);
    expect(darkContext.appColors.isDark, isTrue);
    expect(
      darkContext.appColors.pageBackground,
      AppThemePalette.dark.pageBackground,
    );
    expect(darkContext.bodyStrongStyle.color, AppThemePalette.dark.textPrimary);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(GlobalConstants.themeModeKey), 'dark');

    // 切换为「亮色」
    await tester.tap(find.text('亮色'));
    await tester.pumpAndSettle();
    expect(controller.themeMode.value, ThemeMode.light);
    final lightContext = tester.element(find.byType(SettingsPage));
    expect(Theme.of(lightContext).brightness, Brightness.light);
    expect(lightContext.appColors.isDark, isFalse);
    expect(
      lightContext.appColors.cardBackground,
      AppThemePalette.light.cardBackground,
    );
    expect(prefs.getString(GlobalConstants.themeModeKey), 'light');

    // 返回「我的」页可实时看到「亮色」摘要
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('亮色'), findsOneWidget);

    // 再次进入设置页点击「恢复默认」，回到「跟随系统」
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(controller.themeMode.value, ThemeMode.system);
    expect(prefs.getString(GlobalConstants.themeModeKey), 'system');
  });

  testWidgets('getRootWidget 在跟随系统模式下响应系统深浅色变化', (tester) async {
    addTearDown(() {
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    registerTestControllers();
    installMock((options) {
      if (options.path == '/search/repositories') {
        return jsonResponse(searchReposJson());
      }
      return jsonResponse(<String, dynamic>{});
    });

    await tester.pumpWidget(getRootWidget());
    await tester.pumpAndSettle();

    final lightCtx = tester.element(find.byType(MainPage));
    expect(Theme.of(lightCtx).brightness, Brightness.light);
    expect(lightCtx.appColors.isDark, isFalse);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    final darkCtx = tester.element(find.byType(MainPage));
    expect(Theme.of(darkCtx).brightness, Brightness.dark);
    expect(darkCtx.appColors.isDark, isTrue);
  });
}
