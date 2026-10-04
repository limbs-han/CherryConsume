// 홈과 빈 홈을 시안대로. 작업 011 설계 2절 H1~H6, G6, 계획 단계 3의 1
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/payment.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/theme.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;

/// 글자가 든 조각만 모은다. Text.rich는 바깥에 조각 하나를 더 씌운다
List<TextSpan> leaves(InlineSpan s) {
  final out = <TextSpan>[];
  s.visitChildren((c) {
    if (c is TextSpan && c.text != null) out.add(c);
    return true;
  });
  return out;
}

Finder tab(String label) =>
    find.descendant(of: find.byType(Tabs), matching: find.text(label));

void main() {
  testWidgets('빈 홈. 혜택 띠는 연한 점선 상자에 회색 0원, 안내 카드에 카드 아이콘 원', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    final band = tester.widget<DashedBox>(find.byKey(const Key('total')));
    expect(band.color, C.blueSoft);
    expect(find.byIcon(Icons.credit_card), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('홈. 카드마다 흰 카드, 카드사 색 칸, 강조한 남은 금액, 점선 카드 추가', (tester) async {
    final (:api, :s) = app();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    addCard(s, 'hyundai-zero-edition3-discount');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();

    // 카드 두 장이 각자 흰 카드다. 실적 채우기 제목은 카드 밖이다
    for (final name in ['신한카드 Mr.Life', '현대카드ZERO Edition3(할인형)']) {
      expect(
        find.ancestor(of: find.text(name), matching: find.byType(Box)),
        findsOneWidget,
        reason: name,
      );
    }
    expect(
      find.ancestor(of: find.text('실적 채우기'), matching: find.byType(Box)),
      findsNothing,
    );
    expect(
      tester
          .widgetList<IssuerSwatch>(find.byType(IssuerSwatch))
          .map((w) => w.issuer),
      ['shinhan', 'hyundai'],
    );
    // 남은 금액만 코발트로 강조하고 구간 배지는 문구 아래다
    final lead = find.textContaining('30만 더 쓰면 유지', findRichText: true);
    expect(lead, findsOneWidget);
    final spans = leaves(tester.widget<RichText>(lead).text);
    expect((spans.first.text, spans.first.style!.color), ('30만', C.blue));
    expect(
      tester.getTopLeft(find.text('30만 구간')).dy,
      greaterThan(tester.getTopLeft(lead).dy),
    );
    // 카드 추가는 점선 테두리와 + 아이콘
    expect(
      find.ancestor(of: find.text('카드 추가'), matching: find.byType(DashedBox)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add), findsWidgets);
  });

  testWidgets('혜택 띠의 금액은 크게, 원은 작게 쓰고 움직여 올라간다', (tester) async {
    final (:api, :s) = app();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    expect(find.byType(CountUp), findsOneWidget);
    final total = find.descendant(
      of: find.byKey(const Key('total')),
      matching: find.textContaining('원', findRichText: true),
    );
    final spans = leaves(tester.widget<RichText>(total.last).text);
    expect(spans.first.style!.fontSize, 34);
    expect(spans.last.style!.fontSize, 20);
  });

  testWidgets('결제 기록 버튼이 홈, 추천, 기록 탭에 있고 설정 탭에는 없다', (tester) async {
    final (:api, :s) = app();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    final fab = find.widgetWithText(FloatingActionButton, '결제 기록');
    expect(fab, findsOneWidget);
    // 색은 테마에서 온다. 실제로 칠한 색을 본다
    final paint = tester.widget<Material>(
      find.descendant(of: fab, matching: find.byType(Material)).first,
    );
    expect(paint.color, C.blue);
    for (final t in ['추천', '기록']) {
      await tester.tap(tab(t));
      await tester.pumpAndSettle();
      expect(fab, findsOneWidget, reason: t);
    }
    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(tab('설정'));
    await tester.pumpAndSettle();
    expect(fab, findsNothing);
  });
}
