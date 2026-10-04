// 죽는 영역. 상태 표시줄, 카메라 구멍, 아래 막대, 키보드에 글자와 주요 버튼이 가리지 않는다. 가로로 미는 줄은 좌우 20
// 안에 있어 뒤로 가기 손짓과 겹치지 않는다. 작업 011 의도 성공 기준 7, 8, 설계 2.1절과 5절, 계획 단계 2의 1
import 'dart:math' as math;

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

/// 화면 크기와 위아래 시스템 영역. 논리 픽셀이다. iPhone은 다이내믹 아일랜드 59와 홈 표시줄 34다
const conditions = {
  'Android 제스처': (size: Size(412, 915), top: 24.0, bottom: 24.0, keyboard: 0.0),
  'Android 3버튼': (size: Size(412, 915), top: 24.0, bottom: 48.0, keyboard: 0.0),
  'iPhone': (size: Size(390, 844), top: 59.0, bottom: 34.0, keyboard: 0.0),
  '작은 폰': (size: Size(360, 640), top: 24.0, bottom: 48.0, keyboard: 0.0),
  '키보드': (size: Size(412, 915), top: 24.0, bottom: 48.0, keyboard: 300.0),
};

typedef Condition = ({Size size, double top, double bottom, double keyboard});

void setView(WidgetTester tester, Condition c) {
  const dpr = 3.0;
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = c.size * dpr;
  tester.view.viewPadding = FakeViewPadding(
    top: c.top * dpr,
    bottom: c.bottom * dpr,
  );
  // 키보드가 뜨면 아래 여백은 키보드가 덮어 0이 된다
  tester.view.padding = FakeViewPadding(
    top: c.top * dpr,
    bottom: c.keyboard > 0 ? 0 : c.bottom * dpr,
  );
  tester.view.viewInsets = FakeViewPadding(bottom: c.keyboard * dpr);
  addTearDown(tester.view.reset);
}

/// 시안의 카드 세 장과 9월 결제 다섯 건
Future<Api> seeded() async {
  final (:api, s: _) = app();
  await api.addCard('shinhan-mrlife', prev: 410000);
  await api.addCard('ibk-narasarang', prev: 200000);
  await api.addCard('hyundai-zero-edition3-discount');
  final cards = (await api.home()).cards;
  String id(String part) => cards.firstWhere((c) => c.name.contains(part)).id;
  DateTime kst(int day, int hour) => DateTime.utc(2026, 9, day, hour - 9);
  for (final (amount, name, card, category, channel, at) in [
    (169500, '이마트 성수점', 'Mr.Life', 'grocery_mart', 'offline', kst(10, 18)),
    (128000, '서울시 자동차세', 'ZERO', 'tax', 'online', kst(12, 10)),
    (36900, '쿠팡', 'ZERO', 'online_shopping', 'online', kst(13, 20)),
    (4300, 'GS25 테헤란점', '나라사랑', 'convenience', 'offline', kst(15, 9)),
    (12500, '스타벅스 역삼점', 'Mr.Life', 'cafe', 'offline', kst(15, 14)),
  ]) {
    await api.savePayment(
      PaymentInput()
        ..amount = amount
        ..merchantName = name
        ..userCardId = id(card)
        ..category = category
        ..channel = channel
        ..paidAt = at,
    );
  }
  return api;
}

Future<void> tapIn(WidgetTester tester, Finder f) async {
  // 긴 목록에서 아직 그리지 않은 자리면 내려서 그리게 한다
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder tab(String label) =>
    find.descendant(of: find.byType(Tabs), matching: find.text(label));

/// 화면 이름마다 그 화면을 여는 길과 주요 버튼, 탭이 있는지
final screens =
    <
      String,
      ({
        Future<void> Function(WidgetTester) open,
        Finder? primary,
        bool tabs,
        bool scrollEnd,
      })
    >{
      '빈 홈': (
        open: (t) async {
          final (:api, s: _) = app();
          await t.pumpWidget(CherryApp(api: api));
        },
        primary: find.widgetWithText(FilledButton, '카드 추가'),
        tabs: true,
        scrollEnd: false,
      ),
      '홈': (
        open: (t) async {},
        primary: find.widgetWithText(FloatingActionButton, '결제 기록'),
        tabs: true,
        scrollEnd: true,
      ),
      '카드 추가': (
        open: (t) => tapIn(t, find.text('카드 추가')),
        primary: null,
        tabs: false,
        scrollEnd: true,
      ),
      '등록 시트': (
        open: (t) async {
          await tapIn(t, find.text('카드 추가'));
          await t.enterText(find.byType(TextField).first, '처음');
          await t.pump(const Duration(milliseconds: 400));
          await t.pumpAndSettle();
          await tapIn(t, find.textContaining('처음').last);
        },
        primary: find.widgetWithText(FilledButton, '등록'),
        tabs: false,
        scrollEnd: false,
      ),
      '카드 상세': (
        open: (t) => tapIn(t, find.textContaining('Mr.Life').first),
        primary: null,
        tabs: false,
        scrollEnd: true,
      ),
      '결제 기록': (
        open: (t) => tapIn(t, find.text('결제 기록')),
        primary: find.widgetWithText(FilledButton, '저장'),
        tabs: false,
        scrollEnd: false,
      ),
      '세부 시트': (
        open: (t) async {
          await tapIn(t, find.text('결제 기록'));
          await t.enterText(find.byType(TextField).at(0), '12500');
          await t.enterText(find.byType(TextField).at(1), '스타벅스 역삼점');
          await t.pump(const Duration(milliseconds: 500));
          await t.pumpAndSettle();
          await tapIn(t, find.text('바꾸기'));
        },
        primary: find.widgetWithText(FilledButton, '확인'),
        tabs: false,
        scrollEnd: false,
      ),
      '추천': (
        open: (t) => tapIn(t, tab('추천')),
        primary: null,
        tabs: true,
        scrollEnd: true,
      ),
      '추천 결과': (
        open: (t) async {
          await tapIn(t, tab('추천'));
          await tapIn(t, find.text('GS25 테헤란점').first);
        },
        primary: find.widgetWithText(FilledButton, '이 카드로 결제 기록'),
        tabs: false,
        scrollEnd: true,
      ),
      '기록': (
        open: (t) => tapIn(t, tab('기록')),
        primary: null,
        tabs: true,
        scrollEnd: true,
      ),
      '엑셀 가져오기': (
        open: (t) async {
          await tapIn(t, tab('기록'));
          await tapIn(t, find.text('가져오기'));
        },
        primary: null,
        tabs: false,
        scrollEnd: true,
      ),
      '설정': (
        open: (t) => tapIn(t, tab('설정')),
        primary: null,
        tabs: true,
        scrollEnd: true,
      ),
    };

/// 화면 안에 있는 글자 상자. 화면 밖으로 밀린 것은 뺀다
Iterable<Rect> visibleTexts(WidgetTester tester, Size size) => tester
    .renderObjectList<RenderBox>(find.byType(RichText))
    .where((b) => b.hasSize && b.attached)
    .map((b) => b.localToGlobal(Offset.zero) & b.size)
    .where((r) => r.bottom > 0 && r.top < size.height && r.width > 0);

void main() {
  for (final MapEntry(key: name, value: screen) in screens.entries) {
    for (final MapEntry(key: label, value: c) in conditions.entries) {
      testWidgets('$name · $label', (tester) async {
        setView(tester, c);
        if (name != '빈 홈') {
          await tester.pumpWidget(CherryApp(api: await seeded()));
          await tester.pumpAndSettle();
        }
        await screen.open(tester);
        await tester.pumpAndSettle();
        final size = c.size;
        // 아래에서 가리는 높이. 키보드가 뜨면 키보드, 아니면 막대다
        final cover = math.max(c.bottom, c.keyboard);

        // 상태 표시줄과 카메라 구멍 밑에 글자가 없다
        for (final r in visibleTexts(tester, size)) {
          expect(
            r.top,
            greaterThanOrEqualTo(c.top - 0.5),
            reason: '상태 표시줄 밑 글자 $r',
          );
        }

        // 주요 버튼은 내리지 않아도 막대와 키보드 위에 다 보인다
        if (screen.primary != null) {
          final r = tester.getRect(screen.primary!);
          expect(r.top, greaterThanOrEqualTo(c.top), reason: '주요 버튼 $r');
          expect(
            r.bottom,
            lessThanOrEqualTo(size.height - cover + 0.5),
            reason: '주요 버튼 $r',
          );
        }

        // 가로로 미는 줄은 좌우 20 안에 있다
        for (final s in tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        )) {
          if (s.axisDirection != AxisDirection.right) continue;
          final r = tester.getRect(find.byWidget(s));
          expect(r.left, greaterThanOrEqualTo(20), reason: '가로 줄 $r');
          expect(
            r.right,
            lessThanOrEqualTo(size.width - 20),
            reason: '가로 줄 $r',
          );
        }

        // 끝까지 내리면 마지막 글자가 아래 막대나 탭 막대 위로 올라온다
        if (screen.scrollEnd && c.keyboard == 0) {
          final vertical = find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          );
          if (vertical.evaluate().isNotEmpty) {
            // 긴 목록은 내릴수록 끝 길이를 다시 재서 끝에 닿을 때까지 내린다
            final p = tester.state<ScrollableState>(vertical.first).position;
            for (var i = 0; i < 10 && p.pixels < p.maxScrollExtent; i++) {
              p.jumpTo(p.maxScrollExtent);
              await tester.pumpAndSettle();
            }
          }
          final floor = screen.tabs
              ? tester.getRect(find.byType(Tabs)).top
              : size.height - c.bottom;
          final last = visibleTexts(tester, size)
              .where((r) => r.top < floor)
              .map((r) => r.bottom)
              .fold<double>(0, math.max);
          expect(last, lessThanOrEqualTo(floor + 0.5), reason: '마지막 줄이 막대 밑');
        }
      });
    }
  }
}
