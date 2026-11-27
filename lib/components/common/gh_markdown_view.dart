import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
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

  /// 点击 Markdown 超链接时校验协议并唤起外部浏览器打开
  Future<void> _handleLinkTap(
    BuildContext context,
    String text,
    String? href,
    String title,
  ) async {
    if (href == null || href.trim().isEmpty) return;
    // 仅放行 http/https/mailto，杜绝 javascript:、intent: 等协议注入
    final opened = await openExternalUrl(href);
    if (!opened && context.mounted) {
      ToastUtils.showToast(context, '无法打开链接');
    }
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

    final lower = resolved.toLowerCase();
    // Image.network 不支持 SVG（如 shields.io 徽章），降级为紧凑文本胶囊
    if (lower.endsWith('.svg') ||
        lower.contains('.svg?') ||
        lower.contains('img.shields.io') ||
        lower.contains('shields.io/badge')) {
      final badgeLabel = (alt != null && alt.trim().isNotEmpty)
          ? alt.trim()
          : 'Badge';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.appColors.inputFill,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: context.appColors.divider),
        ),
        child: Text(badgeLabel, style: context.captionSmallStyle),
      );
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
      child: Image.network(
        resolved,
        cacheWidth: cacheWidth,
        semanticLabel: label,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _buildImageFallback(context, alt, loading: true);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildImageFallback(context, alt, loading: false);
        },
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
