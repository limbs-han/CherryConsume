"""로그인한 사용자의 카드와 홈. 작업 005 설계 5절"""

from __future__ import annotations

from datetime import date
from typing import Annotated

import psycopg
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from cherry_core.engine.cond import local, month_of
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
    total = sum(
        b.value
        for ps in payments.values()
        for p in ps
        if month_of(local(p.paid_at).date()) == month
        for b in p.benefits
    )
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
