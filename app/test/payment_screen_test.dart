// 결제 기록 화면을 시안대로. 작업 011 설계 1절 원칙 5, 6, 2절 P1, P2, P4, P5, 계획 단계 3의 4
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/theme.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> open(WidgetTester tester) async {
  final (:api, :s) = app();
  addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
  addCard(s, 'hyundai-zero-edition3-discount');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('결제 기록'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('금액은 44 크기에 쉼표, 열면 바로 금액 칸이다', (tester) async {
    await open(tester);
    final amount = tester.widget<AmountField>(find.byKey(const Key('amount')));
    expect((amount.size, amount.autofocus), (44.0, true));
    expect(find.text('0'), findsNothing);
    await tester.enterText(find.byKey(const Key('amount')), '12500');
    expect(find.text('12,500'), findsOneWidget);
  });

  testWidgets('가게 칸은 돋보기 상자, 카드는 알약, 골라 둔 까닭은 체크와 파란 글자', (tester) async {
    await open(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('merchant')),
        matching: find.byIcon(Icons.search),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('amount')), '4300');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final pills = tester.widgetList<ChoicePill>(find.byType(ChoicePill));
    expect(
      {for (final p in pills) p.label: p.selected},
      {'신한 Mr.Life': true, '현대 ZERO': false},
    );
    final why = find.textContaining('가장 이득이라 골라 뒀어요');
    expect(tester.widget<Text>(why).style!.color, C.blue);
    expect(
      find.descendant(
        of: find.ancestor(of: why, matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('엑셀로 가져온 24개월 할부는 세부 시트에도 24개월로 보인다', (tester) async {
    // 고르는 줄은 1~12개월 몇 가지뿐이고 저장소는 36개월까지 받는다. 없는 값을 첫 줄 "일시불"로 보이면 안 된다
    final (:api, :s) = app();
    final card = addCard(s, 'shinhan-mrlife')['id'] as String;
    pay(s, card, 240000, '이마트', more: {'installment_months': 24});
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이마트'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('pick-할부'));
    expect(
      find.descendant(of: row, matching: find.text('24개월')),
      findsOneWidget,
    );
  });

  testWidgets('세부 시트의 할부, 청구 방식, 결제수단은 바닥 시트에서 고른다', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('amount')), '30000');
    await tester.enterText(find.byKey(const Key('merchant')), '이마트');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    final row = find.byKey(const Key('pick-할부'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3개월').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row, matching: find.text('3개월')),
      findsOneWidget,
    );
  });
}
