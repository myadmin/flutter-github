import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/repo.dart';

/// Unified Diff 文本行语义类别
enum DiffLineKind { hunk, added, removed, context }

/// 单个文件变更卡片（展示变更状态、增删行数、可选跳转源文件按钮及折叠/展开的 Unified Diff）
class GhDiffFileCard extends StatefulWidget {
  const GhDiffFileCard({
    super.key,
    required this.file,
    this.initiallyExpanded = true,
    this.onViewFile,
  });

  final CommitFileChange file;
  final bool initiallyExpanded;
  final VoidCallback? onViewFile;

  @override
  State<GhDiffFileCard> createState() => _GhDiffFileCardState();
}

class _GhDiffFileCardState extends State<GhDiffFileCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant GhDiffFileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  (Color, Color) _statusColors(BuildContext context, String status) {
    final c = context.appColors;
    switch (status.toLowerCase()) {
      case 'added':
        return (c.success, c.successSurface);
      case 'removed':
        return (c.badge, c.badge.withValues(alpha: 0.12));
      case 'renamed':
        return (c.merged, c.mergedSurface);
      default:
        return (c.primary, c.primarySurface);
    }
  }

  DiffLineKind _classifyLine(String line) {
    if (line.startsWith('@@')) return DiffLineKind.hunk;
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return DiffLineKind.added;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return DiffLineKind.removed;
    }
    return DiffLineKind.context;
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final colors = context.appColors;
    final (badgeFg, badgeBg) = _statusColors(context, file.status);

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.divider.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              color: colors.inputFill.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Text(
                      file.statusBadge,
                      style: context.labelStyle.copyWith(
                        color: badgeFg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.displayPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.monoSmallStyle.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (file.additions > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '+${file.additions}',
                        style: context.captionSmallStyle.copyWith(
                          color: colors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (file.deletions > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '-${file.deletions}',
                        style: context.captionSmallStyle.copyWith(
                          color: colors.badge,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (widget.onViewFile != null && file.status != 'removed')
                    IconButton(
                      onPressed: widget.onViewFile,
                      icon: Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      tooltip: '查看完整文件',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _buildDiffBody(context, file.patch),
        ],
      ),
    );
  }

  Widget _buildDiffBody(BuildContext context, String patch) {
    final colors = context.appColors;
    if (patch.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text('二进制文件或变更过大，暂未返回文本 Diff', style: context.captionStyle),
      );
    }
    final lines = patch.replaceAll('\r\n', '\n').split('\n');
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width - 48,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines) _buildDiffLine(context, line),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiffLine(BuildContext context, String line) {
    final colors = context.appColors;
    final kind = _classifyLine(line);
    Color? bgColor;
    Color textColor = colors.textPrimary;
    FontWeight fontWeight = FontWeight.w400;

    switch (kind) {
      case DiffLineKind.hunk:
        bgColor = colors.primarySurface.withValues(
          alpha: colors.isDark ? 0.55 : 0.7,
        );
        textColor = colors.primary;
        fontWeight = FontWeight.w600;
      case DiffLineKind.added:
        bgColor = colors.isDark
            ? colors.success.withValues(alpha: 0.16)
            : colors.successSurface;
        textColor = colors.isDark ? colors.success : const Color(0xFF116329);
      case DiffLineKind.removed:
        bgColor = colors.badge.withValues(alpha: colors.isDark ? 0.18 : 0.1);
        textColor = colors.badge;
      case DiffLineKind.context:
        bgColor = null;
        textColor = colors.textPrimary;
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        line.isEmpty ? ' ' : line,
        softWrap: false,
        style: context.monoSmallStyle.copyWith(
          color: textColor,
          fontWeight: fontWeight,
          height: 1.45,
        ),
      ),
    );
  }
}
