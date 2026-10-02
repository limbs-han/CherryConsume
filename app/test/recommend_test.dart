// 추천 탭에서 업종별 1순위, 추천 결과, 추천에서 결제 기록까지. 작업 005 계획 슬라이스 3의 3단계. S4
// 응답 숫자는 서버 테스트 tests/api/test_recommend.py와 같다. 21시 카페 1만 원은 Mr.Life 1,000원, ZERO 80원
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

Map<String, dynamic> rec(String id, String name, int value, String? title) => {
  'user_card_id': id,
  'name': name,
  'value': value,
  'title': title,
  'rewards': ['billing_discount'],
  'limited': false,
  'pay_with': <Object>[],
  'exhausted': false,
  'provisional': false,
};

class FakeServer {
  FakeServer({this.cards = true});
  final bool cards;
  Map<String, dynamic>? saved;
  int recommends = 0;

  Future<http.Response> call(http.Request req) async {
    switch ((req.method, req.url.path)) {
      case ('GET', '/me/home'):
        return ok({'month': '2026-09-01', 'benefit_total': 0, 'cards': []});
      case ('GET', '/me/recommendations/top'):
        return ok(
          cards
              ? [
                  {
                    'category': 'cafe',
                    'category_name': '카페',
                    ...rec('u1', '신한카드 Mr.Life', 1000, '야간 식음료 10% 할인'),
                  },
                ]
              : [],
        );
      case ('GET', '/me/recent-merchants'):
        return ok(['GS25 테헤란점']);
      case ('GET', '/me/facts'):
        return ok(<Object>[]);
      case ('POST', '/me/recommendations'):
        recommends++;
        return ok({
          'request_id': 'r1',
          'merchant': null,
          'merchant_display': null,
          'category': 'cafe',
          'category_name': '카페',
          'amount': null,
          'ranking': [
            rec('u1', '신한카드 Mr.Life', 1000, '야간 식음료 10% 할인'),
            {
              ...rec('u2', '현대카드 ZERO Edition3', 80, '국내외 가맹점 0.8% 할인'),
              'pay_with': [
                {'payment_method': 'naver_pay', 'name': '네이버페이', 'extra': 1000},
              ],
              'ask': [
                {
                  'kind': 'fact',
                  'key': 'soldier',
                  'scope': 'user',
                  'question': '현역병으로 인정되었나요?',
                  'extra': 3000,
                },
              ],
            },
          ],
        });
      case ('GET', '/catalog/categories'):
        return ok([
          {'code': 'cafe', 'name': '카페', 'children': []},
        ]);
      case ('GET', '/catalog/payment-methods'):
        return ok([
          {'key': 'physical_card', 'name': '실물카드'},
        ]);
      case ('POST', '/me/payments/draft'):
        // 추천 요청 id는 저장에만 간다. 서버의 저장 전 결제는 모르는 칸을 422로 막는다
        expect(
          (jsonDecode(req.body) as Map).containsKey(
            'recommendation_request_id',
          ),
          isFalse,
        );
        return ok({
          'merchant': null,
          'merchant_display': null,
          'category': 'cafe',
          'category_name': '카페',
          'channel': 'offline',
          'paid_at': '2026-09-15T12:00:00+00:00',
          'ranking': [
            {'user_card_id': 'u1', 'name': '신한카드 Mr.Life', 'value': 1000},
          ],
          'pick': 'u1',
          'estimate': null,
        });
      case ('POST', '/me/payments'):
        saved = jsonDecode(req.body);
        return ok({
          'id': 't1',
          'repriced': 0,
          'value': 1000,
          'benefits': [],
          'counted': true,
          'warnings': [],
        }, 201);
    }
    return ok({'detail': 'not found'}, 404);
  }
}

void main() {
  testWidgets('업종별 1순위에서 추천 결과를 보고 1순위 카드로 결제를 기록하면 추천 요청 id가 간다', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer();
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추천'));
    await tester.pumpAndSettle();
    expect(find.text('어디서 결제하세요?'), findsOneWidget);
    expect(find.text('GS25 테헤란점'), findsOneWidget);
    expect(find.text('신한카드 Mr.Life · 야간 식음료 10% 할인'), findsOneWidget);

    await tester.tap(find.text('카페'));
    await tester.pumpAndSettle();
    expect(find.text('1,000원 할인'), findsOneWidget);
    expect(find.text('80원 할인'), findsOneWidget);
    expect(find.text('네이버페이로 내면 1,000원 더 받아요'), findsOneWidget);
    // 사실을 답하면 더 받는 금액. 누르면 답하는 곳으로 가고, 돌아오면 다시 추천한다. 작업 005 설계 5e
    final ask = find.text('답하면 3,000원 더 받아요 · 현역병으로 인정되었나요?');
    expect(ask, findsOneWidget);
    final before = server.recommends;
    await tester.tap(ask);
    await tester.pumpAndSettle();
    expect(find.text('혜택 계산에 쓰는 답'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(server.recommends, before + 1);

    await tester.tap(find.text('이 카드로 결제 기록'));
    await tester.pumpAndSettle();
    expect(find.text('결제 기록'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '10000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final s = server.saved!;
    expect(
      (
        s['user_card_id'],
        s['amount'],
        s['category'],
        s['recommendation_request_id'],
      ),
      ('u1', 10000, 'cafe', 'r1'),
    );
    // 저장하면 추천 결과를 닫고 추천 첫 화면으로 돌아간다
    expect(find.text('어디서 결제하세요?'), findsOneWidget);
  });

  testWidgets('카드가 없으면 추천 탭에 카드 추가가 보인다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer(cards: false);
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추천'));
    await tester.pumpAndSettle();
    expect(find.text('등록된 카드가 없어요'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '카드 추가'), findsOneWidget);
  });

  testWidgets('금액을 적고 확인 없이 결제 기록을 누르면 그 금액으로 다시 계산하고 열지 않는다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer();
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추천'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카페'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '150000');
    await tester.tap(find.text('이 카드로 결제 기록'));
    await tester.pumpAndSettle();
    expect(find.text('적은 금액으로 다시 계산했어요. 1순위를 확인하고 눌러 주세요.'), findsOneWidget);
    expect(find.text('결제 기록'), findsNothing);
  });
}
