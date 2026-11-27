import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/utils/loading_dialog.dart';

/// LoadingDialog 引用计数行为测试：并发 show 不重复弹窗、逐个 hide 才关闭
void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  testWidgets('重复 show 只弹出一个加载框，逐个 hide 后关闭', (tester) async {
    await pumpHost(tester);
    final context = tester.element(find.byType(Scaffold));

    LoadingDialog.show(context, message: '加载中...');
    LoadingDialog.show(context, message: '加载中...');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(LoadingDialog.isShowing, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    LoadingDialog.hide();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    LoadingDialog.hide();
    await tester.pumpAndSettle();

    expect(LoadingDialog.isShowing, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('展示调用方文案', (tester) async {
    await pumpHost(tester);
    final context = tester.element(find.byType(Scaffold));

    LoadingDialog.show(context, message: '正在提交...');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('正在提交...'), findsOneWidget);

    LoadingDialog.hide();
    await tester.pumpAndSettle();
  });

  testWidgets('context 已卸载时 show 不弹窗也不残留计数', (tester) async {
    await pumpHost(tester);
    final staleContext = tester.element(find.byType(Scaffold));

    // 换一棵结构不同的树，强制卸载上面拿到的 Scaffold element
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: const Placeholder(),
      ),
    );
    await tester.pump();
    expect(staleContext.mounted, isFalse, reason: '前置条件：context 必须已卸载');

    LoadingDialog.show(staleContext, message: '不应弹出');
    await tester.pump(const Duration(milliseconds: 200));

    expect(LoadingDialog.isShowing, isFalse);
    expect(find.text('不应弹出'), findsNothing);

    // 计数不能残留：否则下一次真实 show/hide 需要多减一次才能关闭
    await pumpHost(tester);
    final context = tester.element(find.byType(Scaffold));
    LoadingDialog.show(context, message: '正常弹出');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('正常弹出'), findsOneWidget);
    LoadingDialog.hide();
    await tester.pumpAndSettle();
    expect(LoadingDialog.isShowing, isFalse);
  });
}
