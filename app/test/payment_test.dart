// 홈에서 결제를 기록하면 홈 숫자가 바뀌기까지. 작업 005 계획 슬라이스 2의 5단계. S3
// 응답 숫자는 서버 테스트 tests/api/test_payments.py와 같다. GS25 4,300원은 Mr.Life 편의점 10%로 430원
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

class FakeServer {
  Map<String, dynamic>? saved;

  /// 켜면 저장 직전의 저장 전 결제가 다른 1순위를 준다
  bool flip = false;

  Map<String, dynamic> home() => {
    'month': '2026-09-01',
    'benefit_total': saved == null ? 0 : 430,
    'cards': [
      {
        'id': 'u1',
        'card_id': 'shinhan-mrlife',
        'name': '신한카드 Mr.Life',
        'issuer_name': '신한카드',
        'tiers': [300000, 500000, 1000000],
        'headline': null,
        'spend': {
          'counted': saved == null ? 0 : 4300,
          'tier': 300000,
          'tier_source': 'assumed',
          'prev_month_counted': 410000,
          'to_keep': saved == null ? 300000 : 295700,
          'next_tier': 500000,
          'to_next': saved == null ? 500000 : 495700,
          'warnings': [],
        },
      },
    ],
  };

  Map<String, dynamic> draft(Map<String, dynamic> b) {
    final gs = (b['merchant_name'] ?? '').toString().contains('GS25');
    return {
      'merchant': gs ? 'gs25' : null,
      'category': b['category'] ?? (gs ? 'convenience' : null),
      'merchant_display': gs ? 'GS25' : null,
      'category_name': gs ? '편의점' : null,
      // GS25의 기본 청구 방식을 자동납부로 꾸며 요약 줄에 서버 값이 보이는지 본다
      'billing': gs ? 'autopay' : null,
      'channel': 'offline',
      'paid_at': '2026-09-15T12:00:00+00:00',
      'ranking': [
        {'user_card_id': 'u1', 'name': '신한카드 Mr.Life', 'value': gs ? 1000 : 0},
      ],
      'pick': flip ? 'u2' : 'u1',
      'estimate': b['amount'] == null
          ? null
          : {
              'user_card_id': 'u1',
              'payment_method': 'physical_card',
              'value': gs ? 430 : 0,
              'benefits': gs
                  ? [
                      {
                        'key': 'time-convenience',
                        'title': '편의점 10% 할인',
                        'amount': 430,
                        'value': 430,
                      },
                    ]
                  : [],
              'counted': true,
              'warnings': [],
            },
    };
  }

  Future<http.Response> call(http.Request req) async {
    switch ((req.method, req.url.path)) {
      case ('GET', '/me/home'):
        return ok(home());
      case ('GET', '/catalog/categories'):
        return ok([
          {'code': 'convenience', 'name': '편의점', 'children': []},
        ]);
      case ('GET', '/catalog/payment-methods'):
        return ok([
          {'key': 'physical_card', 'name': '실물카드'},
          {'key': 'naver_pay', 'name': '네이버페이'},
        ]);
      case ('POST', '/me/payments/draft'):
        return ok(draft(jsonDecode(req.body)));
      case ('POST', '/me/payments'):
        saved = jsonDecode(req.body);
        return ok({
          'id': 't1',
          'repriced': 1,
          'value': 430,
          'benefits': [],
          'counted': true,
          'warnings': [],
        }, 201);
    }
    return ok({'detail': 'not found'}, 404);
  }
}

void main() {
  testWidgets('결제를 기록하면 1순위 카드가 골라지고 저장 뒤 홈 숫자가 바뀐다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer();
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('30만 더 쓰면 유지'), findsOneWidget);

    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '4300');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25 테헤란점');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('이 가게에선 신한카드 Mr.Life가 가장 이득이라 골라 뒀어요'), findsOneWidget);
    expect(find.text('430원'), findsOneWidget);
    expect(find.text('편의점 10% 할인'), findsOneWidget);
    expect(find.text('오프라인 · 일시불 · 실물카드 · 자동납부'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    final s = server.saved!;
    // 업종과 채널은 사용자가 고르지 않았으면 보내지 않는다. 서버가 가게 이름으로 채운다
    expect(
      (
        s['user_card_id'],
        s['amount'],
        s['merchant_name'],
        s['category'],
        s['channel'],
        s['interest_free'],
      ),
      ('u1', 4300, 'GS25 테헤란점', null, null, false),
    );
    expect((s['paid_at'] as String).endsWith('Z'), isTrue);

    // 홈. 받은 혜택 430원, 30만 구간까지 295,700원은 천 원 아래를 올려 29.6만
    expect(find.text('430원'), findsOneWidget);
    expect(find.text('29.6만 더 쓰면 유지'), findsOneWidget);
    // 앞선 결제를 넣어 다른 결제의 혜택이 바뀌면 알린다. E52
    expect(find.text('다른 결제 1건의 혜택도 다시 계산했어요.'), findsOneWidget);
  });

  testWidgets('저장 직전에 1순위가 바뀌면 저장하지 않고 알린다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer();
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '4300');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    server.flip = true;
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(server.saved, isNull);
    expect(find.text('가장 이득인 카드가 바뀌었어요. 확인하고 다시 저장해 주세요.'), findsOneWidget);
  });
}
