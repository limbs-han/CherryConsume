// 혜택 계산 규칙. Python `backend/tests/engine/test_benefits.py`를 옮겼다. 엔진 설계 3절. 기대값은 손계산이다
//
// test_engine_refuses_catalog_with_rule_errors는 옮기지 않는다. 앱은 규칙을 다시 검사하지 않고, Python의 JSON
// 만들기가 오류 카탈로그를 거절한다. `backend/tests/catalog/test_app_json.py`. 작업 006 설계 3절
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Json b(String key, Json target, Json reward, [Json kw = const {}]) => {
  'key': key,
  'target': target,
  'reward': reward,
  ...kw,
};

const cafe = {
  'categories': ['cafe'],
};
const rate10 = {'type': 'billing_discount', 'rate': 10};

List<PaymentResult> run(Engine eng, List<Payment> payments, [UserCard? h]) =>
    eng.priceMonth(h ?? holder(), payments);

int total(Map<String, int> v) => v.values.fold(0, (s, x) => s + x);

List<Json> areaBenefits() => [
  b(
    'coffee',
    {
      'merchants': ['ediya'],
    },
    {'type': 'billing_discount', 'rate': 30},
    {
      'when': [
        {'ranked': 'top'},
      ],
      'area': 'coffee',
      'stack': 'area',
    },
  ),
  b(
    'coffee-sb',
    {
      'merchants': ['starbucks'],
    },
    {'type': 'billing_discount', 'rate': 30},
    {
      'when': [
        {'ranked': 'top'},
      ],
      'area': 'coffee',
      'stack': 'area',
    },
  ),
  b(
    'delivery',
    {
      'merchants': ['baemin'],
    },
    {'type': 'billing_discount', 'rate': 30},
    {
      'when': [
        {'ranked': 'top'},
      ],
      'stack': 'area',
    },
  ),
];

Engine areaCard(String? way) => engine([
  card(
    areaBenefits(),
    tiers: [0],
    rules: {
      'ranked': [
        {'key': 'top', 'top': 1, 'cancellation': way},
      ],
      'stacks': [
        {'key': 'area'},
      ],
    },
  ),
]);

void main() {
  test('test_rate_with_per_payment_cap', () {
    // 스타벅스 12,500원 × 10% = 1,250 → 건당 최대 1,000원. 시안 7쪽
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'per': 'txn', 'amount': 1000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    expect(
      values(run(eng, [pay(12500, '2026-09-19T14:20', merchant: 'starbucks')])),
      [
        {'cafe-10': 1000},
      ],
    );
  });

  test('test_monthly_limit_just_before_and_after', () {
    // 월 5천원. 4만5천원 결제로 4,500을 쓰면 다음 1만원 결제는 1,000이 아니라 남은 500. 그다음은 0
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'per': 'month', 'amount': 5000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [
      pay(45000, '2026-09-01T10:00', merchant: 'ediya'),
      pay(10000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(10000, '2026-09-03T10:00', merchant: 'ediya'),
    ]);
    expect(values(r), [
      {'cafe-10': 4500},
      {'cafe-10': 500},
      <String, int>{},
    ]);
    expect(codes(r[1]), contains('limit_exhausted'));
    expect(codes(r[2]), contains('limit_exhausted'));
  });

  test('test_limit_resets_next_month', () {
    // 9월 한도 5천원을 다 써도 10월 1일에 초기화. 시안 14쪽
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'per': 'month', 'amount': 5000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [
      pay(50000, '2026-09-30T23:00', merchant: 'ediya'),
      pay(10000, '2026-10-01T00:10', merchant: 'ediya'),
    ]);
    expect(values(r), [
      {'cafe-10': 5000},
      {'cafe-10': 1000},
    ]);
  });

  test('test_shared_limit_between_benefits', () {
    // 카페 10%와 편의점 5%가 통합 1만원을 같이 쓴다. 카페 3,000 + 편의점 1,500 = 4,500 사용. 시안 6쪽
    final benefits = [
      b('cafe-10', cafe, rate10, {
        'limits': [
          {'per': 'month', 'amount': 5000},
          {'shared': 'integrated'},
        ],
      }),
      b(
        'cvs-5',
        {
          'categories': ['convenience'],
        },
        {'type': 'billing_discount', 'rate': 5},
        {
          'limits': [
            {'per': 'month', 'amount': 5000},
            {'shared': 'integrated'},
          ],
        },
      ),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'limits': [
            {'key': 'integrated', 'per': 'month', 'amount': 10000},
          ],
        },
      ),
    ]);
    final h = holder();
    final pays = [
      pay(30000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(30000, '2026-09-03T10:00', merchant: 'gs25'),
    ];
    final r = run(eng, pays, h);
    expect(values(r), [
      {'cafe-10': 3000},
      {'cvs-5': 1500},
    ]);
    final uses = {
      for (final u in eng.limitStatus(
        h,
        saved(pays, r),
        at('2026-09-20T12:00'),
      ))
        (u.key, u.per): u,
    };
    expect(uses[('integrated', 'month')]!.usedAmount, 4500);
    expect(uses[('integrated', 'month')]!.capAmount, 10000);
    expect(
      uses[('cafe-10', 'month')]!.capAmount! -
          uses[('cafe-10', 'month')]!.usedAmount,
      2000,
    );
  });

  test('test_count_limit_per_day', () {
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'per': 'day', 'count': 1},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [
      pay(5000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(5000, '2026-09-02T15:00', merchant: 'ediya'),
      pay(5000, '2026-09-03T10:00', merchant: 'ediya'),
    ]);
    expect(values(r), [
      {'cafe-10': 500},
      <String, int>{},
      {'cafe-10': 500},
    ]);
  });

  test('test_base_limit_per_payment_and_month', () {
    // 1회 5만원까지: 8만원 × 10%가 아니라 5만원 × 10% = 5,000
    var eng = engine([
      card(
        [
          b('mart', cafe, rate10, {
            'limits': [
              {'per': 'txn', 'base': 50000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    expect(
      values(run(eng, [pay(80000, '2026-09-02T10:00', merchant: 'ediya')])),
      [
        {'mart': 5000},
      ],
    );
    // 월 30만원까지: 28만원을 쓴 뒤 5만원 결제는 2만원만 넣어 2,000. 한도가 결제 도중 끝나는 경우
    eng = engine([
      card(
        [
          b('mart', cafe, rate10, {
            'limits': [
              {'per': 'month', 'base': 300000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [
      pay(280000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(50000, '2026-09-03T10:00', merchant: 'ediya'),
    ]);
    expect(values(r), [
      {'mart': 28000},
      {'mart': 2000},
    ]);
    expect(r[1].benefits[0].base, 20000);
  });

  test('test_limit_table_by_tier', () {
    // 통합 한도 {30만: 1만, 60만: 2만}. 60만 구간에서 25만원 × 10% = 25,000 → 20,000
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'shared': 'integrated'},
            ],
            'tiers': {'from': 300000},
          }),
        ],
        rules: {
          'limits': [
            {
              'key': 'integrated',
              'per': 'month',
              'amount': {300000: 10000, 600000: 20000},
            },
          ],
        },
      ),
    ]);
    expect(
      values(
        run(eng, [
          ...prevMonth(600000),
          pay(250000, '2026-09-02T10:00', merchant: 'ediya'),
        ]),
      )[1],
      {'cafe-10': 20000},
    );
  });

  test('test_adjust_by_fact_multiply_and_months', () {
    final base = [
      {
        'per': 'month',
        'amount': 1000,
        'count': 1,
        'adjust': [
          {
            'when': {'fact': 'soldier'},
            'count': null,
          },
        ],
      },
    ];
    var eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {'limits': base}),
        ],
        tiers: [0],
        rules: {
          'facts': [
            {
              'key': 'soldier',
              'type': 'bool',
              'scope': 'user',
              'ask': '현역 병사인가요',
            },
          ],
        },
      ),
    ]);
    final two = [
      pay(5000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(5000, '2026-09-03T10:00', merchant: 'ediya'),
    ];
    expect(values(run(eng, two)), [
      {'cafe-10': 500},
      <String, int>{},
    ]); // 월 1회
    expect(values(run(eng, two, holder(facts: {'soldier': true}))), [
      {'cafe-10': 500},
      {'cafe-10': 500},
    ]); // 횟수 제한 없음
    final doubled = [
      {
        'per': 'month',
        'amount': 1000,
        'adjust': [
          {
            'when': {'fact': 'birth_month_now'},
            'multiply': 2,
          },
          {
            'when': {
              'months': [5, 12],
            },
            'add': 500,
          },
        ],
      },
    ];
    eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {'limits': doubled}),
        ],
        tiers: [0],
        rules: {
          'facts': [
            {
              'key': 'birth_month',
              'type': 'month',
              'scope': 'user',
              'ask': '생일이 몇 월인가요',
            },
          ],
        },
      ),
    ]);
    final big = [pay(50000, '2026-09-02T10:00', merchant: 'ediya')];
    expect(values(run(eng, big, holder(facts: {'birth_month': 9}))), [
      {'cafe-10': 2000},
    ]); // 생일 달 두 배
    expect(
      values(run(eng, [pay(50000, '2026-12-02T10:00', merchant: 'ediya')])),
      [
        {'cafe-10': 1500},
      ],
    ); // 12월 +500
  });

  test('test_tiers_to_and_waived_from_only', () {
    // 나라사랑 편의점: 8만~20만 구간, 급여이체자는 하한 면제. 설계 2.2의 to는 그대로라 25만 구간은 받지 못한다
    final nara = b(
      'nara-cvs',
      {
        'categories': ['convenience'],
      },
      rate10,
      {
        'tiers': {
          'from': 80000,
          'to': 200000,
          'waived_when': {'fact': 'salary'},
        },
      },
    );
    final eng = engine([
      card(
        [nara],
        tiers: [0, 80000, 200000, 250000],
        rules: {
          'facts': [
            {'key': 'salary', 'type': 'bool', 'scope': 'card', 'ask': '급여이체'},
          ],
        },
      ),
    ]);
    Payment gs() => pay(5000, '2026-09-02T10:00', merchant: 'gs25');
    final salary = holder(facts: {'salary': true});
    expect(values(run(eng, [gs()], salary)), [
      {'nara-cvs': 500},
    ]); // 0 구간이지만 면제
    expect(
      values(run(eng, [...prevMonth(250000), gs()], salary))[1],
      <String, int>{},
    ); // 25만 구간은 급여이체자도 없음
    expect(values(run(eng, [...prevMonth(200000), gs()]))[1], {
      'nara-cvs': 500,
    });
    final r = run(eng, [gs()])[0];
    expect(r.benefits, isEmpty);
    expect(codes(r), contains('needs_input')); // 급여이체 여부를 모르면 묻는다
  });

  test('test_day_and_holidays', () {
    Json weekend(String h) => b('wk', cafe, rate10, {
      'when': [
        {
          'day': {
            'in': ['sat', 'sun'],
            'holidays': h,
          },
        },
      ],
    });
    final satHoliday = pay(
      10000,
      '2026-10-03T10:00',
      merchant: 'ediya',
    ); // 개천절, 토요일
    final monSubstitute = pay(
      10000,
      '2026-10-05T10:00',
      merchant: 'ediya',
    ); // 개천절 대체공휴일, 월요일
    for (final (mode, expected) in [
      ('ignore', [1000, 0]),
      ('include', [1000, 1000]),
      ('exclude', [0, 0]),
      ('only', [1000, 1000]),
    ]) {
      final eng = engine([
        card([weekend(mode)], tiers: [0]),
      ]);
      final got = [
        for (final v in values(run(eng, [satHoliday, monSubstitute]))) total(v),
      ];
      expect(got, expected, reason: mode);
    }
  });

  test('공휴일 목록 밖의 해는 결제에 혜택 없이 holiday 모름을 남긴다', () {
    // 작업 006 설계 2절. 2037년 1월 3일 토요일, 공휴일을 뺀 주말 10%. 공휴일인지 몰라 0원과 needs_input이다
    final eng = engine([
      card(
        [
          b('wk', cafe, rate10, {
            'when': [
              {
                'day': {
                  'in': ['sat', 'sun'],
                  'holidays': 'exclude',
                },
              },
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [pay(10000, '2037-01-03T10:00', merchant: 'ediya')])[0];
    expect(r.benefits, isEmpty);
    expect(r.warnings.firstWhere((w) => w.code == 'needs_input').data, {
      'needs': [
        ['holiday'],
      ],
      'benefits': ['wk'],
    });
  });

  test('test_time_range_across_midnight', () {
    final eng = engine([
      card(
        [
          b('night', cafe, rate10, {
            'when': [
              {
                'time': {'from': '21:00', 'to': '09:00'},
              },
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final times = [
      '2026-09-02T23:30',
      '2026-09-03T08:59',
      '2026-09-03T09:00',
      '2026-09-03T20:59',
      '2026-09-03T21:00',
    ];
    final got = [
      for (final v in values(
        run(eng, [for (final t in times) pay(10000, t, merchant: 'ediya')]),
      ))
        v.isNotEmpty,
    ];
    expect(got, [true, true, false, false, true]);
  });

  test('test_unknown_payment_method', () {
    // 결제수단을 모르면 저장한 결제는 혜택 0에 needs_input. 설계 3.1
    final eng = engine([
      card(
        [
          b('npay', cafe, rate10, {
            'when': [
              {
                'payment': ['naver_pay'],
              },
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    var r = run(eng, [pay(10000, '2026-09-02T10:00', merchant: 'ediya')])[0];
    expect(r.benefits, isEmpty);
    expect(r.warnings[0].data['needs'], [
      ['payment_method'],
    ]);
    r = run(eng, [
      pay(
        10000,
        '2026-09-02T10:00',
        merchant: 'ediya',
        paymentMethod: 'naver_pay',
      ),
    ])[0];
    expect(values([r]), [
      {'npay': 1000},
    ]);
  });

  test('test_parent_category_target_is_unknown', () {
    final eng = engine([
      card(
        [
          b('burger', {
            'categories': ['restaurant.fastfood'],
          }, rate10),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [
      pay(10000, '2026-09-02T12:00', category: 'restaurant'),
    ])[0];
    expect(r.benefits, isEmpty);
    expect(r.warnings[0].data['needs'], [
      ['category', 'restaurant'],
    ]);
    expect(
      values(
        run(eng, [
          pay(10000, '2026-09-02T12:00', category: 'restaurant.fastfood'),
        ]),
      ),
      [
        {'burger': 1000},
      ],
    );
  });

  test('test_common_exclusion_and_explicit_target', () {
    // 공통 제외 업종이어도 혜택이 대상으로 직접 적었으면 받는다. 무이자할부는 늘 뺀다. 설계 3.2의 3
    final benefits = [
      b('all-1', {'all': true}, {'type': 'billing_discount', 'rate': 1}),
      b(
        'tax-3',
        {
          'categories': ['tax'],
        },
        {'type': 'billing_discount', 'rate': 3},
        {'stack': 'tax'},
      ),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'stacks': [
            {'key': 'tax'},
          ],
          'benefit_exclusions': {
            'categories': ['tax'],
            'when_any': [
              {'interest_free': true},
            ],
          },
        },
      ),
    ]);
    final r = run(eng, [
      pay(100000, '2026-09-02T12:00', category: 'tax'),
      pay(100000, '2026-09-03T12:00', category: 'other', interestFree: true),
    ]);
    expect(values(r), [
      {'tax-3': 3000},
      <String, int>{},
    ]);
  });

  test('test_stack_best_and_other_stack_adds', () {
    // 같은 묶음은 큰 쪽 하나, 다른 묶음은 더한다. 카페 10% 1,000 vs 전가맹점 1% 100 → 1,000. 간편결제 묶음 2% 200 더함
    final benefits = [
      b('all-1', {'all': true}, {'type': 'billing_discount', 'rate': 1}),
      b('cafe-10', cafe, rate10),
      b('pay-2', {'all': true}, {'type': 'billing_discount', 'rate': 2}, {
        'when': [
          {
            'payment': ['naver_pay'],
          },
        ],
        'stack': 'pay',
      }),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'stacks': [
            {'key': 'pay'},
          ],
        },
      ),
    ]);
    expect(
      values(
        run(eng, [
          pay(
            10000,
            '2026-09-02T10:00',
            merchant: 'ediya',
            paymentMethod: 'naver_pay',
          ),
        ]),
      ),
      [
        {'cafe-10': 1000, 'pay-2': 200},
      ],
    );
  });

  test('test_priority_split', () {
    // 현대카드M처럼 5% 영역 한도를 넘은 금액은 1.5%. 10만원: 5% 월 한도 2,000P → 4만원분, 나머지 6만원 × 1.5% = 900
    final benefits = [
      b(
        'base-1-5',
        {'all': true},
        {'type': 'points', 'program': 'test_point', 'rate': 1.5},
      ),
      b(
        'area-5',
        cafe,
        {'type': 'points', 'program': 'test_point', 'rate': 5},
        {
          'limits': [
            {'per': 'month', 'amount': 2000},
          ],
        },
      ),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'stacks': [
            {
              'key': 'main',
              'pick': 'priority',
              'order': ['area-5', 'base-1-5'],
              'spill': 'split',
            },
          ],
        },
      ),
    ]);
    final r = run(eng, [pay(100000, '2026-09-02T10:00', merchant: 'ediya')])[0];
    expect(values([r]), [
      {'area-5': 2000, 'base-1-5': 900},
    ]);
    expect([for (final x in r.benefits) x.base], [40000, 60000]);
  });

  test('test_priority_without_split_moves_on_when_exhausted', () {
    // 삼성 iD ON처럼 3% 한도를 다 쓴 다음 결제부터 1%. 같은 결제 안에서는 나누지 않는다
    final benefits = [
      b('over-3', {'all': true}, {'type': 'billing_discount', 'rate': 3}, {
        'limits': [
          {'per': 'month', 'amount': 1000},
        ],
      }),
      b('over-1', {'all': true}, {'type': 'billing_discount', 'rate': 1}),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'stacks': [
            {
              'key': 'main',
              'pick': 'priority',
              'order': ['over-3', 'over-1'],
            },
          ],
        },
      ),
    ]);
    final r = run(eng, [
      pay(50000, '2026-09-02T10:00', category: 'other'),
      pay(10000, '2026-09-03T10:00', category: 'other'),
    ]);
    expect(values(r), [
      {'over-3': 1000},
      {'over-1': 100},
    ]);
  });

  test('test_month_total_fixed', () {
    // 카카오뱅크처럼 후불교통 한 달 합 5만원 이상이면 4천원. 3만 → 0, 2만5천 → 합 5만5천이라 4,000, 1만 → 0
    final t = b(
      'transit-4000',
      {
        'categories': ['transit.subway'],
      },
      {'type': 'cashback', 'fixed': 4000, 'basis': 'month_total'},
      {
        'when': [
          {
            'month_total': {'min': 50000},
          },
        ],
        'limits': [
          {'per': 'month', 'count': 1},
        ],
      },
    );
    final eng = engine([
      card([t], tiers: [0]),
    ]);
    final r = run(eng, [
      pay(30000, '2026-09-10T08:00', category: 'transit.subway'),
      pay(25000, '2026-09-20T08:00', category: 'transit.subway'),
      pay(10000, '2026-09-25T08:00', category: 'transit.subway'),
    ]);
    expect(values(r), [
      <String, int>{},
      {'transit-4000': 4000},
      <String, int>{},
    ]);
  });

  test('test_month_total_rate', () {
    // LOCA 365처럼 한 달 합 2만원 이상이면 합의 10%, 월 5천원. 1만5천 → 0, 1만 → 합 2만5천의 10% 2,500, 3만 → 합 5만5천의 10% 5,500 중 한도 남은 2,500
    final t = b(
      'transit-10',
      {
        'categories': ['transit.subway'],
      },
      {'type': 'billing_discount', 'rate': 10, 'basis': 'month_total'},
      {
        'when': [
          {
            'month_total': {'min': 20000},
          },
        ],
        'limits': [
          {'per': 'month', 'amount': 5000},
        ],
      },
    );
    final eng = engine([
      card([t], tiers: [0]),
    ]);
    final r = run(eng, [
      pay(15000, '2026-09-10T08:00', category: 'transit.subway'),
      pay(10000, '2026-09-20T08:00', category: 'transit.subway'),
      pay(30000, '2026-09-25T08:00', category: 'transit.subway'),
    ]);
    expect(values(r), [
      <String, int>{},
      {'transit-10': 2500},
      {'transit-10': 2500},
    ]);
  });

  test('test_ranked_area_and_final', () {
    // 삼성 iD ON처럼 커피와 배달 중 이번 달 1위만 30%. 스타벅스와 이디야는 area coffee로 한 영역
    final eng = engine([
      card(
        areaBenefits(),
        tiers: [0],
        rules: {
          'ranked': [
            {'key': 'top', 'top': 1},
          ],
          'stacks': [
            {'key': 'area'},
          ],
        },
      ),
    ]);
    final h = holder();
    final pays = [
      pay(10000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(20000, '2026-09-03T19:00', merchant: 'baemin'),
      pay(15000, '2026-09-04T10:00', merchant: 'starbucks'),
    ];
    final r = run(eng, pays, h);
    // 1: 커피 1만 1위 → 3,000. 2: 배달 2만이 커피 1만을 넘어 1위 → 6,000. 3: 커피 2만5천 → 1위 → 4,500
    expect(values(r), [
      {'coffee': 3000},
      {'delivery': 6000},
      {'coffee-sb': 4500},
    ]);
    expect(codes(r[0]), contains('ranked_provisional'));
    // 달이 끝나면 최종 순위로 다시 계산. 커피 2만5천이 배달 2만보다 커서 배달은 0. 설계 3.5
    final finalR = eng.priceMonth(
      h,
      saved(pays, r),
      month: day(2026, 9, 1),
      isFinal: true,
    );
    expect(values(finalR), [
      {'coffee': 3000},
      <String, int>{},
      {'coffee-sb': 4500},
    ]);
    expect(codes(finalR[0]), isNot(contains('ranked_provisional')));
  });

  for (final (way, expected) in <(String?, List<Map<String, int>>)>[
    // 취소한 달: 8월 커피는 이디야 1만 원 전부와 스타벅스 5천 원으로 1만 5천 원이라 배달 1만 2천 원을 넘는다. 이디야는 남은
    // 5천 원의 30%로 1,500원, 스타벅스 1,500원. 9월 커피는 취소 -5천 원에 이디야 6천 원으로 1천 원이라 배달 4천 원이
    // 1위다. 배민 1,200원, 이디야 0원
    (
      'cancel_month',
      [
        {'coffee': 1500},
        {},
        {'coffee-sb': 1500},
        {'delivery': 1200},
        {},
      ],
    ),
    // 결제한 달: 8월 커피는 남은 5천 원과 5천 원으로 1만 원이라 배달이 1위다. 배민 1만 2천 원의 30%로 3,600원.
    // 9월은 배민 4천 원 1,200원, 이디야 6천 원이 커피 6천 원으로 1위라 1,800원
    (
      'original_month',
      [
        {},
        {'delivery': 3600},
        {},
        {'delivery': 1200},
        {'coffee': 1800},
      ],
    ),
    // 칸이 없으면 지금처럼 결제한 달에서 뺀다. 확인 필요
    (
      null,
      [
        {},
        {'delivery': 3600},
        {},
        {'delivery': 1200},
        {'coffee': 1800},
      ],
    ),
  ]) {
    test('test_ranked_area_cancellation_month $way', () {
      // E55. 삼성 iD ON은 "결제 취소건의 경우, 매출취소전표 접수월의 3개 영역 합산 이용금액 및 영역별 이용금액에 반영"이다.
      // 순위 영역 이용액에서 취소를 빼는 달은 카드 칸 ranked[].cancellation을 따른다. 8월 2일 이디야 1만 원 가운데 5천 원을
      // 9월 3일 취소했다
      final eng = engine([
        card(
          areaBenefits(),
          tiers: [0],
          rules: {
            'ranked': [
              {'key': 'top', 'top': 1, 'cancellation': ?way},
            ],
            'stacks': [
              {'key': 'area'},
            ],
          },
        ),
      ]);
      final pays = [
        pay(
          10000,
          '2026-08-02T10:00',
          merchant: 'ediya',
          cancelledAmount: 5000,
          cancelledAt: at('2026-09-03T10:00'),
        ),
        pay(12000, '2026-08-03T19:00', merchant: 'baemin'),
        pay(5000, '2026-08-04T10:00', merchant: 'starbucks'),
        pay(4000, '2026-09-05T10:00', merchant: 'baemin'),
        pay(6000, '2026-09-06T10:00', merchant: 'ediya'),
      ];
      expect(
        values(
          eng.priceMonth(holder(), pays, month: day(2026, 8, 1), isFinal: true),
        ),
        expected,
      );
    });
  }

  test('test_ranked_area_cancellation_month_end_of_cancel_month', () {
    // E55. 같은 결제로 9월 달 끝을 계산한다. 9월 커피는 취소 -5천 원과 이디야 6천 원으로 1천 원이라 배달 4천 원이 1위다.
    // 배민 1,200원, 이디야 0원. 달 끝 합계에 8월 결제의 9월 취소가 들어가야 나오는 값이다
    final eng = areaCard('cancel_month');
    final pays = [
      pay(
        10000,
        '2026-08-02T10:00',
        merchant: 'ediya',
        cancelledAmount: 5000,
        cancelledAt: at('2026-09-03T10:00'),
      ),
      pay(4000, '2026-09-05T10:00', merchant: 'baemin'),
      pay(6000, '2026-09-06T10:00', merchant: 'ediya'),
    ];
    final r = eng.priceMonth(
      holder(),
      pays,
      month: day(2026, 9, 1),
      isFinal: true,
    );
    expect(values(r), [
      {'coffee': 1500},
      {'delivery': 1200},
      <String, int>{},
    ]);
  });

  test('test_ranked_area_full_cancel_and_korean_month', () {
    // E55. 이디야 1만 원을 다음 달에 전액 취소해도 8월 커피에는 1만 원이 남아 스타벅스 5천 원과 1만 5천 원이다. 배달 1만
    // 2천 원보다 커 스타벅스 1,500원, 배민 0원. 취소 시각 8월 31일 15시 30분 UTC는 한국 시간 9월 1일 0시 30분이라 9월
    // 취소다
    final eng = areaCard('cancel_month');
    final pays = [
      pay(
        10000,
        '2026-08-02T10:00',
        merchant: 'ediya',
        cancelledAmount: 10000,
        cancelledAt: DateTime.utc(2026, 8, 31, 15, 30),
      ),
      pay(12000, '2026-08-03T19:00', merchant: 'baemin'),
      pay(5000, '2026-08-04T10:00', merchant: 'starbucks'),
    ];
    final r = eng.priceMonth(
      holder(),
      pays,
      month: day(2026, 8, 1),
      isFinal: true,
    );
    expect(values(r), [
      <String, int>{},
      <String, int>{},
      {'coffee-sb': 1500},
    ]);
  });

  test('test_onsite_discount_back_calculation', () {
    // 현장할인 10%: 기록 9,000원 → 할인 전 10,000원, 할인 1,000원. 1만원 이상 조건은 할인 전 금액으로 본다. 실적은 9,000
    final t = b(
      'px',
      {
        'categories': ['convenience'],
      },
      {'type': 'onsite_discount', 'rate': 10},
      {
        'when': [
          {
            'amount': {'min': 10000},
          },
        ],
      },
    );
    final eng = engine([
      card([t], tiers: [0]),
    ]);
    final r = run(eng, [pay(9000, '2026-09-02T10:00', merchant: 'gs25')])[0];
    expect(values([r]), [
      {'px': 1000},
    ]);
    expect(r.benefits[0].base, 10000);
    expect(r.spend[0].amount, 9000);
  });

  test('test_per_unit_per_liter_points_and_rounding', () {
    final perUnit = b(
      'unit',
      {
        'categories': ['other'],
      },
      {
        'type': 'points',
        'program': 'test_point',
        'per_unit': {'unit': 20000, 'amount': 1000},
      },
    );
    expect(
      values(
        run(
          engine([
            card([perUnit], tiers: [0]),
          ]),
          [pay(45000, '2026-09-02T10:00', category: 'other')],
        ),
      ),
      [
        {'unit': 2000},
      ],
    ); // 2만원당 1천P, 남는 5천원은 버림
    final fuel = b(
      'fuel',
      {
        'categories': ['fuel'],
      },
      {'type': 'billing_discount', 'per_liter': 60},
    );
    expect(
      values(
        run(
          engine([
            card([fuel], tiers: [0]),
          ]),
          [pay(85000, '2026-09-02T10:00', merchant: 'sk_energy')],
        ),
      ),
      [
        {'fuel': 3000},
      ],
    ); // 85,000 ÷ 1,700 = 50L × 60
    final halfUp = b(
      'm',
      {'all': true},
      {
        'type': 'points',
        'program': 'test_point',
        'rate': 1.5,
        'round': 'round',
      },
    );
    expect(
      values(
        run(
          engine([
            card([halfUp], tiers: [0]),
          ]),
          [pay(4639, '2026-09-02T10:00', category: 'other')],
        ),
      ),
      [
        {'m': 70},
      ],
    ); // 69.585 반올림. 현대카드M 원문 예시
    final floor = b(
      'm',
      {'all': true},
      {'type': 'points', 'program': 'test_point', 'rate': 1.5},
    );
    expect(
      values(
        run(
          engine([
            card([floor], tiers: [0]),
          ]),
          [pay(4639, '2026-09-02T10:00', category: 'other')],
        ),
      ),
      [
        {'m': 69},
      ],
    );
  });

  test('test_options_default_change_and_missing', () {
    const opt = {
      'key': 'pkg',
      'title': '패키지',
      'choices': [
        {'key': 'p1', 'title': '1'},
        {'key': 'p2', 'title': '2'},
      ],
      'change': 'next_month',
    };
    final benefits = [
      b('p1-cafe', cafe, rate10, {
        'when': [
          {
            'option': {
              'pkg': ['p1'],
            },
          },
        ],
      }),
      b(
        'p2-cafe',
        cafe,
        {'type': 'billing_discount', 'rate': 20},
        {
          'when': [
            {
              'option': {
                'pkg': ['p2'],
              },
            },
          ],
        },
      ),
    ];
    var eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'options': [opt],
        },
      ),
    ]);
    final septPays = [pay(10000, '2026-09-20T10:00', merchant: 'ediya')];
    final r = run(eng, septPays)[0];
    expect(r.benefits, isEmpty);
    expect(r.warnings[0].data['needs'], [
      ['option', 'pkg'],
    ]);
    final picks = [
      OptionPick(option: 'pkg', choice: 'p1', effectiveFrom: day(2026, 9, 1)),
      OptionPick(option: 'pkg', choice: 'p2', effectiveFrom: day(2026, 10, 1)),
    ];
    final h = holder(options: picks);
    expect(
      values(
        run(eng, [
          ...septPays,
          pay(10000, '2026-10-02T10:00', merchant: 'ediya'),
        ], h),
      ),
      [
        {'p1-cafe': 1000},
        {'p2-cafe': 2000},
      ],
    );
    eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'options': [
            {...opt, 'default': 'p2'},
          ],
        },
      ),
    ]);
    expect(values(run(eng, septPays)), [
      {'p2-cafe': 2000},
    ]); // 고르지 않으면 카드사 기본값
  });

  test('test_card_month_and_promo_period', () {
    // 생활혜택은 카드 등록 달에는 없다. 행사 혜택은 기간 안에만
    final benefits = [
      b('life', cafe, rate10, {
        'when': [
          {
            'card_month': {'min': 1},
          },
        ],
      }),
      b(
        'promo',
        {
          'merchants': ['gs25'],
        },
        {'type': 'cashback', 'fixed': 1000},
        {'valid_from': '2026-09-10', 'valid_until': '2026-09-30'},
      ),
    ];
    final eng = engine([
      card(benefits, tiers: [0]),
    ]);
    final h = holder(startedOn: day(2026, 9, 5));
    var r = run(eng, [
      pay(10000, '2026-09-20T10:00', merchant: 'ediya'),
      pay(10000, '2026-10-02T10:00', merchant: 'ediya'),
    ], h);
    expect(values(r), [
      <String, int>{},
      {'life': 1000},
    ]);
    final one = run(eng, [
      pay(10000, '2026-09-20T10:00', merchant: 'ediya'),
    ])[0];
    expect(one.benefits, isEmpty);
    expect(one.warnings[0].data['needs'], [
      ['started_on'],
    ]);
    r = run(eng, [
      pay(5000, '2026-09-09T10:00', merchant: 'gs25'),
      pay(5000, '2026-09-10T10:00', merchant: 'gs25'),
      pay(5000, '2026-10-01T10:00', merchant: 'gs25'),
    ]);
    expect(values(r), [
      <String, int>{},
      {'promo': 1000},
      <String, int>{},
    ]);
  });

  test('test_revision_estimated_and_missing', () {
    var eng = engine([
      card(
        [b('cafe-10', cafe, rate10)],
        tiers: [0],
        start: '2026-09-01',
        estimated: true,
      ),
    ]);
    var r = run(eng, [pay(10000, '2026-08-20T10:00', merchant: 'ediya')])[0];
    expect(values([r]), [
      {'cafe-10': 1000},
    ]);
    expect(codes(r), contains('revision_estimated'));
    eng = engine([
      card([b('cafe-10', cafe, rate10)], tiers: [0], start: '2026-09-01'),
    ]);
    r = run(eng, [pay(10000, '2026-08-20T10:00', merchant: 'ediya')])[0];
    expect(r.benefits, isEmpty);
    expect(codes(r), ['no_revision']);
  });

  test('test_unmodeled_is_computed_with_warning', () {
    // E12. 문장으로 남긴 조건은 없는 것처럼 계산하고 문장을 경고에 담는다
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'unmodeled': ['백화점 안 매장은 제외'],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final r = run(eng, [pay(10000, '2026-09-02T10:00', merchant: 'ediya')])[0];
    expect(values([r]), [
      {'cafe-10': 1000},
    ]);
    expect(
      [
        for (final w in r.warnings)
          if (w.code == 'check_conditions') w.data,
      ],
      [
        {
          'sentences': ['백화점 안 매장은 제외'],
        },
      ],
    );
  });

  test('test_full_cancellation_gives_nothing', () {
    // E5. 전액 취소된 결제는 혜택 0이고 한도도 쓰지 않는다
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'per': 'month', 'amount': 1000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final gone = pay(
      10000,
      '2026-09-02T10:00',
      merchant: 'ediya',
      cancelledAmount: 10000,
      cancelledAt: at('2026-09-03T10:00'),
    );
    expect(
      values(
        run(eng, [gone, pay(10000, '2026-09-04T10:00', merchant: 'ediya')]),
      ),
      [
        <String, int>{},
        {'cafe-10': 1000},
      ],
    );
  });

  test('test_same_input_same_output_and_integers', () {
    final eng = engine([
      card(
        [
          b(
            'm',
            {'all': true},
            {'type': 'points', 'program': 'test_point', 'rate': 1.3},
          ),
        ],
        tiers: [0],
      ),
    ]);
    final pays = [
      pay(12345, '2026-09-02T10:00', category: 'other'),
      pay(67891, '2026-09-03T10:00', category: 'other'),
    ];
    final first = run(eng, pays), second = run(eng, pays);
    expect(
      [
        for (final r in first)
          [r.benefits, r.spend, for (final w in r.warnings) w.toJson()],
      ],
      [
        for (final r in second)
          [r.benefits, r.spend, for (final w in r.warnings) w.toJson()],
      ],
    );
    expect(values(first), [
      {'m': 160},
      {'m': 882},
    ]); // 12,345 × 1.3% = 160.485, 67,891 × 1.3% = 882.583 → 버림
  });

  test('test_new_card_tier_decides_ranked_top', () {
    // KB Easy all처럼 상위 몇 개가 구간표인데 새 카드면 특례 구간으로 센다. 표 대조에서 찾았다
    final benefits = [
      b(
        'coffee',
        {
          'merchants': ['ediya'],
        },
        rate10,
        {
          'when': [
            {'ranked': 'top'},
          ],
          'tiers': {'from': 300000},
        },
      ),
      b(
        'delivery',
        {
          'merchants': ['baemin'],
        },
        rate10,
        {
          'when': [
            {'ranked': 'top'},
          ],
          'tiers': {'from': 300000},
        },
      ),
    ];
    final eng = engine([
      card(
        benefits,
        rules: {
          'ranked': [
            {
              'key': 'top',
              'top': {300000: 1},
            },
          ],
          'new_card': {
            'from': 'registration',
            'until': 'next_month_end',
            'tier': 300000,
          },
        },
      ),
    ]);
    final r = run(eng, [
      pay(10000, '2026-09-10T10:00', merchant: 'ediya'),
    ], holder(startedOn: day(2026, 9, 5)));
    expect(values(r), [
      {'coffee': 1000},
    ]);
  });

  test('test_waived_unknown_reports_tier_and_input', () {
    // 나라사랑처럼 급여이체자면 하한 면제인데 급여이체 여부를 모르면 구간 미달과 묻기를 함께 붙인다. 표 대조에서 찾았다
    final nara = b(
      'nara-cvs',
      {
        'categories': ['convenience'],
      },
      rate10,
      {
        'tiers': {
          'from': 80000,
          'waived_when': {'fact': 'salary'},
        },
      },
    );
    final eng = engine([
      card(
        [nara],
        tiers: [0, 80000],
        rules: {
          'facts': [
            {'key': 'salary', 'type': 'bool', 'scope': 'card', 'ask': '급여이체'},
          ],
        },
      ),
    ]);
    final r = run(eng, [
      ...prevMonth(79999),
      pay(8000, '2026-09-01T12:00', merchant: 'gs25'),
    ])[1];
    expect(r.benefits, isEmpty);
    expect(codes(r), containsAll(['tier_not_met', 'needs_input']));
  });

  test('test_unknown_adjust_asks', () {
    // My WE:SH처럼 한도 조건이 모름이면 한도를 늘리지 않고 묻는다. 표 대조에서 찾았다
    final doubled = [
      {
        'per': 'month',
        'amount': 1000,
        'adjust': [
          {
            'when': {'fact': 'birth_month_now'},
            'multiply': 2,
          },
        ],
      },
    ];
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {'limits': doubled}),
        ],
        tiers: [0],
        rules: {
          'facts': [
            {
              'key': 'birth_month',
              'type': 'month',
              'scope': 'user',
              'ask': '생일',
            },
          ],
        },
      ),
    ]);
    final r = run(eng, [pay(50000, '2026-09-02T10:00', merchant: 'ediya')])[0];
    expect(values([r]), [
      {'cafe-10': 1000},
    ]);
    expect(
      r.warnings.firstWhere((w) => w.code == 'needs_input').data['needs'],
      contains(equals(['fact', 'birth_month'])),
    );
  });

  test('test_onsite_discount_with_cap', () {
    // 현장할인 20%에 건당 4만원 한도. 기록 170,000원이면 할인 4만원, 할인 전 210,000원. 식대로 212,500원으로 부풀리지 않는다
    final t = b(
      'outback',
      {
        'categories': ['restaurant'],
      },
      {'type': 'onsite_discount', 'rate': 20},
      {
        'limits': [
          {'per': 'txn', 'amount': 40000},
        ],
      },
    );
    final r = run(
      engine([
        card([t], tiers: [0]),
      ]),
      [pay(170000, '2026-09-02T19:00', category: 'restaurant')],
    )[0];
    expect(values([r]), [
      {'outback': 40000},
    ]);
    expect(r.benefits[0].base, 210000);
  });

  test('test_limit_exhausted_only_for_period_limits', () {
    // 건당 최대 1,000원으로 줄어든 것은 한도를 다 쓴 것이 아니다. 달 한도로 줄면 붙인다
    final perTxn = b('cafe-10', cafe, rate10, {
      'limits': [
        {'per': 'txn', 'amount': 1000},
      ],
    });
    var r = run(
      engine([
        card([perTxn], tiers: [0]),
      ]),
      [pay(12500, '2026-09-02T10:00', merchant: 'ediya')],
    )[0];
    expect(codes(r), isNot(contains('limit_exhausted')));
    final monthly = b('cafe-10', cafe, rate10, {
      'limits': [
        {'per': 'month', 'amount': 1000},
      ],
    });
    r = run(
      engine([
        card([monthly], tiers: [0]),
      ]),
      [pay(12500, '2026-09-02T10:00', merchant: 'ediya')],
    )[0];
    expect(codes(r), contains('limit_exhausted'));
  });

  test('test_common_exclusion_skipped_only_for_listed_category', () {
    // 가맹점만 적은 혜택은 결제 업종으로 공통 제외를 본다. 이마트에서 산 상품권 5만원은 0원, 장보기 5만원은 2,500원.
    // 업종을 직접 적은 혜택은 공통 제외보다 우선한다. 2026-09-29 사용자가 정했다. 설계 3.2의 3
    final benefits = [
      b(
        'gs-5',
        {
          'merchants': ['gs25'],
        },
        {'type': 'billing_discount', 'rate': 5},
      ),
      b(
        'tax-3',
        {
          'categories': ['tax'],
        },
        {'type': 'billing_discount', 'rate': 3},
        {'stack': 'tax'},
      ),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'stacks': [
            {'key': 'tax'},
          ],
          'benefit_exclusions': {
            'categories': ['tax', 'other'],
          },
        },
      ),
    ]);
    final r = run(eng, [
      pay(50000, '2026-09-02T10:00', merchant: 'gs25', category: 'other'),
      pay(50000, '2026-09-03T10:00', merchant: 'gs25'),
      pay(100000, '2026-09-04T10:00', category: 'tax'),
    ]);
    expect(values(r), [
      <String, int>{},
      {'gs-5': 2500},
      {'tax-3': 3000},
    ]);
  });

  test('test_onsite_amount_condition_uses_capped_discount', () {
    // 현장할인 20%, 건당 4만원, 할인 전 211,000원 미만. 기록 170,000원의 할인 전 금액은 170,000 + 40,000 = 210,000이라 대상.
    // 비율로만 되짚은 212,500원으로 판정하지 않는다. 설계 3.6
    final t = b(
      'outback',
      {
        'categories': ['restaurant'],
      },
      {'type': 'onsite_discount', 'rate': 20},
      {
        'when': [
          {
            'amount': {'below': 211000},
          },
        ],
        'limits': [
          {'per': 'txn', 'amount': 40000},
        ],
      },
    );
    final r = run(
      engine([
        card([t], tiers: [0]),
      ]),
      [pay(170000, '2026-09-02T19:00', category: 'restaurant')],
    )[0];
    expect(values([r]), [
      {'outback': 40000},
    ]);
  });

  test('test_final_leaves_other_months_to_their_own_ranking', () {
    // 9월 final 계산에 저장값 없는 10월 결제가 섞여도 10월 결제는 10월 순위로 본다. 10월 배달 2만원이 1위라 6,000. 설계 3.5
    final benefits = [
      b(
        'coffee',
        {
          'merchants': ['ediya'],
        },
        {'type': 'billing_discount', 'rate': 30},
        {
          'when': [
            {'ranked': 'top'},
          ],
        },
      ),
      b(
        'delivery',
        {
          'merchants': ['baemin'],
        },
        {'type': 'billing_discount', 'rate': 30},
        {
          'when': [
            {'ranked': 'top'},
          ],
        },
      ),
    ];
    final eng = engine([
      card(
        benefits,
        tiers: [0],
        rules: {
          'ranked': [
            {'key': 'top', 'top': 1},
          ],
        },
      ),
    ]);
    final pays = [
      pay(10000, '2026-09-02T10:00', merchant: 'ediya'),
      pay(20000, '2026-10-02T19:00', merchant: 'baemin'),
    ];
    expect(
      values(
        eng.priceMonth(holder(), pays, month: day(2026, 9, 1), isFinal: true),
      ),
      [
        {'coffee': 3000},
        {'delivery': 6000},
      ],
    );
  });

  test('test_unknown_card_is_skipped_with_warning', () {
    // 카탈로그에 없는 카드의 결제는 계산하지 않고 경고를 남긴다. 예외를 던지지 않는다. 설계 6.8
    final eng = engine([
      card([b('cafe-10', cafe, rate10)], tiers: [0]),
    ]);
    final h = holder(cardId: 'test-gone');
    final r = run(eng, [
      pay(10000, '2026-09-02T10:00', merchant: 'ediya'),
    ], h)[0];
    expect(r.benefits, isEmpty);
    expect(codes(r), ['no_revision']);
    expect(eng.spendStatus(h, [], day(2026, 9, 1)).tier, isNull);
    expect(eng.limitStatus(h, [], at('2026-09-19T14:20')), isEmpty);
    final [rows] = eng.recommend(
      [h],
      {},
      [const Query(merchant: 'ediya', amount: 10000)],
      at('2026-09-19T14:20'),
    );
    expect(rows[0].value, 0);
  });

  test('test_narrow_common_exclusion_beats_parent_target', () {
    // 대상 음식점, 공통 제외 패스트푸드. 패스트푸드 1만원은 좁은 제외가 이겨 0원, 일반음식점은 1,000원.
    // 대상이 제외 업종이나 더 좁은 업종을 적었을 때만 공통 제외를 무시한다. 2026-09-29 사용자가 정했다. 설계 3.2의 3
    final eng = engine([
      card(
        [
          b('food-10', {
            'categories': ['restaurant'],
          }, rate10),
        ],
        tiers: [0],
        rules: {
          'benefit_exclusions': {
            'categories': ['restaurant.fastfood'],
          },
        },
      ),
    ]);
    final r = run(eng, [
      pay(10000, '2026-09-02T12:00', category: 'restaurant.fastfood'),
      pay(10000, '2026-09-03T12:00', category: 'restaurant.general'),
    ]);
    expect(values(r), [
      <String, int>{},
      {'food-10': 1000},
    ]);
  });

  test('test_onsite_back_calculation_follows_rounding', () {
    // 10% 현장할인, 원 미만 버림. 기록 9,001원은 할인 전 10,001원에서 1,000원을 뺀 값이다.
    // 올림으로 되짚은 10,002원은 할인 1,000원이라 기록이 9,002원이 되어 맞지 않는다. 2026-09-29 사용자가 정했다. 설계 3.6
    final t = b(
      'gs',
      {
        'merchants': ['gs25'],
      },
      {'type': 'onsite_discount', 'rate': 10},
    );
    final r = run(
      engine([
        card([t], tiers: [0]),
      ]),
      [pay(9001, '2026-09-02T10:00', merchant: 'gs25')],
    )[0];
    expect(values([r]), [
      {'gs': 1000},
    ]);
    expect(r.benefits[0].base, 10001);
  });

  test('test_unknown_adjust_uses_smaller_limit', () {
    // 카페 10% 월 1만원, 가족카드는 월 5천원. 가족카드인지 모르면 작은 한도로 보고 묻는다.
    // 2만원 세 번이면 2,000 + 2,000 + 1,000 = 5,000. 아니라고 답하면 6,000. 2026-09-29 사용자가 정했다. 설계 3.1
    final cafeLimit = b('cafe-10', cafe, rate10, {
      'limits': [
        {
          'per': 'month',
          'amount': 10000,
          'adjust': [
            {
              'when': {'fact': 'family'},
              'amount': 5000,
            },
          ],
        },
      ],
    });
    final eng = engine([
      card(
        [cafeLimit],
        tiers: [0],
        rules: {
          'facts': [
            {
              'key': 'family',
              'type': 'bool',
              'scope': 'card',
              'ask': '가족카드인가요',
            },
          ],
        },
      ),
    ]);
    final pays = [
      for (final d in [2, 3, 4])
        pay(20000, '2026-09-0${d}T10:00', merchant: 'ediya'),
    ];
    final r = run(eng, pays);
    expect(values(r), [
      {'cafe-10': 2000},
      {'cafe-10': 2000},
      {'cafe-10': 1000},
    ]);
    expect(codes(r[2]), contains('needs_input'));
    expect(values(run(eng, pays, holder(facts: {'family': false})))[2], {
      'cafe-10': 2000,
    });
  });

  test('test_month_recompute_after_import', () {
    // 9월 3일 카페 결제가 월 1천원 한도를 다 쓴 뒤, 엑셀로 9월 2일 결제가 들어오면 서버가 그 달을 다시 계산한다.
    // 카드사처럼 9월 2일이 1,000원, 9월 3일이 0원이다. 2026-09-29 사용자가 정했다. 설계 3.9
    final eng = engine([
      card(
        [
          b('cafe-10', cafe, rate10, {
            'limits': [
              {'per': 'month', 'amount': 1000},
            ],
          }),
        ],
        tiers: [0],
      ),
    ]);
    final later = pay(10000, '2026-09-03T10:00', merchant: 'ediya');
    final kept = later.copyWith(benefits: run(eng, [later])[0].benefits);
    final imported = pay(10000, '2026-09-02T10:00', merchant: 'ediya');
    final again = eng.priceMonth(holder(), [
      kept,
      imported,
    ], month: day(2026, 9, 1));
    expect(
      {
        for (final x in again)
          x.paymentId: x.benefits.fold(0, (s, y) => s + y.value),
      },
      {imported.id: 1000, later.id: 0},
    );
  });
}
