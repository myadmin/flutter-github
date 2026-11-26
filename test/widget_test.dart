import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 根应用启动冒烟测试
void main() {
  testWidgets('getRootWidget 正常启动并渲染首页探索列表', (tester) async {
    SharedPreferences.setMockInitialValues({});
    registerTestControllers();
    installMock((options) => jsonResponse(searchReposJson()));

    await tester.pumpWidget(getRootWidget());
    await tester.pumpAndSettle();

    expect(find.text('探索开源项目'), findsOneWidget);
    expect(find.text('flutter/flutter'), findsOneWidget);
  });
}
