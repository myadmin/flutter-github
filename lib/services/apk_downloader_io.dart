import 'dart:io';

import 'package:dio/dio.dart';

/// 使用独立纯净 Dio 下载 APK 到目标目录，避免将 GitHub API Token 转发到 CDN 跳转地址
Future<String> downloadApkToFile({
  required String url,
  required String directoryPath,
  required String fileName,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
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
