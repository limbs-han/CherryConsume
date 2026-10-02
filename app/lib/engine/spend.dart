/// 실적 계산. Python `backend/cherry_core/engine/spend.py`를 옮겼다. 엔진 설계 2절
library;

import '../catalog/models.dart';
import 'cond.dart';
import 'context.dart';
import 'frac.dart';
import 'models.dart';

/// 받은 혜택 가운데 가장 큰 실적 제외 비율. 한도가 차서 0원이 된 혜택은 받은 것으로 보지 않는다
Frac appliedRatio(Rules rules, List<AppliedBenefit> benefits) {
  var ratio = frac(0);
  final byKey = {for (final b in rules.benefits) b.key: b};
  for (final got in benefits) {
    final b = byKey[got.key];
    if (got.value > 0 && b != null) {
      ratio = maxFrac(
        ratio,
        frac(b.excludeApplied ?? rules.spend.excludeApplied),
      );
    }
  }
  return ratio;
}

List<List<String>> _sortedNeeds(Set<String> needs) => [
  for (final n in needs.toList()..sort()) needParts(n),
];

/// 결제 한 건이 실적에 넣는 금액과 달. 엔진 설계 2.2, 2.3. 실적에서 빠지면 그 이유를 경고로 돌려준다
///
/// 취소한 결제면 benefits는 남은 금액이 받는 혜택이고 before는 취소하지 않았다면 받았을 혜택이다. 결제한 달의 처음
/// 실적은 before의 비율로, 남은 금액의 실적은 benefits의 비율로 센다. 설계 문서 6.5, E5
(List<SpendPart>, List<Warn>) spendParts(
  Ctx ctx,
  UserCard card,
  Payment p,
  Rules rules,
  List<AppliedBenefit> benefits, [
  List<AppliedBenefit>? before,
]) {
  final s = rules.spend;
  final paidMonth = monthOf(localDay(p.paidAt));
  final category = ctx.category(p);
  if (!s.regions.contains(p.region)) {
    return (
      const [],
      const [
        Warn('not_counted_toward_spend', data: {'reason': 'region'}),
      ],
    );
  }
  final (excluded, needs) = categoriesMatch(category, s.excludeCategories);
  if (excluded != false) {
    final warns = [
      const Warn('not_counted_toward_spend', data: {'reason': 'category'}),
    ];
    if (excluded == null) {
      warns.add(Warn('needs_input', data: {'needs': _sortedNeeds(needs)}));
    }
    return (const [], warns);
  }
  if (s.interestFree == 'exclude' && p.interestFree) {
    return (
      const [],
      const [
        Warn('not_counted_toward_spend', data: {'reason': 'interest_free'}),
      ],
    );
  }

  final ratio = appliedRatio(rules, benefits);
  final first = p.cancelledAmount > 0 && before != null
      ? appliedRatio(rules, before)
      : ratio;
  final counted = ((frac(1) - first) * p.amount).floor();
  final warns = counted == 0
      ? [
          const Warn(
            'not_counted_toward_spend',
            data: {'reason': 'benefit_applied'},
          ),
        ]
      : <Warn>[];

  var offset = 0;
  for (final MapEntry(key: cat, value: n) in s.monthOffset.entries) {
    if (categoriesMatch(category, [cat]).$1 == true && n > offset) offset = n;
  }
  final start = addMonths(paidMonth, offset);
  final parts = <SpendPart>[];
  if (s.installment == 'per_installment_month' && p.installmentMonths > 1) {
    final each = counted ~/ p.installmentMonths;
    for (var i = 0; i < p.installmentMonths; i++) {
      final last = i == p.installmentMonths - 1;
      parts.add(
        SpendPart(addMonths(start, i), last ? counted - each * i : each),
      );
    }
  } else {
    parts.add(SpendPart(start, counted));
  }

  final minus = p.cancelledAmount > 0
      ? counted - ((frac(1) - ratio) * (p.amount - p.cancelledAmount)).floor()
      : 0;
  // 남은 금액이 혜택을 잃어 처음보다 실적이 커지면 취소로 실적을 늘려야 하는지 카드사 문구가 없다. 늘리지 않는다
  // 모르면 부풀리지 않는 쪽이다. 설계 3.1과 같다. 확인 필요. 2026-10-02 위험 검토
  if (minus > 0) {
    var use = s.cancellation;
    for (final o in s.cancellationOverrides) {
      if (check(o.when, ctx.situation(card, p)).$1 == true) use = o.use;
    }
    final month = use == 'cancel_month' && p.cancelledAt != null
        ? monthOf(localDay(p.cancelledAt!))
        : start;
    parts.add(SpendPart(month, -minus));
  }
  return (parts, warns);
}

/// 이번 달 기본 구간. (구간 하한, 근거, 지난달 인정 실적, 경고). 엔진 설계 2.4
///
/// prevCounted는 지난달 인정 실적, prevRecorded는 지난달 결제가 한 건이라도 기록됐는지다
(int?, String, int?, List<Warn>) tierOf(
  Ctx ctx,
  UserCard card,
  DateTime month,
  int prevCounted,
  bool prevRecorded,
) {
  final found = ctx.rulesOn(card.cardId, month);
  if (found == null) return (null, 'none', null, const []);
  final rules = found.rules;
  if (rules.spend.basis == 'none') return (0, 'none', null, const []);
  if (rules.spend.basis == 'billing_cycle') {
    return (0, 'unsupported', null, const [Warn('spend_basis_unsupported')]);
  }
  var prev = prevCounted > 0 ? prevCounted : 0;
  var source = 'prev_month';
  var warns = <Warn>[];
  final registeredNow =
      card.registeredOn != null && monthOf(card.registeredOn!) == month;
  if (registeredNow && !prevRecorded) {
    if (card.assumedPrevMonthSpend != null) {
      prev = card.assumedPrevMonthSpend!;
      source = 'assumed';
    } else {
      prev = 0;
      warns = [const Warn('no_prev_month_data')];
    }
  }
  final tier = rules.tiers
      .where((t) => t <= prev)
      .reduce((a, b) => a > b ? a : b);
  return (tier, source, prev, warns);
}

/// 신규 발급 특례 기간이면 특례 구간과 기본 구간 중 큰 쪽. (구간, 특례를 썼는지). 엔진 설계 2.4의 3
(int, bool) newCardTier(
  UserCard card,
  DateTime month,
  Rules rules,
  String? benefitKey,
  int base,
) {
  final nc = rules.newCard;
  if (nc == null || card.startedOn == null) return (base, false);
  final start = monthOf(card.startedOn!);
  if (month.isBefore(start) || month.isAfter(addMonths(start, 1))) {
    return (base, false);
  }
  final special = benefitKey != null
      ? (nc.tierByBenefit[benefitKey] ?? nc.tier)
      : nc.tier;
  return (base > special ? base : special, special > base);
}

/// 카드 전체에 해당하는 문장 조건, 가정한 값, 고르지 않은 옵션. 엔진 설계 5.2, 5.3, 3.8
List<Warn> cardNotes(Ctx ctx, UserCard card, Rules rules, DateTime month) {
  final out = <Warn>[];
  final sentences = [...rules.unmodeled, ...rules.benefitExclusions.unmodeled];
  if (sentences.isNotEmpty) {
    out.add(Warn('check_conditions', data: {'sentences': sentences}));
  }
  final paths = ctx.assumed[card.cardId]?[null];
  if (paths != null && paths.isNotEmpty) {
    out.add(Warn('assumed_value', data: {'paths': paths}));
  }
  final lastDay = addMonths(month, 1);
  final picks = sortedStable(
    card.options.where((p) => p.effectiveFrom.isBefore(lastDay)),
    (a, b) => a.effectiveFrom.compareTo(b.effectiveFrom),
  );
  final chosenNow = {for (final p in picks) p.option: p.choice};
  for (final o in rules.options) {
    final chosen = chosenNow.containsKey(o.key)
        ? chosenNow[o.key]
        : o.defaultChoice;
    if (chosen == null) {
      out.add(
        Warn(
          'needs_input',
          data: {
            'needs': [
              ['option', o.key],
            ],
          },
        ),
      );
    } else if (o.unsupported.contains(chosen)) {
      out.add(
        Warn('option_unsupported', data: {'option': o.key, 'choice': chosen}),
      );
    }
  }
  return out;
}
