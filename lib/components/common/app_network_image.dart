import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 统一网络图片与头像组件，封装占位、失败兜底与按需解码尺寸
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholderIcon = Icons.person_outline,
    this.placeholderIconSize = 28,
    this.decodeWidth,
    this.borderRadius,
    this.semanticLabel,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final IconData placeholderIcon;
  final double placeholderIconSize;
  final double? decodeWidth;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final trimmed = url.trim();
    Widget child;
    if (trimmed.isEmpty) {
      child = _buildPlaceholder(context, showIcon: true);
    } else {
      final cacheWidth = decodeWidth == null
          ? null
          : (decodeWidth! * MediaQuery.devicePixelRatioOf(context)).round();
      child = Image.network(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        semanticLabel: semanticLabel,
        loadingBuilder: (context, imageChild, progress) {
          if (progress == null) return imageChild;
          return _buildPlaceholder(context, showIcon: false);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(context, showIcon: true);
        },
      );
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _buildPlaceholder(BuildContext context, {required bool showIcon}) {
    final placeholder = Container(
      width: width,
      height: height,
      color: context.appColors.imagePlaceholder,
      alignment: Alignment.center,
      child: showIcon
          ? Icon(
              placeholderIcon,
              size: placeholderIconSize,
              color: context.appColors.textSecondary,
            )
          : null,
    );
    final label = semanticLabel;
    if (label == null || label.isEmpty) return placeholder;
    return Semantics(image: true, label: label, child: placeholder);
  }
}
