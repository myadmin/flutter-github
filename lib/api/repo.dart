import 'package:gh_explorer/constants/index.dart';
import 'package:gh_explorer/models/parsers.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/dio_request.dart';
import 'package:gh_explorer/utils/paged_list.dart';

/// 拼接指定仓库的 REST API 基础路径
String _repoBase(String owner, String repo) =>
    '${HttpConstants.repos}/${Uri.encodeComponent(owner.trim())}/${Uri.encodeComponent(repo.trim())}';

/// 获取仓库详细信息
Future<RepoItem> getRepoDetailAPI(String owner, String repo) async {
  final data = await dioRequest.get(_repoBase(owner, repo));
  return RepoItem.fromJson(asMap(data));
}

/// 获取仓库 README 原文（无 README 时返回空字符串）
Future<String> getRepoReadmeRawAPI(
  String owner,
  String repo, {
  String ref = '',
}) async {
  try {
    return await dioRequest.getRaw(
      '${_repoBase(owner, repo)}/readme',
      params: ref.isEmpty ? null : {'ref': ref},
    );
  } on ApiException catch (e) {
    // 仓库未包含 README 时 GitHub 返回 404，按空内容降级处理
    if (e.code == '404') return '';
    rethrow;
  }
}

/// 获取仓库指定目录的内容列表（目录排在文件前，同类型按名称升序）
Future<List<RepoContentItem>> getRepoContentsAPI(
  String owner,
  String repo, {
  String path = '',
  String ref = '',
}) async {
  // 对路径按段编码，保留目录分隔符 `/`
  final cleanPath = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  final url = cleanPath.isEmpty
      ? '${_repoBase(owner, repo)}/contents'
      : '${_repoBase(owner, repo)}/contents/$cleanPath';
  final data = await dioRequest.get(
    url,
    params: ref.isEmpty ? null : {'ref': ref},
  );
  final items = asModelList(data, RepoContentItem.fromJson);
  items.sort((a, b) {
    if (a.isDir != b.isDir) {
      return a.isDir ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return items;
}

/// 获取仓库单个文件的原始文本内容
Future<String> getRepoFileRawAPI(
  String owner,
  String repo, {
  required String path,
  String ref = '',
}) async {
  final cleanPath = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
  return dioRequest.getRaw(
    '${_repoBase(owner, repo)}/contents/$cleanPath',
    params: ref.isEmpty ? null : {'ref': ref},
  );
}

/// 获取仓库分支列表
Future<List<RepoBranch>> getRepoBranchesAPI(
  String owner,
  String repo, {
  int page = 1,
  int perPage = 50,
}) async {
  final data = await dioRequest.get(
    '${_repoBase(owner, repo)}/branches',
    params: {'page': page, 'per_page': perPage},
  );
  return asModelList(data, RepoBranch.fromJson);
}

/// 分页获取仓库 Commit 历史
Future<PageResult<CommitItem>> getRepoCommitsAPI(
  String owner,
  String repo, {
  String branch = '',
  int page = 1,
  int perPage = GlobalConstants.defaultPageSize,
}) async {
  final params = <String, dynamic>{'page': page, 'per_page': perPage};
  if (branch.isNotEmpty) {
    params['sha'] = branch;
  }
  final res = await dioRequest.getPaged(
    '${_repoBase(owner, repo)}/commits',
    params: params,
    perPage: perPage,
  );
  return PageResult<CommitItem>(
    items: asModelList(res.data, CommitItem.fromJson),
    page: page,
    hasMore: res.hasNextPage,
  );
}
