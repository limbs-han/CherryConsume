// 추천 탭에서 업종별 1순위, 추천 결과, 추천에서 결제 기록까지. 작업 005 계획 슬라이스 3의 3단계. S4
// 작업 006 계획 단계 4의 7에서 가짜 서버 대신 실제 저장소로 바꿨다. 21시 카페 1만 원은 Mr.Life 1,000원, ZERO 80원.
// IBK 나라사랑 25만 구간은 카페에서 실물카드로 0원이고 네이버페이로 내면 Npay 10% 1,000원을 더 받는다
import 'package:cherry_consume/format.dart' show won;
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/routes/recommend.dart' show recommend;
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> openTab(WidgetTester tester) async {
  await tester.tap(find.text('추천'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('업종별 1순위에서 추천 결과를 보고 1순위 카드로 결제를 기록하면 추천에서 기록함 표시가 남는다', (
    tester,
  ) async {
    final (:api, :s) = app();
    final mr = addCard(
      s,
      'shinhan-mrlife',
      assumedPrevMonthSpend: 410000,
    )['id'];
    addCard(s, 'hyundai-zero-edition3-discount');
    addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000);
    pay(s, mr, 4300, 'GS25 테헤란점', at: '2026-09-14T12:00:00+09:00');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester);
    expect(find.text('어디서 결제하세요?'), findsOneWidget);
    expect(find.text('GS25 테헤란점'), findsOneWidget);
    // 업종 줄은 카드 이름과 혜택 이름을 두 줄로 쓴다. 작업 011 설계 2절 R1
    final cafe = find.widgetWithText(Pressable, '카페');
    for (final text in ['신한 Mr.Life', '야간 식음료 10% 할인']) {
      expect(
        find.descendant(of: cafe, matching: find.text(text)),
        findsOneWidget,
      );
    }

    await tester.tap(cafe);
    await tester.pumpAndSettle();
    expect(find.text('1,000원 할인'), findsOneWidget);
    expect(find.text('80원 할인'), findsOneWidget);
    expect(find.text('네이버페이로 내면 1,000원 더 받아요'), findsOneWidget);
    // 결제수단을 바꾸면 더 받는 팁은 지갑 아이콘을 붙인다. 작업 011 설계 2절 R5
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsWidgets);

    await tester.tap(find.text('이 카드로 결제 기록').first);
    await tester.pumpAndSettle();
    expect(find.text('결제 기록'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '10000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    final t = s.db
        .select("select * from transactions where category_code = 'cafe'")
        .single;
    expect(
      (t['user_card_id'], t['amount'], t['from_recommendation']),
      (mr, 10000, 1),
    );
    // 저장하면 추천 결과를 닫고 추천 첫 화면으로 돌아간다
    expect(find.text('어디서 결제하세요?'), findsOneWidget);
  });

  testWidgets('답하면 더 받는 질문을 누르면 답하는 곳으로 가고 돌아오면 다시 추천한다', (tester) async {
    // 작업 005 설계 5e. IBK 나라사랑 PX 1만 원은 현역병이나 급여이체를 몰라 0원이다. 현역병은 사람 사실이라 설정에서 답한다
    final (:api, :s) = app();
    addCard(s, 'ibk-narasarang');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester);
    await tester.enterText(find.byKey(const Key('search')), 'PX');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final [row] = recommend(s, {'merchant_name': 'PX'})['ranking'] as List;
    final soldier = (row['ask'] as List).firstWhere(
      (a) => a['key'] == 'soldier',
    );
    final ask = find.text(
      '답하면 ${won(soldier['extra'] as int)} 더 받아요 · ${soldier['question']}',
    );
    expect(ask, findsOneWidget);
    await tester.ensureVisible(ask);
    await tester.tap(ask);
    await tester.pumpAndSettle();
    expect(find.text('혜택 계산에 쓰는 답'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(ask, findsOneWidget);
  });

  testWidgets('카드가 없으면 추천 탭에 카드 추가가 보인다', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester);
    expect(find.text('등록된 카드가 없어요'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '카드 추가'), findsOneWidget);
  });

  testWidgets('금액을 적고 확인 없이 결제 기록을 누르면 그 금액으로 다시 계산하고 열지 않는다', (tester) async {
    final (:api, :s) = app();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester);
    await tester.tap(find.text('카페'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '150000');
    await tester.tap(find.text('이 카드로 결제 기록').first);
    await tester.pumpAndSettle();
    expect(find.text('적은 금액으로 다시 계산했어요. 1순위를 확인하고 눌러 주세요.'), findsOneWidget);
    expect(find.text('결제 기록'), findsNothing);
  });
}
