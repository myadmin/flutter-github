# gh_explorer 开发与发布规范

在 `gh_explorer` 仓库内完成任意功能开发、缺陷修复或配置调整后，默认必须执行以下完整交付闭环：

1. **升级版本号与更新日志**：
   - 按变更幅度递增 `pubspec.yaml` 中的 `version`（格式 `<major>.<minor>.<patch>+<buildNumber>`：新功能递增 minor 且重置 patch，修复递增 patch；`+<buildNumber>` 单调递增，避免低于远端已发布构建号）。
   - 在 `CHANGELOG.md` 顶部补充对应版本的简要中文更新条目。
2. **代码规范与测试门禁**：
   - 运行 `dart format --output=none --set-exit-if-changed lib test`
   - 运行 `flutter analyze --fatal-infos`
   - 运行 `flutter test --coverage`，确认全部测试通过且行覆盖率不低于 `80%`。
3. **构建 Android 安装包**：
   - 本地执行 `flutter build apk --release --split-per-abi` 验证 Android Release 打包可正常出包（产出 `arm64-v8a` / `armeabi-v7a` / `x86_64` 安装包）。
4. **提交并推送远程仓库**：
   - 使用清晰的中文规范提交信息提交改动并推送至 `origin/master`，由 `.github/workflows/android.yml` 与 `.github/workflows/web.yml` 自动完成云端发布与部署。
