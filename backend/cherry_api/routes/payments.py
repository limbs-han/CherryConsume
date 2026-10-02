"""저장 전 결제와 결제 저장. 작업 005 설계 5b절. S3"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Request
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from cherry_core.catalog.models import Billing
from cherry_core.engine.cond import local
from cherry_core.engine.models import Payment, PaymentResult, Query, Recommendation
from cherry_core.engine.recommend import DEFAULT_AMOUNT, order

from ..auth import User
from ..deps import Conn
from ..payments import DRAFT_ID, load_payments, match_merchant, new_id, priced_with
from .catalog import MAX_SPEND
from .me import engine_card

router = APIRouter(prefix="/me/payments")
Amount = Annotated[int, Field(strict=True, gt=0, le=MAX_SPEND)]
# 이 업종은 온라인으로 채운다. 앱스토어처럼 업종이 기타인 온라인 가맹점은 사용자가 바꾼다
# ponytail: 업종으로만 정한다. 가맹점마다 채널을 카탈로그에 담으면 그쪽을 따른다
ONLINE = {"online_shopping", "delivery_app", "streaming"}


class PaymentFields(BaseModel):
    # 모르는 칸은 422다. 카드번호 같은 칸이 몰래 들어오지 않는다. 작업 005 의도 성공 기준 6
    model_config = ConfigDict(extra="forbid")
    merchant_name: Annotated[str, Field(max_length=100)] | None = None
    category: str | None = None
    paid_at: AwareDatetime | None = None
    channel: Literal["online", "offline"] | None = None
    region: Literal["domestic", "overseas"] = "domestic"
    installment_months: Annotated[int, Field(strict=True, ge=1, le=36)] = 1
    interest_free: bool = False
    payment_method: str | None = None
    # 자동납부, 후불교통, 정기결제는 사용자가 안다. 비우면 가맹점의 기본 청구 방식이다. 카드 혜택 스물두 개가 이 조건을 단다
    billing: Billing | None = None

    @model_validator(mode="after")
    def _check(self) -> PaymentFields:
        if self.installment_months == 1 and self.interest_free:
            raise ValueError("일시불은 무이자할부가 아니다")
        return self


class Draft(PaymentFields):
    amount: Amount | None = None
    user_card_id: str | None = None
    # 고치는 결제의 id. 그 결제의 옛 값을 이력에서 빼고 계산한다. 작업 005 슬라이스 4 위험 검토 3번
    editing: str | None = None


class NewPayment(PaymentFields):
    amount: Amount
    user_card_id: str
    paid_at: AwareDatetime
    # 추천 결과에서 "이 카드로 결제 기록"을 누르면 채워진다. 추천을 따랐는지 본다. S4, 설계 문서 4.1
    recommendation_request_id: str | None = None


def filled(request: Request, body) -> dict:
    """가게 이름으로 가맹점과 업종을 채우고 채널과 시각의 기본값을 넣는다. S3"""
    cat = request.app.state.catalog
    if body.category is not None and body.category not in cat.categories:
        raise HTTPException(422, "모르는 업종이다")
    if body.payment_method is not None and body.payment_method not in cat.payment_methods:
        raise HTTPException(422, "모르는 결제수단이다")
    now = request.app.state.clock()
    # 추천 요청에는 시각 칸이 없어 지금이다
    paid_at = getattr(body, "paid_at", None) or now
    if paid_at > now + timedelta(days=1):
        raise HTTPException(422, "결제 시각이 지금보다 하루 넘게 뒤다")
    merchant = match_merchant(request.app.state.aliases, body.merchant_name)
    category = body.category or (cat.merchants[merchant].category if merchant else None)
    # 청구 방식은 저장할 때 정해 둔다. 카탈로그의 가맹점 청구 방식이 바뀌어도 저장한 결제는 그대로다. E18
    billing = getattr(body, "billing", None) or (cat.merchants[merchant].billing if merchant else None)
    channel = body.channel or ("online" if category and category.split(".")[0] in ONLINE else "offline")
    return {
        "merchant": merchant,
        "category": category,
        # 찾은 가맹점 이름. 별칭이 엉뚱한 가게에 걸렸으면 사용자가 화면에서 알아본다
        "merchant_display": cat.merchants[merchant].name if merchant else None,
        "category_name": request.app.state.category_names.get(category),
        "channel": channel,
        "paid_at": paid_at,
        "billing": billing,
    }


def my_cards(conn, user) -> list[dict]:
    return conn.execute(
        "SELECT uc.*, c.name FROM user_cards uc JOIN cards c ON c.id = uc.card_id"
        " WHERE uc.user_id = %s AND uc.removed_at IS NULL ORDER BY uc.added_at",
        (user,),
    ).fetchall()


def mine(conn, user, tid: str) -> dict:
    row = conn.execute(
        "SELECT * FROM transactions WHERE id = %s AND user_id = %s AND deleted_at IS NULL", (tid, user)
    ).fetchone()
    if row is None:
        raise HTTPException(404, "결제가 아니다")
    return row


def checked_id(value: str | None, what: str = "보유 카드가 아니다") -> str | None:
    if value is None:
        return None
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise HTTPException(404, what) from None


def payment_of(row: dict, body: PaymentFields, amount: int, f: dict, pid: str) -> Payment:
    return Payment(
        id=pid,
        user_card_id=str(row["id"]),
        amount=amount,
        paid_at=f["paid_at"],
        merchant=f["merchant"],
        category=f["category"],
        channel=f["channel"],
        region=body.region,
        installment_months=body.installment_months,
        interest_free=body.interest_free,
        payment_method=body.payment_method or row["last_payment_method"] or "physical_card",
        billing=f["billing"],
    )


def described(request: Request, card_id: str, at: datetime, result: PaymentResult) -> dict:
    found = request.app.state.engine.ctx.rules_on(card_id, local(at).date())
    titles = {b.key: b.title for b in found[1].benefits} if found else {}
    return {
        "value": result.value,
        "benefits": [
            {"key": b.key, "title": titles.get(b.key, b.key), "amount": b.amount, "value": b.value}
            for b in result.benefits
        ],
        "counted": any(part.amount > 0 for part in result.spend),
        "warnings": sorted({w.code for w in result.warnings}),
    }


def again(r: Recommendation, result: PaymentResult) -> Recommendation:
    """추천 줄을 다시 계산한 금액과 실적 인정 여부로 바꾼다. 무이자할부를 실적에서 빼는 카드가 실적 인정으로 앞에 서지 않게 한다"""
    return r.model_copy(update={"value": result.value, "counted": any(part.amount > 0 for part in result.spend)})


@router.post("/draft")
def draft(body: Draft, request: Request, user: User, conn: Conn) -> dict:
    """저장 전 결제. 카드 순위와 고른 카드의 예상 혜택. 고르지 않았으면 1순위를 고른다. S3"""
    f = filled(request, body)
    engine = request.app.state.engine
    rows = my_cards(conn, user)
    cards = {str(r["id"]): r for r in rows}
    old = None
    if body.editing is not None:
        old = mine(conn, user, checked_id(body.editing, "결제가 아니다"))
        if body.amount is not None and old["cancelled_amount"] > body.amount:
            raise HTTPException(422, "취소한 금액보다 작게 고칠 수 없다")
        card = str(old["user_card_id"])
        if card not in cards:
            # 해지한 카드의 결제는 그 카드로 예상 혜택만 낸다. 순위에는 넣지 않는다. 위험 검토 8번
            cards[card] = conn.execute(
                "SELECT uc.*, c.name FROM user_cards uc JOIN cards c ON c.id = uc.card_id WHERE uc.id = %s", (card,)
            ).fetchone()
    if not cards:
        return {**f, "paid_at": f["paid_at"].isoformat(), "ranking": [], "pick": None, "estimate": None}
    editing = str(old["id"]) if old else None
    payments = {k: [q for q in v if q.id != editing] for k, v in load_payments(conn, list(cards)).items()}
    query = Query(
        merchant=f["merchant"],
        category=f["category"],
        amount=body.amount,
        channel=f["channel"],
        region=body.region,
        payment_method=body.payment_method,
    )
    [ranked] = engine.recommend([engine_card(r) for r in rows], payments, [query], f["paid_at"])
    # 순위의 금액은 할부, 무이자, 지역까지 넣은 price_payment로 다시 계산한다. 추천 질문에는 그 칸이 없어서
    # 1순위 카드의 순위 금액과 예상 혜택이 다를 수 있었다. 줄 세우기는 엔진의 order 그대로다. 같은 금액이면
    # 실적이 모자란 카드가 앞이다. 설계 4.2, S5
    amount = body.amount or DEFAULT_AMOUNT

    def priced_on(uid: str) -> tuple[Payment, PaymentResult]:
        # 고치는 결제는 저장 경로 edit처럼 그 결제의 id와 취소를 그대로 둔다. 같은 시각 결제와의 순서와 남은 금액이 같다
        p = payment_of(cards[uid], body, amount, f, editing or DRAFT_ID)
        if old is not None and body.amount is not None:
            p = p.model_copy(update={"cancelled_amount": old["cancelled_amount"], "cancelled_at": old["cancelled_at"]})
        return p, engine.price_payment(engine_card(cards[uid]), payments[uid], p)

    priced = {r.user_card_id: priced_on(r.user_card_id) for r in ranked}
    ranking = [r.user_card_id for r in sorted((again(r, priced[r.user_card_id][1]) for r in ranked), key=order)]
    pick = checked_id(body.user_card_id) or (ranking[0] if ranking else None)
    if pick not in cards:
        raise HTTPException(404, "보유 카드가 아니다")
    estimate = None
    if body.amount is not None:
        if pick not in priced:
            priced[pick] = priced_on(pick)
        p, result = priced[pick]
        estimate = {"user_card_id": pick, "payment_method": p.payment_method}
        estimate |= described(request, cards[pick]["card_id"], p.paid_at, result)
    return {
        **f,
        "paid_at": f["paid_at"].isoformat(),
        "ranking": [{"user_card_id": i, "name": cards[i]["name"], "value": priced[i][1].value} for i in ranking],
        "pick": pick,
        "estimate": estimate,
    }


@router.post("", status_code=201)
def save(body: NewPayment, request: Request, user: User, conn: Conn) -> dict:
    """결제 저장. 엔진이 계산한 혜택을 저장한다. 앞선 결제나 지난달 결제로 다시 계산할 결제가 생기면 함께 바꾼다. E52, E53"""
    f = filled(request, body)
    card_id = checked_id(body.user_card_id)
    # 같은 카드의 결제 저장을 줄 세운다. 두 결제가 같은 한도를 함께 쓰지 않게 한다
    row = conn.execute(
        "SELECT * FROM user_cards WHERE id = %s AND user_id = %s AND removed_at IS NULL FOR UPDATE", (card_id, user)
    ).fetchone()
    if row is None:
        raise HTTPException(404, "보유 카드가 아니다")
    request_id = None
    if body.recommendation_request_id is not None:
        request_id = checked_id(body.recommendation_request_id, "추천 요청이 아니다")
        asked = conn.execute(
            "SELECT 1 FROM recommendation_requests WHERE id = %s AND user_id = %s", (request_id, user)
        ).fetchone()
        if asked is None:
            raise HTTPException(404, "추천 요청이 아니다")
    engine = request.app.state.engine
    pid = new_id()
    p = payment_of(row, body, body.amount, f, pid)
    history = load_payments(conn, [card_id])[card_id]
    now = request.app.state.clock()
    results = priced_with(engine, engine_card(row), history, p, now)
    result = results[pid]

    def revision_of(at: datetime) -> int | None:
        found = engine.ctx.rules_on(row["card_id"], local(at).date())
        return request.app.state.revision_ids[(row["card_id"], found[0].effective_from)] if found else None

    conn.execute(
        """
        INSERT INTO transactions (id, user_id, user_card_id, amount, merchant_name, merchant_key, category_code, paid_at,
                                  installment_months, interest_free_installment, channel, region, payment_method,
                                  billing, card_revision_id, recommendation_request_id, source, created_at,
                                  updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'manual', %s, %s)
        """,
        (
            pid,
            user,
            card_id,
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
            revision_of(p.paid_at),
            request_id,
            now,
            now,
        ),
    )
    # 다시 계산한 결제 가운데 혜택이 바뀐 것만 저장된 혜택과 계산에 쓴 개정 행을 바꾼다. E52, E53
    # 그대로인 결제까지 다시 쓰면 1년치 결제에 수백 문장이 나가고 updated_at이 바뀌어 E25의 늦은 쪽 이기기가 틀어진다
    before = {q.id: q for q in history}

    def same(tid: str, r: PaymentResult) -> bool:
        return tid != pid and sorted(r.benefits, key=lambda b: b.key) == sorted(
            before[tid].benefits, key=lambda b: b.key
        )

    changed = [tid for tid, r in results.items() if tid != pid and not same(tid, r)]
    if changed:
        conn.execute("DELETE FROM transaction_benefits WHERE transaction_id = ANY(%s)", (changed,))
        with conn.cursor() as cur:
            cur.executemany(
                "UPDATE transactions SET card_revision_id = %s, updated_at = %s WHERE id = %s",
                [(revision_of(before[tid].paid_at), now, tid) for tid in changed],
            )
    rows = [(tid, b.key, b.amount, b.value, b.base) for tid in [pid, *changed] for b in results[tid].benefits]
    if rows:
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO transaction_benefits (transaction_id, benefit_key, amount, value, base_amount)"
                " VALUES (%s, %s, %s, %s, %s)",
                rows,
            )
    conn.execute("UPDATE user_cards SET last_payment_method = %s WHERE id = %s", (p.payment_method, card_id))
    # 혜택이 바뀐 다른 결제 수. 앱이 알린다
    return {"id": pid, "repriced": len(changed), **described(request, row["card_id"], p.paid_at, result)}
