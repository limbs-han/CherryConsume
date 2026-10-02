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
  int cancelled = 0,
}) => {
  'id': id,
  'paid_at': '2026-09-15T21:00:00+09:00',
  'merchant_name': name,
  'category': category,
  'category_name': category == null ? null : '편의점',
  'user_card_id': 'u1',
  'card_name': '신한카드 Mr.Life',
  'amount': amount,
  'cancelled_amount': cancelled,
  'cancelled_at': cancelled > 0 ? '2026-09-15T21:10:00+09:00' : null,
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
  final cancels = <Map<String, dynamic>>[];
  final answers = <String, Map<String, dynamic>>{};
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
            row('t2', '상품권', 10000, 0, counted: false, cancelled: 3000),
          ],
        });
      case ('POST', '/me/payments/t1/cancel'):
        cancels.add(jsonDecode(req.body) as Map<String, dynamic>);
        return ok({'detail': '다른 달에 더 취소한 금액은 아직 담지 못한다'}, 422);
      case ('POST', '/me/payments/t2/cancel'):
        cancels.add(jsonDecode(req.body) as Map<String, dynamic>);
        return ok({'id': 't2', 'value': 0, 'repriced': 0});
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
          'questions': {
            'facts': [
              {
                'key': 'instant_pay',
                'type': 'bool',
                'ask': '이 카드로 쓴 일시불 금액을 그 달 안에 즉시결제하나요',
                'choices': null,
                'answer': null,
              },
            ],
            'options': [
              {
                'key': 'package',
                'title': '라이프스타일 옵션 패키지',
                'choices': [
                  {'key': 'p1', 'title': '패키지 1'},
                  {'key': 'p4', 'title': '패키지 4'},
                ],
                'default': null,
                'unsupported': <String>[],
                'change': 'next_month',
                'answer': 'p1',
                'pending': {'value': 'p4', 'from': '2026-10-01'},
              },
            ],
          },
          'registered_on': '2026-09-15',
          'revision_from': '2026-07-15',
          'checked_at': '2026-09-29',
        });
      case ('PUT', '/me/cards/u1/answers'):
        answers['card'] = jsonDecode(req.body) as Map<String, dynamic>;
        return ok({'repriced': 2});
      case ('GET', '/me/facts'):
        return ok([
          {
            'key': 'soldier',
            'type': 'bool',
            'ask': '현역병으로 인정되었나요?',
            'choices': null,
            'answer': null,
            'cards': ['IBK나라사랑카드'],
          },
        ]);
      case ('PUT', '/me/facts'):
        answers['user'] = jsonDecode(req.body) as Map<String, dynamic>;
        return ok({'repriced': 0});
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

  testWidgets('취소 기록은 빈 칸에서 시작하고 다른 달 추가 취소는 담지 못한다고 알린다', (tester) async {
    final server = await start(tester);
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GS25'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소 기록'));
    await tester.pumpAndSettle();

    // 처음 값이 전액이면 누르기만 해도 전액 취소가 된다. 비워 둔다. 위험 검토 16번
    final field = tester.widget<TextField>(
      find.byKey(const Key('cancel-amount')),
    );
    expect(field.controller!.text, '');
    expect(find.textContaining('취소한 날'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cancel-amount')), '2000');
    await tester.tap(find.widgetWithText(FilledButton, '기록'));
    await tester.pumpAndSettle();

    // 오늘을 고르면 지금보다 뒤가 아닌 시각을 보낸다
    expect(server.cancels.single['cancelled_amount'], 2000);
    final at = DateTime.parse(server.cancels.single['cancelled_at']);
    expect(at.isAfter(DateTime.now()), isFalse);
    expect(find.text('다른 달에 더 취소된 금액은 아직 담지 못해요.'), findsOneWidget);
  });

  testWidgets('이미 취소된 결제는 이번 금액을 더해 보내고 취소 기록을 지울 수 있다', (tester) async {
    final server = await start(tester);
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();

    Future<void> openCancel() async {
      await tester.tap(find.text('상품권'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소 기록'));
      await tester.pumpAndSettle();
    }

    // 지금까지 3,000원이 취소됐다. 이번에 2,000원이 더 취소되면 합 5,000원을 보낸다
    await openCancel();
    expect(find.textContaining('지금까지 3,000원 취소'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cancel-amount')), '2000');
    await tester.tap(find.widgetWithText(FilledButton, '기록'));
    await tester.pumpAndSettle();
    expect(server.cancels.last['cancelled_amount'], 5000);

    // 위험 검토 16번. 취소 기록 지우기는 0원을 보낸다
    await openCancel();
    await tester.tap(find.byKey(const Key('cancel-undo')));
    await tester.pumpAndSettle();
    expect(server.cancels.last['cancelled_amount'], 0);
  });

  testWidgets('카드 정보에서 카드 사실과 옵션을 답하고 설정에서 사람 사실을 답한다', (tester) async {
    final server = await start(tester);
    await tester.tap(find.text('신한카드 Mr.Life'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('카드 정보'), 300);
    await tester.pumpAndSettle();

    // 다음 달부터 바뀌는 옵션은 그 날과 함께 보인다. E56
    expect(find.text('쓰기 시작한 날을 몰라요'), findsOneWidget);
    expect(find.text('10월 1일부터 패키지 4'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('예'), 100);
    await tester.tap(find.text('예'));
    await tester.pumpAndSettle();
    expect(server.answers['card'], {
      'facts': {'instant_pay': true},
    });
    expect(find.text('결제 2건의 혜택을 다시 계산했어요.'), findsOneWidget);
    expect(find.text('답을 적지 못했어요.'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.text('쓰는 카드 · IBK나라사랑카드'), findsOneWidget);
    await tester.tap(find.text('예'));
    await tester.pumpAndSettle();
    expect(server.answers['user'], {
      'facts': {'soldier': true},
    });
    expect(find.text('답을 적었어요.'), findsOneWidget);
    expect(find.text('답을 적지 못했어요.'), findsNothing);
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
