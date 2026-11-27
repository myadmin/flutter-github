import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';
import 'package:gh_explorer/utils/external_link.dart';

/// GitHub 风格 Markdown 渲染组件（README / Issue 正文与评论共用）
class GhMarkdownView extends StatelessWidget {
  const GhMarkdownView({
    super.key,
    required this.data,
    this.owner = '',
    this.repo = '',
    this.branch = 'main',
  });

  final String data;
  final String owner;
  final String repo;
  final String branch;

  /// 解析同仓库相对链接或 GitHub 站内链接，可命中应用内页面时优先端内跳转
  bool _tryOpenInApp(BuildContext context, String rawHref) {
    final trimmed = rawHref.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return false;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && !uri.hasScheme && !trimmed.startsWith('//')) {
      if (owner.isNotEmpty && repo.isNotEmpty) {
        final cleanPath = trimmed
            .split('#')
            .first
            .split('?')
            .first
            .replaceFirst(RegExp(r'^\.?/'), '');
        if (cleanPath.isEmpty) return false;
        if (cleanPath.endsWith('/')) {
          Navigator.pushNamed(
            context,
            AppRoutes.repoFiles(
              owner,
              repo,
              ref: branch,
              path: cleanPath.substring(0, cleanPath.length - 1),
            ),
          );
          return true;
        }
        Navigator.pushNamed(
          context,
          AppRoutes.repoFileView(owner, repo, path: cleanPath, ref: branch),
        );
        return true;
      }
      return false;
    }

    if (uri == null || uri.host.toLowerCase() != 'github.com') return false;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return false;
    final targetOwner = segs[0];
    final targetRepo = segs[1];
    if (segs.length == 2) {
      Navigator.pushNamed(
        context,
        AppRoutes.repoDetail(targetOwner, targetRepo),
      );
      return true;
    }
    final section = segs[2].toLowerCase();
    if ((section == 'issues' || section == 'pull') && segs.length >= 4) {
      final n = int.tryParse(segs[3]);
      if (n != null && n > 0) {
        Navigator.pushNamed(
          context,
          AppRoutes.repoIssueDetail(targetOwner, targetRepo, n),
        );
        return true;
      }
    }
    if (section == 'commit' && segs.length >= 4) {
      Navigator.pushNamed(
        context,
        AppRoutes.repoCommitDetail(targetOwner, targetRepo, segs[3]),
      );
      return true;
    }
    if (section == 'releases') {
      Navigator.pushNamed(
        context,
        AppRoutes.repoReleases(targetOwner, targetRepo),
      );
      return true;
    }
    if (section == 'blob' && segs.length >= 5) {
      final ref = segs[3];
      final filePath = segs.sublist(4).join('/');
      Navigator.pushNamed(
        context,
        AppRoutes.repoFileView(
          targetOwner,
          targetRepo,
          path: filePath,
          ref: ref,
        ),
      );
      return true;
    }
    if (section == 'tree' && segs.length >= 4) {
      final ref = segs[3];
      final dirPath = segs.length >= 5 ? segs.sublist(4).join('/') : '';
      Navigator.pushNamed(
        context,
        AppRoutes.repoFiles(targetOwner, targetRepo, ref: ref, path: dirPath),
      );
      return true;
    }
    return false;
  }

  /// 点击 Markdown 超链接时优先应用内跳转，否则校验协议并唤起外部浏览器打开
  Future<void> _handleLinkTap(
    BuildContext context,
    String text,
    String? href,
    String title,
  ) async {
    if (href == null || href.trim().isEmpty) return;
    if (_tryOpenInApp(context, href)) return;
    // 仅放行 http/https/mailto，杜绝 javascript:、intent: 等协议注入
    final opened = await openExternalUrl(href);
    if (!opened && context.mounted) {
      ToastUtils.showToast(context, '无法打开链接');
    }
  }

  /// 全屏缩放预览 Markdown 中的图片
  void _showImageViewer(BuildContext context, String imageUrl, String? label) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogCtx) => Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  // 预览按屏幕宽度解码，避免长图按原始分辨率占用内存
                  cacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  errorBuilder: (ctx, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: '关闭预览',
                ),
              ),
            ),
            if (label != null && label.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 自定义图片构建器：补全仓库相对路径，并为不支持的 SVG 徽章提供文本胶囊降级
  Widget _buildImage(
    BuildContext context,
    Uri uri,
    String? title,
    String? alt,
  ) {
    final raw = uri.toString();
    final resolved = (owner.isNotEmpty && repo.isNotEmpty)
        ? resolveRepoAssetUrl(raw, owner: owner, repo: repo, branch: branch)
        : raw;

    if (isSvgImageUrl(resolved)) {
      return _buildSvgBadge(context, resolved, alt);
    }

    // README 内图片通常为整幅截图，按容器宽度解码即可，避免原图分辨率占满内存
    final double logicalWidth = MediaQuery.sizeOf(context).width
        .clamp(160.0, 1200.0);
    final int cacheWidth =
        (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final String? label = (alt != null && alt.trim().isNotEmpty)
        ? alt.trim()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: () => _showImageViewer(context, resolved, label),
        child: Image.network(
          resolved,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          semanticLabel: label,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _buildImageFallback(context, alt, loading: true);
          },
          errorBuilder: (context, error, stackTrace) {
            return _buildImageFallback(context, alt, loading: false);
          },
        ),
      ),
    );
  }

  /// 将 SVG 徽章 / shields.io 渲染为紧凑语义徽章胶囊（不吞外层超链接手势）
  Widget _buildSvgBadge(BuildContext context, String url, String? alt) {
    final c = context.appColors;
    var label = (alt ?? '').trim();
    if (label.isEmpty) {
      final shieldsMatch = RegExp(
        r'/badge/([^/?#]+)',
        caseSensitive: false,
      ).firstMatch(url);
      if (shieldsMatch != null) {
        final rawSeg = Uri.decodeComponent(shieldsMatch.group(1) ?? '');
        final parts = rawSeg.split('-');
        if (parts.length >= 2) {
          label = '${parts[0]} ${parts[1]}'.replaceAll('_', ' ').trim();
        }
      }
    }
    if (label.isEmpty) label = 'Badge';

    final lower = url.toLowerCase();
    final isSuccessTone =
        lower.contains('brightgreen') ||
        lower.contains('-green') ||
        lower.contains('passing');
    final isWarningTone =
        lower.contains('failing') ||
        lower.contains('-red') ||
        lower.contains('critical');
    final bgColor = isSuccessTone
        ? c.successSurface
        : isWarningTone
        ? c.badge.withValues(alpha: 0.12)
        : c.inputFill;
    final fgColor = isSuccessTone
        ? c.success
        : isWarningTone
        ? c.badge
        : c.textSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: fgColor.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.captionSmallStyle.copyWith(
                color: fgColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图片加载中 / 加载失败的占位，保持与正文一致的圆角与配色
  Widget _buildImageFallback(
    BuildContext context,
    String? alt, {
    required bool loading,
  }) {
    final text = loading
        ? (alt != null && alt.isNotEmpty ? '[图片加载中: $alt]' : '[图片加载中]')
        : (alt != null && alt.isNotEmpty ? '[图片: $alt]' : '[图片加载失败]');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.appColors.imagePlaceholder,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Text(text, style: context.captionStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (text, href, title) =>
          _handleLinkTap(context, text, href, title),
      imageBuilder: (uri, title, alt) => _buildImage(context, uri, title, alt),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: context.bodyStyle.copyWith(height: 1.55),
        h1: context.pageTitleStyle.copyWith(fontSize: 20, height: 1.4),
        h2: context.sectionTitleStyle.copyWith(fontSize: 18, height: 1.4),
        h3: context.sectionTitleStyle.copyWith(fontSize: 16, height: 1.4),
        a: TextStyle(color: context.appColors.link),
        code: context.monoStyle.copyWith(
          backgroundColor: context.appColors.codeBackground,
          fontSize: 12.5,
        ),
        codeblockDecoration: BoxDecoration(
          color: context.appColors.codeBackground,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: context.appColors.divider),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: context.appColors.divider, width: 3),
          ),
        ),
      ),
    );
  }
}
