// 제목줄 간격을 시안대로. 뒤로 가기가 있으면 제목이 52, 탭 화면은 24에서 시작한다. 작업 011 설계 2절 G5, 계획 단계 3의 9
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

double titleLeft(WidgetTester tester, String title) => tester
    .getRect(
      find.descendant(of: find.byType(AppBar), matching: find.text(title)),
    )
    .left;

Future<void> tab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(Tabs), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('탭 화면 제목은 24, 뒤로 가기가 있는 화면 제목은 52에서 시작한다', (tester) async {
    final (:api, :s) = app();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    expect(titleLeft(tester, '내 카드'), 24);
    await tab(tester, '추천');
    expect(titleLeft(tester, '어디서 결제하세요?'), 24);
    await tab(tester, '설정');
    expect(titleLeft(tester, '설정'), 24);
    await tab(tester, '기록');
    expect(titleLeft(tester, '기록'), 24);

    await tester.tap(find.text('가져오기'));
    await tester.pumpAndSettle();
    expect(titleLeft(tester, '이용 내역 가져오기'), 52);
    expect(tester.getCenter(find.byType(BackButton)).dx, 24);
  });
}
