"""카탈로그 2판 모델. 설계는 docs/work/001-catalog-schema-v2/design.md 2절과 3절."""

from __future__ import annotations

from datetime import date
from itertools import pairwise
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Key = Annotated[str, Field(pattern=r"^[a-z0-9][a-z0-9_-]*$")]
Money = Annotated[int, Field(strict=True, ge=0)]
Count = Annotated[int, Field(strict=True, ge=1)]
Rate = Annotated[float, Field(gt=0, le=100)]
MoneyOrTable = Money | dict[Money, Money]
CountOrTable = Count | dict[Money, Count]
RateOrTable = Rate | dict[Money, Rate]
Ratio = Literal[0, 0.5, 1]
HHMM = Annotated[str, Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")]
Weekday = Literal["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
Region = Literal["domestic", "overseas"]
Billing = Literal["normal", "autopay", "subscription", "postpaid_transit", "app_prepay", "in_app"]
Per = Literal["txn", "day", "month", "quarter", "year", "period", "lifetime"]


class Base(BaseModel):
    model_config = ConfigDict(extra="forbid")


# 2.4 조건


class AmountRange(Base):
    min: Money | None = None
    below: Money | None = None

    @model_validator(mode="after")
    def check_range(self) -> AmountRange:
        if self.min is None and self.below is None:
            raise ValueError("min과 below 중 하나는 쓴다")
        if self.min is not None and self.below is not None and self.min >= self.below:
            raise ValueError("min은 below보다 작아야 한다")
        return self


class Days(Base):
    days: list[Weekday] | None = Field(default=None, alias="in")
    holidays: Literal["ignore", "include", "exclude", "only"] = "ignore"

    @model_validator(mode="after")
    def check_days(self) -> Days:
        if not self.days and self.holidays != "only":
            raise ValueError("in이 비어 있으면 holidays: only만 쓸 수 있다")
        return self


class TimeRange(Base):
    start: HHMM = Field(alias="from")
    end: HHMM = Field(alias="to")


class CardMonth(Base):
    min: Annotated[int, Field(strict=True, ge=0)] | None = None
    max: Annotated[int, Field(strict=True, ge=0)] | None = None


class MonthTotal(Base):
    min: Money


class Condition(Base):
    """항목 하나에 적은 조건은 전부 맞아야 한다."""

    amount: AmountRange | None = None
    day: Days | None = None
    time: TimeRange | None = None
    months: list[Annotated[int, Field(strict=True, ge=1, le=12)]] | None = None
    region: Region | None = None
    channel: Literal["online", "offline"] | None = None
    interest_free: bool | None = None
    payment: list[Key] | None = None
    payment_not: list[Key] | None = None
    billing: list[Billing] | None = None
    billing_not: list[Billing] | None = None
    option: dict[Key, list[Key]] | None = None
    fact: Key | None = None
    ranked: Key | None = None
    card_month: CardMonth | None = None
    month_total: MonthTotal | None = None
    any_of: list[Condition] | None = None

    @model_validator(mode="after")
    def check_not_empty(self) -> Condition:
        if not any(getattr(self, name) is not None for name in type(self).model_fields):
            raise ValueError("빈 조건")
        return self


# 2.3 대상, 2.5 보상


class Target(Base):
    all: bool = False
    categories: list[str] = []
    merchants: list[Key] = []
    exclude_categories: list[str] = []
    exclude_merchants: list[Key] = []

    @model_validator(mode="after")
    def check_target(self) -> Target:
        if self.all and (self.categories or self.merchants):
            raise ValueError("all: true와 categories, merchants를 함께 쓰지 않는다")
        if not self.all and not (self.categories or self.merchants):
            raise ValueError("all: true나 categories, merchants 중 하나를 쓴다")
        return self


class PerUnit(Base):
    unit: Annotated[int, Field(strict=True, ge=1)]
    amount: Money


class Reward(Base):
    type: Literal["billing_discount", "onsite_discount", "points", "cashback"]
    program: Key | None = None
    rate: RateOrTable | None = None
    fixed: MoneyOrTable | None = None
    per_unit: PerUnit | None = None
    per_liter: Money | None = None
    round: Literal["floor", "round", "floor10", "floor100"] = "floor"
    basis: Literal["txn", "month_total"] = "txn"

    @model_validator(mode="after")
    def check_reward(self) -> Reward:
        given = [n for n in ("rate", "fixed", "per_unit", "per_liter") if getattr(self, n) is not None]
        if len(given) != 1:
            raise ValueError(f"rate, fixed, per_unit, per_liter 중 정확히 하나를 쓴다. 지금은 {given or '없음'}")
        if (self.type == "points") != (self.program is not None):
            raise ValueError("program은 type이 points일 때 반드시 쓰고, 그 밖에는 쓰지 않는다")
        return self


# 2.6 한도


class Adjust(Base):
    when: Condition
    amount: MoneyOrTable | None = None
    count: CountOrTable | None = None
    base: MoneyOrTable | None = None
    multiply: Annotated[float, Field(gt=0)] | None = None
    add: Money | None = None

    @model_validator(mode="after")
    def check_adjust(self) -> Adjust:
        if not self.model_fields_set & {"amount", "count", "base", "multiply", "add"}:
            raise ValueError("amount, count, base, multiply, add 중 하나는 쓴다. null은 제한 없음이다")
        return self


class Limit(Base):
    """혜택 하나의 한도. 공유 한도를 가리키거나 직접 적는다."""

    shared: Key | None = None
    per: Per | None = None
    amount: MoneyOrTable | None = None
    count: CountOrTable | None = None
    base: MoneyOrTable | None = None
    adjust: list[Adjust] = []

    @model_validator(mode="after")
    def check_limit(self) -> Limit:
        if self.shared is not None:
            if self.model_fields_set - {"shared"}:
                raise ValueError("shared를 쓰면 다른 칸은 공유 한도 쪽에 쓴다")
        elif self.per is None or (self.amount is None and self.count is None and self.base is None):
            raise ValueError("per와 amount, count, base 중 하나 이상을 쓴다")
        return self


class SharedLimit(Base):
    """여러 혜택이 같이 쓰는 한도."""

    key: Key
    per: Per
    amount: MoneyOrTable | None = None
    count: CountOrTable | None = None
    base: MoneyOrTable | None = None
    adjust: list[Adjust] = []

    @model_validator(mode="after")
    def check_shared(self) -> SharedLimit:
        if self.amount is None and self.count is None and self.base is None:
            raise ValueError("amount, count, base 중 하나 이상을 쓴다")
        return self


# 2.7 중복 묶음, 2.8 옵션과 자동 선택, 2.9 사실


class Stack(Base):
    key: Key
    pick: Literal["best", "priority"] = "best"
    order: list[Key] = []
    spill: Literal["none", "split"] = "none"


class Choice(Base):
    key: Key
    title: str


class Option(Base):
    key: Key
    title: str
    choices: list[Choice] = Field(min_length=1)
    default: Key | None = None
    change: Literal["immediate", "next_month"]
    unsupported: list[Key] = []

    @model_validator(mode="after")
    def check_option(self) -> Option:
        keys = [c.key for c in self.choices]
        if len(keys) != len(set(keys)):
            raise ValueError("choices의 key가 겹친다")
        if self.default is not None and self.default not in keys:
            raise ValueError(f"default {self.default}가 choices에 없다")
        if set(self.unsupported) - set(keys):
            raise ValueError("unsupported는 choices의 key만 쓴다")
        return self


class Ranked(Base):
    key: Key
    top: CountOrTable
    by: Literal["month_amount"] = "month_amount"


class Fact(Base):
    key: Key
    type: Literal["bool", "month", "choice"]
    scope: Literal["user", "card"]
    ask: str
    choices: list[str] | None = None

    @model_validator(mode="after")
    def check_fact(self) -> Fact:
        if (self.type == "choice") != (self.choices is not None):
            raise ValueError("choices는 type이 choice일 때만, 그리고 반드시 쓴다")
        return self


# 2.10 실적 규칙과 신규 발급 특례, 2.11 공통 제외


class CancellationOverride(Base):
    when: Condition
    use: Literal["cancel_month", "original_month"]


class Spend(Base):
    basis: Literal["prev_calendar_month", "billing_cycle", "none"]
    regions: list[Region] = ["domestic", "overseas"]
    exclude_categories: list[str] = []
    interest_free: Literal["count", "exclude"] = "count"
    installment: Literal["full_at_purchase", "per_installment_month"]
    cancellation: Literal["cancel_month", "original_month"]
    cancellation_overrides: list[CancellationOverride] = []
    month_offset: dict[str, Annotated[int, Field(strict=True, ge=1, le=2)]] = {}
    exclude_applied: Ratio = 0


class NewCard(Base):
    start: Literal["registration", "first_use", "issue", "receipt"] = Field(alias="from")
    until: Literal["next_month_end"]
    tier: Money
    tier_by_benefit: dict[Key, Money] = {}


class BenefitExclusions(Base):
    categories: list[str] = []
    when_any: list[Condition] = []
    unmodeled: list[str] = []


# 혜택과 개정


class BenefitTiers(Base):
    start: Money | None = Field(default=None, alias="from")
    end: Money | None = Field(default=None, alias="to")
    waived_when: Condition | None = None

    @model_validator(mode="after")
    def check_tiers(self) -> BenefitTiers:
        if self.start is None and self.end is None:
            raise ValueError("from이나 to 중 하나는 쓴다")
        return self


class Benefit(Base):
    key: Key
    title: str
    source: Key | None = None
    target: Target
    when: list[Condition] = []
    reward: Reward
    limits: list[Limit] = []
    tiers: BenefitTiers | None = None
    stack: Key = "main"
    exclude_applied: Ratio | None = None
    valid_from: date | None = None
    valid_until: date | None = None
    unmodeled: list[str] = []
    notes: str | None = None

    @model_validator(mode="after")
    def check_benefit(self) -> Benefit:
        if self.valid_from and self.valid_until and self.valid_from > self.valid_until:
            raise ValueError("valid_from은 valid_until 이하여야 한다")
        return self


class Rules(Base):
    """카드사 기본값과 패치를 합친 뒤의 개정 하나. DB와 엔진은 이것만 본다."""

    tiers: list[Money] = Field(min_length=1)
    spend: Spend
    new_card: NewCard | None = None
    benefit_exclusions: BenefitExclusions = Field(default_factory=BenefitExclusions)
    facts: list[Fact] = []
    options: list[Option] = []
    ranked: list[Ranked] = []
    limits: list[SharedLimit] = []
    stacks: list[Stack] = []
    benefits: list[Benefit] = []
    unmodeled: list[str] = []


# 카드 파일


class AnnualFee(Base):
    brand: str | None = None
    scope: Literal["domestic", "global"]
    form: Literal["physical", "mobile"] = "physical"
    amount: Money


class Source(Base):
    id: Key
    kind: Literal["product_page", "manual_pdf", "terms_pdf", "promo_page", "notice", "api"]
    url: Annotated[str, Field(pattern=r"^https://")]
    fetched_at: date
    text_sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")] | None = None
    review_no: str | None = None
    review_valid_until: date | None = None


class OpenQuestion(Base):
    path: str
    question: str
    assumed: str | int | float | bool | None = None


class RevisionEntry(Base):
    """파일에 적힌 개정. 규칙 칸은 합친 뒤 Rules로 검사하므로 여기서는 받아 둔다."""

    model_config = ConfigDict(extra="allow")

    effective_from: date
    effective_from_estimated: bool = False
    source: Key
    patch: dict[str, Any] | None = None

    @model_validator(mode="after")
    def check_entry(self) -> RevisionEntry:
        if self.patch is not None and self.model_extra:
            raise ValueError(f"patch와 규칙 칸을 함께 쓰지 않는다: {sorted(self.model_extra)}")
        return self


class CardFile(Base):
    schema_version: Literal[2]
    id: Annotated[str, Field(pattern=r"^[a-z0-9]+-[a-z0-9-]+$")]
    issuer: Key
    name: str
    search_names: list[str] = []
    kind: Literal["credit", "check"]
    product_codes: list[str] = []
    status: Literal["on_sale", "discontinued", "closed"]
    status_since: date | None = None
    annual_fees: list[AnnualFee] = []
    sources: list[Source] = Field(min_length=1)
    checked_at: date
    revisions: list[RevisionEntry] = Field(min_length=1)
    open_questions: list[OpenQuestion] = []
    notes: str | None = None

    @model_validator(mode="after")
    def check_card(self) -> CardFile:
        ids = [s.id for s in self.sources]
        if len(ids) != len(set(ids)):
            raise ValueError("sources의 id가 겹친다")
        days = [r.effective_from for r in self.revisions]
        if any(a >= b for a, b in pairwise(days)):
            raise ValueError("revisions는 effective_from 오름차순이고 날짜가 겹치지 않아야 한다")
        if self.revisions[0].patch is not None:
            raise ValueError("첫 개정은 patch로 쓸 수 없다")
        return self


# 카드사 파일


class Collect(Base):
    list_url: Annotated[str, Field(pattern=r"^https://")]
    method: Literal["api", "browser", "manual", "blocked"]
    interval_days: Literal[14, 30]
    notice_url: Annotated[str, Field(pattern=r"^https://")] | None = None


class IssuerDefaults(Base):
    """카드사 공통 규칙. 칸 안은 카드 규칙과 합친 뒤 Rules로 검사한다."""

    effective_from: date
    effective_from_estimated: bool = False
    spend: dict[str, Any] | None = None
    new_card: dict[str, Any] | None = None
    benefit_exclusions: dict[str, Any] | None = None


class IssuerFile(Base):
    schema_version: Literal[2]
    id: Key
    name: str
    collect: Collect | None = None
    defaults: list[IssuerDefaults] = []
    open_questions: list[OpenQuestion] = []
    notes: str | None = None

    @model_validator(mode="after")
    def check_issuer(self) -> IssuerFile:
        days = [d.effective_from for d in self.defaults]
        if any(a >= b for a, b in pairwise(days)):
            raise ValueError("defaults는 effective_from 오름차순이고 날짜가 겹치지 않아야 한다")
        return self


# 공통 파일


class CategoryChild(Base):
    code: Key
    name: str
    kakao: str | None = None


class Category(Base):
    code: Key
    name: str
    kakao: str | None = None
    children: list[CategoryChild] = []


class Merchant(Base):
    key: Key
    name: str
    category: str
    aliases: list[str] = Field(min_length=1)
    billing: Billing = "normal"


class PaymentMethod(Base):
    key: Key
    name: str
    statement_names: list[str] = []


class PointProgram(Base):
    key: Key
    name: str
    won_per_point: Annotated[float, Field(gt=0)] = 1


class ReferenceValue(Base):
    key: Key
    value: Annotated[float, Field(gt=0)]
    unit: str
    as_of: date
    source: str
