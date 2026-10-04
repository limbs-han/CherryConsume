// 카드 추가와 등록 시트를 시안대로. 작업 011 설계 2절 A1, A3, 계획 단계 3의 2
import 'package:cherry_consume/main.dart';
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
