// 카드 추가와 등록 시트를 시안대로. 작업 011 설계 2절 A1, A3, 계획 단계 3의 2
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/add_card.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, '카드 추가'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'mr');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('신한카드 Mr.Life'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('찾는 카드가 없으면 카드 요청 설문을 브라우저로 연다', (tester) async {
    // 시나리오 E22, 작업 012 설계 6절. 목록 맨 아래와 검색 결과가 없을 때 둔다
    final (:api, s: _) = app();
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AddCardScreen(
          api: api,
          requestUrl: 'https://forms.gle/example',
          open: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ask = find.text('카드 요청하기');
    await tester.scrollUntilVisible(
      ask,
      300,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(ask, findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '없는카드이름');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('찾는 카드가 없어요.'), findsOneWidget);
    await tester.tap(ask);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://forms.gle/example')]);
  });

  testWidgets('브라우저를 열지 못하면 설문 주소를 알린다', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(
      MaterialApp(
        home: AddCardScreen(
          api: api,
          requestUrl: 'https://forms.gle/example',
          open: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '없는카드이름');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카드 요청하기'));
    await tester.pumpAndSettle();
    expect(
      find.text('브라우저를 열지 못했어요. forms.gle/example에서 요청할 수 있어요.'),
      findsOneWidget,
    );
  });

  testWidgets('설문 주소가 없으면 카드 요청 줄을 두지 않는다', (tester) async {
    // 목록 맨 아래까지 그려지게 높게 띄운다
    tester.view.physicalSize = const Size(1080, 8000);
    addTearDown(tester.view.reset);
    final (:api, s: _) = app();
    Widget screen(String? url) => MaterialApp(
      home: AddCardScreen(api: api, requestUrl: url),
    );
    await tester.pumpWidget(screen('https://forms.gle/example'));
    await tester.pumpAndSettle();
    expect(find.text('찾는 카드가 없나요?'), findsOneWidget);
    await tester.pumpWidget(screen(null));
    await tester.pumpAndSettle();
    expect(find.text('찾는 카드가 없나요?'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '없는카드이름');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('카드 요청하기'), findsNothing);
  });

  testWidgets('카드 목록 줄마다 카드사 색 칸이 있다', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '카드 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'mr');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<IssuerSwatch>(find.byType(IssuerSwatch))
          .map((w) => w.issuer),
      ['shinhan'],
    );
  });

  testWidgets('등록을 누르면 짧게 떤다', (tester) async {
    // 설계 문서 10절, 작업 013 13-16
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openSheet(tester);
    final log = haptics(tester);
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();
    expect(log, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('등록 시트. 닫기, 쉼표 금액, 체크 안내, 알약 예와 아니오', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.enterText(find.byKey(const Key('prev')), '410000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('410,000'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('이번 달은 30만 구간이 적용돼요'), findsOneWidget);

    final no = tester.widget<ChoicePill>(
      find.widgetWithText(ChoicePill, '아니요'),
    );
    final yes = tester.widget<ChoicePill>(find.widgetWithText(ChoicePill, '예'));
    expect((no.selected, yes.selected), (true, false));
    await tester.tap(find.text('예'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoicePill, '이번 달'), findsOneWidget);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('신한카드 Mr.Life 등록'), findsNothing);
  });
}
