// 기록 탭, 결제 지우기, 카드 상세와 해지. 작업 005 계획 슬라이스 4의 4단계. S7, S8, S9
// 응답 숫자는 서버 테스트 tests/api/test_records.py와 같다
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

Map<String, dynamic> row(
  String id,
  String name,
  int amount,
  int value, {
  bool counted = true,
  String? category,
}) => {
  'id': id,
  'paid_at': '2026-09-15T21:00:00+09:00',
  'merchant_name': name,
  'category': category,
  'category_name': category == null ? null : '편의점',
  'user_card_id': 'u1',
  'card_name': '신한카드 Mr.Life',
  'amount': amount,
  'cancelled_amount': 0,
  'value': value,
  'rewards': value > 0 ? ['billing_discount'] : <String>[],
  'counted': counted,
  'channel': 'offline',
  'region': 'domestic',
  'installment_months': 1,
  'interest_free': false,
  'payment_method': 'physical_card',
  'billing': 'normal',
};

class FakeServer {
  final calls = <String>[];
  final drafts = <Map<String, dynamic>>[];
  bool removed = false;

  Future<http.Response> call(http.Request req) async {
    calls.add('${req.method} ${req.url.path}');
    switch ((req.method, req.url.path)) {
      case ('GET', '/me/home'):
        return ok({
          'month': '2026-09-01',
          'benefit_total': 430,
          'cards': [
            if (!removed)
              {
                'id': 'u1',
                'card_id': 'shinhan-mrlife',
                'name': '신한카드 Mr.Life',
                'issuer_name': '신한카드',
                'tiers': [300000, 500000, 1000000],
                'headline': null,
                'spend': {
                  'counted': 4300,
                  'tier': 300000,
                  'tier_source': 'assumed',
                  'prev_month_counted': 410000,
                  'to_keep': 295700,
                  'next_tier': 500000,
                  'to_next': 495700,
                  'warnings': [],
                },
              },
          ],
        });
      case ('GET', '/me/payments'):
        return ok({
          'month': '2026-09-01',
          'count': 2,
          'amount': 14300,
          'benefit_total': 430,
          'cards': [
            {'id': 'u1', 'name': '신한카드 Mr.Life'},
          ],
          'payments': [
            row('t1', 'GS25', 4300, 430, category: 'convenience'),
            row('t2', '상품권', 10000, 0, counted: false),
          ],
        });
      case ('DELETE', '/me/payments/t1'):
        return ok({'id': 't1', 'repriced': 1});
      case ('GET', '/catalog/categories'):
        return ok([
          {'code': 'convenience', 'name': '편의점', 'children': []},
        ]);
      case ('GET', '/catalog/payment-methods'):
        return ok([
          {'key': 'physical_card', 'name': '실물카드'},
        ]);
      case ('POST', '/me/payments/draft'):
        drafts.add(jsonDecode(req.body) as Map<String, dynamic>);
        return ok({
          'merchant': 'gs25',
          'merchant_display': 'GS25',
          'category': 'convenience',
          'category_name': '편의점',
          'channel': 'offline',
          'billing': 'normal',
          'paid_at': '2026-09-15T12:00:00+00:00',
          'ranking': [
            {'user_card_id': 'u1', 'name': '신한카드 Mr.Life', 'value': 430},
          ],
          'pick': 'u1',
          'estimate': null,
        });
      case ('GET', '/me/cards/u1'):
        return ok({
          'id': 'u1',
          'card_id': 'shinhan-mrlife',
          'name': '신한카드 Mr.Life',
          'issuer_name': '신한카드',
          'tiers': [300000, 500000, 1000000],
          'spend': {
            'counted': 4300,
            'tier': 300000,
            'tier_source': 'assumed',
            'prev_month_counted': 410000,
            'to_keep': 295700,
            'next_tier': 500000,
            'to_next': 495700,
            'warnings': [],
          },
          'limits': [
            {
              'title': '편의점 10% 할인',
              'per': 'month',
              'used_amount': 430,
              'cap_amount': null,
              'used_count': 1,
              'cap_count': 5,
              'used_base': 4300,
              'cap_base': null,
            },
            {
              'title': '통합 한도',
              'per': 'month',
              'used_amount': 430,
              'cap_amount': 10000,
              'used_count': 1,
              'cap_count': null,
              'used_base': 4300,
              'cap_base': null,
            },
            {
              'title': '주말 주유 리터당 60원 할인',
              'per': 'month',
              'used_amount': 0,
              'cap_amount': null,
              'used_count': 0,
              'cap_count': null,
              'used_base': 100000,
              'cap_base': 300000,
            },
            {
              'title': 'PX 할인',
              'per': 'month',
              'used_amount': 6000,
              'cap_amount': 50000,
              'used_count': 2,
              'cap_count': 2,
              'used_base': 60000,
              'cap_base': null,
            },
            {
              'title': '영화 할인',
              'per': 'year',
              'used_amount': 0,
              'cap_amount': null,
              'used_count': 5,
              'cap_count': 4,
              'used_base': 0,
              'cap_base': null,
            },
          ],
          'locked': [],
          'check_sentences': ['일부 혜택은 원문 조건을 문장으로만 담았어요'],
          'assumed_count': 2,
          'started_on': null,
          'registered_on': '2026-09-15',
          'revision_from': '2026-07-15',
          'checked_at': '2026-09-29',
        });
      case ('DELETE', '/me/cards/u1'):
        removed = true;
        return ok({'id': 'u1'});
    }
    return ok({'detail': 'not found'}, 404);
  }
}

Future<FakeServer> start(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({'token': 't'});
  final server = FakeServer();
  final api = Api(client: MockClient((r) => server(r)), baseUrl: 'http://test');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  testWidgets('기록 탭에 그 달 결제와 합계가 보이고, 결제를 지우면 다시 계산 알림이 뜬다', (tester) async {
    final server = await start(tester);
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    // 2건, 14,300원은 천 원 아래를 올려 1.5만 원. 혜택 430원
    expect(find.text('2건 · 1.5만 원'), findsOneWidget);
    expect(find.text('혜택 430원'), findsOneWidget);
    expect(find.text('430원 할인'), findsOneWidget);
    expect(find.text('혜택 없음'), findsOneWidget);
    expect(find.text('실적 제외'), findsOneWidget);

    await tester.tap(find.text('GS25'));
    await tester.pumpAndSettle();
    expect(find.text('결제 고치기'), findsOneWidget);
    // 고치는 화면의 예상 혜택은 이 결제의 옛 값을 빼고 계산한다
    expect(server.drafts.last['editing'], 't1');
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();

    expect(server.calls, contains('DELETE /me/payments/t1'));
    expect(find.text('다른 결제 1건의 혜택도 다시 계산했어요.'), findsOneWidget);
  });

  testWidgets('홈의 카드를 누르면 카드 상세에 남은 한도가 보이고 해지하면 홈에서 빠진다', (tester) async {
    final server = await start(tester);
    await tester.tap(find.text('신한카드 Mr.Life'));
    await tester.pumpAndSettle();

    // 편의점 월 5회 가운데 1회를 써 4회, 통합 한도 1만 원 가운데 430원을 써 9,570원이 남았다
    expect(find.text('이번 달 4회 남음'), findsOneWidget);
    expect(find.text('이번 달 9,570원 남음'), findsOneWidget);
    // 결제액 한도만 있는 줄도 보이고, 한도를 넘겨 쓴 줄은 0으로 보인다. 금액과 횟수가 함께 있으면 먼저 끝나는 쪽이다
    expect(find.text('이번 달 결제액 200,000원 남음'), findsOneWidget);
    expect(find.text('올해 0회 남음'), findsOneWidget);
    expect(find.text('이번 달 0회 남음'), findsOneWidget);
    expect(find.text('지금 적용 중 · 30만 구간 · 전월 41만 기준'), findsOneWidget);
    expect(find.text('카드사 공식 문구로 확인하지 못한 값 2개는 추정으로 계산해요.'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카드 해지'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '해지'));
    await tester.pumpAndSettle();

    expect(server.calls, contains('DELETE /me/cards/u1'));
    expect(find.text('첫 카드를 등록해 보세요'), findsOneWidget);
  });
}
