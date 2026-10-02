// 실적 계산 규칙. Python `backend/tests/engine/test_spend.py`를 옮겼다. 엔진 설계 2절. 기대값은 손계산이다
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const cafe10 = {
  'key': 'cafe-10',
  'target': {
    'categories': ['cafe'],
  },
  'reward': {'type': 'billing_discount', 'rate': 10},
  'limits': [
    {'per': 'month', 'amount': 5000},
  ],
  'tiers': {'from': 300000},
};
final sept = day(2026, 9, 1);

/// 구간 없는 cafe10
Json get flat => {...cafe10}..remove('tiers');

SpendStatus status(
  Engine eng,
  List<Payment> payments, [
  UserCard? holderCard,
  DateTime? month,
]) {
  final h = holderCard ?? holder();
  final priced = eng.priceMonth(h, payments);
  return eng.spendStatus(h, saved(payments, priced), month ?? sept);
}

List<(int, int)> monthsAndAmounts(PaymentResult r) => [
  for (final p in r.spend) (p.month.month, p.amount),
];

const cafeMin5 = {
  'key': 'cafe-min-5',
  'target': {
    'categories': ['cafe'],
  },
  'when': [
    {
      'amount': {'min': 10000},
    },
  ],
  'reward': {'type': 'billing_discount', 'rate': 5},
  'tiers': {'from': 300000},
};

void main() {
  test('test_tier_from_previous_month', () {
    // 지난달 35만 → 30만 구간. 이번 달 18.2만 → 유지까지 30만 − 18.2만 = 11.8만, 60만까지 41.8만. 시안 6쪽
    final eng = engine([
      card([cafe10]),
    ]);
    final s = status(eng, [
      ...prevMonth(350000),
      pay(182000, '2026-09-10T12:00', category: 'other'),
    ]);
    expect(
      (s.tier, s.tierSource, s.prevMonthCounted),
      (300000, 'prev_month', 350000),
    );
    expect(
      (s.counted, s.toKeep, s.nextTier, s.toNext),
      (182000, 118000, 600000, 418000),
    );
  });

  test('test_tier_lower_bound_boundary', () {
    // 하한 1원 아래는 아래 구간, 하한은 그 구간
    final eng = engine([
      card([cafe10]),
    ]);
    expect(status(eng, prevMonth(299999)).tier, 0);
    expect(status(eng, prevMonth(300000)).tier, 300000);
  });

  test('test_registration_month_uses_estimate_only_without_records', () {
    // E2. 등록한 달에 지난달 기록이 없으면 추정값, 추정값도 없으면 0 구간과 경고, 기록이 있으면 기록
    final eng = engine([
      card([cafe10]),
    ]);
    final newCard = holder(
      registeredOn: day(2026, 9, 10),
      assumedPrevMonthSpend: 410000,
    );
    var s = status(eng, [], newCard);
    expect(
      (s.tier, s.tierSource),
      (300000, 'assumed'),
    ); // 시안 4쪽. 지난달 41만이면 30만 구간
    s = status(eng, [], holder(registeredOn: day(2026, 9, 10)));
    expect(s.tier, 0);
    expect([
      for (final w in s.warnings) w.code,
    ], contains('no_prev_month_data'));
    s = status(eng, prevMonth(100000), newCard);
    expect(
      (s.tier, s.tierSource, s.prevMonthCounted),
      (0, 'prev_month', 100000),
    );
  });

  test('test_excluded_category_and_interest_free', () {
    final eng = engine([
      card([cafe10], spend: {'interest_free': 'exclude'}),
    ]);
    final h = holder();
    final tax = pay(128000, '2026-09-18T09:00', category: 'tax');
    final free = pay(
      50000,
      '2026-09-18T10:00',
      category: 'other',
      interestFree: true,
    );
    final r = eng.priceMonth(h, [tax, free]);
    // 시안 10쪽 자동차세 실적 제외
    expect(r[0].spend, isEmpty);
    expect(r[0].warnings[0].data, {'reason': 'category'});
    expect(r[1].spend, isEmpty);
    expect(r[1].warnings[0].data, {'reason': 'interest_free'});
  });

  test('test_parent_category_is_excluded_conservatively', () {
    // 설계 2.1. 지하철만 빼는 카드에 대중교통까지만 아는 결제는 뺀 것으로 보고 자식 업종을 묻는다
    final eng = engine([
      card(
        [cafe10],
        spend: {
          'exclude_categories': ['transit.subway'],
        },
      ),
    ]);
    final r = eng.priceMonth(holder(), [
      pay(1500, '2026-09-02T08:00', category: 'transit'),
    ])[0];
    expect(r.spend, isEmpty);
    expect(codes(r).take(2), ['not_counted_toward_spend', 'needs_input']);
    expect(r.warnings[1].data['needs'], [
      ['category', 'transit'],
    ]);
  });

  test('test_region_only_domestic', () {
    final eng = engine([
      card(
        [cafe10],
        spend: {
          'regions': ['domestic'],
        },
      ),
    ]);
    final r = eng.priceMonth(holder(), [
      pay(30000, '2026-09-02T08:00', category: 'other', region: 'overseas'),
    ])[0];
    expect(r.spend, isEmpty);
    expect(r.warnings[0].data, {'reason': 'region'});
  });

  test('test_benefit_applied_ratio', () {
    // 우리 K-LIFE처럼 혜택 받은 결제는 50%만. 30,001원이면 15,000.5 → 원 미만 버림 15,000
    final eng = engine([
      card([flat], tiers: [0], spend: {'exclude_applied': 0.5}),
    ]);
    final r = eng.priceMonth(holder(), [
      pay(30001, '2026-09-02T08:00', merchant: 'starbucks'),
    ])[0];
    expect(r.benefits[0].value, 3000);
    expect(r.spend[0].amount, 15000);
  });

  test('test_month_offset_moves_transit_to_next_month', () {
    // 신한처럼 9월에 탄 지하철은 10월 실적
    final eng = engine([
      card(
        [cafe10],
        spend: {
          'month_offset': {'transit.subway': 1},
        },
      ),
    ]);
    final r = eng.priceMonth(holder(), [
      pay(1500, '2026-09-02T08:00', category: 'transit.subway'),
    ])[0];
    expect(r.spend, [SpendPart(day(2026, 10, 1), 1500)]);
  });

  test('test_installment_split_by_month', () {
    // E4. 100,000원 3개월이면 33,333, 33,333, 나머지 33,334
    final eng = engine([
      card([cafe10], spend: {'installment': 'per_installment_month'}),
    ]);
    final r = eng.priceMonth(holder(), [
      pay(100000, '2026-09-02T08:00', category: 'other', installmentMonths: 3),
    ])[0];
    expect([for (final p in r.spend) p.amount], [33333, 33333, 33334]);
    expect([for (final p in r.spend) p.month.month], [9, 10, 11]);
  });

  test('test_cancellation_months', () {
    // 8월 10만원을 9월 5일에 4만원 취소. cancel_month면 9월에서, original_month면 8월에서 뺀다
    Payment cancelled({String region = 'domestic'}) => pay(
      100000,
      '2026-08-20T10:00',
      category: 'other',
      region: region,
      cancelledAmount: 40000,
      cancelledAt: at('2026-09-05T10:00'),
    );
    var eng = engine([
      card([cafe10]),
    ]);
    var r = eng.priceMonth(holder(), [cancelled()])[0];
    expect(monthsAndAmounts(r), [(8, 100000), (9, -40000)]);
    eng = engine([
      card(
        [cafe10],
        spend: {
          'cancellation': 'original_month',
          'cancellation_overrides': [
            {
              'when': {'region': 'overseas'},
              'use': 'cancel_month',
            },
          ],
        },
      ),
    ]);
    r = eng.priceMonth(holder(), [cancelled()])[0];
    expect(monthsAndAmounts(r), [(8, 100000), (8, -40000)]);
    r = eng.priceMonth(holder(), [cancelled(region: 'overseas')])[0];
    expect(monthsAndAmounts(r), [(8, 100000), (9, -40000)]);
  });

  test('test_original_month_cancellation_lowers_this_month_tier', () {
    // E5. 8월 35만 중 10만을 original_month로 취소하면 8월 25만 → 9월 구간 0
    final eng = engine([
      card([cafe10], spend: {'cancellation': 'original_month'}),
    ]);
    final p = pay(
      350000,
      '2026-08-10T10:00',
      category: 'other',
      cancelledAmount: 100000,
      cancelledAt: at('2026-09-03T10:00'),
    );
    expect(status(eng, [p]).tier, 0);
  });

  test('test_month_below_zero_counts_as_zero', () {
    final eng = engine([
      card([cafe10]),
    ]);
    final p = pay(
      50000,
      '2026-08-31T10:00',
      category: 'other',
      cancelledAmount: 50000,
      cancelledAt: at('2026-09-01T10:00'),
    );
    expect(status(eng, [p]).counted, 0);
  });

  test('test_korean_time_month_boundary', () {
    // E7. 8월 31일 23:30 한국 시간은 8월, 협정 세계시 8월 31일 15:30은 한국 시간 9월 1일 00:30이라 9월
    final eng = engine([
      card([cafe10]),
    ]);
    final late = pay(10000, '2026-08-31T23:30', category: 'other');
    final utc = Payment(
      id: 'utc',
      userCardId: 'u1',
      amount: 10000,
      paidAt: DateTime.utc(2026, 8, 31, 15, 30),
      category: 'other',
    );
    expect(eng.priceMonth(holder(), [late])[0].spend[0].month, day(2026, 8, 1));
    expect(eng.priceMonth(holder(), [utc])[0].spend[0].month, day(2026, 9, 1));
  });

  test('test_new_card_period', () {
    // 9월 5일부터 쓴 카드는 9월과 10월에 30만 구간 특례. 11월은 10월 실적대로
    final eng = engine([
      card(
        [cafe10],
        rules: {
          'new_card': {
            'from': 'registration',
            'until': 'next_month_end',
            'tier': 300000,
          },
        },
      ),
    ]);
    final newCard = holder(startedOn: day(2026, 9, 5));
    expect(
      (status(eng, [], newCard).tier, status(eng, [], newCard).tierSource),
      (300000, 'new_card'),
    );
    expect(status(eng, [], newCard, day(2026, 10, 1)).tier, 300000);
    expect(status(eng, [], newCard, day(2026, 11, 1)).tier, 0);
  });

  test('test_new_card_tier_by_benefit', () {
    // tier_by_benefit 0인 혜택은 특례가 없다
    final eng = engine([
      card(
        [cafe10],
        rules: {
          'new_card': {
            'from': 'registration',
            'until': 'next_month_end',
            'tier': 300000,
            'tier_by_benefit': {'cafe-10': 0},
          },
        },
      ),
    ]);
    final r = eng.priceMonth(holder(startedOn: day(2026, 9, 5)), [
      pay(10000, '2026-09-10T10:00', merchant: 'starbucks'),
    ])[0];
    expect(r.benefits, isEmpty);
    expect(r.warnings[0].code, 'tier_not_met');
  });

  test('test_basis_none_and_billing_cycle', () {
    // E6. 실적 조건 없는 카드는 구간을 세지 않고, 결제일 기준 실적 카드는 계산하지 않는다
    var s = status(
      engine([
        card([flat], tiers: [0], spend: {'basis': 'none'}),
      ]),
      [],
    );
    expect((s.tier, s.tierSource, s.toKeep, s.toNext), (0, 'none', null, null));
    s = status(
      engine([
        card([cafe10], spend: {'basis': 'billing_cycle'}),
      ]),
      prevMonth(350000),
    );
    expect((s.tier, s.tierSource), (0, 'unsupported'));
    expect([
      for (final w in s.warnings) w.code,
    ], contains('spend_basis_unsupported'));
  });

  test('test_partial_cancellation_counts_like_remaining_amount', () {
    // 혜택 받은 결제는 50%. 10,001원 중 5,000원 취소면 남은 5,001원의 50% 2,500.5 → 2,500. 5,000 − 2,500 = 2,500을 뺀다
    final eng = engine([
      card([flat], tiers: [0], spend: {'exclude_applied': 0.5}),
    ]);
    final p = pay(
      10001,
      '2026-09-02T08:00',
      merchant: 'starbucks',
      cancelledAmount: 5000,
      cancelledAt: at('2026-09-03T08:00'),
    );
    final r = eng.priceMonth(holder(), [p])[0];
    expect(r.spend.fold(0, (s, x) => s + x.amount), 2500);
  });

  test('test_cancellation_cannot_exceed_payment_and_needs_time', () {
    // 결제보다 큰 취소와 시각 없는 취소는 받지 않는다. 취소한 달 기준 카드에서 달을 정할 수 없다. E5
    expect(
      () => pay(
        30000,
        '2026-09-02T08:00',
        cancelledAmount: 50000,
        cancelledAt: at('2026-09-03T08:00'),
      ),
      throwsArgumentError,
    );
    expect(
      () => pay(30000, '2026-09-02T08:00', cancelledAmount: 10000),
      throwsArgumentError,
    );
  });

  test('test_month_recompute_after_original_month_cancellation', () {
    // 8월 100만원 중 10만원을 9월 10일에 결제한 달 기준으로 취소하면 9월 구간이 100만에서 50만으로 내려간다.
    // 서버가 9월을 다시 계산해 9월 5일 5% 5,000원이 1.5% 1,500원이 된다. 2026-09-29 사용자가 정했다. E5
    final rates = [
      {
        ...cafe10,
        'key': 'cafe-5',
        'reward': {'type': 'billing_discount', 'rate': 5},
        'tiers': {'from': 1000000},
      }..remove('limits'),
      {
        ...cafe10,
        'key': 'cafe-15',
        'reward': {'type': 'billing_discount', 'rate': 1.5},
        'tiers': {'to': 500000},
      }..remove('limits'),
    ];
    final eng = engine([
      card(
        rates,
        tiers: [0, 500000, 1000000],
        spend: {'cancellation': 'original_month'},
      ),
    ]);
    final aug = [
      pay(900000, '2026-08-10T10:00', category: 'other'),
      pay(100000, '2026-08-20T10:00', category: 'other'),
    ];
    final septPay = pay(100000, '2026-09-05T10:00', merchant: 'starbucks');
    final first = eng.priceMonth(holder(), [...aug, septPay]);
    expect([for (final b in first[2].benefits) b.value], [5000]);
    final kept = saved([...aug, septPay], first);
    kept[1] = kept[1].copyWith(
      cancelledAmount: 100000,
      cancelledAt: at('2026-09-10T10:00'),
    );
    final again = eng.priceMonth(holder(), kept, month: sept);
    expect([for (final b in again[0].benefits) b.value], [1500]);
  });

  Payment cancelOn(
    int paid,
    String when,
    int amount, {
    String category = 'cafe',
  }) => pay(
    paid,
    when,
    category: category,
    cancelledAmount: amount,
    cancelledAt: at('2026-09-03T10:00'),
  );

  test('test_cancelled_benefit_payment_keeps_paid_month_spend', () {
    // E5, 설계 문서 6.5. 혜택 받은 결제를 실적에서 다 빼고 취소한 달 기준인 카드. 7월 30만으로 8월 30만 구간
    // 8월 카페 2만 원은 10% 2,000원을 받아 실적 0. 기타 29만 원으로 8월 실적 29만. 9월 3일 카페 전액 취소에도 처음 실적이 0이라
    // 뺄 것이 없다. 저장된 기록으로 다시 세도 8월 29만, 9월 0원 구간이다. 취소 뒤 빈 혜택으로 세면 8월이 31만이 되었다
    final eng = engine([
      card(
        [cafe10],
        spend: {'exclude_applied': 1, 'cancellation': 'cancel_month'},
      ),
    ]);
    final payments = [
      ...prevMonth(300000, '2026-07'),
      cancelOn(20000, '2026-08-10T10:00', 20000),
      pay(290000, '2026-08-20T10:00', category: 'other'),
    ];
    final s = status(eng, payments);
    expect((s.prevMonthCounted, s.tier), (290000, 0));
  });

  test('test_cancel_half_excluded_benefit_payment', () {
    // 혜택 받은 결제를 반만 빼는 카드. 8월 카페 2만 원은 10% 2,000원을 받아 실적 1만
    // 9월 전액 취소면 8월에 1만을 넣고 9월에서 1만을 뺀다
    final eng = engine([
      card(
        [cafe10],
        spend: {'exclude_applied': 0.5, 'cancellation': 'cancel_month'},
      ),
    ]);
    final payments = [
      ...prevMonth(300000, '2026-07'),
      cancelOn(20000, '2026-08-10T10:00', 20000),
    ];
    final r = eng.priceMonth(holder(), payments)[1];
    expect(monthsAndAmounts(r), [(8, 10000), (9, -10000)]);
  });

  test('test_partial_cancel_never_adds_spend', () {
    // 8월 카페 12,000원은 1만 원 이상 5%로 600원을 받고 반만 빼 실적 6,000. 9월에 5,000원을 취소하면 남은 7,000원은 혜택을 잃어
    // 실적이 7,000이 되어야 하는지 카드사 문구가 없다. 취소로 실적을 늘리지 않는다. 부풀리지 않는 쪽이다. 확인 필요
    final eng = engine([
      card(
        [cafeMin5],
        spend: {'exclude_applied': 0.5, 'cancellation': 'cancel_month'},
      ),
    ]);
    final payments = [
      ...prevMonth(300000, '2026-07'),
      cancelOn(12000, '2026-08-10T10:00', 5000),
    ];
    final r = eng.priceMonth(holder(), payments)[1];
    expect(monthsAndAmounts(r), [(8, 6000)]);
  });

  test('test_cancel_benefit_payment_in_paid_month_basis', () {
    // 결제한 달 기준이어도 혜택 받아 실적 0인 결제는 전액 취소로 뺄 것이 없다. 8월은 기타 29만 그대로
    final eng = engine([
      card(
        [cafe10],
        spend: {'exclude_applied': 1, 'cancellation': 'original_month'},
      ),
    ]);
    final payments = [
      ...prevMonth(300000, '2026-07'),
      cancelOn(20000, '2026-08-10T10:00', 20000),
      pay(290000, '2026-08-20T10:00', category: 'other'),
    ];
    expect(status(eng, payments).prevMonthCounted, 290000);
  });
}
