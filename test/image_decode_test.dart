import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/components/common/app_network_image.dart';
import 'package:gh_explorer/components/common/gh_markdown_view.dart';
import 'package:gh_explorer/routes/index.dart';

/// 图片解码尺寸测试：确保列表头像与 README 图片都按显示尺寸解码，避免原图占满内存
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  /// 读取 Image 实际使用的解码宽度（未设置 cacheWidth 时返回 null）
  int? decodedWidthOf(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    return provider is ResizeImage ? provider.width : null;
  }

  testWidgets('AppNetworkImage 未显式指定 decodeWidth 时按 width 推导解码宽度', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const AppNetworkImage(url: 'https://example.com/a.png', width: 40)),
    );
    await tester.pump();

    final dpr = tester.view.devicePixelRatio;
    expect(decodedWidthOf(tester), (40 * dpr).round());
  });

  testWidgets('AppNetworkImage 显式 decodeWidth 优先于 width', (tester) async {
    await tester.pumpWidget(
      wrap(
        const AppNetworkImage(
          url: 'https://example.com/a.png',
          width: 40,
          decodeWidth: 80,
        ),
      ),
    );
    await tester.pump();

    final dpr = tester.view.devicePixelRatio;
    expect(decodedWidthOf(tester), (80 * dpr).round());
  });

  testWidgets('Markdown 图片按容器宽度解码并携带语义标签', (tester) async {
    await tester.pumpWidget(
      wrap(
        const GhMarkdownView(
          data: '![架构图](https://example.com/arch.png)',
          owner: '',
          repo: '',
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, '架构图');
    expect(decodedWidthOf(tester), isNotNull);
    expect(decodedWidthOf(tester), greaterThan(0));
  });
}
