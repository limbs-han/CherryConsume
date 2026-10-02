"""실적 계산. 설계 2절."""

from __future__ import annotations

import math
from datetime import date

from cherry_core.catalog.models import Rules

from .cond import add_months, categories_match, check, local, month_of
from .context import Ctx, frac
from .models import AppliedBenefit, Payment, SpendPart, UserCard, Warn


def applied_ratio(rules: Rules, benefits: list[AppliedBenefit]) -> object:
    """받은 혜택 가운데 가장 큰 실적 제외 비율. 한도가 차서 0원이 된 혜택은 받은 것으로 보지 않는다"""
    ratio = frac(0)
    by_key = {b.key: b for b in rules.benefits}
    for got in benefits:
        if got.value > 0 and got.key in by_key:
            own = by_key[got.key].exclude_applied
            ratio = max(ratio, frac(own if own is not None else rules.spend.exclude_applied))
    return ratio


def spend_parts(
    ctx: Ctx,
    card: UserCard,
    p: Payment,
    rules: Rules,
    benefits: list[AppliedBenefit],
    before: list[AppliedBenefit] | None = None,
) -> tuple[list[SpendPart], list[Warn]]:
    """결제 한 건이 실적에 넣는 금액과 달. 설계 2.2, 2.3. 실적에서 빠지면 그 이유를 경고로 돌려준다

    취소한 결제면 benefits는 남은 금액이 받는 혜택이고 before는 취소하지 않았다면 받았을 혜택이다. 결제한 달의 처음 실적은 before의
    비율로, 남은 금액의 실적은 benefits의 비율로 센다. 취소 뒤 혜택이 0원이라고 처음 실적을 원금으로 다시 세면
    결제한 달 실적이 늘어 다음 달 구간이 올랐다. 설계 문서 6.5, E5
    """
    s = rules.spend
    paid_month = month_of(local(p.paid_at).date())
    category = ctx.category(p)
    if p.region not in s.regions:
        return [], [Warn(code="not_counted_toward_spend", data={"reason": "region"})]
    excluded, needs = categories_match(category, s.exclude_categories)
    if excluded is not False:
        warns = [Warn(code="not_counted_toward_spend", data={"reason": "category"})]
        if excluded is None:
            warns.append(Warn(code="needs_input", data={"needs": sorted(needs)}))
        return [], warns
    if s.interest_free == "exclude" and p.interest_free:
        return [], [Warn(code="not_counted_toward_spend", data={"reason": "interest_free"})]

    ratio = applied_ratio(rules, benefits)
    first = applied_ratio(rules, before) if p.cancelled_amount and before is not None else ratio
    counted = math.floor(p.amount * (1 - first))
    warns = [Warn(code="not_counted_toward_spend", data={"reason": "benefit_applied"})] if counted == 0 else []

    offset = max((n for cat, n in s.month_offset.items() if categories_match(category, [cat])[0] is True), default=0)
    start = add_months(paid_month, offset)
    parts: list[SpendPart] = []
    if s.installment == "per_installment_month" and p.installment_months > 1:
        each = counted // p.installment_months
        for i in range(p.installment_months):
            last = i == p.installment_months - 1
            parts.append(SpendPart(month=add_months(start, i), amount=counted - each * i if last else each))
    else:
        parts.append(SpendPart(month=start, amount=counted))

    minus = counted - math.floor((p.amount - p.cancelled_amount) * (1 - ratio)) if p.cancelled_amount else 0
    # 남은 금액이 혜택을 잃어 처음보다 실적이 커지면 취소로 실적을 늘려야 하는지 카드사 문구가 없다. 늘리지 않는다
    # 모르면 부풀리지 않는 쪽이다. 설계 3.1과 같다. 확인 필요. 2026-10-02 위험 검토
    if minus > 0:
        use = s.cancellation
        for o in s.cancellation_overrides:
            if check(o.when, ctx.situation(card, p))[0] is True:
                use = o.use
        month = month_of(local(p.cancelled_at).date()) if use == "cancel_month" and p.cancelled_at else start
        parts.append(SpendPart(month=month, amount=-minus))
    return parts, warns


def tier_of(
    ctx: Ctx, card: UserCard, month: date, prev_counted: int, prev_recorded: bool
) -> tuple[int | None, str, int | None, list[Warn]]:
    """이번 달 기본 구간. (구간 하한, 근거, 지난달 인정 실적, 경고). 설계 2.4

    prev_counted는 지난달 인정 실적, prev_recorded는 지난달 결제가 한 건이라도 기록됐는지다.
    """
    found = ctx.rules_on(card.card_id, month)
    if found is None:
        return None, "none", None, []
    rules = found[1]
    if rules.spend.basis == "none":
        return 0, "none", None, []
    if rules.spend.basis == "billing_cycle":
        return 0, "unsupported", None, [Warn(code="spend_basis_unsupported")]
    prev = max(prev_counted, 0)
    source, warns = "prev_month", []
    registered_now = card.registered_on is not None and month_of(card.registered_on) == month
    if registered_now and not prev_recorded:
        if card.assumed_prev_month_spend is not None:
            prev, source = card.assumed_prev_month_spend, "assumed"
        else:
            prev, warns = 0, [Warn(code="no_prev_month_data")]
    tier = max(t for t in rules.tiers if t <= prev)
    return tier, source, prev, warns


def new_card_tier(card: UserCard, month: date, rules: Rules, benefit_key: str | None, base: int) -> tuple[int, bool]:
    """신규 발급 특례 기간이면 특례 구간과 기본 구간 중 큰 쪽. (구간, 특례를 썼는지). 설계 2.4의 3"""
    nc = rules.new_card
    if nc is None or card.started_on is None:
        return base, False
    start = month_of(card.started_on)
    if not (start <= month <= add_months(start, 1)):
        return base, False
    special = nc.tier_by_benefit.get(benefit_key, nc.tier) if benefit_key else nc.tier
    return max(base, special), special > base


def card_notes(ctx: Ctx, card: UserCard, rules: Rules, month: date) -> list[Warn]:
    """카드 전체에 해당하는 문장 조건, 가정한 값, 고르지 않은 옵션. 설계 5.2, 5.3, 3.8"""
    out: list[Warn] = []
    sentences = rules.unmodeled + rules.benefit_exclusions.unmodeled
    if sentences:
        out.append(Warn(code="check_conditions", data={"sentences": sentences}))
    paths = ctx.assumed.get(card.card_id, {}).get(None)
    if paths:
        out.append(Warn(code="assumed_value", data={"paths": paths}))
    last_day = add_months(month, 1)
    picks = sorted((p for p in card.options if p.effective_from < last_day), key=lambda p: p.effective_from)
    chosen_now = {p.option: p.choice for p in picks}
    for o in rules.options:
        chosen = chosen_now.get(o.key, o.default)
        if chosen is None:
            out.append(Warn(code="needs_input", data={"needs": [["option", o.key]]}))
        elif chosen in o.unsupported:
            out.append(Warn(code="option_unsupported", data={"option": o.key, "choice": chosen}))
    return out
