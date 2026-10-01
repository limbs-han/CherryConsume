"""로그인한 사용자의 카드와 홈. 작업 005 설계 5절"""

from __future__ import annotations

from datetime import date, datetime
from typing import Annotated
from uuid import UUID

import psycopg
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from cherry_core.engine.cond import KST, add_months, local, month_of
from cherry_core.engine.models import UserCard

from ..auth import User
from ..deps import Conn, today
from ..payments import load_payments
from .catalog import MAX_SPEND, benefits_at, registrable

router = APIRouter(prefix="/me")


class NewUserCard(BaseModel):
    # 모르는 칸은 422다. 카드번호 같은 칸이 몰래 들어오지 않는다. 작업 005 의도 성공 기준 6
    model_config = ConfigDict(extra="forbid")
    card_id: str
    assumed_prev_month_spend: Annotated[int, Field(strict=True, ge=0, le=MAX_SPEND)] | None = None
    started_on: date | None = None


def engine_card(row: dict) -> UserCard:
    return UserCard(
        id=str(row["id"]),
        card_id=row["card_id"],
        registered_on=local(row["added_at"]).date(),
        started_on=row["started_on"],
        assumed_prev_month_spend=row["assumed_prev_month_spend"],
        last_payment_method=row["last_payment_method"],
    )


@router.post("/cards", status_code=201)
def add_card(body: NewUserCard, request: Request, user: User, conn: Conn) -> dict:
    registrable(request, body.card_id)
    try:
        row = conn.execute(
            "INSERT INTO user_cards (user_id, card_id, assumed_prev_month_spend, started_on, added_at)"
            " VALUES (%s, %s, %s, %s, %s) RETURNING id",
            (user, body.card_id, body.assumed_prev_month_spend, body.started_on, request.app.state.clock()),
        ).fetchone()
    except psycopg.errors.UniqueViolation:
        raise HTTPException(409, "이미 등록한 카드다. E21") from None
    return {"id": str(row["id"])}


@router.get("/home")
def home(request: Request, user: User, conn: Conn) -> dict:
    month = month_of(today(request))
    rows = conn.execute(
        "SELECT uc.*, c.name, i.name AS issuer_name FROM user_cards uc"
        " JOIN cards c ON c.id = uc.card_id JOIN issuers i ON i.code = c.issuer_code"
        " WHERE uc.user_id = %s AND uc.removed_at IS NULL ORDER BY uc.added_at",
        (user,),
    ).fetchall()
    engine = request.app.state.engine
    payments = load_payments(conn, [str(r["id"]) for r in rows])
    # 받은 혜택은 한국 시간으로 이번 달에 결제한 건의 저장된 혜택 원 가치 합이다. E13
    # 해지한 카드의 결제도 넣는다. 그달 실제로 받은 혜택이다. 작업 005 설계 5d절
    start, end = month_range(month)
    total = conn.execute(
        "SELECT coalesce(sum(b.value), 0) AS v FROM transactions t JOIN transaction_benefits b ON b.transaction_id = t.id"
        " WHERE t.user_id = %s AND t.deleted_at IS NULL AND t.paid_at >= %s AND t.paid_at < %s",
        (user, start, end),
    ).fetchone()["v"]
    cards = []
    for r in rows:
        card = engine_card(r)
        status = engine.spend_status(card, payments[str(r["id"])], month)
        found = engine.ctx.rules_on(r["card_id"], month)
        titles = benefits_at(found[1], card, month, status) if found and status.tier is not None else []
        cards.append(
            {
                "id": str(r["id"]),
                "card_id": r["card_id"],
                "name": r["name"],
                "issuer_name": r["issuer_name"],
                # 비면 실적 무관 카드다
                "tiers": [t for t in found[1].tiers if t > 0] if found else [],
                # 실적 무관 카드는 홈에 남은 금액 대신 이 혜택 제목을 보인다
                "headline": titles[0] if titles else None,
                "spend": status.model_dump(mode="json", exclude={"user_card_id", "month"}),
            }
        )
    return {"month": month.isoformat(), "benefit_total": total, "cards": cards}


def month_range(month: date) -> tuple[datetime, datetime]:
    """한국 시간 그 달의 처음과 다음 달 처음. E7"""
    nxt = add_months(month, 1)
    return datetime(month.year, month.month, 1, tzinfo=KST), datetime(nxt.year, nxt.month, 1, tzinfo=KST)


def shared_title(rules, key: str) -> str:
    if key == "integrated":
        return "통합 한도"
    users = [b.title for b in rules.benefits for lim in b.limits if lim.shared == key]
    return "함께 쓰는 한도 · " + ", ".join(users) if users else "함께 쓰는 한도"


@router.get("/cards/{uid}")
def card_detail(uid: str, request: Request, user: User, conn: Conn) -> dict:
    """카드 상세. 시안 보드 6. 실적과 구간, 혜택별 남은 한도, 구간이 모자라 못 받는 혜택, 확인 필요 안내. S7, E37"""
    try:
        uid = str(UUID(uid))
    except ValueError:
        raise HTTPException(404, "보유 카드가 아니다") from None
    row = conn.execute(
        "SELECT uc.*, c.name, c.checked_at, i.name AS issuer_name FROM user_cards uc"
        " JOIN cards c ON c.id = uc.card_id JOIN issuers i ON i.code = c.issuer_code"
        " WHERE uc.id = %s AND uc.user_id = %s AND uc.removed_at IS NULL",
        (uid, user),
    ).fetchone()
    if row is None:
        raise HTTPException(404, "보유 카드가 아니다")
    engine, now = request.app.state.engine, request.app.state.clock()
    month = month_of(today(request))
    card = engine_card(row)
    payments = load_payments(conn, [uid])[uid]
    status = engine.spend_status(card, payments, month)
    found = engine.ctx.rules_on(row["card_id"], month)
    limits, locked = [], []
    if found is not None:
        rules = found[1]
        titles = {b.key: b.title for b in rules.benefits}
        # 1회와 하루 한도는 남은 양이 아니라 조건이라 보이지 않는다
        for use in engine.limit_status(card, payments, now):
            if use.per in ("txn", "day") or (use.cap_amount is None and use.cap_count is None):
                continue
            limits.append(
                {
                    "title": titles.get(use.benefit, use.benefit) if use.benefit else shared_title(rules, use.key),
                    "per": use.per,
                    "used_amount": use.used_amount,
                    "cap_amount": use.cap_amount,
                    "used_count": use.used_count,
                    "cap_count": use.cap_count,
                }
            )
        prev = status.prev_month_counted
        base = max(t for t in rules.tiers if t <= prev) if prev is not None else (status.tier or 0)
        available = set(benefits_at(rules, card, month, status))
        for b in rules.benefits:
            lo = b.tiers.start if b.tiers and b.tiers.start is not None else rules.tiers[0]
            # 구간이 모자라 못 받는 혜택. 필요 금액은 그 구간 하한 빼기 이번 달 인정 실적, 받는 때는 다음 달이다. E37
            if lo > base and b.title not in available:
                locked.append({"title": b.title, "required_tier": lo, "remaining": max(lo - status.counted, 0)})
    sentences = [s for w in status.warnings if w.code == "check_conditions" for s in w.data.get("sentences", [])]
    assumed = sum(len(w.data.get("paths", [])) for w in status.warnings if w.code == "assumed_value")
    return {
        "id": uid,
        "card_id": row["card_id"],
        "name": row["name"],
        "issuer_name": row["issuer_name"],
        "tiers": [t for t in found[1].tiers if t > 0] if found else [],
        "spend": status.model_dump(mode="json", exclude={"user_card_id", "month"}),
        "limits": limits,
        "locked": locked,
        # 조건을 문장으로만 담은 혜택과 공식 문구로 확인하지 못한 값. 슬라이스 1에서 늘 붙는 안내를 여기서 보인다
        "check_sentences": sentences,
        "assumed_count": assumed,
        "started_on": row["started_on"].isoformat() if row["started_on"] else None,
        "registered_on": local(row["added_at"]).date().isoformat(),
        "revision_from": found[0].effective_from.isoformat() if found else None,
        "checked_at": row["checked_at"].isoformat(),
    }


@router.delete("/cards/{uid}")
def remove_card(uid: str, request: Request, user: User, conn: Conn) -> dict:
    """카드 해지. 결제와 기록은 남기고 홈과 추천에서만 뺀다. S9"""
    try:
        uid = str(UUID(uid))
    except ValueError:
        raise HTTPException(404, "보유 카드가 아니다") from None
    row = conn.execute(
        "UPDATE user_cards SET removed_at = %s WHERE id = %s AND user_id = %s AND removed_at IS NULL RETURNING id",
        (request.app.state.clock(), uid, user),
    ).fetchone()
    if row is None:
        raise HTTPException(404, "보유 카드가 아니다")
    return {"id": uid}
