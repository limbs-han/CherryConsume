// 추천. Python `backend/tests/engine/test_recommend.py`를 옮겼다. 엔진 설계 4절. 기대값은 손계산이다
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final now = at('2026-09-19T14:20');

Json b(String key, Json target, Json reward, [Json kw = const {}]) => {
  'key': key,
  'target': target,
  'reward': reward,
  ...kw,
};

(Engine, UserCard, UserCard) twoCards() {
  final cafe = card(
    [
      b(
        'cafe-10',
        {
          'categories': ['cafe'],
        },
        {'type': 'billing_discount', 'rate': 10},
        {
          'limits': [
            {'per': 'txn', 'amount': 1000},
          ],
        },
      ),
    ],
    id: 'test-cafe',
    tiers: [0],
  );
  final flat = card(
    [
      b('all-07', {'all': true}, {'type': 'billing_discount', 'rate': 0.7}),
    ],
    id: 'test-flat',
    tiers: [0],
  );
  return (
    engine([cafe, flat]),
    holder(id: 'a', cardId: 'test-cafe'),
    holder(id: 'b', cardId: 'test-flat'),
  );
}

List<Payment> asCard(List<Payment> ps, String uid) => [
  for (final p in ps) p.copyWith(userCardId: uid),
];

void main() {
  test('test_order_by_value_and_default_amount', () {
    // 1만원 기준: 카페 카드 1,000원, 0.7% 카드 70원. 시안 9쪽의 1위와 2위
    final (eng, cafe, flat) = twoCards();
    final [rows] = eng.recommend(
      [cafe, flat],
      {},
      [const Query(merchant: 'starbucks')],
      now,
    );
    expect(
      [for (final r in rows) (r.cardId, r.value)],
      [('test-cafe', 1000), ('test-flat', 70)],
    );
    expect([
      for (final w in rows[0].warnings) w.code,
    ], contains('default_amount_used'));
  });

  test('test_tie_prefers_card_short_of_tier', () {
    // 기대 혜택이 같으면 이번 결제가 실적에 들어가고 유지까지 남은 금액이 적은 카드가 앞. S5
    final one = card([
      b('all-1', {'all': true}, {'type': 'billing_discount', 'rate': 1}),
    ], id: 'test-one');
    final two = card([
      b('all-1', {'all': true}, {'type': 'billing_discount', 'rate': 1}),
    ], id: 'test-two');
    final eng = engine([one, two]);
    final a = holder(id: 'a', cardId: 'test-one'),
        c = holder(id: 'c', cardId: 'test-two');
    final history = {
      'a': asCard([
        ...prevMonth(350000),
        pay(100000, '2026-09-05T10:00', category: 'other'),
      ], 'a'),
      'c': asCard([
        ...prevMonth(350000),
        pay(250000, '2026-09-05T10:00', category: 'other'),
      ], 'c'),
    };
    final [rows] = eng.recommend(
      [a, c],
      history,
      [const Query(category: 'other', amount: 10000)],
      now,
    );
    expect(
      [for (final r in rows) (r.cardId, r.toKeep)],
      [('test-two', 50000), ('test-one', 200000)],
    );
  });

  test('test_locked_benefit', () {
    // 90만 구간 스타벅스 20%. 이번 달 18.2만이면 71.8만 더. 1만원 × 20% = 2,000. 시안 9쪽
    final sb = b(
      'sb-20',
      {
        'merchants': ['starbucks'],
      },
      {'type': 'billing_discount', 'rate': 20},
      {
        'tiers': {'from': 900000},
      },
    );
    final eng = engine([
      card([sb], id: 'test-mr', tiers: [0, 300000, 600000, 900000]),
    ]);
    final h = holder(id: 'm', cardId: 'test-mr');
    final history = {
      'm': asCard([
        ...prevMonth(410000),
        pay(182000, '2026-09-05T10:00', category: 'other'),
      ], 'm'),
    };
    final [rows] = eng.recommend(
      [h],
      history,
      [const Query(merchant: 'starbucks')],
      now,
    );
    final [lock] = rows[0].locked;
    expect(
      (
        lock.benefit,
        lock.requiredTier,
        lock.remainingThisMonth,
        lock.valueIfUnlocked,
      ),
      ('sb-20', 900000, 718000, 2000),
    );
  });

  test('test_conditional_payment_method_and_fact', () {
    // 네이버페이면 +1,000원, 현역병이면 +1,500원
    final benefits = [
      b(
        'npay',
        {
          'categories': ['cafe'],
        },
        {'type': 'billing_discount', 'rate': 10},
        {
          'when': [
            {
              'payment': ['naver_pay'],
            },
          ],
        },
      ),
      b(
        'px',
        {
          'categories': ['convenience'],
        },
        {'type': 'billing_discount', 'rate': 15},
        {
          'when': [
            {'fact': 'soldier'},
          ],
        },
      ),
    ];
    final eng = engine([
      card(
        benefits,
        id: 'test-c',
        tiers: [0],
        rules: {
          'facts': [
            {
              'key': 'soldier',
              'type': 'bool',
              'scope': 'user',
              'ask': '현역병인가요',
            },
          ],
        },
      ),
    ]);
    final h = holder(id: 'c', cardId: 'test-c');
    final [cafeRows, cvsRows] = eng.recommend(
      [h],
      {},
      [
        const Query(merchant: 'ediya', amount: 10000),
        const Query(merchant: 'gs25', amount: 10000),
      ],
      now,
    );
    expect(cafeRows[0].value, 0);
    expect(
      [
        for (final c in cafeRows[0].conditional) [c.benefit, c.needs, c.extra],
      ],
      [
        [
          'npay',
          {'payment_method': 'naver_pay'},
          1000,
        ],
      ],
    );
    expect(
      [
        for (final c in cvsRows[0].conditional) [c.benefit, c.needs, c.extra],
      ],
      [
        [
          'px',
          {'fact': 'soldier'},
          1500,
        ],
      ],
    );
  });

  test('빈 결제수단은 적지 않은 것으로 본다', () {
    // Python의 or와 같다. 질문의 결제수단이 빈 글자면 마지막 결제수단을 쓴다. 네이버페이 10%라 1만원에 1,000원
    final eng = engine([
      card(
        [
          b(
            'npay',
            {
              'categories': ['cafe'],
            },
            {'type': 'billing_discount', 'rate': 10},
            {
              'when': [
                {
                  'payment': ['naver_pay'],
                },
              ],
            },
          ),
        ],
        id: 'test-n',
        tiers: [0],
      ),
    ]);
    final h = holder(id: 'n', cardId: 'test-n', lastPaymentMethod: 'naver_pay');
    final [rows] = eng.recommend(
      [h],
      {},
      [const Query(merchant: 'ediya', amount: 10000, paymentMethod: '')],
      now,
    );
    expect(rows[0].value, 1000);
  });

  test('test_removed_card_and_category_query', () {
    // 해지한 카드는 빼고, 업종만 준 질문은 업종별 1순위에 쓴다. S9, 시안 8쪽
    final (eng, cafe, flat) = twoCards();
    final gone = holder(id: cafe.id, cardId: cafe.cardId, removed: true);
    final [rows] = eng.recommend(
      [gone, flat],
      {},
      [const Query(category: 'cafe')],
      now,
    );
    expect([for (final r in rows) r.cardId], ['test-flat']);
  });

  test('test_recommend_does_not_use_later_payments', () {
    // 지금보다 뒤에 적힌 결제는 한도 사용량에 넣지 않는다
    final eng = engine([
      card(
        [
          b(
            'cafe-10',
            {
              'categories': ['cafe'],
            },
            {'type': 'billing_discount', 'rate': 10},
            {
              'limits': [
                {'per': 'month', 'amount': 1000},
              ],
            },
          ),
        ],
        id: 'test-l',
        tiers: [0],
      ),
    ]);
    final h = holder(id: 'l', cardId: 'test-l');
    final later = pay(
      10000,
      '2026-09-25T10:00',
      merchant: 'ediya',
      userCardId: 'l',
    );
    final kept = saved([later], eng.priceMonth(h, [later]));
    final [rows] = eng.recommend([h], {'l': kept}, [
      const Query(merchant: 'ediya', amount: 10000),
    ], now);
    expect(rows[0].value, 1000);
  });

  test('test_limit_status_period', () {
    final eng = engine([
      card(
        [
          b(
            'cafe-10',
            {
              'categories': ['cafe'],
            },
            {'type': 'billing_discount', 'rate': 10},
            {
              'limits': [
                {'per': 'month', 'amount': 5000},
                {'per': 'day', 'count': 1},
              ],
            },
          ),
        ],
        id: 'test-s',
        tiers: [0],
      ),
    ]);
    final h = holder(id: 's', cardId: 'test-s');
    final ps = [
      pay(30000, '2026-09-02T10:00', merchant: 'ediya', userCardId: 's'),
    ];
    final kept = saved(ps, eng.priceMonth(h, ps));
    var uses = {
      for (final u in eng.limitStatus(h, kept, at('2026-09-02T20:00')))
        u.per: u,
    };
    expect((uses['month']!.usedAmount, uses['month']!.capAmount), (3000, 5000));
    expect((uses['day']!.usedCount, uses['day']!.capCount), (1, 1));
    uses = {
      for (final u in eng.limitStatus(h, kept, at('2026-10-01T09:00')))
        u.per: u,
    };
    expect(uses['month']!.usedAmount, 0);
    expect(uses['day']!.usedCount, 0);
  });

  test('test_unsupported_option_warns_in_recommendation', () {
    // KB Easy all의 DIY 모드처럼 계산하지 않는 선택지를 골랐으면 추천에도 option_unsupported를 붙인다. 설계 5.1
    const opt = {
      'key': 'mode',
      'title': '모드',
      'choices': [
        {'key': 'auto', 'title': '자동'},
        {'key': 'diy', 'title': 'DIY'},
      ],
      'change': 'immediate',
      'unsupported': ['diy'],
    };
    final cafe = b(
      'cafe-10',
      {
        'categories': ['cafe'],
      },
      {'type': 'billing_discount', 'rate': 10},
      {
        'when': [
          {
            'option': {
              'mode': ['auto'],
            },
          },
        ],
        'limits': [
          {'per': 'txn', 'amount': 1000},
        ],
      },
    );
    final eng = engine([
      card(
        [cafe],
        tiers: [0],
        rules: {
          'options': [opt],
        },
      ),
    ]);
    final h = holder(
      id: 'k',
      options: [
        OptionPick(
          option: 'mode',
          choice: 'diy',
          effectiveFrom: day(2026, 9, 1),
        ),
      ],
    );
    final [rows] = eng.recommend(
      [h],
      {},
      [const Query(merchant: 'starbucks')],
      now,
    );
    expect([
      for (final w in rows[0].warnings) w.code,
    ], contains('option_unsupported'));
  });

  test('test_locked_ranked_benefit_when_top_is_zero_below_tier', () {
    // KB Easy all처럼 순위 상위 개수가 30만 구간부터면 0 구간에서는 순위 혜택을 못 받는 혜택으로 보여 준다.
    // 30만 구간이면 1위 영역 하나라 스타벅스 1만원 × 10% = 1,000. E37
    final ranked = [
      for (final (key, m) in [('coffee', 'starbucks'), ('delivery', 'baemin')])
        b(
          key,
          {
            'merchants': [m],
          },
          {'type': 'billing_discount', 'rate': 10},
          {
            'when': [
              {'ranked': 'top'},
            ],
            'tiers': {'from': 300000},
            'limits': [
              {'per': 'txn', 'amount': 1000},
            ],
          },
        ),
    ];
    final eng = engine([
      card(
        ranked,
        rules: {
          'ranked': [
            {
              'key': 'top',
              'top': {300000: 1},
            },
          ],
        },
      ),
    ]);
    final h = holder(id: 'k');
    final [rows] = eng.recommend(
      [h],
      {},
      [const Query(merchant: 'starbucks')],
      now,
    );
    expect(
      [
        for (final x in rows[0].locked)
          (x.benefit, x.requiredTier, x.valueIfUnlocked),
      ],
      [('coffee', 300000, 1000)],
    );
  });
}
