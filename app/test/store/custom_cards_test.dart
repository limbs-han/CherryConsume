// 직접 만든 카드. 작업 019 설계 1절, 설계 문서 11절, S13, S14, E65~E67
//
// 시계는 2026-09-15 21:00 한국 시간이다. 기대값은 손계산이다
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/store/backup.dart';
import 'package:cherry_consume/store/routes/catalog.dart' show cards;
import 'package:cherry_consume/store/routes/custom.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/records.dart' show cancel;
import 'package:cherry_consume/store/store.dart' show Store, inUse;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 카페 10% 할인, 월 5,000원, 30만부터
const cafe = {
  'issuer': 'shinhan',
  'name': '위시플러스',
  'kind': 'credit',
  'annual_fee': 15000,
  'tiers': [300000],
  'benefits': [
    {
      'categories': ['cafe'],
      'type': 'discount',
      'rate': 10,
      'month_cap': 5000,
      'from_tier': 300000,
    },
  ],
};

/// 모든 가맹점 0.5% 적립, 실적 무관
const everywhere = {
  'issuer': 'etc',
  'name': '동네카드',
  'kind': 'check',
  'tiers': <int>[],
  'benefits': [
    {'all': true, 'type': 'points', 'rate': 0.5},
  ],
};

int counted(Store s) =>
    ((home(s)['cards'] as List).single['spend'] as Map)['counted'] as int;

String make(Store s, Map<String, Object?> input, {int? prev}) {
  final id = createCustom(s, input)['card_id'] as String;
  expect(id, startsWith('custom-'));
  return addCard(s, id, assumedPrevMonthSpend: prev)['id'] as String;
}

void main() {
  test('S13 카페 10% 할인은 30만 구간부터 월 5,000원까지다', () {
    final (:s, clock: _) = fresh();
    final card = make(s, cafe, prev: 300000);
    // 30,000 x 10% = 3,000. 두 번째는 남은 한도 2,000
    expect(
      pay(s, card, 30000, null, more: {'category': 'cafe'})['value'],
      3000,
    );
    expect(
      pay(s, card, 30000, null, more: {'category': 'cafe'})['value'],
      2000,
    );
    // 카페가 아니면 0
    expect(
      pay(s, card, 30000, null, more: {'category': 'convenience'})['value'],
      0,
    );
  });

  test('S13 30만 구간 1원 전이면 카페도 0원이다', () {
    final (:s, clock: _) = fresh();
    final card = make(s, cafe, prev: 299999);
    expect(pay(s, card, 30000, null, more: {'category': 'cafe'})['value'], 0);
  });

  test('S13 모든 가맹점 0.5% 적립은 1포인트 1원이고 원 미만은 버린다', () {
    final (:s, clock: _) = fresh();
    final card = make(s, everywhere);
    // 15,000 x 0.5% = 75. 999 x 0.5% = 4.995 → 4
    expect(pay(s, card, 15000, 'GS25')['value'], 75);
    expect(pay(s, card, 999, 'GS25')['value'], 4);
  });

  test('E65 처음부터 만든 카드는 모든 결제가 실적이고 취소와 실적 제외는 빠진다', () {
    final (:s, clock: _) = fresh();
    final card = make(s, cafe, prev: 0);
    final paid = pay(s, card, 10000, null, more: {'category': 'cafe'});
    pay(
      s,
      card,
      20000,
      null,
      more: {'category': 'convenience', 'spend_excluded': true},
    );
    expect(counted(s), 10000);
    // 같은 달 4,000원 취소. 10,000 - 4,000 = 6,000
    cancel(s, paid['id'] as String, {
      'cancelled_amount': 4000,
      'cancelled_at': '2026-09-15T21:30:00+09:00',
    });
    expect(counted(s), 6000);
  });

  test('E65 실적 제외는 직접 만든 카드의 결제에서만 켤 수 있다', () {
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    expect(
      () => pay(s, card, 10000, 'GS25', more: {'spend_excluded': true}),
      throwsA(status(422)),
    );
  });

  test('E67 고치면 그 카드의 지난 결제를 새 규칙으로 다시 계산한다', () {
    final (:s, clock: _) = fresh();
    final card = make(s, cafe, prev: 300000);
    pay(s, card, 30000, null, more: {'category': 'cafe'});
    pay(s, card, 30000, null, more: {'category': 'cafe'});
    final id = customOf(s, card);
    // 20%면 첫 결제 6,000이 한도 5,000에 걸리고 두 번째는 0. 둘 다 바뀐다
    final out = updateCustom(s, id, {
      ...cafe,
      'benefits': [
        {
          ...(cafe['benefits'] as List).single as Map<String, Object?>,
          'rate': 20,
        },
      ],
    });
    expect(out['repriced'], 2);
    final values = [
      for (final r in s.db.select(
        'select coalesce(sum(b.value), 0) v from transactions t left join transaction_benefits b '
        'on b.transaction_id = t.id group by t.id order by t.paid_at, t.id',
      ))
        r['v'],
    ];
    expect(values, [5000, 0]);
  });

  test('직접 만든 카드는 고친 값을 그대로 돌려주고 카드 검색에는 없다', () {
    final (:s, clock: _) = fresh();
    final card = make(s, cafe, prev: 300000);
    final id = customOf(s, card);
    final back = customInput(s, id);
    expect(back['name'], '위시플러스');
    expect(back['tiers'], [300000]);
    expect((back['benefits'] as List).single['rate'], 10);
    expect([for (final c in cards(s)) c['id']], isNot(contains(id)));
  });

  test('E66 직접 만든 카드는 카탈로그를 고를 때 보유 카드 검사에서 빠진다', () {
    final (:s, clock: _) = fresh();
    make(s, cafe);
    expect(inUse(s.db).cards.where((c) => c.startsWith('custom-')), isEmpty);
  });

  test('비슷한 카드에서 시작하면 그 카드의 실적 규칙과 구간을 가져온다', () {
    final (:s, clock: _) = fresh();
    final start = startFrom(s, 'shinhan-mrlife');
    expect(start['issuer'], 'shinhan');
    expect(start['base_card_id'], 'shinhan-mrlife');
    expect(start['tiers'], isNotEmpty);
    final card = make(s, {...start, 'name': '미스터라이프 비슷한 카드'});
    final id = customOf(s, card);
    final mine = s.catalog.cards[id]!.revisions.single.rules.spend;
    final base = s.catalog.cards['shinhan-mrlife']!.revisions.last.rules.spend;
    expect(
      (mine.cancellation, mine.installment, mine.excludeCategories.join(',')),
      (base.cancellation, base.installment, base.excludeCategories.join(',')),
    );
  });

  test('직접 만든 카드와 실적 제외가 기록 내보내기와 가져오기를 거쳐 그대로 돌아온다', () {
    // 작업 019 설계 4절, 성공 기준 8
    final (:s, clock: _) = fresh();
    final card = make(s, cafe, prev: 300000);
    pay(s, card, 30000, null, more: {'category': 'cafe'});
    pay(
      s,
      card,
      20000,
      null,
      more: {'category': 'convenience', 'spend_excluded': true},
    );
    final file = exportAll(s);
    final (s: t, clock: _) = fresh();
    importAll(t, Uint8List.fromList(utf8.encode(file)));
    expect(jsonEncode(home(t)), jsonEncode(home(s)));
    expect(counted(t), 30000);
    final id = customOf(t, card);
    expect(customInput(t, id)['name'], '위시플러스');
    // 가져온 뒤 새 결제도 직접 만든 카드 규칙으로 계산한다. 한도 5,000 - 3,000 = 2,000
    expect(
      pay(t, card, 30000, null, more: {'category': 'cafe'})['value'],
      2000,
    );
  });
}
