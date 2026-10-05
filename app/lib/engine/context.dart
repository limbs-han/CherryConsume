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
  }

  final Catalog catalog;
  late final Map<String, Frac> pointValue;
  final Map<String, List<String>> children = {};
  late final Frac? fuelPrice;
  final Map<String, Map<String?, List<String>>> _assumed = {};

  /// 카드의 확인 필요 항목 경로를 혜택 key마다 모은 것. 카드 밖의 항목은 null 키다. 규칙 파일을 처음 쓸 때 만든다.
  /// 작업 014 설계 2절
  Map<String?, List<String>> assumedOf(String cardId) =>
      _assumed[cardId] ??= () {
        final byBenefit = <String?, List<String>>{};
        for (final q in catalog.cards[cardId]?.openQuestions ?? const []) {
          final m = _benefitInPath.firstMatch(q.path);
          byBenefit.putIfAbsent(m?.group(1), () => []).add(q.path);
        }
        return byBenefit;
      }();

  /// 그날의 개정 차례. 시행일이 그날 이하인 마지막 개정이고, 없으면 첫 개정이 추정 시행일일 때만 그것이다
  int? _on(String cardId, DateTime day) {
    final heads = catalog.cards[cardId]?.heads;
    if (heads == null || heads.isEmpty) return null;
    final i = heads.lastIndexWhere((h) => !h.effectiveFrom.isAfter(day));
    if (i >= 0) return i;
    return heads.first.effectiveFromEstimated ? 0 : null;
  }

  /// 그날의 개정 머리. 카드 추가 검색이 규칙 파일을 열지 않고 구간을 읽는다. 작업 014 설계 4절
  RevisionHead? headOn(String cardId, DateTime day) {
    final i = _on(cardId, day);
    return i == null ? null : catalog.cards[cardId]!.heads[i];
  }

  /// 그날의 개정. 카탈로그에 없는 카드는 null이라 no_revision으로 건너뛴다. 설계 문서 6.8
  Revision? rulesOn(String cardId, DateTime day) {
    final i = _on(cardId, day);
    return i == null ? null : catalog.cards[cardId]!.revisions[i];
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
