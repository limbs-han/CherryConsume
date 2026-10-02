// 조건 판정. 참, 거짓, 모름. Python `backend/tests/engine/test_cond.py`를 옮겼다. 엔진 설계 2.1, 3.1, 3.2
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/cond.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:flutter_test/flutter_test.dart' hide allOf, anyOf;

import 'helpers.dart';

Situation sit({
  DateTime? at_,
  int amount = 10000,
  String? paymentMethod = 'physical_card',
  int installmentMonths = 1,
  UserCard card = const UserCard(id: 'u', cardId: 'c'),
  Map<String, String?>? defaults,
  bool timeKnown = true,
}) => Situation(
  at: at_ ?? at('2026-09-19T14:20'),
  amount: amount,
  merchant: null,
  category: 'cafe',
  channel: 'offline',
  region: 'domestic',
  installmentMonths: installmentMonths,
  interestFree: false,
  paymentMethod: paymentMethod,
  billing: 'normal',
  card: card,
  defaults: defaults,
  holidays: realCatalog.holidays,
  timeKnown: timeKnown,
);

Condition cond(Json j) => Condition.fromJson(j);

/// 판정 값만
bool? v(Tri t) => t.$1;

/// 모름이고 모르는 것이 needs다. Dart 기록은 집합을 값으로 비교하지 않아 따로 본다
void isUnknown(Tri t, List<List<String>> needs) {
  expect(t.$1, isNull);
  expect(t.$2, {for (final n in needs) need(n)});
}

void main() {
  test('test_category_tree', () {
    expect(v(categoryMatch('transit.subway', 'transit')), true);
    expect(v(categoryMatch('transit.subway', 'transit.subway')), true);
    expect(v(categoryMatch('transit.subway', 'transit.bus_express')), false);
    isUnknown(categoryMatch('transit', 'transit.subway'), [
      ['category', 'transit'],
    ]);
    expect(v(categoryMatch(null, 'cafe')), false);
  });

  test('test_three_valued_and_or', () {
    final u = unknown(['fact', 'soldier']);
    expect(allOf([yes, u]).$2, u.$2);
    expect(v(allOf([yes, u])), null);
    expect(v(allOf([u, no])), false);
    expect(v(allOf([])), true);
    expect(v(anyOf([no, u])), null);
    expect(anyOf([no, u]).$2, u.$2);
    expect(v(anyOf([u, yes])), true);
    expect(v(anyOf([])), false);
  });

  test('test_amount_range', () {
    final c = cond({
      'amount': {'min': 30000, 'below': 70000},
    });
    expect(
      [
        for (final a in [29999, 30000, 69999, 70000])
          v(check(c, sit(amount: a))),
      ],
      [false, true, true, false],
    );
  });

  test('test_holidays_include_substitute_and_election', () {
    final h = realCatalog.holidays;
    expect(isHoliday(day(2026, 10, 5), h), isTrue); // 개천절 대체공휴일
    expect(isHoliday(day(2026, 6, 3), h), isTrue); // 지방선거일
    expect(isHoliday(day(2026, 10, 6), h), isFalse);
  });

  test('카탈로그 공휴일 목록 밖의 해는 모름이다', () {
    // 작업 006 설계 2절. 목록은 2020~2036년이다. 2037년 1월 1일 금요일을 공휴일이 아니라고 짐작하지 않는다.
    // 요일만으로 정해지는 경우는 모름이 아니다
    final h = realCatalog.holidays;
    expect(isHoliday(day(2037, 1, 1), h), isNull);
    final fri = at('2037-01-02T12:00');
    Tri on(String holidays, List<String> days) => check(
      cond({
        'day': {'in': days, 'holidays': holidays},
      }),
      sit(at_: fri),
    );
    isUnknown(on('only', []), [
      ['holiday'],
    ]);
    isUnknown(on('include', ['sat']), [
      ['holiday'],
    ]);
    isUnknown(on('exclude', ['fri']), [
      ['holiday'],
    ]);
    expect(v(on('include', ['fri'])), true);
    expect(v(on('exclude', ['sat'])), false);
    expect(v(on('ignore', ['fri'])), true);
  });

  test('test_time_uses_korean_time', () {
    final c = cond({
      'time': {'from': '21:00', 'to': '09:00'},
    });
    final utc1330 = DateTime.utc(2026, 9, 19, 13, 30); // 한국 시간 22:30
    expect(v(check(c, sit(at_: utc1330))), true);
  });

  test('test_payment_unknown_and_known', () {
    final c = cond({
      'payment': ['naver_pay'],
    });
    expect(check(c, sit(paymentMethod: null)).$2, {
      need(['payment_method']),
    });
    expect(v(check(c, sit(paymentMethod: null))), null);
    expect(v(check(c, sit(paymentMethod: 'naver_pay'))), true);
    final not = cond({
      'payment_not': ['naver_pay'],
    });
    expect(check(not, sit(paymentMethod: null)).$2, {
      need(['payment_method']),
    });
  });

  test('test_option_choice_by_date_and_default', () {
    final picks = [
      OptionPick(option: 'pkg', choice: 'p1', effectiveFrom: day(2026, 9, 1)),
      OptionPick(option: 'pkg', choice: 'p2', effectiveFrom: day(2026, 10, 1)),
    ];
    final card = UserCard(id: 'u', cardId: 'c', options: picks);
    final c = cond({
      'option': {
        'pkg': ['p2'],
      },
    });
    expect(v(check(c, sit(card: card))), false);
    expect(v(check(c, sit(card: card, at_: at('2026-10-01T00:00')))), true);
    expect(check(c, sit()).$2, {
      need(['option', 'pkg']),
    });
    expect(v(check(c, sit(defaults: {'pkg': 'p2'}))), true);
  });

  test('test_fact_picks_follow_the_payment_day', () {
    // 작업 005 슬라이스 5. 처음 답은 0001-01-01부터, 바꾼 답은 바꾼 날부터다. 9월 결제는 처음 답 참, 10월 결제는 바꾼 답
    // 거짓이다. 답이 없는 날이면 facts를 보고, 그것도 없으면 모른다
    final picks = [
      FactPick(key: 'salary', value: true, effectiveFrom: firstDay),
      FactPick(key: 'salary', value: false, effectiveFrom: day(2026, 10, 1)),
    ];
    final card = UserCard(
      id: 'u',
      cardId: 'c',
      factPicks: picks,
      facts: const {'soldier': true},
    );
    expect(v(check(cond({'fact': 'salary'}), sit(card: card))), true);
    expect(
      v(
        check(
          cond({'fact': 'salary'}),
          sit(card: card, at_: at('2026-10-01T00:00')),
        ),
      ),
      false,
    );
    expect(v(check(cond({'fact': 'soldier'}), sit(card: card))), true);
    final late = UserCard(
      id: 'u',
      cardId: 'c',
      factPicks: [
        FactPick(key: 'salary', value: true, effectiveFrom: day(2026, 10, 1)),
      ],
    );
    expect(check(cond({'fact': 'salary'}), sit(card: late)).$2, {
      need(['fact', 'salary']),
    });
    final month = [
      FactPick(key: 'birth_month', value: 9, effectiveFrom: firstDay),
    ];
    expect(
      v(
        check(
          cond({'fact': 'birth_month_now'}),
          sit(
            card: UserCard(id: 'u', cardId: 'c', factPicks: month),
          ),
        ),
      ),
      true,
    );
  });

  test('test_unknown_time_makes_time_conditions_unknown', () {
    // E57. 시각을 모르는 결제는 시각 조건이 모름이다. 날짜로 정해지는 달 조건은 그대로다
    final night = cond({
      'time': {'from': '21:00', 'to': '09:00'},
    });
    expect(v(check(night, sit(at_: at('2026-09-19T22:00')))), true);
    isUnknown(
      check(night, sit(at_: at('2026-09-19T22:00'), timeKnown: false)),
      [
        ['time'],
      ],
    );
    expect(
      v(
        check(
          cond({
            'months': [9],
          }),
          sit(timeKnown: false),
        ),
      ),
      true,
    );
  });

  test('test_facts_and_birth_month', () {
    expect(check(cond({'fact': 'soldier'}), sit()).$2, {
      need(['fact', 'soldier']),
    });
    const card = UserCard(
      id: 'u',
      cardId: 'c',
      facts: {'soldier': false, 'birth_month': 9},
    );
    expect(v(check(cond({'fact': 'soldier'}), sit(card: card))), false);
    expect(v(check(cond({'fact': 'birth_month_now'}), sit(card: card))), true);
  });

  test('test_card_month_and_lump_sum', () {
    final card = UserCard(id: 'u', cardId: 'c', startedOn: day(2026, 8, 20));
    // 8월이 0, 9월이 1
    expect(
      v(
        check(
          cond({
            'card_month': {'min': 1},
          }),
          sit(card: card),
        ),
      ),
      true,
    );
    expect(
      check(
        cond({
          'card_month': {'min': 1},
        }),
        sit(),
      ).$2,
      {
        need(['started_on']),
      },
    );
    expect(
      v(check(cond({'lump_sum': true}), sit(installmentMonths: 3))),
      false,
    );
  });

  test('test_any_of_unknown_only_when_nothing_true', () {
    final c = cond({
      'any_of': [
        {'fact': 'soldier'},
        {'fact': 'salary'},
      ],
    });
    const card = UserCard(id: 'u', cardId: 'c', facts: {'salary': true});
    expect(v(check(c, sit(card: card))), true);
    expect(v(check(c, sit())), null);
    expect(check(c, sit()).$2, {
      need(['fact', 'soldier']),
      need(['fact', 'salary']),
    });
  });
}
