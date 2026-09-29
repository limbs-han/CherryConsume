"""결제 하나의 혜택 계산. 설계 3절과 4.4의 사용량 표."""

from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime

from cherry_core.catalog.models import Benefit, Limit, Rules

from .cond import (
    FALSE,
    TRUE,
    Situation,
    Tri,
    add_months,
    all_of,
    any_of,
    categories_match,
    check,
    check_all,
    local,
    month_of,
)
from .context import Ctx, at_tier, frac, round_money
from .models import AppliedBenefit, LimitUse, Payment, PaymentResult, SpendStatus, UserCard, Warn
from .spend import card_notes, new_card_tier, spend_parts, tier_of

SKIP_TOTALS = frozenset({"ranked", "month_total"})


def period_key(per: str, at: datetime) -> tuple | None:
    """한도 기간. txn은 결제 하나라 쌓지 않는다. period는 행사 기간 전체, lifetime은 늘 하나다. 설계 3.4"""
    d = local(at).date()
    return {
        "txn": None,
        "day": ("d", d),
        "month": ("m", d.year, d.month),
        "quarter": ("q", d.year, (d.month - 1) // 3),
        "year": ("y", d.year),
        "period": ("p",),
        "lifetime": ("l",),
    }[per]


def limit_specs(rules: Rules, b: Benefit) -> list[tuple[tuple, Limit]]:
    """혜택이 쓰는 한도마다 (이름, 실제 칸). 혜택에 직접 적은 한도는 ("own", key, 순서), 공유 한도는 ("shared", key)"""
    shared = {x.key: x for x in rules.limits}
    return [
        (("shared", lim.shared), shared[lim.shared]) if lim.shared is not None else (("own", b.key, i), lim)
        for i, lim in enumerate(b.limits)
    ]


def situation(ctx: Ctx, card: UserCard, rules: Rules, p: Payment) -> Situation:
    s = ctx.situation(card, p)
    s.defaults = {o.key: o.default for o in rules.options}
    return s


def negate(t: Tri) -> Tri:
    """제외 조건을 대상 쪽 판정으로 바꾼다. 제외에 걸리면 거짓, 모르면 모름이다. 설계 2.1"""
    return FALSE if t[0] is True else TRUE if t[0] is False else t


def benefit_match(rules: Rules, b: Benefit, s: Situation) -> Tri:
    """행사 기간, 대상, 공통 제외, when 조건. 구간은 따로 본다. 설계 3.2의 1~4"""
    if (b.valid_from and s.day < b.valid_from) or (b.valid_until and s.day > b.valid_until):
        return FALSE
    t = b.target
    hit = (
        TRUE
        if t.all
        else any_of([TRUE if s.merchant in t.merchants else FALSE, categories_match(s.category, t.categories)])
    )
    if hit[0] is False or s.merchant in t.exclude_merchants:
        return FALSE
    parts = [hit, negate(categories_match(s.category, t.exclude_categories))]
    be = rules.benefit_exclusions
    # 대상이 이 결제의 업종을 직접 적었으면 공통 제외 업종보다 우선한다. 가맹점만 적었으면 결제 업종으로 공통 제외를 본다.
    # 이마트 5% 혜택으로 이마트에서 산 상품권은 뺀다. 2026-09-29 사용자가 정했다. 설계 3.2의 3
    if categories_match(s.category, t.categories)[0] is not True:
        parts.append(negate(categories_match(s.category, be.categories)))
    parts += [negate(check(w, s)) for w in be.when_any]
    s.area = b.area or b.key
    parts.append(check_all(b.when, s))
    return all_of(parts)


def ranked_areas(rules: Rules) -> dict[str, dict[str, list[Benefit]]]:
    """순위 그룹마다 영역과 그 영역의 혜택. 영역은 area, 없으면 혜택 key. 파일에 적힌 순서다"""
    out: dict[str, dict[str, list[Benefit]]] = {}
    for b in rules.benefits:
        for c in b.when:
            if c.ranked is not None:
                out.setdefault(c.ranked, {}).setdefault(b.area or b.key, []).append(b)
    return out


@dataclass
class Ledger:
    """사용량 표. 저장된 결제를 한 번 훑어 한도 사용량, 순위 영역 이용액, 달 합계, 달별 실적을 모은다. 설계 4.4

    child()로 만든 표는 부모 위에 쌓아 두는 임시 표다. 결제 하나를 계산하는 동안 쓴 한도를 부모를 바꾸지 않고 센다.
    """

    use: dict = field(default_factory=lambda: defaultdict(lambda: [0, 0, 0]))
    area: dict = field(default_factory=lambda: defaultdict(int))
    month_base: dict = field(default_factory=lambda: defaultdict(int))
    counted: dict = field(default_factory=lambda: defaultdict(int))
    seen: set = field(default_factory=set)
    parent: Ledger | None = None

    def _sum(self, name: str, key) -> int:
        own = getattr(self, name).get(key, 0)
        return own + (self.parent._sum(name, key) if self.parent else 0)

    def used(self, ident: tuple, key: tuple) -> list[int]:
        own = self.use.get((ident, key), [0, 0, 0])
        up = self.parent.used(ident, key) if self.parent else [0, 0, 0]
        return [a + b for a, b in zip(up, own)]

    def area_spend(self, group: str, area: str, month: date) -> int:
        return self._sum("area", (group, area, month))

    def month_total(self, key: str, month: date) -> int:
        return self._sum("month_base", (key, month))

    def counted_in(self, month: date) -> int:
        return self._sum("counted", month)

    def recorded(self, month: date) -> bool:
        return month in self.seen or (self.parent is not None and self.parent.recorded(month))

    def child(self) -> Ledger:
        return Ledger(parent=self)

    def add_benefit(self, rules: Rules, b: Benefit, got: AppliedBenefit, at: datetime) -> None:
        idents = limit_specs(rules, b)
        if b.reward.basis == "month_total":
            idents.append((("given", b.key), Limit(per="month", amount=0)))
        for ident, lim in idents:
            key = period_key(lim.per, at)
            if key is None:
                continue
            u = self.use[(ident, key)]
            u[0] += got.amount
            u[1] += 1 if got.amount > 0 else 0
            u[2] += got.base

    def add(self, ctx: Ctx, card: UserCard, p: Payment) -> None:
        """저장된 결제 한 건을 표에 더한다"""
        day = local(p.paid_at).date()
        month = month_of(day)
        self.seen.add(month)
        found = ctx.rules_on(card.card_id, day)
        if found is None:
            return
        rules = found[1]
        parts, _ = spend_parts(ctx, card, p, rules, p.benefits or [])
        for part in parts:
            self.counted[part.month] += part.amount
        by_key = {b.key: b for b in rules.benefits}
        for got in p.benefits or []:
            if got.key in by_key:
                self.add_benefit(rules, by_key[got.key], got, p.paid_at)
        if p.amount > p.cancelled_amount:
            self.add_totals(ctx, card, rules, p, month)

    def add_totals(self, ctx: Ctx, card: UserCard, rules: Rules, p: Payment, month: date) -> None:
        """순위 영역 이용액과 달 합계 혜택의 대상 이용액. 설계 3.4, 3.5"""
        s = situation(ctx, card, rules, p)
        s.skip = SKIP_TOTALS
        for b in rules.benefits:
            if b.reward.basis == "month_total" and benefit_match(rules, b, s)[0] is True:
                self.month_base[(b.key, month)] += s.amount
        for group, areas in ranked_areas(rules).items():
            for area, members in areas.items():
                if any(benefit_match(rules, b, s)[0] is True for b in members):
                    self.area[(group, area, month)] += s.amount


def build_ledger(ctx: Ctx, card: UserCard, payments: list[Payment]) -> Ledger:
    ledger = Ledger()
    for p in sorted(payments, key=lambda q: (q.paid_at, q.id)):
        ledger.add(ctx, card, p)
    return ledger


def reward_amount(ctx: Ctx, b: Benefit, base: int, tier: int) -> int:
    """결제액 base에 대한 보상 단위의 금액. 원 미만과 반올림은 reward.round를 따른다. 설계 3.3"""
    r = b.reward
    if r.rate is not None:
        x = frac(base) * frac(at_tier(r.rate, tier)) / 100
    elif r.fixed is not None:
        x = frac(at_tier(r.fixed, tier) or 0) if base > 0 else frac(0)
    elif r.per_unit is not None:
        x = frac((base // r.per_unit.unit) * r.per_unit.amount)
    elif ctx.fuel_price is not None:
        x = frac(base) * r.per_liter / ctx.fuel_price
    else:
        return 0
    return round_money(x, r.round)


def pre_discount(b: Benefit, net: int, tier: int) -> int:
    """현장할인의 할인 전 금액을 되짚는다. 설계 3.6"""
    r = b.reward
    if r.rate is not None:
        return math.ceil(frac(net) / (1 - frac(at_tier(r.rate, tier)) / 100))
    return net + int(at_tier(r.fixed, tier) or 0)


def caps(lim: Limit, tier: int, s: Situation) -> tuple[int | None, int | None, int | None, frozenset]:
    """한도 칸의 (금액, 횟수, 결제액, 모르는 것). 구간표와 adjust를 적용한다.
    adjust 조건이 모름이면 적용하지 않고 무엇을 모르는지 돌려준다. 설계 3.1"""
    amount, count, base = at_tier(lim.amount, tier), at_tier(lim.count, tier), at_tier(lim.base, tier)
    needs: frozenset = frozenset()
    for a in lim.adjust:
        hit = check(a.when, s)
        if hit[0] is None:
            needs |= hit[1]
        if hit[0] is not True:
            continue
        given = a.model_fields_set
        if "amount" in given:
            amount = at_tier(a.amount, tier)
        if "count" in given:
            count = at_tier(a.count, tier)
        if "base" in given:
            base = at_tier(a.base, tier)
        if a.multiply is not None and amount is not None:
            amount = math.floor(amount * frac(a.multiply))
        if a.add is not None and amount is not None:
            amount += a.add
    return amount, count, base, needs


@dataclass
class Offer:
    """혜택 하나를 이 결제에 계산해 본 결과. base는 혜택 계산에 넣은 결제액이다"""

    benefit: Benefit
    amount: int
    value: int
    base: int
    limited: bool
    exhausted: bool = False
    needs: frozenset = frozenset()

    def applied(self) -> AppliedBenefit:
        return AppliedBenefit(key=self.benefit.key, amount=self.amount, value=self.value, base=self.base)


def offer(
    ctx: Ctx, rules: Rules, b: Benefit, s: Situation, tier: int, ledger: Ledger, room: int, total: int = 0
) -> Offer:
    """한도 안에서 이 혜택이 이 결제에 줄 수 있는 금액. room은 이 묶음에서 아직 혜택에 쓰지 않은 결제액이고
    total은 달 합계 혜택이면 이 결제까지의 이번 달 대상 이용액이다.

    limited는 어느 한도든 금액을 줄였는지, exhausted는 날, 달, 기간 한도가 줄였는지다. 건당 한도는
    "한도를 다 썼다"가 아니라서 exhausted에 넣지 않는다. 설계 5.1
    """
    onsite = b.reward.type == "onsite_discount"
    pre = pre_discount(b, room, tier) if onsite else room
    base, limited, exhausted = pre, False, False
    specs = [(ident, lim, caps(lim, tier, s)) for ident, lim in limit_specs(rules, b)]
    needs = frozenset().union(*(c[3] for _, _, c in specs))
    usage = {
        ident: ledger.used(ident, key) if (key := period_key(lim.per, s.at)) else [0, 0, 0] for ident, lim, _ in specs
    }
    for ident, lim, (_, count, cap_base, _) in specs:
        if count is not None and usage[ident][1] >= count:
            return Offer(b, 0, 0, 0, True, lim.per != "txn", needs)
        if cap_base is not None and base > cap_base - usage[ident][2]:
            base, limited = max(cap_base - usage[ident][2], 0), True
            exhausted = exhausted or lim.per != "txn"
    if b.reward.basis == "month_total":
        given = ledger.used(("given", b.key), period_key("month", s.at))[0]
        amount = max(reward_amount(ctx, b, total, tier) - given, 0)
    elif onsite and not limited:
        amount = pre - room if b.reward.rate is not None else reward_amount(ctx, b, base, tier)
    else:
        amount = reward_amount(ctx, b, base, tier)
    for ident, lim, (cap_amount, _, _, _) in specs:
        if cap_amount is not None and amount > cap_amount - usage[ident][0]:
            amount, limited = max(cap_amount - usage[ident][0], 0), True
            exhausted = exhausted or lim.per != "txn"
    if amount == 0:
        base = 0
    elif onsite and b.reward.rate is not None:
        base = room + amount  # 현장할인은 기록 금액에 실제 할인액을 더한 것이 할인 전 금액이다. 설계 3.6
    elif limited and b.reward.rate is not None and b.reward.basis == "txn":
        base = min(base, math.ceil(frac(amount) * 100 / frac(at_tier(b.reward.rate, tier))))
    value = amount if b.reward.type != "points" else math.floor(amount * ctx.point_value.get(b.reward.program, frac(1)))
    return Offer(b, amount, value, base, limited, exhausted, needs)


def choose(
    ctx: Ctx, rules: Rules, s: Situation, candidates: dict[str, list[tuple[Benefit, int, int]]], ledger: Ledger
) -> tuple[list[Offer], set[str], dict[str, frozenset]]:
    """중복 묶음마다 혜택을 고른다. 설계 3.7. candidates는 묶음 key마다 (혜택, 구간, 달 합계)이고 파일 순서다.
    (받은 혜택, 기간 한도로 줄어든 혜택 key, 혜택마다 한도 조건에서 모르는 것)을 돌려준다"""
    specs = {st.key: st for st in rules.stacks}
    scratch = ledger.child()
    got: list[Offer] = []
    exhausted: set[str] = set()
    needs: dict[str, frozenset] = {}
    for stack, members in candidates.items():
        st = specs.get(stack)
        pick, spill = (st.pick, st.spill) if st else ("best", "none")
        if pick == "priority":
            rank = {k: i for i, k in enumerate(st.order)}
            members = sorted(members, key=lambda m: rank.get(m[0].key, len(rank)))
        room, left = s.amount, list(members)
        while left and room > 0:
            offers = [offer(ctx, rules, b, s, tier, scratch, room, total) for b, tier, total in left]
            exhausted |= {o.benefit.key for o in offers if o.exhausted}
            for o in offers:
                if o.needs:
                    needs[o.benefit.key] = needs.get(o.benefit.key, frozenset()) | o.needs
            live = [o for o in offers if o.amount > 0]
            if not live:
                break
            best = live[0] if pick == "priority" else max(live, key=lambda o: (o.value, -offers.index(o)))
            got.append(best)
            scratch.add_benefit(rules, best.benefit, best.applied(), s.at)
            if spill != "split":
                break
            room -= best.base
            left = [m for m in left if m[0].key != best.benefit.key]
    return got, exhausted, needs


@dataclass
class Priced:
    """price_payment의 중간 결과. 추천이 못 받는 혜택과 조건부 혜택을 만들 때 쓴다"""

    result: PaymentResult
    rules: Rules | None = None
    tier: int = 0
    unknown: dict[str, frozenset] = field(default_factory=dict)
    tier_short: dict[str, int] = field(default_factory=dict)


def price(ctx: Ctx, card: UserCard, p: Payment, ledger: Ledger, final_areas: dict | None = None) -> Priced:
    """결제 한 건의 혜택과 실적. ledger는 이 결제보다 앞선 결제들의 사용량 표다"""
    day = local(p.paid_at).date()
    month = month_of(day)
    found = ctx.rules_on(card.card_id, day)
    if found is None:
        return Priced(PaymentResult(payment_id=p.id, warnings=[Warn(code="no_revision")]))
    rev, rules = found
    warns: list[Warn] = []
    if day < rev.effective_from:
        warns.append(Warn(code="revision_estimated", data={"effective_from": rev.effective_from.isoformat()}))
    prev = add_months(month, -1)
    base_tier, _, _, tier_warns = tier_of(ctx, card, month, ledger.counted_in(prev), ledger.recorded(prev))
    warns += tier_warns
    base_tier = base_tier or 0
    s = situation(ctx, card, rules, p)
    net = s.amount
    got: list[Offer] = []
    unknown: dict[str, frozenset] = {}
    tier_short: dict[str, int] = {}
    exhausted: set[str] = set()
    limit_needs: dict[str, frozenset] = {}
    if net > 0:
        top_tier, _ = new_card_tier(card, month, rules, None, base_tier)
        s.top_areas = top_areas(rules, s, month, top_tier, ledger, final_areas)
        candidates: dict[str, list[tuple[Benefit, int, int]]] = {}
        for b in rules.benefits:
            tier, _ = new_card_tier(card, month, rules, b.key, base_tier)
            total = 0
            if b.reward.basis == "month_total":
                s.skip = frozenset({"month_total"})
                mine = net if benefit_match(rules, b, s)[0] is True else 0
                total = ledger.month_total(b.key, month) + mine
                s.skip, s.month_total = frozenset(), total
            if b.reward.type == "onsite_discount":
                s.amount = pre_discount(b, net, tier)
            hit = benefit_match(rules, b, s)
            s.amount, s.month_total = net, None
            if hit[0] is False:
                continue
            lo = b.tiers.start if b.tiers and b.tiers.start is not None else rules.tiers[0]
            hi = b.tiers.end if b.tiers and b.tiers.end is not None else rules.tiers[-1]
            if tier > hi:
                continue
            if tier < lo:
                waived = check(b.tiers.waived_when, s) if b.tiers.waived_when else FALSE
                if waived[0] is False:
                    if hit[0] is True:
                        tier_short[b.key] = lo
                    continue
                if waived[0] is None:
                    tier_short[b.key] = lo
                    hit = all_of([hit, waived])
            if hit[0] is None:
                unknown[b.key] = hit[1]
                continue
            candidates.setdefault(b.stack, []).append((b, tier, total))
        got, exhausted, limit_needs = choose(ctx, rules, s, candidates, ledger)
    applied = [o.applied() for o in got]
    parts, spend_warns = spend_parts(ctx, card, p, rules, applied)
    unknown = {**unknown, **limit_needs}
    warns += spend_warns + notes(ctx, card, got, unknown, tier_short, exhausted, final_areas is not None)
    result = PaymentResult(payment_id=p.id, benefits=applied, spend=parts, warnings=warns)
    return Priced(result, rules, base_tier, unknown, tier_short)


def top_areas(
    rules: Rules, s: Situation, month: date, tier: int, ledger: Ledger, final: dict | None
) -> dict[str, set[str]]:
    """순위 그룹마다 이번 달 이용액 상위 영역. 이 결제를 포함한다. final이 있으면 달 전체 이용액으로 매긴다. 설계 3.5"""
    groups = ranked_areas(rules)
    if not groups:
        return {}
    skip, s.skip = s.skip, SKIP_TOTALS
    tops = {r.key: r.top for r in rules.ranked}
    out: dict[str, set[str]] = {}
    for group, areas in groups.items():
        spend = []
        for i, (area, members) in enumerate(areas.items()):
            if final is not None:
                total = final.get((group, area, month), 0)
            else:
                mine = s.amount if any(benefit_match(rules, b, s)[0] is True for b in members) else 0
                total = ledger.area_spend(group, area, month) + mine
            spend.append((-total, i, area))
        top = at_tier(tops[group], tier) or 0
        out[group] = {area for total, _, area in sorted(spend)[:top] if total < 0}
    s.skip = skip
    return out


def notes(
    ctx: Ctx,
    card: UserCard,
    got: list[Offer],
    unknown: dict[str, frozenset],
    tier_short: dict[str, int],
    exhausted: set[str],
    final: bool,
) -> list[Warn]:
    """결제 결과에 붙는 경고. 설계 5절"""
    out = [Warn(code="tier_not_met", benefit=k, data={"required": lo}) for k, lo in tier_short.items()]
    out += [Warn(code="limit_exhausted", benefit=k) for k in sorted(exhausted)]
    if unknown:
        needs = sorted({n for ns in unknown.values() for n in ns})
        out.append(Warn(code="needs_input", data={"needs": [list(n) for n in needs], "benefits": sorted(unknown)}))
    sentences = [u for o in got for u in o.benefit.unmodeled]
    if sentences:
        out.append(Warn(code="check_conditions", data={"sentences": sentences}))
    assumed = ctx.assumed.get(card.card_id, {})
    paths = [path for o in got for path in assumed.get(o.benefit.key, [])]
    if paths:
        out.append(Warn(code="assumed_value", data={"paths": paths}))
    if not final:
        for o in got:
            groups = [c.ranked for c in o.benefit.when if c.ranked]
            if groups:
                out.append(Warn(code="ranked_provisional", benefit=o.benefit.key, data={"group": groups[0]}))
    return out


def price_payment(ctx: Ctx, card: UserCard, history: list[Payment], p: Payment) -> PaymentResult:
    """결제 한 건의 혜택, 실적, 경고. history는 같은 카드의 다른 결제이고 저장된 혜택이 들어 있다. 설계 1.3"""
    prior = [q for q in history if q.id != p.id and (q.paid_at, q.id) < (p.paid_at, p.id)]
    return price(ctx, card, p, build_ledger(ctx, card, prior)).result


def price_month(
    ctx: Ctx, card: UserCard, payments: list[Payment], month: date | None = None, final: bool = False
) -> list[PaymentResult]:
    """저장된 혜택이 없는 결제를 결제 시각 순서로 차례로 계산한다. 설계 1.3

    month를 주면 그 달 결제는 저장된 혜택이 있어도 다시 계산한다. final이면 그 달 순위를 달 전체 이용액으로
    매긴다. 달이 끝난 순위 카드를 다시 계산할 때 쓴다. 설계 3.5
    """
    ordered = sorted(payments, key=lambda q: (q.paid_at, q.id))
    final_areas = None
    if final and month is not None:
        totals = Ledger()
        for q in ordered:
            day = local(q.paid_at).date()
            found = ctx.rules_on(card.card_id, day)
            if month_of(day) == month and found and q.amount > q.cancelled_amount:
                totals.add_totals(ctx, card, found[1], q, month)
        final_areas = dict(totals.area)
    ledger = Ledger()
    results: list[PaymentResult] = []
    for q in ordered:
        if q.benefits is None or (month is not None and month_of(local(q.paid_at).date()) == month):
            result = price(ctx, card, q, ledger, final_areas).result
            q = q.model_copy(update={"benefits": result.benefits})
            results.append(result)
        ledger.add(ctx, card, q)
    return results


def spend_status(ctx: Ctx, card: UserCard, payments: list[Payment], month: date) -> SpendStatus:
    """카드 한 장의 이번 달 실적 현황. 설계 2.4, 2.5"""
    ledger = build_ledger(ctx, card, payments)
    prev = add_months(month, -1)
    tier, source, prev_counted, warns = tier_of(ctx, card, month, ledger.counted_in(prev), ledger.recorded(prev))
    this = max(ledger.counted_in(month), 0)
    found = ctx.rules_on(card.card_id, month)
    to_keep = next_tier = to_next = None
    if found is not None and tier is not None and source not in ("none", "unsupported"):
        rules = found[1]
        tier, special = new_card_tier(card, month, rules, None, tier)
        source = "new_card" if special else source
        to_keep = max(tier - this, 0) if tier > 0 else None
        above = [t for t in rules.tiers if t > max(tier, this)]
        if above:
            next_tier = min(above)
            to_next = next_tier - this
    if found is not None:
        warns += card_notes(ctx, card, found[1], month)
    return SpendStatus(
        user_card_id=card.id,
        month=month,
        counted=this,
        tier=tier,
        tier_source=source,
        prev_month_counted=prev_counted,
        to_keep=to_keep,
        next_tier=next_tier,
        to_next=to_next,
        warnings=warns,
    )


def limit_status(ctx: Ctx, card: UserCard, payments: list[Payment], now: datetime) -> list[LimitUse]:
    """혜택별 한도와 공유 한도의 이번 기간 사용량과 한도. 설계 1.3"""
    day = local(now).date()
    month = month_of(day)
    found = ctx.rules_on(card.card_id, day)
    if found is None:
        return []
    rules = found[1]
    ledger = build_ledger(ctx, card, [q for q in payments if q.paid_at <= now])
    prev = add_months(month, -1)
    tier, _, _, _ = tier_of(ctx, card, month, ledger.counted_in(prev), ledger.recorded(prev))
    probe = Payment(id="now", user_card_id=card.id, amount=1, paid_at=now)
    s = situation(ctx, card, rules, probe)
    seen: set = set()
    out = []
    for b in rules.benefits:
        t, _ = new_card_tier(card, month, rules, b.key, tier or 0)
        for ident, lim in limit_specs(rules, b):
            key = period_key(lim.per, now)
            if key is None or ident in seen:
                continue
            seen.add(ident)
            used = ledger.used(ident, key)
            cap_amount, cap_count, cap_base, _ = caps(lim, t, s)
            out.append(
                LimitUse(
                    key=ident[1],
                    benefit=b.key if ident[0] == "own" else None,
                    per=lim.per,
                    used_amount=used[0],
                    used_count=used[1],
                    used_base=used[2],
                    cap_amount=cap_amount,
                    cap_count=cap_count,
                    cap_base=cap_base,
                )
            )
    return out
