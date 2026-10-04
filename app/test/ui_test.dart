// 함께 쓰는 부품. 작업 011 설계 1절, 4절, 계획 단계 1의 3
import 'package:cherry_consume/theme.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 폭 360, 높이 800인 폰. 상태 표시줄 24, 아래 막대 48
void phone(WidgetTester tester, {double keyboard = 0}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.padding = const FakeViewPadding(top: 72, bottom: 144);
  tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 144);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
  addTearDown(tester.view.reset);
}

Widget page(Widget body) => MaterialApp(
  theme: theme(),
  home: Scaffold(body: body),
);

TextEditingValue at(String text, int cursor) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor),
);

void main() {
  test('쉼표 금액은 가운데를 고쳐도 커서가 그 자리에 남고, 자릿수가 차면 더 받지 않는다', () {
    final f = ThousandsFormatter(9);
    // "12,500"의 2를 지우고 그 자리에 3을 쳐 13,500으로 고친다. 커서가 끝으로 가면 15,003이 된다
    final deleted = f.formatEditUpdate(at('12,500', 2), at('1,500', 1));
    expect((deleted.text, deleted.selection.baseOffset), ('1,500', 1));
    final typed = f.formatEditUpdate(deleted, at('13,500', 2));
    expect((typed.text, typed.selection.baseOffset), ('13,500', 2));
    // 끝에 이어 치면 쉼표가 옮겨도 커서는 끝이다
    final tail = f.formatEditUpdate(at('1,250', 5), at('1,2500', 6));
    expect((tail.text, tail.selection.baseOffset), ('12,500', 6));
    // 9자리가 찬 뒤 가운데에 넣으면 마지막 자리를 자르지 않고 받지 않는다
    final full = at('123,456,789', 1);
    expect(f.formatEditUpdate(full, at('1523,456,789', 2)), full);
  });

  testWidgets('금액 칸은 쉼표를 넣고 숫자만 받는다', (tester) async {
    final c = TextEditingController();
    int? got;
    await tester.pumpWidget(
      page(AmountField(controller: c, onChanged: (v) => got = v)),
    );
    await tester.enterText(find.byType(TextField), '12500');
    expect(c.text, '12,500');
    expect(got, 12500);
    await tester.enterText(find.byType(TextField), '00a7');
    expect(c.text, '7');
    expect(amountOf(''), isNull);
    expect(amountOf('1,234,000'), 1234000);
  });

  testWidgets('알약 칩은 고르면 남색 바탕에 흰 글자다', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      page(
        Row(
          children: [
            ChoicePill('신한 Mr.Life', selected: true, onTap: () => tapped++),
            ChoicePill('현대 ZERO', selected: false, onTap: () => tapped++),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color? bg(String label) =>
        ((tester
                    .widget<AnimatedContainer>(
                      find.ancestor(
                        of: find.text(label),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration
                as BoxDecoration?)
            ?.color);
    expect(bg('신한 Mr.Life'), C.text);
    expect(
      tester.widget<Text>(find.text('신한 Mr.Life')).style!.color,
      Colors.white,
    );
    expect(bg('현대 ZERO'), Colors.white);
    expect(
      tester.getSize(find.text('현대 ZERO').hitTestable()).height,
      lessThan(44),
    );
    expect(
      tester.getSize(find.byType(ChoicePill).last).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.text('현대 ZERO'));
    expect(tapped, 1);
  });

  testWidgets('하단 고정 버튼은 키보드가 뜨면 키보드 위에 있다', (tester) async {
    phone(tester, keyboard: 300);
    await tester.pumpWidget(
      page(
        WithAction(
          action: FilledButton(onPressed: () {}, child: const Text('저장')),
          children: [for (var i = 0; i < 30; i++) Text('줄 $i')],
        ),
      ),
    );
    final button = tester.getRect(find.widgetWithText(FilledButton, '저장'));
    expect(button.bottom, lessThanOrEqualTo(800 - 300));
  });

  testWidgets('하단 고정 버튼은 키보드가 없으면 아래 막대 위에 있다', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      page(
        WithAction(
          action: FilledButton(onPressed: () {}, child: const Text('저장')),
          children: const [Text('줄')],
        ),
      ),
    );
    final button = tester.getRect(find.widgetWithText(FilledButton, '저장'));
    expect(button.bottom, lessThanOrEqualTo(800 - 48));
    expect(button.height, 56);
  });

  testWidgets('바닥 시트는 상태 표시줄 아래에서 멈추고 고른 값을 돌려준다', (tester) async {
    phone(tester);
    String? got;
    await tester.pumpWidget(
      page(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await pickSheet(
              context,
              title: '업종',
              options: [for (var i = 0; i < 40; i++) ('c$i', '업종 $i')],
              selected: 'c3',
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('업종').first).top, greaterThanOrEqualTo(24));
    await tester.tap(find.text('업종 1'));
    await tester.pumpAndSettle();
    expect(got, 'c1');
  });

  testWidgets('숫자 움직임은 0.6초 동안 새 값까지 가고, 애니메이션 줄이기면 바로 바뀐다', (tester) async {
    Widget at(int v, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: CountUp(v, builder: (n) => Text('$n')),
      ),
    );
    await tester.pumpWidget(at(1000));
    await tester.pump(const Duration(milliseconds: 300));
    final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!);
    expect(mid, inExclusiveRange(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('1000'), findsOneWidget);

    await tester.pumpWidget(at(7669, reduce: true));
    await tester.pump();
    expect(find.text('7669'), findsOneWidget);
  });

  testWidgets('흰 상자는 옅은 코발트 그림자가 있다', (tester) async {
    await tester.pumpWidget(page(const Box(child: Text('카드'))));
    final d =
        tester
                .widget<Container>(
                  find.ancestor(
                    of: find.text('카드'),
                    matching: find.byType(Container),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(d.boxShadow, isNotEmpty);
  });

  testWidgets('칩 줄은 화면 좌우 20 안에서만 보인다', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      page(
        PillRow(
          children: [
            for (var i = 0; i < 12; i++)
              ChoicePill('카드사 $i', selected: i == 0, onTap: () {}),
          ],
        ),
      ),
    );
    final clip = tester.getRect(find.byType(SingleChildScrollView));
    expect(clip.left, 20);
    expect(clip.right, 360 - 20);
  });

  testWidgets('누르는 동안 0.96배로 작아졌다가 돌아온다', (tester) async {
    await tester.pumpWidget(
      page(
        Center(
          child: Pressable(onTap: () {}, child: const Text('누르기')),
        ),
      ),
    );
    double scale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    final g = await tester.startGesture(tester.getCenter(find.text('누르기')));
    await tester.pump();
    expect(scale(), 0.96);
    await g.up();
    await tester.pump();
    expect(scale(), 1);
  });

  testWidgets('알약 칩은 폭이 정해진 줄에서도 글자만큼만 넓다', (tester) async {
    await tester.pumpWidget(
      page(
        SizedBox(
          width: 360,
          child: Wrap(
            children: [
              ChoicePill('아니요', selected: true, onTap: () {}),
              ChoicePill('예', selected: false, onTap: () {}),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ChoicePill).first).width, lessThan(120));
  });

  testWidgets('점선은 바탕색 위에 그린다', (tester) async {
    await tester.pumpWidget(
      page(const DashedBox(color: C.blueSoft, child: SizedBox(height: 40))),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(DashedBox),
        matching: find.byType(CustomPaint),
      ),
    );
    expect((paint.painter, paint.foregroundPainter == null), (null, false));
  });
}
