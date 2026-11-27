import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gh_explorer/routes/app_routes.dart';
import 'package:gh_explorer/routes/index.dart';
import 'package:gh_explorer/services/apk_downloader_io.dart';
import 'package:gh_explorer/services/apk_verifier.dart';
import 'package:gh_explorer/utils/app_error_reporter.dart';
import 'package:gh_explorer/utils/external_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mock_http.dart';

/// 安全与健壮性基础设施测试：外链白名单、错误上报、APK 下载前置校验、深链参数守卫
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    registerTestControllers();
  });

  group('isAllowedExternalUrl', () {
    test('允许 http/https/mailto', () {
      expect(
        isAllowedExternalUrl('https://github.com/flutter/flutter'),
        isTrue,
      );
      expect(isAllowedExternalUrl('http://example.com'), isTrue);
      expect(isAllowedExternalUrl('mailto:dev@example.com'), isTrue);
    });

    test('拦截危险 scheme 与非法输入', () {
      expect(isAllowedExternalUrl('intent://scan#Intent;end'), isFalse);
      expect(isAllowedExternalUrl('javascript:alert(1)'), isFalse);
      expect(isAllowedExternalUrl('market://details?id=x'), isFalse);
      expect(isAllowedExternalUrl('tg://resolve?domain=x'), isFalse);
      expect(isAllowedExternalUrl(''), isFalse);
      expect(isAllowedExternalUrl('   '), isFalse);
    });

    test('http/https 必须带主机名', () {
      expect(isAllowedExternalUrl('https://'), isFalse);
      expect(isAllowedExternalUrl('file:///etc/passwd'), isFalse);
    });

    test('openExternalUrl 对非法链接直接返回 false', () async {
      expect(await openExternalUrl('intent://scan#Intent;end'), isFalse);
    });
  });

  group('AppErrorReporter', () {
    test('把未捕获异常交给可插拔上报器', () {
      final reported = <String>[];
      final previous = AppErrorReporter.sink;
      AppErrorReporter.sink = (error, stack, {String? context}) {
        reported.add('$context:$error');
      };
      addTearDown(() => AppErrorReporter.sink = previous);

      AppErrorReporter.report(
        StateError('boom'),
        StackTrace.current,
        context: 'unit-test',
      );

      expect(reported, ['unit-test:Bad state: boom']);
    });

    test('上报器自身抛错不会影响调用方', () {
      final previous = AppErrorReporter.sink;
      AppErrorReporter.sink = (error, stack, {String? context}) {
        throw StateError('sink failed');
      };
      addTearDown(() => AppErrorReporter.sink = previous);

      expect(
        () => AppErrorReporter.report(StateError('boom'), null),
        returnsNormally,
      );
    });
  });

  group('downloadApkToFile 前置校验', () {
    test('拒绝非 HTTPS 下载地址', () async {
      await expectLater(
        downloadApkToFile(
          url: 'http://example.com/app.apk',
          directoryPath: 'unused',
          fileName: 'app.apk',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('拒绝相对地址与空主机', () async {
      await expectLater(
        downloadApkToFile(
          url: 'https:///app.apk',
          directoryPath: 'unused',
          fileName: 'app.apk',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('sha256OfFile', () {
    test('计算本地文件 SHA-256 摘要', () async {
      final dir = await Directory.systemTemp.createTemp('ghx_sha_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/sample.apk');
      await file.writeAsString('abc');

      expect(
        await sha256OfFile(file.path),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });
  group('深链参数守卫', () {
    testWidgets('缺少 owner/name 时回落到未知路由页并提示参数缺失', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: AppRoutes.repoDetail('', ''),
          onGenerateRoute: buildRoute,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('没有找到这个页面'), findsOneWidget);
      expect(find.textContaining('缺少参数'), findsOneWidget);
    });

    testWidgets('缺少 number 的 Issue 详情深链同样被拦截', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: AppRoutes.repoIssueDetail('flutter', 'flutter', 0),
          onGenerateRoute: buildRoute,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('没有找到这个页面'), findsOneWidget);
      expect(find.textContaining('number'), findsOneWidget);
    });
  });

  group('verifyDownloadedApk 安装包校验', () {
    test('体积与摘要都匹配时通过', () {
      expect(
        () => verifyDownloadedApk(
          actualSize: 1024,
          actualSha256: 'ABCDEF',
          expectedSize: 1024,
          expectedSha256: 'abcdef',
        ),
        returnsNormally,
      );
    });

    test('空文件被拦截', () {
      expect(
        () => verifyDownloadedApk(actualSize: 0),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('安装包为空'),
          ),
        ),
      );
    });

    test('体积与 Release 记录不一致被拦截', () {
      expect(
        () => verifyDownloadedApk(actualSize: 900, expectedSize: 1024),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('安装包大小与 Release 记录不一致'),
          ),
        ),
      );
    });

    test('SHA-256 摘要不匹配被拦截', () {
      expect(
        () => verifyDownloadedApk(
          actualSize: 1024,
          actualSha256: 'deadbeef',
          expectedSize: 1024,
          expectedSha256: 'abcdef',
        ),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('SHA-256 摘要不匹配'),
          ),
        ),
      );
    });

    test('声明了摘要但本地未计算时同样视为不匹配', () {
      expect(
        () => verifyDownloadedApk(actualSize: 1024, expectedSha256: 'abcdef'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
