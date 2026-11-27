import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gh_explorer/api/repo.dart';
import 'package:gh_explorer/components/Repo/gh_code_editor_view.dart';
import 'package:gh_explorer/components/common/app_error_view.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/external_link.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 仓库单文件查看页（支持编辑器级源码阅读、Markdown 预览/源码切换及图片缩放）
class RepoFileViewPage extends StatefulWidget {
  const RepoFileViewPage({
    super.key,
    required this.owner,
    required this.repoName,
    required this.path,
    this.branch = '',
  });

  final String owner;
  final String repoName;
  final String path;
  final String branch;

  @override
  State<RepoFileViewPage> createState() => _RepoFileViewPageState();
}

class _RepoFileViewPageState extends State<RepoFileViewPage> {
  String _content = '';
  bool _isLoading = true;
  String _errorMessage = '';
  bool _showMarkdownSource = false;
  int _loadSeq = 0;
  CancelToken? _loadToken;

  /// 根据扩展名判断是否为图片资源（直接走 Raw 地址渲染）
  bool get _isImageFile {
    final lower = widget.path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  /// 判断是否为 Markdown 文档（走富文本渲染而非纯文本代码视图）
  bool get _isMarkdownFile {
    final lower = widget.path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  String get _fileName {
    final parts = widget.path.split('/');
    return parts.isEmpty ? widget.path : parts.last;
  }

  @override
  void initState() {
    super.initState();
    if (_isImageFile) {
      _isLoading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _loadToken?.cancel();
    super.dispose();
  }

  /// 拉取文件原始文本内容
  Future<void> _load() async {
    if (widget.owner.isEmpty ||
        widget.repoName.isEmpty ||
        widget.path.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '文件路径缺失';
      });
      return;
    }
    final seq = ++_loadSeq;
    _loadToken?.cancel();
    final token = CancelToken();
    _loadToken = token;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final raw = await getRepoFileRawAPI(
        widget.owner,
        widget.repoName,
        path: widget.path,
        ref: widget.branch,
        cancelToken: token,
      );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _content = raw;
        _isLoading = false;
      });
    } catch (e) {
      if (e is RequestCancelledException || !mounted || seq != _loadSeq) return;
      setState(() {
        _isLoading = false;
        _errorMessage = resolveErrorMessage(e, fallback: '文件内容加载失败');
      });
    }
  }

  /// 将文件全文复制到系统剪贴板
  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (!mounted) return;
    ToastUtils.showToast(context, '已复制文件内容');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(_fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        backgroundColor: context.appColors.pageBackground,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        actions: [
          if (_isMarkdownFile && _content.isNotEmpty)
            IconButton(
              onPressed: () =>
                  setState(() => _showMarkdownSource = !_showMarkdownSource),
              icon: Icon(
                _showMarkdownSource ? Icons.article_outlined : Icons.code,
                size: 19,
              ),
              tooltip: _showMarkdownSource ? '切换预览' : '查看源码',
            ),
          if (!_isImageFile && _content.isNotEmpty)
            IconButton(
              onPressed: _copyCode,
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '复制代码',
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
      final canOpenWeb =
          widget.owner.isNotEmpty &&
          widget.repoName.isNotEmpty &&
          widget.path.isNotEmpty;
      final branch = widget.branch.isEmpty ? 'HEAD' : widget.branch;
      final encodedPath = widget.path
          .split('/')
          .where((s) => s.isNotEmpty)
          .map(Uri.encodeComponent)
          .join('/');
      final blobUrl =
          'https://github.com/${Uri.encodeComponent(widget.owner)}/${Uri.encodeComponent(widget.repoName)}/blob/${Uri.encodeComponent(branch)}/$encodedPath';
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppErrorView(message: _errorMessage, onRetry: _load),
          if (canOpenWeb) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => openExternalUrl(blobUrl),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('在 GitHub 网页端查看原文件'),
            ),
          ],
        ],
      );
    }
    if (_isImageFile) {
      final imageUrl = resolveRepoAssetUrl(
        widget.path,
        owner: widget.owner,
        repo: widget.repoName,
        branch: widget.branch.isEmpty ? 'HEAD' : widget.branch,
      );
      return Center(
        child: InteractiveViewer(
          child: AppNetworkImage(
            url: imageUrl,
            fit: BoxFit.contain,
            decodeWidth: MediaQuery.sizeOf(context).width,
          ),
        ),
      );
    }
    if (_isMarkdownFile && !_showMarkdownSource) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: GhMarkdownView(
                data: _content,
                owner: widget.owner,
                repo: widget.repoName,
                branch: widget.branch,
              ),
            ),
          ),
        ),
      );
    }

    return GhCodeEditorView(content: _content, filePath: widget.path);
  }
}
