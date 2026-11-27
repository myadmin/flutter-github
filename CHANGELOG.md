# 更新日志（Changelog）

本文件记录 `gh_explorer` 各版本的重点功能与修复说明。  
每次推送到 `master` 或打 `v*` 标签构建 Android Release 时，[Build Android](.github/workflows/android.yml) 会自动把**本次更新说明**写入 GitHub Release 正文，并在手机端应用内更新弹窗中直接展示：

- 打正式 `v*` 标签（例如 `v1.0.1`）或触发输入与标题匹配时，会优先提取本文件对应 `## [1.0.1]` 段落作为「本次更新」；
- 日常推送到 `master`（自动生成 `v<versionName>-build.<run_number>`）时，会自动汇总上一版 Tag 至今的提交记录（或使用手动触发填写的更新说明）。

## [1.3.0] - 2026-11-27

### 新增与优化
- **Commit 详情与代码 Diff 对比**：点击提交历史卡片可查看完整提交信息、父提交链接、增删行数统计及逐文件 Unified Diff 高亮视图（支持折叠展开与跳转完整源文件）。
- **Pull Request 审查与闭环管理**：Issues 与 PR 列表支持「全部类型 / 仅 Issue / 仅 PR」过滤与 `#编号` 一键直达；PR 详情支持分支流向与统计展示、变更文件 Diff 审查，并支持已登录具权限用户选择 Merge / Squash / Rebase 合并；同步支持端内新建 Issue、编辑标题与正文、关闭/重开及实时更新评论数。
- **仓库 Releases / 社区浏览与细节打磨**：新增 Releases 版本及附件浏览页、社区页（Stargazers / 贡献者 / Forks 切换）、详情页分支切换联动 README 与一键复制 HTTPS/SSH Clone 地址；通知中心新增「与我相关」筛选并支持点击精准跳往 Issue / PR / Commit / Release 详情；代码阅读器主题联动全局外观、大文件 403 提供网页直链、Markdown 支持相对路径/GitHub 站内跳转与图片缩放预览，设置页新增足迹/搜索历史/推荐缓存清理，并抽离 `StarService` 与适配系统状态栏反色。

## [1.2.2] - 2026-11-27

### 优化与修复
- **页面退出即取消在途请求**：`PagedListController` 改为持有与请求代际绑定的 `CancelToken`，在 `refresh()` / `clear()` / `dispose()` 时取消未完成请求；仓库动态、通知、提交、Issues、我的仓库与 Star、关注与粉丝、仓库/用户检索、用户仓库与 Star 等 13 个分页接口支持透传令牌，切换筛选或退出页面后不再继续占用带宽与 API 配额。
- **取消请求静默处理**：新增 `RequestCancelledException` 并把 Dio 的 `cancel` 类型翻译为该异常，被取消的请求不会在列表底部弹出「加载失败」，也不会污染重试状态。

## [1.2.1] - 2026-11-27

### 优化与修复
- **仓库内 Issues / PR 搜索防注入**：对搜索关键词中的 `key:value` 限定符自动整体加引号，并对 `owner` / `repo` 做空格与冒号清洗，避免用户输入 `repo:other/repo` 等表达式把检索范围转移到其他仓库。
- **启动首帧主题正确**：`main()` 改为在 `runApp` 前等待 `ThemeController` 读取本地配置，暗色用户不再先闪一帧浅色界面。
- **搜索首屏更快**：搜索页先发起网络刷新再异步落盘搜索历史，避免 SharedPreferences 写入阻塞结果展示。
- **分页加载失败可恢复**：`PagedListController` 新增 `loadMoreFailed` 状态，失败后暂停自动重试并在列表底部展示「加载失败，点击重试」，避免断网时滚动反复打接口。
- **安装包校验可测化**：把体积 / SHA-256 / 空文件校验抽成纯函数 `verifyDownloadedApk`，并补齐 5 条单元测试覆盖此前零覆盖的安全分支。
- **图片解码更省内存**：README 内图片按容器宽度解码并补充语义标签与加载中占位；`AppNetworkImage` 未显式传 `decodeWidth` 时按 `width` 推导，统一列表头像的解码尺寸。
- **代码编辑器滚动更顺**：行富文本样式增加 LRU 缓存（上限 400 行），主题切换、字号调整、文件内搜索时整体失效，滚动与点击行不再重复分词。

## [1.2.0] - 2026-11-26

### 新增与优化
- **全局亮色 / 暗色 / 跟随系统主题切换**：新增 `ThemeController` 持久化主题设置，并在设置页集成「外观主题色（跟随系统 / 亮色 / 暗色）」实时切换卡片；扩展 `AppThemePalette`（`ThemeExtension`）与上下文响应式排版样式，实现全应用页面、卡片、导航栏、弹窗及代码高亮视图的深浅双主题适配。
- **安全性与稳定性加固**：使用 `flutter_secure_storage` 加密存储 GitHub Token（支持历史明文凭证自动迁移），新增安装包 SHA-256 与文件体积校验、外部链接安全打开校验及 Android 明文传输/备份安全配置，并补充 `app_error_reporter` 统一异常上报与更完善的次级限流/大文件错误提示。
- **应用标识统一**：Android `applicationId` / `namespace`、iOS 与 macOS Bundle Identifier、Windows 元信息及安装器 MethodChannel 统一为 `com.ghexplorer.app`，替换无法上架应用商店的 `com.example.*` 占位标识。

## [1.1.1] - 2026-11-26

### 新增与优化
- **品牌应用图标全面焕新**：生成全新「GitHub 探索」图标并替换 Web（高清圆角 `favicon.png` 与 PWA `Icon-*` / `Icon-maskable-*`）、Android（传统圆角 `ic_launcher.png` 与 API 26+ 自适应图标 `ic_launcher_foreground.png` / `mipmap-anydpi-v26`）、iOS、macOS 及 Windows 全端应用图标。
- **Web 元信息优化**：将 `web/index.html` 与 `web/manifest.json` 的页面标题、应用名称及主题色同步为 `GitHub 探索` 与 `#0C121B`。

## [1.1.0] - 2026-11-26

### 新增与优化
- **编辑器级单文件代码阅读体验**：重构 `RepoFileViewPage` 与新增 `GhCodeEditorView` / `CodeSyntaxHighlighter`，支持 20+ 种语言词法语法高亮与跨行块注释、固定行号栏、GitHub Dark / Light 一键切换、自动换行与横滑模式切换、字号调节（`A-` / `A+`）、点击激活行高亮、文件内搜索（计数与上下跳行）及 Markdown 源码/预览双模式切换。
- **Issues / PR 仓内全量搜索**：在 `RepoIssuesPage` 顶部集成搜索框，支持按关键词或 `#编号` 检索仓库全部历史 Issues 与 PR，并与 `Open / Closed / All` 状态筛选实时联动（搜索栏展示于标题下方，支持一键清空恢复常规列表）。
- **探索首页丰富化与个性化设置**：新增探索首页精选专题轮播、8 大领域 Topic 快捷入口、继续浏览足迹横条、热门开发者与组织横滑栏（带本地缓存），支持首页顶部语言标签排序/增删自定义设置与 Core / Search API 配额分桶展示。

## [1.0.0] - 2026-11-26

### 核心功能
- **完整登录体系**：支持 GitHub Personal Access Token（PAT）与 OAuth Device Flow 设备授权登录、权限 Scope 解析、冷启动会话恢复、401 自动失效拦截与二次确认退出。
- **底部 4 Tab 懒加载架构**：首页「探索」（按编程语言与时间窗口浏览热门开源项目）、「搜索」（仓库 / 用户切换、排序、热搜词与本地历史）、「动态」（关注流与消息通知已读管理）、「我的」（个人资料、快捷入口、GitHub API 配额实时监控与本地浏览足迹）。
- **仓库浏览与互动**：仓库详情、Topic / 协议信息、Markdown README 渲染（相对路径补全与 SVG 徽章降级）、目录树与带行号源码查看、Commit 记录、Issue 列表/详情与发表评论、Star / Follow 乐观更新与失败回滚。
- **Web 与 Android 自动化打包及应用内更新**：
  - GitHub Actions 自动执行格式校验、`--fatal-infos` 静态分析、单元测试与覆盖率门禁（`>= 80%`）、Web 部署至 GitHub Pages、Android 分 ABI APK（`arm64-v8a` / `armeabi-v7a` / `x86_64`）与 AAB 自动发布至 GitHub Releases。
  - Android 端支持冷启动静默检测及「我的 → 检查更新」手动检测 GitHub Releases，支持弹窗查看更新说明、应用内带进度条下载对应架构 APK（可取消/重试）并自动调起系统安装界面。
