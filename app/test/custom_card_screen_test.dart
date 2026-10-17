// 카드 직접 만들기 화면. 작업 019 설계 2절, S13
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/add_card.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

Future<void> openAdd(WidgetTester tester) async {
  // 입력 줄과 혜택 시트가 한 화면에 다 그려지게 높게 띄운다
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 6000);
  addTearDown(tester.view.reset);
  final (:api, s: _) = app();
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '카드 추가'));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('카드 추가 오른쪽 위와 검색 결과가 없을 때 직접 만들기가 있다', (tester) async {
    await openAdd(tester);
    final action = find.descendant(
      of: find.byType(AppBar),
      matching: find.widgetWithText(TextButton, '직접 만들기'),
    );
    expect(action, findsOneWidget);
    // 배경색 없는 글자 버튼이다
    expect(tester.widget<TextButton>(action).style?.backgroundColor, isNull);
    await tester.enterText(find.byType(TextField).first, '없는카드이름');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('찾는 카드가 없어요.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '직접 만들기'), findsNWidgets(2));
  });

  testWidgets('처음부터 만들어 혜택 한 줄을 넣고 등록하면 홈에 직접 등록 카드가 보인다', (tester) async {
    await openAdd(tester);
    await tester.tap(find.widgetWithText(TextButton, '직접 만들기').first);
    await tester.pumpAndSettle();
    await tapText(tester, '처음부터 만들기');

    await tapText(tester, '카드사');
    await tapText(tester, '신한');
    await tester.enterText(find.byKey(const Key('custom-name')), '위시플러스');
    await tester.enterText(find.byKey(const Key('tier-0')), '300000');
    await tapText(tester, '혜택 더하기');
    // 혜택 한 줄 시트
    await tapText(tester, '카페');
    await tapText(tester, '할인');
    await tester.enterText(find.byKey(const Key('benefit-size')), '10');
    await tester.enterText(find.byKey(const Key('benefit-cap')), '5000');
    await tapText(tester, '30만부터');
    await tapText(tester, '이 혜택 넣기');
    expect(find.text('카페 10% 할인'), findsOneWidget);
    expect(find.text('월 5,000원 · 30만부터'), findsOneWidget);

    await tapText(tester, '만들고 등록');
    // 이어서 기존 등록 시트
    expect(find.byType(RegisterSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();
    expect(find.text('위시플러스'), findsWidgets);
  });

  testWidgets('비슷한 카드에서 시작하면 구간이 채워지고 잠긴다', (tester) async {
    await openAdd(tester);
    await tester.tap(find.widgetWithText(TextButton, '직접 만들기').first);
    await tester.pumpAndSettle();
    await tapText(tester, '비슷한 카드에서 시작');
    await tester.enterText(find.byType(TextField).first, 'mr');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tapText(tester, '신한카드 Mr.Life');
    expect(find.text('비슷한 카드의 구간을 따라요'), findsOneWidget);
    final tier = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('tier-0')),
        matching: find.byType(TextField),
      ),
    );
    expect(tier.enabled, isFalse);
    expect(tier.controller!.text, isNotEmpty);
    // 혜택 줄을 가져왔다. 고칠 수 있는 줄이나 복사한 혜택이다
    expect(find.byTooltip('지우기'), findsWidgets);
    expect(find.byType(ChoicePill), findsWidgets);
  });

  testWidgets('이름이 없거나 혜택 크기가 비면 만들 수 없다고 알린다', (tester) async {
    await openAdd(tester);
    await tester.tap(find.widgetWithText(TextButton, '직접 만들기').first);
    await tester.pumpAndSettle();
    await tapText(tester, '처음부터 만들기');
    await tapText(tester, '만들고 등록');
    expect(find.text('카드 이름을 적어 주세요'), findsOneWidget);
    expect(find.byType(RegisterSheet), findsNothing);
  });

  testWidgets('혜택 시트에서 업종을 고르면 비슷한 혜택을 골라 채울 수 있다', (tester) async {
    // 작업 019 설계 2.5, 성공 기준 3
    await openAdd(tester);
    await tester.tap(find.widgetWithText(TextButton, '직접 만들기').first);
    await tester.pumpAndSettle();
    await tapText(tester, '처음부터 만들기');
    await tapText(tester, '혜택 더하기');
    expect(find.text('비슷한 혜택 가져오기'), findsNothing);
    await tapText(tester, '카페');
    expect(find.text('비슷한 혜택 가져오기'), findsOneWidget);
    await tester.tap(find.byKey(const Key('suggest-0')));
    await tester.pumpAndSettle();
    final size = tester.widget<TextField>(
      find.byKey(const Key('benefit-size')),
    );
    expect(size.controller!.text, isNotEmpty);
  });
}
