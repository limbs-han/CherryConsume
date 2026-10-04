// 카드 검색, 등록 미리보기, 카드 등록과 홈. Python `backend/tests/api/test_cards.py`를 옮겼다. 작업 006 계획 단계 4의 2
//
// 신한카드 Mr.Life 2026-07-15 개정의 구간은 0, 30만, 50만, 100만이다. 새 카드 특례 구간은 30만이다.
// 시계는 2026-09-15 21:00 한국 시간이다. 로그인, 모르는 칸 막기, 사용자마다 나누기 시험은 옮기지 않는다. 설계 4절
import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/routes/catalog.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/records.dart' show delete;
import 'package:cherry_consume/store/store.dart' show inUse;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

List<String> names(List<Json> rows) => [for (final r in rows) r['name']];

Matcher status(int code) =>
    isA<ApiError>().having((e) => e.status, 'status', code);

void main() {
  test('test_search_by_name_and_alias', () {
    final (:s, clock: _) = fresh();
    expect(names(cards(s, q: 'mr')), contains('신한카드 Mr.Life'));
    expect(names(cards(s, q: '미스터 라이프')), ['신한카드 Mr.Life']);
  });

  test('test_search_by_issuer', () {
    final (:s, clock: _) = fresh();
    final rows = cards(s, issuer: 'shinhan');
    expect({for (final r in rows) r['issuer']}, {'shinhan'});
    expect(rows, hasLength(3));
  });

  test('test_search_row', () {
    // 연회비는 국내 전용 15,000원과 해외 겸용 18,000원 중 국내 전용
    final (:s, clock: _) = fresh();
    expect(cards(s, q: 'mr.life').first, {
      'id': 'shinhan-mrlife',
      'name': '신한카드 Mr.Life',
      'issuer': 'shinhan',
      'issuer_name': '신한카드',
      'kind': 'credit',
      'annual_fee': 15000,
      'tiers': [300000, 500000, 1000000],
    });
  });

  test('test_discontinued_card_is_hidden', () {
    // E19
    final (:s, clock: _) = fresh((j) {
      for (final c in j['cards'] as List) {
        if (c['id'] == 'shinhan-mrlife') c['status'] = 'discontinued';
      }
    });
    expect(names(cards(s)), isNot(contains('신한카드 Mr.Life')));
    expect(() => preview(s, 'shinhan-mrlife'), throwsA(status(404)));
  });

  test('test_issuer_chips', () {
    final (:s, clock: _) = fresh();
    final chips = issuers(s);
    expect(chips, hasLength(10));
    // 카드사 칩은 짧은 이름이다. 작업 011 설계 2.4
    expect(chips, contains(equals({'code': 'shinhan', 'name': '신한'})));
  });

  test('test_preview_with_last_month', () {
    // 지난달 41만은 30만 이상 50만 미만이라 30만 구간. 그 구간에서 받는 혜택은 30만부터인 10개 모두
    final (:s, clock: _) = fresh();
    final r = preview(s, 'shinhan-mrlife', prev: 410000);
    expect((r['tier'], r['tier_source']), (300000, 'assumed'));
    // 카드 안내 경고는 늘 붙는다. 조건을 문장으로만 담은 혜택과 공식 문구로 확인하지 못한 값이 있다
    expect(r['warnings'], ['check_conditions', 'assumed_value']);
    expect(r['tiers'], [300000, 500000, 1000000]);
    expect(r['benefits'], hasLength(10));
    expect(r['benefits'], contains('편의점 10% 할인'));
  });

  test('test_preview_without_last_month', () {
    // E1. 비우면 최저 구간 0원과 no_prev_month_data. 0원 구간에서 받는 혜택은 없다
    final (:s, clock: _) = fresh();
    final r = preview(s, 'shinhan-mrlife');
    expect(
      (r['tier'], (r['warnings'] as List).first),
      (0, 'no_prev_month_data'),
    );
    expect(r['benefits'], isEmpty);
  });

  test('test_preview_new_card', () {
    // 이번 달에 받은 새 카드는 실적이 없어도 특례 30만 구간이다
    final (:s, clock: _) = fresh();
    final r = preview(s, 'shinhan-mrlife', startedOn: day(2026, 9, 1));
    expect((r['tier'], r['tier_source']), (300000, 'new_card'));
  });

  test('test_preview_new_card_skips_package_benefits', () {
    // 삼성카드 taptap O는 새 카드 특례 30만 구간이지만 패키지 혜택 6개는 특례 구간이 0원이라 받지 못한다
    // 패키지 혜택은 옵션을 골라야 받는다. 고르지 않은 패키지끼리는 서로 배타라 목록에 넣지 않는다
    final (:s, clock: _) = fresh();
    final r = preview(s, 'samsung-taptap-o', startedOn: day(2026, 9, 1));
    expect((r['tier'], r['tier_source']), (300000, 'new_card'));
    expect(r['benefits'], contains('대중교통 10% 할인'));
    expect([
      for (final b in r['benefits'] as List)
        if ((b as String).startsWith('[패키지')) b,
    ], isEmpty);
  });

  test('test_preview_uses_the_default_option', () {
    // 하나 원더2 DAILY는 조합 옵션의 기본값이 daily라 고르지 않아도 그 조합 혜택을 받는다. 엔진과 같다
    final (:s, clock: _) = fresh();
    final r = preview(s, 'hana-wonder2-daily', prev: 410000);
    expect(r['tier'], 400000);
    expect(r['benefits'], contains('배달앱 10% 할인'));
  });

  test('test_preview_spend_upper_bound', () {
    final (:s, clock: _) = fresh();
    expect(
      () => preview(s, 'shinhan-mrlife', prev: 100000001),
      throwsA(status(422)),
    );
  });

  test('test_add_card_and_home', () {
    final (:s, clock: _) = fresh();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    final h = home(s);
    expect((h['month'], h['benefit_total']), ('2026-09-01', 0));
    final [card as Json] = h['cards'] as List;
    expect(
      (card['card_id'], card['name'], card['issuer_name']),
      // 홈의 카드 이름은 짧은 이름이다. 작업 011 설계 2.4
      ('shinhan-mrlife', '신한 Mr.Life', '신한카드'),
    );
    expect(card['tiers'], [300000, 500000, 1000000]);
    // 이번 달 실적 0원. 30만 구간을 지키려면 30만, 다음 50만 구간까지 50만
    final spend = card['spend'] as Json;
    final warnings = spend['warnings'] as List;
    expect(spend, {
      'counted': 0,
      'tier': 300000,
      'tier_source': 'assumed',
      'prev_month_counted': 410000,
      'to_keep': 300000,
      'next_tier': 500000,
      'to_next': 500000,
      'warnings': [
        {
          'code': 'check_conditions',
          'benefit': null,
          'data': warnings[0]['data'],
        },
        {'code': 'assumed_value', 'benefit': null, 'data': warnings[1]['data']},
      ],
    });
  });

  test('test_home_after_month_change', () {
    // S6, E7. 9월 30일 15:30 UTC는 한국 시간 10월 1일 00:30이다. 등록한 달이 지나 추정값을 쓰지 않는다
    final (:s, :clock) = fresh();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    clock.now = DateTime.utc(2026, 9, 30, 15, 30);
    final h = home(s);
    expect(h['month'], '2026-10-01');
    final spend = (h['cards'] as List).first['spend'] as Json;
    expect(
      (spend['tier'], spend['tier_source'], spend['to_keep'], spend['to_next']),
      (0, 'prev_month', null, 300000),
    );
  });

  test('test_home_just_before_month_change', () {
    // 9월 30일 14:59:59 UTC는 한국 시간 9월 30일 23:59:59라 아직 9월이다
    final (:s, :clock) = fresh();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    clock.now = DateTime.utc(2026, 9, 30, 14, 59, 59);
    final h = home(s);
    expect(
      (h['month'], (h['cards'] as List).first['spend']['tier']),
      ('2026-09-01', 300000),
    );
  });

  test('test_card_without_tiers', () {
    // 현대 ZERO Edition3 할인형은 구간이 0원 하나라 실적 무관이다
    final (:s, clock: _) = fresh();
    addCard(s, 'hyundai-zero-edition3-discount');
    final card = (home(s)['cards'] as List).first as Json;
    expect(card['tiers'], isEmpty);
    expect(card['headline'], '국내외 가맹점 0.8% 할인');
    expect(
      (card['spend']['to_keep'], card['spend']['next_tier']),
      (null, null),
    );
  });

  test('test_same_card_again_is_409', () {
    final (:s, clock: _) = fresh();
    addCard(s, 'shinhan-mrlife');
    expect(() => addCard(s, 'shinhan-mrlife'), throwsA(status(409)));
  });

  test('test_unknown_card_is_404', () {
    final (:s, clock: _) = fresh();
    expect(() => addCard(s, 'nope-card'), throwsA(status(404)));
  });

  test('카탈로그가 빠뜨리면 안 되는 것에 해지한 카드와 지운 결제도 든다', () {
    // 작업 006 단계 4 위험 검토. 해지한 카드 이름을 기록이 읽고, 지운 결제도 되돌리면 다시 계산한다. 카드의 마지막
    // 결제수단은 다음 결제의 기본값이라 결제에 없어도 든다
    final (:s, clock: _) = fresh();
    final mr = addCard(s, 'shinhan-mrlife')['id'] as String;
    final ibk = addCard(s, 'ibk-narasarang')['id'] as String;
    pay(s, mr, 4300, 'GS25');
    final cafe = pay(
      s,
      ibk,
      10000,
      '스타벅스 역삼점',
      more: {'payment_method': 'naver_pay'},
    );
    delete(s, cafe['id'] as String);
    removeCard(s, mr);
    s.db.execute(
      "update user_cards set last_payment_method = 'kakao_pay' where id = ?",
      [ibk],
    );
    final used = inUse(s.db);
    expect(used.cards, {'shinhan-mrlife', 'ibk-narasarang'});
    expect(used.merchants, {'gs25', 'starbucks'});
    expect(used.categories, {'convenience', 'cafe'});
    expect(used.methods, {'physical_card', 'naver_pay', 'kakao_pay'});
  });
}
