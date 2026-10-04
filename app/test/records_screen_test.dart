// 기록 화면을 시안대로. 작업 011 설계 2절 Hi1, Hi2, 계획 단계 3의 6
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> open(WidgetTester tester) async {
  final (:api, :s) = app();
  final card = addCard(s, 'shinhan-mrlife')['id'] as String;
  pay(s, card, 12500, '스타벅스 역삼점');
  pay(
    s,
    card,
    10000,
    '상품권',
    at: '2026-09-13T12:00:00+09:00',
    more: {'category': 'gift_card'},
  );
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('기록'));
  await tester.pumpAndSettle();
}

Finder rowOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Row)).first;

void main() {
  testWidgets('가져오기는 오른쪽 위 테두리 버튼, 달 요약은 달과 같은 줄 오른쪽', (tester) async {
    await open(tester);
    final import = find.widgetWithText(OutlinedButton, '가져오기');
    expect(import, findsOneWidget);
    expect(
      find.descendant(of: import, matching: find.byIcon(Icons.upload)),
      findsOneWidget,
    );
    expect(find.byTooltip('가져온 묶음'), findsOneWidget);

    final month = find.ancestor(
      of: find.text('9월'),
      matching: find.byType(Row),
    );
    final summary = find.textContaining('건 ·');
    expect(find.descendant(of: month.last, matching: summary), findsOneWidget);
    expect(
      tester.getRect(summary).left,
      greaterThan(tester.getRect(find.text('9월')).right),
    );
  });

  testWidgets('결제 금액은 크고 굵다. 실적 제외 배지는 업종 줄 앞이다', (tester) async {
    await open(tester);
    final amount = tester.widget<Text>(find.text('12,500'));
    expect(
      (amount.style!.fontSize, amount.style!.fontWeight),
      (17.0, FontWeight.w800),
    );

    final pill = find.text('실적 제외');
    final under = find.ancestor(of: pill, matching: find.byType(Row)).first;
    final line = find.descendant(
      of: under,
      matching: find.textContaining('신한카드 Mr.Life'),
    );
    expect(line, findsOneWidget);
    expect(tester.getRect(pill).right, lessThan(tester.getRect(line).left));
  });
}
