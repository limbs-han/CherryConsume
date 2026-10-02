"""결제를 DB에서 읽어 엔진 모양으로 바꾸고, 가게 이름으로 가맹점을 찾는다. 작업 005 설계 5b절"""

from __future__ import annotations

import os
import time
import uuid
from datetime import date, datetime

import psycopg

from cherry_core.engine.cond import add_months, local, month_of
from cherry_core.engine.models import AppliedBenefit, Payment, PaymentResult, UserCard
from cherry_core.engine.price import ranked_areas

from .catalog_sync import alias_key

PAYMENTS = """
SELECT t.*,
       coalesce(json_agg(json_build_object('key', b.benefit_key, 'amount', b.amount, 'value', b.value,
                                           'base', b.base_amount))
                FILTER (WHERE b.benefit_key IS NOT NULL), '[]') AS benefits
FROM transactions t LEFT JOIN transaction_benefits b ON b.transaction_id = t.id
WHERE t.user_card_id = ANY(%s) AND t.deleted_at IS NULL
GROUP BY t.id
ORDER BY t.paid_at, t.id
"""


def to_payment(row: dict) -> Payment:
    return Payment(
        id=str(row["id"]),
        user_card_id=str(row["user_card_id"]),
        amount=row["amount"],
        paid_at=row["paid_at"],
        merchant=row["merchant_key"],
        category=row["category_code"],
        channel=row["channel"],
        region=row["region"],
        installment_months=row["installment_months"],
        interest_free=row["interest_free_installment"],
        payment_method=row["payment_method"],
        billing=row["billing"],
        cancelled_amount=row["cancelled_amount"],
        cancelled_at=row["cancelled_at"],
        benefits=[AppliedBenefit(**b) for b in row["benefits"]],
    )


def load_payments(conn: psycopg.Connection, user_card_ids: list[str]) -> dict[str, list[Payment]]:
    """카드마다 지운 것을 뺀 모든 결제와 저장된 혜택. 엔진에 한도 기간 전체를 넘긴다. 작업 002 설계

    ponytail: 카드 한 장의 결제가 수천 건이 되면 한도 기간으로 줄인다
    """
    out: dict[str, list[Payment]] = {i: [] for i in user_card_ids}
    for row in conn.execute(PAYMENTS, (user_card_ids,)).fetchall():
        out[str(row["user_card_id"])].append(to_payment(row))
    return out


def new_id() -> str:
    """시각 순서 uuid. RFC 9562의 7판. 엔진은 같은 시각의 결제를 id 순서로 줄 세워서, 먼저 넣은 결제가 앞이 되게 한다

    무작위 uuid4면 같은 시각의 두 결제 가운데 어느 쪽이 하루 1회 한도를 쓰는지가 무작위였다. 2026-10-01 위험 검토
    """
    # ponytail: 서버의 벽시계를 쓴다. 시계가 뒤로 가거나 서버 여러 대의 시계가 어긋나면 순서가 뒤집힐 수 있다
    ms = time.time_ns() // 1_000_000
    r = int.from_bytes(os.urandom(10), "big")
    n = (ms << 80) | (0x7 << 76) | (((r >> 62) & 0xFFF) << 64) | (0b10 << 62) | (r & ((1 << 62) - 1))
    return str(uuid.UUID(int=n))


# 저장 전 결제의 id. 어떤 uuid 글자보다 뒤라 같은 시각의 저장된 결제 뒤에 온다
DRAFT_ID = "~draft"


def alias_index(catalog) -> dict[str, str]:
    return {alias_key(a): m.key for m in catalog.merchants.values() for a in m.aliases}


def match_merchant(index: dict[str, str], name: str | None) -> str | None:
    """가게 이름의 가맹점. E15

    앞에서부터 띄어 쓴 낱말 몇 개를 이은 것이 별칭과 같으면 맞는 것으로 보고 가장 긴 별칭을 고른다.
    "스타벅스 역삼점", "GS25 테헤란점", "LOTTE MART 잠실점"은 맞는다. "롯데하이마트 강남점", "멜론빵 전문점",
    "이마트트레이더스 월계점"처럼 별칭 뒤에 글자가 붙은 낱말은 맞지 않는다. 2026-10-01 위험 검토 두 번
    붙여 쓴 "스타벅스역삼점"도 맞지 않아 사용자가 업종을 고른다. 엉뚱한 가맹점의 혜택으로 저장되는 것보다 낫다. E16
    """
    words = (name or "").split()
    prefixes = {alias_key("".join(words[:k])) for k in range(1, len(words) + 1)}
    hits = [a for a in prefixes if a in index]
    return index[max(hits, key=len)] if hits else None


def _month(p: Payment) -> date:
    return month_of(local(p.paid_at).date())


def _with(payments: list[Payment], results: dict[str, PaymentResult]) -> list[Payment]:
    return [q.model_copy(update={"benefits": results[q.id].benefits}) if q.id in results else q for q in payments]


def ranked_past(engine, card: UserCard, month: date, now: datetime) -> bool:
    """지나간 달이고 그 달 개정에 순위 혜택이 있으면 참이다. 그 달은 달 끝 순위로 계산한다. E48

    ponytail: 달 첫날의 개정만 본다. 달 중간에 순위 혜택이 생기는 개정이 오면 그 달 결제마다 본다
    """
    found = engine.ctx.rules_on(card.card_id, month)
    return month < month_of(local(now).date()) and found is not None and bool(ranked_areas(found[1]))


def priced_with(engine, card: UserCard, history: list[Payment], p: Payment, now: datetime) -> dict[str, PaymentResult]:
    """새 결제 p의 혜택과, p 때문에 다시 계산한 결제의 혜택. 작업 005 설계 5b절

    p보다 뒤 결제가 하나도 없으면 p만 계산한다. 있으면 p가 든 달부터 마지막 결제가 든 달까지 달마다 결제 시각 순서로
    다시 계산한다. 카드사처럼 앞 결제가 한도를 먼저 쓴다. E52. 연, 분기, 행사 기간 한도와 지난달 실적으로 바뀐 구간 E53,
    실적이 다음 달에 들어가는 결제의 연쇄가 모두 이 순서 계산으로 맞는다. 2026-10-01 사용자가 정했다
    지나간 달은 달 끝 순위로 계산한다. E48
    """
    later = any((q.paid_at, q.id) > (p.paid_at, p.id) for q in history)
    if not later and not ranked_past(engine, card, _month(p), now):
        return {p.id: engine.price_payment(card, history, p)}
    this_month = month_of(local(now).date())
    payments, out = [*history, p], {}
    m, last = _month(p), max(_month(q) for q in [*history, p])
    while m <= last:
        results = {r.payment_id: r for r in engine.price_month(card, payments, month=m, final=m < this_month)}
        out |= results
        payments = _with(payments, results)
        m = add_months(m, 1)
    return out


def base_tier(engine, card: UserCard, payments: list[Payment], month: date) -> int | None:
    """새 카드 특례를 넣기 전의 기본 구간. 특례 구간은 결제와 상관없어 결제가 바꾸는 것은 기본 구간뿐이다"""
    status = engine.spend_status(card, payments, month)
    found = engine.ctx.rules_on(card.card_id, month)
    prev = status.prev_month_counted
    if found is None or prev is None:
        return status.tier
    return max(t for t in found[1].tiers if t <= prev)


def changed_with(
    engine,
    card: UserCard,
    before: list[Payment],
    changed: Payment | None,
    drop: str | None,
    start: date,
    now: datetime,
    rerank: bool = True,
) -> dict[str, PaymentResult]:
    """고치거나 취소한 결제 changed는 그 결제만 다시 계산한다. E50. drop은 이 카드에서 빠진 결제다

    그 뒤 start 다음 달부터 기본 구간이 저장된 상태와 처음 다른 달을 찾아 그 달부터 마지막 결제가 든 달까지 달마다
    결제 시각 순서로 다시 계산한다. 구간이 그대로인 뒤 달도 연, 분기, 행사 기간 한도가 바뀌어 함께 계산한다. E5, E54.
    2026-10-01 사용자가 정했다. 실적이 다음 달에 들어가는 결제가 있어 한 달을 건너 구간이 바뀔 수 있어 마지막 결제가 든
    달까지 찾는다. 지나간 달은 달 끝 순위로 계산한다. E48
    """
    gone = {drop, changed.id if changed else None}
    others = [q for q in before if q.id not in gone]
    out: dict[str, PaymentResult] = {}
    payments = others
    if changed is not None:
        out[changed.id] = engine.price_payment(card, others, changed)
        payments = [*others, changed.model_copy(update={"benefits": out[changed.id].benefits})]
    this_month = month_of(local(now).date())
    # 고친 결제가 들거나 빠진 지나간 달에 순위 혜택이 있으면 그 달 전체를 달 끝 순위로 다시 계산한다. E48
    touched = {_month(q) for q in before if q.id in gone} | ({_month(changed)} if changed is not None else set())
    for m in sorted(touched):
        if rerank and ranked_past(engine, card, m, now):
            results = {r.payment_id: r for r in engine.price_month(card, payments, month=m, final=True)}
            out |= results
            payments = _with(payments, results)
    last = max((_month(q) for q in payments), default=start)
    m, redo = start, False
    while m < last:
        m = add_months(m, 1)
        if not redo and base_tier(engine, card, before, m) == base_tier(engine, card, payments, m):
            continue
        redo = True
        results = {r.payment_id: r for r in engine.price_month(card, payments, month=m, final=m < this_month)}
        out |= results
        payments = _with(payments, results)
    return out
