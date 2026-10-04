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

/// 큰 화면에 카드 상세를 띄운다. 긴 목록을 한 번에 그리려고 높이를 크게 잡는다
Future<void> openTall(WidgetTester tester, String id, String name) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 20000);
  addTearDown(tester.view.reset);
  final (:api, :s) = app();
  addCard(s, id, assumedPrevMonthSpend: 1000000);
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이번 달 혜택은 업종 순서로 늘어놓고 업종이 바뀌는 곳에 머리줄을 단다', (tester) async {
    // 2026-10-05 사용자가 비슷한 업종끼리 묶자고 했다. IBK 나라사랑의 함께 쓰는 한도가 없는 혜택 가운데 GS25 주요품목,
    // 이마트24 주요품목, 군마트 3만원 미만은 편의점이다. 군마트는 화면에서만 편의점이다. 작업 011 설계 2.5, F9
    await openTall(tester, 'ibk-narasarang', 'IBK 나라사랑');
    // 편의점 머리줄은 통합 한도 상자 안에도 있다. 상자 밖 목록은 상자들 뒤라 마지막 것이다
    final head = tester.getRect(find.byKey(const Key('group-편의점')).last);
    final items = [
      'GS25 주요품목 10% 현장할인',
      '이마트24 주요품목 10% 현장할인',
      '군마트(PX) 3만원 미만 15% 할인',
    ].map((t) => tester.getRect(find.text(t))).toList();
    final next =
        [
              for (final e
                  in find
                      .byWidgetPredicate(
                        (w) =>
                            w.key is ValueKey<String> &&
                            (w.key! as ValueKey<String>).value.startsWith(
                              'group-',
                            ),
                      )
                      .evaluate())
                tester.getRect(find.byWidget(e.widget)).top,
            ]
            .where((top) => top > head.top)
            .fold(double.infinity, (a, b) => a < b ? a : b);
    for (final r in items) {
      expect(r.top, greaterThan(head.top));
      expect(r.bottom, lessThan(next));
    }
    // 군마트 함께 쓰는 한도 상자는 모두 편의점이라 머리줄이 없다. NOL 상자도 모두 여행이다
    expect(find.byKey(const Key('group-여행')), findsNothing);
  });

  testWidgets('함께 쓰는 한도 상자 안도 업종으로 나눈다', (tester) async {
    // 신한 Mr.Life 통합 한도를 쓰는 혜택은 편의점, 병원 · 약국, 세탁, 온라인 쇼핑, 택시, 카페 · 음식점이다
    await openTall(tester, 'shinhan-mrlife', '신한 Mr.Life');
    final grey = find.byWidgetPredicate(
      (w) =>
          w is Container && (w.decoration as BoxDecoration?)?.color == C.grey,
    );
    final box = find.ancestor(of: find.text('통합 한도'), matching: grey);
    expect(
      find.descendant(
        of: box,
        matching: find.byKey(const Key('group-카페 · 음식점')),
      ),
      findsOneWidget,
    );
  });

  test('실적 막대는 구간 눈금을 같은 간격으로 두고 눈금 사이에서 금액 비율대로 찬다', () {
    // 2026-10-05 사용자가 겹치는 글자를 아랫줄로 내린 것도 이상하다고 해 같은 간격을 골랐다. 작업 011 설계 2절 F2
    const tiers = [80000, 200000, 250000, 500000, 1000000];
    expect(tierFill(tiers, 0), 0);
    expect(tierFill(tiers, 40000), closeTo(0.1, 1e-9));
    expect(tierFill(tiers, 80000), closeTo(0.2, 1e-9));
    expect(tierFill(tiers, 225000), closeTo(0.5, 1e-9));
    expect(tierFill(tiers, 1000000), 1);
    expect(tierFill(tiers, 2000000), 1);
  });

  testWidgets('한 혜택이 같이 쓰는 함께 쓰는 한도는 한 상자에 모은다', (tester) async {
    // 2026-10-05 실제 폰에서 IBK 나라사랑의 "올해 2 / 2회 남음" 상자가 비어 있었다. 놀이공원과 캐리비안베이 할인은 월 1회와
    // 연 2회 한도를 같이 써서, 혜택을 첫 상자에만 넣으면 둘째 상자가 빈다. 작업 011 설계 2절 F7
    final (:api, :s) = app();
    addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IBK 나라사랑'));
    await tester.pumpAndSettle();
    final year = find.text('올해 2 / 2회 남음');
    await tester.scrollUntilVisible(
      year,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final grey = find.byWidgetPredicate(
      (w) =>
          w is Container && (w.decoration as BoxDecoration?)?.color == C.grey,
    );
    final box = find.ancestor(of: year, matching: grey);
    expect(box, findsOneWidget);
    for (final text in ['1 / 1회 남음', '놀이공원 자유이용권 50% 현장할인']) {
      expect(
        find.descendant(of: box, matching: find.text(text)),
        findsOneWidget,
      );
    }
    // 같은 혜택들이 쓰는 한도라 제목은 한 번만 쓴다. 작업 011 설계 2절 F8
    expect(
      find.descendant(of: box, matching: find.text('함께 쓰는 한도')),
      findsOneWidget,
    );
  });

  testWidgets('큰 한도 혜택의 일부만 쓰는 한도는 그 상자 안의 흰 상자다', (tester) async {
    // 2026-10-05 실제 폰에서 함께 쓰는 한도가 한 상자에 겹쳐 보였다. KB Easy all은 혜택 22개가 통합 한도를 쓰고, 그 가운데
    // 해외·면세점 둘과 구독·영화 둘이 따로 월 4,000원 한도를 더 쓴다. 작업 011 설계 2절 F8
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 20000);
    addTearDown(tester.view.reset);
    final (:api, :s) = app();
    addCard(s, 'kb-easy-all-titanium', assumedPrevMonthSpend: 1000000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KB Easy all'));
    await tester.pumpAndSettle();
    Finder box(Color color, String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container && (w.decoration as BoxDecoration?)?.color == color,
      ),
    );
    final outer = box(C.grey, '통합 한도');
    expect(outer, findsOneWidget);
    final inner = box(Colors.white, '[A] 면세점 3% 캐시백').first;
    expect(find.descendant(of: outer, matching: inner), findsOneWidget);
    expect(
      find.descendant(of: inner, matching: find.text('함께 쓰는 한도')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: inner, matching: find.text('[A] 음식 3% 캐시백')),
      findsNothing,
    );
    expect(
      find.descendant(of: outer, matching: find.text('[A] 음식 3% 캐시백')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: outer, matching: find.text('함께 쓰는 한도')),
      findsNWidgets(2),
    );
  });

  testWidgets('구간 사이가 좁아도 눈금 글자가 겹치지 않는다', (tester) async {
    // 2026-10-05 실제 폰에서 IBK 나라사랑의 20만과 25만이 겹쳤다. 겹치는 글자는 아랫줄에 둔다. 작업 011 설계 2절 F2
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final (:api, :s) = app();
    addCard(s, 'ibk-narasarang');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IBK 나라사랑'));
    await tester.pumpAndSettle();
    Rect at(String t) => tester.getRect(
      find.descendant(of: find.byType(TierBar), matching: find.text(t)),
    );
    final labels = ['8만', '20만', '25만', '50만', '100만'];
    for (final (i, a) in labels.indexed) {
      for (final b in labels.skip(i + 1)) {
        expect(at(a).overlaps(at(b)), isFalse, reason: '$a $b');
      }
    }
    // 눈금은 같은 간격이고 끝 구간 글자만 막대 끝에 오른쪽을 맞춘다
    final gap = at('20만').center.dx - at('8만').center.dx;
    expect(at('25만').center.dx - at('20만').center.dx, closeTo(gap, 1));
    expect(at('50만').center.dx - at('25만').center.dx, closeTo(gap, 1));
    expect(at('8만').center.dy, at('25만').center.dy);
  });

  testWidgets('못 받는 혜택은 따로 접어 두고, 펼치면 구간마다 남은 금액을 한 번만 쓴다', (tester) async {
    // 2026-10-05 사용자가 실제 폰에서 이번 달 혜택에 섞여 정보가 많다고 했고, 줄마다 "29.6만 더"가 되풀이되는 것도
    // 어색하다고 했다. 추정값 없이 0원 구간이면 30만부터인 혜택 10개를 못 받는다. 이번 달 4,300원을 써 30만까지
    // 295,700원이고 천 원 아래를 올려 29.6만이다. 작업 011 설계 2절 F3, F4
    final (:api, :s) = app();
    final card = addCard(s, 'shinhan-mrlife')['id'];
    pay(s, card, 4300, 'GS25');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신한 Mr.Life'));
    await tester.pumpAndSettle();
    final head = find.text('구간이 모자라 아직 못 받는 혜택');
    await tester.scrollUntilVisible(
      head,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('10개'), findsOneWidget);
    final group = find.text('30만 구간까지 29.6만 원 남았어요');
    expect(group, findsNothing);
    await tester.ensureVisible(head);
    await tester.pumpAndSettle();
    await tester.tap(head);
    await tester.pumpAndSettle();
    final locked = find.ancestor(of: head, matching: find.byType(Box));
    expect(locked, findsOneWidget);
    expect(find.descendant(of: locked, matching: group), findsOneWidget);
    expect(
      find.descendant(of: locked, matching: find.textContaining('29.6만')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: locked, matching: find.text('편의점 10% 할인')),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: find.text('이번 달 혜택'), matching: find.byType(Box)),
      findsNothing,
    );
  });

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
