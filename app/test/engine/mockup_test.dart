// 화면 시안의 숫자를 시안 카드로 재현한다. Python `backend/tests/engine/test_mockup.py`를 옮겼다. 엔진 설계 6.3
//
// 시안 카드는 `backend/tests/engine/mockup/`의 지어낸 카드이고, Python이 `test/fixtures/mockup_catalog.json`으로 만든다.
// 시안 Mr.Life는 9월 1일에 등록하며 지난달 41만원으로 적었다. 9월 결제는 카페 3건, 편의점 1건, 기타 2건으로
// 이번 달 182,000원이다. 시안 IBK는 편의점 3건과 기타 1건으로 265,000원, 시안 ZERO는 쿠팡, 자동차세, 기타다
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final now = at('2026-09-20T12:00');
final sept = day(2026, 9, 1);

Engine mockEngine() => Engine(
  Catalog.fromJson(
    jsonDecode(File('test/fixtures/mockup_catalog.json').readAsStringSync())
        as Json,
  ),
);

List<Payment> mine(String cardId, List<Payment> ps) => [
  for (final p in ps) p.copyWith(userCardId: cardId),
];

int sumValues(List<PaymentResult> rs) => rs.fold(0, (s, r) => s + r.value);

void main() {
  late Engine eng;
  late Map<String, UserCard> cards;
  late Map<String, List<PaymentResult>> results;
  late Map<String, List<Payment>> kept;

  setUpAll(() {
    eng = mockEngine();
    final list = [
      UserCard(
        id: 'mr',
        cardId: 'mock-mrlife',
        registeredOn: sept,
        assumedPrevMonthSpend: 410000,
      ),
      UserCard(
        id: 'ibk',
        cardId: 'mock-ibk',
        registeredOn: sept,
        assumedPrevMonthSpend: 250000,
      ),
      UserCard(id: 'zero', cardId: 'mock-zero', registeredOn: sept),
    ];
    final raw = {
      'mr': mine('mr', [
        pay(10000, '2026-09-05T10:00', merchant: 'ediya'),
        pay(60000, '2026-09-08T12:00', category: 'other'),
        pay(10000, '2026-09-12T10:00', merchant: 'ediya'),
        pay(30000, '2026-09-15T18:00', merchant: 'gs25'),
        pay(59500, '2026-09-16T13:00', category: 'other'),
        pay(12500, '2026-09-19T14:20', merchant: 'starbucks'),
      ]),
      'ibk': mine('ibk', [
        pay(5700, '2026-09-06T09:00', merchant: 'gs25'),
        pay(5000, '2026-09-10T09:00', merchant: 'gs25'),
        pay(250000, '2026-09-11T19:00', category: 'other'),
        pay(4300, '2026-09-19T09:02', merchant: 'gs25'),
      ]),
      'zero': mine('zero', [
        pay(128000, '2026-09-18T11:00', category: 'tax'),
        pay(36900, '2026-09-18T21:00', merchant: 'coupang', channel: 'online'),
        pay(130143, '2026-09-20T10:00', category: 'other'),
      ]),
    };
    cards = {for (final c in list) c.id: c};
    results = {};
    kept = {};
    for (final c in list) {
      final rs = eng.priceMonth(c, raw[c.id]!);
      results[c.id] = rs;
      kept[c.id] = saved(raw[c.id]!, rs);
    }
  });

  test('test_1_saved_this_month', () {
    // 3쪽 홈 이번 달 아낀 돈 7,669원 = Mr.Life 4,500 + IBK 2,000 + ZERO 1,169
    expect(
      {
        for (final MapEntry(:key, :value) in results.entries)
          key: sumValues(value),
      },
      {'mr': 4500, 'ibk': 2000, 'zero': 1169},
    );
  });

  test('test_2_and_5_mrlife_status', () {
    // 3쪽과 6쪽. 지난달 41만 기준 30만 구간, 이번 달 182,000원, 유지까지 11.8만, 60만까지 41.8만. 4쪽 등록 41만이면 30만 구간
    final s = eng.spendStatus(cards['mr']!, kept['mr']!, sept);
    expect(
      (s.tier, s.tierSource, s.prevMonthCounted),
      (300000, 'assumed', 410000),
    );
    expect(
      (s.counted, s.toKeep, s.nextTier, s.toNext),
      (182000, 118000, 600000, 418000),
    );
  });

  test('폰 시간 날짜를 넘겨도 UTC 날짜와 같게 센다', () {
    // 2026-10-02 위험 검토. Dart DateTime은 UTC 여부까지 같아야 같은 값이라 엔진이 날짜 인자를 UTC 자정으로 맞춘다.
    // 달과 등록일을 폰 시간으로 넘겨도 test_2_and_5와 test_1의 숫자가 나온다
    final mr = UserCard(
      id: 'mr',
      cardId: 'mock-mrlife',
      registeredOn: DateTime(2026, 9, 1),
      assumedPrevMonthSpend: 410000,
    );
    final s = eng.spendStatus(mr, kept['mr']!, DateTime(2026, 9, 1));
    expect(
      (s.tier, s.tierSource, s.counted, s.toKeep, s.toNext),
      (300000, 'assumed', 182000, 118000, 418000),
    );
    final again = eng.priceMonth(mr, kept['mr']!, month: DateTime(2026, 9, 1));
    expect(sumValues(again), 4500);
  });

  test('test_3_mrlife_limits', () {
    // 6쪽. 통합 1만 중 4,500 사용, 잔여 5,500. 카페 잔여 2,000/5,000, 편의점 잔여 3,500/5,000
    final uses = {
      for (final u in eng.limitStatus(cards['mr']!, kept['mr']!, now))
        (u.key, u.per): u,
    };
    final integrated = uses[('integrated', 'month')]!,
        cafe = uses[('cafe-10', 'month')]!,
        cvs = uses[('cvs-5', 'month')]!;
    expect(
      (integrated.usedAmount, integrated.capAmount! - integrated.usedAmount),
      (4500, 5500),
    );
    expect((cafe.capAmount! - cafe.usedAmount, cafe.capAmount), (2000, 5000));
    expect((cvs.capAmount! - cvs.usedAmount, cvs.capAmount), (3500, 5000));
  });

  test('test_4_ibk_and_zero', () {
    // 3쪽. IBK 20만 구간 할인 잔여 3,000원, 이번 달 20만을 넘어 다음 달 구간 확정. ZERO 이번 달 1,169원
    final uses = {
      for (final u in eng.limitStatus(cards['ibk']!, kept['ibk']!, now))
        (u.key, u.per): u,
    };
    final integrated = uses[('integrated', 'month')]!;
    expect(integrated.capAmount! - integrated.usedAmount, 3000);
    final s = eng.spendStatus(cards['ibk']!, kept['ibk']!, sept);
    expect((s.tier, s.toKeep), (200000, 0));
    expect(sumValues(results['zero']!), 1169);
  });

  test('test_6_and_7_records', () {
    // 7쪽 스타벅스 12,500원 1,000원, 실적 인정. 10쪽 GS25 4,300원 430원, 자동차세 0원 실적 제외, 쿠팡 36,900원 258원
    final starbucks = results['mr']![5];
    expect(
      [for (final b in starbucks.benefits) (b.key, b.value)],
      [('cafe-10', 1000)],
    );
    expect(starbucks.spend[0].amount, 12500);
    expect([for (final b in results['ibk']![3].benefits) b.value], [430]);
    final tax = results['zero']![0], coupang = results['zero']![1];
    expect(tax.benefits, isEmpty);
    expect(tax.spend, isEmpty);
    expect(tax.warnings[0].data, {'reason': 'category'});
    expect([for (final b in coupang.benefits) b.value], [258]);
  });

  test('test_8_category_tops', () {
    // 8쪽. 1만원 기준 카페 Mr.Life 1,000, 편의점 IBK 1,000, 음식점·온라인·대중교통 ZERO 70
    final queries = [
      for (final c in [
        'cafe',
        'convenience',
        'restaurant',
        'online_shopping',
        'transit',
      ])
        Query(category: c),
    ];
    final tops = [
      for (final rows in eng.recommend(
        cards.values.toList(),
        kept,
        queries,
        now,
      ))
        (rows[0].cardId, rows[0].value),
    ];
    expect(tops, [
      ('mock-mrlife', 1000),
      ('mock-ibk', 1000),
      ('mock-zero', 70),
      ('mock-zero', 70),
      ('mock-zero', 70),
    ]);
  });

  test('test_9_starbucks_recommendation', () {
    // 9쪽. 1위 Mr.Life 1,000, 2위 ZERO 70, 3위 IBK 20. 스타벅스 20%는 90만 구간, 이번 달 18.2만이라 71.8만 더
    final [rows] = eng.recommend(cards.values.toList(), kept, [
      const Query(merchant: 'starbucks'),
    ], now);
    expect(
      [for (final r in rows) (r.cardId, r.value)],
      [('mock-mrlife', 1000), ('mock-zero', 70), ('mock-ibk', 20)],
    );
    final [lock] = [
      for (final x in rows[0].locked)
        if (x.benefit == 'sb-20') x,
    ];
    expect(
      (lock.requiredTier, lock.remainingThisMonth, lock.valueIfUnlocked),
      (900000, 718000, 2000),
    );
    expect(rows[0].counted, isTrue);
  });

  test('test_9b_naver_pay_conditional', () {
    // 5b 추천 결과의 3위 IBK. 스타벅스 1만원을 네이버페이로 내면 10% 1,000P라, 실물카드 기본 0.2% 20원보다 980원 더
    final [rows] = eng.recommend(cards.values.toList(), kept, [
      const Query(merchant: 'starbucks'),
    ], now);
    final ibk = rows.firstWhere((r) => r.cardId == 'mock-ibk');
    expect(
      [
        for (final c in ibk.conditional) [c.benefit, c.needs, c.extra],
      ],
      [
        [
          'npay-10',
          {'payment_method': 'naver_pay'},
          980,
        ],
      ],
    );
  });

  test('test_10_import_preview_august', () {
    // 12쪽 8월 가져오기 미리보기. 스타벅스 6,100원 610원, 쿠팡 24,900원 혜택 없음, 자동차세 실적 제외
    final mr = UserCard(
      id: 'mr',
      cardId: 'mock-mrlife',
      registeredOn: day(2026, 8, 1),
      assumedPrevMonthSpend: 410000,
    );
    final rs = mockEngine().priceMonth(
      mr,
      mine('mr', [
        pay(6100, '2026-08-29T10:00', merchant: 'starbucks'),
        pay(24900, '2026-08-28T20:00', merchant: 'coupang', channel: 'online'),
        pay(128000, '2026-08-25T11:00', category: 'tax'),
      ]),
    );
    final byAmount = {
      for (final r in rs) r.spend.isNotEmpty ? r.spend[0].amount : 0: r,
    };
    expect([for (final b in byAmount[6100]!.benefits) b.value], [610]);
    expect(byAmount[24900]!.benefits, isEmpty);
    expect(byAmount[0]!.warnings[0].data, {'reason': 'category'});
  });

  test('test_11_cafe_limit_exhausted_and_reset', () {
    // 14쪽. 카페 한도 5,000원을 다 쓰면 0원과 limit_exhausted, 10월 1일에 초기화
    final mr = UserCard(
      id: 'mr',
      cardId: 'mock-mrlife',
      registeredOn: sept,
      assumedPrevMonthSpend: 410000,
    );
    final cafe = [
      for (final d in [1, 2, 3, 4, 5, 6])
        pay(
          10000,
          '2026-09-${d.toString().padLeft(2, '0')}T10:00',
          merchant: 'ediya',
        ),
    ];
    final rs = mockEngine().priceMonth(
      mr,
      mine('mr', [
        pay(300000, '2026-09-07T12:00', category: 'other'),
        ...cafe,
        pay(10000, '2026-10-01T10:00', merchant: 'ediya'),
      ]),
    );
    expect(
      [for (final r in rs) r.value],
      [1000, 1000, 1000, 1000, 1000, 0, 0, 1000],
    );
    expect(codes(rs[5]), contains('limit_exhausted'));
  });
}
