import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 允许通过系统浏览器 / 邮件客户端打开的安全协议白名单。
///
/// 仓库 homepage、用户 blog、Markdown 链接等均由外部数据提供，
/// 若不加限制，`intent:` / `market:` / `tg:` 等自定义 scheme 可能被直接唤起。
const Set<String> kAllowedExternalSchemes = {'http', 'https', 'mailto'};

/// 判断 URL 是否允许交给系统打开（仅 http/https/mailto）
bool isAllowedExternalUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (!kAllowedExternalSchemes.contains(scheme)) return false;
  if (scheme == 'mailto') return true;
  return uri.host.isNotEmpty;
}

/// 统一的外部链接打开入口：校验协议白名单后交给系统浏览器。
///
/// 返回 `true` 表示系统已接管，`false` 表示链接非法或打开失败。
Future<bool> openExternalUrl(String url) async {
  if (!isAllowedExternalUrl(url)) {
    debugPrint('已拦截非白名单外链: $url');
    return false;
  }
  try {
    return await launchUrl(
      Uri.parse(url.trim()),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('打开外部链接失败: $e');
    return false;
  }
}
