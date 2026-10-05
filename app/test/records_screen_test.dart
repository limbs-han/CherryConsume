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

  testWidgets('결제 줄은 누르는 동안 0.96배로 작아진다', (tester) async {
    // 누를 수 있는 카드 줄은 누름 반응이 있다. 기록 탭에서는 결제 줄이 그 줄이다. 작업 011 설계 1절 원칙 4, 작업 013 13-19
    await open(tester);
    final scale = find.ancestor(
      of: find.text('스타벅스 역삼점'),
      matching: find.byType(AnimatedScale),
    );
    expect(scale, findsOneWidget);
    // 화면 읽기는 결제 줄 하나를 누를 수 있는 버튼으로 읽는다. 작업 013 위험 검토 낮음 4
    expect(
      tester.getSemantics(find.text('스타벅스 역삼점')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    final g = await tester.startGesture(
      tester.getCenter(find.text('스타벅스 역삼점')),
    );
    // 목록 안에서는 끌기인지 누르기인지 가려질 때까지 기다린 뒤 작아진다
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(scale).scale, 0.96);
    await g.up();
    await tester.pumpAndSettle();
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
      matching: find.textContaining('신한 Mr.Life'),
    );
    expect(line, findsOneWidget);
    expect(tester.getRect(pill).right, lessThan(tester.getRect(line).left));
  });
}
