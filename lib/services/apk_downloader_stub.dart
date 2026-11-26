import 'package:dio/dio.dart';

/// 非 IO 平台（Web）的 APK 下载占位实现
Future<String> downloadApkToFile({
  required String url,
  required String directoryPath,
  required String fileName,
  String expectedSha256 = '',
  int expectedSize = 0,
  void Function(int received, int total)? onProgress,
  CancelToken? cancelToken,
}) async {
  throw UnsupportedError('当前平台不支持直接下载安装 APK');
}
