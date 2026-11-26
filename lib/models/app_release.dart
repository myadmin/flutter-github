import 'package:gh_explorer/models/parsers.dart';

/// GitHub Release 中附带的单个产物文件
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  /// 产物文件名，例如 `app-arm64-v8a-release.apk`
  final String name;

  /// 可直接下载该文件的 URL
  final String downloadUrl;

  /// 文件字节大小
  final int size;

  /// 从 GitHub Release Asset JSON 解析对象
  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: asString(json['name']),
      downloadUrl: asString(json['browser_download_url']),
      size: asInt(json['size']),
    );
  }

  /// 是否为 Android APK 安装包
  bool get isAndroidApk => name.toLowerCase().endsWith('.apk');

  /// 格式化为人类可读的文件体积文案
  String get sizeText {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// 解析后的语义化版本与构建号（用于比较 `v1.0.0-build.4` 或 `1.0.0+1`）
class VersionSpec {
  const VersionSpec({required this.segments, required this.buildNumber});

  /// 数字主次修订号，例如 `[1, 0, 0]`
  final List<int> segments;

  /// 构建序号（`-build.4` 或 `+4` 中的数字，缺失时为 `0`）
  final int buildNumber;

  /// 归一化后的主版本号文本（如 `1.0.0`）
  String get normalizedVersion => segments.join('.');
}

/// 一次 GitHub Release（`/releases/latest` 接口模型）
class AppRelease {
  const AppRelease({
    required this.tagName,
    required this.versionName,
    required this.buildNumber,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
  });

  /// GitHub 原始 Tag 名称，例如 `v1.0.0-build.4` 或 `v1.0.1`
  final String tagName;

  /// 归一化后的版本号，例如 `1.0.0`
  final String versionName;

  /// 解析自 Tag 的构建号（无 `-build.<n>` 时为 `0`）
  final int buildNumber;

  /// Release 更新日志正文（Markdown）
  final String notes;

  /// Release 网页端详情地址
  final String htmlUrl;

  /// 附带构建产物列表
  final List<ReleaseAsset> assets;

  /// 从 GitHub Release JSON 解析对象
  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = asString(json['tag_name']);
    final spec = parseVersionSpec(tag);
    return AppRelease(
      tagName: tag,
      versionName: spec.normalizedVersion,
      buildNumber: spec.buildNumber,
      notes: asString(json['body']),
      htmlUrl: asString(json['html_url']),
      assets: asList(json['assets'], ReleaseAsset.fromJson),
    );
  }

  /// 用于界面标题展示的版本文案
  String get displayVersion {
    if (buildNumber > 0) {
      return 'v$versionName (build $buildNumber)';
    }
    return versionName.isNotEmpty ? 'v$versionName' : tagName;
  }

  /// 提取适合在应用内弹窗展示的更新说明（优先抽取 `## 本次更新` 段落，剔除安装包下载表格与冗余尾部指引）
  String get updateSummaryNotes {
    final trimmed = notes.trim();
    if (trimmed.isEmpty) return '';

    final lines = trimmed.replaceAll('\r\n', '\n').split('\n');
    final extracted = <String>[];
    var inUpdateSection = false;
    var foundUpdateHeading = false;

    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('## ')) {
        final heading = t.substring(3).trim();
        if (heading.startsWith('本次更新') ||
            heading.startsWith('更新说明') ||
            heading.startsWith('更新内容') ||
            heading.toLowerCase().startsWith("what's changed")) {
          foundUpdateHeading = true;
          inUpdateSection = true;
          continue;
        }
        if (inUpdateSection) {
          break;
        }
      }
      if (inUpdateSection) {
        extracted.add(line);
      }
    }

    if (foundUpdateHeading) {
      return extracted.join('\n').trim();
    }

    // 若 Release 正文未分节，过滤掉 CI 附带的「Android 安装包 / 安装说明」固定章节
    final fallback = <String>[];
    var skipBoilerplate = false;
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('## ')) {
        final heading = t.substring(3).trim();
        skipBoilerplate =
            heading.startsWith('Android 安装包') || heading.startsWith('安装说明');
        if (skipBoilerplate) continue;
      }
      if (!skipBoilerplate) {
        fallback.add(line);
      }
    }
    return fallback.join('\n').trim();
  }

  /// 根据当前设备支持的 ABI 优先级挑选最匹配的 `.apk` 产物
  ReleaseAsset? pickAndroidApkAsset({
    List<String> supportedAbis = const ['arm64-v8a', 'armeabi-v7a', 'x86_64'],
  }) {
    final apks = assets.where((asset) => asset.isAndroidApk).toList();
    if (apks.isEmpty) return null;

    for (final abi in supportedAbis) {
      for (final apk in apks) {
        if (apk.name.contains(abi)) {
          return apk;
        }
      }
    }
    for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
      for (final apk in apks) {
        if (apk.name.contains(abi)) {
          return apk;
        }
      }
    }
    return apks.first;
  }
}

/// 去掉 `v` 前缀及构建/预发布后缀后的基础版本号
String normalizeVersion(String raw) {
  return parseVersionSpec(raw).normalizedVersion;
}

/// 将任意版本/Tag 字符串（`v1.0.0-build.4`、`1.0.0+1`、`v1.2.3`）解析为版本结构
VersionSpec parseVersionSpec(String raw) {
  var value = raw.trim();
  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1).trim();
  }
  if (value.isEmpty) {
    return const VersionSpec(segments: [0], buildNumber: 0);
  }

  var buildNumber = 0;
  final plusIdx = value.indexOf('+');
  if (plusIdx >= 0) {
    final plusTail = value.substring(plusIdx + 1).trim();
    buildNumber = int.tryParse(plusTail) ?? 0;
    value = value.substring(0, plusIdx).trim();
  }

  final buildMatch = RegExp(r'-build\.(\d+)$').firstMatch(value);
  if (buildMatch != null) {
    buildNumber = int.tryParse(buildMatch.group(1) ?? '') ?? buildNumber;
    value = value.substring(0, buildMatch.start).trim();
  } else {
    final dashIdx = value.indexOf('-');
    if (dashIdx >= 0) {
      value = value.substring(0, dashIdx).trim();
    }
  }

  final rawSegments = value.split('.').map((s) {
    final match = RegExp(r'^\d+').firstMatch(s.trim());
    return match == null ? 0 : (int.tryParse(match.group(0)!) ?? 0);
  }).toList();

  return VersionSpec(
    segments: rawSegments.isEmpty ? const [0] : rawSegments,
    buildNumber: buildNumber,
  );
}

/// 比较远端 Release 与本地版本：远端更新返回正数，一致返回 0，更旧返回负数
int compareReleaseVersions(String remoteRaw, String localRaw) {
  final remote = parseVersionSpec(remoteRaw);
  final local = parseVersionSpec(localRaw);

  final length = remote.segments.length > local.segments.length
      ? remote.segments.length
      : local.segments.length;
  for (var i = 0; i < length; i++) {
    final l = i < remote.segments.length ? remote.segments[i] : 0;
    final r = i < local.segments.length ? local.segments[i] : 0;
    if (l != r) {
      return l > r ? 1 : -1;
    }
  }

  // 主版本相同时仅当远端显式携带 buildNumber（如 v1.0.0-build.4）才继续比较构建号，
  // 避免正式纯语义化标签（v1.0.1）与本地 pubspec 的 +1 产生死循环弹窗。
  if (remote.buildNumber > 0) {
    if (remote.buildNumber != local.buildNumber) {
      return remote.buildNumber > local.buildNumber ? 1 : -1;
    }
  }
  return 0;
}
