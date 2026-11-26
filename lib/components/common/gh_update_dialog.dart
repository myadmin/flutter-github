import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/app_release.dart';
import 'package:gh_explorer/services/app_installer.dart';
import 'package:gh_explorer/services/app_update_service.dart';
import 'package:gh_explorer/utils/api_exception.dart';

/// 弹出应用更新提示弹窗：
/// - Android 原生端支持点击「立即更新」后在应用内下载 APK（带进度条、可取消），下载完成自动调起系统安装界面；
/// - 非 Android 端或缺少 APK 资产时自动回退跳转到浏览器下载页面。
Future<void> showGhUpdateDialog(
  BuildContext context, {
  required AppRelease release,
  required String currentVersion,
  AppUpdateService? service,
  bool? inAppInstallOverride,
}) {
  final updateService = service ?? AppUpdateService.instance;
  final canInAppInstall =
      inAppInstallOverride ??
      (updateService.supportsInAppApkInstall &&
          release.pickAndroidApkAsset() != null);

  return showDialog<void>(
    context: context,
    barrierDismissible: !canInAppInstall,
    builder: (dialogContext) {
      return _GhUpdateDialog(
        release: release,
        currentVersion: currentVersion,
        service: updateService,
        canInAppInstall: canInAppInstall,
      );
    },
  );
}

enum _UpdateDialogStage {
  ready,
  downloading,
  awaitingPermission,
  downloaded,
  error,
}

class _GhUpdateDialog extends StatefulWidget {
  const _GhUpdateDialog({
    required this.release,
    required this.currentVersion,
    required this.service,
    required this.canInAppInstall,
  });

  final AppRelease release;
  final String currentVersion;
  final AppUpdateService service;
  final bool canInAppInstall;

  @override
  State<_GhUpdateDialog> createState() => _GhUpdateDialogState();
}

class _GhUpdateDialogState extends State<_GhUpdateDialog> {
  _UpdateDialogStage _stage = _UpdateDialogStage.ready;
  CancelToken? _cancelToken;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedPath;
  String _errorMessage = '';

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  /// 格式化当前版本号文案，避免重复拼接 `v` 前缀
  String get _currentLabel {
    final v = widget.currentVersion.trim();
    if (v.isEmpty) return '未知';
    return v.startsWith('v') || v.startsWith('V') ? v : 'v$v';
  }

  String _formatMb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 启动应用内 APK 下载，并在下载完成后立即调起系统安装器
  Future<void> _startInAppUpdate() async {
    final token = CancelToken();
    setState(() {
      _cancelToken = token;
      _stage = _UpdateDialogStage.downloading;
      _receivedBytes = 0;
      _totalBytes = 0;
      _errorMessage = '';
    });

    try {
      final path = await widget.service.downloadApk(
        widget.release,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
          });
        },
      );
      if (!mounted) return;
      _downloadedPath = path;
      await _triggerInstall(path);
    } on DioException catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e)) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _stage = _UpdateDialogStage.error;
        _errorMessage = resolveErrorMessage(
          e,
          fallback: '下载安装包失败，请检查网络或改用浏览器下载',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateDialogStage.error;
        _errorMessage = resolveErrorMessage(e, fallback: '更新准备失败，请重试或前往浏览器下载');
      });
    } finally {
      _cancelToken = null;
    }
  }

  /// 调起 Android 系统安装界面，若缺「安装未知来源」权限则引导用户授权后继续
  Future<void> _triggerInstall(String path) async {
    try {
      final status = await widget.service.installApk(path);
      if (!mounted) return;
      if (status == AppInstallStatus.needsPermission) {
        setState(() {
          _stage = _UpdateDialogStage.awaitingPermission;
        });
      } else {
        setState(() {
          _stage = _UpdateDialogStage.downloaded;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateDialogStage.error;
        _errorMessage = resolveErrorMessage(e, fallback: '调起系统安装器失败，请尝试重新安装');
      });
    }
  }

  /// 跳往浏览器下载或查看 Release 页面（非 Android 端默认行为 / 下载异常兜底）
  Future<void> _openInBrowser() async {
    await widget.service.openDownloadPage(widget.release);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
  }

  Widget _buildContent() {
    final apkAsset = widget.release.pickAndroidApkAsset();
    final sizeText = apkAsset?.sizeText ?? '';
    final summary = sizeText.isEmpty
        ? '当前版本 $_currentLabel'
        : '当前版本 $_currentLabel · 安装包 $sizeText';

    switch (_stage) {
      case _UpdateDialogStage.ready:
        final summaryNotes = widget.release.updateSummaryNotes;
        final displayNotes = summaryNotes.isNotEmpty
            ? summaryNotes
            : '包含最新功能优化与问题修复，建议更新体验。';
        return SizedBox(
          width: 320,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(summary, style: context.captionStyle),
                  const SizedBox(height: 10),
                  Text('更新说明', style: context.bodyStrongStyle),
                  const SizedBox(height: 6),
                  GhMarkdownView(
                    data: displayNotes,
                    owner: 'myadmin',
                    repo: 'flutter-github',
                    branch: 'master',
                  ),
                ],
              ),
            ),
          ),
        );

      case _UpdateDialogStage.downloading:
        final hasTotal = _totalBytes > 0;
        final ratio = hasTotal
            ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0)
            : null;
        final pctText = hasTotal
            ? '${(ratio! * 100).toStringAsFixed(0)}%'
            : '下载中';
        final bytesHint = hasTotal
            ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)}'
            : '已下载 ${_formatMb(_receivedBytes)}';

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在下载新版安装包，请保持应用在前台', style: context.bodySmallStyle),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.small),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: context.appColors.inputFill,
                valueColor: AlwaysStoppedAnimation<Color>(
                  context.appColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(bytesHint, style: context.captionStyle),
                Text(
                  pctText,
                  style: context.captionStyle.copyWith(
                    color: context.appColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        );

      case _UpdateDialogStage.awaitingPermission:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装包已下载完成！', style: context.bodyStrongStyle),
            const SizedBox(height: 6),
            Text(
              '系统尚未开启本应用「安装未知来源应用」权限。请在弹出的系统设置中开启授权后，返回本弹窗点击「继续安装」。',
              style: context.bodySmallStyle.copyWith(height: 1.55),
            ),
          ],
        );

      case _UpdateDialogStage.downloaded:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装包已就绪，正在调起系统安装界面…', style: context.bodyStrongStyle),
            const SizedBox(height: 6),
            Text(
              '如果未弹出安装页面或系统提示签名冲突，请确认新旧版本签名一致，也可尝试点击「重新安装」或前往浏览器下载。',
              style: context.captionStyle.copyWith(height: 1.55),
            ),
          ],
        );

      case _UpdateDialogStage.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _errorMessage.isEmpty ? '下载或安装过程出现异常' : _errorMessage,
              style: context.bodySmallStyle.copyWith(
                color: context.appColors.badge,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text('你可以重试应用内下载，或改用系统浏览器直接下载安装。', style: context.captionStyle),
          ],
        );
    }
  }

  List<Widget> _buildActions() {
    switch (_stage) {
      case _UpdateDialogStage.ready:
        return [
          TextButton(
            onPressed: () async {
              await widget.service.skip(widget.release);
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('跳过此版本'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: widget.canInAppInstall
                ? _startInAppUpdate
                : _openInBrowser,
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.primary,
            ),
            child: Text(widget.canInAppInstall ? '立即更新' : '前往下载'),
          ),
        ];

      case _UpdateDialogStage.downloading:
        return [
          TextButton(onPressed: _cancelDownload, child: const Text('取消下载')),
        ];

      case _UpdateDialogStage.awaitingPermission:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: _downloadedPath == null
                ? null
                : () => _triggerInstall(_downloadedPath!),
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.primary,
            ),
            child: const Text('继续安装'),
          ),
        ];

      case _UpdateDialogStage.downloaded:
        return [
          TextButton(onPressed: _openInBrowser, child: const Text('浏览器下载')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: _downloadedPath == null
                ? null
                : () => _triggerInstall(_downloadedPath!),
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.primary,
            ),
            child: const Text('重新安装'),
          ),
        ];

      case _UpdateDialogStage.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(onPressed: _openInBrowser, child: const Text('浏览器下载')),
          FilledButton(
            onPressed: _startInAppUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.primary,
            ),
            child: const Text('重试下载'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDownloading = _stage == _UpdateDialogStage.downloading;
    return PopScope(
      canPop: !isDownloading,
      child: AlertDialog(
        title: Text('发现新版本 ${widget.release.displayVersion}'),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }
}
