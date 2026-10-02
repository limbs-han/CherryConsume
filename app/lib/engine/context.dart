/// 카탈로그에서 계산에 쓰는 값을 한 번 준비한다. Python `backend/cherry_core/engine/context.py`를 옮겼다. 엔진 설계 4.4의 1
library;

import '../catalog/models.dart';
import 'cond.dart';
import 'frac.dart';
import 'models.dart';

const fuelPriceKey = 'fuel_price_gasoline';
final _benefitInPath = RegExp(r'benefits\[([^\]]+)\]');

/// 카탈로그의 비율 1.3을 정확한 분수 13/10으로 바꾼다. 부동소수점으로 돈을 계산하지 않기 위해서다
Frac frac(Object x) => Frac.of(x);

/// 구간표면 이번 구간 이하 키 중 가장 큰 키의 값, 아니면 그 값
Object? atTier(Object? value, int tier) {
  if (value is Map<int, dynamic>) {
    final keys = value.keys.where((k) => k <= tier);
    if (keys.isEmpty) return null;
    return value[keys.reduce((a, b) => a > b ? a : b)];
  }
  return value;
}

int roundMoney(Frac x, [String mode = 'floor']) {
  if (mode == 'round') return (x + Frac(1, 2)).floor();
  final step = switch (mode) {
    'floor' => 1,
    'floor10' => 10,
    'floor100' => 100,
    _ => throw StateError('모르는 반올림 $mode'),
  };
  return (x / step).floor() * step;
}

class Ctx {
  Ctx(this.catalog) {
    final cat = catalog;
    pointValue = {
      for (final MapEntry(:key, :value) in cat.pointPrograms.entries)
        key: frac(value.wonPerPoint),
    };
    for (final code in [...cat.categories]..sort()) {
      if (code.contains('.')) {
        children.putIfAbsent(code.split('.').first, () => []).add(code);
      }
    }
    final ref = cat.reference[fuelPriceKey];
    fuelPrice = ref != null ? frac(ref.value) : null;
    for (final MapEntry(key: cid, value: card) in cat.cards.entries) {
      final byBenefit = <String?, List<String>>{};
      for (final q in card.openQuestions) {
        final m = _benefitInPath.firstMatch(q.path);
        byBenefit.putIfAbsent(m?.group(1), () => []).add(q.path);
      }
      assumed[cid] = byBenefit;
    }
  }

  final Catalog catalog;
  late final Map<String, Frac> pointValue;
  final Map<String, List<String>> children = {};
  late final Frac? fuelPrice;
  final Map<String, Map<String?, List<String>>> assumed = {};

  /// 그날의 개정. 카탈로그에 없는 카드는 null이라 no_revision으로 건너뛴다. 설계 문서 6.8
  Revision? rulesOn(String cardId, DateTime day) {
    final card = catalog.cards[cardId];
    if (card == null) return null;
    final revisions = card.revisions;
    final current = revisions.where((r) => !r.effectiveFrom.isAfter(day));
    if (current.isNotEmpty) return current.last;
    return revisions.first.effectiveFromEstimated ? revisions.first : null;
  }

  String category(Payment p) {
    if (p.category != null && p.category!.isNotEmpty) return p.category!;
    final m = catalog.merchants[p.merchant ?? ''];
    return m != null ? m.category : 'other';
  }

  String billing(Payment p) {
    if (p.billing != null && p.billing!.isNotEmpty) return p.billing!;
    final m = catalog.merchants[p.merchant ?? ''];
    return m != null ? m.billing : 'normal';
  }

  Situation situation(UserCard card, Payment p) => Situation(
    at: p.paidAt,
    amount: p.amount - p.cancelledAmount,
    merchant: p.merchant,
    category: category(p),
    channel: p.channel,
    region: p.region,
    installmentMonths: p.installmentMonths,
    interestFree: p.interestFree,
    paymentMethod: p.paymentMethod,
    billing: billing(p),
    card: card,
    holidays: catalog.holidays,
    timeKnown: p.timeKnown,
  );
}
