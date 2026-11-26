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
}
