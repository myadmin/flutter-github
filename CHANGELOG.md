# 更新日志（Changelog）

本文件记录 `gh_explorer` 各版本的重点功能与修复说明。  
每次推送到 `master` 或打 `v*` 标签构建 Android Release 时，[Build Android](.github/workflows/android.yml) 会自动把**本次更新说明**写入 GitHub Release 正文，并在手机端应用内更新弹窗中直接展示：

- 打正式 `v*` 标签（例如 `v1.0.1`）或触发输入与标题匹配时，会优先提取本文件对应 `## [1.0.1]` 段落作为「本次更新」；
- 日常推送到 `master`（自动生成 `v<versionName>-build.<run_number>`）时，会自动汇总上一版 Tag 至今的提交记录（或使用手动触发填写的更新说明）。

## [1.0.0] - 2026-11-26

### 核心功能
- **完整登录体系**：支持 GitHub Personal Access Token（PAT）与 OAuth Device Flow 设备授权登录、权限 Scope 解析、冷启动会话恢复、401 自动失效拦截与二次确认退出。
- **底部 4 Tab 懒加载架构**：首页「探索」（按编程语言与时间窗口浏览热门开源项目）、「搜索」（仓库 / 用户切换、排序、热搜词与本地历史）、「动态」（关注流与消息通知已读管理）、「我的」（个人资料、快捷入口、GitHub API 配额实时监控与本地浏览足迹）。
- **仓库浏览与互动**：仓库详情、Topic / 协议信息、Markdown README 渲染（相对路径补全与 SVG 徽章降级）、目录树与带行号源码查看、Commit 记录、Issue 列表/详情与发表评论、Star / Follow 乐观更新与失败回滚。
- **Web 与 Android 自动化打包及应用内更新**：
  - GitHub Actions 自动执行格式校验、`--fatal-infos` 静态分析、单元测试与覆盖率门禁（`>= 80%`）、Web 部署至 GitHub Pages、Android 分 ABI APK（`arm64-v8a` / `armeabi-v7a` / `x86_64`）与 AAB 自动发布至 GitHub Releases。
  - Android 端支持冷启动静默检测及「我的 → 检查更新」手动检测 GitHub Releases，支持弹窗查看更新说明、应用内带进度条下载对应架构 APK（可取消/重试）并自动调起系统安装界面。
