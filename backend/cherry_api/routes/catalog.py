"""카드사 칩, 카드 검색, 등록 미리보기. 작업 005 설계 5절. 계산은 메모리의 카탈로그와 엔진으로 한다"""

from __future__ import annotations

import re
from datetime import date
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, Request

from cherry_core.catalog.load import LoadedCard
from cherry_core.catalog.models import Rules
from cherry_core.engine.cond import month_of
from cherry_core.engine.models import SpendStatus, UserCard
from cherry_core.engine.spend import new_card_tier

from ..deps import today

router = APIRouter(prefix="/catalog")
# 지난달 쓴 금액의 상한 1억 원. DB 정수 범위를 넘는 값이 500이 되지 않게 막는다
MAX_SPEND = 100_000_000
_SPACE = re.compile(r"\s+")


def _key(text: str) -> str:
    return _SPACE.sub("", text).casefold()


def registrable(request: Request, card_id: str) -> LoadedCard:
    """판매 중인 카드만 새로 등록한다. 단종 카드는 검색에서 숨긴다. E19"""
    loaded = request.app.state.catalog.cards.get(card_id)
    if loaded is None or loaded.card.status != "on_sale":
        raise HTTPException(404, "등록할 수 있는 카드가 아니다")
    return loaded


def benefits_at(rules: Rules, card: UserCard, month: date, status: SpendStatus) -> list[str]:
    """그 달에 받는 혜택 제목. 엔진처럼 새 카드 특례 구간을 혜택마다 본다. 하한과 상한을 모두 넣는다

    옵션을 골라야 받는 혜택은 고른 선택지나 기본값에 맞을 때만 넣는다. 고르지 않은 패키지끼리는 서로 배타라 함께 보이면 안 된다.
    옵션은 슬라이스 5에서 묻는다.
    """
    prev = status.prev_month_counted
    base = max(t for t in rules.tiers if t <= prev) if prev is not None else (status.tier or 0)
    # 엔진처럼 고르지 않은 옵션은 기본값으로 본다. 기본값이 없으면 그 옵션의 혜택은 뺀다
    chosen = {o.key: o.default for o in rules.options}
    chosen |= {
        p.option: p.choice for p in sorted(card.options, key=lambda p: p.effective_from) if p.effective_from <= month
    }
    out = []
    for b in rules.benefits:
        # ponytail: when의 첫 단계만 본다. any_of 안의 옵션 조건은 놓친다. 지금 카탈로그에는 없다
        if any(c.option and not all(chosen.get(k) in v for k, v in c.option.items()) for c in b.when):
            continue
        tier, _ = new_card_tier(card, month, rules, b.key, base)
        lo = b.tiers.start if b.tiers and b.tiers.start is not None else rules.tiers[0]
        hi = b.tiers.end if b.tiers and b.tiers.end is not None else rules.tiers[-1]
        if lo <= tier <= hi:
            out.append(b.title)
    return out


@router.get("/issuers")
def issuers(request: Request) -> list[dict]:
    cat = request.app.state.catalog
    selling = {c.card.issuer for c in cat.cards.values() if c.card.status == "on_sale"}
    rows = [{"code": code, "name": i.issuer.name} for code, i in cat.issuers.items() if code in selling]
    return sorted(rows, key=lambda r: r["name"])


@router.get("/cards")
def cards(request: Request, q: str = "", issuer: str | None = None) -> list[dict]:
    cat, engine = request.app.state.catalog, request.app.state.engine
    # 구간은 미리보기, 홈과 같게 이달 1일의 개정에서 읽는다. 엔진이 이달 구간을 그 개정으로 정한다
    month, want = month_of(today(request)), _key(q)
    out = []
    for loaded in cat.cards.values():
        c = loaded.card
        issuer_name = cat.issuers[c.issuer].issuer.name
        if c.status != "on_sale" or (issuer and c.issuer != issuer):
            continue
        if want and not any(want in _key(n) for n in (c.name, *c.search_names, issuer_name)):
            continue
        found = engine.ctx.rules_on(c.id, month)
        fees = [f.amount for f in c.annual_fees if f.scope == "domestic"] or [f.amount for f in c.annual_fees]
        out.append(
            {
                "id": c.id,
                "name": c.name,
                "issuer": c.issuer,
                "issuer_name": issuer_name,
                "kind": c.kind,
                "annual_fee": min(fees) if fees else None,
                "tiers": [t for t in found[1].tiers if t > 0] if found else [],
            }
        )
    return sorted(out, key=lambda r: (r["issuer_name"], r["name"]))


@router.get("/cards/{card_id}/preview")
def preview(
    card_id: str,
    request: Request,
    prev: Annotated[int | None, Query(ge=0, le=MAX_SPEND)] = None,
    started_on: date | None = None,
) -> dict:
    """등록 시트. 지난달 쓴 금액으로 이번 달 구간을 보여 준다. 비우면 최저 구간이다. E1"""
    registrable(request, card_id)
    day = today(request)
    month = month_of(day)
    card = UserCard(
        id="preview", card_id=card_id, registered_on=day, assumed_prev_month_spend=prev, started_on=started_on
    )
    status = request.app.state.engine.spend_status(card, [], month)
    found = request.app.state.engine.ctx.rules_on(card_id, month)
    return {
        "tier": status.tier,
        "tier_source": status.tier_source,
        "tiers": [t for t in found[1].tiers if t > 0] if found else [],
        "benefits": benefits_at(found[1], card, month, status) if found and status.tier is not None else [],
        "warnings": [w.code for w in status.warnings],
    }
