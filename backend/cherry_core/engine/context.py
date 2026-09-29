"""카탈로그에서 계산에 쓰는 값을 서버가 켜질 때 한 번 준비한다. 설계 4.4의 1"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from datetime import date
from fractions import Fraction

from cherry_core.catalog.load import Catalog
from cherry_core.catalog.models import Rules
from cherry_core.catalog.resolve import ResolvedRevision

from .cond import Situation, local
from .models import Payment, UserCard

FUEL_PRICE_KEY = "fuel_price_gasoline"
_BENEFIT_IN_PATH = re.compile(r"benefits\[([^\]]+)\]")


def frac(x: float) -> Fraction:
    """카탈로그의 비율 1.3을 정확한 분수 13/10으로 바꾼다. 부동소수점으로 돈을 계산하지 않기 위해서다"""
    return Fraction(str(x))


def at_tier(value, tier: int):
    """구간표면 이번 구간 이하 키 중 가장 큰 키의 값, 아니면 그 값"""
    if isinstance(value, dict):
        keys = [k for k in value if k <= tier]
        return value[max(keys)] if keys else None
    return value


def round_money(x: Fraction, mode: str = "floor") -> int:
    if mode == "round":
        return math.floor(x + Fraction(1, 2))
    step = {"floor": 1, "floor10": 10, "floor100": 100}[mode]
    return math.floor(x / step) * step


@dataclass
class Ctx:
    catalog: Catalog
    point_value: dict[str, Fraction] = field(default_factory=dict)
    children: dict[str, list[str]] = field(default_factory=dict)
    fuel_price: Fraction | None = None
    assumed: dict[str, dict[str | None, list[str]]] = field(default_factory=dict)

    def __post_init__(self) -> None:
        cat = self.catalog
        self.point_value = {k: frac(p.won_per_point) for k, p in cat.point_programs.items()}
        for code in sorted(cat.categories):
            if "." in code:
                self.children.setdefault(code.split(".")[0], []).append(code)
        ref = cat.reference.get(FUEL_PRICE_KEY)
        self.fuel_price = frac(ref.value) if ref else None
        for cid, card in cat.cards.items():
            by_benefit: dict[str | None, list[str]] = {}
            for q in card.card.open_questions:
                m = _BENEFIT_IN_PATH.search(q.path)
                by_benefit.setdefault(m.group(1) if m else None, []).append(q.path)
            self.assumed[cid] = by_benefit

    def rules_on(self, card_id: str, day: date) -> tuple[ResolvedRevision, Rules] | None:
        revisions = self.catalog.cards[card_id].revisions
        current = [r for r in revisions if r[0].effective_from <= day]
        if current:
            return current[-1]
        return revisions[0] if revisions[0][0].effective_from_estimated else None

    def category(self, p: Payment) -> str:
        if p.category:
            return p.category
        m = self.catalog.merchants.get(p.merchant or "")
        return m.category if m else "other"

    def billing(self, p: Payment) -> str:
        if p.billing:
            return p.billing
        m = self.catalog.merchants.get(p.merchant or "")
        return m.billing if m else "normal"

    def situation(self, card: UserCard, p: Payment) -> Situation:
        return Situation(
            at=local(p.paid_at),
            amount=p.amount - p.cancelled_amount,
            merchant=p.merchant,
            category=self.category(p),
            channel=p.channel,
            region=p.region,
            installment_months=p.installment_months,
            interest_free=p.interest_free,
            payment_method=p.payment_method,
            billing=self.billing(p),
            card=card,
        )
