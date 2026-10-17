// 접근성. WCAG 2.2 AA와 Android 접근성 지침. 작업 018, 설계 10절 접근성 줄
import 'dart:math' show pow;

import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/theme.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 대비비
double ratio(Color a, Color b) {
  final (x, y) = (_lum(a), _lum(b));
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

Future<(dynamic, dynamic)> openPayment(WidgetTester tester) async {
  final (:api, :s) = app();
  final card = addCard(
    s,
    'shinhan-mrlife',
    assumedPrevMonthSpend: 410000,
  )['id'];
  pay(s, card, 15000, 'GS25 테헤란점');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('결제 기록'));
  await tester.pumpAndSettle();
  return (api, s);
}

void main() {
  testWidgets('입력 칸의 테두리는 3:1, 예시 글자는 4.5:1을 넘는다', (tester) async {
    await openPayment(tester);
    InputDecoration deco(Finder f) => tester
        .widget<TextField>(
          find.descendant(of: f, matching: find.byType(TextField)),
        )
        .decoration!;
    final amount = deco(find.byKey(const Key('amount')));
    final merchant = deco(find.byKey(const Key('merchant')));
    for (final d in [amount, merchant]) {
      final side = d.enabledBorder!.borderSide.color;
      expect(ratio(side, Colors.white), greaterThanOrEqualTo(3));
    }
    expect(
      ratio(amount.hintStyle!.color!, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(ratio(C.faint, Colors.white), greaterThanOrEqualTo(4.5));
  });

  testWidgets('앱이 한국어라 뒤로 가기 버튼을 한국어로 읽는다', (tester) async {
    await openPayment(tester);
    expect(find.byTooltip('뒤로'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('결제 금액 칸은 위 제목을 이름으로 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPayment(tester);
    final node = tester.getSemantics(
      find.descendant(
        of: find.byKey(const Key('amount')),
        matching: find.byType(EditableText),
      ),
    );
    expect(node.label, contains('얼마 썼나요'));
    semantics.dispose();
  });

  testWidgets('칩은 누르는 범위가 48dp다', (tester) async {
    await openPayment(tester);
    for (final e in find.byType(ChoicePill).evaluate()) {
      expect(
        tester.getSize(find.byWidget(e.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });

  testWidgets('기록 금액은 원까지 읽는다', (tester) async {
    final semantics = tester.ensureSemantics();
    final (:api, :s) = app();
    final card = addCard(s, 'shinhan-mrlife')['id'];
    pay(s, card, 15000, 'GS25 테헤란점');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(find.text('15,000'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('15,000원')), findsWidgets);
    semantics.dispose();
  });
}
