// 칩과 줄처럼 좁은 곳은 카탈로그의 짧은 이름을 쓰고, 카드 상세 제목은 전체 이름을 쓴다. 작업 011 설계 2.4, 계획 단계 4의 2
import 'dart:convert';

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/clock.dart' as clock;
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/store.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/helpers.dart' show realJson;
import 'store/helpers.dart' show start;

/// 커밋된 카탈로그에서 현대 ZERO의 짧은 이름만 비운 것. 2026-10-04 봇 커밋 90ff4b3부터 카드 20장과 카드사 열 곳에
/// 짧은 이름이 있어, 칸이 빈 카드가 전체 이름으로 돌아가는지 보려고 하나를 비운다
Json withoutZeroShortName() {
  final j = jsonDecode(jsonEncode(realJson)) as Json;
  for (final c in j['cards'] as List) {
    if (c['id'] == 'hyundai-zero-edition3-discount') c.remove('short_name');
  }
  return j;
}

({Api api, Store s}) shortApp() {
  final j = withoutZeroShortName();
  clock.now = () => start;
  addTearDown(() => clock.now = DateTime.now);
  final s = Store(openDb(), Catalog.fromJson(j), clock: () => clock.now());
  return (api: Api(s), s: s);
}

void main() {
  test('짧은 이름 칸이 없으면 이름을 쓴다', () {
    final real = Catalog.fromJson(realJson);
    expect(real.cards['shinhan-mrlife']!.shortName, '신한 Mr.Life');
    expect(real.issuers['shinhan']!.shortName, '신한');
    final c = Catalog.fromJson(withoutZeroShortName());
    expect(c.cards['hyundai-zero-edition3-discount']!.shortName, isNull);
  });

  testWidgets('홈과 결제 기록의 카드 알약은 짧은 이름, 카드 상세 제목은 전체 이름이다', (tester) async {
    final (:api, :s) = shortApp();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    addCard(s, 'hyundai-zero-edition3-discount');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('신한 Mr.Life'), findsOneWidget);
    expect(find.text('신한카드 Mr.Life'), findsNothing);
    // 짧은 이름을 적지 않은 카드는 전체 이름 그대로다
    expect(find.text('현대카드ZERO Edition3(할인형)'), findsOneWidget);

    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoicePill, '신한 Mr.Life'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('신한 Mr.Life'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('신한카드 Mr.Life'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('카드 추가의 카드사 칩은 짧은 이름이다', (tester) async {
    final (:api, s: _) = shortApp();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카드 추가').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoicePill, '신한'), findsOneWidget);
    expect(find.widgetWithText(ChoicePill, '신한카드'), findsNothing);
  });
}
