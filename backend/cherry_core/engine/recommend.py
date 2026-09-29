"""추천, 못 받는 혜택, 조건부 혜택, 한도 현황. 설계 4절."""

from __future__ import annotations

from datetime import datetime

from cherry_core.catalog.models import Condition

from .cond import local, month_of
from .context import Ctx
from .models import (
    ConditionalBenefit,
    LockedBenefit,
    OptionPick,
    Payment,
    Query,
    Recommendation,
    UserCard,
    Warn,
)
from .price import Ledger, Priced, build_ledger, offer, price, situation

DEFAULT_AMOUNT = 10_000


def query_payment(ctx: Ctx, card: UserCard, q: Query, now: datetime) -> Payment:
    """추천 질문으로 만든 가상의 결제. 설계 4.1"""
    return Payment(
        id="query",
        user_card_id=card.id,
        amount=q.amount or DEFAULT_AMOUNT,
        paid_at=now,
        merchant=q.merchant,
        category=q.category,
        channel=q.channel or "offline",
        region=q.region or "domestic",
        payment_method=q.payment_method or card.last_payment_method or "physical_card",
    )


def payment_methods_in(conditions: list[Condition]) -> set[str]:
    out: set[str] = set()
    for c in conditions:
        out |= set(c.payment or [])
        for sub in c.any_of or []:
            out |= payment_methods_in([sub])
    return out


def conditional(ctx: Ctx, card: UserCard, p: Payment, ledger: Ledger, base: Priced) -> list[ConditionalBenefit]:
    """다른 값이면 더 받는 혜택. 설계 4.3, 작업 001 설계 3.3

    결제수단은 결제 직전에 고를 수 있어 알고 있어도 조건에 적힌 다른 결제수단으로 바꿔 본다.
    사실, 옵션, 업종은 모를 때만 본다. 바꿔 볼 것이 있을 때만 다시 계산한다. 설계 4.4의 3
    """
    if base.rules is None:
        return []
    rules = base.rules
    trials: list[tuple[dict, UserCard, Payment]] = []
    methods = set().union(*(payment_methods_in(b.when) for b in rules.benefits)) - {p.payment_method}
    trials += [({"payment_method": m}, card, p.model_copy(update={"payment_method": m})) for m in sorted(methods)]
    for need in sorted({n for ns in base.unknown.values() for n in ns}):
        kind = need[0]
        if kind == "fact":
            key = need[1]
            value = local(p.paid_at).month if key == "birth_month" else True
            trials.append(({"fact": key}, card.model_copy(update={"facts": {**card.facts, key: value}}), p))
        elif kind == "option":
            option = next(o for o in rules.options if o.key == need[1])
            for ch in option.choices:
                pick = OptionPick(option=option.key, choice=ch.key, effective_from=local(p.paid_at).date())
                trials.append(
                    (
                        {"option": option.key, "choice": ch.key},
                        card.model_copy(update={"options": [*card.options, pick]}),
                        p,
                    )
                )
        elif kind == "category":
            trials += [
                ({"category": c}, card, p.model_copy(update={"category": c})) for c in ctx.children.get(need[1], [])
            ]
    out: list[ConditionalBenefit] = []
    before = {b.key: b.value for b in base.result.benefits}
    for needs_given, c2, p2 in trials:
        after = price(ctx, c2, p2, ledger).result
        extra = after.value - base.result.value
        if extra > 0:
            gains = {b.key: b.value - before.get(b.key, 0) for b in after.benefits}
            key = max(gains, key=lambda k: gains[k])
            out.append(ConditionalBenefit(user_card_id=card.id, benefit=key, needs=needs_given, extra=extra))
    return sorted(out, key=lambda c: -c.extra)


def locked(ctx: Ctx, card: UserCard, p: Payment, ledger: Ledger, base: Priced, counted_now: int) -> list[LockedBenefit]:
    """대상과 조건은 맞는데 구간이 모자란 혜택. 다음 달 한도가 비어 있다고 보고 계산한다. E37"""
    if base.rules is None:
        return []
    rules = base.rules
    s = situation(ctx, card, rules, p)
    out = []
    for key, required in base.tier_short.items():
        b = next(x for x in rules.benefits if x.key == key)
        o = offer(ctx, rules, b, s, required, Ledger(), s.amount, s.amount)
        if o.value > 0:
            out.append(
                LockedBenefit(
                    user_card_id=card.id,
                    benefit=key,
                    required_tier=required,
                    remaining_this_month=max(required - counted_now, 0),
                    value_if_unlocked=o.value,
                )
            )
    return out


def recommend(
    ctx: Ctx, cards: list[UserCard], payments: dict[str, list[Payment]], queries: list[Query], now: datetime
) -> list[list[Recommendation]]:
    """질문마다 보유 카드의 추천 순위. 사용량 표는 카드마다 한 번만 만든다. 설계 4절"""
    from .price import spend_status

    month = month_of(local(now).date())
    prepared = []
    for card in cards:
        if card.removed:
            continue
        history = payments.get(card.id, [])
        ledger = build_ledger(ctx, card, [q for q in history if q.paid_at <= now])
        status = spend_status(ctx, card, history, month)
        prepared.append((card, ledger, status))
    answers = []
    for q in queries:
        rows = []
        for card, ledger, status in prepared:
            p = query_payment(ctx, card, q, now)
            base = price(ctx, card, p, ledger)
            warns = list(base.result.warnings) + [w for w in status.warnings if w.code == "option_unsupported"]
            if q.amount is None:
                warns.append(Warn(code="default_amount_used"))
            rows.append(
                Recommendation(
                    user_card_id=card.id,
                    card_id=card.card_id,
                    value=base.result.value,
                    benefits=base.result.benefits,
                    counted=any(part.amount > 0 for part in base.result.spend),
                    to_keep=status.to_keep,
                    to_next=status.to_next,
                    locked=locked(ctx, card, p, ledger, base, status.counted),
                    conditional=conditional(ctx, card, p, ledger, base),
                    warnings=warns,
                )
            )
        rows.sort(key=order)
        answers.append(rows)
    return answers


def order(r: Recommendation) -> tuple:
    """기대 혜택, 실적이 모자란 카드, 카드 id 순. 설계 4.2"""
    keep = r.to_keep if r.counted and r.to_keep else None
    nxt = r.to_next if r.counted and r.to_next else None
    return (-r.value, keep is None, keep or 0, nxt is None, nxt or 0, r.card_id)
