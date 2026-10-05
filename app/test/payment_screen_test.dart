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

  testWidgets('카드가 5장을 넘으면 칩은 앞의 두 장과 다른 카드다', (tester) async {
    // 작업 004 설계 3절, 작업 013 13-17. 다른 카드는 나머지를 바닥 시트로 고르고, 고르면 칩 이름이 그 카드가 된다
    final (:api, :s) = app();
    for (final id in [
      'shinhan-mrlife',
      'hyundai-zero-edition3-discount',
      'ibk-narasarang',
      'kb-easy-all-titanium',
      'samsung-taptap-o',
      'lotte-loca365',
    ]) {
      addCard(s, id);
    }
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    List<ChoicePill> pills() =>
        tester.widgetList<ChoicePill>(find.byType(ChoicePill)).toList();
    expect(pills().length, 3);
    expect(pills().last.label, '다른 카드');

    // 가게를 고르면 혜택이 가장 큰 카드가 앞이고 골라 둔다
    await tester.enterText(find.byKey(const Key('amount')), '4300');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(pills().first.selected, isTrue);
    final shown = {for (final p in pills().take(2)) p.label};

    await tester.tap(find.text('다른 카드'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    final rows = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: sheet, matching: find.byType(Text)),
      ))
        t.data!,
    ].skip(1).toList();
    expect(rows.length, 4);
    expect(rows.toSet().intersection(shown), isEmpty);
    await tester.tap(
      find.descendant(of: sheet, matching: find.text(rows.last)),
    );
    await tester.pumpAndSettle();
    expect((pills().last.label, pills().last.selected), (rows.last, true));
    expect(pills().first.selected, isFalse);
  });

  testWidgets('카드가 5장이면 모두 늘어놓는다', (tester) async {
    final (:api, :s) = app();
    for (final id in [
      'shinhan-mrlife',
      'hyundai-zero-edition3-discount',
      'ibk-narasarang',
      'kb-easy-all-titanium',
      'samsung-taptap-o',
    ]) {
      addCard(s, id);
    }
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    List<String> labels() => [
      for (final p in tester.widgetList<ChoicePill>(find.byType(ChoicePill)))
        p.label,
    ];
    final home = labels();
    expect(home.length, 5);
    expect(home, isNot(contains('다른 카드')));
    // 5장 이하면 가게를 쳐도 칩 자리가 바뀌지 않는다. 바뀌는 사이에 누르면 다른 카드가 골린다. 작업 013 위험 검토 중간 1
    await tester.enterText(find.byKey(const Key('amount')), '4300');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(labels(), home);
  });

  testWidgets('카드가 5장을 넘어도 가게를 고르기 전에는 홈 순서의 두 장이다', (tester) async {
    final (:api, :s) = app();
    final ids = [
      'shinhan-mrlife',
      'hyundai-zero-edition3-discount',
      'ibk-narasarang',
      'kb-easy-all-titanium',
      'samsung-taptap-o',
      'lotte-loca365',
    ];
    for (final id in ids) {
      addCard(s, id);
    }
    final home = [for (final c in (await api.home()).cards) c.name];
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    final labels = [
      for (final p in tester.widgetList<ChoicePill>(find.byType(ChoicePill)))
        p.label,
    ];
    expect(labels, [...home.take(2), '다른 카드']);
  });

  testWidgets('저장을 누르면 짧게 떤다', (tester) async {
    // 진동은 저장, 등록, 칩 고르기에만 짧게 준다. 설계 문서 10절, 작업 013 13-16
    await open(tester);
    await tester.enterText(find.byKey(const Key('amount')), '4300');
    await tester.enterText(find.byKey(const Key('merchant')), 'GS25');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final log = haptics(tester);
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(log, ['HapticFeedbackType.lightImpact']);
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

  testWidgets('업종을 고치면 같은 가게 결제도 바꿀지 묻고, 바꾸기를 고르면 함께 바꾼다', (tester) async {
    // 작업 016 설계 5절. 2026-10-05 사용자가 물어보고 바꾸기로 정했다
    final (:api, :s) = app();
    final card = addCard(s, 'shinhan-mrlife')['id'] as String;
    pay(s, card, 4300, '동네 가게', at: '2026-09-10T12:00:00+09:00');
    pay(s, card, 4300, '동네가게', at: '2026-09-11T12:00:00+09:00');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동네 가게'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    final pill = find.widgetWithText(
      ChoicePill,
      s.categoryNames['convenience']!,
    );
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('같은 가게 결제 1건도 바꿀까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '바꾸기'));
    await tester.pumpAndSettle();
    expect(
      {
        for (final r in s.db.select('select category_code from transactions'))
          r['category_code'],
      },
      {'convenience'},
    );
  });
  testWidgets('같은 가게 결제를 묻는 창에서 그대로 두기를 고르면 그 결제는 바뀌지 않는다', (tester) async {
    // 작업 016 설계 5절. 2026-10-05 사용자가 물어보고 바꾸기로 정했다
    final (:api, :s) = app();
    final card = addCard(s, 'shinhan-mrlife')['id'] as String;
    pay(s, card, 4300, '동네 가게', at: '2026-09-10T12:00:00+09:00');
    pay(s, card, 4300, '동네가게', at: '2026-09-11T12:00:00+09:00');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동네 가게'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    final pill = find.widgetWithText(
      ChoicePill,
      s.categoryNames['convenience']!,
    );
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('같은 가게 결제 1건도 바꿀까요?'), findsOneWidget);
    await tester.tap(find.text('그대로 두기'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final r in s.db.select(
          'select category_code from transactions order by paid_at',
        ))
          r['category_code'],
      ],
      ['convenience', null],
    );
  });
}
