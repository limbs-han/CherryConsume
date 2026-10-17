// 직접 만든 카드의 표시와 관리. 직접 등록 배지, 카드 고치기, 결제마다 실적 제외. 작업 019 설계 3절, S14, E65
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/store/routes/custom.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

const cafe = {
  'issuer': 'shinhan',
  'name': '위시플러스',
  'kind': 'credit',
  'tiers': <int>[],
  'benefits': [
    {
      'categories': ['cafe'],
      'type': 'discount',
      'rate': 10,
    },
  ],
};

Future<Store> openHome(WidgetTester tester) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 4000);
  addTearDown(tester.view.reset);
  final (:api, :s) = app();
  addCard(s, createCustom(s, cafe)['card_id'] as String);
  addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('홈, 카드 상세, 추천 순위에 직접 등록 배지가 붙는다', (tester) async {
    await openHome(tester);
    expect(find.text('직접 등록'), findsOneWidget);
    await tester.tap(find.text('위시플러스'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('직접 등록')),
      findsOneWidget,
    );
    await back(tester);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Tabs), matching: find.text('추천')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('카페').first);
    await tester.pumpAndSettle();
    expect(find.text('직접 등록'), findsOneWidget);
  });

  testWidgets('S14 카드 상세 메뉴의 카드 고치기로 혜택을 고치면 다시 계산했다고 알린다', (tester) async {
    await openHome(tester);
    await tester.tap(find.text('위시플러스'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카드 고치기'));
    await tester.pumpAndSettle();
    expect(find.text('카드 고치기'), findsOneWidget);
    final name = tester.widget<TextField>(find.byKey(const Key('custom-name')));
    expect(name.controller!.text, '위시플러스');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('결제 0건의 혜택을 다시 계산했어요.'), findsOneWidget);
  });

  testWidgets('E65 실적 제외는 직접 만든 카드를 골랐을 때만 보이고 켜면 그대로 저장된다', (tester) async {
    final s = await openHome(tester);
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '5000');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신한 Mr.Life'));
    await tester.pumpAndSettle();
    expect(find.text('실적에서 빼기'), findsNothing);
    await tester.tap(find.text('위시플러스'));
    await tester.pumpAndSettle();
    expect(find.text('실적에서 빼기'), findsOneWidget);
    await tester.tap(find.text('실적에서 빼기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(
      s.db
          .select('select spend_excluded from transactions')
          .single['spend_excluded'],
      1,
    );
  });
}
