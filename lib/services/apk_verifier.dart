import 'dart:io';

/// 安装包完整性校验（纯函数，便于在任意平台单测，不依赖真实网络下载）
///
/// 依次校验：非空文件 → 体积与 Release 记录一致 → SHA-256 摘要一致。
/// 任一环节不通过都会抛 [FileSystemException]，调用方需删除临时文件。
void verifyDownloadedApk({
  required int actualSize,
  String actualSha256 = '',
  int expectedSize = 0,
  String expectedSha256 = '',
}) {
  if (actualSize <= 0) {
    throw const FileSystemException('下载完成但安装包为空');
  }
  if (expectedSize > 0 && actualSize != expectedSize) {
    throw FileSystemException(
      '安装包大小与 Release 记录不一致（$actualSize / $expectedSize 字节）',
    );
  }
  if (expectedSha256.isNotEmpty &&
      actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
    throw const FileSystemException('安装包校验失败：SHA-256 摘要不匹配');
  }
}
