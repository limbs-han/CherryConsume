"""계산 엔진의 입력과 출력. 설계는 docs/work/002-calc-engine/design.md 1절과 5절."""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from cherry_core.catalog.models import Billing, Region

Won = Annotated[int, Field(strict=True, ge=0)]


class Base(BaseModel):
    model_config = ConfigDict(extra="forbid")


# 입력


class OptionPick(Base):
    option: str
    choice: str
    effective_from: date


class UserCard(Base):
    """보유 카드 한 장. 사실은 사람 사실과 카드 사실을 합쳐 넣는다."""

    id: str
    card_id: str
    registered_on: date | None = None
    started_on: date | None = None
    options: list[OptionPick] = []
    facts: dict[str, bool | int | str] = {}
    assumed_prev_month_spend: Won | None = None
    last_payment_method: str | None = None
    removed: bool = False


class AppliedBenefit(Base):
    """결제 한 건이 받은 혜택 하나. amount는 보상 단위(원이나 포인트), value는 원 가치다."""

    key: str
    amount: Won
    value: Won
    base: Won


class Payment(Base):
    id: str
    user_card_id: str
    amount: Annotated[int, Field(strict=True, gt=0)]
    paid_at: AwareDatetime
    merchant: str | None = None
    category: str | None = None
    channel: Literal["online", "offline"] = "offline"
    region: Region = "domestic"
    installment_months: Annotated[int, Field(strict=True, ge=1)] = 1
    interest_free: bool = False
    payment_method: str | None = None
    billing: Billing | None = None
    cancelled_amount: Won = 0
    cancelled_at: AwareDatetime | None = None
    benefits: list[AppliedBenefit] | None = None

    @model_validator(mode="after")
    def _cancellation(self) -> Payment:
        if self.cancelled_amount > self.amount:
            raise ValueError("취소 금액이 결제 금액보다 크다")
        if self.cancelled_amount and self.cancelled_at is None:
            raise ValueError("취소 금액이 있으면 취소 시각도 있어야 한다. E5")
        return self


class Query(Base):
    """추천 질문. 금액이 없으면 1만원으로 계산한다. E11"""

    merchant: str | None = None
    category: str | None = None
    amount: Annotated[int, Field(strict=True, gt=0)] | None = None
    channel: Literal["online", "offline"] | None = None
    region: Region | None = None
    payment_method: str | None = None


# 출력


class Warn(Base):
    code: str
    benefit: str | None = None
    data: dict[str, Any] = {}


class SpendPart(Base):
    """결제 한 건이 어느 달 실적에 얼마를 넣는지. 취소는 음수다."""

    month: date
    amount: int


class ConditionalBenefit(Base):
    user_card_id: str
    benefit: str
    needs: dict[str, Any]
    extra: Won


class PaymentResult(Base):
    payment_id: str
    benefits: list[AppliedBenefit] = []
    spend: list[SpendPart] = []
    conditional: list[ConditionalBenefit] = []
    warnings: list[Warn] = []

    @property
    def value(self) -> int:
        return sum(b.value for b in self.benefits)


class SpendStatus(Base):
    user_card_id: str
    month: date
    counted: int
    tier: int | None
    tier_source: Literal["prev_month", "assumed", "new_card", "none", "unsupported"]
    prev_month_counted: int | None
    to_keep: int | None
    next_tier: int | None
    to_next: int | None
    warnings: list[Warn] = []


class LimitUse(Base):
    key: str
    benefit: str | None
    per: str
    used_amount: int
    used_count: int
    used_base: int
    cap_amount: int | None
    cap_count: int | None
    cap_base: int | None


class LockedBenefit(Base):
    user_card_id: str
    benefit: str
    required_tier: int
    remaining_this_month: int
    value_if_unlocked: int


class Recommendation(Base):
    user_card_id: str
    card_id: str
    value: int
    benefits: list[AppliedBenefit] = []
    counted: bool
    to_keep: int | None
    to_next: int | None
    locked: list[LockedBenefit] = []
    conditional: list[ConditionalBenefit] = []
    warnings: list[Warn] = []
