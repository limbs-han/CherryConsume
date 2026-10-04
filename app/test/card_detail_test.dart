// 카드 상세를 시안대로. 작업 011 설계 2절 D1~D4, 계획 단계 3의 3
// GS25 4,300원을 Mr.Life로 내면 편의점 10%로 430원. 통합 한도 1만 원에서 430원을 써 9,570원, 편의점 월 5회에서 1회를 써 4회가 남는다
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/card_detail.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> openMrLife(WidgetTester tester) async {
  final (:api, :s) = app();
  final card = addCard(
    s,
    'shinhan-mrlife',
    assumedPrevMonthSpend: 410000,
  )['id'];
  pay(s, card, 4300, 'GS25');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text('신한카드 Mr.Life'));
  await tester.pumpAndSettle();
}

/// 이름과 값이 한 줄에 왼쪽 오른쪽으로 놓였다
void expectRow(WidgetTester tester, String label, String value) {
  final l = tester.getRect(find.text(label));
  final v = tester.getRect(find.text(value));
  expect((v.center.dy - l.center.dy).abs(), lessThan(4), reason: label);
  expect(v.left, greaterThan(l.right), reason: label);
}

void main() {
  testWidgets('실적 카드. 구간 눈금 막대와 이름 오른쪽 값 줄', (tester) async {
    await openMrLife(tester);
    final bar = tester.widget<TierBar>(find.byType(TierBar));
    expect(bar.tiers, [300000, 500000, 1000000]);
    expect(bar.counted, 4300);
    for (final t in ['30만', '50만', '100만']) {
      expect(
        find.descendant(of: find.byType(TierBar), matching: find.text(t)),
        findsOneWidget,
        reason: t,
      );
    }
    expectRow(tester, '지금 적용 중', '30만 구간 · 전월 41만 기준');
    expectRow(tester, '다음 달 30만 구간 유지', '29.6만 더');
    expect(tester.widget<Text>(find.text('29.6만 더')).style!.color, C.blue);
  });

  testWidgets('이번 달 혜택. 남은 양과 한도, 통합 한도는 회색 상자', (tester) async {
    await openMrLife(tester);
    expect(find.text('이번 달 혜택'), findsOneWidget);
    expect(find.text('4 / 5회 남음'), findsWidgets);
    expect(find.text('9,570 / 10,000 남음'), findsOneWidget);
    expect(find.text('결제액 300,000 / 300,000 남음'), findsOneWidget);
    final shared = find.ancestor(
      of: find.text('9,570 / 10,000 남음'),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container && (w.decoration as BoxDecoration?)?.color == C.grey,
      ),
    );
    expect(shared, findsOneWidget);
  });

  testWidgets('아래쪽. 쓰기 시작한 달 줄과 연한 파랑 결제 보기 버튼', (tester) async {
    await openMrLife(tester);
    final row = find.byKey(const Key('started-on'));
    await tester.scrollUntilVisible(
      row,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: row, matching: find.text('쓰기 시작한 달')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('몰라요')),
      findsOneWidget,
    );
    final see = find.widgetWithText(FilledButton, '이 카드 결제 보기');
    await tester.scrollUntilVisible(
      see,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final paint = tester.widget<Material>(
      find.descendant(of: see, matching: find.byType(Material)).first,
    );
    expect(paint.color, C.blueSoft);
  });
}
