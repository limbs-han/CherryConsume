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
  testWidgets('가게를 못 찾으면 업종 고르기를 눌러 바닥 시트에서 고른다', (tester) async {
    // 작업 011 설계 2절 T4, 시나리오 E16. 업종 칩을 모두 펼치지 않는다
    await openTab(tester);
    await tester.enterText(find.byType(TextField).first, '동네 카페 달빛');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('“동네 카페 달빛”을 찾지 못했어요'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    await tester.tap(find.text('업종 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카페').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rank-1')), findsOneWidget);
  });

  testWidgets('문장으로만 남은 조건이 있는 혜택은 조건 확인 배지와 그 문장을 붙인다', (tester) async {
    // 작업 011 설계 2절 T5, 시나리오 E12. IBK 나라사랑의 GS25 주요품목 할인은 간편식, 음료, 아이스크림만이다
    final (:api, :s) = app();
    final card = addCard(
      s,
      'ibk-narasarang',
      assumedPrevMonthSpend: 300000,
    )['id'];
    pay(s, card, 4300, 'GS25 테헤란점', at: '2026-09-10T12:00:00+09:00');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Tabs), matching: find.text('추천')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GS25 테헤란점'));
    await tester.pumpAndSettle();
    final first = find.byKey(const Key('rank-1'));
    expect(
      find.descendant(of: first, matching: find.widgetWithText(Pill, '조건 확인')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.textContaining('아이스크림만')),
      findsOneWidget,
    );
  });

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
