import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/components/Repo/gh_code_editor_view.dart';
import 'package:gh_explorer/constants/app_theme.dart';
import 'package:gh_explorer/pages/RepoFileView/index.dart';
import 'package:gh_explorer/utils/code_syntax_highlighter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    registerTestControllers();
  });

  group('CodeSyntaxHighlighter 词法识别与高亮', () {
    test('detectLanguage 能正确识别常见编程语言与配置文件', () {
      expect(
        CodeSyntaxHighlighter.detectLanguage('src/showThreadUndoNotice.ts')
            .label,
        'TypeScript',
      );
      expect(CodeSyntaxHighlighter.detectLanguage('App.tsx').label, 'TSX');
      expect(
        CodeSyntaxHighlighter.detectLanguage('lib/main.dart').label,
        'Dart',
      );
      expect(CodeSyntaxHighlighter.detectLanguage('train.py').label, 'Python');
      expect(CodeSyntaxHighlighter.detectLanguage('server.go').label, 'Go');
      expect(CodeSyntaxHighlighter.detectLanguage('lib.rs').label, 'Rust');
      expect(
        CodeSyntaxHighlighter.detectLanguage('package.json').label,
        'JSON',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('pubspec.yaml').label,
        'YAML',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('docker/Dockerfile').label,
        'Dockerfile',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('Makefile').label,
        'Makefile',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('.env.local').label,
        'Config',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('README.md').label,
        'Markdown',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('notes.customext').label,
        'CUSTOMEXT',
      );
      expect(
        CodeSyntaxHighlighter.detectLanguage('LICENSE').label,
        'Plain Text',
      );
    });

    test('computeBlockCommentMask 能准确跟踪跨行块注释且忽略字符串内符号', () {
      const lang = CodeLanguageInfo(id: 'typescript', label: 'TypeScript');
      const lines = [
        'const pattern = "/* not comment */";',
        '/* start block',
        ' * middle line',
        ' */ const a = 1;',
        'const b = 2;',
      ];
      final mask = CodeSyntaxHighlighter.computeBlockCommentMask(lines, lang);
      expect(mask, [false, false, true, true, false]);
    });

    test('buildLineSpan 能区分关键字、类型、函数调用、字符串、注释与搜索命中高亮', () {
      const palette = EditorPalette.dark;
      const baseStyle = TextStyle(fontSize: 13);
      final lang = CodeSyntaxHighlighter.detectLanguage('demo.ts');
      const line =
          'export const undo = msg("Settled", UndoOptions, 42); // note';

      final matches = CodeSyntaxHighlighter.findMatches([line], 'Undo');
      expect(matches.length, 2);

      final span = CodeSyntaxHighlighter.buildLineSpan(
        line: line,
        language: lang,
        palette: palette,
        baseStyle: baseStyle,
        lineMatches: matches,
        lineMatchStartIndex: 0,
        activeMatchGlobalIndex: 1,
      );

      expect(span.toPlainText(), line);
      final children = span.children!.whereType<TextSpan>().toList();

      // export 关键字颜色
      expect(
        children.any(
          (s) => s.text == 'export' && s.style?.color == palette.keyword,
        ),
        isTrue,
      );
      // msg 函数调用颜色
      expect(
        children.any(
          (s) => s.text == 'msg' && s.style?.color == palette.functionCall,
        ),
        isTrue,
      );
      // 字符串字面量颜色
      expect(
        children.any(
          (s) =>
              s.text == '"Settled"' && s.style?.color == palette.stringLiteral,
        ),
        isTrue,
      );
      // 数字字面量颜色
      expect(
        children.any((s) => s.text == '42' && s.style?.color == palette.number),
        isTrue,
      );
      // 单行注释颜色
      expect(
        children.any(
          (s) => s.text == '// note' && s.style?.color == palette.comment,
        ),
        isTrue,
      );
      // 第 0 个匹配项使用普通匹配底色，第 1 个（当前激活）使用激活匹配底色
      expect(
        children.any(
          (s) =>
              s.text == 'undo' &&
              s.style?.backgroundColor == palette.matchBackground,
        ),
        isTrue,
      );
      expect(
        children.any(
          (s) =>
              s.text == 'Undo' &&
              s.style?.backgroundColor == palette.activeMatchBackground,
        ),
        isTrue,
      );
    });

    test('buildLineSpan 支持 JSON 键值、YAML 与 Markdown 高亮', () {
      const palette = EditorPalette.light;
      const baseStyle = TextStyle(fontSize: 13);

      final jsonSpan = CodeSyntaxHighlighter.buildLineSpan(
        line: '  "name": "gh_explorer",',
        language: CodeSyntaxHighlighter.detectLanguage('package.json'),
        palette: palette,
        baseStyle: baseStyle,
      );
      final jsonSpans = jsonSpan.children!.whereType<TextSpan>().toList();
      expect(
        jsonSpans.any(
          (s) => s.text == '"name"' && s.style?.color == palette.typeName,
        ),
        isTrue,
      );
      expect(
        jsonSpans.any(
          (s) =>
              s.text == '"gh_explorer"' &&
              s.style?.color == palette.stringLiteral,
        ),
        isTrue,
      );

      final yamlSpan = CodeSyntaxHighlighter.buildLineSpan(
        line: 'name: gh_explorer # app',
        language: CodeSyntaxHighlighter.detectLanguage('pubspec.yaml'),
        palette: palette,
        baseStyle: baseStyle,
      );
      expect(yamlSpan.toPlainText(), 'name: gh_explorer # app');

      final mdSpan = CodeSyntaxHighlighter.buildLineSpan(
        line: '# Heading',
        language: CodeSyntaxHighlighter.detectLanguage('README.md'),
        palette: palette,
        baseStyle: baseStyle,
      );
      expect(
        mdSpan.children!.whereType<TextSpan>().first.style?.color,
        palette.keyword,
      );
    });
  });

  group('RepoFileViewPage 与 GhCodeEditorView 交互测试', () {
    const sampleTsCode = '''import { thrownErrorMessage } from '@t3tools/client-runtime/errors/AtomCommandError';
import {
  type AtomCommandResult,
  isAtomCommandInterrupted,
} from '@t3tools/client-runtime/state/runtime';

// 处理撤销操作提示条
@deprecated
export const useThreadUndoNotice = create<{ notice: UndoNotice | null }>(() => ({
  notice: null,
}));
const count = 3;
const label = 'UndoNotice';''';

    testWidgets('支持多语言高亮渲染、主题切换、换行/横滑切换、字号调节与文件内查找跳转', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              return null;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      installMock((options) {
        if (options.path.contains('/contents/')) {
          return rawResponse(sampleTsCode);
        }
        return jsonResponse(<String, dynamic>{});
      });

      await tester.pumpWidget(
        buildTestApp(
          const RepoFileViewPage(
            owner: 't3dotgg',
            repoName: 't3code',
            path: 'src/showThreadUndoNotice.ts',
            branch: 'main',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 语言徽章、总行数、默认字体大小与完整长行渲染
      expect(find.text('showThreadUndoNotice.ts'), findsOneWidget);
      expect(find.text('TypeScript'), findsOneWidget);
      expect(find.text('13 行'), findsOneWidget);
      expect(find.text('13'), findsNWidgets(2)); // 13 既是字号指示也是第 13 行行号
      expect(
        find.textContaining(
          "@t3tools/client-runtime/errors/AtomCommandError';",
        ),
        findsOneWidget,
      );

      // 字号 A+ / A- 调节
      await tester.tap(find.text('A+'));
      await tester.pump();
      expect(find.text('14'), findsOneWidget);

      await tester.tap(find.text('A-'));
      await tester.pump();
      await tester.tap(find.text('A-'));
      await tester.pump();
      // 12 既是字号指示，也是第 12 行行号
      expect(find.text('12'), findsNWidgets(2));

      // 切换自动换行 -> 单行横滑模式（含左侧固定行号栏 + 水平滚动）
      expect(find.text('换行'), findsOneWidget);
      await tester.tap(find.text('换行'));
      await tester.pump();
      expect(find.text('横滑'), findsOneWidget);
      expect(find.textContaining('useThreadUndoNotice'), findsOneWidget);

      // 切回自动换行模式
      await tester.tap(find.text('横滑'));
      await tester.pump();
      expect(find.text('换行'), findsOneWidget);

      // 编辑器主题联动全局外观（默认亮色起点），支持一键切换到暗色再切回
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.dark_mode_outlined));
      await tester.pump();
      expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

      // 点击某一行代码激活当前行高亮
      await tester.tap(find.text('2'));
      await tester.pump();

      // 文件内查找与上下跳转
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Undo');
      await tester.pump();

      expect(find.text('1/3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      expect(find.text('2/3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      expect(find.text('1/3'), findsOneWidget);

      // 关闭查找栏
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);

      // 复制全文触发 Toast
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(find.text('已复制文件内容'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Markdown 文件支持富文本预览与源码编辑器双模式切换', (tester) async {
      installMock((options) {
        if (options.path.contains('/contents/')) {
          return rawResponse('# Title\n\n`inline code` paragraph');
        }
        return jsonResponse(<String, dynamic>{});
      });

      await tester.pumpWidget(
        buildTestApp(
          const RepoFileViewPage(
            owner: 'flutter',
            repoName: 'flutter',
            path: 'README.md',
            branch: 'master',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 默认渲染 Markdown 富文本，顶部出现源码切换按钮
      expect(find.byType(GhCodeEditorView), findsNothing);
      expect(find.byIcon(Icons.code), findsOneWidget);

      // 切换为源码编辑器模式
      await tester.tap(find.byIcon(Icons.code));
      await tester.pumpAndSettle();
      expect(find.byType(GhCodeEditorView), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
      expect(find.textContaining('# Title'), findsOneWidget);

      // 切换回富文本预览模式
      await tester.tap(find.byIcon(Icons.article_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(GhCodeEditorView), findsNothing);
    });
  });
}
