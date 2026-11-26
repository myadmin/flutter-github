import 'package:flutter/material.dart';
import 'package:gh_explorer/api/repo.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/components/common/hm_empty_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/repo.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/utils/api_exception.dart';

/// 仓库代码目录浏览页（支持分支切换与多层目录深链）
class RepoFilesPage extends StatefulWidget {
  const RepoFilesPage({
    super.key,
    required this.owner,
    required this.repoName,
    this.branch = '',
    this.path = '',
  });

  final String owner;
  final String repoName;
  final String branch;
  final String path;

  @override
  State<RepoFilesPage> createState() => _RepoFilesPageState();
}

class _RepoFilesPageState extends State<RepoFilesPage> {
  List<RepoContentItem> _items = const [];
  List<RepoBranch> _branches = const [];
  late String _currentBranch;
  int _loadSeq = 0;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _currentBranch = widget.branch;
    _load();
  }

  /// 并发拉取当前目录文件列表与仓库分支列表
  Future<void> _load() async {
    if (widget.owner.isEmpty || widget.repoName.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '仓库信息缺失';
      });
      return;
    }
    // 请求序号：快速切换分支时，只有最后一次请求的结果可以写回界面
    final seq = ++_loadSeq;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final contentsFuture = getRepoContentsAPI(
        widget.owner,
        widget.repoName,
        path: widget.path,
        ref: _currentBranch,
      );
      // 首次进入时加载分支列表，切换分支后复用已拉取的分支选项
      final branchesFuture = _branches.isEmpty
          ? getAllRepoBranchesAPI(
              widget.owner,
              widget.repoName,
            ).catchError((Object _) => const <RepoBranch>[])
          : Future<List<RepoBranch>>.value(_branches);

      final (items, branches) = await (contentsFuture, branchesFuture).wait;
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _items = items;
        _branches = branches;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _isLoading = false;
        _errorMessage = resolveErrorMessage(e, fallback: '加载目录内容失败');
      });
    }
  }

  /// 切换目标分支并重新加载当前目录
  void _switchBranch(String branch) {
    if (branch == _currentBranch) return;
    setState(() => _currentBranch = branch);
    _load();
  }

  /// 将文件字节数格式化为易读单位（B / KB / MB）
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.path.isEmpty ? '${widget.repoName} 代码' : widget.path;
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_branches.isNotEmpty)
            PopupMenuButton<String>(
              initialValue: _currentBranch,
              onSelected: _switchBranch,
              tooltip: '切换分支',
              itemBuilder: (context) => [
                for (final branch in _branches)
                  PopupMenuItem<String>(
                    value: branch.name,
                    child: Text(branch.name),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.alt_route, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _currentBranch.isEmpty ? '默认分支' : _currentBranch,
                      style: context.bodySmallStyle,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return AppErrorView(message: _errorMessage, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const HmEmptyView(icon: Icons.folder_open, title: '目录为空');
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: HmBottomBar.maxContentWidth,
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = _items[index];
              return Material(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.small),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    side: BorderSide(
                      color: context.appColors.divider.withValues(alpha: 0.5),
                    ),
                  ),
                  leading: Icon(
                    item.isDir
                        ? Icons.folder
                        : Icons.insert_drive_file_outlined,
                    color: item.isDir
                        ? context.appColors.primary
                        : context.appColors.textSecondary,
                  ),
                  title: Text(item.name, style: context.bodyStyle),
                  trailing: item.isDir
                      ? Icon(
                          Icons.chevron_right,
                          color: context.appColors.textSecondary,
                        )
                      : Text(
                          _formatSize(item.size),
                          style: context.captionSmallStyle,
                        ),
                  onTap: () {
                    if (item.isDir) {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.repoFiles(
                          widget.owner,
                          widget.repoName,
                          ref: _currentBranch,
                          path: item.path,
                        ),
                      );
                    } else {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.repoFileView(
                          widget.owner,
                          widget.repoName,
                          path: item.path,
                          ref: _currentBranch,
                        ),
                      );
                    }
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
