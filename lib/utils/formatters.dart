import 'dart:convert';

/// 将数字格式化为紧凑显示（例如 `1234 -> 1.2k`、`1500000 -> 1.5m`）
String formatCompactNumber(int value) {
  if (value < 0) return '0';
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final double k = value / 1000;
    return k >= 100 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
  }
  final double m = value / 1000000;
  return '${m.toStringAsFixed(1)}m';
}

/// 将 [DateTime] 格式化为中文相对时间（如「刚刚」「3 小时前」「2 天前」）
String formatRelativeTime(DateTime? dateTime, {DateTime? now}) {
  if (dateTime == null) return '';
  final current = now ?? DateTime.now();
  final diff = current.difference(dateTime.toLocal());
  if (diff.isNegative || diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} 天前';
  }
  final local = dateTime.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  if (local.year == current.year) {
    return '$month-$day';
  }
  return '${local.year}-$month-$day';
}

/// 解码 GitHub API 返回的带换行的 Base64 文本
String decodeBase64Text(String encoded) {
  if (encoded.isEmpty) return '';
  final normalized = encoded.replaceAll(RegExp(r'\s+'), '');
  try {
    final bytes = base64Decode(normalized);
    return utf8.decode(bytes, allowMalformed: true);
  } on FormatException {
    return encoded;
  }
}

/// 从 GitHub `Link` 响应头中判断是否还有下一页（`rel="next"`）
bool parseHasNextPage(String? linkHeader) {
  if (linkHeader == null || linkHeader.isEmpty) {
    return false;
  }
  return RegExp(r'rel="next"').hasMatch(linkHeader);
}

/// 将 README 中的相对图片路径修正为 GitHub Raw 绝对地址
String resolveRepoAssetUrl(
  String url, {
  required String owner,
  required String repo,
  required String branch,
}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('data:')) {
    return trimmed;
  }
  var clean = trimmed;
  if (clean.startsWith('./')) {
    clean = clean.substring(2);
  } else if (clean.startsWith('/')) {
    clean = clean.substring(1);
  }
  final safeBranch = branch.isEmpty ? 'HEAD' : Uri.encodeComponent(branch);
  return 'https://raw.githubusercontent.com/$owner/$repo/$safeBranch/$clean';
}
