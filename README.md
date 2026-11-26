# gh_explorer

参考 `hm_shop` 分层架构与工程规范构建的 Flutter GitHub 客户端应用（支持 Android / iOS / Web / Windows）。

## 核心功能

- **完整登录体系**：
  - 支持 **Personal Access Token (PAT)** 登录（全平台通用，含「前往 GitHub 生成 Token」外链及权限指引）；
  - 支持 **GitHub OAuth Device Flow** 设备授权码登录（非 Web 端可用，带倒计时轮询）；
  - 基于 `shared_preferences` 持久化 Token 与 Scope，冷启动自动恢复会话，拦截 HTTP 401 并跳转登录，支持二次确认退出登录。
- **底部 4 Tab 懒加载架构**：
  - **探索**：按编程语言（Dart / TypeScript / Python / Go / Rust / Swift 等）与时间窗口（今日 / 本周 / 本月 / 历史）浏览热门开源项目，带呼吸骨架屏、下拉刷新与上拉分页；
  - **搜索**：支持仓库与用户双类型搜索、排序切换（最佳匹配 / Star 最多 / Fork 最多 / 最近更新）、本地搜索历史与热搜词；
  - **动态**：展示已关注开发者的事件流（Star / Fork / Push / Release / Issue / PR）与消息通知入口（支持仅未读筛选与标为已读）；
  - **我的**：展示个人资料统计（公开仓库 / Followers / Following）、快捷入口（我的仓库 / 我的 Star / 消息通知 / 本地浏览足迹）、实时 GitHub API 配额、Token 权限范围以及应用内自动检查更新（Android 端支持应用内下载带进度条的 APK 并自动调起系统安装界面）。
- **项目查看与 Star 互动**：
  - **仓库详情**：概览信息、Topic 标签、开源协议、代码浏览 / Issues / Commits 导航、Markdown README 渲染（自动修正相对图片路径，SVG 徽章优雅降级）；
  - **点 Star / 取消 Star**：未登录拦截跳转登录页，已登录支持**乐观更新 + 失败回滚**，并通过 `StarSyncController` 在探索页、搜索页、我的 Star 与详情页之间实时联动；
  - **代码与 Issue 浏览**：支持分支切换、目录树下钻、带行号源码查看、图片预览、Commit SHA 复制、Issue 列表与详情评论提交、开发者主页与 Follow 互动。

## 目录结构

```text
lib/
├── api/          # GitHub REST v3 接口封装（auth / user / repo / search / star / issue / feed）
├── components/   # 公共与业务组件（GhRepoCard / GhStarButton / GhMarkdownView / Mine 组件等）
├── constants/    # 颜色令牌、语言色板、文字样式、接口地址常量
├── models/       # 安全解析工具 parsers.dart 与业务模型
├── pages/        # 各 Tab 与二级深链页面
├── routes/       # 查询串路由构造（AppRoutes）与深链解析
├── stores/       # TokenManager、GetX 控制器（User / StarSync / RateLimit）、本地历史存储
├── utils/        # DioRequest（Link 分页 / 204&404 / 速率限制 / 401）、PagedListController 等
└── main.dart     # 入口与全局状态注册
```

## 质量检查命令

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
flutter build web --release
```

## GitHub Actions 自动化流程

仓库已在 `.github/workflows/` 中补全 CI 门禁、Web 端打包部署与 Android 端打包发版脚本（均针对 `master` 分支）：

| 工作流文件 | 触发方式 | 说明 |
| --- | --- | --- |
| `.github/workflows/dart.yml` | push / PR 到 `master` | 格式校验、`--fatal-infos` 静态分析、单测与 80% 覆盖率门禁、`build web` 冒烟 |
| `.github/workflows/web.yml` | push / PR 到 `master`、手动触发 | 构建 Web Release（按仓库名子路径 `--base-href`、精简 `*.symbols`、补充 `404.html` 深链兜底），上传 `gh-explorer-web` Artifact 并部署到 GitHub Pages |
| `.github/workflows/android.yml` | push 到 `master`、`v*` 标签、手动触发 | 在 Ubuntu + JDK 17 环境构建分 ABI APK 与 AAB；上传 `gh-explorer-android` Artifact 并自动发布到 GitHub Releases（标签使用 `v*` 或 `v<versionName>-build.<run_number>`） |

- **GitHub Pages 说明**：如需自动部署在线预览页，请在 GitHub 仓库的 `Settings -> Pages -> Build and deployment -> Source` 中选择 **GitHub Actions**；未启用时 `build-web` 仍会产出可下载的 `gh-explorer-web` 构建产物。
- **更新说明生成机制**：发布 Release 时会自动提取 [CHANGELOG.md](CHANGELOG.md) 对应版本段落及上一版以来的 Git 提交记录，并在应用内更新弹窗中以「更新说明」渲染展示；手动运行也可填写 `release_notes` 自定义说明。
- **Android 正式签名（可选）**：未配置仓库 Secrets 时自动回退为 debug 签名（可直接装机试用）；如需正式签名，配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS` 即可自动切换（参考 `android/key.properties.example`）。
- **Release 权限说明**：通过标签或手动触发创建 Release 需要 GitHub 仓库 `Settings -> Actions -> General -> Workflow permissions` 允许读写权限（`Read and write permissions`）。
