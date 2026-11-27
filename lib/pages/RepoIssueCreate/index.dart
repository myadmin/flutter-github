import 'package:flutter/material.dart';
import 'package:gh_explorer/api/issue.dart';
import 'package:gh_explorer/components/common/hm_bottom_bar.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/models/issue.dart';
import 'package:gh_explorer/utils/api_exception.dart';
import 'package:gh_explorer/utils/toast_utils.dart';

/// 新建 Issue 表单页（支持填写标题、Markdown 描述与选择仓库标签）
class RepoIssueCreatePage extends StatefulWidget {
  const RepoIssueCreatePage({
    super.key,
    required this.owner,
    required this.repoName,
  });

  final String owner;
  final String repoName;

  @override
  State<RepoIssueCreatePage> createState() => _RepoIssueCreatePageState();
}

class _RepoIssueCreatePageState extends State<RepoIssueCreatePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  List<IssueLabel> _availableLabels = const [];
  final Set<String> _selectedLabels = <String>{};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadLabels() async {
    try {
      final labels = await getRepoLabelsAPI(widget.owner, widget.repoName);
      if (!mounted) return;
      setState(() => _availableLabels = labels);
    } catch (_) {
      // 无 labels 或无权限时静默忽略
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _submitting = true);
    try {
      final created = await createRepoIssueAPI(
        widget.owner,
        widget.repoName,
        title: _titleController.text,
        body: _bodyController.text,
        labels: _selectedLabels.toList(),
      );
      if (!mounted) return;
      ToastUtils.showToast(context, 'Issue #${created.number} 已提交');
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ToastUtils.showToast(
        context,
        resolveErrorMessage(e, fallback: '创建 Issue 失败'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text('新建 Issue'),
        centerTitle: true,
        backgroundColor: colors.cardBackground,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: HmBottomBar.maxContentWidth,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.6),
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.owner}/${widget.repoName}',
                      style: context.captionStyle.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('标题', style: context.bodyStrongStyle),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '请输入 Issue 标题'
                          : null,
                      decoration: InputDecoration(
                        hintText: '简明扼要描述问题或建议...',
                        hintStyle: context.captionStyle,
                        filled: true,
                        fillColor: colors.inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('详细描述（支持 Markdown）', style: context.bodyStrongStyle),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bodyController,
                      minLines: 6,
                      maxLines: 12,
                      decoration: InputDecoration(
                        hintText: '补充复现步骤、期望结果或上下文...',
                        hintStyle: context.captionStyle,
                        filled: true,
                        fillColor: colors.inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_availableLabels.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('标签（可选）', style: context.bodyStrongStyle),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final label in _availableLabels)
                            FilterChip(
                              label: Text(label.name),
                              selected: _selectedLabels.contains(label.name),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedLabels.add(label.name);
                                  } else {
                                    _selectedLabels.remove(label.name);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.brandButtonBg,
                          foregroundColor: colors.brandButtonFg,
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        child: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.brandButtonFg,
                                ),
                              )
                            : const Text('提交 Issue'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
