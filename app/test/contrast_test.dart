// 흐린 글자는 흰 상자 안에서만 쓴다. 회색 바탕 위에서는 대비가 4.19:1이라 읽기 어렵다. 작업 004 설계 2.1, 작업 013 13-14
//
// 화면마다 목록이 화면 밖까지 그려지게 높게 띄워 흰 상자 밖의 흐린 글자를 찾는다
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> tall(WidgetTester tester) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 8000);
  addTearDown(tester.view.reset);
  final (:api, :s) = app();
  final card = addCard(
    s,
    'ibk-narasarang',
    assumedPrevMonthSpend: 300000,
  )['id'];
  addCard(s, 'hyundai-zero-edition3-discount');
  pay(s, card, 4300, 'GS25 테헤란점', at: '2026-09-10T12:00:00+09:00');
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
}

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(Tabs), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈, 기록, 설정 탭', (tester) async {
    await tall(tester);
    expect(faintOffWhite(tester), isEmpty, reason: '홈');
    await tab(tester, '기록');
    expect(faintOffWhite(tester), isEmpty, reason: '기록');
    await tab(tester, '설정');
    expect(faintOffWhite(tester), isEmpty, reason: '설정');
  });

  testWidgets('카드 상세', (tester) async {
    await tall(tester);
    await tester.tap(find.text('IBK 나라사랑'));
    await tester.pumpAndSettle();
    expect(faintOffWhite(tester), isEmpty);
  });

  testWidgets('결제 기록과 카드 추가', (tester) async {
    await tall(tester);
    await tester.tap(find.text('결제 기록'));
    await tester.pumpAndSettle();
    expect(faintOffWhite(tester), isEmpty, reason: '결제 기록');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('카드 추가'));
    await tester.pumpAndSettle();
    expect(faintOffWhite(tester), isEmpty, reason: '카드 추가');
  });
}
