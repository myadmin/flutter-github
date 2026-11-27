import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/utils/formatters.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 单条 Issue / PR 评论卡片（支持引用回复、复制、Emoji Reaction 及本人评论编辑删除）
class GhIssueCommentCard extends StatelessWidget {
  const GhIssueCommentCard({
    super.key,
    required this.comment,
    required this.owner,
    required this.repoName,
    required this.currentUserLogin,
    required this.onQuoteReply,
    required this.onReact,
    this.onEdit,
    this.onDelete,
  });

  final IssueComment comment;
  final String owner;
  final String repoName;
  final String currentUserLogin;
  final VoidCallback onQuoteReply;
  final ValueChanged<String> onReact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  bool get _isAuthor =>
      currentUserLogin.isNotEmpty &&
      currentUserLogin.toLowerCase() == comment.user.login.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const quickReactions = [
      ('+1', '👍'),
      ('heart', '❤️'),
      ('rocket', '🚀'),
      ('eyes', '👀'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: comment.user.login.isEmpty
                    ? null
                    : () => Navigator.pushNamed(
                        context,
                        AppRoutes.userDetail(comment.user.login),
                      ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppNetworkImage(
                      url: comment.user.avatarUrl,
                      width: 24,
                      height: 24,
                      decodeWidth: 24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(width: 8),
                    Text(comment.user.login, style: context.bodyStrongStyle),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  formatRelativeTime(comment.createdAt),
                  style: context.captionSmallStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '评论操作',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: colors.textSecondary,
                ),
                onSelected: (value) async {
                  switch (value) {
                    case 'quote':
                      onQuoteReply();
                    case 'copy':
                      await Clipboard.setData(
                        ClipboardData(text: comment.body),
                      );
                      if (context.mounted) {
                        ToastUtils.showToast(context, '已复制评论内容');
                      }
                    case 'edit':
                      onEdit?.call();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<String>(
                    value: 'quote',
                    child: Text('引用回复'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'copy',
                    child: Text('复制全文'),
                  ),
                  if (_isAuthor && onEdit != null)
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('编辑评论'),
                    ),
                  if (_isAuthor && onDelete != null)
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(
                        '删除评论',
                        style: TextStyle(color: colors.badge),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          GhMarkdownView(data: comment.body, owner: owner, repo: repoName),
          if (currentUserLogin.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (code, emoji) in quickReactions)
                  InkWell(
                    onTap: () => onReact(code),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.inputFill,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
