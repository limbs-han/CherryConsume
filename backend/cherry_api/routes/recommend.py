"""추천. 업종별 지금 1순위, 최근 간 가게, 가게와 업종 추천. 작업 005 설계 5c절. S4"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Request
from psycopg.types.json import Jsonb
from pydantic import BaseModel, ConfigDict, Field

from cherry_core.engine.cond import local
from cherry_core.engine.models import Query, Recommendation

from ..auth import User
from ..deps import Conn
from ..payments import load_payments
from .me import engine_card
from .payments import ONLINE, Amount, filled, my_cards

router = APIRouter(prefix="/me")

# 업종별 지금 1순위의 업종. 시안의 다섯에 자주 쓰는 일곱을 더했다. Claude가 정했다
# 지하철, 시내버스, 휴대폰 요금은 혜택 대부분이 후불교통이나 자동납부 조건이라 가게 없는 질문으로는 1순위를 맞게 못 낸다.
# 담을 수 없는 것은 계산하지 않는다는 규칙대로 뺐다. 2026-10-01 위험 검토
TOP = [
    "cafe",
    "convenience",
    "restaurant.general",
    "restaurant.fastfood",
    "delivery_app",
    "online_shopping",
    "grocery_mart",
    "department_store",
    "taxi",
    "fuel",
    "movie",
    "pharmacy",
]


def billing_bound(catalog) -> set[str]:
    """청구 방식 조건이 붙은 혜택의 대상 업종. 가게 없이 업종만 물으면 후불교통인지 자동납부인지 몰라 1순위를 맞게 못 낸다"""

    def has_billing(conditions) -> bool:
        return any(c.billing or has_billing(c.any_of or []) for c in conditions)

    out: set[str] = set()
    for loaded in catalog.cards.values():
        for _, rules in loaded.revisions:
            for b in rules.benefits:
                if has_billing(b.when):
                    out |= set(b.target.categories)
    return out


def bound(request: Request, code: str) -> bool:
    found = request.app.state.billing_bound
    return code in found or code.split(".")[0] in found


class Ask(BaseModel):
    # 모르는 칸은 422다. 작업 005 의도 성공 기준 6
    model_config = ConfigDict(extra="forbid")
    merchant_name: Annotated[str, Field(max_length=100)] | None = None
    category: str | None = None
    amount: Amount | None = None
    channel: Literal["online", "offline"] | None = None
    region: Literal["domestic", "overseas"] = "domestic"
    payment_method: str | None = None


def rows_of(request: Request, cards: dict, recs: list[Recommendation], at: datetime) -> list[dict]:
    """카드마다 순위, 혜택 금액, 이유 한 줄, 할인과 적립 구분, 결제수단을 바꾸면 더 받는 금액"""
    engine, cat = request.app.state.engine, request.app.state.catalog
    out = []
    for rank, r in enumerate(recs, 1):
        found = engine.ctx.rules_on(r.card_id, local(at).date())
        benefits = {b.key: b for b in found[1].benefits} if found else {}
        top = max(r.benefits, key=lambda b: b.value, default=None)
        b = benefits.get(top.key) if top else None
        received = {x.key for x in r.benefits if x.value > 0}
        # 받은 혜택의 한도 때문에 줄었을 때만 이유로 보인다. 받지 않은 혜택의 한도 소진은 이유가 아니다
        limited = r.value > 0 and any(w.code == "limit_exhausted" and w.benefit in received for w in r.warnings)
        codes = {w.code for w in r.warnings}
        # 받는 혜택의 종류를 모두 준다. 할인과 적립을 함께 받으면 둘 다 보인다. E13
        rewards = sorted({benefits[x.key].reward.type for x in r.benefits if x.key in benefits and x.value > 0})
        pay_with = []
        # 사실과 옵션의 조건부 혜택은 슬라이스 5에서 보인다. 작업 004의 추천 결과는 결제수단만 보인다
        for c in r.conditional:
            method = c.needs.get("payment_method") if set(c.needs) == {"payment_method"} else None
            if method in cat.payment_methods:
                pay_with.append({"payment_method": method, "name": cat.payment_methods[method].name, "extra": c.extra})
        out.append(
            {
                "rank": rank,
                "user_card_id": r.user_card_id,
                "name": cards[r.user_card_id]["name"],
                "value": r.value,
                "title": b.title if b else None,
                "rewards": rewards,
                "pay_with": pay_with,
                # 한도를 다 써 0원이 된 카드. E10
                "exhausted": r.value == 0 and "limit_exhausted" in codes,
                # 한도가 남은 만큼만 받는 카드. 작업 004 의도 성공 기준 3대로 한도 때문에 줄었을 때 이유로 보인다
                "limited": limited,
                # 달 끝 순위로 정해지는 혜택. E48
                "provisional": "ranked_provisional" in codes,
            }
        )
    return out


@router.get("/recommendations/top")
def top(request: Request, user: User, conn: Conn) -> list[dict]:
    """업종마다 가게 없이 1만 원으로 추천을 돌린 1위. 설계 문서 6.5"""
    rows = my_cards(conn, user)
    if not rows:
        return []
    cards = {str(r["id"]): r for r in rows}
    now = request.app.state.clock()
    names = request.app.state.category_names
    # 카탈로그에서 빠진 업종은 건너뛴다. 카탈로그는 봇이 커밋해 코드와 따로 바뀐다
    codes = [c for c in TOP if c in names and not bound(request, c)]
    # 채널은 결과 화면과 같게 업종으로 채운다. 같은 줄의 금액이 두 화면에서 다르지 않게 한다
    queries = [Query(category=c, channel="online" if c.split(".")[0] in ONLINE else "offline") for c in codes]
    answers = request.app.state.engine.recommend(
        [engine_card(r) for r in rows], load_payments(conn, list(cards)), queries, now
    )
    return [
        {"category": c, "category_name": names[c], **rows_of(request, cards, recs[:1], now)[0]}
        for c, recs in zip(codes, answers, strict=True)
    ]


@router.get("/recent-merchants")
def recent(user: User, conn: Conn) -> list[str]:
    """최근 간 가게 4곳. 결제에 적은 이름 그대로"""
    rows = conn.execute(
        "SELECT merchant_name FROM transactions WHERE user_id = %s AND deleted_at IS NULL AND merchant_name IS NOT NULL"
        " GROUP BY merchant_name ORDER BY max(paid_at) DESC LIMIT 4",
        (user,),
    ).fetchall()
    return [r["merchant_name"] for r in rows]


@router.post("/recommendations")
def recommend(body: Ask, request: Request, user: User, conn: Conn) -> dict:
    """가게나 업종의 추천. 요청과 순위를 남겨 추천을 따랐는지 보게 한다. 설계 문서 4.1"""
    f = filled(request, body)
    result = {
        "merchant": f["merchant"],
        "merchant_display": f["merchant_display"],
        "category": f["category"],
        "category_name": f["category_name"],
        "amount": body.amount,
    }
    # 담을 수 없는 질문은 계산하지 않는다. 가게 없이 지하철처럼 청구 방식에 따라 혜택이 갈리는 업종을 물을 때다
    if f["merchant"] is None and f["category"] and bound(request, f["category"]):
        return {**result, "request_id": None, "unsupported": "billing", "ranking": []}
    rows = my_cards(conn, user)
    cards = {str(r["id"]): r for r in rows}
    now = f["paid_at"]
    query = Query(
        merchant=f["merchant"],
        category=f["category"],
        amount=body.amount,
        channel=f["channel"],
        region=body.region,
        payment_method=body.payment_method,
    )
    engine = request.app.state.engine
    recs = (
        engine.recommend([engine_card(r) for r in rows], load_payments(conn, list(cards)), [query], now)[0]
        if rows
        else []
    )
    request_id = conn.execute(
        "INSERT INTO recommendation_requests (user_id, merchant_name, merchant_key, category_code, amount, channel,"
        " region, payment_method, requested_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id",
        (
            user,
            body.merchant_name,
            f["merchant"],
            f["category"],
            body.amount,
            f["channel"],
            body.region,
            body.payment_method,
            now,
        ),
    ).fetchone()["id"]
    if recs:
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO recommendation_results (request_id, rank, user_card_id, expected_benefit, applied,"
                " conditional, warnings) VALUES (%s, %s, %s, %s, %s, %s, %s)",
                [
                    (
                        request_id,
                        rank,
                        r.user_card_id,
                        r.value,
                        Jsonb([b.model_dump() for b in r.benefits]),
                        Jsonb([c.model_dump(mode="json") for c in r.conditional]),
                        sorted({w.code for w in r.warnings}),
                    )
                    for rank, r in enumerate(recs, 1)
                ],
            )
    return {**result, "request_id": str(request_id), "unsupported": None, "ranking": rows_of(request, cards, recs, now)}
