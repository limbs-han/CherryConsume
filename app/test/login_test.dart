// 카카오와 Google로 시작, 로그아웃, 탈퇴. 작업 005 설계 5g. S1, E27, E29, E36
import 'dart:convert';

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response ok(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class FakeSocial extends Social {
  FakeSocial({
    this.kakaoToken = 'kakao1',
    this.googleToken = 'google1',
  });
  final String? kakaoToken, googleToken;
  final unlinked = <String>[];
  final signedOut = <String>[];

  @override
  Future<String?> kakao() async => kakaoToken;

  @override
  Future<String?> google() async => googleToken;

  @override
  Future<void> unlink(String provider) async => unlinked.add(provider);

  @override
  Future<void> signOut(String provider) async => signedOut.add(provider);
}

class FakeServer {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};

  Future<http.Response> call(http.Request req) async {
    calls.add('${req.method} ${req.url.path}');
    switch ((req.method, req.url.path)) {
      case ('POST', '/auth/kakao'):
        bodies['kakao'] = jsonDecode(req.body);
        return ok({'token': 'session'});
      case ('POST', '/auth/google'):
        return ok({'detail': '탈퇴한 계정이에요. 탈퇴하고 30일이 지나면 다시 가입할 수 있어요'}, 403);
      case ('GET', '/me/home'):
        return ok({'month': '2026-09-01', 'benefit_total': 0, 'cards': []});
      case ('GET', '/me/account'):
        return ok({
          'provider': 'kakao',
          'created_at': '2026-09-15T03:00:00+00:00',
        });
      case ('GET', '/me/facts'):
        return ok(<Object>[]);
      case ('DELETE', '/me'):
        return ok({'deleted': true});
      case ('POST', '/auth/logout'):
        return http.Response('', 204);
    }
    return ok({'detail': 'not found'}, 404);
  }
}

Future<(FakeServer, FakeSocial)> start(
  WidgetTester tester, {
  FakeSocial? social,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final server = FakeServer();
  final s = social ?? FakeSocial();
  final api = Api(client: MockClient((r) => server(r)), baseUrl: 'http://test');
  await tester.pumpWidget(CherryApp(api: api, social: s));
  await tester.pumpAndSettle();
  return (server, s);
}

void main() {
  testWidgets('카카오로 시작하면 서버에 카카오 토큰을 보내고 홈으로 간다', (tester) async {
    final (server, _) = await start(tester);
    // E29. 다른 수단으로 들어오면 새 계정이라고 미리 알린다
    expect(
      find.text('전에 쓴 수단으로 로그인해 주세요. 다른 수단으로 들어오면 새 계정이에요.'),
      findsOneWidget,
    );
    await tester.tap(find.text('카카오로 시작'));
    await tester.pumpAndSettle();
    expect(server.bodies['kakao'], {'access_token': 'kakao1'});
    expect(server.calls, contains('GET /me/home'));
    expect(find.text('카카오로 시작'), findsNothing);
  });

  testWidgets('탈퇴한 계정은 서버가 준 까닭을 보이고, 그만두면 아무것도 보내지 않는다', (tester) async {
    final (server, _) = await start(
      tester,
      social: FakeSocial(kakaoToken: null),
    );
    await tester.tap(find.text('Google로 시작'));
    await tester.pumpAndSettle();
    expect(find.text('탈퇴한 계정이에요. 탈퇴하고 30일이 지나면 다시 가입할 수 있어요'), findsOneWidget);
    await tester.tap(find.text('카카오로 시작'));
    await tester.pumpAndSettle();
    expect(server.calls.where((c) => c == 'POST /auth/kakao'), isEmpty);
    expect(find.text('카카오로 시작'), findsOneWidget);
  });

  testWidgets('설정에서 탈퇴하면 서버에 알리고 카카오 연결을 끊고 시작 화면으로 간다', (tester) async {
    final (server, social) = await start(tester);
    await tester.tap(find.text('카카오로 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 로그인했어요'), findsOneWidget);
    await tester.tap(find.text('탈퇴'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '탈퇴'));
    await tester.pumpAndSettle();
    expect(server.calls, contains('DELETE /me'));
    expect(social.unlinked, ['kakao']);
    expect(find.text('카카오로 시작'), findsOneWidget);
  });

  testWidgets('로그아웃하면 시작 화면으로 간다', (tester) async {
    final (server, social) = await start(tester);
    await tester.tap(find.text('카카오로 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(server.calls, contains('POST /auth/logout'));
    // 카카오의 로그인 상태도 지워 폰에 카카오 토큰이 남지 않는다
    expect(social.signedOut, ['kakao']);
    expect(find.text('카카오로 시작'), findsOneWidget);
  });
}
