/// APK 文件下载工具跨平台门面（Web 端走空实现以隔离 `dart:io`）
library;

export 'apk_downloader_stub.dart' if (dart.library.io) 'apk_downloader_io.dart';
