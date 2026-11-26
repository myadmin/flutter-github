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
    this.placeholderIconSize = 28,
    this.decodeWidth,
    this.borderRadius,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double placeholderIconSize;
  final double? decodeWidth;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final trimmed = url.trim();
    Widget child;
    if (trimmed.isEmpty) {
      child = _buildPlaceholder(showIcon: true);
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
        loadingBuilder: (context, imageChild, progress) {
          if (progress == null) return imageChild;
          return _buildPlaceholder(showIcon: false);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder(showIcon: true);
        },
      );
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _buildPlaceholder({required bool showIcon}) {
    return Container(
      width: width,
      height: height,
      color: AppColors.imagePlaceholder,
      alignment: Alignment.center,
      child: showIcon
          ? Icon(
              Icons.person_outline,
              size: placeholderIconSize,
              color: AppColors.textSecondary,
            )
          : null,
    );
  }
}
