// 카드 상세를 시안대로. 작업 011 설계 2절 D1~D4, 계획 단계 3의 3
// GS25 4,300원을 Mr.Life로 내면 편의점 10%로 430원. 통합 한도 1만 원에서 430원을 써 9,570원, 편의점 월 5회에서 1회를 써 4회가 남는다
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/card_detail.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/theme.dart';
import 'package:cherry_consume/ui.dart';
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
  await tester.tap(find.text('신한 Mr.Life'));
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
  testWidgets('카드별 답은 줄마다 답하기 배지와 화살표, 누르면 바닥 시트에서 고른다', (tester) async {
    // 작업 011 설계 2절 T3. IBK 나라사랑은 지난달 결제계좌로 급여를 받았는지 묻는다. 칩을 펼치지 않는다
    final (:api, :s) = app();
    addCard(s, 'ibk-narasarang');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IBK 나라사랑'));
    await tester.pumpAndSettle();
    final title = find.textContaining('급여를 받았나요');
    await tester.scrollUntilVisible(
      title,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final row = find.ancestor(of: title, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.widgetWithText(Pill, '답하기')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(find.byType(ChoicePill), findsNothing);
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.tap(find.text('예').last);
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: find.text('예')), findsOneWidget);
  });

  testWidgets('폰 폭에서 값은 오른쪽 끝에 붙고, 짧은 값 옆의 이름은 한 줄이다', (tester) async {
    // 2026-10-04 에뮬레이터에서 이름과 값이 폭을 반씩 나눠 값이 가운데서 시작하고 "기준"이 줄을 바꿨다. 412 폭 폰
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await openMrLife(tester);
    final right = tester.getRect(find.text('30만 구간 · 전월 41만 기준')).right;
    expect(tester.getRect(find.text('29.6만 더')).right, closeTo(right, 1));
    final line = tester.getSize(find.text('지금 적용 중')).height;
    expect(tester.getSize(find.text('30만 구간 · 전월 41만 기준')).height, line);
    expect(
      tester.getRect(find.text('4 / 5회 남음').first).right,
      closeTo(right, 20),
    );
    expect(
      tester.getSize(find.text('세탁소 10% 할인')).height,
      lessThan(line * 1.5),
    );
  });

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

  testWidgets('혜택마다 조건 한 줄, 함께 쓰는 한도를 쓰는 혜택은 그 회색 상자 안에 묶는다', (tester) async {
    // 작업 011 설계 2절 D5. Mr.Life 편의점은 건당 결제액 1만 원, 하루 1회이고 통합 한도를 쓴다. 야간 혜택은 21시부터 9시다.
    // 주말 할인마트는 기간 한도가 없어 전에는 줄이 없었다. 주말 한도를 함께 쓴다. 인테이크몰은 온라인이고 함께 쓰는 한도가 없다
    await openMrLife(tester);
    final grey = find.byWidgetPredicate(
      (w) =>
          w is Container && (w.decoration as BoxDecoration?)?.color == C.grey,
    );
    Finder box(String title) =>
        find.ancestor(of: find.text(title), matching: grey);
    expect(find.text('건당 결제액 1만 원까지 · 하루 1회'), findsNWidgets(3));
    expect(find.text('건당 결제액 1만 원까지 · 하루 1회 · 21:00~09:00'), findsNWidgets(2));
    expect(
      find.text('건당 결제액 1만 원까지 · 하루 1회 · 온라인 · 21:00~09:00'),
      findsOneWidget,
    );
    expect(find.text('건당 결제액 5만 원까지 · 하루 1회 · 주말'), findsOneWidget);
    expect(find.text('건당 결제액 5만 원까지 · 하루 1회'), findsOneWidget);
    expect(find.text('온라인'), findsOneWidget);
    expect(
      find.descendant(of: box('통합 한도'), matching: find.text('편의점 10% 할인')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: box('함께 쓰는 한도'),
        matching: find.text('주말 할인마트 10% 할인'),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('인테이크몰 20% 할인'), matching: grey),
      findsNothing,
    );
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
