// 엑셀 가져오기 화면을 시안대로. 작업 011 설계 1절 원칙 1, 2절 I1, 계획 단계 3의 7
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/screens/import.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

Future<void> open(WidgetTester tester, {PickFile? pick}) async {
  final (:api, :s) = app();
  final card = addCard(s, 'shinhan-mrlife')['id'] as String;
  await tester.pumpWidget(
    MaterialApp(
      home: ImportScreen(
        api: api,
        cards: [(id: card, name: '신한카드 Mr.Life')],
        pick:
            pick ??
            () async => (
              name: '내역.csv',
              bytes: Uint8List.fromList(
                utf8.encode('날,곳,값\n2026.09.10 21:30,GS25 강남점,4300\n'),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 버튼이 화면 아래 끝에 붙어 있다
void atBottom(WidgetTester tester, Finder button) {
  final screen = tester.getSize(find.byType(Scaffold));
  expect(tester.getRect(button).bottom, greaterThan(screen.height - 20));
}

void main() {
  testWidgets('단계 버튼은 아래 고정, 카드는 알약, 엑셀 받는 곳 안내가 있다', (tester) async {
    await open(tester);
    atBottom(tester, find.widgetWithText(FilledButton, '파일 고르기'));
    expect(find.widgetWithText(ChoicePill, '신한카드 Mr.Life'), findsOneWidget);
    expect(find.widgetWithText(ChoicePill, '파일에 카드 이름이 있어요'), findsOneWidget);

    await tester.tap(find.text('엑셀은 어디서 받나요'));
    await tester.pumpAndSettle();
    expect(find.textContaining('이용 내역 조회'), findsOneWidget);
  });

  testWidgets('파일을 고르면 파일 상자에 이름과 다른 파일, 아래 버튼은 다음 단계다', (tester) async {
    await open(tester);
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
    expect(find.text('내역.csv'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '다른 파일'), findsOneWidget);
    atBottom(tester, find.widgetWithText(FilledButton, '다시 읽기'));
  });

  testWidgets('미리보기는 숫자 타일, 카드와 달과 합계, 날짜가 든 줄, N건 저장이다', (tester) async {
    // 작업 011 설계 2절 I3. 열 이름이 사전에 있어 짝짓기 없이 미리보기가 된다. GS25 4,300원 한 건이다
    await open(
      tester,
      pick: () async => (
        name: '내역.csv',
        bytes: Uint8List.fromList(
          utf8.encode('이용일자,이용시간,가맹점명,이용금액\n2026.09.10,21:30,GS25 강남점,4300\n'),
        ),
      ),
    );
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
    for (final label in ['읽은 행', '저장 예정', '중복 제외', '업종 미정']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('신한카드 Mr.Life · 2026년 9월'), findsOneWidget);
    expect(find.text('합계 4,300원'), findsOneWidget);
    expect(find.text('9/10'), findsOneWidget);
    atBottom(tester, find.widgetWithText(FilledButton, '1건 저장'));
  });

  testWidgets('2MB 넘는 파일을 고르면 앞 파일을 지워 그 파일로 저장하지 않는다', (tester) async {
    var n = 0;
    await open(
      tester,
      pick: () async => n++ == 0
          ? (
              name: '내역.csv',
              bytes: Uint8List.fromList(
                utf8.encode('날,곳,값\n2026.09.10 21:30,GS25 강남점,4300\n'),
              ),
            )
          : (name: '큰 파일.xlsx', bytes: null),
    );
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다른 파일'));
    await tester.pumpAndSettle();
    expect(find.text('파일이 2MB보다 커요. 기간을 나눠 올려 주세요.'), findsOneWidget);
    expect(find.text('내역.csv'), findsNothing);
    atBottom(tester, find.widgetWithText(FilledButton, '파일 고르기'));
  });
}
