// 빈 홈에서 카드를 등록해 홈에 구간 배지가 보이기까지. 작업 005 계획 슬라이스 1의 8단계
// 서버는 가짜 클라이언트로 바꾼다. 응답은 서버 테스트 tests/api/test_cards.py의 값과 같다
import 'dart:convert';

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/main.dart';
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

const mrlife = {
  'id': 'shinhan-mrlife',
  'name': '신한카드 Mr.Life',
  'issuer': 'shinhan',
  'issuer_name': '신한카드',
  'kind': 'credit',
  'annual_fee': 15000,
  'tiers': [300000, 500000, 1000000],
};

class FakeServer {
  final added = <Map<String, dynamic>>[];
  final seen = <String>[];

  Future<http.Response> call(http.Request req) async {
    seen.add('${req.method} ${req.url.path}');
    switch ((req.method, req.url.path)) {
      case ('GET', '/me/home'):
        return ok({
          'month': '2026-09-01',
          'benefit_total': 0,
          'cards': [
            for (final _ in added)
              {
                'id': 'u1',
                'card_id': 'shinhan-mrlife',
                'name': '신한카드 Mr.Life',
                'issuer_name': '신한카드',
                'tiers': [300000, 500000, 1000000],
                'headline': '전기·가스·통신요금 10% 할인',
                'spend': {
                  'counted': 0,
                  'tier': 300000,
                  'tier_source': 'assumed',
                  'prev_month_counted': 410000,
                  'to_keep': 300000,
                  'next_tier': 500000,
                  'to_next': 500000,
                  'warnings': [],
                },
              },
          ],
        });
      case ('GET', '/catalog/issuers'):
        return ok([
          {'code': 'shinhan', 'name': '신한카드'},
        ]);
      case ('GET', '/catalog/cards'):
        return ok([mrlife]);
      case ('GET', '/catalog/cards/shinhan-mrlife/preview'):
        final prev = int.tryParse(req.url.queryParameters['prev'] ?? '');
        final tier = prev != null && prev >= 300000 ? 300000 : 0;
        return ok({
          'tier': tier,
          'tier_source': prev == null ? 'prev_month' : 'assumed',
          'tiers': [300000, 500000, 1000000],
          'benefits': tier == 0
              ? []
              : ['전기·가스·통신요금 10% 할인', '편의점 10% 할인', '병원·약국 10% 할인'],
          'warnings': [],
        });
      case ('POST', '/me/cards'):
        added.add(jsonDecode(req.body));
        return ok({'id': 'u1'}, 201);
    }
    return ok({'detail': 'not found'}, 404);
  }
}

void main() {
  testWidgets('빈 홈에서 카드를 등록하면 홈에 구간 배지가 보인다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer();
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();

    // 1a 빈 홈
    expect(find.text('첫 카드를 등록해 보세요'), findsOneWidget);
    expect(find.text('0원'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '카드 추가'));
    await tester.pumpAndSettle();

    // 2 카드 추가
    expect(find.text('신용 · 연회비 1.5만 · 실적 30/50/100만'), findsOneWidget);
    await tester.tap(find.text('신한카드 Mr.Life'));
    await tester.pumpAndSettle();

    // 등록 시트. 비우면 구간 전, 41만을 넣으면 30만 구간
    expect(find.text('신한카드 Mr.Life 등록'), findsOneWidget);
    expect(find.text('이번 달은 혜택 구간 전이에요. 30만부터 받아요'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('prev')), '410000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('이번 달은 30만 구간이 적용돼요'), findsOneWidget);
    expect(find.text('전기·가스·통신요금 10% 할인, 편의점 10% 할인 외 1개'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();

    // 1 홈
    expect(server.added.single, {
      'card_id': 'shinhan-mrlife',
      'assumed_prev_month_spend': 410000,
      'started_on': null,
    });
    expect(find.text('30만 구간'), findsOneWidget);
    expect(find.text('30만 더 쓰면 유지'), findsOneWidget);
    expect(find.text('9월'), findsOneWidget);
  });

  testWidgets('토큰이 없으면 시작 화면이고 개발용 버튼은 켤 때만 보인다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = Api(
      client: MockClient((r) async => ok({}, 404)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api, devLogin: false));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 시작'), findsOneWidget);
    expect(find.text('개발용으로 시작'), findsNothing);
  });

  testWidgets('토큰이 끝났으면 시작 화면으로 돌아간다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 'old'});
    final api = Api(
      client: MockClient((r) async => ok({'detail': '로그인이 필요하다'}, 401)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api, devLogin: false));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 시작'), findsOneWidget);
    expect(await api.restore(), false);
  });

  testWidgets('등록 시트에서 토큰이 끝나면 시트와 카드 추가 화면이 닫히고 시작 화면이 보인다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer();
    final api = Api(
      client: MockClient(
        (r) async =>
            r.method == 'POST' ? ok({'detail': '로그인이 필요하다'}, 401) : server(r),
      ),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api, devLogin: false));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '카드 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신한카드 Mr.Life'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 시작'), findsOneWidget);
    expect(find.text('신한카드 Mr.Life 등록'), findsNothing);
  });
}
