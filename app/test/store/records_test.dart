// 기록, 고치기, 취소, 지우기, 카드 상세와 해지. Python `backend/tests/api/test_records.py`를 옮겼다. S7, S8, S9
//
// 신한카드 Mr.Life. 구간 0, 30만, 50만, 100만. 편의점 10%는 30만 구간부터 1회 1만 원까지, 하루 1회, 월 5회.
// 통합 한도는 30만 구간에서 월 1만 원. 상품권은 실적에서 빠진다. 시계는 2026-09-15 21:00 한국 시간이다.
// 작업 006 계획 단계 4의 2, 3, 4, 6에서 옮겼다. 남의 결제 시험은 옮기지 않는다
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/records.dart';
import 'package:cherry_consume/store/routes/recommend.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const noGuess = {'card_id': 'shinhan-mrlife'};

const zeroCard = {'card_id': 'hyundai-zero-edition3-discount'};
const aug20 = '2026-08-20T12:00:00+09:00';

Json editOf(
  Store s,
  String tid,
  String card,
  int amount,
  String merchant, {
  String at = '2026-09-15T21:00:00+09:00',
  Json more = const {},
}) => edit(s, tid, {
  'user_card_id': card,
  'amount': amount,
  'merchant_name': merchant,
  'paid_at': at,
  ...more,
});

int total(Store s) => home(s)['benefit_total'] as int;

List<Json> recordsOf(Store s, [String month = '2026-09']) => [
  for (final x in records(s, month: month)['payments'] as List) x as Json,
];

int totalOf(Store s, [String month = '2026-09']) =>
    records(s, month: month)['benefit_total'] as int;

Json cancelOf(Store s, String tid, int amount, String at) =>
    cancel(s, tid, {'cancelled_amount': amount, 'cancelled_at': at});

/// IBK 나라사랑 철도 5%는 8만 구간부터 월 2회, 연 4회, 1회 2천 원까지. 취소는 취소한 달 실적에서 뺀다.
/// 5월 이마트 8만 원으로 6월이 8만 구간이다. 6월과 7월은 이마트 4만 원과 KTX 2만 원 두 번으로 실적 8만이고 KTX는
/// 5%로 1,000원씩이다. 연 4회를 다 써 8월 KTX 2만 원은 0원이다. 6월, 7월, 8월 혜택 합은 2,000, 2,000, 0원이다
(List<String>, String, List<int> Function()) naraYear(
  Store s, [
  List<Map<String, Object?>> more = const [],
]) {
  final ids = setup(s, [
    {'card_id': 'ibk-narasarang'},
    ...more,
  ]);
  final may =
      pay(s, ids[0], 80000, '이마트', at: '2026-05-20T12:00:00+09:00')['id']
          as String;
  for (final month in ['06', '07']) {
    pay(s, ids[0], 40000, '이마트', at: '2026-$month-02T12:00:00+09:00');
    pay(s, ids[0], 20000, 'KTX', at: '2026-$month-10T12:00:00+09:00');
    pay(s, ids[0], 20000, 'KTX', at: '2026-$month-20T12:00:00+09:00');
  }
  pay(s, ids[0], 20000, 'KTX', at: '2026-08-10T12:00:00+09:00');
  List<int> totals() => [
    for (final m in ['2026-06', '2026-07', '2026-08']) totalOf(s, m),
  ];
  expect(totals(), [2000, 2000, 0]);
  return (ids, may, totals);
}

List<Json> limitsOf(Json d) => [for (final x in d['limits'] as List) x as Json];
List<Json> lockedOf(Json d) => [for (final x in d['locked'] as List) x as Json];

void main() {
  test('test_card_detail', () {
    // GS25 4,300원 뒤 편의점 월 5회 가운데 1회, 통합 한도 월 1만 원 가운데 430원을 썼다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    final d = cardDetail(s, card);
    final limits = {for (final x in limitsOf(d)) x['title']: x};
    expect(
      (limits['편의점 10% 할인']!['used_count'], limits['편의점 10% 할인']!['cap_count']),
      (1, 5),
    );
    expect(
      (limits['통합 한도']!['used_amount'], limits['통합 한도']!['cap_amount']),
      (430, 10000),
    );
    // 위험 검토 15번. 주말 주유는 할인받는 결제액 월 30만 원 한도만 있다. 그래도 한도 줄에 보인다
    final fuel = [
      for (final x in limitsOf(d))
        if (x['cap_base'] != null) (x['per'], x['used_base'], x['cap_base']),
    ];
    expect(fuel, [('month', 0, 300000)]);
    // 30만 구간에서 받는 혜택은 모두 30만부터라 못 받는 혜택이 없다
    expect(d['locked'], isEmpty);
    expect(d['revision_from'], '2026-07-15');
    expect(d['check_sentences'], isNotEmpty);
  });

  test('test_card_detail_locked_benefits', () {
    // E37. 추정값 없이 0원 구간이면 30만부터인 혜택 10개를 못 받는다. 이번 달 4,300원을 써 30만까지 295,700원
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    pay(s, card, 4300, 'GS25');
    final locked = lockedOf(cardDetail(s, card));
    expect(locked, hasLength(10));
    expect(
      {for (final x in locked) (x['required_tier'], x['remaining'])},
      {(300000, 295700)},
    );
  });

  test('test_card_detail_hides_what_the_card_does_not_give', () {
    // 위험 검토 9번과 10번. 삼성 taptap O를 추정값 없이 등록하면 0원 구간이다. 혜택은 모두 30만 구간부터라 받는 혜택의
    // 한도가 없다. 패키지 옵션은 고르지 않았고 기본값이 없어 패키지 혜택 6개는 구간이 올라도 받지 못한다. 못 받는 혜택은
    // 대중교통, 택시, 이동통신, 영화 4개다
    final (:s, clock: _) = fresh();
    final [tap] = setup(s, [
      {'card_id': 'samsung-taptap-o'},
    ]);
    final d = cardDetail(s, tap);
    expect(d['limits'], isEmpty);
    expect(d['locked'], hasLength(4));
    expect([
      for (final x in lockedOf(d))
        if ((x['title'] as String).contains('패키지')) x,
    ], isEmpty);
  });

  test('test_card_detail_counts_unconfirmed_values_it_uses', () {
    // 위험 검토 14번. Mr.Life의 확인 필요 항목은 카드 전체 2개와 혜택별 3개다. 혜택별 3개는 모두 30만 구간부터라
    // 0원 구간이면 2개, 30만 구간이면 5개를 센다
    for (final (card, count) in [(noGuess, 2), (mrlife, 5)]) {
      final (:s, clock: _) = fresh();
      final [uid] = setup(s, [card]);
      expect(cardDetail(s, uid)['assumed_count'], count);
    }
  });

  test('test_card_detail_hides_limits_of_unpicked_options', () {
    // 위험 검토 10번 재검토. taptap O를 지난달 30만 원으로 등록하면 30만 구간이다. 대중교통과 택시가 함께 쓰는 월 5천 원,
    // 이동통신 월 5천 원, 영화 월 2회와 연 12회가 보인다. 패키지는 고르지 않아 패키지 혜택과 그 한도는 숨는다
    final (:s, clock: _) = fresh();
    final [tap] = setup(s, [
      {'card_id': 'samsung-taptap-o', 'assumed_prev_month_spend': 300000},
    ]);
    final d = cardDetail(s, tap);
    final got = [
      for (final x in limitsOf(d))
        '(${x['per']}, ${x['cap_amount']}, ${x['cap_count']})',
    ]..sort();
    expect(got, [
      '(month, 5000, null)',
      '(month, 5000, null)',
      '(month, null, 2)',
      '(year, null, 12)',
    ]);
    expect(d['locked'], isEmpty);
  });

  test('test_card_detail_tells_apart_benefits_with_the_same_title', () {
    // 재검토 중간 1번. IBK 나라사랑에는 "편의점 10% 청구할인"이 둘이다. 하나는 8만~20만 구간 월 2회, 하나는 25만 구간부터
    // 월 10회다. 8만 구간이면 월 2회만 보이고 25만 구간 혜택은 못 받는 혜택에 있다. 25만 구간이면 월 10회만 보인다
    const title = '편의점 10% 청구할인';
    for (final (prev, caps, locked) in [
      (80000, [2], [250000]),
      (250000, [10], <int>[]),
    ]) {
      final (:s, clock: _) = fresh();
      final [uid] = setup(s, [
        {'card_id': 'ibk-narasarang', 'assumed_prev_month_spend': prev},
      ]);
      final d = cardDetail(s, uid);
      expect([
        for (final x in limitsOf(d))
          if (x['title'] == title) x['cap_count'],
      ], caps);
      expect([
        for (final x in lockedOf(d))
          if (x['title'] == title) x['required_tier'],
      ], locked);
    }
  });

  test('test_card_detail_leaves_out_ended_events', () {
    // 재검토 중간 2번. IBK 슈마커 1만 원 청구할인은 2026-09-30에 끝난다. 10월 2일 카드 상세에는 그 한도가 없다
    final (:s, :clock) = fresh();
    final [nara] = setup(s, [
      {'card_id': 'ibk-narasarang', 'assumed_prev_month_spend': 80000},
    ]);
    bool shoe(Json d) =>
        limitsOf(d).any((b) => (b['title'] as String).contains('슈마커'));
    expect(shoe(cardDetail(s, nara)), isTrue);
    clock.now = DateTime.utc(2026, 10, 2, 3);
    expect(shoe(cardDetail(s, nara)), isFalse);
  });

  test('test_records_of_a_month', () {
    // 8월 이마트 30만 원으로 9월도 30만 구간이다. 9월은 GS25 4,300원 430원, 낮 스타벅스 4,500원 0원,
    // 상품권 1만 원 0원에 실적 제외. 9월 3건, 18,800원, 혜택 430원
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    pay(s, card, 300000, '이마트', at: aug20);
    pay(s, card, 4300, 'GS25');
    pay(s, card, 4500, '스타벅스', at: '2026-09-14T12:00:00+09:00');
    pay(
      s,
      card,
      10000,
      '상품권',
      at: '2026-09-13T12:00:00+09:00',
      more: {'category': 'gift_card'},
    );
    final r = records(s);
    expect(
      (r['month'], r['count'], r['amount'], r['benefit_total']),
      ('2026-09-01', 3, 18800, 430),
    );
    final rows = [
      for (final x in r['payments'] as List)
        (x['merchant_name'], x['value'], x['counted']),
    ];
    expect(rows, [('GS25', 430, true), ('스타벅스', 0, true), ('상품권', 0, false)]);
    expect((r['payments'] as List).first['rewards'], ['billing_discount']);
    expect(records(s, month: '2026-08')['count'], 1);
  });

  test('test_records_filtered_by_card', () {
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    pay(s, mr, 4300, 'GS25');
    pay(s, zero, 10000, '이마트');
    final r = records(s, card: zero);
    expect(
      [for (final x in r['payments'] as List) (x['user_card_id'], x['value'])],
      [(zero, 80)],
    );
  });

  test('test_edit_reprices_only_that_payment', () {
    // E50. GS25 4,300원을 1만 원으로 고치면 10%로 1,000원
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 4300, 'GS25')['id'];
    expect(editOf(s, tid, card, 10000, 'GS25')['value'], 1000);
    expect(total(s), 1000);
  });

  test('test_edit_last_month_reprices_this_month', () {
    // E54. 8월 30만 원으로 9월 30만 구간이라 GS25 430원. 8월을 20만 원으로 고치면 9월이 0원 구간이라 0원
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    final aug = pay(s, card, 300000, '이마트', at: aug20)['id'];
    pay(s, card, 4300, 'GS25');
    expect(editOf(s, aug, card, 200000, '이마트', at: aug20)['repriced'], 1);
    expect(total(s), 0);
  });

  test('test_delete_last_month_reprices_this_month', () {
    // E54. 추정값 없이 등록해 8월 30만 원이 9월 구간을 정한다. 8월 결제를 지우면 지난달 기록이 없어 0원 구간이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    final aug = pay(s, card, 300000, '이마트', at: aug20)['id'];
    pay(s, card, 4300, 'GS25');
    expect(total(s), 430);
    expect(delete(s, aug)['repriced'], 1);
    expect(total(s), 0);
    expect(records(s, month: '2026-08')['count'], 0);
  });

  test('test_edit_reprices_every_month_after_the_first_changed_tier', () {
    // E54 범위. 5월을 79,999원으로 고치면 6월만 0원 구간이 되어 6월 KTX 2건이 0원이다. 7월과 8월 구간은 그대로지만
    // 연 횟수가 2회 남아 8월 KTX가 1,000원이다. 다시 계산해 혜택이 바뀐 다른 결제는 6월 2건과 8월 1건이다
    final (:s, clock: _) = fresh();
    final ([nara], may, totals) = naraYear(s);
    final r = editOf(
      s,
      may,
      nara,
      79999,
      '이마트',
      at: '2026-05-20T12:00:00+09:00',
    );
    expect(totals(), [0, 2000, 1000]);
    expect(r['repriced'], 3);
  });

  test('test_cancel_in_cancel_month_reprices_from_the_month_after', () {
    // E5, E54. 5월 이마트 8만 원 가운데 1만 원을 6월 5일 취소하면 6월 실적에서 빠져 6월 실적이 7만이다. 6월 구간은 5월
    // 실적 그대로 8만이고 7월만 0원 구간이다. 7월 KTX가 0원, 연 2회가 남아 8월 KTX가 1,000원이다
    final (:s, clock: _) = fresh();
    final (_, may, totals) = naraYear(s);
    cancelOf(s, may, 10000, '2026-06-05T12:00:00+09:00');
    expect(totals(), [2000, 0, 1000]);
  });

  test('test_move_payment_reprices_the_old_card', () {
    // E54. 5월 이마트를 현대카드ZERO로 옮기면 나라사랑의 5월 실적이 0원이라 6월이 0원 구간이다. 6월 KTX가 0원,
    // 8월 KTX가 1,000원이다
    final (:s, clock: _) = fresh();
    final ([_, zero], may, totals) = naraYear(s, [zeroCard]);
    editOf(s, may, zero, 80000, '이마트', at: '2026-05-20T12:00:00+09:00');
    expect(totals(), [0, 2000, 1000]);
  });

  test('test_edit_reprices_a_payment_in_next_month', () {
    // 위험 검토 13번. 시계가 9월 30일 21시면 하루 뒤인 10월 1일 결제까지 받는다. 9월 이마트 30만 원으로 10월이
    // 30만 구간이라 GS25 4,300원이 430원이다. 9월을 20만 원으로 고치면 10월이 0원 구간이라 0원이다
    final (:s, :clock) = fresh();
    clock.now = DateTime.utc(2026, 9, 30, 12);
    final [card] = setup(s, [noGuess]);
    final sep = pay(
      s,
      card,
      300000,
      '이마트',
      at: '2026-09-20T12:00:00+09:00',
    )['id'];
    expect(
      pay(s, card, 4300, 'GS25', at: '2026-10-01T10:00:00+09:00')['value'],
      430,
    );
    editOf(s, sep, card, 200000, '이마트', at: '2026-09-20T12:00:00+09:00');
    expect(totalOf(s, '2026-10'), 0);
  });

  test('test_cancel_full_and_partial', () {
    // E5. 4,300원 전액 취소면 0원. 1만 원 결제의 5,000원 취소면 남은 5,000원의 10%로 500원
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final small = pay(s, card, 4300, 'GS25')['id'];
    expect(cancelOf(s, small, 4300, '2026-09-15T21:10:00+09:00')['value'], 0);
    final big = pay(
      s,
      card,
      10000,
      'GS25',
      at: '2026-09-14T21:00:00+09:00',
    )['id'];
    expect(cancelOf(s, big, 5000, '2026-09-14T22:00:00+09:00')['value'], 500);
    // 실적은 0원과 남은 5,000원
    expect((home(s)['cards'] as List).first['spend']['counted'], 5000);
  });

  test('test_move_payment_to_another_card', () {
    // GS25 4,300원을 ZERO로 옮기면 0.8%로 34원. 원 미만은 버린다
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    final tid = pay(s, mr, 4300, 'GS25')['id'];
    expect(editOf(s, tid, zero, 4300, 'GS25')['value'], 34);
    final cards = {for (final c in home(s)['cards'] as List) c['card_id']: c};
    expect(cards['shinhan-mrlife']['spend']['counted'], 0);
  });

  test('test_bad_changes', () {
    // 남의 결제 시험은 옮기지 않는다. 사용자가 한 명이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 4300, 'GS25')['id'];
    expect(
      () => cancelOf(s, tid, 5000, '2026-09-15T21:10:00+09:00'),
      throwsA(status(422)),
    );
    expect(
      () => cancelOf(s, tid, 100, '2026-09-15T20:00:00+09:00'),
      throwsA(status(422)),
    );
    delete(s, tid);
    expect(() => delete(s, tid), throwsA(status(404)));
  });

  test('test_cancel_keeps_the_month_spend_of_a_benefit_payment', () {
    // E5. KB 톡톡은 혜택 받은 결제를 실적에서 빼고 취소한 달 기준이다. 7월 30만으로 8월 30만 구간
    // 8/10 스타벅스 2만 원은 50%가 월 1만 원 한도를 채워 1만 원 할인, 실적 0. 8/20 기타 29만이라 8월 실적 29만, 9월 0원 구간
    // 9/3에 8월 스타벅스를 전액 취소해도 처음 실적이 0이라 8월은 29만 그대로다. 9월은 0원 구간이고 다시 계산할 결제도 없다
    final (:s, clock: _) = fresh();
    final [kb] = setup(s, [
      {'card_id': 'kb-toktok'},
    ]);
    const method = {'payment_method': 'physical_card'};
    pay(
      s,
      kb,
      300000,
      '기타',
      at: '2026-07-20T12:00:00+09:00',
      more: {...method, 'category': 'other'},
    );
    final sb = pay(
      s,
      kb,
      20000,
      '스타벅스',
      at: '2026-08-10T08:30:00+09:00',
      more: method,
    );
    expect(sb['value'], 10000);
    pay(
      s,
      kb,
      290000,
      '기타',
      at: '2026-08-20T12:00:00+09:00',
      more: {...method, 'category': 'other'},
    );
    expect(
      pay(
        s,
        kb,
        10000,
        '스타벅스',
        at: '2026-09-05T08:30:00+09:00',
        more: method,
      )['value'],
      0,
    );
    final r = cancelOf(s, sb['id'], 20000, '2026-09-03T10:00:00+09:00');
    expect((r['value'], r['repriced']), (0, 0));
    // 저장된 기록으로 다시 세도 9월은 0원 구간이다. 엔진이 취소하지 않은 결제로 다시 계산해 처음 실적을 센다
    final spend = (home(s)['cards'] as List).first['spend'];
    expect((spend['tier'], spend['prev_month_counted']), (0, 290000));
  });

  test('test_records_show_spend_like_the_engine_after_cancel', () {
    // 삼성 taptap O는 혜택 받은 결제를 실적에서 뺀다. 7월 30만으로 8월 30만 구간. 8/10 CGV 15,000원은 1만 원 이상 5,000원 할인으로 실적 0
    // 9/3에 6,000원을 부분 취소하면 남은 9,000원은 1만 원 미만이라 할인이 없다. 취소로 실적을 늘리지 않아 엔진은 8월 0원이다
    // 기록 목록도 엔진처럼 실적 제외로 보여야 한다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [
      {'card_id': 'samsung-taptap-o'},
    ]);
    pay(
      s,
      card,
      300000,
      '기타',
      at: '2026-07-20T12:00:00+09:00',
      more: {'category': 'other'},
    );
    final cgv = pay(s, card, 15000, 'CGV 강남', at: '2026-08-10T19:00:00+09:00');
    expect(cgv['value'], 5000);
    expect(
      cancelOf(s, cgv['id'], 6000, '2026-09-03T10:00:00+09:00')['value'],
      0,
    );
    expect(
      [
        for (final x in recordsOf(s, '2026-08'))
          (x['merchant_name'], x['counted']),
      ],
      [('CGV 강남', false)],
    );
  });

  test('test_edit_cannot_move_a_payment_after_its_cancel', () {
    // 위험 검토 6번. 9월 14일 21시 결제를 22시에 일부 취소했다. 결제 시각을 15일로 고치면 취소보다 뒤라 422다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(
      s,
      card,
      10000,
      'GS25',
      at: '2026-09-14T21:00:00+09:00',
    )['id'];
    cancelOf(s, tid, 5000, '2026-09-14T22:00:00+09:00');
    expect(
      () =>
          editOf(s, tid, card, 10000, 'GS25', at: '2026-09-15T21:00:00+09:00'),
      throwsA(status(422)),
    );
    editOf(s, tid, card, 10000, 'GS25', at: '2026-09-14T20:00:00+09:00');
  });

  test('test_more_cancel_in_another_month_is_unsupported', () {
    // 위험 검토 5번. 8월 결제를 8월에 3,000원 취소했다. 9월에 더 취소해 합을 5,000원으로 올리면 취소 시각이 하나라
    // 담지 못해 422다. 금액을 그대로 두고 시각만 9월로 고치는 것은 받는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 10000, '이마트', at: aug20)['id'];
    cancelOf(s, tid, 3000, '2026-08-25T12:00:00+09:00');
    expect(
      () => cancelOf(s, tid, 5000, '2026-09-10T12:00:00+09:00'),
      throwsA(status(422)),
    );
    // 합 대신 이번 취소 2,000원만 적어 달을 바꾸면 8월 3,000원 취소가 사라진다. 이것도 막는다
    expect(
      () => cancelOf(s, tid, 2000, '2026-09-10T12:00:00+09:00'),
      throwsA(status(422)),
    );
    cancelOf(s, tid, 3000, '2026-09-10T12:00:00+09:00');
    // 취소한 적 없는 결제는 되돌릴 것이 없어 422다
    final other = pay(s, card, 4300, 'GS25')['id'];
    expect(
      () => cancelOf(s, other, 0, '2026-09-15T21:10:00+09:00'),
      throwsA(status(422)),
    );
  });

  test('test_cancel_zero_undoes_the_cancel', () {
    // 위험 검토 16번. GS25 4,300원을 전액 취소하면 0원이다. 0원 취소로 되돌리면 다시 430원이고 취소 시각도 지운다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 4300, 'GS25')['id'];
    expect(cancelOf(s, tid, 4300, '2026-09-15T21:10:00+09:00')['value'], 0);
    expect(recordsOf(s).first['cancelled_at'], isNotNull);
    expect(cancelOf(s, tid, 0, '2026-09-15T21:20:00+09:00')['value'], 430);
    final row = recordsOf(s).first;
    expect(
      (row['cancelled_amount'], row['cancelled_at'], row['value']),
      (0, null, 430),
    );
  });

  test('test_payment_without_a_revision_is_not_counted', () {
    // 위험 검토 17번. Mr.Life 개정은 2026-07-15부터다. 7월 1일 결제는 맞는 개정이 없어 계산하지 않고 실적에도 넣지 않는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    pay(s, card, 10000, '이마트', at: '2026-07-01T12:00:00+09:00');
    final [row] = recordsOf(s, '2026-07');
    expect((row['value'], row['counted']), (0, false));
  });

  test('test_past_month_ranked_benefit_uses_the_month_end_rank', () {
    // 위험 검토 7번, E48. 삼성 iD ON은 30만 구간부터 그 달 이용액 1위 영역만 30% 할인, 월 1만 원까지다. 7월 이마트
    // 30만 원으로 8월이 30만 구간이다. 8월 5일 스타벅스 1만 원은 그때 커피가 1위라 3,000원이었다. 8월 20일 배민 2만 원이
    // 들어오면 8월 끝 1위는 배달이라 스타벅스 0원, 배민 6,000원이다. 배민을 5,000원으로 고치면 다시 커피가 1위라
    // 스타벅스 3,000원, 배민 0원이다
    final (:s, clock: _) = fresh();
    final [ion] = setup(s, [
      {'card_id': 'samsung-id-on'},
    ]);
    pay(s, ion, 300000, '이마트', at: '2026-07-10T12:00:00+09:00');
    expect(
      pay(s, ion, 10000, '스타벅스', at: '2026-08-05T12:00:00+09:00')['value'],
      3000,
    );
    final baemin = pay(s, ion, 20000, '배민', at: aug20);
    expect(baemin['value'], 6000);
    Map<Object?, Object?> august() => {
      for (final r in recordsOf(s, '2026-08')) r['merchant_name']: r['value'],
    };
    expect(august(), {'스타벅스': 0, '배민': 6000});
    editOf(s, baemin['id'], ion, 5000, '배민', at: aug20);
    expect(august(), {'스타벅스': 3000, '배민': 0});
  });

  test('test_cancel_does_not_rerank_a_past_month', () {
    // 재검토 중간 3번, E55. 8월 스타벅스 1만 5천 원 4,500원, 배민 1만 2천 원 0원이다. 9월 3일 스타벅스 5,000원 취소를
    // 적으면 스타벅스만 남은 1만 원의 30%로 3,000원이고 배민은 0원 그대로다
    final (:s, clock: _) = fresh();
    final [ion] = setup(s, [
      {'card_id': 'samsung-id-on'},
    ]);
    pay(s, ion, 300000, '이마트', at: '2026-07-10T12:00:00+09:00');
    final star = pay(s, ion, 15000, '스타벅스', at: '2026-08-05T12:00:00+09:00');
    expect(star['value'], 4500);
    expect(pay(s, ion, 12000, '배민', at: aug20)['value'], 0);
    cancelOf(s, star['id'], 5000, '2026-09-03T12:00:00+09:00');
    expect(
      {for (final r in recordsOf(s, '2026-08')) r['merchant_name']: r['value']},
      {'스타벅스': 3000, '배민': 0},
    );
  });

  test('test_move_last_month_payment_into_this_month', () {
    // 위험 검토 19번. 8월 이마트 30만 원으로 9월이 30만 구간이라 GS25 4,300원 430원이다. 이마트를 9월 1일로 옮기면
    // 8월 실적이 0원이라 9월이 0원 구간이고 GS25도 0원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    final aug = pay(s, card, 300000, '이마트', at: aug20)['id'];
    pay(s, card, 4300, 'GS25');
    editOf(s, aug, card, 300000, '이마트', at: '2026-09-01T12:00:00+09:00');
    expect(totalOf(s), 0);
  });

  test('test_tier_boundary_299999_and_300000', () {
    // 위험 검토 19번. 8월 실적 299,999원이면 9월이 0원 구간이라 GS25 0원, 30만 원으로 고치면 30만 구간이라 430원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [noGuess]);
    final aug = pay(s, card, 299999, '이마트', at: aug20)['id'];
    pay(s, card, 4300, 'GS25');
    expect(totalOf(s), 0);
    editOf(s, aug, card, 300000, '이마트', at: aug20);
    expect(totalOf(s), 430);
  });

  test('test_edit_a_cancelled_payment_keeps_the_cancel', () {
    // 위험 검토 19번. GS25 1만 원 가운데 5,000원을 취소해 500원이다. 1만 2,000원으로 고치면 취소는 그대로라 남은
    // 7,000원의 10%로 700원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(
      s,
      card,
      10000,
      'GS25',
      at: '2026-09-14T21:00:00+09:00',
    )['id'];
    expect(cancelOf(s, tid, 5000, '2026-09-14T22:00:00+09:00')['value'], 500);
    expect(
      editOf(
        s,
        tid,
        card,
        12000,
        'GS25',
        at: '2026-09-14T21:00:00+09:00',
      )['value'],
      700,
    );
  });

  test('test_edit_a_payment_on_a_removed_card', () {
    // 위험 검토 19번. 해지한 카드의 결제도 그 카드 그대로 고친다. GS25 4,300원을 1만 원으로 고치면 1,000원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 4300, 'GS25')['id'];
    removeCard(s, card);
    expect(editOf(s, tid, card, 10000, 'GS25')['value'], 1000);
  });

  test('test_remove_card', () {
    // S9. 해지하면 홈과 추천에서 빠지고 기록과 받은 혜택 합계에는 남는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    removeCard(s, card);
    final h = home(s);
    expect(h['cards'], isEmpty);
    expect(h['benefit_total'], 430);
    expect(records(s)['count'], 1);
    expect(recommend(s, {'merchant_name': 'GS25'})['ranking'], isEmpty);
    expect(() => cardDetail(s, card), throwsA(status(404)));
    expect(() => pay(s, card, 1000, 'GS25'), throwsA(status(404)));
  });
}
