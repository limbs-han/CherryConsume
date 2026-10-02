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

  /// 켜면 저장 응답이 자식 업종을 묻는다. E47
  bool askCategory = false;
  bool failEdit = false;
  Map<String, dynamic>? edited;
  int saves = 0;

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
        saves++;
        saved = jsonDecode(req.body);
        return ok({
          'id': 't1',
          'repriced': 1,
          'value': 430,
          'benefits': [],
          'counted': true,
          'warnings': [],
          'ask_category': askCategory
              ? {
                  'parent': 'telecom',
                  'parent_name': '통신요금',
                  'children': [
                    {'code': 'telecom.internet_tv', 'name': '인터넷·TV'},
                    {'code': 'telecom.mobile', 'name': '이동통신'},
                  ],
                }
              : null,
        }, 201);
      case ('PATCH', '/me/payments/t1'):
        if (failEdit) return ok({'detail': 'down'}, 500);
        edited = jsonDecode(req.body);
        return ok({
          'id': 't1',
          'value': 2000,
          'repriced': 0,
          'ask_category': null,
        });
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

  testWidgets('업종이 부모까지만 있으면 저장한 자리에서 자식 업종을 묻는다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer()..askCategory = true;
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '50000');
    await tester.enterText(find.byKey(const Key('merchant')), 'KT 요금');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    // E47. 한 번 묻고, 답하면 그 결제의 업종만 고친다
    expect(find.text('KT 요금은 통신요금 가운데 어느 쪽인가요'), findsOneWidget);
    await tester.tap(find.text('이동통신'));
    await tester.pumpAndSettle();
    expect(server.edited!['category'], 'telecom.mobile');
    expect(find.text('KT 요금은 통신요금 가운데 어느 쪽인가요'), findsNothing);
  });

  testWidgets('자식 업종 고치기가 실패해도 저장한 결제라 화면을 닫는다', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final server = FakeServer()
      ..askCategory = true
      ..failEdit = true;
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '50000');
    await tester.enterText(find.byKey(const Key('merchant')), 'KT 요금');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이동통신'));
    await tester.pumpAndSettle();

    // 재검토 중간 1번. 남겨 두면 다시 눌러 같은 결제가 두 건이 된다
    expect(find.text('저장했지만 업종은 고치지 못했어요. 기록에서 고쳐 주세요.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장'), findsNothing);
    expect(server.saves, 1);
  });
}
