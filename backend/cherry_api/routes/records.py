"""기록 탭. 달별 결제 목록, 고치기, 취소, 지우기. 작업 005 설계 5d절. S7, S8"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, HTTPException, Request
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from cherry_core.engine.cond import local, month_of
from cherry_core.engine.models import Payment, PaymentResult
from cherry_core.engine.price import before_cancel, build_ledger
from cherry_core.engine.spend import spend_parts

from ..auth import User
from ..deps import Conn, today
from ..payments import PAYMENTS, changed_with, load_payments, to_payment
from .me import engine_card, month_range
from .payments import Amount, PaymentFields, checked_id, filled, mine, payment_of

router = APIRouter(prefix="/me/payments")


class EditPayment(PaymentFields):
    amount: Amount
    user_card_id: str
    paid_at: AwareDatetime


class Cancel(BaseModel):
    model_config = ConfigDict(extra="forbid")
    # 지금까지 취소한 금액의 합이다. 부분 취소가 여러 번이면 합을 보낸다. E5
    cancelled_amount: Annotated[int, Field(strict=True, gt=0)]
    cancelled_at: AwareDatetime


def revision_for(request: Request, card_id: str, at: datetime) -> int | None:
    found = request.app.state.engine.ctx.rules_on(card_id, local(at).date())
    return request.app.state.revision_ids[(card_id, found[0].effective_from)] if found else None


def lock_cards(conn, user, ids: set[str]) -> dict[str, dict]:
    """결제를 바꾸는 보유 카드 행을 잠근다. 저장과 같은 줄 세우기다. 순서를 정해 서로 기다리다 멈추지 않게 한다"""
    rows = conn.execute(
        "SELECT * FROM user_cards WHERE user_id = %s AND id = ANY(%s) ORDER BY id FOR UPDATE", (user, sorted(ids))
    ).fetchall()
    return {str(r["id"]): r for r in rows}


def store(
    conn, request, card_id: str, results: dict[str, PaymentResult], before: dict[str, Payment], always: set[str], now
) -> int:
    """다시 계산한 결제의 혜택과 개정 행을 쓴다. always는 고친 결제라 늘 쓴다. 혜택이 바뀐 다른 결제 수를 돌려준다"""
    changed = 0
    for tid, r in results.items():
        old = before.get(tid)
        same = old is not None and sorted(r.benefits, key=lambda b: b.key) == sorted(old.benefits, key=lambda b: b.key)
        if tid not in always and same:
            continue
        if tid not in always:
            changed += 1
        at = old.paid_at if old is not None else None
        conn.execute("DELETE FROM transaction_benefits WHERE transaction_id = %s", (tid,))
        if at is not None and tid not in always:
            conn.execute(
                "UPDATE transactions SET card_revision_id = %s, updated_at = %s WHERE id = %s",
                (revision_for(request, card_id, at), now, tid),
            )
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO transaction_benefits (transaction_id, benefit_key, amount, value, base_amount)"
                " VALUES (%s, %s, %s, %s, %s)",
                [(tid, b.key, b.amount, b.value, b.base) for b in r.benefits],
            )
    return changed


@router.get("")
def records(request: Request, user: User, conn: Conn, month: str | None = None, card: str | None = None) -> dict:
    """그 달 결제를 최근 순으로. 해지한 카드의 결제도 보인다. 받은 혜택은 저장된 혜택이다. E18"""
    try:
        m = date.fromisoformat(f"{month}-01") if month else month_of(today(request))
    except ValueError:
        raise HTTPException(422, "달은 2026-09처럼 쓴다") from None
    card_id = checked_id(card)
    start, end = month_range(m)
    cards = {
        str(r["id"]): r
        for r in conn.execute(
            "SELECT uc.*, c.name FROM user_cards uc JOIN cards c ON c.id = uc.card_id WHERE uc.user_id = %s", (user,)
        ).fetchall()
    }
    sql = PAYMENTS.replace(
        "WHERE t.user_card_id = ANY(%s) AND t.deleted_at IS NULL",
        "WHERE t.user_id = %s AND t.deleted_at IS NULL AND t.paid_at >= %s AND t.paid_at < %s"
        " AND (%s::uuid IS NULL OR t.user_card_id = %s::uuid)",
    ).replace("ORDER BY t.paid_at, t.id", "ORDER BY t.paid_at DESC, t.id DESC")
    rows = conn.execute(sql, (user, start, end, card_id, card_id)).fetchall()
    engine, names = request.app.state.engine, request.app.state.category_names
    out = []
    history: dict[str, list[Payment]] = {}
    for row in rows:
        p = to_payment(row)
        uc = cards[str(row["user_card_id"])]
        found = engine.ctx.rules_on(uc["card_id"], local(p.paid_at).date())
        counted = True
        rewards: list[str] = []
        if found is not None:
            card_ = engine_card(uc)
            before = None
            if p.cancelled_amount:
                # 취소한 결제는 엔진처럼 취소하지 않았다면 받았을 혜택으로 처음 실적을 센다. 설계 문서 6.5
                if p.user_card_id not in history:
                    history |= load_payments(conn, [p.user_card_id])
                prior = [q for q in history[p.user_card_id] if (q.paid_at, q.id) < (p.paid_at, p.id)]
                before = before_cancel(engine.ctx, card_, p, build_ledger(engine.ctx, card_, prior))
            parts, _ = spend_parts(engine.ctx, card_, p, found[1], p.benefits or [], before)
            # 어느 달 실적에도 넣지 않으면 실적 제외다. 취소로 0원이 된 결제는 취소로 보인다
            counted = any(part.amount > 0 for part in parts) or p.cancelled_amount == p.amount
            types = {b.key: b.reward.type for b in found[1].benefits}
            rewards = sorted({types[b.key] for b in p.benefits or [] if b.key in types and b.value > 0})
        out.append(
            {
                "id": p.id,
                "paid_at": p.paid_at.isoformat(),
                "merchant_name": row["merchant_name"],
                "category": p.category,
                "category_name": names.get(p.category) if p.category else None,
                "user_card_id": p.user_card_id,
                "card_name": uc["name"],
                "amount": p.amount,
                "cancelled_amount": p.cancelled_amount,
                "value": sum(b.value for b in p.benefits or []),
                "rewards": rewards,
                "counted": counted,
                # 고치기 화면을 채운다
                "channel": p.channel,
                "region": p.region,
                "installment_months": p.installment_months,
                "interest_free": p.interest_free,
                "payment_method": p.payment_method,
                "billing": row["billing"],
            }
        )
    return {
        "month": m.isoformat(),
        "count": len(out),
        "amount": sum(x["amount"] - x["cancelled_amount"] for x in out),
        "benefit_total": sum(x["value"] for x in out),
        "cards": [{"id": i, "name": r["name"]} for i, r in cards.items() if r["removed_at"] is None],
        "payments": out,
    }


@router.patch("/{tid}")
def edit(tid: str, body: EditPayment, request: Request, user: User, conn: Conn) -> dict:
    """결제 고치기. 그 결제만 다시 계산한다. E50. 구간이 바뀐 달이 있으면 처음 바뀐 달부터 마지막 결제가 든 달까지 다시 계산한다. E54"""
    tid = checked_id(tid, "결제가 아니다")
    old = mine(conn, user, tid)
    if old["cancelled_amount"] > body.amount:
        raise HTTPException(422, "취소한 금액보다 작게 고칠 수 없다")
    f = filled(request, body)
    new_card = checked_id(body.user_card_id)
    old_card = str(old["user_card_id"])
    rows = lock_cards(conn, user, {old_card, new_card})
    # 새로 고른 카드는 해지하지 않은 카드여야 한다. 해지한 카드의 결제는 그 카드 그대로만 고친다
    if new_card not in rows or (new_card != old_card and rows[new_card]["removed_at"] is not None):
        raise HTTPException(404, "보유 카드가 아니다")
    now, engine = request.app.state.clock(), request.app.state.engine
    loaded = load_payments(conn, sorted({old_card, new_card}))
    p = payment_of(rows[new_card], body, body.amount, f, tid).model_copy(
        update={"cancelled_amount": old["cancelled_amount"], "cancelled_at": old["cancelled_at"]}
    )
    start = min(month_of(local(old["paid_at"]).date()), month_of(local(p.paid_at).date()))
    results: dict[str, dict[str, PaymentResult]] = {}
    if new_card == old_card:
        results[new_card] = changed_with(engine, engine_card(rows[new_card]), loaded[new_card], p, None, start, now)
    else:
        results[old_card] = changed_with(engine, engine_card(rows[old_card]), loaded[old_card], None, tid, start, now)
        results[new_card] = changed_with(engine, engine_card(rows[new_card]), loaded[new_card], p, None, start, now)
    conn.execute(
        """
        UPDATE transactions SET user_card_id = %s, amount = %s, merchant_name = %s, merchant_key = %s, category_code = %s,
            paid_at = %s, installment_months = %s, interest_free_installment = %s, channel = %s, region = %s,
            payment_method = %s, billing = %s, card_revision_id = %s, updated_at = %s
        WHERE id = %s
        """,
        (
            new_card,
            p.amount,
            body.merchant_name,
            p.merchant,
            p.category,
            p.paid_at,
            p.installment_months,
            p.interest_free,
            p.channel,
            p.region,
            p.payment_method,
            p.billing,
            revision_for(request, rows[new_card]["card_id"], p.paid_at),
            now,
            tid,
        ),
    )
    repriced = 0
    for cid, res in results.items():
        before = {q.id: q for q in loaded[cid]}
        repriced += store(conn, request, rows[cid]["card_id"], res, before, {tid} if cid == new_card else set(), now)
    return {"id": tid, "value": results[new_card][tid].value, "repriced": repriced}


@router.post("/{tid}/cancel")
def cancel(tid: str, body: Cancel, request: Request, user: User, conn: Conn) -> dict:
    """취소 기록. 남은 금액으로 그 결제를 다시 계산하고 전액 취소면 혜택은 0이다. 구간이 처음 바뀐 달부터 다시 계산한다. E5, E54"""
    tid = checked_id(tid, "결제가 아니다")
    old = mine(conn, user, tid)
    now = request.app.state.clock()
    if body.cancelled_amount > old["amount"]:
        raise HTTPException(422, "결제 금액보다 많이 취소할 수 없다")
    if body.cancelled_at < old["paid_at"] or body.cancelled_at > now + timedelta(days=1):
        raise HTTPException(422, "취소 시각이 결제 시각보다 앞서거나 지금보다 하루 넘게 뒤다")
    card_id = str(old["user_card_id"])
    rows = lock_cards(conn, user, {card_id})
    loaded = load_payments(conn, [card_id])[card_id]
    before = {q.id: q for q in loaded}
    p = before[tid].model_copy(update={"cancelled_amount": body.cancelled_amount, "cancelled_at": body.cancelled_at})
    engine = request.app.state.engine
    res = changed_with(engine, engine_card(rows[card_id]), loaded, p, None, month_of(local(p.paid_at).date()), now)
    conn.execute(
        "UPDATE transactions SET cancelled_amount = %s, cancelled_at = %s, updated_at = %s WHERE id = %s",
        (body.cancelled_amount, body.cancelled_at, now, tid),
    )
    repriced = store(conn, request, rows[card_id]["card_id"], res, before, {tid}, now)
    return {"id": tid, "value": res[tid].value, "repriced": repriced}


@router.delete("/{tid}")
def delete(tid: str, request: Request, user: User, conn: Conn) -> dict:
    """결제 지우기. 행은 남기고 지운 시각만 찍는다. S8. 구간이 처음 바뀐 달부터 마지막 결제가 든 달까지 다시 계산한다. E54"""
    tid = checked_id(tid, "결제가 아니다")
    old = mine(conn, user, tid)
    now = request.app.state.clock()
    card_id = str(old["user_card_id"])
    rows = lock_cards(conn, user, {card_id})
    loaded = load_payments(conn, [card_id])[card_id]
    before = {q.id: q for q in loaded}
    engine = request.app.state.engine
    res = changed_with(
        engine, engine_card(rows[card_id]), loaded, None, tid, month_of(local(old["paid_at"]).date()), now
    )
    conn.execute("UPDATE transactions SET deleted_at = %s, updated_at = %s WHERE id = %s", (now, now, tid))
    return {"id": tid, "repriced": store(conn, request, rows[card_id]["card_id"], res, before, set(), now)}
