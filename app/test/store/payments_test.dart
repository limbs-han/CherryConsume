// 결제 기록. Python `backend/tests/api/test_payments.py`를 옮겼다. 작업 006 계획 단계 4의 3
//
// 신한카드 Mr.Life 2026-07-15 개정. 편의점 10% 할인은 30만 구간부터, 1회 승인금액 1만 원까지, 하루 1회, 월 5회.
// 신한 공통 규칙은 카카오페이, 네이버페이, 페이코, 토스페이 결제와 무이자할부를 혜택에서 뺀다. 할부는 결제한 달에 다 넣는다.
// 현대 ZERO Edition3 할인형은 구간 없이 모든 가맹점 0.8% 할인이다. 시계는 2026-09-15 21:00 한국 시간이다.
// 취소, 고치기, 지우기가 필요한 시험은 단계 4의 4에서 옮긴다. 같은 번호 다시 보내기 E24는 서버가 없어 옮기지 않는다
import 'dart:convert';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/routes/answers.dart';
import 'package:cherry_consume/store/routes/catalog.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/payments.dart';
import 'package:cherry_consume/store/routes/records.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const zeroCard = {'card_id': 'hyundai-zero-edition3-discount'};
const ibk300 = {
  'card_id': 'ibk-narasarang',
  'assumed_prev_month_spend': 300000,
};

int benefitTotal(Store s) => home(s)['benefit_total'] as int;

Json firstSpend(Store s) => (home(s)['cards'] as List).first['spend'] as Json;

List<(Object?, Object?)> ranks(Json d) => [
  for (final r in d['ranking'] as List) (r['user_card_id'], r['value']),
];

void main() {
  test('test_categories_and_payment_methods', () {
    final (:s, clock: _) = fresh();
    final restaurant = categories(
      s,
    ).firstWhere((c) => c['code'] == 'restaurant');
    expect(
      restaurant['children'],
      contains(equals({'code': 'restaurant.general', 'name': '일반음식점'})),
    );
    expect(
      paymentMethods(s),
      contains(equals({'key': 'physical_card', 'name': '실물카드'})),
    );
  });

  test('test_draft_fills_from_merchant', () {
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final d = draft(s, {'amount': 4300, 'merchant_name': 'GS25 테헤란점'});
    expect(
      (d['merchant'], d['category'], d['category_name'], d['channel']),
      ('gs25', 'convenience', '편의점', 'offline'),
    );
    expect(d['pick'], card);
    // 4,300원의 10%는 430원
    final est = d['estimate'] as Json;
    expect(
      (est['value'], est['payment_method'], est['counted']),
      (430, 'physical_card', true),
    );
    expect(est['benefits'], [
      {
        'key': 'time-convenience',
        'title': '편의점 10% 할인',
        'amount': 430,
        'value': 430,
      },
    ]);
  });

  test('test_save_then_home', () {
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    expect(pay(s, card, 4300, 'GS25 테헤란점')['value'], 430);
    expect(benefitTotal(s), 430);
    // 30만 구간을 지키려면 300,000 - 4,300 = 295,700원
    final spend = firstSpend(s);
    expect(
      (spend['counted'], spend['to_keep'], spend['to_next']),
      (4300, 295700, 495700),
    );
    final row = s.db.select('select * from transaction_benefits').single;
    expect(
      (row['benefit_key'], row['amount'], row['value'], row['base_amount']),
      ('time-convenience', 430, 430, 4300),
    );
  });

  test('test_second_convenience_same_day_is_zero', () {
    // 편의점 할인은 하루 1회다. E10
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    expect(
      pay(s, card, 5000, 'GS25', at: '2026-09-15T22:00:00+09:00')['value'],
      0,
    );
    expect(benefitTotal(s), 430);
  });

  test('test_earlier_payment_reprices_the_month', () {
    // E52. 같은 날 21시 4,300원이 430원을 받은 뒤 10시 5,000원을 넣는다. 편의점 할인은 하루 1회라
    // 카드사처럼 시각 순서로 다시 계산하면 10시가 5,000원의 10%인 500원, 21시가 0원이다. 합계 500원
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    final saved = pay(s, card, 5000, 'GS25', at: '2026-09-15T10:00:00+09:00');
    expect((saved['value'], saved['repriced']), (500, 1));
    expect(benefitTotal(s), 500);
  });

  test('test_earlier_payment_on_another_day_keeps_values', () {
    // 하루 1회 한도는 날마다라 9월 14일 결제는 9월 15일 결제와 겹치지 않는다. 500원과 430원으로 합계 930원
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    expect(
      pay(s, card, 5000, 'GS25', at: '2026-09-14T10:00:00+09:00')['value'],
      500,
    );
    expect(benefitTotal(s), 930);
  });

  test('test_last_month_payment_reprices_this_month', () {
    // E53. 추정 41만으로 30만 구간이라 9월 15일 GS25 4,300원이 430원을 받았다
    // 8월 20일 이마트 1만 원을 넣으면 E2대로 8월 기록 1만 원이 구간을 정해 9월은 0원 구간이다. 430원이 0원이 된다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    expect(
      pay(s, card, 10000, '이마트', at: '2026-08-20T12:00:00+09:00')['repriced'],
      1,
    );
    expect((benefitTotal(s), firstSpend(s)['tier']), (0, 0));
  });

  test('test_last_month_payment_with_the_same_tier_keeps_values', () {
    // 8월 이마트 30만 원은 30만 구간 하한 그대로라 9월 구간이 바뀌지 않는다. 430원이 남는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    expect(
      pay(s, card, 300000, '이마트', at: '2026-08-20T12:00:00+09:00')['repriced'],
      0,
    );
    expect(benefitTotal(s), 430);
  });

  test('test_payment_method_follows_each_card', () {
    // 신한 공통 규칙은 네이버페이 결제를 혜택에서 빼지만 Mr.Life 파일은 그 제외를 빈 목록으로 덮는다
    // Mr.Life 원문에 간편결제 제외 문구가 없어서다. 카드별 규칙을 따라 Mr.Life는 네이버페이도 430원이다
    // Point Plan은 공통 규칙을 그대로 따라 네이버페이면 0원, 실물카드면 1만 원의 0.5%인 50포인트, 1포인트 1원
    final (:s, clock: _) = fresh();
    final [mr, plan] = setup(s, [
      mrlife,
      {'card_id': 'shinhan-pointplan', 'assumed_prev_month_spend': 410000},
    ]);
    expect(
      pay(s, mr, 4300, 'GS25', more: {'payment_method': 'naver_pay'})['value'],
      430,
    );
    expect(
      pay(
        s,
        plan,
        10000,
        'GS25',
        more: {'payment_method': 'naver_pay'},
      )['value'],
      0,
    );
    const later = '2026-09-15T21:30:00+09:00';
    expect(
      pay(
        s,
        plan,
        10000,
        'GS25',
        at: later,
        more: {'payment_method': 'physical_card'},
      )['value'],
      50,
    );
    // 다음 결제의 결제수단은 그 카드로 마지막에 쓴 것으로 채운다. S3
    final d = draft(s, {
      'amount': 4300,
      'merchant_name': 'GS25',
      'user_card_id': mr,
    });
    expect(d['estimate']['payment_method'], 'naver_pay');
  });

  test('test_payment_points_to_the_revision_used', () {
    // 서버는 개정 행 번호를 적었다. 폰은 개정 표가 없어 계산에 쓴 개정의 시행일과 규칙 지문을 적는다. 설계 4절
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    final t = s.db
        .select('select revision_from, revision_sha from transactions')
        .single;
    final rev = s.catalog.cards['shinhan-mrlife']!.revisions.firstWhere(
      (r) => dayText(r.effectiveFrom) == '2026-07-15',
    );
    expect((t['revision_from'], t['revision_sha']), ('2026-07-15', rev.sha256));
  });

  test('test_last_month_payment_beats_the_guess', () {
    // E2. 등록한 달에 지난달 결제를 넣으면 추정 41만 대신 그 결제의 합 50만으로 구간을 정한다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 500000, '이마트 성수점', at: '2026-08-20T12:00:00+09:00');
    final spend = firstSpend(s);
    expect(
      (spend['tier'], spend['tier_source'], spend['prev_month_counted']),
      (500000, 'prev_month', 500000),
    );
  });

  test('test_installment_counts_in_the_month_paid', () {
    // E4. 신한은 할부를 결제한 달에 다 넣는다. 3개월 할부 30만 원은 이번 달 30만 원이고 30만 구간을 지켰다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 300000, '이마트', more: {'installment_months': 3});
    final spend = firstSpend(s);
    expect((spend['counted'], spend['to_keep']), (300000, 0));
  });

  test('test_ranking_picks_the_best_card', () {
    // GS25 1만 원. Mr.Life는 10%로 1,000원, ZERO는 0.8%로 80원
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    final d = draft(s, {'amount': 10000, 'merchant_name': 'GS25'});
    expect(ranks(d), [(mr, 1000), (zero, 80)]);
    expect(d['pick'], mr);
    final picked = draft(s, {
      'amount': 10000,
      'merchant_name': 'GS25',
      'user_card_id': zero,
    });
    expect((picked['pick'], picked['estimate']['value']), (zero, 80));
  });

  test('test_longest_alias_wins_and_online_channel', () {
    // "쿠팡이츠"에는 별칭 "쿠팡"과 "쿠팡이츠"가 함께 들어 있다. 긴 쪽인 배달앱이다. 배달앱은 온라인으로 채운다
    final (:s, clock: _) = fresh();
    setup(s);
    final d = draft(s, {'merchant_name': '쿠팡이츠'});
    expect(
      (d['merchant'], d['category'], d['channel']),
      ('coupang_eats', 'delivery_app', 'online'),
    );
  });

  test('test_unknown_merchant_leaves_category_empty', () {
    // E16. 못 찾은 가게는 업종을 비우고 이름은 적은 그대로 둔다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final d = draft(s, {'merchant_name': '동네 카페 달빛'});
    expect((d['merchant'], d['category'], d['estimate']), (null, null, null));
    // 업종을 고르면 그 업종으로 계산한다. 21시 카페는 Mr.Life 야간 식음료 10%로 450원
    expect(
      pay(s, card, 4500, '동네 카페 달빛', more: {'category': 'cafe'})['value'],
      450,
    );
  });

  test('test_bad_payments', () {
    // 모르는 칸과 남의 카드 시험은 옮기지 않는다. 설계 4절
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final base = {
      'user_card_id': card,
      'amount': 4300,
      'paid_at': '2026-09-15T21:00:00+09:00',
    };
    void bad(Json more, int code) => expect(
      () => save(s, {...base, ...more}),
      throwsA(status(code)),
      reason: '$more',
    );
    bad({'paid_at': '2026-09-17T00:00:00+09:00'}, 422); // 하루 넘게 뒤
    bad({'category': 'nope'}, 422);
    bad({'payment_method': 'nope'}, 422);
    bad({'amount': 0}, 422);
    bad({'interest_free': true}, 422); // 일시불은 무이자할부가 아니다
    bad({'user_card_id': 'not-a-uuid'}, 404);
    expect(s.db.select('select * from transactions'), isEmpty);
  });

  test('test_benefit_total_is_this_month_only', () {
    final (:s, :clock) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    clock.now = DateTime.utc(2026, 10, 2, 3);
    expect(benefitTotal(s), 0);
  });

  test('test_same_time_payments_follow_entry_order', () {
    // 같은 시각의 두 결제는 먼저 넣은 결제가 하루 1회 한도를 쓴다. 무작위 id면 절반은 두 번째도 500원을 받았다
    for (var n = 0; n < 8; n++) {
      final (:s, clock: _) = fresh();
      final [card] = setup(s);
      pay(s, card, 4300, 'GS25');
      expect(pay(s, card, 5000, 'GS25')['value'], 0, reason: '$n');
    }
  });

  test('test_convenience_cap_is_per_payment', () {
    // 1회 승인금액 1만 원까지 할인이라 10,001원도 1,000원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    expect(pay(s, card, 10001, 'GS25')['value'], 1000);
  });

  test('test_benefit_total_uses_korean_month', () {
    // 9월 30일 23:30 한국 시간은 UTC로 9월 30일 14:30이다. 10월 1일 00:30 한국 시간에는 지난달 혜택이다
    final (:s, :clock) = fresh();
    clock.now = DateTime.utc(2026, 9, 30, 14, 45);
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25', at: '2026-09-30T23:30:00+09:00');
    expect(benefitTotal(s), 430);
    clock.now = DateTime.utc(2026, 9, 30, 15, 30);
    expect(benefitTotal(s), 0);
  });

  test('test_merchant_names_that_must_not_match', () {
    // 2026-10-01 위험 검토 두 번이 찾은 이름. 짧은 별칭이 다른 가게에 걸리면 안 된다
    final (:s, clock: _) = fresh();
    setup(s);
    const wrong = [
      '롯데하이마트 강남점',
      'COSTCO',
      '파고다 토익학원',
      '카카오TV',
      '카카오페이지',
      '멜론빵 가게',
      '멜론빵 전문점',
      '컬리헤어 역삼점',
      '토익스터디카페 강남점',
      '옥션하우스 강남점',
      '자라섬 캠핑장',
      '자라탕 전문점',
      'Tropical Juice',
      'STEPS 댄스',
      'desktop shop',
      'Arnold',
      '스타벅스역삼점',
    ];
    for (final name in wrong) {
      expect(
        draft(s, {'merchant_name': name})['merchant'],
        isNull,
        reason: name,
      );
    }
    const right = {
      '스타벅스 역삼점': 'starbucks',
      'GS25 테헤란점': 'gs25',
      '이마트24 역삼점': 'emart24',
      'LOTTE MART 잠실점': 'lotte_mart',
      '쿠팡이츠': 'coupang_eats',
      // 2026-10-01 사용자가 이마트, 쿠팡과 다른 가게로 보기로 했고 골드를 거쳐 카탈로그에 들어왔다. 띄어 써도 다른 가게다
      '이마트 트레이더스 월계점': 'traders',
      '이마트트레이더스 월계점': 'traders',
      '쿠팡 플레이': 'coupang_play',
      '쿠팡플레이': 'coupang_play',
    };
    for (final MapEntry(key: name, value: key) in right.entries) {
      expect(draft(s, {'merchant_name': name})['merchant'], key, reason: name);
    }
  });

  test('test_streaming_is_online', () {
    final (:s, clock: _) = fresh();
    setup(s);
    final d = draft(s, {'merchant_name': '넷플릭스'});
    expect((d['category'], d['channel']), ('streaming', 'online'));
  });

  test('test_ranking_value_matches_the_estimate', () {
    // 순위 금액도 할부까지 넣어 계산한다. 1순위로 고른 카드의 순위 금액과 예상 혜택이 같다
    final (:s, clock: _) = fresh();
    setup(s, [mrlife, zeroCard]);
    final d = draft(s, {
      'amount': 30000,
      'merchant_name': '이마트',
      'installment_months': 3,
      'interest_free': true,
    });
    expect((d['ranking'] as List).first['value'], d['estimate']['value']);
    expect((d['ranking'] as List).first['user_card_id'], d['pick']);
  });

  test('test_billing_is_frozen_when_saved', () {
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 4300, 'GS25');
    expect(
      s.db.select('select billing from transactions').single['billing'],
      'normal',
    );
  });

  test('test_deferred_spend_chain_skips_a_month', () {
    // 신한은 지하철 실적을 다음 달에 넣는다. 8월 31일 지하철 1만 원은 9월 실적이다
    // 9월 이마트 29만에 더해 9월 실적이 30만이 되어 10월이 30만 구간이 된다. 9월 구간은 그대로 0원이다
    // 그래서 9월에서 멈추지 않고 10월까지 봐야 10월 5일 GS25 4,300원이 0원에서 430원이 된다
    final (:s, :clock) = fresh();
    clock.now = DateTime.utc(2026, 8, 1, 3);
    final [card] = setup(s);
    clock.now = DateTime.utc(2026, 9, 10, 3);
    pay(s, card, 290000, '이마트', at: '2026-09-10T12:00:00+09:00');
    clock.now = DateTime.utc(2026, 10, 5, 3);
    expect(
      pay(s, card, 4300, 'GS25', at: '2026-10-05T12:00:00+09:00')['value'],
      0,
    );
    clock.now = DateTime.utc(2026, 10, 15, 3);
    final saved = pay(
      s,
      card,
      10000,
      '지하철',
      at: '2026-08-31T12:00:00+09:00',
      more: {'category': 'transit.subway'},
    );
    expect(saved['repriced'], 1);
    expect((firstSpend(s)['tier'], benefitTotal(s)), (300000, 430));
  });

  test('test_same_value_puts_the_card_short_of_its_tier_first', () {
    // 이마트 3만 원 3개월 무이자. Mr.Life는 평일이라 주말 마트 할인이 없고, ZERO는 현대 공통 규칙이 무이자할부를 뺀다
    // 둘 다 0원이면 설계 4.2대로 30만 구간까지 실적이 모자란 Mr.Life가 앞이다
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    final d = draft(s, {
      'amount': 30000,
      'merchant_name': '이마트',
      'installment_months': 3,
      'interest_free': true,
    });
    expect(ranks(d), [(mr, 0), (zero, 0)]);
  });

  test('test_earlier_payment_reprices_through_this_month', () {
    // IBK 나라사랑 철도 5% 할인은 1회 2천 원, 월 2회, 연 4회이고 8만 구간부터다
    // 3/20, 4/10, 4/15, 5/10 KTX 10만 원이 연 4회를 다 쓴 뒤 3/25 KTX 10만 원을 넣는다
    // 시각 순서로 이번 달까지 다시 계산하면 3/20, 3/25, 4/10, 4/15가 2천 원씩이고 5/10은 연 4회를 넘어 0원. 합계 8천 원
    // 4월 구간은 3월 실적 20만, 5월 구간은 4월 실적 20만이라 모두 8만 이상이다
    final (:s, :clock) = fresh();
    clock.now = DateTime.utc(2026, 3, 1, 3);
    final [ibk] = setup(s, [ibk300]);
    for (final d in ['2026-03-20', '2026-04-10', '2026-04-15', '2026-05-10']) {
      clock.now = DateTime.parse('${d}T03:00:00Z');
      expect(
        pay(s, ibk, 100000, 'KTX', at: '${d}T12:00:00+09:00')['value'],
        2000,
        reason: d,
      );
    }
    clock.now = DateTime.utc(2026, 5, 20, 3);
    final saved = pay(s, ibk, 100000, 'KTX', at: '2026-03-25T12:00:00+09:00');
    expect((saved['value'], saved['repriced']), (2000, 1));
    expect(
      s.db
          .select(
            'select coalesce(sum(value), 0) as v from transaction_benefits',
          )
          .single['v'],
      8000,
    );
    final may = s.db.select(
      'select coalesce(sum(b.value), 0) as v from transactions t '
      'join transaction_benefits b on b.transaction_id = t.id where t.paid_at = ?',
      [DateTime.parse('2026-05-10T12:00:00+09:00').millisecondsSinceEpoch],
    );
    expect(may.single['v'], 0);
  });

  test('test_ranking_uses_the_repriced_spend_flag', () {
    // 이마트 3만 원 3개월 무이자. LOCA 365는 무이자할부를 실적에서 빼고 ZERO는 실적 기준이 없다. 둘 다 혜택 0원
    // 일시불로 본 추천은 LOCA 365를 실적 인정으로 보지만 다시 계산하면 둘 다 실적에 들지 않아 카드 id 순으로 ZERO가 앞이다
    final (:s, clock: _) = fresh();
    final [loca, zero] = setup(s, [
      {'card_id': 'lotte-loca365', 'assumed_prev_month_spend': 600000},
      zeroCard,
    ]);
    final d = draft(s, {
      'amount': 30000,
      'merchant_name': '이마트',
      'installment_months': 3,
      'interest_free': true,
    });
    expect(ranks(d), [(zero, 0), (loca, 0)]);
  });

  test('test_unchanged_payments_are_not_rewritten', () {
    // 9/15 10시 결제를 넣으면 9월을 다시 계산하지만 9/14 결제는 값이 그대로라 다시 쓰지 않는다
    final (:s, :clock) = fresh();
    final [card] = setup(s);
    pay(s, card, 4500, '스타벅스 역삼점', at: '2026-09-14T12:00:00+09:00');
    pay(s, card, 4300, 'GS25');
    clock.now = DateTime.utc(2026, 9, 15, 13);
    expect(
      pay(s, card, 5000, 'GS25', at: '2026-09-15T10:00:00+09:00')['repriced'],
      1,
    );
    final row = s.db
        .select(
          "select updated_at from transactions where merchant_key = 'starbucks'",
        )
        .single;
    expect(
      row['updated_at'],
      DateTime.utc(2026, 9, 15, 12).millisecondsSinceEpoch,
    );
  });

  test('test_draft_shows_the_merchant_found', () {
    final (:s, clock: _) = fresh();
    setup(s);
    expect(
      draft(s, {'merchant_name': 'GS25 테헤란점'})['merchant_display'],
      'GS25',
    );
  });

  test('test_postpaid_transit_billing', () {
    // IBK 나라사랑 25만 구간 대중교통 20%는 후불교통으로 탄 시내버스, 지하철만이다. 청구 방식을 고르면 1만 원에 2,000원
    // 고르지 않으면 일반 결제라 0원이다. 사용자가 아는 값이라 결제 화면에서 고른다
    final (:s, clock: _) = fresh();
    final [ibk] = setup(s, [ibk300]);
    const subway = {'category': 'transit.subway'};
    expect(pay(s, ibk, 10000, '지하철', more: subway)['value'], 0);
    const later = '2026-09-15T21:30:00+09:00';
    expect(
      pay(
        s,
        ibk,
        10000,
        '지하철',
        at: later,
        more: {...subway, 'billing': 'postpaid_transit'},
      )['value'],
      2000,
    );
  });

  test('test_repricing_keeps_the_saved_billing', () {
    // 후불교통으로 저장한 지하철 2,000원은 앞선 결제를 넣어 9월을 다시 계산해도 저장한 청구 방식으로 계산돼 2,000원이다
    final (:s, clock: _) = fresh();
    final [ibk] = setup(s, [ibk300]);
    pay(
      s,
      ibk,
      10000,
      '지하철',
      more: {'category': 'transit.subway', 'billing': 'postpaid_transit'},
    );
    pay(s, ibk, 5000, 'GS25', at: '2026-09-15T10:00:00+09:00');
    final row = s.db
        .select(
          'select t.billing, coalesce(sum(b.value), 0) as v from transactions t '
          "left join transaction_benefits b on b.transaction_id = t.id where t.category_code = 'transit.subway' "
          'group by t.billing',
        )
        .single;
    expect((row['billing'], row['v']), ('postpaid_transit', 2000));
  });

  test('test_draft_for_an_edit_leaves_out_the_payment_being_edited', () {
    // 작업 005 슬라이스 4 위험 검토 3번. Mr.Life 편의점 10%는 하루 1회다. GS25 4,300원 430원을 1만 원으로 고치는
    // 화면의 예상 혜택은 옛 4,300원이 하루 1회를 쓴 것으로 보지 않아 1,000원이다. 남의 결제 시험은 옮기지 않는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 4300, 'GS25')['id'];
    final body = {
      'amount': 10000,
      'merchant_name': 'GS25',
      'user_card_id': card,
      'paid_at': '2026-09-15T21:00:00+09:00',
    };
    expect(draft(s, body)['estimate']['value'], 0);
    expect(draft(s, {...body, 'editing': tid})['estimate']['value'], 1000);
  });

  test('test_draft_for_an_edit_on_a_removed_card', () {
    // 위험 검토 8번. 해지한 카드의 결제를 고치는 화면도 그 카드로 예상 혜택을 낸다. 순위에는 넣지 않는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 4300, 'GS25')['id'];
    removeCard(s, card);
    final body = {
      'amount': 10000,
      'merchant_name': 'GS25',
      'user_card_id': card,
      'paid_at': '2026-09-15T21:00:00+09:00',
    };
    final d = draft(s, {...body, 'editing': tid});
    expect(d['ranking'], isEmpty);
    expect((d['pick'], d['estimate']['value']), (card, 1000));
    // 고치는 결제 id가 없으면 해지한 카드는 보유 카드가 아니다. 남은 카드가 없어 빈 결과다
    expect(draft(s, body)['estimate'], isNull);
  });

  test('test_draft_for_an_edit_matches_the_saved_value', () {
    // 3번 재검토. GS25 1만 원 가운데 6,000원을 취소하면 남은 4,000원의 10%로 400원이다. 고치는 화면의 예상 혜택도
    // 그 취소를 넣어 400원이고 저장한 값과 같다. 취소한 금액보다 작게 고치면 저장처럼 422다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final tid = pay(s, card, 10000, 'GS25')['id'] as String;
    final cancelled = cancel(s, tid, {
      'cancelled_amount': 6000,
      'cancelled_at': '2026-09-15T21:10:00+09:00',
    });
    expect(cancelled['value'], 400);
    final body = {
      'amount': 10000,
      'merchant_name': 'GS25',
      'user_card_id': card,
      'paid_at': '2026-09-15T21:00:00+09:00',
    };
    expect(draft(s, {...body, 'editing': tid})['estimate']['value'], 400);
    expect(edit(s, tid, body)['value'], 400);
    expect(
      () => draft(s, {...body, 'amount': 5000, 'editing': tid}),
      throwsA(status(422)),
    );
  });

  test('test_draft_for_an_edit_refuses_other_payments_and_cards', () {
    // 지운 결제는 고칠 수 없어 404다. 고치는 결제의 카드가 아닌 해지한 카드는 보유 카드가 아니라 404다
    final (:s, clock: _) = fresh();
    final [mr, zero] = setup(s, [mrlife, zeroCard]);
    final tid = pay(s, mr, 4300, 'GS25')['id'];
    final gone =
        pay(s, mr, 4300, 'GS25', at: '2026-09-14T21:00:00+09:00')['id']
            as String;
    delete(s, gone);
    removeCard(s, zero);
    final body = {
      'amount': 10000,
      'merchant_name': 'GS25',
      'paid_at': '2026-09-15T21:00:00+09:00',
    };
    expect(
      () => draft(s, {...body, 'user_card_id': mr, 'editing': gone}),
      throwsA(status(404)),
    );
    expect(
      () => draft(s, {...body, 'user_card_id': zero, 'editing': tid}),
      throwsA(status(404)),
    );
  });

  test('결제 입력 검사의 경계', () {
    // 2026-10-02 위험 검토. 서버에서는 Pydantic이 하던 검사를 손으로 옮겼다. 설계 4절이 정한 데이터를 지키는 검사다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final base = {
      'user_card_id': card,
      'amount': 4300,
      'merchant_name': 'GS25',
      'paid_at': '2026-09-15T21:00:00+09:00',
    };
    void bad(Json more) => expect(
      () => save(s, {...base, ...more}),
      throwsA(status(422)),
      reason: '$more',
    );
    // 시간대가 없거나 없는 날이거나 모양이 틀린 시각. 폰의 현지 시각으로 읽거나 다음 날로 넘기지 않는다
    for (final at in [
      '2026-09-15T21:00:00',
      '2026-09-31T12:00:00+09:00',
      '2026-09-15T24:00:00+09:00',
      '2026-0915',
    ]) {
      bad({'paid_at': at});
    }
    bad({'installment_months': 0});
    bad({'installment_months': 37});
    bad({'merchant_name': 'ㄱ' * 101});
    bad({'amount': 100000001});
    bad({'amount': 4300.5});
    bad({'channel': 'store'});
    bad({'region': 'mars'});
    bad({'billing': 'cash'});
    expect(s.db.select('select * from transactions'), isEmpty);
    // 경계 안쪽은 받는다
    save(s, {...base, 'installment_months': 36, 'interest_free': true});
    save(s, {
      ...base,
      'merchant_name': 'ㄱ' * 100,
      'paid_at': '2026-09-15T12:00:00Z',
    });
    save(s, {
      ...base,
      'amount': 100000000,
      'paid_at': '2026-09-15T21:30:00+0900',
    });
    expect(s.db.select('select * from transactions'), hasLength(3));
    // 취소 시각과 쓰기 시작한 날도 같다
    final tid =
        s.db.select('select id from transactions').first['id'] as String;
    expect(
      () => cancel(s, tid, {
        'cancelled_amount': 100,
        'cancelled_at': '2026-09-15T21:10:00',
      }),
      throwsA(status(422)),
    );
    expect(
      () => cardAnswers(s, card, {'started_on': '2026-02-30'}),
      throwsA(status(422)),
    );
  });

  test('다시 계산하거나 고친 결제는 그 결제일의 개정을 적는다', () {
    // 2026-10-02 위험 검토. Mr.Life에 9월 10일부터 편의점 20%인 개정을 더한다. 9월 12일 GS25 4,300원은 그 개정으로
    // 860원이다. 8월 20일 이마트 1만 원을 넣으면 9월이 0원 구간이라 9월 12일 결제가 0원으로 다시 계산되는데, 그 결제의
    // 개정은 넣은 결제의 7월 15일 개정이 아니라 자기 결제일의 9월 10일 개정이다. 9월 5일 결제를 9월 12일로 고치면
    // 고친 결제일의 개정이 된다. E18
    final (:s, clock: _) = fresh((j) {
      final c = (j['cards'] as List).firstWhere(
        (c) => c['id'] == 'shinhan-mrlife',
      );
      final revs = c['revisions'] as List;
      final next = jsonDecode(jsonEncode(revs.last)) as Json;
      next['effective_from'] = '2026-09-10';
      next['sha256'] = 'sha-of-0910';
      for (final b in next['rules']['benefits'] as List) {
        if (b['key'] == 'time-convenience') b['reward']['rate'] = 20;
      }
      revs.add(next);
    });
    final [card] = setup(s);
    String? revOf(String id) =>
        s.db.select('select revision_from from transactions where id = ?', [
              id,
            ]).single['revision_from']
            as String?;
    final sep12 = pay(s, card, 4300, 'GS25', at: '2026-09-12T21:00:00+09:00');
    expect((sep12['value'], revOf(sep12['id'])), (860, '2026-09-10'));
    final aug = pay(s, card, 10000, '이마트', at: '2026-08-20T12:00:00+09:00');
    expect(aug['repriced'], 1);
    expect(
      (revOf(aug['id']), revOf(sep12['id'])),
      ('2026-07-15', '2026-09-10'),
    );
    final sep5 =
        pay(s, card, 300000, '이마트', at: '2026-09-05T12:00:00+09:00')['id']
            as String;
    expect(revOf(sep5), '2026-07-15');
    edit(s, sep5, {
      'user_card_id': card,
      'amount': 300000,
      'merchant_name': '이마트',
      'paid_at': '2026-09-12T12:00:00+09:00',
    });
    expect(revOf(sep5), '2026-09-10');
    final sha = s.db.select(
      'select revision_sha from transactions where id = ?',
      [sep5],
    ).single;
    expect(sha['revision_sha'], 'sha-of-0910');
  });

  test('test_catalog_change_keeps_saved_benefits', () {
    // 의도 성공 기준 5, E18. 저장한 결제의 혜택은 카탈로그가 바뀌어도 그대로다. 새 결제만 바뀐 규칙을 쓴다
    final (:s, :clock) = fresh();
    final [card] = setup(s);
    expect(pay(s, card, 4300, 'GS25')['value'], 430);
    final (s: changed, clock: _) = fresh((j) {
      for (final c in j['cards'] as List) {
        if (c['id'] != 'shinhan-mrlife') continue;
        for (final r in c['revisions'] as List) {
          for (final b in r['rules']['benefits'] as List) {
            if (b['key'] == 'time-convenience') b['reward']['rate'] = 20;
          }
        }
      }
    });
    final other = Store(s.db, changed.catalog, clock: clock.call);
    expect(benefitTotal(other), 430);
    // 다음 날 GS25 4,300원은 바뀐 편의점 20%로 860원이다. 430 + 860 = 1,290원
    expect(
      pay(other, card, 4300, 'GS25', at: '2026-09-16T10:00:00+09:00')['value'],
      860,
    );
    expect(benefitTotal(other), 1290);
  });
}
