// 서버에 닿지 못할 때. 작업 005 계획 슬라이스 9, 설계 5i. E24, E26
import 'dart:async';
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

const idA = '0b7e9a52-6c1d-4a7e-9a3f-2f4c1b8d9e10';
const idB = '7c1f2e3d-4b5a-4c6d-8e7f-9a0b1c2d3e4f';

class FakeServer {
  /// 켜면 모든 요청이 연결 실패다
  bool down = false;

  /// 켜면 요청이 답 없이 멈춘다
  bool hang = false;

  /// 켜면 결제를 넣고 답은 끊긴다
  bool loseAnswer = false;

  /// 켜면 결제 저장이 404다. 해지한 카드의 결제가 그렇다
  bool rejectSave = false;

  /// 켜면 사용자 경로가 401이다. 다른 기기에서 탈퇴했다
  bool unauthorized = false;

  /// 이 번호의 결제는 늘 500이다
  final failFor = <String>{};

  /// 켜면 모든 요청이 503이다. 서버 전체 장애다
  bool broken = false;

  /// 켜면 결제 저장이 409다. 같은 번호의 다른 결제가 있다
  bool conflict = false;

  /// 서버처럼 같은 번호는 한 번만 넣는다
  final rows = <String, Map<String, dynamic>>{};
  final tries = <String, int>{};

  Map<String, dynamic> home() => {
    'month': '2026-09-01',
    'benefit_total': rows.isEmpty ? 0 : 430,
    'cards': [
      {
        'id': 'u1',
        'card_id': 'shinhan-mrlife',
        'name': '신한카드 Mr.Life',
        'issuer_name': '신한카드',
        'tiers': [300000, 500000, 1000000],
        'headline': null,
        'spend': {
          'counted': rows.isEmpty ? 0 : 4300,
          'tier': 300000,
          'tier_source': 'assumed',
          'prev_month_counted': 410000,
          'to_keep': rows.isEmpty ? 300000 : 295700,
          'next_tier': 500000,
          'to_next': rows.isEmpty ? 500000 : 495700,
          'warnings': [],
        },
      },
    ],
  };

  Future<http.Response> call(http.Request req) async {
    if (down) throw http.ClientException('연결 실패', req.url);
    if (hang) return Completer<http.Response>().future;
    if (broken) return ok({'detail': 'down'}, 503);
    if (unauthorized && req.url.path.startsWith('/me')) {
      return ok({'detail': '로그인이 필요하다'}, 401);
    }
    switch ((req.method, req.url.path)) {
      case ('GET', '/me/home'):
        return ok(home());
      case ('POST', '/me/payments/draft'):
        return ok({
          'merchant': null,
          'category': null,
          'merchant_display': null,
          'category_name': null,
          'billing': null,
          'channel': 'offline',
          'paid_at': '2026-09-15T12:00:00+00:00',
          'ranking': [
            {'user_card_id': 'u1', 'name': '신한카드 Mr.Life', 'value': 0},
          ],
          'pick': 'u1',
          'estimate': null,
        });
      case ('POST', '/me/payments'):
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        final id = b['client_id'] as String;
        tries[id] = (tries[id] ?? 0) + 1;
        if (failFor.contains(id)) return ok({'detail': 'boom'}, 500);
        if (rejectSave) return ok({'detail': '보유 카드가 아니다'}, 404);
        if (conflict) return ok({'detail': '같은 번호의 다른 결제가 있다'}, 409);
        rows.putIfAbsent(id, () => b);
        if (loseAnswer) throw http.ClientException('답이 끊겼다', req.url);
        return ok({'id': 't-$id', 'repriced': 1, 'ask_category': null}, 201);
      case ('GET', '/me/account'):
        return ok({
          'provider': 'kakao',
          'created_at': '2026-09-15T03:00:00+00:00',
        });
      case ('GET', '/me/facts'):
        return ok(<Object>[]);
      case ('POST', '/auth/logout'):
        return http.Response('', 204);
    }
    return ok({'detail': 'not found'}, 404);
  }
}

Future<FakeServer> start(
  WidgetTester tester, {
  Map<String, String> stored = const {},
  void Function(FakeServer)? before,
}) async {
  FlutterSecureStorage.setMockInitialValues({'token': 't', ...stored});
  final server = FakeServer();
  before?.call(server);
  final api = Api(client: MockClient((r) => server(r)), baseUrl: 'http://test');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  return server;
}

Map<String, Object?> waiting(String id, String merchant) => {
  'body': {
    'amount': 4300,
    'merchant_name': merchant,
    'user_card_id': 'u1',
    'paid_at': '2026-09-15T12:00:00.000Z',
    'client_id': id,
  },
  'card': '신한카드 Mr.Life',
  'error': null,
};

String outbox(List<Map<String, Object?>> items) => jsonEncode(items);

/// 홈에서 결제 기록을 열어 GS25 4,300원을 적는다
Future<void> fill(WidgetTester tester) async {
  await tester.tap(find.text('결제 기록'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('amount')), '4300');
  await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> reloadHome(WidgetTester tester) async {
  await tester.tap(find.text('기록'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('홈'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('닿지 못하면 결제를 모아 두고 홈은 받아 둔 것을 보이다가 돌아오면 한 번 보낸다', (tester) async {
    final server = await start(tester);
    expect(find.text('30만 더 쓰면 유지'), findsOneWidget);
    server.down = true;

    // 추천은 서버가 계산해 안내만 한다
    await tester.tap(find.text('추천'));
    await tester.pumpAndSettle();
    expect(find.text('서버에 닿으면 추천을 볼 수 있어요. 다시 시도'), findsOneWidget);
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    // E26. 받아 둔 홈과 받은 때
    expect(find.textContaining('서버에 연결하지 못해'), findsOneWidget);
    expect(find.text('30만 더 쓰면 유지'), findsOneWidget);

    // E24. 추천 없이 카드를 골라 기록한다
    await fill(tester);
    await tester.pumpAndSettle();
    expect(find.text('서버에 닿지 못해 추천 없이 기록해요. 카드를 골라 주세요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '신한카드 Mr.Life'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('서버에 닿지 못해 폰에 모아 뒀어요. 닿으면 보내고 혜택을 계산해요.'), findsOneWidget);
    expect(find.text('GS25 · 4,300원'), findsOneWidget);
    expect(find.text('신한카드 Mr.Life · 계산 대기'), findsOneWidget);

    // 돌아오면 홈을 다시 불러올 때 보낸다. 다시 불러와도 한 번이다
    server.down = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(
      find.text('모아 둔 결제 1건을 보냈어요. 다른 결제 1건의 혜택도 다시 계산했어요.'),
      findsOneWidget,
    );
    final s = server.rows.values.single;
    expect(
      (s['user_card_id'], s['amount'], s['merchant_name']),
      ('u1', 4300, 'GS25'),
    );
    expect(find.text('GS25 · 4,300원'), findsNothing);
    expect(find.textContaining('서버에 연결하지 못해'), findsNothing);
    expect(find.text('29.6만 더 쓰면 유지'), findsOneWidget);
    await reloadHome(tester);
    expect(server.tries.values.single, 1);
  });

  testWidgets('저장은 됐는데 답이 끊기면 같은 번호로 다시 보내 한 건이다', (tester) async {
    final server = await start(tester);
    server.loseAnswer = true;
    await fill(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('신한카드 Mr.Life · 계산 대기'), findsOneWidget);

    server.loseAnswer = false;
    await reloadHome(tester);
    final id = server.rows.keys.single;
    // 저장, 화면을 닫고 홈이 보낸 것, 다시 불러와 보낸 것. 모두 같은 번호라 결제는 하나다
    expect(server.tries[id], 3);
    expect(find.text('신한카드 Mr.Life · 계산 대기'), findsNothing);
  });

  testWidgets('서버가 답하지 않으면 30초 뒤 끊고 모은다', (tester) async {
    final server = await start(tester);
    server.hang = true;
    await fill(tester);
    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(find.text('서버에 닿지 못해 추천 없이 기록해요. 카드를 골라 주세요.'), findsOneWidget);
    server.hang = false;
    await tester.tap(find.widgetWithText(ChoiceChip, '신한카드 Mr.Life'));
    await tester.pumpAndSettle();
    server.hang = true;
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pump();
    // 저장 전 계산이 멈춘 사이 서버가 돌아온다. 끊긴 뒤 모은 결제를 홈이 바로 보낸다
    server.hang = false;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(server.rows.length, 1);
    expect(
      find.text('모아 둔 결제 1건을 보냈어요. 다른 결제 1건의 혜택도 다시 계산했어요.'),
      findsOneWidget,
    );
  });

  testWidgets('서버 오류가 나는 결제는 뒤 결제를 막지 않고 세 번 뒤 다시 보내기를 둔다', (tester) async {
    final server = await start(
      tester,
      stored: {
        'outbox': outbox([waiting(idA, 'GS25'), waiting(idB, '스타벅스')]),
      },
      before: (s) => s.failFor.add(idA),
    );
    expect(server.rows.keys, [idB]);
    expect(find.text('신한카드 Mr.Life · 계산 대기'), findsOneWidget);
    await reloadHome(tester);
    await reloadHome(tester);
    expect(server.tries[idA], 3);
    expect(find.text('보내지 못했어요. 서버 오류로 보내지 못했어요'), findsOneWidget);
    await reloadHome(tester);
    expect(server.tries[idA], 3);

    server.failFor.clear();
    await tester.tap(find.byTooltip('다시 보내기'));
    await tester.pumpAndSettle();
    expect(server.rows.keys, [idB, idA]);
    expect(find.text('GS25 · 4,300원'), findsNothing);
  });

  testWidgets('서버가 거절한 결제는 까닭을 보이고 다시 보내지 않으며 지울 수 있다', (tester) async {
    final server = await start(
      tester,
      stored: {
        'outbox': outbox([waiting(idA, 'GS25')]),
      },
      before: (s) => s.rejectSave = true,
    );
    expect(find.text('보내지 못했어요. 카드를 찾지 못했어요. 해지한 카드일 수 있어요'), findsOneWidget);
    server.rejectSave = false;
    await reloadHome(tester);
    expect(server.rows, isEmpty);

    await tester.tap(find.byTooltip('지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();
    expect(find.text('GS25 · 4,300원'), findsNothing);
  });

  testWidgets('401이면 그 계정의 둔 홈과 모아 둔 결제를 폰에서 지운다', (tester) async {
    await start(
      tester,
      stored: {
        'outbox': outbox([waiting(idA, 'GS25')]),
        'home': jsonEncode({'at': '2026-09-15T03:00:00Z', 'home': {}}),
      },
      before: (s) => s.unauthorized = true,
    );
    expect(find.text('카카오로 시작'), findsOneWidget);
    expect(find.text('다시 로그인해야 해서 보내지 못한 결제 1건을 지웠어요.'), findsOneWidget);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'outbox'), isNull);
    expect(await storage.read(key: 'home'), isNull);
  });

  testWidgets('서버 전체가 멈춘 동안에는 횟수를 세지 않아 돌아오면 저절로 보낸다', (tester) async {
    final server = await start(
      tester,
      stored: {
        'outbox': outbox([waiting(idA, 'GS25')]),
        'home': jsonEncode({
          'at': '2026-09-15T03:00:00Z',
          'home': FakeServer().home(),
        }),
      },
      before: (s) => s.broken = true,
    );
    for (var i = 0; i < 3; i++) {
      await reloadHome(tester);
    }
    expect(find.text('신한카드 Mr.Life · 계산 대기'), findsOneWidget);
    server.broken = false;
    await reloadHome(tester);
    expect(server.rows.keys, [idA]);
    expect(find.text('GS25 · 4,300원'), findsNothing);
  });

  testWidgets('이미 서버에 있는 결제는 기록에서 보라고 하고 다시 보내기를 두지 않는다', (tester) async {
    await start(
      tester,
      stored: {
        'outbox': outbox([waiting(idA, 'GS25')]),
      },
      before: (s) => s.conflict = true,
    );
    expect(find.text('보내지 못했어요. 이미 기록에 있는 결제예요. 기록에서 확인해 주세요'), findsOneWidget);
    expect(find.byTooltip('다시 보내기'), findsNothing);
    expect(find.byTooltip('지우기'), findsOneWidget);
  });

  test('보내는 사이 새로 모은 결제는 남는다', () async {
    FlutterSecureStorage.setMockInitialValues({
      'token': 't',
      'outbox': outbox([waiting(idA, 'GS25')]),
    });
    final started = Completer<void>(), gate = Completer<void>();
    final api = Api(
      client: MockClient((r) async {
        started.complete();
        await gate.future;
        return ok({'id': 't', 'repriced': 0, 'ask_category': null}, 201);
      }),
      baseUrl: 'http://test',
    );
    await api.restore();
    final sending = api.flush();
    await started.future;
    await api.queue(
      PaymentInput()
        ..amount = 5000
        ..userCardId = 'u1'
        ..paidAt = DateTime.utc(2026, 9, 15),
      '신한카드 Mr.Life',
    );
    gate.complete();
    expect((await sending).sent, 1);
    expect([for (final p in await api.pending()) p.amount], [5000]);
  });

  test('로그아웃한 뒤 끝난 홈 받기는 폰에 쓰지 않는다', () async {
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final started = Completer<void>(), gate = Completer<void>();
    final api = Api(
      client: MockClient((r) async {
        if (r.url.path == '/auth/logout') return http.Response('', 204);
        started.complete();
        await gate.future;
        return ok(FakeServer().home());
      }),
      baseUrl: 'http://test',
    );
    await api.restore();
    final loading = api.home();
    await started.future;
    await api.logout();
    gate.complete();
    await loading;
    expect(await const FlutterSecureStorage().read(key: 'home'), isNull);
  });

  testWidgets('보내지 못한 결제가 있으면 로그아웃 전에 묻고 로그아웃하면 폰에서 지운다', (tester) async {
    await start(
      tester,
      stored: {
        'outbox': outbox([waiting(idA, 'GS25')]),
      },
      before: (s) => s.rejectSave = true,
    );
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('아직 보내지 못한 결제 1건이 지워져요.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 시작'), findsOneWidget);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'outbox'), isNull);
    expect(await storage.read(key: 'home'), isNull);
  });
}
