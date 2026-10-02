/// 추천, 못 받는 혜택, 조건부 혜택. Python `backend/cherry_core/engine/recommend.py`를 옮겼다. 엔진 설계 4절
library;

import '../catalog/models.dart';
import 'cond.dart';
import 'context.dart';
import 'models.dart';
import 'price.dart';

const defaultAmount = 10000;

/// 추천 질문으로 만든 가상의 결제. 엔진 설계 4.1
Payment queryPayment(Ctx ctx, UserCard card, Query q, DateTime now) => Payment(
  id: 'query',
  userCardId: card.id,
  amount: q.amount ?? defaultAmount,
  paidAt: now,
  merchant: q.merchant,
  category: q.category,
  channel: _filled(q.channel) ?? 'offline',
  region: _filled(q.region) ?? 'domestic',
  paymentMethod:
      _filled(q.paymentMethod) ??
      _filled(card.lastPaymentMethod) ??
      'physical_card',
);

/// Python의 `or`처럼 빈 글자도 없는 것으로 본다
String? _filled(String? s) => s == null || s.isEmpty ? null : s;

Set<String> paymentMethodsIn(List<Condition> conditions) {
  final out = <String>{};
  for (final c in conditions) {
    out.addAll(c.payment ?? const []);
    for (final sub in c.anyOf ?? const <Condition>[]) {
      out.addAll(paymentMethodsIn([sub]));
    }
  }
  return out;
}

/// 다른 값이면 더 받는 혜택. 엔진 설계 4.3, 작업 001 설계 3.3
///
/// 결제수단은 결제 직전에 고를 수 있어 알고 있어도 조건에 적힌 다른 결제수단으로 바꿔 본다.
/// 사실, 옵션, 업종은 모를 때만 본다. 바꿔 볼 것이 있을 때만 다시 계산한다. 엔진 설계 4.4의 3
List<ConditionalBenefit> conditional(
  Ctx ctx,
  UserCard card,
  Payment p,
  Ledger ledger,
  Priced base,
) {
  final rules = base.rules;
  if (rules == null) return const [];
  final trials = <(Map<String, Object?>, UserCard, Payment)>[];
  final methods = {for (final b in rules.benefits) ...paymentMethodsIn(b.when)}
    ..remove(p.paymentMethod);
  for (final m in methods.toList()..sort()) {
    trials.add(({'payment_method': m}, card, p.copyWith(paymentMethod: m)));
  }
  final needs = {for (final ns in base.unknown.values) ...ns}.toList()..sort();
  for (final n in needs) {
    final parts = needParts(n);
    final kind = parts.first;
    if (kind == 'fact') {
      final key = parts[1];
      final Object value = key == 'birth_month' ? kst(p.paidAt).month : true;
      trials.add((
        {'fact': key},
        card.copyWith(facts: {...card.facts, key: value}),
        p,
      ));
    } else if (kind == 'option') {
      final option = rules.options.firstWhere((o) => o.key == parts[1]);
      for (final ch in option.choices) {
        final pick = OptionPick(
          option: option.key,
          choice: ch.key,
          effectiveFrom: localDay(p.paidAt),
        );
        trials.add((
          {'option': option.key, 'choice': ch.key},
          card.copyWith(options: [...card.options, pick]),
          p,
        ));
      }
    } else if (kind == 'category') {
      for (final c in ctx.children[parts[1]] ?? const <String>[]) {
        trials.add(({'category': c}, card, p.copyWith(category: c)));
      }
    }
  }
  final out = <ConditionalBenefit>[];
  final before = {for (final b in base.result.benefits) b.key: b.value};
  for (final (given, c2, p2) in trials) {
    final after = price(ctx, c2, p2, ledger).result;
    final extra = after.value - base.result.value;
    if (extra > 0) {
      String? key;
      int? gain;
      for (final b in after.benefits) {
        final g = b.value - (before[b.key] ?? 0);
        if (gain == null || g > gain) {
          key = b.key;
          gain = g;
        }
      }
      out.add(
        ConditionalBenefit(
          userCardId: card.id,
          benefit: key!,
          needs: given,
          extra: extra,
        ),
      );
    }
  }
  return sortedStable(out, (a, b) => b.extra.compareTo(a.extra));
}

/// 대상과 조건은 맞는데 구간이 모자란 혜택. 다음 달 한도가 비어 있다고 보고 계산한다. E37
List<LockedBenefit> locked(
  Ctx ctx,
  UserCard card,
  Payment p,
  Ledger ledger,
  Priced base,
  int countedNow,
) {
  final rules = base.rules;
  if (rules == null) return const [];
  final s = situationOf(ctx, card, rules, p);
  final out = <LockedBenefit>[];
  for (final MapEntry(key: key, value: required) in base.tierShort.entries) {
    final b = rules.benefits.firstWhere((x) => x.key == key);
    final o = offer(ctx, rules, b, s, required, Ledger(), s.amount, s.amount);
    if (o.value > 0) {
      out.add(
        LockedBenefit(
          userCardId: card.id,
          benefit: key,
          requiredTier: required,
          remainingThisMonth: required - countedNow > 0
              ? required - countedNow
              : 0,
          valueIfUnlocked: o.value,
        ),
      );
    }
  }
  return out;
}

/// 질문마다 보유 카드의 추천 순위. 사용량 표는 카드마다 한 번만 만든다. 엔진 설계 4절
List<List<Recommendation>> recommend(
  Ctx ctx,
  List<UserCard> cards,
  Map<String, List<Payment>> payments,
  List<Query> queries,
  DateTime now,
) {
  final month = monthOf(localDay(now));
  final prepared = <(UserCard, Ledger, SpendStatus)>[];
  for (final card in cards) {
    if (card.removed) continue;
    final history = payments[card.id] ?? const <Payment>[];
    final ledger = buildLedger(ctx, card, [
      for (final q in history)
        if (!q.paidAt.isAfter(now)) q,
    ]);
    prepared.add((card, ledger, spendStatus(ctx, card, history, month)));
  }
  final answers = <List<Recommendation>>[];
  for (final q in queries) {
    final rows = <Recommendation>[];
    for (final (card, ledger, status) in prepared) {
      final p = queryPayment(ctx, card, q, now);
      final base = price(ctx, card, p, ledger);
      final warns = [
        ...base.result.warnings,
        for (final w in status.warnings)
          if (w.code == 'option_unsupported') w,
        if (q.amount == null) const Warn('default_amount_used'),
      ];
      rows.add(
        Recommendation(
          userCardId: card.id,
          cardId: card.cardId,
          value: base.result.value,
          benefits: base.result.benefits,
          counted: base.result.spend.any((part) => part.amount > 0),
          toKeep: status.toKeep,
          toNext: status.toNext,
          locked: locked(ctx, card, p, ledger, base, status.counted),
          conditional: conditional(ctx, card, p, ledger, base),
          warnings: warns,
        ),
      );
    }
    answers.add(sortedStable(rows, order));
  }
  return answers;
}

/// 기대 혜택, 실적이 모자란 카드, 카드 id 순. 엔진 설계 4.2. Python의 정렬 열쇠 튜플을 비교 함수로 옮겼다
int order(Recommendation a, Recommendation b) {
  int? keep(Recommendation r) =>
      r.counted && (r.toKeep ?? 0) != 0 ? r.toKeep : null;
  int? next(Recommendation r) =>
      r.counted && (r.toNext ?? 0) != 0 ? r.toNext : null;
  int flag(int? x) => x == null ? 1 : 0;
  final keys = [
    b.value.compareTo(a.value),
    flag(keep(a)).compareTo(flag(keep(b))),
    (keep(a) ?? 0).compareTo(keep(b) ?? 0),
    flag(next(a)).compareTo(flag(next(b))),
    (next(a) ?? 0).compareTo(next(b) ?? 0),
    a.cardId.compareTo(b.cardId),
  ];
  return keys.firstWhere((c) => c != 0, orElse: () => 0);
}
