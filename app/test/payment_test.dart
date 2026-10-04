// 홈에서 결제를 기록하면 홈 숫자가 바뀌기까지. 작업 005 계획 슬라이스 2의 5단계. S3
// 작업 006 계획 단계 4의 7에서 가짜 서버 대신 실제 저장소로 바꿨다. GS25 4,300원은 Mr.Life 편의점 10%로 430원
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/routes/records.dart' show delete;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay, start;

String mrlife(Store s) =>
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id'];

Future<void> openPayment(
  WidgetTester tester,
  int amount,
  String merchant,
) async {
  await tester.tap(find.text('결제 기록'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('amount')), '$amount');
  await tester.enterText(find.byKey(const Key('merchant')), merchant);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// 세부 시트에서 그 이름의 줄을 눌러 바닥 시트에서 고른다. 작업 011 설계 2절 P5
Future<void> choose(WidgetTester tester, String label, String item) async {
  final row = find.byKey(Key('pick-$label'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('결제를 기록하면 1순위 카드가 골라지고 저장 뒤 홈 숫자가 바뀐다', (tester) async {
    final (:api, :s) = app();
    final card = mrlife(s);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('30만 더 쓰면 유지'), findsOneWidget);

    await openPayment(tester, 4300, 'GS25 테헤란점');
    expect(find.text('이 가게에선 신한카드 Mr.Life가 가장 이득이라 골라 뒀어요'), findsOneWidget);
    expect(find.text('430원'), findsOneWidget);
    expect(find.text('편의점 10% 할인'), findsOneWidget);
    // 화면은 폰 시간대로 보인다. 한국 폰이면 21:00이고 UTC로 도는 CI에서는 12:00이다
    final hour = start.toLocal().hour.toString().padLeft(2, '0');
    expect(find.text('GS25 · 편의점 · 오늘 $hour:00'), findsOneWidget);
    expect(find.text('오프라인 · 일시불 · 실물카드'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    final t = s.db.select('select * from transactions').single;
    expect(
      (
        t['user_card_id'],
        t['amount'],
        t['merchant_name'],
        t['merchant_key'],
        t['category_code'],
      ),
      (card, 4300, 'GS25 테헤란점', 'gs25', 'convenience'),
    );
    expect(
      (t['channel'], t['installment_months'], t['interest_free_installment']),
      ('offline', 1, 0),
    );
    expect(
      (t['payment_method'], t['billing'], t['from_recommendation']),
      ('physical_card', 'normal', 0),
    );
    expect(t['paid_at'], start.millisecondsSinceEpoch);

    // 홈. 받은 혜택 430원, 30만 구간까지 295,700원은 천 원 아래를 올려 29.6만
    expect(find.text('430원'), findsOneWidget);
    expect(find.text('29.6만 더 쓰면 유지'), findsOneWidget);
  });

  testWidgets('앞선 결제를 넣어 다른 결제의 혜택이 바뀌면 알린다', (tester) async {
    // E52. 편의점 할인은 하루 1회다. 23시 GS25 5,000원이 500원을 받아 둔 뒤 21시 4,300원을 넣으면 21시가 430원,
    // 23시가 0원으로 다시 계산된다
    final (:api, :s) = app();
    final card = mrlife(s);
    pay(s, card, 5000, 'GS25', at: '2026-09-15T23:00:00+09:00');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openPayment(tester, 4300, 'GS25');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('다른 결제 1건의 혜택도 다시 계산했어요.'), findsOneWidget);
    expect(find.text('430원'), findsOneWidget);
  });

  testWidgets('저장 직전에 1순위가 바뀌면 저장하지 않고 알린다', (tester) async {
    // 화면이 Mr.Life 430원을 보인 뒤 다른 곳에서 오늘 편의점 할인을 써 버리면 저장할 때 ZERO 34원이 1순위가 된다
    final (:api, :s) = app();
    final card = mrlife(s);
    addCard(s, 'hyundai-zero-edition3-discount');
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openPayment(tester, 4300, 'GS25');
    expect(find.text('이 가게에선 신한카드 Mr.Life가 가장 이득이라 골라 뒀어요'), findsOneWidget);
    pay(s, card, 4300, 'GS25', at: '2026-09-15T20:00:00+09:00');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(s.db.select('select * from transactions'), hasLength(1));
    expect(find.text('가장 이득인 카드가 바뀌었어요. 확인하고 다시 저장해 주세요.'), findsOneWidget);
  });

  testWidgets('업종이 부모까지만 있으면 저장한 자리에서 자식 업종을 묻는다', (tester) async {
    // E47. IBK 나라사랑 20만 구간. "KT 요금"은 통신요금까지만 알아 0원이고 자식 업종을 묻는다. 이동통신이라고 답하면
    // 그 결제의 업종만 고쳐 이동통신 자동납부 5%가 월 2천 원 한도에 걸려 2,000원이다
    final (:api, :s) = app();
    addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 200000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openPayment(tester, 50000, 'KT 요금');
    expect(find.text('오프라인 · 일시불 · 실물카드 · 자동납부'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    expect(find.text('KT 요금은 통신요금 가운데 어느 쪽인가요'), findsOneWidget);
    await tester.tap(find.text('이동통신'));
    await tester.pumpAndSettle();
    expect(find.text('KT 요금은 통신요금 가운데 어느 쪽인가요'), findsNothing);
    final t = s.db.select('select id, category_code from transactions').single;
    expect(t['category_code'], 'telecom.mobile');
    final value = s.db.select(
      'select sum(value) as v from transaction_benefits where transaction_id = ?',
      [t['id']],
    );
    expect(value.single['v'], 2000);
  });

  testWidgets('자식 업종 고치기가 실패해도 저장한 결제라 화면을 닫는다', (tester) async {
    // 재검토 중간 1번. 남겨 두면 다시 눌러 같은 결제가 두 건이 된다. 묻는 사이 그 결제를 지워 고치기가 실패하게 한다
    final (:api, :s) = app();
    addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 200000);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openPayment(tester, 50000, 'KT 요금');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    delete(
      s,
      s.db.select('select id from transactions').single['id'] as String,
    );
    await tester.tap(find.text('이동통신'));
    await tester.pumpAndSettle();
    expect(find.text('저장했지만 업종은 고치지 못했어요. 기록에서 고쳐 주세요.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '저장'), findsNothing);
    expect(s.db.select('select * from transactions'), hasLength(1));
  });

  testWidgets('바꾸기에서 고른 온라인, 할부, 무이자, 해외, 청구 방식, 결제수단이 저장까지 간다', (
    tester,
  ) async {
    // 단계 4 위험 검토 9번. 저장소는 모르는 칸을 버려서 칸 이름이 틀리면 기본값으로 계산된다
    final (:api, :s) = app();
    mrlife(s);
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await openPayment(tester, 30000, '이마트');
    await tester.tap(find.text('바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('온라인'));
    await tester.pumpAndSettle();
    await choose(tester, '할부', '3개월');
    final free = find.widgetWithText(SwitchListTile, '무이자할부');
    await tester.ensureVisible(free);
    await tester.pumpAndSettle();
    await tester.tap(free);
    await tester.pumpAndSettle();
    final overseas = find.widgetWithText(SwitchListTile, '해외 결제');
    await tester.ensureVisible(overseas);
    await tester.pumpAndSettle();
    await tester.tap(overseas);
    await tester.pumpAndSettle();
    await choose(tester, '청구 방식', '정기결제');
    await choose(tester, '결제수단', '네이버페이');
    final done = find.widgetWithText(FilledButton, '확인');
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.text('온라인 · 3개월 무이자 · 네이버페이 · 해외 · 정기결제'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    final t = s.db.select('select * from transactions').single;
    expect(
      (
        t['installment_months'],
        t['interest_free_installment'],
        t['billing'],
        t['payment_method'],
      ),
      (3, 1, 'subscription', 'naver_pay'),
    );
    expect((t['channel'], t['region']), ('online', 'overseas'));
  });
}
