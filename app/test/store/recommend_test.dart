// 추천. Python `backend/tests/api/test_recommend.py`를 옮겼다. 작업 006 계획 단계 4의 6. S4
//
// 신한카드 Mr.Life 30만 구간. 야간 식음료 10%는 21시부터 9시, 1회 1만 원까지, 하루 1회. 편의점 10%는 하루 1회.
// 현대 ZERO Edition3 할인형은 모든 가맹점 0.8%. 시계는 2026-09-15 화요일 21:00 한국 시간이다.
// 추천 요청 표가 없어 요청과 순위 행 수를 세는 부분, 남의 요청과 남의 가게 부분, 모르는 칸 시험은 옮기지 않는다
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/routes/recommend.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const zeroCard = {'card_id': 'hyundai-zero-edition3-discount'};
const ibk300 = {
  'card_id': 'ibk-narasarang',
  'assumed_prev_month_spend': 300000,
};

Json ask(Store s, Json body) => recommend(s, body);

List<Json> ranking(Json r) => [for (final x in r['ranking'] as List) x as Json];

void main() {
  test('test_cafe_at_night', () {
    // 21시 스타벅스 1만 원. Mr.Life 야간 식음료 10%로 1,000원, ZERO 0.8%로 80원
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    final r = ask(s, {'merchant_name': '스타벅스 역삼점', 'amount': 10000});
    expect(
      (r['merchant'], r['category'], r['category_name']),
      ('starbucks', 'cafe', '카페'),
    );
    final [first, second] = ranking(r);
    expect(
      (first['user_card_id'], first['value'], first['title']),
      (mr, 1000, '야간 식음료 10% 할인'),
    );
    expect(first['rewards'], ['billing_discount']);
    expect((second['user_card_id'], second['value']), (zero, 80));
  });

  test('test_cafe_at_noon', () {
    // 12시에는 야간 식음료가 아니라 Mr.Life 0원, ZERO 80원이 1순위
    final (:s, :clock) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    clock.now = DateTime.utc(2026, 9, 15, 3);
    final r = ask(s, {'merchant_name': '스타벅스', 'amount': 10000});
    expect(
      [for (final x in ranking(r)) (x['user_card_id'], x['value'])],
      [(zero, 80), (mr, 0)],
    );
  });

  test('test_no_amount_is_ten_thousand', () {
    // E11. 금액을 비우면 1만 원으로 계산하고 금액 칸은 비운 채 돌려준다
    final (:s, clock: _) = fresh();
    setup(s, [mrlife, zeroCard]);
    final r = ask(s, {'merchant_name': '스타벅스'});
    expect((r['amount'], ranking(r).first['value']), (null, 1000));
  });

  test('test_exhausted_limit', () {
    // E10. 편의점 할인을 오늘 한 번 쓰면 Mr.Life는 GS25에서 0원이고 한도 소진으로 보인다. ZERO 80원이 1순위
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    pay(s, mr, 4300, 'GS25');
    final r = ask(s, {'merchant_name': 'GS25', 'amount': 10000});
    expect(
      [
        for (final x in ranking(r))
          (x['user_card_id'], x['value'], x['exhausted']),
      ],
      [(zero, 80, false), (mr, 0, true)],
    );
  });

  test('test_pay_with_another_method', () {
    // IBK 나라사랑 25만 구간. 이마트에는 실물카드로 받는 IBK 혜택이 없고, 네이버페이로 내면 Npay 10% 적립이
    // 1회 1,000원까지라 1만 원에 1,000원을 더 받는다. 1포인트 1원
    final (:s, clock: _) = fresh();
    setup(s, [ibk300]);
    final [row] = ranking(ask(s, {'merchant_name': '이마트', 'amount': 10000}));
    expect(row['value'], 0);
    expect(
      row['pay_with'],
      contains(
        equals({'payment_method': 'naver_pay', 'name': '네이버페이', 'extra': 1000}),
      ),
    );
  });

  test('test_top_by_category', () {
    // 업종별 지금 1순위. 업종 12개, 1만 원 기준. 21시 카페는 Mr.Life 1,000원, 화요일 마트는 주말이 아니라 ZERO 80원
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    final rows = top(s);
    expect(rows, hasLength(12));
    final by = {for (final r in rows) r['category']: r};
    expect(
      (
        by['cafe']!['user_card_id'],
        by['cafe']!['value'],
        by['cafe']!['category_name'],
      ),
      (mr, 1000, '카페'),
    );
    expect(
      (by['grocery_mart']!['user_card_id'], by['grocery_mart']!['value']),
      (zero, 80),
    );
  });

  test('test_recent_merchants', () {
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25 테헤란점', at: '2026-09-15T10:00:00+09:00');
    pay(s, card, 4500, '스타벅스 역삼점', at: '2026-09-15T11:00:00+09:00');
    pay(s, card, 4300, 'GS25 테헤란점', at: '2026-09-15T12:00:00+09:00');
    expect(recent(s), ['GS25 테헤란점', '스타벅스 역삼점']);
  });

  test('test_payment_follows_the_recommendation', () {
    // S4. 추천에서 결제를 기록하면 결제에 "추천에서 기록함" 표시가 남는다. 서버는 추천 요청 id를 달았다. 설계 4절
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    expect(
      ask(s, {'merchant_name': 'GS25', 'amount': 4300})['request_id'],
      isNull,
    );
    pay(s, card, 4300, 'GS25', more: {'from_recommendation': true});
    pay(s, card, 1000, 'GS25', at: '2026-09-15T21:30:00+09:00');
    final marks = [
      for (final r in s.db.select(
        'select from_recommendation from transactions order by paid_at',
      ))
        r['from_recommendation'],
    ];
    expect(marks, [1, 0]);
  });

  test('test_no_cards', () {
    // E17. 카드가 없으면 순위가 비고 업종별 1순위도 빈다
    final (:s, clock: _) = fresh();
    expect(ask(s, {'merchant_name': 'GS25'})['ranking'], isEmpty);
    expect(top(s), isEmpty);
  });

  test('test_points_card_says_points', () {
    // 신한 Point Plan 40만 구간. GS25 1만 원은 3만 원 미만 0.5% 적립이라 50포인트, 1포인트 1원. 적립으로 보인다. E13
    final (:s, clock: _) = fresh();
    setup(s, [
      {'card_id': 'shinhan-pointplan', 'assumed_prev_month_spend': 410000},
    ]);
    final [row] = ranking(ask(s, {'merchant_name': 'GS25', 'amount': 10000}));
    expect(row['value'], 50);
    expect(row['rewards'], ['points']);
  });

  test('test_top_skips_categories_missing_from_the_catalog', () {
    // 카탈로그에서 영화 업종이 빠져도 추천 탭이 오류로 덮이지 않고 그 줄만 빠진다
    final (:s, clock: _) = fresh((j) {
      (j['categories'] as List).removeWhere((c) => c['code'] == 'movie');
    });
    setup(s);
    final rows = top(s);
    expect(rows, hasLength(11));
    expect({for (final r in rows) r['category']}, isNot(contains('movie')));
  });

  test('test_recent_merchants_are_mine_and_four', () {
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    for (final (n, name) in ['가게1', '가게2', '가게3', '가게4', '가게5'].indexed) {
      pay(s, card, 1000, name, at: '2026-09-15T1$n:00:00+09:00');
    }
    expect(recent(s), ['가게5', '가게4', '가게3', '가게2']);
  });

  test('test_billing_bound_category_is_not_calculated', () {
    // 지하철은 IBK 나라사랑 대중교통 20%처럼 후불교통 조건이 붙는다. 가게 없이 업종만 물으면 청구 방식을 몰라
    // ZERO 80원을 1순위로 잘못 보인다. 담을 수 없는 질문이라 계산하지 않고 미지원으로 돌려준다
    final (:s, clock: _) = fresh();
    setup(s, [ibk300, zeroCard]);
    final r = ask(s, {'category': 'transit.subway', 'amount': 10000});
    expect((r['unsupported'], r['request_id']), ('billing', null));
    expect(r['ranking'], isEmpty);
    final cats = {for (final t in top(s)) t['category']};
    expect(
      cats.intersection({
        'transit.subway',
        'transit.bus_city',
        'telecom.mobile',
      }),
      isEmpty,
    );
  });
}
