/// 결제 하나의 혜택 계산. Python `backend/cherry_core/engine/price.py`를 옮겼다. 엔진 설계 3절과 4.4의 사용량 표
library;

import '../catalog/models.dart';
import 'cond.dart';
import 'context.dart';
import 'frac.dart';
import 'models.dart';
import 'spend.dart';

const skipTotals = {'ranked', 'month_total'};

/// 한도 이름. 혜택에 직접 적은 한도는 own과 혜택 key와 순서, 공유 한도는 shared와 key, 달 합계로 준 혜택은 given이다.
/// Python의 튜플을 대신한다
class Ident {
  const Ident(this.kind, this.key, [this.index]);
  final String kind, key;
  final int? index;
  String get id =>
      index == null ? '$kind\u0000$key' : '$kind\u0000$key\u0000$index';
}

/// 한도 기간. txn은 결제 하나라 쌓지 않는다. period는 행사 기간 전체, lifetime은 늘 하나다. 엔진 설계 3.4
String? periodKey(String per, DateTime at) {
  final d = localDay(at);
  return switch (per) {
    'txn' => null,
    'day' => 'd\u0000${dayText(d)}',
    'month' => 'm\u0000${d.year}\u0000${d.month}',
    'quarter' => 'q\u0000${d.year}\u0000${(d.month - 1) ~/ 3}',
    'year' => 'y\u0000${d.year}',
    'period' => 'p',
    'lifetime' => 'l',
    _ => throw StateError('모르는 한도 기간 $per'),
  };
}

String areaKey(String group, String area, DateTime month) =>
    '$group\u0000$area\u0000${dayText(month)}';

/// 혜택이 쓰는 한도마다 (이름, 실제 칸)
List<(Ident, Limit)> limitSpecs(Rules rules, Benefit b) {
  final shared = {for (final x in rules.limits) x.key: x};
  return [
    for (final (i, lim) in b.limits.indexed)
      lim.shared != null
          ? (Ident('shared', lim.shared!), shared[lim.shared!]!)
          : (Ident('own', b.key, i), lim),
  ];
}

Situation situationOf(Ctx ctx, UserCard card, Rules rules, Payment p) {
  final s = ctx.situation(card, p);
  s.defaults = {for (final o in rules.options) o.key: o.defaultChoice};
  return s;
}

/// 제외 조건을 대상 쪽 판정으로 바꾼다. 제외에 걸리면 거짓, 모르면 모름이다. 엔진 설계 2.1
Tri negate(Tri t) => t.$1 == true
    ? no
    : t.$1 == false
    ? yes
    : t;

/// 행사 기간, 대상, 공통 제외, when 조건. 구간은 따로 본다. 엔진 설계 3.2의 1~4
Tri benefitMatch(Rules rules, Benefit b, Situation s) {
  if ((b.validFrom != null && s.day.isBefore(b.validFrom!)) ||
      (b.validUntil != null && s.day.isAfter(b.validUntil!))) {
    return no;
  }
  final t = b.target;
  final hit = t.all
      ? yes
      : anyOf([
          t.merchants.contains(s.merchant) ? yes : no,
          categoriesMatch(s.category, t.categories),
        ]);
  if (hit.$1 == false || t.excludeMerchants.contains(s.merchant)) return no;
  final parts = <Tri>[
    hit,
    negate(categoriesMatch(s.category, t.excludeCategories)),
  ];
  final be = rules.benefitExclusions;
  // 대상이 공통 제외 업종이나 더 좁은 업종으로 이 결제를 적었으면 그 공통 제외는 무시한다. 가맹점만 적었거나 대상이
  // 제외보다 넓으면 결제 업종으로 공통 제외를 본다. 2026-09-29 사용자가 정했다. 엔진 설계 3.2의 3
  final listed = [
    for (final c in t.categories)
      if (categoriesMatch(s.category, [c]).$1 == true) c,
  ];
  final left = [
    for (final e in be.categories)
      if (!listed.any((c) => categoriesMatch(c, [e]).$1 == true)) e,
  ];
  parts.add(negate(categoriesMatch(s.category, left)));
  parts.addAll(be.whenAny.map((w) => negate(check(w, s))));
  s.area = b.area ?? b.key;
  parts.add(checkAll(b.when, s));
  return allOf(parts);
}

/// 순위 그룹마다 영역과 그 영역의 혜택. 영역은 area, 없으면 혜택 key. 파일에 적힌 순서다
Map<String, Map<String, List<Benefit>>> rankedAreas(Rules rules) {
  final out = <String, Map<String, List<Benefit>>>{};
  for (final b in rules.benefits) {
    for (final c in b.when) {
      if (c.ranked != null) {
        out
            .putIfAbsent(c.ranked!, () => {})
            .putIfAbsent(b.area ?? b.key, () => [])
            .add(b);
      }
    }
  }
  return out;
}

/// 사용량 표. 저장된 결제를 한 번 훑어 한도 사용량, 순위 영역 이용액, 달 합계, 달별 실적을 모은다. 엔진 설계 4.4
///
/// child()로 만든 표는 부모 위에 쌓아 두는 임시 표다. 결제 하나를 계산하는 동안 쓴 한도를 부모를 바꾸지 않고 센다
class Ledger {
  Ledger({this.parent});

  final Map<String, List<int>> use = {};
  final Map<String, int> area = {};
  final Map<String, int> monthBase = {};
  final Map<DateTime, int> counted = {};
  final Set<DateTime> seen = {};
  final Ledger? parent;

  List<int> used(Ident ident, String key) {
    final own = use['${ident.id}#$key'] ?? const [0, 0, 0];
    final up = parent?.used(ident, key) ?? const [0, 0, 0];
    return [for (var i = 0; i < 3; i++) up[i] + own[i]];
  }

  int areaSpend(String group, String areaName, DateTime month) {
    final k = areaKey(group, areaName, month);
    return (area[k] ?? 0) + (parent?.areaSpend(group, areaName, month) ?? 0);
  }

  int monthTotal(String key, DateTime month) =>
      (monthBase['$key\u0000${dayText(month)}'] ?? 0) +
      (parent?.monthTotal(key, month) ?? 0);

  int countedIn(DateTime month) =>
      (counted[month] ?? 0) + (parent?.countedIn(month) ?? 0);

  bool recorded(DateTime month) =>
      seen.contains(month) || (parent?.recorded(month) ?? false);

  Ledger child() => Ledger(parent: this);

  void addBenefit(Rules rules, Benefit b, AppliedBenefit got, DateTime at) {
    final idents = limitSpecs(rules, b);
    if (b.reward.basis == 'month_total') {
      idents.add((Ident('given', b.key), Limit(per: 'month', amount: 0)));
    }
    for (final (ident, lim) in idents) {
      final key = periodKey(lim.per!, at);
      if (key == null) continue;
      final u = use.putIfAbsent('${ident.id}#$key', () => [0, 0, 0]);
      u[0] += got.amount;
      u[1] += got.amount > 0 ? 1 : 0;
      u[2] += got.base;
    }
  }

  /// 저장된 결제 한 건을 표에 더한다
  void add(Ctx ctx, UserCard card, Payment p) {
    final d = localDay(p.paidAt);
    final month = monthOf(d);
    seen.add(month);
    final found = ctx.rulesOn(card.cardId, d);
    if (found == null) return;
    final rules = found.rules;
    final (parts, _) = spendParts(
      ctx,
      card,
      p,
      rules,
      p.benefits ?? const [],
      beforeCancel(ctx, card, p, this),
    );
    for (final part in parts) {
      counted[part.month] = (counted[part.month] ?? 0) + part.amount;
    }
    final byKey = {for (final b in rules.benefits) b.key: b};
    for (final got in p.benefits ?? const <AppliedBenefit>[]) {
      final b = byKey[got.key];
      if (b != null) addBenefit(rules, b, got, p.paidAt);
    }
    addTotals(ctx, card, rules, p, month);
  }

  /// 순위 영역 이용액과 달 합계 혜택의 대상 이용액. 엔진 설계 3.4, 3.5
  ///
  /// 순위 영역에서 취소를 빼는 달은 ranked[].cancellation을 따른다. 취소한 달이면 결제한 달에는 결제 전액을 넣고
  /// 취소한 달에서 취소액을 뺀다. 결제한 달이거나 칸이 비거나 같은 달 취소면 결제한 달에 남은 금액을 넣는다. E55
  ///
  /// ponytail: 취소액은 결제 시각 자리에서 취소한 달 칸에 들어가 그 달의 취소 시각 전 결제의 잠정 순위에도 빠진다.
  /// 결제일 개정의 그룹과 영역 이름으로 쌓는다. 달 중간 잠정값이고 달 끝 순위는 맞다
  void addTotals(
    Ctx ctx,
    UserCard card,
    Rules rules,
    Payment p,
    DateTime month,
  ) {
    final s = situationOf(ctx, card, rules, p);
    s.skip = skipTotals;
    if (s.amount > 0) {
      for (final b in rules.benefits) {
        if (b.reward.basis == 'month_total' &&
            benefitMatch(rules, b, s).$1 == true) {
          final k = '${b.key}\u0000${dayText(month)}';
          monthBase[k] = (monthBase[k] ?? 0) + s.amount;
        }
      }
    }
    final ways = {for (final r in rules.ranked) r.key: r.cancellation};
    for (final MapEntry(key: group, value: areas) in rankedAreas(
      rules,
    ).entries) {
      final later =
          ways[group] == 'cancel_month' &&
          p.cancelledAmount > 0 &&
          monthOf(localDay(p.cancelledAt!)) != month;
      List<(DateTime, int)> adds;
      Situation by;
      if (later) {
        // 달을 건너는 취소는 영역에 드는지를 취소 전 결제로 본다. 더할 때와 뺄 때 같은 판정이어야 한다.
        // 전액 취소여도 결제한 달에는 들어간다
        final whole = situationOf(
          ctx,
          card,
          rules,
          p.copyWith(cancelledAmount: 0, cancelledAt: null),
        );
        whole.skip = skipTotals;
        final cancelMonth = monthOf(localDay(p.cancelledAt!));
        adds = [(month, p.amount), (cancelMonth, -p.cancelledAmount)];
        by = whole;
      } else {
        adds = s.amount > 0 ? [(month, s.amount)] : [];
        by = s;
      }
      for (final MapEntry(key: name, value: members) in areas.entries) {
        if (members.any((b) => benefitMatch(rules, b, by).$1 == true)) {
          for (final (m, x) in adds) {
            final k = areaKey(group, name, m);
            area[k] = (area[k] ?? 0) + x;
          }
        }
      }
    }
  }
}

Ledger buildLedger(Ctx ctx, UserCard card, List<Payment> payments) {
  final ledger = Ledger();
  for (final p in [...payments]..sort(byTime)) {
    ledger.add(ctx, card, p);
  }
  return ledger;
}

/// 결제액 base에 대한 보상 단위의 금액. 원 미만과 반올림은 reward.round를 따른다. 엔진 설계 3.3
int rewardAmount(Ctx ctx, Benefit b, int base, int tier) {
  final r = b.reward;
  Frac x;
  if (r.rate != null) {
    x = frac(base) * frac(atTier(r.rate, tier)!) / 100;
  } else if (r.fixed != null) {
    x = base > 0 ? frac((atTier(r.fixed, tier) as int?) ?? 0) : frac(0);
  } else if (r.perUnit != null) {
    x = frac((base ~/ r.perUnit!.unit) * r.perUnit!.amount);
  } else if (ctx.fuelPrice != null) {
    x = frac(base) * r.perLiter! / ctx.fuelPrice!;
  } else {
    return 0;
  }
  return roundMoney(x, r.round);
}

/// 현장할인의 할인 전 금액을 되짚는다. 혜택의 반올림으로 할인하면 기록 금액이 나오는 금액 중 가장 큰 값이다.
/// 그런 금액이 없으면 비율로 되짚고 버린다. 2026-09-29 사용자가 정했다. 엔진 설계 3.6
int preDiscount(Benefit b, int net, int tier) {
  final r = b.reward;
  if (r.rate == null) return net + ((atTier(r.fixed, tier) as int?) ?? 0);
  final rate = frac(atTier(r.rate, tier)!) / 100;
  final step = switch (r.round) {
    'floor' || 'round' => 1,
    'floor10' => 10,
    'floor100' => 100,
    _ => throw StateError('모르는 반올림 ${r.round}'),
  };
  final top = (frac(net + 1) / (frac(1) - rate)).floor();
  final bottom = (frac(net - step) / (frac(1) - rate)).floor();
  final low = bottom > net ? bottom : net;
  for (var pre = top; pre > low - 1; pre--) {
    if (pre - roundMoney(rate * pre, r.round) == net) return pre;
  }
  return (frac(net) / (frac(1) - rate)).floor();
}

/// 현장할인 조건을 판정할 할인 전 금액. 건당 금액 한도가 있으면 기록 금액 + 자른 할인액이다. 엔진 설계 3.6
/// ponytail: 날·달 한도로 줄어든 할인은 여기서 보지 않는다. 그런 카드가 생기면 한도를 센 뒤 조건을 다시 판정한다
int onsitePre(Rules rules, Benefit b, Situation s, int net, int tier) {
  final pre = preDiscount(b, net, tier);
  final txnCaps = [
    for (final (_, lim) in limitSpecs(rules, b))
      if (lim.per == 'txn') caps(lim, tier, s).$1,
  ].whereType<int>().toList();
  if (txnCaps.isEmpty) return pre;
  final cap = net + txnCaps.reduce((a, c) => a < c ? a : c);
  return pre < cap ? pre : cap;
}

/// 순위 조건을 빼면 걸리는지. 구간이 모자라 상위 개수가 0인 순위 혜택을 못 받는 혜택으로 보여 주려는 것이다. E37
bool unrankedHit(Rules rules, Benefit b, Situation s) {
  if (!b.when.any((c) => c.ranked != null)) return false;
  final skip = s.skip;
  s.skip = {...skip, 'ranked'};
  final hit = benefitMatch(rules, b, s).$1 == true;
  s.skip = skip;
  return hit;
}

/// 한도 칸의 (금액, 횟수, 결제액, 모르는 것). 구간표와 adjust를 적용한다.
/// adjust 조건이 모름이면 바꾼 한도와 원래 한도 중 작은 쪽을 쓰고 무엇을 모르는지 돌려준다. 부풀리지 않는 쪽이다.
/// 2026-09-29 사용자가 정했다. 엔진 설계 3.1
(int?, int?, int?, Set<String>) caps(Limit lim, int tier, Situation s) {
  var amount = atTier(lim.amount, tier) as int?;
  var count = atTier(lim.count, tier) as int?;
  var base = atTier(lim.base, tier) as int?;
  final needs = <String>{};
  for (final a in lim.adjust) {
    final hit = check(a.when, s);
    if (hit.$1 == false) continue;
    final given = a.given;
    var newAmount = given.contains('amount')
        ? atTier(a.amount, tier) as int?
        : amount;
    final newCount = given.contains('count')
        ? atTier(a.count, tier) as int?
        : count;
    final newBase = given.contains('base')
        ? atTier(a.base, tier) as int?
        : base;
    if (a.multiply != null && newAmount != null) {
      newAmount = (frac(a.multiply!) * newAmount).floor();
    }
    if (a.add != null && newAmount != null) newAmount += a.add!;
    if (hit.$1 == null) {
      needs.addAll(hit.$2);
      amount = smaller(amount, newAmount);
      count = smaller(count, newCount);
      base = smaller(base, newBase);
    } else {
      amount = newAmount;
      count = newCount;
      base = newBase;
    }
  }
  return (amount, count, base, needs);
}

/// 한도 둘 중 작은 쪽. null은 제한 없음이다
int? smaller(int? a, int? b) => a == null
    ? b
    : b == null
    ? a
    : (a < b ? a : b);

/// 혜택 하나를 이 결제에 계산해 본 결과. base는 혜택 계산에 넣은 결제액이다
class Offer {
  Offer(
    this.benefit,
    this.amount,
    this.value,
    this.base,
    this.limited, [
    this.exhausted = false,
    this.needs = const {},
  ]);
  final Benefit benefit;
  final int amount, value, base;
  final bool limited, exhausted;
  final Set<String> needs;

  AppliedBenefit applied() => AppliedBenefit(
    key: benefit.key,
    amount: amount,
    value: value,
    base: base,
  );
}

/// 한도 안에서 이 혜택이 이 결제에 줄 수 있는 금액. room은 이 묶음에서 아직 혜택에 쓰지 않은 결제액이고
/// total은 달 합계 혜택이면 이 결제까지의 이번 달 대상 이용액이다.
///
/// limited는 어느 한도든 금액을 줄였는지, exhausted는 날, 달, 기간 한도가 줄였는지다. 건당 한도는
/// "한도를 다 썼다"가 아니라서 exhausted에 넣지 않는다. 엔진 설계 5.1
Offer offer(
  Ctx ctx,
  Rules rules,
  Benefit b,
  Situation s,
  int tier,
  Ledger ledger,
  int room, [
  int total = 0,
]) {
  final onsite = b.reward.type == 'onsite_discount';
  final pre = onsite ? preDiscount(b, room, tier) : room;
  var base = pre;
  var limited = false, exhausted = false;
  final specs = [
    for (final (ident, lim) in limitSpecs(rules, b))
      (ident, lim, caps(lim, tier, s)),
  ];
  final needs = <String>{for (final (_, _, c) in specs) ...c.$4};
  final usage = {
    for (final (ident, lim, _) in specs)
      ident.id: switch (periodKey(lim.per!, s.at)) {
        final String key => ledger.used(ident, key),
        null => const [0, 0, 0],
      },
  };
  for (final (ident, lim, (_, count, capBase, _)) in specs) {
    if (count != null && usage[ident.id]![1] >= count) {
      return Offer(b, 0, 0, 0, true, lim.per != 'txn', needs);
    }
    if (capBase != null && base > capBase - usage[ident.id]![2]) {
      final left = capBase - usage[ident.id]![2];
      base = left > 0 ? left : 0;
      limited = true;
      exhausted = exhausted || lim.per != 'txn';
    }
  }
  int amount;
  if (b.reward.basis == 'month_total') {
    final given = ledger.used(
      Ident('given', b.key),
      periodKey('month', s.at)!,
    )[0];
    final x = rewardAmount(ctx, b, total, tier) - given;
    amount = x > 0 ? x : 0;
  } else if (onsite && !limited) {
    amount = b.reward.rate != null
        ? pre - room
        : rewardAmount(ctx, b, base, tier);
  } else {
    amount = rewardAmount(ctx, b, base, tier);
  }
  for (final (ident, lim, (capAmount, _, _, _)) in specs) {
    if (capAmount != null && amount > capAmount - usage[ident.id]![0]) {
      final left = capAmount - usage[ident.id]![0];
      amount = left > 0 ? left : 0;
      limited = true;
      exhausted = exhausted || lim.per != 'txn';
    }
  }
  if (amount == 0) {
    base = 0;
  } else if (onsite && b.reward.rate != null) {
    base = room + amount; // 현장할인은 기록 금액에 실제 할인액을 더한 것이 할인 전 금액이다. 엔진 설계 3.6
  } else if (limited && b.reward.rate != null && b.reward.basis == 'txn') {
    final need = (frac(amount) * 100 / frac(atTier(b.reward.rate, tier)!))
        .ceil();
    base = base < need ? base : need;
  }
  final value = b.reward.type != 'points'
      ? amount
      : (frac(amount) * (ctx.pointValue[b.reward.program] ?? frac(1))).floor();
  return Offer(b, amount, value, base, limited, exhausted, needs);
}

/// 중복 묶음마다 혜택을 고른다. 엔진 설계 3.7. candidates는 묶음 key마다 (혜택, 구간, 달 합계)이고 파일 순서다.
/// (받은 혜택, 기간 한도로 줄어든 혜택 key, 혜택마다 한도 조건에서 모르는 것)을 돌려준다
(List<Offer>, Set<String>, Map<String, Set<String>>) choose(
  Ctx ctx,
  Rules rules,
  Situation s,
  Map<String, List<(Benefit, int, int)>> candidates,
  Ledger ledger,
) {
  final specs = {for (final st in rules.stacks) st.key: st};
  final scratch = ledger.child();
  final got = <Offer>[];
  final exhausted = <String>{};
  final needs = <String, Set<String>>{};
  for (final MapEntry(key: stack, value: all) in candidates.entries) {
    final st = specs[stack];
    final pick = st?.pick ?? 'best', spill = st?.spill ?? 'none';
    var members = all;
    if (pick == 'priority') {
      final rank = {for (final (i, k) in st!.order.indexed) k: i};
      members = sortedStable(
        members,
        (a, b) => (rank[a.$1.key] ?? rank.length).compareTo(
          rank[b.$1.key] ?? rank.length,
        ),
      );
    }
    var room = s.amount;
    var left = [...members];
    while (left.isNotEmpty && room > 0) {
      final offers = [
        for (final (b, tier, total) in left)
          offer(ctx, rules, b, s, tier, scratch, room, total),
      ];
      exhausted.addAll([
        for (final o in offers)
          if (o.exhausted) o.benefit.key,
      ]);
      for (final o in offers) {
        if (o.needs.isNotEmpty) {
          needs[o.benefit.key] = {...?needs[o.benefit.key], ...o.needs};
        }
      }
      final live = [
        for (final o in offers)
          if (o.amount > 0) o,
      ];
      if (live.isEmpty) break;
      var best = live.first;
      if (pick != 'priority') {
        for (final o in live) {
          if (o.value > best.value) best = o;
        }
      }
      got.add(best);
      scratch.addBenefit(rules, best.benefit, best.applied(), s.at);
      if (spill != 'split') break;
      room -= best.base;
      left = [
        for (final m in left)
          if (m.$1.key != best.benefit.key) m,
      ];
    }
  }
  return (got, exhausted, needs);
}

/// price의 중간 결과. 추천이 못 받는 혜택과 조건부 혜택을 만들 때 쓴다
class Priced {
  Priced(
    this.result, [
    this.rules,
    this.tier = 0,
    this.unknown = const {},
    this.tierShort = const {},
  ]);
  final PaymentResult result;
  final Rules? rules;
  final int tier;
  final Map<String, Set<String>> unknown;
  final Map<String, int> tierShort;
}

/// 취소한 결제가 취소하지 않았다면 받았을 혜택. 결제한 달의 처음 실적을 이 혜택의 비율로 센다. 설계 문서 6.5, E5
///
/// ledger는 이 결제보다 앞선 결제들의 사용량 표라 그때의 구간과 한도로 다시 계산한다. 사용량 표는 읽기만 한다
List<AppliedBenefit>? beforeCancel(
  Ctx ctx,
  UserCard card,
  Payment p,
  Ledger ledger, [
  Map<String, int>? finalAreas,
]) {
  if (p.cancelledAmount == 0) return null;
  // ponytail: 취소한 결제마다 price를 한 번 더 부른다. 취소가 흔해져 느려지면 (결제 id, 사용량 표 판) 열쇠로 기억한다
  final whole = p.copyWith(
    cancelledAmount: 0,
    cancelledAt: null,
    benefits: null,
  );
  return price(ctx, card, whole, ledger, finalAreas).result.benefits;
}

/// 결제 한 건의 혜택과 실적. ledger는 이 결제보다 앞선 결제들의 사용량 표다
Priced price(
  Ctx ctx,
  UserCard card,
  Payment p,
  Ledger ledger, [
  Map<String, int>? finalAreas,
]) {
  final d = localDay(p.paidAt);
  final month = monthOf(d);
  final found = ctx.rulesOn(card.cardId, d);
  if (found == null) {
    return Priced(
      PaymentResult(paymentId: p.id, warnings: const [Warn('no_revision')]),
    );
  }
  final rules = found.rules;
  final warns = <Warn>[];
  if (d.isBefore(found.effectiveFrom)) {
    warns.add(
      Warn(
        'revision_estimated',
        data: {'effective_from': dayText(found.effectiveFrom)},
      ),
    );
  }
  final prev = addMonths(month, -1);
  final (tierBase, _, _, tierWarns) = tierOf(
    ctx,
    card,
    month,
    ledger.countedIn(prev),
    ledger.recorded(prev),
  );
  warns.addAll(tierWarns);
  final baseTier = tierBase ?? 0;
  final s = situationOf(ctx, card, rules, p);
  final net = s.amount;
  var got = <Offer>[];
  final unknown = <String, Set<String>>{};
  final tierShort = <String, int>{};
  var exhausted = <String>{};
  var limitNeeds = <String, Set<String>>{};
  if (net > 0) {
    final (topTier, _) = newCardTier(card, month, rules, null, baseTier);
    s.topAreas = topAreas(rules, s, month, topTier, ledger, finalAreas);
    final candidates = <String, List<(Benefit, int, int)>>{};
    for (final b in rules.benefits) {
      final (tier, _) = newCardTier(card, month, rules, b.key, baseTier);
      var total = 0;
      if (b.reward.basis == 'month_total') {
        s.skip = {'month_total'};
        final mine = benefitMatch(rules, b, s).$1 == true ? net : 0;
        total = ledger.monthTotal(b.key, month) + mine;
        s.skip = const {};
        s.monthTotal = total;
      }
      if (b.reward.type == 'onsite_discount') {
        s.amount = onsitePre(rules, b, s, net, tier);
      }
      var hit = benefitMatch(rules, b, s);
      s.amount = net;
      s.monthTotal = null;
      final lo = b.tiers?.start ?? rules.tiers.first;
      final hi = b.tiers?.end ?? rules.tiers.last;
      if (hit.$1 == false) {
        if (tier < lo &&
            b.tiers!.waivedWhen == null &&
            unrankedHit(rules, b, s)) {
          tierShort[b.key] = lo;
        }
        continue;
      }
      if (tier > hi) continue;
      if (tier < lo) {
        final waived = b.tiers!.waivedWhen != null
            ? check(b.tiers!.waivedWhen!, s)
            : no;
        if (waived.$1 == false) {
          if (hit.$1 == true) tierShort[b.key] = lo;
          continue;
        }
        if (waived.$1 == null) {
          tierShort[b.key] = lo;
          hit = allOf([hit, waived]);
        }
      }
      if (hit.$1 == null) {
        unknown[b.key] = hit.$2;
        continue;
      }
      candidates.putIfAbsent(b.stack, () => []).add((b, tier, total));
    }
    (got, exhausted, limitNeeds) = choose(ctx, rules, s, candidates, ledger);
  }
  final applied = [for (final o in got) o.applied()];
  final (parts, spendWarns) = spendParts(
    ctx,
    card,
    p,
    rules,
    applied,
    beforeCancel(ctx, card, p, ledger, finalAreas),
  );
  final allUnknown = {...unknown, ...limitNeeds};
  warns
    ..addAll(spendWarns)
    ..addAll(
      notes(
        ctx,
        card,
        got,
        allUnknown,
        tierShort,
        exhausted,
        finalAreas != null,
      ),
    );
  final result = PaymentResult(
    paymentId: p.id,
    benefits: applied,
    spend: parts,
    warnings: warns,
  );
  return Priced(result, rules, baseTier, allUnknown, tierShort);
}

/// 순위 그룹마다 이번 달 이용액 상위 영역. 이 결제를 포함한다. finalAreas가 있으면 달 전체 이용액으로 매긴다. 엔진 설계 3.5
Map<String, Set<String>> topAreas(
  Rules rules,
  Situation s,
  DateTime month,
  int tier,
  Ledger ledger,
  Map<String, int>? finalAreas,
) {
  final groups = rankedAreas(rules);
  if (groups.isEmpty) return {};
  final skip = s.skip;
  s.skip = skipTotals;
  final tops = {for (final r in rules.ranked) r.key: r.top};
  final out = <String, Set<String>>{};
  for (final MapEntry(key: group, value: areas) in groups.entries) {
    final spend = <(int, int, String)>[];
    for (final (i, MapEntry(key: name, value: members))
        in areas.entries.indexed) {
      int total;
      if (finalAreas != null) {
        total = finalAreas[areaKey(group, name, month)] ?? 0;
      } else {
        final mine = members.any((b) => benefitMatch(rules, b, s).$1 == true)
            ? s.amount
            : 0;
        total = ledger.areaSpend(group, name, month) + mine;
      }
      spend.add((-total, i, name));
    }
    spend.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    final top = (atTier(tops[group], tier) as int?) ?? 0;
    out[group] = {
      for (final (total, _, name) in spend.take(top))
        if (total < 0) name,
    };
  }
  s.skip = skip;
  return out;
}

/// 결제 결과에 붙는 경고. 엔진 설계 5절
List<Warn> notes(
  Ctx ctx,
  UserCard card,
  List<Offer> got,
  Map<String, Set<String>> unknown,
  Map<String, int> tierShort,
  Set<String> exhausted,
  bool isFinal,
) {
  final out = <Warn>[
    for (final MapEntry(key: k, value: lo) in tierShort.entries)
      Warn('tier_not_met', benefit: k, data: {'required': lo}),
    for (final k in exhausted.toList()..sort())
      Warn('limit_exhausted', benefit: k),
  ];
  if (unknown.isNotEmpty) {
    final needs = {for (final ns in unknown.values) ...ns}.toList()..sort();
    out.add(
      Warn(
        'needs_input',
        data: {
          'needs': [for (final n in needs) needParts(n)],
          'benefits': unknown.keys.toList()..sort(),
        },
      ),
    );
  }
  final sentences = [for (final o in got) ...o.benefit.unmodeled];
  if (sentences.isNotEmpty) {
    out.add(Warn('check_conditions', data: {'sentences': sentences}));
  }
  final assumed = ctx.assumedOf(card.cardId);
  final paths = [for (final o in got) ...?assumed[o.benefit.key]];
  if (paths.isNotEmpty) out.add(Warn('assumed_value', data: {'paths': paths}));
  if (!isFinal) {
    for (final o in got) {
      final groups = [
        for (final c in o.benefit.when)
          if (c.ranked != null) c.ranked!,
      ];
      if (groups.isNotEmpty) {
        out.add(
          Warn(
            'ranked_provisional',
            benefit: o.benefit.key,
            data: {'group': groups.first},
          ),
        );
      }
    }
  }
  return out;
}

/// 결제 한 건의 혜택, 실적, 경고. history는 같은 카드의 다른 결제이고 저장된 혜택이 들어 있다. 엔진 설계 1.3
PaymentResult pricePayment(
  Ctx ctx,
  UserCard card,
  List<Payment> history,
  Payment p,
) {
  final prior = [
    for (final q in history)
      if (q.id != p.id && byTime(q, p) < 0) q,
  ];
  return price(ctx, card, p, buildLedger(ctx, card, prior)).result;
}

/// 저장된 혜택이 없는 결제를 결제 시각 순서로 차례로 계산한다. 엔진 설계 1.3
///
/// month를 주면 그 달 결제는 저장된 혜택이 있어도 다시 계산한다. isFinal이면 그 달 순위를 달 전체 이용액으로
/// 매긴다. 달이 끝난 순위 카드를 다시 계산할 때 쓴다. 엔진 설계 3.5
List<PaymentResult> priceMonth(
  Ctx ctx,
  UserCard card,
  List<Payment> payments, {
  DateTime? month,
  bool isFinal = false,
}) {
  final ordered = [...payments]..sort(byTime);
  Map<String, int>? finalAreas;
  if (isFinal && month != null) {
    // 다른 달 결제의 취소도 이 달 영역 이용액에서 빠질 수 있어 모든 결제를 넣는다. E55
    final totals = Ledger();
    for (final q in ordered) {
      final d = localDay(q.paidAt);
      final found = ctx.rulesOn(card.cardId, d);
      if (found != null) {
        totals.addTotals(ctx, card, found.rules, q, monthOf(d));
      }
    }
    finalAreas = Map.of(totals.area);
  }
  final ledger = Ledger();
  final results = <PaymentResult>[];
  for (var q in ordered) {
    final inMonth = month != null && monthOf(localDay(q.paidAt)) == month;
    if (q.benefits == null || inMonth) {
      final result = price(
        ctx,
        card,
        q,
        ledger,
        inMonth ? finalAreas : null,
      ).result;
      q = q.copyWith(benefits: result.benefits);
      results.add(result);
    }
    ledger.add(ctx, card, q);
  }
  return results;
}

/// 카드 한 장의 이번 달 실적 현황. 엔진 설계 2.4, 2.5
SpendStatus spendStatus(
  Ctx ctx,
  UserCard card,
  List<Payment> payments,
  DateTime month,
) {
  final ledger = buildLedger(ctx, card, payments);
  final prev = addMonths(month, -1);
  var (tier, source, prevCounted, warns) = tierOf(
    ctx,
    card,
    month,
    ledger.countedIn(prev),
    ledger.recorded(prev),
  );
  warns = [...warns];
  final thisMonth = ledger.countedIn(month) > 0 ? ledger.countedIn(month) : 0;
  final found = ctx.rulesOn(card.cardId, month);
  int? toKeep, nextTier, toNext;
  if (found != null &&
      tier != null &&
      source != 'none' &&
      source != 'unsupported') {
    final rules = found.rules;
    final (t, special) = newCardTier(card, month, rules, null, tier);
    tier = t;
    if (special) source = 'new_card';
    toKeep = t > 0 ? (t - thisMonth > 0 ? t - thisMonth : 0) : null;
    final floor = t > thisMonth ? t : thisMonth;
    final above = rules.tiers.where((x) => x > floor);
    if (above.isNotEmpty) {
      nextTier = above.reduce((a, b) => a < b ? a : b);
      toNext = nextTier - thisMonth;
    }
  }
  if (found != null) warns.addAll(cardNotes(ctx, card, found.rules, month));
  return SpendStatus(
    userCardId: card.id,
    month: month,
    counted: thisMonth,
    tier: tier,
    tierSource: source,
    prevMonthCounted: prevCounted,
    toKeep: toKeep,
    nextTier: nextTier,
    toNext: toNext,
    warnings: warns,
  );
}

/// 혜택별 한도와 공유 한도의 이번 기간 사용량과 한도. 엔진 설계 1.3
List<LimitUse> limitStatus(
  Ctx ctx,
  UserCard card,
  List<Payment> payments,
  DateTime now,
) {
  final d = localDay(now);
  final month = monthOf(d);
  final found = ctx.rulesOn(card.cardId, d);
  if (found == null) return const [];
  final rules = found.rules;
  final ledger = buildLedger(ctx, card, [
    for (final q in payments)
      if (!q.paidAt.isAfter(now)) q,
  ]);
  final prev = addMonths(month, -1);
  final (tier, _, _, _) = tierOf(
    ctx,
    card,
    month,
    ledger.countedIn(prev),
    ledger.recorded(prev),
  );
  final probe = Payment(id: 'now', userCardId: card.id, amount: 1, paidAt: now);
  final s = situationOf(ctx, card, rules, probe);
  final seen = <String>{};
  final out = <LimitUse>[];
  for (final b in rules.benefits) {
    final (t, _) = newCardTier(card, month, rules, b.key, tier ?? 0);
    for (final (ident, lim) in limitSpecs(rules, b)) {
      final key = periodKey(lim.per!, now);
      if (key == null || seen.contains(ident.id)) continue;
      seen.add(ident.id);
      final used = ledger.used(ident, key);
      final (capAmount, capCount, capBase, _) = caps(lim, t, s);
      out.add(
        LimitUse(
          key: ident.key,
          benefit: ident.kind == 'own' ? b.key : null,
          per: lim.per!,
          usedAmount: used[0],
          usedCount: used[1],
          usedBase: used[2],
          capAmount: capAmount,
          capCount: capCount,
          capBase: capBase,
        ),
      );
    }
  }
  return out;
}
