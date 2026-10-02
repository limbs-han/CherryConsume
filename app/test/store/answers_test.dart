// 모르는 값 묻기. 카드 사실, 옵션, 쓰기 시작한 날, 사람 사실. Python `backend/tests/api/test_answers.py`를 옮겼다. E56
//
// 시계는 2026-09-15 21:00 한국 시간이다. 처음 답은 그 카드의 모든 결제에, 바꾼 답은 바뀌는 날부터 쓴다.
// 2026-10-02 사용자가 정했다
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/routes/answers.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/records.dart';
import 'package:cherry_consume/store/routes/recommend.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const taptap = {
  'card_id': 'samsung-taptap-o',
  'assumed_prev_month_spend': 300000,
};
const nara = {'card_id': 'ibk-narasarang'};

Json answer(Store s, String uid, Json body) => cardAnswers(s, uid, body);

List<Json> recordsOf(Store s, [String month = '2026-09']) => [
  for (final x in records(s, month: month)['payments'] as List) x as Json,
];

List<Json> optionsOf(Store s, String uid) => [
  for (final o in cardDetail(s, uid)['questions']['options'] as List) o as Json,
];

void main() {
  test('test_first_option_answer_reprices_and_a_change_waits', () {
    // 삼성 taptap O를 지난달 30만 원으로 등록해 30만 구간이다. 패키지를 모르면 9월 10일 스타벅스 1만 원은 0원이다.
    // 처음 p1이라고 답하면 패키지 1~3의 스타벅스 50%로 5,000원이다. p4로 바꾸면 이 옵션은 다음 달부터라 9월은
    // 그대로 5,000원이고 카드 상세에 10월부터 p4가 보인다
    final (:s, clock: _) = fresh();
    final [tap] = setup(s, [taptap]);
    final tid = pay(
      s,
      tap,
      10000,
      '스타벅스',
      at: '2026-09-10T12:00:00+09:00',
    )['id'];
    expect(recordsOf(s).first['value'], 0);
    expect(
      answer(s, tap, {
        'options': {'package': 'p1'},
      })['repriced'],
      1,
    );
    expect(
      [for (final r in recordsOf(s)) (r['id'], r['value'])],
      [(tid, 5000)],
    );
    expect(
      answer(s, tap, {
        'options': {'package': 'p4'},
      })['repriced'],
      0,
    );
    expect(recordsOf(s).first['value'], 5000);
    final [package] = optionsOf(s, tap);
    expect(package['answer'], 'p1');
    expect(package['pending'], {'value': 'p4', 'from': '2026-10-01'});
    // 같은 답을 다시 하면 아무것도 하지 않는다
    expect(
      answer(s, tap, {
        'options': {'package': 'p4'},
      })['repriced'],
      0,
    );
  });

  test('test_card_fact_change_applies_from_this_month', () {
    // IBK 나라사랑 철도 5%는 8만 구간부터인데 병 급여이체를 받으면 실적이 면제된다. 추정값 없이 등록해 8월과 9월이 0원
    // 구간이라 KTX 2만 원은 0원이다. 처음 급여이체를 받았다고 답하면 두 달 모두 1,000원이다. 9월에 받지 않았다로 바꾸면
    // 한국 시간 이번 달 1일부터라 8월 31일 23시 59분은 1,000원 그대로이고 9월 1일 0시는 0원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [nara]);
    pay(s, card, 20000, 'KTX', at: '2026-08-31T23:59:00+09:00');
    pay(s, card, 20000, 'KTX', at: '2026-09-01T00:00:00+09:00');
    List<Object?> values() => [
      for (final m in ['2026-08', '2026-09']) recordsOf(s, m).first['value'],
    ];
    expect(values(), [0, 0]);
    expect(
      answer(s, card, {
        'facts': {'salary_transfer': true},
      })['repriced'],
      2,
    );
    expect(values(), [1000, 1000]);
    expect(
      answer(s, card, {
        'facts': {'salary_transfer': false},
      })['repriced'],
      1,
    );
    expect(values(), [1000, 0]);
    // 이번 달에 바꾼 답을 다시 받았다로 되돌리면 이번 달 답을 지운다
    expect(
      answer(s, card, {
        'facts': {'salary_transfer': true},
      })['repriced'],
      1,
    );
    expect(values(), [1000, 1000]);
    final facts = {
      for (final q in cardDetail(s, card)['questions']['facts'] as List)
        q['key']: q,
    };
    expect(facts['salary_transfer']['answer'], isTrue);
    // 사람 사실인 현역병 여부는 카드 정보에 없다. 설정에서 묻는다
    expect(facts.containsKey('soldier'), isFalse);
  });

  test('test_started_on_answer_reprices_every_payment', () {
    // taptap O를 추정값 없이 등록하면 0원 구간이라 9월 10일 CGV 1만 원은 0원이다. 쓰기 시작한 날을 9월 1일로 답하면
    // 신규 발급 특례로 영화에 30만 구간을 줘 5,000원이다
    final (:s, clock: _) = fresh();
    final [tap] = setup(s, [
      {'card_id': 'samsung-taptap-o'},
    ]);
    pay(s, tap, 10000, 'CGV', at: '2026-09-10T12:00:00+09:00');
    expect(answer(s, tap, {'started_on': '2026-09-01'})['repriced'], 1);
    expect(recordsOf(s).first['value'], 5000);
    expect(cardDetail(s, tap)['started_on'], '2026-09-01');
  });

  test('test_bad_answers', () {
    // 모르는 칸과 남의 카드 시험은 옮기지 않는다. 설계 4절
    final (:s, clock: _) = fresh();
    final [tap, card] = setup(s, [taptap, nara]);
    for (final body in <Json>[
      {
        'options': {'package': 'p9'},
      },
      {
        'options': {'nothing': 'p1'},
      },
      {
        'facts': {'salary_transfer': true},
      },
      {'started_on': '2026-12-01'},
    ]) {
      expect(() => answer(s, tap, body), throwsA(status(422)), reason: '$body');
    }
    // 종류가 bool이면 참과 거짓만 받는다. 사람 사실은 카드 답으로 받지 않는다
    expect(
      () => answer(s, card, {
        'facts': {'salary_transfer': 'yes'},
      }),
      throwsA(status(422)),
    );
    expect(
      () => answer(s, card, {
        'facts': {'soldier': true},
      }),
      throwsA(status(422)),
    );
  });

  test('test_user_fact_reprices_every_card_that_uses_it', () {
    // 사람 사실 현역병 여부. IBK 나라사랑 PX 3만 원 미만 15%는 현역병이거나 급여이체를 받아야 한다. 9월 10일 PX 2만 원은
    // 둘 다 몰라 0원이다. 설정에서 현역병이라고 답하면 15%로 3,000원이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [nara]);
    pay(s, card, 20000, 'PX', at: '2026-09-10T12:00:00+09:00');
    final [soldier] = userFacts(s);
    expect(
      (soldier['key'], soldier['type'], soldier['answer']),
      ('soldier', 'bool', null),
    );
    expect(soldier['cards'], ['IBK나라사랑카드']);
    expect(
      putUserFacts(s, {
        'facts': {'soldier': true},
      }),
      {'repriced': 1},
    );
    expect(recordsOf(s).first['value'], 3000);
    expect(userFacts(s).first['answer'], isTrue);
    // 카드 사실은 설정에서 받지 않는다. 종류가 틀린 답도 422다
    for (final facts in <Json>[
      {'salary_transfer': true},
      {'soldier': 'yes'},
    ]) {
      expect(() => putUserFacts(s, {'facts': facts}), throwsA(status(422)));
    }
    // 묻는 카드가 없으면 목록이 비고 답도 받지 않는다
    final (s: other, clock: _) = fresh();
    setup(other, [taptap]);
    expect(userFacts(other), isEmpty);
    expect(
      () => putUserFacts(other, {
        'facts': {'soldier': true},
      }),
      throwsA(status(422)),
    );
  });

  test('test_ask_child_category_after_saving', () {
    // E47. IBK 나라사랑을 지난달 20만 원으로 등록해 20만 구간이다. 이동통신 자동납부 5%는 업종이 이동통신이어야 하는데
    // "KT 요금"은 통신요금까지만 알아 0원이고 자식 업종을 묻는다. 이동통신이라고 고치면 5만 원의 5% 2,500원이 월
    // 2천 원 한도에 걸려 2,000원이고 더 묻지 않는다
    final (:s, clock: _) = fresh();
    final [card] = setup(s, [
      {'card_id': 'ibk-narasarang', 'assumed_prev_month_spend': 200000},
    ]);
    final saved = pay(s, card, 50000, 'KT 요금');
    expect(saved['value'], 0);
    final ask = saved['ask_category'] as Json;
    expect((ask['parent'], ask['parent_name']), ('telecom', '통신요금'));
    expect(
      [for (final c in ask['children'] as List) c['code']],
      ['telecom.internet_tv', 'telecom.mobile'],
    );
    final edited = edit(s, saved['id'], {
      'user_card_id': card,
      'amount': 50000,
      'merchant_name': 'KT 요금',
      'paid_at': '2026-09-15T21:00:00+09:00',
      'category': 'telecom.mobile',
    });
    expect((edited['value'], edited['ask_category']), (2000, null));
  });

  test('test_option_default_reservation_and_immediate_change', () {
    // 재검토 중간 2번. 하나 원더 조합은 기본값이 DAILY라 처음 DAILY라고 답해도 계산이 같아 다시 계산하지 않는다.
    // 오늘부터 바뀌는 옵션이라 custom으로 바꾸면 예약 없이 바로 답이 된다. taptap O는 p1을 쓰는 중에 p4를 예약했다가
    // p1을 다시 누르면 예약만 지운다. 낮음 9번
    final (:s, clock: _) = fresh();
    final [wonder, tap] = setup(s, [
      {'card_id': 'hana-wonder2-daily'},
      taptap,
    ]);
    pay(s, wonder, 10000, '스타벅스', at: '2026-09-10T12:00:00+09:00');
    expect(
      answer(s, wonder, {
        'options': {'combo': 'daily'},
      })['repriced'],
      0,
    );
    var [combo] = optionsOf(s, wonder);
    expect((combo['answer'], combo['pending']), ('daily', null));
    answer(s, wonder, {
      'options': {'combo': 'custom'},
    });
    [combo] = optionsOf(s, wonder);
    expect((combo['answer'], combo['pending']), ('custom', null));
    for (final p in ['p1', 'p4', 'p1']) {
      answer(s, tap, {
        'options': {'package': p},
      });
    }
    final [package] = optionsOf(s, tap);
    expect((package['answer'], package['pending']), ('p1', null));
  });

  test('test_birth_month', () {
    // 재검토 중간 4번. KB My WE:SH 먹는데 진심은 배달앱 5%, 월 5천 원까지다. 생일 달이고 쓰기 시작한 지 한 달이 지났으면
    // 한도가 2배다. 지난달 40만 원으로 등록하고 8월 1일부터 썼다. 9월 10일 배민 20만 원은 5%로 1만 원이라 한도 5천 원이다.
    // 생일이 9월이라고 답하면 한도 1만 원이라 1만 원이다. 달은 1~12의 정수만 받는다
    final (:s, clock: _) = fresh();
    final [wesh] = setup(s, [
      {
        'card_id': 'kb-my-wesh',
        'assumed_prev_month_spend': 400000,
        'started_on': '2026-08-01',
      },
    ]);
    pay(s, wesh, 200000, '배민', at: '2026-09-10T12:00:00+09:00');
    answer(s, wesh, {
      'options': {'pack': 'eat'},
    });
    expect(recordsOf(s).first['value'], 5000);
    for (final wrong in <Object>[true, 13, '9']) {
      expect(
        () => putUserFacts(s, {
          'facts': {'birth_month': wrong},
        }),
        throwsA(status(422)),
        reason: '$wrong',
      );
    }
    expect(
      putUserFacts(s, {
        'facts': {'birth_month': 9},
      }),
      {'repriced': 1},
    );
    expect(recordsOf(s).first['value'], 10000);
  });

  test('test_user_fact_reprices_a_removed_card', () {
    // 재검토 중간 3번. 사람 사실은 그 사실을 쓰는 카드를 모두 다시 계산한다. IBK를 해지했다가 다시 등록한 사람이 현역병이라고
    // 답하면 해지한 옛 카드의 9월 10일 PX 2만 원도 3,000원이다
    final (:s, clock: _) = fresh();
    final [old] = setup(s, [nara]);
    pay(s, old, 20000, 'PX', at: '2026-09-10T12:00:00+09:00');
    removeCard(s, old);
    expect(userFacts(s), isEmpty);
    setup(s, [nara]);
    expect(
      putUserFacts(s, {
        'facts': {'soldier': true},
      }),
      {'repriced': 1},
    );
    expect(recordsOf(s).first['value'], 3000);
  });

  test('test_recommendation_shows_what_an_answer_would_add', () {
    // 설계 5c의 미뤄 둔 것. taptap O 30만 구간에서 스타벅스 1만 원은 패키지를 몰라 0원이다. 패키지 1~3이면 50%로 5,000원,
    // 4~6이면 커피 30%로 3,000원이라 가장 큰 p1의 5,000원을 묻는다. IBK PX 2만 원은 현역병이나 급여이체면 3,000원이다
    final (:s, clock: _) = fresh();
    final [tap, card] = setup(s, [taptap, nara]);
    Map<Object?, List<String>> asks(String merchant, int amount) => {
      for (final r
          in recommend(s, {
                'merchant_name': merchant,
                'amount': amount,
              })['ranking']
              as List)
        r['user_card_id']: [
          for (final a in r['ask'] as List)
            '${a['kind']} ${a['key']} ${a['choice']} ${a['extra']}',
        ],
    };
    expect(asks('스타벅스', 10000)[tap], ['option package p1 5000']);
    expect(asks('PX', 20000)[card]!..sort(), [
      'fact salary_transfer null 3000',
      'fact soldier null 3000',
    ]);
  });
}
