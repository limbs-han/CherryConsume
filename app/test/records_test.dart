// 기록 탭, 결제 고치기와 지우기와 취소, 카드 상세와 답하기, 해지. 작업 005 계획 슬라이스 4의 4단계. S7, S8, S9
// 작업 006 계획 단계 4의 7에서 가짜 서버 대신 실제 저장소로 바꿨다. 숫자는 서버 시험 test_records.py와 같은 규칙이다.
// 가져온 묶음 되돌리기 화면 시험은 엑셀 가져오기를 폰으로 옮기는 단계 5에서 다시 쓴다
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/answer.dart';
import 'package:cherry_consume/store/routes/answers.dart' show cardAnswers;
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/routes/records.dart' show cancel;
import 'package:cherry_consume/store/store.dart';
import 'package:cherry_consume/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'engine/helpers.dart' show realJson;
import 'store/helpers.dart' show pay, start;

String mrlife(Store s) =>
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id'];

Future<void> openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester, String merchant, String item) async {
  await tester.tap(find.text(merchant));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

/// 질문 글로 그 사실 칸을 찾아 그 안의 답을 누른다
Future<void> answer(WidgetTester tester, String question, String label) async {
  final box = find.ancestor(
    of: find.text(question),
    matching: find.byType(FactAnswer),
  );
  final chip = find.descendant(of: box, matching: find.text(label));
  // 긴 목록은 아래 칸을 아직 그리지 않아 세로 목록을 굴려 그리게 한 뒤 화면 안으로 끌어온다
  await tester.scrollUntilVisible(
    chip,
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// 화면이 보이는 질문 글. 시계의 오늘 개정에서 읽는다. 마지막 개정은 글이 다를 수 있다
String ask(String card, String key) {
  final c =
      (realJson['cards'] as List).firstWhere((c) => c['id'] == card) as Json;
  final today = [
    for (final r in c['revisions'] as List)
      if ((r['effective_from'] as String).compareTo('2026-09-15') <= 0) r,
  ].last;
  return (today['rules']['facts'] as List).firstWhere(
    (f) => f['key'] == key,
  )['ask'];
}

void main() {
  testWidgets('기록 탭에 그 달 결제와 합계가 보이고, 결제를 지우면 다시 계산 알림이 뜬다', (tester) async {
    // 추정값 없이 등록해 8월 이마트 30만 원이 9월 30만 구간을 정한다. 9월은 편의점 할인이 하루 1회라 21시 GS25 4,300원이
    // 430원, 22시 GS25 역삼점 5,000원은 0원이다. 상품권은 실적에서 빠진다. 8월 결제를 지우면 9월이 0원 구간이라 GS25가
    // 0원으로 다시 계산된다. 지우기는 구간이 바뀐 달부터 다시 계산한다. E54
    final (:api, :s) = app();
    final card = addCard(s, 'shinhan-mrlife')['id'] as String;
    pay(s, card, 300000, '이마트', at: '2026-08-20T12:00:00+09:00');
    pay(s, card, 4300, 'GS25');
    pay(s, card, 5000, 'GS25 역삼점', at: '2026-09-15T22:00:00+09:00');
    pay(
      s,
      card,
      10000,
      '상품권',
      at: '2026-09-13T12:00:00+09:00',
      more: {'category': 'gift_card'},
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester, '기록');

    // 3건 19,300원은 천 원 아래를 올려 2만 원
    expect(find.text('3건 · 2만 원'), findsOneWidget);
    expect(find.text('혜택 430원'), findsOneWidget);
    expect(find.text('430원 할인'), findsOneWidget);
    expect(find.text('혜택 없음'), findsNWidgets(2));
    expect(find.text('실적 제외'), findsOneWidget);

    // 고치는 화면의 예상 혜택은 이 결제의 옛 값을 빼고 계산한다. 빼지 않으면 하루 1회를 이미 써 0원이다
    await tester.tap(find.text('GS25'));
    await tester.pumpAndSettle();
    expect(find.text('결제 고치기'), findsOneWidget);
    expect(find.text('430원'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('지난달'));
    await tester.pumpAndSettle();
    await openMenu(tester, '이마트', '지우기');
    await tester.tap(find.widgetWithText(FilledButton, '지우기'));
    await tester.pumpAndSettle();

    expect(
      s.db.select('select * from transactions where deleted_at is not null'),
      hasLength(1),
    );
    expect(find.text('다른 결제 1건의 혜택도 다시 계산했어요.'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('혜택 0원'), findsOneWidget);
  });

  testWidgets('기록에서 금액만 고쳐 저장해도 온라인, 해외, 할부, 결제수단, 청구 방식이 그대로 남는다', (
    tester,
  ) async {
    // 단계 4의 7 위험 검토 5번. 고치기는 기록 줄의 값을 다시 보낸다. 한 칸이라도 빠뜨리면 저장소가 기본값으로 바꾼다
    final (:api, :s) = app();
    final card = mrlife(s);
    pay(
      s,
      card,
      30000,
      '이마트',
      more: {
        'channel': 'online',
        'region': 'overseas',
        'installment_months': 3,
        'interest_free': true,
        'payment_method': 'naver_pay',
        'billing': 'subscription',
      },
    );
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester, '기록');
    await tester.tap(find.text('이마트'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '40000');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    final t = s.db.select('select * from transactions').single;
    expect(
      (t['amount'], t['channel'], t['region'], t['installment_months']),
      (40000, 'online', 'overseas', 3),
    );
    expect(
      (t['interest_free_installment'], t['payment_method'], t['billing']),
      (1, 'naver_pay', 'subscription'),
    );
  });

  testWidgets('취소 기록은 빈 칸에서 시작하고 다른 달 추가 취소는 담지 못한다고 알린다', (tester) async {
    // 위험 검토 5번. 8월 20일 이마트 1만 원 가운데 3,000원을 8월 25일 취소했다. 9월에 2,000원을 더 취소하면 취소 시각이
    // 하나라 담지 못한다
    final (:api, :s) = app();
    final card = mrlife(s);
    final aug =
        pay(s, card, 10000, '이마트', at: '2026-08-20T12:00:00+09:00')['id']
            as String;
    cancel(s, aug, {
      'cancelled_amount': 3000,
      'cancelled_at': '2026-08-25T12:00:00+09:00',
    });
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester, '기록');
    await tester.tap(find.byTooltip('지난달'));
    await tester.pumpAndSettle();
    await openMenu(tester, '이마트', '취소 기록');

    // 처음 값이 전액이면 누르기만 해도 전액 취소가 된다. 비워 둔다. 위험 검토 16번
    final field = tester.widget<AmountField>(
      find.byKey(const Key('cancel-amount')),
    );
    expect(field.controller.text, '');
    expect(find.textContaining('취소한 날'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cancel-amount')), '2000');
    // 취소 금액도 쉼표를 넣는 금액 칸이다. 작업 011 설계 1절 원칙 6
    expect(find.text('2,000'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '기록'));
    await tester.pumpAndSettle();
    expect(find.text('다른 달에 더 취소된 금액은 아직 담지 못해요.'), findsOneWidget);
    expect(
      s.db
          .select('select cancelled_amount from transactions')
          .single['cancelled_amount'],
      3000,
    );
  });

  testWidgets('이미 취소된 결제는 이번 금액을 더해 적고 취소 기록을 지울 수 있다', (tester) async {
    // 오늘을 고르면 한국 시간 23:59가 지금 21:00보다 뒤라 지금을 적는다
    final (:api, :s) = app();
    final card = mrlife(s);
    final tid =
        pay(s, card, 10000, 'GS25', at: '2026-09-15T20:00:00+09:00')['id']
            as String;
    cancel(s, tid, {
      'cancelled_amount': 3000,
      'cancelled_at': '2026-09-15T20:30:00+09:00',
    });
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openTab(tester, '기록');
    Map<String, Object?> row() => s.db
        .select('select cancelled_amount, cancelled_at from transactions')
        .single;

    // 지금까지 3,000원이 취소됐다. 이번에 2,000원이 더 취소되면 합 5,000원을 적는다
    await openMenu(tester, 'GS25', '취소 기록');
    expect(find.textContaining('지금까지 3,000원 취소'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('cancel-amount')), '2000');
    await tester.tap(find.widgetWithText(FilledButton, '기록'));
    await tester.pumpAndSettle();
    expect(row()['cancelled_amount'], 5000);
    expect(row()['cancelled_at'], start.millisecondsSinceEpoch);

    // 위험 검토 16번. 취소 기록 지우기는 0원을 적는다
    await openMenu(tester, 'GS25', '취소 기록');
    await tester.tap(find.byKey(const Key('cancel-undo')));
    await tester.pumpAndSettle();
    expect((row()['cancelled_amount'], row()['cancelled_at']), (0, null));
  });

  testWidgets('카드 정보에서 카드 사실과 옵션을 답하고 설정에서 사람 사실을 답한다', (tester) async {
    // IBK 나라사랑을 추정값 없이 등록해 9월 10일 KTX 2만 원은 0원이다. 급여이체를 받았다고 답하면 실적이 면제돼 1,000원이다.
    // 삼성 taptap O는 패키지 1을 쓰는 중에 패키지 4를 골라 다음 달부터 바뀐다. E56
    final (:api, :s) = app();
    final nara = addCard(s, 'ibk-narasarang')['id'] as String;
    final tap = addCard(s, 'samsung-taptap-o')['id'] as String;
    pay(s, nara, 20000, 'KTX', at: '2026-09-10T12:00:00+09:00');
    cardAnswers(s, tap, {
      'options': {'package': 'p1'},
    });
    cardAnswers(s, tap, {
      'options': {'package': 'p4'},
    });
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('삼성카드 taptap O'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('카드 정보'), 300);
    await tester.pumpAndSettle();
    expect(find.text('쓰기 시작한 달'), findsOneWidget);
    final c =
        (realJson['cards'] as List).firstWhere(
              (c) => c['id'] == 'samsung-taptap-o',
            )
            as Json;
    final p4 = ((c['revisions'] as List).last['rules']['options'] as List)
        .first['choices']
        .firstWhere((ch) => ch['key'] == 'p4')['title'];
    expect(find.text('10월 1일부터 $p4'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('IBK나라사랑카드'));
    await tester.pumpAndSettle();
    await answer(tester, ask('ibk-narasarang', 'salary_transfer'), '예');
    expect(find.text('결제 1건의 혜택을 다시 계산했어요.'), findsOneWidget);
    expect(find.text('답을 적지 못했어요.'), findsNothing);
    final facts = s.db.select('select key, value from user_card_facts').single;
    expect((facts['key'], facts['value']), ('salary_transfer', 'true'));

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openTab(tester, '설정');
    expect(find.textContaining('쓰는 카드 · IBK나라사랑카드'), findsOneWidget);
    // 설정은 줄을 눌러 바닥 시트에서 고른다. 작업 011 설계 2절 S1
    // 설정 줄은 질문의 첫 문장이 제목이다. 작업 011 설계 2절 S4
    await tester.tap(
      find.text('${ask('ibk-narasarang', 'soldier').split('?').first}?'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('예').last);
    await tester.pumpAndSettle();
    expect(find.text('답을 적었어요.'), findsOneWidget);
    expect(find.text('답을 적지 못했어요.'), findsNothing);
    expect(s.db.select('select key from user_facts').single['key'], 'soldier');
  });

  testWidgets('홈의 카드를 누르면 카드 상세에 남은 한도가 보이고 해지하면 홈에서 빠진다', (tester) async {
    // 편의점 월 5회 가운데 1회를 써 4회, 통합 한도 1만 원 가운데 430원을 써 9,570원이 남았다. 주말 주유는 결제액 월 30만 원
    // 한도만 있다. 30만 구간이라 확인 필요 항목은 카드 전체 2개와 혜택별 3개다
    final (:api, :s) = app();
    final card = mrlife(s);
    pay(s, card, 4300, 'GS25');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신한카드 Mr.Life'));
    await tester.pumpAndSettle();

    // 편의점 월 5회와 다른 혜택의 월 5회가 같은 4회로 보인다. 작업 011에서 남은 양 / 한도로 바꿨다. 설계 2절 D2, D3
    expect(find.text('4 / 5회 남음'), findsWidgets);
    expect(find.text('9,570 / 10,000 남음'), findsOneWidget);
    expect(find.text('결제액 300,000 / 300,000 남음'), findsOneWidget);
    expect(find.text('30만 구간 · 전월 41만 기준'), findsOneWidget);
    final assumed = find.text('카드사 공식 문구로 확인하지 못한 값 5개는 추정으로 계산해요.');
    await tester.scrollUntilVisible(
      assumed,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(assumed, findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카드 해지'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '해지'));
    await tester.pumpAndSettle();

    expect(
      s.db.select('select removed_at from user_cards').single['removed_at'],
      isNotNull,
    );
    expect(find.text('첫 카드를 등록해 보세요'), findsOneWidget);
  });
}
