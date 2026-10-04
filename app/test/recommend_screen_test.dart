// 추천과 추천 결과를 시안대로. 작업 011 설계 2절 R1~R5, 계획 단계 3의 5
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/theme.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> openTab(WidgetTester tester) async {
  final (:api, :s) = app();
  final card = addCard(
    s,
    'shinhan-mrlife',
    assumedPrevMonthSpend: 410000,
  )['id'];
  addCard(s, 'hyundai-zero-edition3-discount');
  pay(s, card, 4300, 'GS25 테헤란점');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Tabs), matching: find.text('추천')),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('업종별 1순위는 업종이 왼쪽 칸이고 화살표가 있다. 최근 가게는 알약이다', (tester) async {
    await openTab(tester);
    expect(find.text('1만 원 결제 기준 혜택'), findsOneWidget);
    final cafe = tester.getRect(find.text('카페'));
    final row = find
        .ancestor(of: find.text('카페'), matching: find.byType(Row))
        .first;
    final texts = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    expect(texts.length, greaterThanOrEqualTo(3), reason: '$texts');
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(cafe.left, lessThan(60));
    expect(find.widgetWithText(ChoicePill, 'GS25 테헤란점'), findsOneWidget);
  });

  testWidgets('추천 결과. 누른 가게 이름 그대로와 업종 배지, 한 줄 결제 금액, 1순위 강조', (tester) async {
    await openTab(tester);
    await tester.tap(find.text('GS25 테헤란점'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('GS25 테헤란점'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('편의점')),
      findsOneWidget,
    );
    expect(find.text('결제 금액'), findsOneWidget);
    expect(find.text('1만 원 기준'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amount')), '150000');
    expect(find.text('150,000'), findsOneWidget);

    final first = find.byKey(const Key('rank-1'));
    final box = tester.widget<Container>(first);
    final border = (box.decoration! as BoxDecoration).border! as Border;
    expect((border.top.color, border.top.width), (C.blue, 2.0));
    final dot = tester.widget<Container>(
      find.ancestor(of: find.text('1'), matching: find.byType(Container)).first,
    );
    expect((dot.decoration! as BoxDecoration).color, C.text);
  });
}
