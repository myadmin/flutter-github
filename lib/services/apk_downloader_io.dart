import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
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
      actualDigest = sha256.convert(await partFile.readAsBytes()).toString();
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
  final bytes = await File(path).readAsBytes();
  return sha256.convert(bytes).toString();
}
