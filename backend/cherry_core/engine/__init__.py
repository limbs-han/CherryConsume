"""계산 엔진. 서버가 켜질 때 Engine을 한 번 만들고 요청마다 함수를 부른다. 설계는 docs/work/002-calc-engine/design.md"""

from __future__ import annotations

from datetime import date, datetime
from pathlib import Path

from cherry_core.catalog.load import Catalog, load_catalog

from . import price as _price
from . import recommend as _recommend
from .context import Ctx
from .models import LimitUse, Payment, PaymentResult, Query, Recommendation, SpendStatus, UserCard


class Engine:
    def __init__(self, catalog: Catalog) -> None:
        if [p for p in catalog.problems if p.level == "error"]:
            raise ValueError("오류가 있는 카탈로그로는 계산하지 않는다. 설계 문서 6.8")
        self.ctx = Ctx(catalog)

    @classmethod
    def from_dir(cls, root: Path) -> Engine:
        return cls(load_catalog(root))

    def price_payment(self, card: UserCard, history: list[Payment], payment: Payment) -> PaymentResult:
        return _price.price_payment(self.ctx, card, history, payment)

    def price_month(
        self, card: UserCard, payments: list[Payment], month: date | None = None, final: bool = False
    ) -> list[PaymentResult]:
        return _price.price_month(self.ctx, card, payments, month, final)

    def spend_status(self, card: UserCard, payments: list[Payment], month: date) -> SpendStatus:
        return _price.spend_status(self.ctx, card, payments, month)

    def limit_status(self, card: UserCard, payments: list[Payment], now: datetime) -> list[LimitUse]:
        return _price.limit_status(self.ctx, card, payments, now)

    def recommend(
        self, cards: list[UserCard], payments: dict[str, list[Payment]], queries: list[Query], now: datetime
    ) -> list[list[Recommendation]]:
        return _recommend.recommend(self.ctx, cards, payments, queries, now)
