import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/app_release.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/utils/dio_request.dart';

/// 拉取本仓库在 GitHub Releases 上发布的最新版本信息
Future<AppRelease?> fetchLatestReleaseAPI() async {
  final data = await dioRequest.get(
    HttpConstants.latestRelease,
    skipAuthRedirect: true,
  );
  final map = asMap(data);
  if (map.isEmpty) return null;
  final release = AppRelease.fromJson(map);
  if (release.tagName.isEmpty) return null;
  return release;
}
