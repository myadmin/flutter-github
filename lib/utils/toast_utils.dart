import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 轻提示工具：自适应宽度的浮动 SnackBar，并对相同文案做短时去重
class ToastUtils {
  const ToastUtils._();

  static String? _lastMessage;
  static DateTime? _throttleUntil;

  static void showToast(
    BuildContext context,
    String? message, {
    int duration = 2,
  }) {
    final text = message ?? '操作成功';
    final now = DateTime.now();
    final until = _throttleUntil;
    if (_lastMessage == text && until != null && now.isBefore(until)) {
      return;
    }
    _lastMessage = text;
    _throttleUntil = now.add(Duration(seconds: duration));

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTextStyles.body.copyWith(color: Colors.white),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double textWidth = painter.width;
    painter.dispose();

    final double maxWidth = MediaQuery.sizeOf(context).width - 32;
    double width = textWidth + 56;
    if (width > maxWidth) {
      width = maxWidth;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.toast)),
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: duration),
        content: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
