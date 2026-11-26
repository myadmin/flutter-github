import 'package:flutter/material.dart';
import 'package:gh_explorer/constants/app_theme.dart';

/// 语法 Token 语义分类
enum CodeTokenKind {
  plain,
  keyword,
  stringLiteral,
  comment,
  number,
  typeName,
  functionCall,
  annotation,
  punctuation,
}

/// 语言识别结果（包含内部标识符、展示名、是否支持 `#` 单行注释与块注释）
class CodeLanguageInfo {
  const CodeLanguageInfo({
    required this.id,
    required this.label,
    this.supportsHashComment = false,
    this.supportsSlashComment = true,
    this.supportsSqlComment = false,
  });

  final String id;
  final String label;
  final bool supportsHashComment;
  final bool supportsSlashComment;
  final bool supportsSqlComment;
}

/// 文件内文本查找命中范围
class CodeSearchMatch {
  const CodeSearchMatch({
    required this.lineIndex,
    required this.start,
    required this.end,
  });

  /// 命中所在行索引（从 0 开始）
  final int lineIndex;

  /// 在该行内的起始字符偏移（含）
  final int start;

  /// 在该行内的结束字符偏移（不含）
  final int end;
}

/// 轻量级多语言代码词法高亮器
///
/// 采用按行无状态分词 + 跨行块注释预处理，确保大文件在 `ListView.builder` 中
/// 仅对可见行即时构建彩色 `TextSpan`，并支持叠加搜索词高亮而保持原始文本完整可复制。
class CodeSyntaxHighlighter {
  CodeSyntaxHighlighter._();

  static const CodeLanguageInfo _plainText = CodeLanguageInfo(
    id: 'plaintext',
    label: 'Plain Text',
    supportsSlashComment: false,
  );

  /// 通用及主流语言关键字集合
  static const Set<String> _keywords = {
    'abstract',
    'as',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'declare',
    'default',
    'defer',
    'def',
    'del',
    'delete',
    'do',
    'dynamic',
    'elif',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'fn',
    'for',
    'from',
    'fun',
    'function',
    'get',
    'go',
    'hide',
    'if',
    'impl',
    'implements',
    'import',
    'in',
    'infer',
    'instanceof',
    'interface',
    'is',
    'keyof',
    'lambda',
    'late',
    'let',
    'library',
    'match',
    'mixin',
    'mod',
    'module',
    'mut',
    'namespace',
    'never',
    'new',
    'nil',
    'nonlocal',
    'none',
    'not',
    'null',
    'object',
    'of',
    'on',
    'operator',
    'or',
    'out',
    'override',
    'package',
    'part',
    'pass',
    'private',
    'protected',
    'pub',
    'public',
    'raise',
    'readonly',
    'record',
    'ref',
    'required',
    'return',
    'satisfies',
    'sealed',
    'select',
    'self',
    'set',
    'show',
    'static',
    'struct',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'throws',
    'trait',
    'true',
    'try',
    'type',
    'typedef',
    'typeof',
    'undefined',
    'unknown',
    'unless',
    'unsafe',
    'use',
    'using',
    'val',
    'var',
    'void',
    'when',
    'where',
    'while',
    'with',
    'yield',
  };

  /// 内置原始类型名集合
  static const Set<String> _builtinTypes = {
    'any',
    'bool',
    'boolean',
    'byte',
    'char',
    'double',
    'f32',
    'f64',
    'float',
    'i32',
    'i64',
    'int',
    'long',
    'number',
    'short',
    'str',
    'string',
    'symbol',
    'u32',
    'u64',
    'usize',
  };

  /// 根据文件路径或文件名识别语言信息
  static CodeLanguageInfo detectLanguage(String filePath) {
    final normalized = filePath.trim().replaceAll('\\', '/');
    final fileName = normalized.split('/').last.toLowerCase();

    if (fileName == 'dockerfile' || fileName.startsWith('dockerfile.')) {
      return const CodeLanguageInfo(
        id: 'dockerfile',
        label: 'Dockerfile',
        supportsHashComment: true,
        supportsSlashComment: false,
      );
    }
    if (fileName == 'makefile' || fileName == 'gnumakefile') {
      return const CodeLanguageInfo(
        id: 'makefile',
        label: 'Makefile',
        supportsHashComment: true,
        supportsSlashComment: false,
      );
    }
    if (fileName == '.gitignore' ||
        fileName == '.dockerignore' ||
        fileName.startsWith('.env')) {
      return const CodeLanguageInfo(
        id: 'config',
        label: 'Config',
        supportsHashComment: true,
        supportsSlashComment: false,
      );
    }

    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return _plainText;
    }
    final ext = fileName.substring(dotIndex + 1);
    switch (ext) {
      case 'ts':
      case 'mts':
      case 'cts':
        return const CodeLanguageInfo(id: 'typescript', label: 'TypeScript');
      case 'tsx':
        return const CodeLanguageInfo(id: 'typescript', label: 'TSX');
      case 'js':
      case 'mjs':
      case 'cjs':
        return const CodeLanguageInfo(id: 'javascript', label: 'JavaScript');
      case 'jsx':
        return const CodeLanguageInfo(id: 'javascript', label: 'JSX');
      case 'dart':
        return const CodeLanguageInfo(id: 'dart', label: 'Dart');
      case 'py':
      case 'pyw':
      case 'pyi':
        return const CodeLanguageInfo(
          id: 'python',
          label: 'Python',
          supportsHashComment: true,
          supportsSlashComment: false,
        );
      case 'go':
        return const CodeLanguageInfo(id: 'go', label: 'Go');
      case 'rs':
        return const CodeLanguageInfo(id: 'rust', label: 'Rust');
      case 'java':
        return const CodeLanguageInfo(id: 'java', label: 'Java');
      case 'kt':
      case 'kts':
        return const CodeLanguageInfo(id: 'kotlin', label: 'Kotlin');
      case 'swift':
        return const CodeLanguageInfo(id: 'swift', label: 'Swift');
      case 'c':
      case 'h':
        return const CodeLanguageInfo(id: 'c', label: 'C');
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'hpp':
        return const CodeLanguageInfo(id: 'cpp', label: 'C++');
      case 'cs':
        return const CodeLanguageInfo(id: 'csharp', label: 'C#');
      case 'rb':
        return const CodeLanguageInfo(
          id: 'ruby',
          label: 'Ruby',
          supportsHashComment: true,
          supportsSlashComment: false,
        );
      case 'php':
        return const CodeLanguageInfo(
          id: 'php',
          label: 'PHP',
          supportsHashComment: true,
        );
      case 'json':
      case 'arb':
        return const CodeLanguageInfo(
          id: 'json',
          label: 'JSON',
          supportsSlashComment: false,
        );
      case 'jsonc':
        return const CodeLanguageInfo(id: 'json', label: 'JSONC');
      case 'yaml':
      case 'yml':
        return const CodeLanguageInfo(
          id: 'yaml',
          label: 'YAML',
          supportsHashComment: true,
          supportsSlashComment: false,
        );
      case 'toml':
        return const CodeLanguageInfo(
          id: 'toml',
          label: 'TOML',
          supportsHashComment: true,
          supportsSlashComment: false,
        );
      case 'sh':
      case 'bash':
      case 'zsh':
        return const CodeLanguageInfo(
          id: 'shell',
          label: 'Shell',
          supportsHashComment: true,
          supportsSlashComment: false,
        );
      case 'ps1':
        return const CodeLanguageInfo(
          id: 'powershell',
          label: 'PowerShell',
          supportsHashComment: true,
          supportsSlashComment: false,
        );
      case 'sql':
        return const CodeLanguageInfo(
          id: 'sql',
          label: 'SQL',
          supportsSqlComment: true,
        );
      case 'html':
      case 'htm':
      case 'xml':
      case 'svg':
        return CodeLanguageInfo(
          id: 'markup',
          label: ext.toUpperCase(),
          supportsSlashComment: false,
        );
      case 'css':
      case 'scss':
      case 'less':
        return CodeLanguageInfo(id: 'css', label: ext.toUpperCase());
      case 'md':
      case 'markdown':
        return const CodeLanguageInfo(
          id: 'markdown',
          label: 'Markdown',
          supportsSlashComment: false,
        );
      case 'gradle':
        return const CodeLanguageInfo(id: 'kotlin', label: 'Gradle');
      default:
        return CodeLanguageInfo(
          id: ext,
          label: ext.toUpperCase(),
          supportsHashComment: true,
        );
    }
  }

  /// 获取某类 Token 在当前主题下的前景颜色
  static Color colorForToken(CodeTokenKind kind, EditorPalette palette) {
    switch (kind) {
      case CodeTokenKind.plain:
        return palette.plain;
      case CodeTokenKind.keyword:
        return palette.keyword;
      case CodeTokenKind.stringLiteral:
        return palette.stringLiteral;
      case CodeTokenKind.comment:
        return palette.comment;
      case CodeTokenKind.number:
        return palette.number;
      case CodeTokenKind.typeName:
        return palette.typeName;
      case CodeTokenKind.functionCall:
        return palette.functionCall;
      case CodeTokenKind.annotation:
        return palette.annotation;
      case CodeTokenKind.punctuation:
        return palette.punctuation;
    }
  }

  /// 预计算每一行进入时是否处于 `/* ... */` 跨行注释状态
  static List<bool> computeBlockCommentMask(
    List<String> lines,
    CodeLanguageInfo language,
  ) {
    final result = List<bool>.filled(lines.length, false);
    if (!language.supportsSlashComment) return result;

    var inBlockComment = false;
    for (var row = 0; row < lines.length; row++) {
      result[row] = inBlockComment;
      final line = lines[row];
      var i = 0;
      while (i < line.length) {
        if (inBlockComment) {
          if (i + 1 < line.length && line[i] == '*' && line[i + 1] == '/') {
            inBlockComment = false;
            i += 2;
          } else {
            i++;
          }
          continue;
        }
        final ch = line[i];
        if (ch == '"' || ch == '\'' || ch == '`') {
          i = _skipString(line, i, ch);
          continue;
        }
        if (i + 1 < line.length && ch == '/' && line[i + 1] == '/') {
          break;
        }
        if (i + 1 < line.length && ch == '/' && line[i + 1] == '*') {
          inBlockComment = true;
          i += 2;
          continue;
        }
        i++;
      }
    }
    return result;
  }

  /// 在全文件行列表中执行大小写不敏感的关键字查找
  static List<CodeSearchMatch> findMatches(List<String> lines, String query) {
    final trimmed = query;
    if (trimmed.isEmpty) return const [];
    final lowerQuery = trimmed.toLowerCase();
    final matches = <CodeSearchMatch>[];
    for (var row = 0; row < lines.length; row++) {
      final lowerLine = lines[row].toLowerCase();
      var startIndex = 0;
      while (startIndex <= lowerLine.length - lowerQuery.length) {
        final found = lowerLine.indexOf(lowerQuery, startIndex);
        if (found < 0) break;
        matches.add(
          CodeSearchMatch(
            lineIndex: row,
            start: found,
            end: found + lowerQuery.length,
          ),
        );
        startIndex = found + lowerQuery.length;
      }
    }
    return matches;
  }

  /// 将单行源代码分词并叠加当前行的搜索高亮，返回完整的 `TextSpan`
  static TextSpan buildLineSpan({
    required String line,
    required CodeLanguageInfo language,
    required EditorPalette palette,
    required TextStyle baseStyle,
    bool startsInBlockComment = false,
    List<CodeSearchMatch> lineMatches = const [],
    int lineMatchStartIndex = 0,
    int? activeMatchGlobalIndex,
  }) {
    if (line.isEmpty) {
      return TextSpan(
        text: '',
        style: baseStyle.copyWith(color: palette.plain),
      );
    }

    final runs = _tokenizeLine(
      line: line,
      language: language,
      startsInBlockComment: startsInBlockComment,
    );

    if (lineMatches.isEmpty) {
      return TextSpan(
        style: baseStyle,
        children: [
          for (final run in runs)
            TextSpan(
              text: line.substring(run.start, run.end),
              style: TextStyle(color: colorForToken(run.kind, palette)),
            ),
        ],
      );
    }

    final children = <InlineSpan>[];
    for (final run in runs) {
      var cursor = run.start;
      final tokenColor = colorForToken(run.kind, palette);
      for (var mIdx = 0; mIdx < lineMatches.length; mIdx++) {
        final match = lineMatches[mIdx];
        if (match.end <= cursor) continue;
        if (match.start >= run.end) break;

        if (match.start > cursor) {
          children.add(
            TextSpan(
              text: line.substring(cursor, match.start),
              style: TextStyle(color: tokenColor),
            ),
          );
          cursor = match.start;
        }

        final overlapEnd = match.end < run.end ? match.end : run.end;
        final isActive =
            activeMatchGlobalIndex != null &&
            (lineMatchStartIndex + mIdx) == activeMatchGlobalIndex;
        children.add(
          TextSpan(
            text: line.substring(cursor, overlapEnd),
            style: TextStyle(
              color: tokenColor,
              backgroundColor: isActive
                  ? palette.activeMatchBackground
                  : palette.matchBackground,
            ),
          ),
        );
        cursor = overlapEnd;
      }

      if (cursor < run.end) {
        children.add(
          TextSpan(
            text: line.substring(cursor, run.end),
            style: TextStyle(color: tokenColor),
          ),
        );
      }
    }

    return TextSpan(style: baseStyle, children: children);
  }

  static List<_TokenRun> _tokenizeLine({
    required String line,
    required CodeLanguageInfo language,
    required bool startsInBlockComment,
  }) {
    if (language.id == 'yaml' || language.id == 'toml') {
      return _tokenizeKeyValueConfig(line);
    }
    if (language.id == 'markdown') {
      return _tokenizeMarkdownLine(line);
    }
    return _tokenizeCodeLine(
      line: line,
      language: language,
      startsInBlockComment: startsInBlockComment,
    );
  }

  static List<_TokenRun> _tokenizeMarkdownLine(String line) {
    final trimmedLeft = line.trimLeft();
    if (trimmedLeft.startsWith('#')) {
      return [_TokenRun(0, line.length, CodeTokenKind.keyword)];
    }
    if (trimmedLeft.startsWith('```')) {
      return [_TokenRun(0, line.length, CodeTokenKind.annotation)];
    }
    if (trimmedLeft.startsWith('>')) {
      return [_TokenRun(0, line.length, CodeTokenKind.comment)];
    }

    final runs = <_TokenRun>[];
    var i = 0;
    while (i < line.length) {
      if (line[i] == '`') {
        final close = line.indexOf('`', i + 1);
        final end = close >= 0 ? close + 1 : line.length;
        runs.add(_TokenRun(i, end, CodeTokenKind.stringLiteral));
        i = end;
      } else if (line[i] == '[' ||
          line[i] == ']' ||
          line[i] == '(' ||
          line[i] == ')') {
        runs.add(_TokenRun(i, i + 1, CodeTokenKind.punctuation));
        i++;
      } else {
        final start = i;
        while (i < line.length &&
            line[i] != '`' &&
            line[i] != '[' &&
            line[i] != ']' &&
            line[i] != '(' &&
            line[i] != ')') {
          i++;
        }
        runs.add(_TokenRun(start, i, CodeTokenKind.plain));
      }
    }
    return runs;
  }

  static List<_TokenRun> _tokenizeKeyValueConfig(String line) {
    final runs = <_TokenRun>[];
    var i = 0;
    while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
      i++;
    }
    if (i > 0) {
      runs.add(_TokenRun(0, i, CodeTokenKind.plain));
    }
    if (i < line.length && line[i] == '#') {
      runs.add(_TokenRun(i, line.length, CodeTokenKind.comment));
      return runs;
    }

    // YAML/TOML 键名识别（如 `name:` 或 `version =`）
    final sepIndex = _findConfigSeparator(line, i);
    if (sepIndex > i) {
      if (line.substring(i, sepIndex).startsWith('- ')) {
        runs.add(_TokenRun(i, i + 2, CodeTokenKind.punctuation));
        runs.add(_TokenRun(i + 2, sepIndex, CodeTokenKind.typeName));
      } else {
        runs.add(_TokenRun(i, sepIndex, CodeTokenKind.typeName));
      }
      runs.add(_TokenRun(sepIndex, sepIndex + 1, CodeTokenKind.punctuation));
      i = sepIndex + 1;
    }

    if (i < line.length) {
      runs.addAll(
        _tokenizeCodeLine(
          line: line,
          language: const CodeLanguageInfo(
            id: 'yaml',
            label: 'YAML',
            supportsHashComment: true,
            supportsSlashComment: false,
          ),
          startsInBlockComment: false,
          initialIndex: i,
        ),
      );
    }
    return runs;
  }

  static int _findConfigSeparator(String line, int start) {
    var quoteChar = '';
    for (var i = start; i < line.length; i++) {
      final ch = line[i];
      if (quoteChar.isNotEmpty) {
        if (ch == quoteChar && (i == 0 || line[i - 1] != '\\')) {
          quoteChar = '';
        }
        continue;
      }
      if (ch == '"' || ch == '\'') {
        quoteChar = ch;
        continue;
      }
      if (ch == '#') return -1;
      if (ch == ':' && (i + 1 == line.length || line[i + 1] == ' ')) {
        return i;
      }
      if (ch == '=') return i;
    }
    return -1;
  }

  static List<_TokenRun> _tokenizeCodeLine({
    required String line,
    required CodeLanguageInfo language,
    required bool startsInBlockComment,
    int initialIndex = 0,
  }) {
    final runs = <_TokenRun>[];
    var i = initialIndex;
    var inBlockComment = startsInBlockComment;

    if (inBlockComment) {
      final closeIndex = line.indexOf('*/', i);
      if (closeIndex < 0) {
        runs.add(_TokenRun(i, line.length, CodeTokenKind.comment));
        return runs;
      }
      runs.add(_TokenRun(i, closeIndex + 2, CodeTokenKind.comment));
      i = closeIndex + 2;
      inBlockComment = false;
    }

    while (i < line.length) {
      final ch = line[i];

      // 连续空白直接归为 plain
      if (ch == ' ' || ch == '\t' || ch == '\r') {
        final start = i;
        while (i < line.length &&
            (line[i] == ' ' || line[i] == '\t' || line[i] == '\r')) {
          i++;
        }
        runs.add(_TokenRun(start, i, CodeTokenKind.plain));
        continue;
      }

      // 单行与块注释
      if (language.supportsSlashComment &&
          i + 1 < line.length &&
          ch == '/' &&
          line[i + 1] == '/') {
        runs.add(_TokenRun(i, line.length, CodeTokenKind.comment));
        break;
      }
      if (language.supportsSlashComment &&
          i + 1 < line.length &&
          ch == '/' &&
          line[i + 1] == '*') {
        final closeIndex = line.indexOf('*/', i + 2);
        if (closeIndex < 0) {
          runs.add(_TokenRun(i, line.length, CodeTokenKind.comment));
          break;
        }
        runs.add(_TokenRun(i, closeIndex + 2, CodeTokenKind.comment));
        i = closeIndex + 2;
        continue;
      }
      if (language.supportsHashComment && ch == '#') {
        runs.add(_TokenRun(i, line.length, CodeTokenKind.comment));
        break;
      }
      if (language.supportsSqlComment &&
          i + 1 < line.length &&
          ch == '-' &&
          line[i + 1] == '-') {
        runs.add(_TokenRun(i, line.length, CodeTokenKind.comment));
        break;
      }

      // 字符串字面量（支持单/双/反引号及 JSON 属性键区分）
      if (ch == '"' || ch == '\'' || ch == '`') {
        final end = _skipString(line, i, ch);
        var kind = CodeTokenKind.stringLiteral;
        if (language.id == 'json') {
          var lookahead = end;
          while (lookahead < line.length && line[lookahead] == ' ') {
            lookahead++;
          }
          if (lookahead < line.length && line[lookahead] == ':') {
            kind = CodeTokenKind.typeName;
          }
        }
        runs.add(_TokenRun(i, end, kind));
        i = end;
        continue;
      }

      // 注解/装饰器 `@override`、`@Component`
      if (ch == '@' &&
          i + 1 < line.length &&
          _isIdentifierStart(line.codeUnitAt(i + 1))) {
        final start = i;
        i++;
        while (i < line.length && _isIdentifierPart(line.codeUnitAt(i))) {
          i++;
        }
        runs.add(_TokenRun(start, i, CodeTokenKind.annotation));
        continue;
      }

      // 数字字面量
      if (_isDigit(line.codeUnitAt(i))) {
        final start = i;
        while (i < line.length && _isNumberChar(line.codeUnitAt(i))) {
          i++;
        }
        runs.add(_TokenRun(start, i, CodeTokenKind.number));
        continue;
      }

      // 标识符、关键字、类型与函数调用
      if (_isIdentifierStart(line.codeUnitAt(i))) {
        final start = i;
        i++;
        while (i < line.length && _isIdentifierPart(line.codeUnitAt(i))) {
          i++;
        }
        final word = line.substring(start, i);
        final kind = _classifyIdentifier(word, line, i);
        runs.add(_TokenRun(start, i, kind));
        continue;
      }

      // 标点及运算符
      if (_isPunctuation(ch)) {
        final start = i;
        i++;
        while (i < line.length && _isPunctuation(line[i])) {
          i++;
        }
        runs.add(_TokenRun(start, i, CodeTokenKind.punctuation));
        continue;
      }

      // 兜底其他字符
      runs.add(_TokenRun(i, i + 1, CodeTokenKind.plain));
      i++;
    }

    return runs;
  }

  static CodeTokenKind _classifyIdentifier(
    String word,
    String line,
    int afterIndex,
  ) {
    if (_keywords.contains(word) || _keywords.contains(word.toLowerCase())) {
      // 仅对大小写敏感的关键字或 SQL 全大写关键字做严格匹配
      if (_keywords.contains(word) || word == word.toUpperCase()) {
        return CodeTokenKind.keyword;
      }
    }
    if (_builtinTypes.contains(word)) {
      return CodeTokenKind.typeName;
    }

    // 紧跟括号的非关键字标识符视为函数/方法调用
    var lookahead = afterIndex;
    while (lookahead < line.length && line[lookahead] == ' ') {
      lookahead++;
    }
    if (lookahead < line.length && line[lookahead] == '(') {
      return CodeTokenKind.functionCall;
    }

    // 首字母大写（且含小写字母，避免全大写常量误判或按类型高亮）
    final first = word.codeUnitAt(0);
    if (first >= 65 && first <= 90) {
      return CodeTokenKind.typeName;
    }

    return CodeTokenKind.plain;
  }

  static int _skipString(String line, int start, String quote) {
    var i = start + 1;
    while (i < line.length) {
      final ch = line[i];
      if (ch == '\\') {
        i += 2;
        continue;
      }
      if (ch == quote) {
        return i + 1;
      }
      i++;
    }
    return line.length;
  }

  static bool _isDigit(int code) => code >= 48 && code <= 57;

  static bool _isNumberChar(int code) =>
      _isDigit(code) ||
      code == 46 || // .
      code == 95 || // _
      (code >= 65 && code <= 70) || // A-F
      (code >= 97 && code <= 102) || // a-f
      code == 120 || // x
      code == 88; // X

  static bool _isIdentifierStart(int code) =>
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 95 ||
      code == 36;

  static bool _isIdentifierPart(int code) =>
      _isIdentifierStart(code) || _isDigit(code);

  static bool _isPunctuation(String ch) => const {
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    '<',
    '>',
    '=',
    '+',
    '-',
    '*',
    '/',
    '%',
    '|',
    '&',
    '!',
    '?',
    ':',
    ';',
    ',',
    '.',
  }.contains(ch);
}

class _TokenRun {
  const _TokenRun(this.start, this.end, this.kind);

  final int start;
  final int end;
  final CodeTokenKind kind;
}
