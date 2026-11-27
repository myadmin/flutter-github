import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_text_styles.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/utils/code_syntax_highlighter.dart';

/// 代码编辑器视图组件
///
/// 还原现代代码编辑器的核心阅读体验：
/// - 独立行号栏（非换行横滑时左侧固定贴边，避免行号跟随横向滚走）
/// - 多语言词法语法高亮与跨行注释识别
/// - GitHub Dark / Light 一键切换主题
/// - 自动换行（Soft Wrap）与横滑模式切换（带可见水平滚动条）
/// - 字号调节（`A-` / `A+`）、点击高亮当前行、可选中复制、文件内查找与上/下一处跳转
class GhCodeEditorView extends StatefulWidget {
  const GhCodeEditorView({
    super.key,
    required this.content,
    required this.filePath,
    this.initialDarkTheme = true,
    this.initialWordWrap = true,
  });

  /// 文件完整文本内容
  final String content;

  /// 文件路径（用于自动识别语言与标题提示）
  final String filePath;

  /// 默认是否使用深色编辑器主题
  final bool initialDarkTheme;

  /// 默认是否开启自动换行，适配移动端窄屏阅读长代码行
  final bool initialWordWrap;

  @override
  State<GhCodeEditorView> createState() => _GhCodeEditorViewState();
}

class _GhCodeEditorViewState extends State<GhCodeEditorView> {
  static const double _minFontSize = 10;
  static const double _maxFontSize = 20;
  static const double _defaultFontSize = 13;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _gutterVerticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  late bool _isDark;
  late bool _wordWrap;
  double _fontSize = _defaultFontSize;
  int? _activeLineIndex;

  bool _showSearchBar = false;
  List<CodeSearchMatch> _matches = const [];
  Map<int, int> _lineFirstMatchIndex = const {};
  Map<int, List<CodeSearchMatch>> _matchesByLine = const {};
  int _activeMatchIndex = 0;

  late List<String> _lines;
  late CodeLanguageInfo _language;
  late List<bool> _blockCommentMask;
  late int _maxLineUnits;

  @override
  void initState() {
    super.initState();
    _isDark = widget.initialDarkTheme;
    _wordWrap = widget.initialWordWrap;
    _verticalController.addListener(_syncGutterScroll);
    _prepareDocument();
  }

  @override
  void didUpdateWidget(covariant GhCodeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.filePath != widget.filePath) {
      _prepareDocument();
      _rebuildSearchMatches(_searchController.text, jumpToFirst: false);
    }
  }

  @override
  void dispose() {
    _verticalController.removeListener(_syncGutterScroll);
    _verticalController.dispose();
    _gutterVerticalController.dispose();
    _horizontalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _prepareDocument() {
    // 统一换行符避免 CRLF 行尾携带多余 `\r` 影响计算与搜索偏移
    final normalized = widget.content.replaceAll('\r\n', '\n');
    _lines = normalized.split('\n');
    _language = CodeSyntaxHighlighter.detectLanguage(widget.filePath);
    _blockCommentMask = CodeSyntaxHighlighter.computeBlockCommentMask(
      _lines,
      _language,
    );

    var maxUnits = 0;
    for (final line in _lines) {
      final units = _visualUnits(line);
      if (units > maxUnits) {
        maxUnits = units;
      }
    }
    _maxLineUnits = maxUnits;
    _invalidateLineSpans();
  }

  void _syncGutterScroll() {
    if (!_gutterVerticalController.hasClients ||
        !_verticalController.hasClients) {
      return;
    }
    final target = _verticalController.offset.clamp(
      0.0,
      _gutterVerticalController.position.maxScrollExtent,
    );
    if ((_gutterVerticalController.offset - target).abs() > 0.1) {
      _gutterVerticalController.jumpTo(target);
    }
  }

  int _visualUnits(String text) {
    var units = 0;
    for (final rune in text.runes) {
      if (rune == 9) {
        units += 2;
      } else {
        units += rune > 0x7F ? 2 : 1;
      }
    }
    return units;
  }

  EditorPalette get _palette =>
      _isDark ? EditorPalette.dark : EditorPalette.light;

  double get _lineHeight => 1.55;

  double get _singleRowHeight => (_fontSize * _lineHeight).ceilToDouble() + 4;

  double _gutterWidth() {
    final digits = math.max(2, _lines.length.toString().length);
    return digits * (_fontSize * 0.68) + 22;
  }

  void _toggleTheme() {
    _invalidateLineSpans();
    setState(() => _isDark = !_isDark);
  }

  void _toggleWordWrap() {
    setState(() => _wordWrap = !_wordWrap);
  }

  void _adjustFontSize(double delta) {
    final next = (_fontSize + delta).clamp(_minFontSize, _maxFontSize);
    if (next == _fontSize) return;
    _invalidateLineSpans();
    setState(() => _fontSize = next);
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        _searchController.clear();
        _matches = const [];
        _matchesByLine = const {};
        _lineFirstMatchIndex = const {};
        _activeMatchIndex = 0;
      }
    });
    _invalidateLineSpans();
  }

  void _rebuildSearchMatches(String query, {bool jumpToFirst = true}) {
    final matches = CodeSyntaxHighlighter.findMatches(_lines, query);
    final byLine = <int, List<CodeSearchMatch>>{};
    final firstIdx = <int, int>{};
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      byLine.putIfAbsent(m.lineIndex, () => []).add(m);
      firstIdx.putIfAbsent(m.lineIndex, () => i);
    }

    setState(() {
      _matches = matches;
      _matchesByLine = byLine;
      _lineFirstMatchIndex = firstIdx;
      _activeMatchIndex = 0;
      if (matches.isNotEmpty) {
        _activeLineIndex = matches.first.lineIndex;
      }
    });
    _invalidateLineSpans();

    if (jumpToFirst && matches.isNotEmpty) {
      _scrollToLine(matches.first.lineIndex);
    }
  }

  void _stepMatch(int step) {
    if (_matches.isEmpty) return;
    final next = (_activeMatchIndex + step) % _matches.length;
    final normalizedIndex = next < 0 ? next + _matches.length : next;
    final targetLine = _matches[normalizedIndex].lineIndex;
    setState(() {
      _activeMatchIndex = normalizedIndex;
      _activeLineIndex = targetLine;
    });
    _invalidateLineSpans();
    _scrollToLine(targetLine);
  }

  void _scrollToLine(int lineIndex) {
    if (!_verticalController.hasClients) return;
    final viewportHeight = _verticalController.position.viewportDimension;
    double estimatedOffset;
    if (!_wordWrap) {
      estimatedOffset = lineIndex * _singleRowHeight - viewportHeight * 0.25;
    } else {
      final renderBox = context.findRenderObject();
      final totalWidth = renderBox is RenderBox ? renderBox.size.width : 360.0;
      final codeWidth = math.max(120.0, totalWidth - _gutterWidth() - 20);
      final charsPerLine = math.max(
        12,
        (codeWidth / (_fontSize * 0.62)).floor(),
      );
      var offset = 0.0;
      for (var i = 0; i < lineIndex; i++) {
        final units = math.max(1, _visualUnits(_lines[i]));
        final wrappedLines = (units / charsPerLine).ceil();
        offset += wrappedLines * (_fontSize * _lineHeight) + 4;
      }
      estimatedOffset = offset - viewportHeight * 0.25;
    }

    final clamped = estimatedOffset.clamp(
      0.0,
      _verticalController.position.maxScrollExtent,
    );
    _verticalController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    return Container(
      color: palette.background,
      child: Column(
        children: [
          _buildToolbar(palette),
          if (_showSearchBar) _buildSearchBar(palette),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _wordWrap
                    ? _buildWrappedEditor(palette, constraints)
                    : _buildHorizontalEditor(palette, constraints);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(EditorPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          _LanguageBadge(label: _language.label, palette: palette),
          const SizedBox(width: 8),
          Text(
            '${_lines.length} 行',
            style: TextStyle(
              color: palette.toolbarMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _EditorToolButton(
                      tooltip: _showSearchBar ? '关闭查找' : '文件内查找',
                      icon: Icons.search,
                      active: _showSearchBar,
                      palette: palette,
                      onPressed: _toggleSearchBar,
                    ),
                    const SizedBox(width: 4),
                    _EditorToolButton(
                      tooltip: _wordWrap ? '切换为单行横滑' : '切换为自动换行',
                      icon: Icons.wrap_text,
                      label: _wordWrap ? '换行' : '横滑',
                      active: _wordWrap,
                      palette: palette,
                      onPressed: _toggleWordWrap,
                    ),
                    const SizedBox(width: 4),
                    _FontStepper(
                      fontSize: _fontSize,
                      palette: palette,
                      onDecrease: () => _adjustFontSize(-1),
                      onIncrease: () => _adjustFontSize(1),
                    ),
                    const SizedBox(width: 4),
                    _EditorToolButton(
                      tooltip: _isDark ? '切换浅色主题' : '切换深色主题',
                      icon: _isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      active: false,
                      palette: palette,
                      onPressed: _toggleTheme,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(EditorPalette palette) {
    final hasQuery = _searchController.text.isNotEmpty;
    final counterText = _matches.isEmpty
        ? (hasQuery ? '0/0' : '')
        : '${_activeMatchIndex + 1}/${_matches.length}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: palette.toolbarText, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '在代码中查找...',
                  hintStyle: TextStyle(
                    color: palette.toolbarMuted,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: palette.background,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    borderSide: BorderSide(color: palette.chipActiveBackground),
                  ),
                  suffixIcon: counterText.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                counterText,
                                style: TextStyle(
                                  color: _matches.isEmpty
                                      ? palette.keyword
                                      : palette.toolbarMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                ),
                textInputAction: TextInputAction.next,
                onChanged: (value) => _rebuildSearchMatches(value),
                onSubmitted: (_) => _stepMatch(1),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _EditorToolButton(
            tooltip: '上一处',
            icon: Icons.keyboard_arrow_up,
            active: false,
            palette: palette,
            onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
          ),
          const SizedBox(width: 2),
          _EditorToolButton(
            tooltip: '下一处',
            icon: Icons.keyboard_arrow_down,
            active: false,
            palette: palette,
            onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
          ),
          const SizedBox(width: 2),
          _EditorToolButton(
            tooltip: '关闭查找',
            icon: Icons.close,
            active: false,
            palette: palette,
            onPressed: _toggleSearchBar,
          ),
        ],
      ),
    );
  }

  /// 自动换行模式：行号与代码在同一行内竖向堆叠对齐，长行完整折行显示
  Widget _buildWrappedEditor(
    EditorPalette palette,
    BoxConstraints constraints,
  ) {
    final gutterW = _gutterWidth();
    final codeBaseStyle = _codeTextStyle();

    return Scrollbar(
      controller: _verticalController,
      notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
      child: SelectionArea(
        child: ListView.builder(
          controller: _verticalController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _lines.length,
          itemBuilder: (context, index) {
            final isActive = _activeLineIndex == index;
            return InkWell(
              onTap: () => setState(() => _activeLineIndex = index),
              child: Container(
                color: isActive
                    ? palette.activeLineBackground
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: gutterW,
                      padding: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: palette.border),
                        ),
                      ),
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.right,
                        style: _gutterTextStyle(palette, isActive),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10, right: 12),
                        child: Text.rich(
                          _buildLineSpan(index, palette, codeBaseStyle),
                          softWrap: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 横滑单行模式：左侧行号栏固定贴边，右侧支持自由水平滚动并显示水平滚动条
  Widget _buildHorizontalEditor(
    EditorPalette palette,
    BoxConstraints constraints,
  ) {
    final gutterW = _gutterWidth();
    final availableCodeWidth = math.max(80.0, constraints.maxWidth - gutterW);
    final estimatedCodeWidth = _maxLineUnits * (_fontSize * 0.65) + 48.0;
    final contentWidth = math.max(availableCodeWidth, estimatedCodeWidth);
    final rowHeight = _singleRowHeight;
    final codeBaseStyle = _codeTextStyle();

    return Row(
      children: [
        Container(
          width: gutterW,
          decoration: BoxDecoration(
            color: palette.gutterBackground,
            border: Border(right: BorderSide(color: palette.border)),
          ),
          child: ListView.builder(
            controller: _gutterVerticalController,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemExtent: rowHeight,
            itemCount: _lines.length,
            itemBuilder: (context, index) {
              final isActive = _activeLineIndex == index;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _activeLineIndex = index),
                child: Container(
                  color: isActive
                      ? palette.activeLineBackground
                      : Colors.transparent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '${index + 1}',
                    style: _gutterTextStyle(palette, isActive),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Scrollbar(
                  controller: _verticalController,
                  notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                  child: SelectionArea(
                    child: ListView.builder(
                      controller: _verticalController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemExtent: rowHeight,
                      itemCount: _lines.length,
                      itemBuilder: (context, index) {
                        final isActive = _activeLineIndex == index;
                        return InkWell(
                          onTap: () => setState(() => _activeLineIndex = index),
                          child: Container(
                            color: isActive
                                ? palette.activeLineBackground
                                : Colors.transparent,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 10, right: 16),
                            child: Text.rich(
                              _buildLineSpan(index, palette, codeBaseStyle),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 行样式缓存：主题/字号/搜索态变化时整体失效，避免滚动或点行时重复分词
  static const int _spanCacheLimit = 400;
  final Map<int, TextSpan> _spanCache = <int, TextSpan>{};

  void _invalidateLineSpans() {
    _spanCache.clear();
  }

  TextSpan _buildLineSpan(
    int lineIndex,
    EditorPalette palette,
    TextStyle baseStyle,
  ) {
    final cached = _spanCache.remove(lineIndex);
    if (cached != null) {
      // 命中后重新插入到队尾，保持“最近使用在最后”的顺序
      _spanCache[lineIndex] = cached;
      return cached;
    }
    final lineMatches = _matchesByLine[lineIndex] ?? const <CodeSearchMatch>[];
    final firstMatchIdx = _lineFirstMatchIndex[lineIndex] ?? 0;
    final span = CodeSyntaxHighlighter.buildLineSpan(
      line: _lines[lineIndex],
      language: _language,
      palette: palette,
      baseStyle: baseStyle,
      startsInBlockComment: _blockCommentMask[lineIndex],
      lineMatches: lineMatches,
      lineMatchStartIndex: firstMatchIdx,
      activeMatchGlobalIndex: _matches.isEmpty ? null : _activeMatchIndex,
    );
    _spanCache[lineIndex] = span;
    if (_spanCache.length > _spanCacheLimit) {
      _spanCache.remove(_spanCache.keys.first);
    }
    return span;
  }

  TextStyle _codeTextStyle() {
    return AppTextStyles.mono.copyWith(
      fontSize: _fontSize,
      height: _lineHeight,
    );
  }

  TextStyle _gutterTextStyle(EditorPalette palette, bool isActive) {
    return AppTextStyles.monoSmall.copyWith(
      fontSize: math.max(10, _fontSize - 1),
      height: _lineHeight,
      color: isActive ? palette.gutterActiveText : palette.gutterText,
      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
    );
  }
}

class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.label, required this.palette});

  final String label;
  final EditorPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.languageColor(label),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: palette.toolbarText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorToolButton extends StatelessWidget {
  const _EditorToolButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.palette,
    required this.onPressed,
    this.label,
  });

  final String tooltip;
  final IconData icon;
  final String? label;
  final bool active;
  final EditorPalette palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bgColor = active
        ? palette.chipActiveBackground
        : palette.chipBackground;
    final fgColor = active
        ? palette.chipActiveText
        : (onPressed == null ? palette.toolbarMuted : palette.toolbarText);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: label != null ? 7 : 6,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.small),
              border: Border.all(
                color: active ? palette.chipActiveBackground : palette.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fgColor),
                if (label != null) ...[
                  const SizedBox(width: 3),
                  Text(
                    label!,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FontStepper extends StatelessWidget {
  const _FontStepper({
    required this.fontSize,
    required this.palette,
    required this.onDecrease,
    required this.onIncrease,
  });

  final double fontSize;
  final EditorPalette palette;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.chipBackground,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onDecrease,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(AppRadius.small),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                'A-',
                style: TextStyle(
                  color: palette.toolbarText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Container(width: 1, height: 14, color: palette.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              '${fontSize.toInt()}',
              style: TextStyle(
                color: palette.toolbarMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(width: 1, height: 14, color: palette.border),
          InkWell(
            onTap: onIncrease,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(AppRadius.small),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                'A+',
                style: TextStyle(
                  color: palette.toolbarText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
