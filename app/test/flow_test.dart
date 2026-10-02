// 빈 홈에서 카드를 등록해 홈에 구간 배지가 보이기까지. 작업 005 계획 슬라이스 1의 8단계. 로그인을 뺀 S1
// 작업 006 계획 단계 4의 7에서 가짜 서버 대신 실제 저장소로 바꿨다. 로그인 시험은 로그인이 없어져 지웠다
import 'package:cherry_consume/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

void main() {
  testWidgets('빈 홈에서 카드를 등록하면 홈에 구간 배지가 보인다', (tester) async {
    final (:api, :s) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();

    // 1a 빈 홈
    expect(find.text('첫 카드를 등록해 보세요'), findsOneWidget);
    expect(find.text('0원'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '카드 추가'));
    await tester.pumpAndSettle();

    // 2 카드 추가. 실제 카탈로그는 20장이라 찾아서 고른다
    await tester.enterText(find.byType(TextField).first, 'mr');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('신용 · 연회비 1.5만 · 실적 30/50/100만'), findsOneWidget);
    await tester.tap(find.text('신한카드 Mr.Life'));
    await tester.pumpAndSettle();

    // 등록 시트. 비우면 구간 전, 41만을 넣으면 30만 구간이고 받는 혜택 10개 가운데 둘을 보인다
    expect(find.text('신한카드 Mr.Life 등록'), findsOneWidget);
    expect(find.text('이번 달은 혜택 구간 전이에요. 30만부터 받아요'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('prev')), '410000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('이번 달은 30만 구간이 적용돼요'), findsOneWidget);
    expect(find.text('전기·가스·통신요금 10% 할인, 편의점 10% 할인 외 8개'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();

    // 1 홈
    final row = s.db
        .select(
          'select card_id, assumed_prev_month_spend, started_on from user_cards',
        )
        .single;
    expect(
      (row['card_id'], row['assumed_prev_month_spend'], row['started_on']),
      ('shinhan-mrlife', 410000, null),
    );
    expect(find.text('30만 구간'), findsOneWidget);
    expect(find.text('30만 더 쓰면 유지'), findsOneWidget);
    expect(find.text('9월'), findsOneWidget);
  });
}
