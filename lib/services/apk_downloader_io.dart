import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:gh_explorer/services/apk_verifier.dart';

/// 使用独立纯净 Dio 下载 APK 到目标目录，避免将 GitHub API Token 转发到 CDN 跳转地址。
///
/// 下载完成后会校验 HTTPS、文件大小与 SHA-256 摘要（若 Release 产物记录了摘要），
/// 校验失败会删除临时文件并抛错，绝不把未校验的安装包交给系统安装器。
Future<String> downloadApkToFile({
  required String url,
  required String directoryPath,
  required String fileName,
  String expectedSha256 = '',
  int expectedSize = 0,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw ArgumentError.value(url, 'url', '安装包下载地址必须为 HTTPS');
  }

  final dir = Directory(directoryPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final targetFile = File('${dir.path}${Platform.pathSeparator}$safeName');
  final partFile = File('${targetFile.path}.part');

  if (await partFile.exists()) {
    await partFile.delete();
  }

  // 下载客户端独立于 dioRequest，防止 302 跳转到 GitHub 对象存储时携带多余头导致 400
  final client = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
      followRedirects: true,
      maxRedirects: 8,
    ),
  );

  try {
    await client.download(
      url,
      partFile.path,
      cancelToken: cancelToken,
      deleteOnError: true,
      onReceiveProgress: onProgress,
    );
    if (!await partFile.exists() || await partFile.length() <= 0) {
      throw const FileSystemException('下载完成但安装包为空');
    }

    final downloadedSize = await partFile.length();
    var actualDigest = '';
    if (expectedSha256.isNotEmpty) {
      // 安装包约 20 MB，改为分块流式计算摘要，避免一次性把整包读进内存
      actualDigest = await _sha256OfFileStreaming(partFile);
    }
    verifyDownloadedApk(
      actualSize: downloadedSize,
      actualSha256: actualDigest,
      expectedSize: expectedSize,
      expectedSha256: expectedSha256,
    );

    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await partFile.rename(targetFile.path);
    // 顺手清掉历史版本遗留的安装包，避免缓存目录随版本升级无限膨胀
    await pruneStaleApks(dir.path, keepFileName: safeName);
    return targetFile.path;
  } catch (e) {
    if (await partFile.exists()) {
      await partFile.delete();
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// 计算本地文件的 SHA-256 十六进制摘要（供测试与手动校验使用）
Future<String> sha256OfFile(String path) async {
  return _sha256OfFileStreaming(File(path));
}

/// 清理同一目录下已过期的安装包（保留 [keepFileName]，连同其 `.part` 残留）。
///
/// 安装包文件名带版本号，跨版本下载时旧包不会被同名覆盖，若不清理，
/// 每升级一次就会在缓存目录永久留下约 20 MB 的旧安装包。
/// 返回被删除的文件数量。
Future<int> pruneStaleApks(
  String directoryPath, {
  required String keepFileName,
}) async {
  final dir = Directory(directoryPath);
  if (!await dir.exists()) return 0;
  final keep = keepFileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final apkPattern = RegExp(r'^gh_explorer_.*\.apk(\.part)?$');
  var removed = 0;
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name == keep || name == '$keep.part') continue;
      if (!apkPattern.hasMatch(name)) continue;
      try {
        await entity.delete();
        removed++;
      } on FileSystemException catch (e) {
        debugPrint('[ApkDownloader] 清理旧安装包失败：$name ${e.message}');
      }
    }
  } on FileSystemException catch (e) {
    debugPrint('[ApkDownloader] 列举缓存目录失败：${e.message}');
  }
  return removed;
}

/// 以固定大小的分块流式读取文件并计算 SHA-256，避免大文件整包驻留内存
Future<String> _sha256OfFileStreaming(File file) async {
  final output = _DigestSink();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return output.value.toString();
}

/// 承接 `sha256.startChunkedConversion` 输出的极简 `Sink<Digest>`
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest ?? Digest(const <int>[]);

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}
}
