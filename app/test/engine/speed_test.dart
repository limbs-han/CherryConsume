// 추천 속도. Python `backend/tests/engine/test_speed.py`를 옮겼다. 엔진 설계 4.4와 6.5
//
// 카드 10장, 이번 달 결제 300건, 조건부 혜택 포함으로 추천 한 번 50ms, 업종 12개의 업종별 1순위 200ms 안이다.
// 컴퓨터마다 속도가 달라 여러 번 재서 가운데 값을 쓴다. 결제 10건에 1건은 반을 취소한다. 기준은 PC다
import 'dart:math';

import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

final now = at('2026-09-28T19:30');
const categories = [
  'cafe',
  'convenience',
  'restaurant',
  'online_shopping',
  'transit.subway',
  'delivery_app',
  'grocery_mart',
  'fuel',
  'movie',
  'telecom.mobile',
  'hospital',
  'other',
];

double medianMs(void Function() fn, [int runs = 7]) {
  fn();
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    final w = Stopwatch()..start();
    fn();
    times.add(w.elapsedMicroseconds / 1000);
  }
  times.sort();
  return times[runs ~/ 2];
}

void main() {
  late Engine eng;
  late List<UserCard> cards;
  final payments = <String, List<Payment>>{};

  setUpAll(() {
    final cat = realCatalog;
    eng = Engine(cat);
    final ids = cat.cards.keys.toList()
      ..sort(
        (a, b) => cat.cards[b]!.revisions.last.rules.benefits.length.compareTo(
          cat.cards[a]!.revisions.last.rules.benefits.length,
        ),
      );
    final rng = Random(20260928);
    final merchants = cat.merchants.keys.toList()..sort();
    cards = [
      for (final (i, cid) in ids.take(10).indexed)
        UserCard(
          id: 'u$i',
          cardId: cid,
          registeredOn: DateTime.utc(2026, 1, 1),
        ),
    ];
    const amounts = [4500, 12000, 35000, 58000, 120000];
    const methods = ['physical_card', 'naver_pay', 'kakao_pay'];
    for (var n = 0; n < 300; n++) {
      final c = cards[n % 10];
      final when = at(
        '2026-09-01T08:00',
      ).add(Duration(minutes: rng.nextInt(27 * 24 * 60)));
      final amount = amounts[rng.nextInt(amounts.length)];
      final p = Payment(
        id: 'x${n.toString().padLeft(3, '0')}',
        userCardId: c.id,
        amount: amount,
        paidAt: when,
        merchant: merchants[rng.nextInt(merchants.length)],
        channel: rng.nextBool() ? 'online' : 'offline',
        paymentMethod: methods[rng.nextInt(methods.length)],
        cancelledAmount: n % 10 == 0 ? amount ~/ 2 : 0,
        cancelledAt: n % 10 == 0 ? when.add(const Duration(hours: 1)) : null,
      );
      payments.putIfAbsent(c.id, () => []).add(p);
    }
    for (final c in cards) {
      payments[c.id] = saved(
        payments[c.id] ?? [],
        eng.priceMonth(c, payments[c.id] ?? []),
      );
    }
  });

  test('test_one_recommendation_under_50ms', () {
    final ms = medianMs(
      () => eng.recommend(cards, payments, [
        const Query(merchant: 'starbucks', amount: 12000),
      ], now),
    );
    expect(ms, lessThan(50), reason: '${ms.toStringAsFixed(1)}ms');
  });

  test('test_category_tops_under_200ms', () {
    final queries = [for (final c in categories) Query(category: c)];
    final ms = medianMs(() => eng.recommend(cards, payments, queries, now));
    expect(ms, lessThan(200), reason: '${ms.toStringAsFixed(1)}ms');
  });
}
