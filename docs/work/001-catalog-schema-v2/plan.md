# 001 계획

> **에이전트가 실행할 때:** superpowers:subagent-driven-development로 과제마다 새 에이전트를 띄우고 과제 사이에 검토한다. 한 세션에서 직접 하면 superpowers:executing-plans를 쓴다. 단계는 `- [ ]` 체크박스로 표시하고 끝나면 `- [x]`로 바꾼다.

**목표:** 카탈로그 2판의 모델과 검증기를 만들고, 카드 20장을 2판으로 옮겨 intent.md의 성공 기준을 모두 채운다.

**구조:** `backend/cherry_core/catalog/`에 다섯 가지를 둔다.
- Pydantic 모델
- 카드사 기본값과 패치를 합치는 해석기
- 교차 검사
- 고정 저장 형식
- check와 format 명령

20장은 네 단계로 옮긴다.
1. 1판에서 기계적으로 변환한다.
2. 카드사 공통 규칙을 카드사 파일로 올린다.
3. 에이전트가 notes에 문장으로 적힌 조건을 구조로 옮긴다.
4. 다른 에이전트가 공식 원문과 대조한다.

**기술:** Python 3.12, uv, Pydantic 2, PyYAML, pytest, ruff. 셸은 Git Bash다.

**코드의 근거:** 2026-09-29에 임시 폴더에서 먼저 돌려 봤다.
- 과제 1부터 6까지의 코드와 테스트: 테스트 70개가 통과했고 ruff 검사도 통과했다.
- 과제 8부터 10까지의 작업 스크립트: 1판 20장의 복사본을 변환하고 카드사 공통 규칙까지 올려 봤다. 검증 오류는 0개였고, 경고는 상품 코드가 빈 20건이었다. 사람이 판단할 목록은 131건이었다. 여기에 카드마다 첫 개정 시행일 조사 1건씩, 20건을 더한다.
- 과제 15의 성공 기준 테스트: 그 복사본에서 5개 중 4개가 통과했다. 남은 하나는 과제 12에서 넣을 IBK 개정이 있어야 통과한다.

**걸리는 시간**

| 과제 | 시간 |
|---|---|
| 1~6 검증기 | 2시간. 코드가 아래에 모두 있어 옮겨 쓰며 테스트를 돌린다 |
| 7~11 이동, 공통 파일, 변환, 공통 규칙, 에이전트 정의 | 1시간 |
| 12 카드별 판단과 시행일 조사 | 에이전트 6개를 동시에 돌려 3~4시간 |
| 13 원문 대조와 수정 | 1~2시간 |
| 14 IBK 확인 | 사용자 답을 받은 뒤 10분 |
| 15~18 성공 기준, 훅 전환, 문서 합치기, 마무리 | 2시간 |

## 설계 단계

- [x] 방식 선택과 1절 파일 구조, 갱신 흐름. 검증: 사용자 확정 2026-09-28
- [x] 2절 혜택 규칙. 검증: 사용자 확정 2026-09-28
- [x] 3절 결제와 보유 카드 입력, DB 변경. 검증: 사용자 확정 2026-09-28
- [x] 4절 검증 규칙과 20장 옮기는 방법. 검증: 사용자 확정 2026-09-28
- [x] design.md 전체 검토. 검증: 사용자 승인 2026-09-28
- [x] 구현 계획 검토. 이 문서와 design.md 4.6. 검증: 사용자 승인 2026-09-29. 계획 실행 중의 커밋은 한 번에 허락받았다

## 지켜야 할 것

모든 과제에 적용한다.

- 금액은 원 단위 정수다. 모델의 금액 칸은 `strict=True` 정수라 문자열이나 소수를 받지 않는다.
- 카탈로그 값은 카드사 공식 페이지, 카드사가 올린 설명서와 약관에서만 옮긴다. 확인하지 못한 값은 추측하지 않고 `open_questions`에 남긴다.
- 카탈로그 파일에는 주석을 쓰지 않는다. 사람용 메모는 `notes`에 쓴다.
- 한 번 정한 카드 id와 혜택 key는 바꾸지 않는다. 과제 12에서 혜택을 나눌 때만 새 key를 만든다.
- 커밋은 사용자가 커밋을 요청했거나, 계획 실행을 맡기며 커밋까지 허락했을 때만 한다. 허락이 없으면 커밋 지점에서 멈추고 묻는다. 절차는 `/commit` 스킬을 따르고 `--no-verify`는 쓰지 않는다.
- 명령은 저장소 루트에서 실행한다.
  - 테스트: `uv run --project backend pytest -q`
  - 카탈로그 검증: `uv run --project backend python -m cherry_core.catalog check`
  - 카탈로그 형식 고치기: `uv run --project backend python -m cherry_core.catalog format`
- 작업 스크립트는 그 세션의 scratchpad 폴더에 두고 저장소에 넣지 않는다. 아래에서 `$SCRATCH`는 그 폴더다. 스크립트 원본은 이 문서에 있다. 명령마다 셸이 새로 뜨는 환경이면 명령 앞에 `SCRATCH=<그 폴더>`를 붙인다.
- 과제 16 전까지 파일 수정 뒤 훅은 1판 스크립트를 부른다. 1판 스크립트는 `catalog/cards/*.yaml`만 보므로 과제 7 이후에는 검사할 카드가 없다. 그동안은 위 검증 명령을 직접 돌린다.

## 파일

| 파일 | 할 일 | 과제 |
|---|---|---|
| `backend/pyproject.toml`, `backend/uv.lock` | 새로. 패키지와 의존성 | 1 |
| `backend/cherry_core/catalog/models.py` | 새로. 2절과 3절 모델 | 1 |
| `backend/cherry_core/catalog/resolve.py` | 새로. 기본값과 패치 합치기, 날짜로 개정 고르기 | 2 |
| `backend/cherry_core/catalog/canonical.py` | 새로. 고정 저장 형식 | 3 |
| `backend/cherry_core/catalog/load.py` | 새로. 파일 읽기와 오류 위치 | 4 |
| `backend/cherry_core/catalog/check.py` | 새로. 교차 검사와 경고 | 5 |
| `backend/cherry_core/catalog/__main__.py` | 새로. check, format 명령 | 6 |
| `backend/tests/catalog/` | 새로. 과제마다 테스트 | 1~6, 15 |
| `catalog/cards/<카드사>/<id>.yaml` | 옮기고 2판으로 다시 쓰기 | 7, 9, 10, 12~14 |
| `catalog/categories.yaml`, `catalog/merchants.yaml` | 2판으로 다시 쓰기 | 8 |
| `catalog/payment_methods.yaml`, `catalog/point_programs.yaml`, `catalog/reference.yaml` | 새로 | 8 |
| `catalog/issuers/<카드사>.yaml` | 새로 | 8, 10, 12 |
| `docs/work/001-catalog-schema-v2/judgment.md` | 새로. 카드별 판단 목록과 결과 | 9, 12~15 |
| `.claude/agents/card-researcher.md`, `.claude/agents/card-verifier.md`, `.claude/rules/catalog.md` | 2판에 맞추기 | 11 |
| `.claude/hooks/after_edit.py`, `.claude/settings.json`, `.claude/CLAUDE.md`, `README.md` | 2판 검증기로 전환 | 16 |
| `tools/validate_catalog.py` | 지우기 | 16 |
| `docs/2026-09-19-cherryconsume-design.md`, `docs/erd.md`, `docs/erd.html`, `docs/scenarios.md` | 결론 합치기 | 17 |

---

## 과제 1: backend 패키지와 모델

**파일**
- 새로: `backend/pyproject.toml`, `backend/cherry_core/__init__.py`, `backend/cherry_core/catalog/__init__.py`, `backend/tests/__init__.py`, `backend/tests/catalog/__init__.py`
- 새로: `backend/cherry_core/catalog/models.py`
- 테스트: `backend/tests/catalog/test_models.py`

**인터페이스**
- 내놓는 것: `Condition`, `Target`, `Reward`, `Limit`, `SharedLimit`, `Adjust`, `Stack`, `Option`, `Ranked`, `Fact`, `Spend`, `NewCard`, `BenefitExclusions`, `BenefitTiers`, `Benefit`, `Rules`, `RevisionEntry`, `CardFile`, `IssuerFile`, `Category`, `Merchant`, `PaymentMethod`, `PointProgram`, `ReferenceValue`.
- 모든 모델은 모르는 칸을 받지 않는다. `RevisionEntry`만 규칙 칸을 그대로 받아 두고, 과제 4에서 합친 뒤 `Rules`로 검사한다.
- 파일의 `in`, `from`, `to`는 파이썬 칸 이름이 `days`, `start`, `end`이고 별칭으로 받는다.

- [x] **1단계: 패키지 파일을 쓴다**

`backend/pyproject.toml`

```toml
[project]
name = "cherry-core"
version = "0.1.0"
description = "체리컨슘 카탈로그와 계산 엔진"
requires-python = ">=3.12"
dependencies = ["pydantic>=2.9", "pyyaml>=6.0"]

[dependency-groups]
dev = ["pytest>=8.3", "ruff>=0.8"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["cherry_core"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.ruff]
line-length = 120
```

`backend/cherry_core/__init__.py`, `backend/tests/__init__.py`, `backend/tests/catalog/__init__.py`는 빈 파일이다. `backend/cherry_core/catalog/__init__.py`는 한 줄이다.

`backend/cherry_core/catalog/__init__.py`

```python
"""카탈로그 2판 모델, 합치기, 검증, 저장 형식."""
```

- [x] **2단계: 의존성을 고정한다**

```bash
uv lock --project backend
```

기대: `backend/uv.lock`이 생기고 `Resolved` 줄이 나온다.

- [x] **3단계: 커밋 지점**

```bash
git add backend/pyproject.toml backend/uv.lock backend/cherry_core/__init__.py backend/cherry_core/catalog/__init__.py backend/tests/__init__.py backend/tests/catalog/__init__.py
git commit -m "build: 계산 엔진 패키지와 의존성 설정 추가" -m "작업 001. Python 3.12, pydantic, pyyaml, 개발용 pytest와 ruff"
```

- [x] **4단계: 실패하는 테스트를 쓴다**

`backend/tests/catalog/test_models.py`

```python
"""한 객체 안에서 끝나는 규칙. 설계 2.4부터 2.11."""

import pytest
from pydantic import ValidationError

from cherry_core.catalog.models import Adjust, Condition, Fact, Limit, Option, Reward, SharedLimit, Target


def test_reward_needs_exactly_one_amount_rule():
    Reward(type="billing_discount", rate=10)
    Reward(type="billing_discount", per_unit={"unit": 20000, "amount": 1000})
    with pytest.raises(ValidationError, match="정확히 하나"):
        Reward(type="billing_discount", rate=10, fixed=1000)
    with pytest.raises(ValidationError, match="정확히 하나"):
        Reward(type="billing_discount")


def test_points_need_program_and_others_do_not():
    Reward(type="points", program="mysinhan_point", rate=1.5)
    with pytest.raises(ValidationError, match="program"):
        Reward(type="points", rate=1.5)
    with pytest.raises(ValidationError, match="program"):
        Reward(type="cashback", program="mysinhan_point", rate=1)


def test_rate_table_and_rate_range():
    Reward(type="billing_discount", rate={0: 0.5, 1500000: 1.0})
    with pytest.raises(ValidationError):
        Reward(type="billing_discount", rate=0)
    with pytest.raises(ValidationError):
        Reward(type="billing_discount", rate=101)


def test_money_is_strict_integer():
    Limit(per="txn", amount=1000)
    for bad in ["1000", 1000.5, True, -1]:
        with pytest.raises(ValidationError):
            Limit(per="txn", amount=bad)


def test_condition_is_not_empty():
    Condition(region="overseas")
    with pytest.raises(ValidationError, match="빈 조건"):
        Condition()
    with pytest.raises(ValidationError, match="빈 조건"):
        Condition(region=None)


def test_amount_range_and_time_format():
    Condition(amount={"min": 30000, "below": 100000})
    with pytest.raises(ValidationError, match="below보다 작아야"):
        Condition(amount={"min": 100000, "below": 30000})
    Condition(time={"from": "21:00", "to": "09:00"})
    with pytest.raises(ValidationError):
        Condition(time={"from": "25:00", "to": "09:00"})
    with pytest.raises(ValidationError):
        Condition.model_validate({"time": {"from": 1260, "to": "09:00"}})


def test_day_condition():
    Condition.model_validate({"day": {"in": ["sat", "sun"], "holidays": "exclude"}})
    Condition.model_validate({"day": {"holidays": "only"}})
    with pytest.raises(ValidationError, match="holidays: only"):
        Condition.model_validate({"day": {"holidays": "exclude"}})
    with pytest.raises(ValidationError):
        Condition.model_validate({"day": {"in": ["saturday"]}})


def test_limit_is_shared_or_spec():
    Limit(shared="integrated")
    Limit(per="month", count=10)
    with pytest.raises(ValidationError, match="shared를 쓰면"):
        Limit(shared="integrated", per="month", amount=1000)
    with pytest.raises(ValidationError, match="per와 amount"):
        Limit(per="month")
    with pytest.raises(ValidationError, match="amount, count, base"):
        SharedLimit(key="integrated", per="month")


def test_adjust_null_means_unlimited():
    a = Adjust.model_validate({"when": {"fact": "salary_transfer"}, "count": None})
    assert a.count is None
    with pytest.raises(ValidationError, match="multiply"):
        Adjust.model_validate({"when": {"fact": "salary_transfer"}})


def test_target_all_or_lists():
    Target(all=True)
    Target(merchants=["starbucks"])
    with pytest.raises(ValidationError, match="함께 쓰지 않는다"):
        Target(all=True, categories=["cafe"])
    with pytest.raises(ValidationError, match="하나를 쓴다"):
        Target()


def test_option_default_and_unsupported_are_choices():
    choices = [{"key": "auto", "title": "Auto"}, {"key": "diy", "title": "DIY"}]
    Option(key="mode", title="모드", choices=choices, default="auto", change="next_month", unsupported=["diy"])
    with pytest.raises(ValidationError, match="default"):
        Option(key="mode", title="모드", choices=choices, default="x", change="next_month")
    with pytest.raises(ValidationError, match="unsupported"):
        Option(key="mode", title="모드", choices=choices, change="next_month", unsupported=["x"])


def test_choice_fact_needs_choices():
    Fact(key="soldier", type="bool", scope="user", ask="현역 병사인가요")
    Fact(key="grade", type="choice", scope="user", ask="등급은", choices=["a", "b"])
    with pytest.raises(ValidationError, match="choices"):
        Fact(key="grade", type="choice", scope="user", ask="등급은")


def test_unknown_field_is_rejected():
    with pytest.raises(ValidationError, match="Extra inputs"):
        Reward.model_validate({"type": "billing_discount", "rate": 10, "rat": 5})
```

- [x] **5단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/catalog/test_models.py
```

기대: `ModuleNotFoundError: No module named 'cherry_core.catalog.models'`

- [x] **6단계: 모델을 쓴다**

`backend/cherry_core/catalog/models.py`

```python
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
```

- [x] **7단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend
uvx ruff format --check backend
```

기대: `13 passed`, `All checks passed!`, 형식 검사에서 고칠 파일 없음.

- [x] **8단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog/models.py backend/tests/catalog/test_models.py
git commit -m "feat: 카탈로그 2판 모델 추가" -m "작업 001. 조건, 대상, 보상, 한도, 중복 묶음, 옵션, 사실, 실적 규칙, 개정,
카드와 카드사, 공통 파일 모델. 모르는 칸과 정수가 아닌 금액을 받지 않는다"
```

---

## 과제 2: 개정 해석

카드사 기본값을 깔고, 카드 개정을 얹고, 패치를 앞 개정에 얹어 날짜마다 개정 전체를 만든다. 설계 1절 카드사 파일, 2.12, 4.6의 1번.

**파일**
- 새로: `backend/cherry_core/catalog/resolve.py`
- 테스트: `backend/tests/catalog/test_resolve.py`

**인터페이스**
- 받는 것: 모델이 아니라 dict다. 카드와 카드사는 `CardFile.model_dump(by_alias=True, exclude_unset=True)` 모양이고 날짜는 `datetime.date`다.
- 내놓는 것:
  - `merge(base, patch, field=None) -> Any`
  - `card_contents(revisions: list[dict]) -> list[tuple[dict, dict]]`
  - `resolve_card(card: dict, issuer: dict | None) -> list[ResolvedRevision]`
  - `revision_for(revisions: list[ResolvedRevision], day: date) -> ResolvedRevision | None`
  - `ResolvedRevision(effective_from: date, effective_from_estimated: bool, source: str, data: dict)`
- 합치기가 불가능하면 `ValueError`를 던진다. 과제 4가 이것을 문제 목록으로 바꾼다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/catalog/test_resolve.py`

```python
"""카드사 기본값 합치기, 패치, 날짜로 개정 고르기. 설계 1절과 2.12, 4.3."""

from datetime import date

import pytest

from cherry_core.catalog.resolve import merge, resolve_card, revision_for

SPEND = {
    "basis": "prev_calendar_month",
    "exclude_categories": ["tax"],
    "installment": "full_at_purchase",
    "cancellation": "cancel_month",
}


def issuer(*defaults):
    return {"schema_version": 2, "id": "kb", "name": "KB국민카드", "defaults": list(defaults)}


def card(*revisions):
    return {"id": "kb-test", "revisions": list(revisions)}


def rev(day, **rules):
    return {"effective_from": day, "source": "page", **rules}


def test_merge_maps_and_null_deletes():
    assert merge({"a": 1, "b": {"c": 2, "d": 3}}, {"b": {"c": 9, "d": None}}) == {"a": 1, "b": {"c": 9}}


def test_merge_keyed_list_by_key():
    base = [{"key": "a", "rate": 1, "limits": [{"per": "day", "count": 1}]}, {"key": "b", "rate": 2}]
    patch = {"a": {"limits": [{"per": "month", "count": 5}]}, "b": None, "c": {"rate": 3}}
    assert merge(base, patch) == [
        {"key": "a", "rate": 1, "limits": [{"per": "month", "count": 5}]},
        {"key": "c", "rate": 3},
    ]


def test_merge_list_replaces_whole_list():
    assert merge({"tiers": [0, 300000]}, {"tiers": [0, 400000]}) == {"tiers": [0, 400000]}


def test_merge_keyed_patch_on_keyless_list_fails():
    with pytest.raises(ValueError, match="key가 없는 목록"):
        merge([{"per": "day", "count": 1}], {"x": {"count": 2}})


def test_card_overrides_only_the_fields_it_writes():
    out = resolve_card(
        card(rev(date(2026, 7, 1), tiers=[0], spend={"cancellation": "original_month"})),
        issuer({"effective_from": date(2026, 1, 1), "spend": SPEND}),
    )
    assert out[0].data["spend"] == {**SPEND, "cancellation": "original_month"}


def test_issuer_default_change_reaches_every_card():
    kb = issuer(
        {"effective_from": date(2026, 1, 1), "spend": SPEND},
        {"effective_from": date(2026, 10, 1), "spend": {**SPEND, "exclude_categories": ["tax", "utility"]}},
    )
    for c in [card(rev(date(2026, 7, 1), tiers=[0])), card(rev(date(2026, 8, 1), tiers=[0, 300000]))]:
        out = resolve_card(c, kb)
        assert [r.effective_from for r in out][-1] == date(2026, 10, 1)
        assert revision_for(out, date(2026, 9, 30)).data["spend"]["exclude_categories"] == ["tax"]
        assert revision_for(out, date(2026, 10, 1)).data["spend"]["exclude_categories"] == ["tax", "utility"]


def test_patch_revision_splits_the_day_before_and_the_day():
    npay = {"key": "npay-points", "limits": [{"per": "month", "count": {250000: 5, 500000: 7, 1000000: 10}}]}
    c = card(
        rev(date(2026, 7, 27), tiers=[0, 250000, 500000, 1000000], benefits=[npay]),
        {
            "effective_from": date(2027, 1, 1),
            "source": "page",
            "patch": {"benefits": {"npay-points": {"limits": [{"per": "month", "count": 5}]}}},
        },
    )
    out = resolve_card(c, None)
    before, after = revision_for(out, date(2026, 12, 31)), revision_for(out, date(2027, 1, 1))
    assert before.effective_from == date(2026, 7, 27)
    assert after.effective_from == date(2027, 1, 1)
    assert before.data["benefits"][0]["limits"][0]["count"] == {250000: 5, 500000: 7, 1000000: 10}
    assert after.data["benefits"][0]["limits"][0]["count"] == 5
    assert after.data["tiers"] == [0, 250000, 500000, 1000000]


def test_before_first_revision_uses_it_only_when_estimated():
    known = resolve_card(card(rev(date(2026, 9, 28), tiers=[0])), None)
    assert revision_for(known, date(2026, 8, 15)) is None
    guessed = resolve_card(card({**rev(date(2026, 9, 28), tiers=[0]), "effective_from_estimated": True}), None)
    assert revision_for(guessed, date(2026, 8, 15)).effective_from == date(2026, 9, 28)
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/catalog/test_resolve.py
```

기대: `ModuleNotFoundError: No module named 'cherry_core.catalog.resolve'`

- [x] **3단계: 해석기를 쓴다**

`backend/cherry_core/catalog/resolve.py`

```python
"""카드사 기본값 합치기, 패치 적용, 날짜로 개정 고르기. 설계 1절 카드사 파일과 2.12."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from datetime import date
from typing import Any

META_KEYS = ("effective_from", "effective_from_estimated", "source", "patch")
DEFAULT_KEYS = ("spend", "new_card", "benefit_exclusions")
KEYED_LISTS = ("benefits", "limits", "stacks", "options", "facts", "ranked")


@dataclass(frozen=True)
class ResolvedRevision:
    effective_from: date
    effective_from_estimated: bool
    source: str
    data: dict[str, Any]


def merge(base: Any, patch: Any, field: str | None = None) -> Any:
    """patch를 base 위에 얹는다.

    맵은 키마다 합치고 값 null은 그 키를 지운다. key가 있는 목록에 맵을 얹으면 key로 짝을 맞춰 합친다.
    그 밖의 목록과 값은 통째로 바꾼다.
    """
    if isinstance(patch, dict) and (isinstance(base, list) or (base is None and field in KEYED_LISTS)):
        return _merge_keyed(base or [], patch)
    if isinstance(patch, dict) and isinstance(base, dict):
        out = copy.deepcopy(base)
        for k, v in patch.items():
            if v is None:
                out.pop(k, None)
            else:
                out[k] = merge(out.get(k), v, k)
        return out
    return copy.deepcopy(patch)


def _merge_keyed(base: list, patch: dict) -> list:
    if not all(isinstance(item, dict) and "key" in item for item in base):
        raise ValueError("key가 없는 목록에는 맵으로 패치할 수 없다. 목록 전체를 다시 쓴다")
    items = {item["key"]: copy.deepcopy(item) for item in base}
    for k, v in patch.items():
        if v is None:
            items.pop(k, None)
        elif not isinstance(v, dict):
            raise ValueError(f"key {k}의 패치는 맵이어야 한다")
        elif k in items:
            items[k] = merge(items[k], v)
        else:
            items[k] = {"key": k, **copy.deepcopy(v)}
    return list(items.values())


def card_contents(revisions: list[dict]) -> list[tuple[dict, dict]]:
    """개정 항목마다 (메타, 그 날짜의 카드 규칙 전체)를 돌려준다. 패치는 앞 개정에 얹는다."""
    out: list[tuple[dict, dict]] = []
    prev: dict | None = None
    for entry in revisions:
        meta = {k: entry[k] for k in META_KEYS if k in entry}
        if "patch" in entry:
            if prev is None:
                raise ValueError("첫 개정은 patch로 쓸 수 없다")
            content = merge(prev, entry["patch"])
        else:
            content = {k: copy.deepcopy(v) for k, v in entry.items() if k not in META_KEYS}
        out.append((meta, content))
        prev = content
    return out


def resolve_card(card: dict, issuer: dict | None) -> list[ResolvedRevision]:
    """카드 파일과 카드사 파일을 합쳐 날짜마다 개정 전체를 만든다.

    날짜는 카드 개정 날짜와, 카드 첫 개정 뒤에 생긴 카드사 기본값 날짜를 합친 것이다.
    카드 파일에 적은 칸이 카드사 기본값보다 우선한다.
    """
    contents = card_contents(card["revisions"])
    defaults = (issuer or {}).get("defaults", [])
    first = contents[0][0]["effective_from"]
    days = {meta["effective_from"] for meta, _ in contents}
    days |= {d["effective_from"] for d in defaults if d["effective_from"] > first}
    out = []
    for day in sorted(days):
        meta, content = [c for c in contents if c[0]["effective_from"] <= day][-1]
        current = [d for d in defaults if d["effective_from"] <= day]
        base = {k: current[-1][k] for k in DEFAULT_KEYS if current and current[-1].get(k) is not None}
        estimated = any(
            x["effective_from"] == day and x.get("effective_from_estimated", False) for x in [meta, *defaults]
        )
        out.append(ResolvedRevision(day, estimated, meta["source"], merge(base, content)))
    return out


def revision_for(revisions: list[ResolvedRevision], day: date) -> ResolvedRevision | None:
    """day에 적용되는 개정. day가 첫 개정보다 앞이면 첫 개정의 시행일이 추정일 때만 첫 개정을 쓴다."""
    current = [r for r in revisions if r.effective_from <= day]
    if current:
        return current[-1]
    first = revisions[0]
    return first if first.effective_from_estimated else None
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend
```

기대: `21 passed`, `All checks passed!`

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog/resolve.py backend/tests/catalog/test_resolve.py
git commit -m "feat: 카드사 기본값과 패치를 합치는 개정 해석 추가" -m "작업 001. 카드 개정 날짜와 카드사 기본값 날짜마다 개정 전체를 만들고,
첫 개정 시행일이 추정이면 그 이전 결제에도 첫 개정을 쓴다"
```

---

## 과제 3: 고정 저장 형식

같은 내용이면 언제나 같은 글자가 나오게 한다. 같은 원문으로 두 번 갱신해도 git 차이가 0이 되는 바탕이다. 설계 4.2 저장 형식, 4.6의 2번과 8번.

**파일**
- 새로: `backend/cherry_core/catalog/canonical.py`
- 테스트: `backend/tests/catalog/test_canonical.py`

**인터페이스**
- 내놓는 것:
  - `canonical_text(data) -> str`
  - `catalog_files(root: Path) -> list[Path]`: `*.yaml`, `issuers/*.yaml`, `cards/*/*.yaml`. 1판 자리인 `cards/*.yaml`은 넣지 않는다
  - `is_canonical(path) -> bool`
  - `format_file(path) -> bool`: 바꿨으면 True

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/catalog/test_canonical.py`

```python
"""고정 저장 형식. 설계 4.2와 4.3."""

from datetime import date

import yaml

from cherry_core.catalog.canonical import canonical_text, format_file, is_canonical

SAMPLE = {
    "schema_version": 2,
    "id": "kb-sample",
    "revisions": [
        {
            "effective_from": date(2026, 7, 1),
            "tiers": [0, 300000],
            "benefits": [{"key": "cafe-10", "reward": {"type": "billing_discount", "rate": 10}}],
        }
    ],
}


def test_same_content_gives_same_text_and_is_idempotent():
    once = canonical_text(SAMPLE)
    assert canonical_text(yaml.safe_load(once)) == once
    shuffled = dict(reversed(list(SAMPLE.items())))
    assert canonical_text(shuffled) == once


def test_key_order_and_set_like_lists():
    text = canonical_text(
        {
            "target": {"merchants": ["b", "a"]},
            "title": "t",
            "key": "k",
            "when": [{"day": {"in": ["sun", "sat"]}}],
            "tiers": [0, 500000, 300000],
        }
    )
    assert text.splitlines()[0] == "key: k"
    data = yaml.safe_load(text)
    assert data["target"]["merchants"] == ["a", "b"]
    assert data["when"][0]["day"]["in"] == ["sat", "sun"]
    assert data["tiers"] == [0, 500000, 300000]


def test_tier_table_keys_sorted_and_strings_kept():
    data = yaml.safe_load(
        canonical_text({"amount": {500000: 2, 300000: 1}, "from": "21:00", "notes": "첫 줄\n둘째 줄"})
    )
    assert list(data["amount"]) == [300000, 500000]
    assert data["from"] == "21:00"
    assert data["notes"] == "첫 줄\n둘째 줄"


def test_format_file_rewrites_only_when_needed(tmp_path):
    path = tmp_path / "x.yaml"
    path.write_text("title: t\nkey: k\nchecked_at: 2026-09-28\n", encoding="utf-8")
    assert not is_canonical(path)
    assert format_file(path) is True
    assert is_canonical(path)
    assert format_file(path) is False
    assert yaml.safe_load(path.read_text(encoding="utf-8"))["checked_at"] == date(2026, 9, 28)


def test_benefit_fields_in_reading_order():
    b = {
        "tiers": {"from": 300000},
        "limits": [],
        "reward": {"type": "cashback", "fixed": 1000},
        "target": {"all": True},
        "title": "t",
        "key": "k",
    }
    assert list(yaml.safe_load(canonical_text(b))) == ["key", "title", "target", "reward", "limits", "tiers"]
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/catalog/test_canonical.py
```

기대: `ModuleNotFoundError: No module named 'cherry_core.catalog.canonical'`

- [x] **3단계: 저장 형식을 쓴다**

`backend/cherry_core/catalog/canonical.py`

```python
"""카탈로그 파일의 고정 저장 형식. 설계 4.2 저장 형식.

같은 내용이면 언제나 같은 글자가 나오게 키 순서, 들여쓰기, 집합 성격 목록의 순서를 고정한다.
카탈로그 파일에는 주석을 쓰지 않는다. 사람이 읽을 메모는 notes 칸에 쓴다.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

KEY_ORDER = [
    "schema_version",
    "id",
    "key",
    "code",
    "issuer",
    "name",
    "title",
    "search_names",
    "kind",
    "product_codes",
    "status",
    "status_since",
    "type",
    "scope",
    "ask",
    "brand",
    "form",
    "annual_fees",
    "sources",
    "url",
    "fetched_at",
    "text_sha256",
    "review_no",
    "review_valid_until",
    "checked_at",
    "collect",
    "list_url",
    "method",
    "interval_days",
    "notice_url",
    "defaults",
    "revisions",
    "effective_from",
    "effective_from_estimated",
    "source",
    "patch",
    "tiers",
    "spend",
    "basis",
    "regions",
    "exclude_categories",
    "interest_free",
    "installment",
    "cancellation",
    "cancellation_overrides",
    "use",
    "month_offset",
    "exclude_applied",
    "new_card",
    "until",
    "tier",
    "tier_by_benefit",
    "benefit_exclusions",
    "when_any",
    "facts",
    "options",
    "choices",
    "default",
    "change",
    "unsupported",
    "ranked",
    "top",
    "by",
    "limits",
    "stacks",
    "pick",
    "order",
    "spill",
    "benefits",
    "target",
    "all",
    "categories",
    "merchants",
    "exclude_merchants",
    "when",
    "in",
    "holidays",
    "from",
    "to",
    "min",
    "below",
    "max",
    "months",
    "region",
    "channel",
    "payment",
    "payment_not",
    "billing",
    "billing_not",
    "option",
    "fact",
    "card_month",
    "month_total",
    "any_of",
    "waived_when",
    "reward",
    "program",
    "rate",
    "fixed",
    "per_unit",
    "per_liter",
    "round",
    "shared",
    "per",
    "unit",
    "amount",
    "count",
    "multiply",
    "add",
    "adjust",
    "stack",
    "valid_from",
    "valid_until",
    "unmodeled",
    "open_questions",
    "path",
    "question",
    "assumed",
    "category",
    "aliases",
    "statement_names",
    "won_per_point",
    "value",
    "as_of",
    "kakao",
    "children",
    "notes",
]
_RANK = {k: i for i, k in enumerate(KEY_ORDER)}
# 혜택은 읽는 순서대로 쓴다. 대상, 조건, 보상, 한도, 구간
BENEFIT_ORDER = [
    "key",
    "title",
    "source",
    "target",
    "when",
    "reward",
    "limits",
    "tiers",
    "stack",
    "exclude_applied",
    "valid_from",
    "valid_until",
    "unmodeled",
    "notes",
]
_BENEFIT_RANK = {k: i for i, k in enumerate(BENEFIT_ORDER)}
SET_FIELDS = {
    "search_names",
    "product_codes",
    "regions",
    "exclude_categories",
    "categories",
    "merchants",
    "exclude_merchants",
    "in",
    "months",
    "payment",
    "payment_not",
    "billing",
    "billing_not",
    "unsupported",
    "statement_names",
}
WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def normalize(node: Any, parent: Any = None) -> Any:
    if isinstance(node, dict):
        if node and all(isinstance(k, int) and not isinstance(k, bool) for k in node):
            items = sorted(node.items())
        else:
            rank = _BENEFIT_RANK if "reward" in node else _RANK
            items = sorted(node.items(), key=lambda kv: (rank.get(kv[0], len(rank)), str(kv[0])))
        return {k: normalize(v, k) for k, v in items}
    if isinstance(node, list):
        items = [normalize(v) for v in node]
        if parent in SET_FIELDS and all(isinstance(v, (str, int)) and not isinstance(v, bool) for v in items):
            if parent == "in" and all(v in WEEKDAYS for v in items):
                return sorted(items, key=WEEKDAYS.index)
            return sorted(items, key=lambda v: (isinstance(v, str), v))
        return items
    return node


class _Dumper(yaml.SafeDumper):
    def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
        return super().increase_indent(flow, False)


def _represent_str(dumper: yaml.SafeDumper, value: str) -> yaml.Node:
    return dumper.represent_scalar("tag:yaml.org,2002:str", value, style="|" if "\n" in value else None)


_Dumper.add_representer(str, _represent_str)


def canonical_text(data: Any) -> str:
    return yaml.dump(
        normalize(data),
        Dumper=_Dumper,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=None,
        width=10_000,
        indent=2,
    )


def catalog_files(root: Path) -> list[Path]:
    """2판 카탈로그 파일. 1판 카드 파일 catalog/cards/*.yaml은 포함하지 않는다."""
    return sorted([*root.glob("*.yaml"), *root.glob("issuers/*.yaml"), *root.glob("cards/*/*.yaml")])


def is_canonical(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    return text == canonical_text(yaml.safe_load(text))


def format_file(path: Path) -> bool:
    """고정 형식으로 다시 쓴다. 바뀌었으면 True."""
    text = path.read_text(encoding="utf-8")
    new = canonical_text(yaml.safe_load(text))
    if new == text:
        return False
    path.write_text(new, encoding="utf-8", newline="\n")
    return True
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend
```

기대: `26 passed`, `All checks passed!`

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog/canonical.py backend/tests/catalog/test_canonical.py
git commit -m "feat: 카탈로그 고정 저장 형식 추가" -m "작업 001. 키 순서, 들여쓰기, 집합 성격 목록의 순서를 고정한다"
```

---

## 과제 4: 파일 읽기와 오류 위치

**파일**
- 새로: `backend/cherry_core/catalog/load.py`
- 새로: `backend/tests/catalog/conftest.py`. 과제 5에서 두 줄을 더한다
- 테스트: `backend/tests/catalog/test_load.py`

**인터페이스**
- 받는 것: 과제 1의 모델, 과제 2의 `resolve_card`, `ResolvedRevision`.
- 내놓는 것:
  - `Problem(level, file, path, message)`: `str()`은 `파일: 경로: 내용`
  - `LoadedCard(file, raw, card, revisions: list[tuple[ResolvedRevision, Rules]])`
  - `LoadedIssuer(file, raw, issuer)`
  - `Catalog(root, categories, merchants, payment_methods, point_programs, reference, issuers, cards, problems)`
  - `format_loc(loc, data) -> str`
  - `load_catalog(root: Path) -> Catalog`: 예외를 던지지 않고 문제를 `problems`에 모은다
- 합친 개정의 오류 위치 머리는 `revisions@<시행일>.`이다. 테스트 픽스처 `make_catalog(edit)`는 한 곳만 틀리게 고친 카탈로그를 임시 폴더에 쓴다.

- [x] **1단계: 픽스처와 실패하는 테스트를 쓴다**

`backend/tests/catalog/conftest.py`

```python
"""작은 2판 카탈로그를 임시 폴더에 만든다. 테스트는 edit 함수로 한 곳만 틀리게 바꾼다."""

import copy
from datetime import date
from pathlib import Path

import pytest

from cherry_core.catalog.canonical import canonical_text
from cherry_core.catalog.load import load_catalog

CARD = {
    "schema_version": 2,
    "id": "shinhan-test",
    "issuer": "shinhan",
    "name": "신한카드 테스트",
    "kind": "credit",
    "product_codes": ["T0001"],
    "status": "on_sale",
    "sources": [
        {"id": "page", "kind": "product_page", "url": "https://www.shinhancard.com/t", "fetched_at": date(2026, 9, 28)}
    ],
    "checked_at": date(2026, 9, 28),
    "revisions": [
        {
            "effective_from": date(2026, 7, 1),
            "source": "page",
            "tiers": [0, 300000, 500000],
            "limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 20000}}],
            "benefits": [
                {
                    "key": "cafe-10",
                    "title": "카페 10% 할인",
                    "target": {"categories": ["cafe"]},
                    "reward": {"type": "billing_discount", "rate": 10},
                    "limits": [{"per": "txn", "amount": 1000}, {"shared": "integrated"}],
                    "tiers": {"from": 300000},
                },
            ],
        }
    ],
}

FILES = {
    "categories.yaml": [
        {"code": "cafe", "name": "카페", "kakao": "CE7"},
        {"code": "tax", "name": "세금"},
        {"code": "transit", "name": "대중교통", "children": [{"code": "subway", "name": "지하철", "kakao": "SW8"}]},
    ],
    "merchants.yaml": [{"key": "starbucks", "name": "스타벅스", "category": "cafe", "aliases": ["스타벅스", "스벅"]}],
    "payment_methods.yaml": [
        {"key": "naver_pay", "name": "네이버페이", "statement_names": ["네이버페이"]},
        {"key": "physical_card", "name": "실물카드"},
    ],
    "point_programs.yaml": [{"key": "mysinhan_point", "name": "마이신한포인트", "won_per_point": 1}],
    "reference.yaml": [
        {"key": "fuel_price_gasoline", "value": 1700, "unit": "원/L", "as_of": date(2026, 9, 28), "source": "오피넷"}
    ],
    "issuers/shinhan.yaml": {
        "schema_version": 2,
        "id": "shinhan",
        "name": "신한카드",
        "defaults": [
            {
                "effective_from": date(2026, 1, 1),
                "spend": {
                    "basis": "prev_calendar_month",
                    "exclude_categories": ["tax"],
                    "installment": "full_at_purchase",
                    "cancellation": "cancel_month",
                },
            }
        ],
    },
    "cards/shinhan/shinhan-test.yaml": CARD,
}


def write_catalog(root: Path, files: dict) -> Path:
    for rel, data in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(canonical_text(data), encoding="utf-8", newline="\n")
    return root


@pytest.fixture
def make_catalog(tmp_path):
    """edit(files)로 고친 카탈로그를 쓰고 그 폴더를 돌려준다."""

    def make(edit=None) -> Path:
        files = copy.deepcopy(FILES)
        if edit:
            edit(files)
        return write_catalog(tmp_path / "catalog", files)

    return make


def rev(files: dict, i: int = 0) -> dict:
    """테스트 카드의 i번째 개정."""
    return files["cards/shinhan/shinhan-test.yaml"]["revisions"][i]


def benefit(files: dict) -> dict:
    return rev(files)["benefits"][0]


def load_problems(root: Path) -> list[str]:
    """파일 읽기와 모델 검사에서 나온 문제."""
    return [str(p) for p in load_catalog(root).problems]
```

`backend/tests/catalog/test_load.py`

```python
"""파일 읽기와 오류 위치."""

from cherry_core.catalog.load import format_loc, load_catalog

from .conftest import benefit, load_problems, rev


def test_valid_catalog_has_no_errors(make_catalog):
    root = make_catalog()
    cat = load_catalog(root)
    assert load_problems(root) == []
    card = cat.cards["shinhan-test"]
    rules = card.revisions[0][1]
    assert rules.spend.exclude_categories == ["tax"]
    assert "transit.subway" in cat.categories


def test_error_path_uses_benefit_key(make_catalog):
    root = make_catalog(lambda f: benefit(f)["reward"].update(rat=5))
    assert any("revisions@2026-07-01.benefits[cafe-10].reward.rat" in e for e in load_problems(root))


def test_missing_issuer_default_field_is_reported(make_catalog):
    root = make_catalog(lambda f: f["issuers/shinhan.yaml"]["defaults"][0]["spend"].pop("installment"))
    assert any("revisions@2026-07-01.spend.installment" in e for e in load_problems(root))


def test_yaml_syntax_error_is_reported(make_catalog):
    root = make_catalog()
    (root / "merchants.yaml").write_text("- key: [broken\n", encoding="utf-8")
    assert any(e.startswith("merchants.yaml: YAML을 읽지 못했다") for e in load_problems(root))


def test_revisions_must_ascend(make_catalog):
    def edit(f):
        f["cards/shinhan/shinhan-test.yaml"]["revisions"].append({**rev(f), "effective_from": rev(f)["effective_from"]})

    assert any("오름차순" in e for e in load_problems(make_catalog(edit)))


def test_format_loc():
    data = {"benefits": [{"key": "a"}, {"title": "no key"}]}
    assert format_loc(("benefits", 0, "reward"), data) == "benefits[a].reward"
    assert format_loc(("benefits", 1, "reward"), data) == "benefits[1].reward"
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/catalog/test_load.py
```

기대: `ModuleNotFoundError: No module named 'cherry_core.catalog.load'`

- [x] **3단계: 읽기를 쓴다**

`backend/cherry_core/catalog/load.py`

```python
"""카탈로그 파일을 읽어 파일 단위 모델과 합친 개정 모델로 검사한다."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from pydantic import TypeAdapter, ValidationError

from .models import (
    CardFile,
    Category,
    IssuerFile,
    Merchant,
    PaymentMethod,
    PointProgram,
    ReferenceValue,
    Rules,
)
from .resolve import ResolvedRevision, resolve_card


@dataclass
class Problem:
    level: str  # error 또는 warning
    file: str
    path: str
    message: str

    def __str__(self) -> str:
        where = f"{self.file}: {self.path}" if self.path else self.file
        return f"{where}: {self.message}"


@dataclass
class LoadedCard:
    file: str
    raw: dict
    card: CardFile
    revisions: list[tuple[ResolvedRevision, Rules]]


@dataclass
class LoadedIssuer:
    file: str
    raw: dict
    issuer: IssuerFile


@dataclass
class Catalog:
    root: Path
    categories: set[str] = field(default_factory=set)
    merchants: dict[str, Merchant] = field(default_factory=dict)
    payment_methods: dict[str, PaymentMethod] = field(default_factory=dict)
    point_programs: dict[str, PointProgram] = field(default_factory=dict)
    reference: dict[str, ReferenceValue] = field(default_factory=dict)
    issuers: dict[str, LoadedIssuer] = field(default_factory=dict)
    cards: dict[str, LoadedCard] = field(default_factory=dict)
    problems: list[Problem] = field(default_factory=list)


def format_loc(loc: tuple, data: Any) -> str:
    """pydantic 오류 위치를 사람이 읽는 경로로 바꾼다. key가 있는 목록 항목은 [key]로 쓴다."""
    out, node = "", data
    for part in loc:
        if isinstance(part, int):
            item = node[part] if isinstance(node, list) and part < len(node) else None
            label = item.get("key") if isinstance(item, dict) else None
            out += f"[{label}]" if label else f"[{part}]"
            node = item
        else:
            out += f".{part}" if out else str(part)
            node = node.get(part) if isinstance(node, dict) else None
    return out


def _read(path: Path, rel: str, problems: list[Problem]) -> Any:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        problems.append(Problem("error", rel, "", f"YAML을 읽지 못했다: {e}"))
        return None


def _validate(tp: Any, data: Any, rel: str, problems: list[Problem], prefix: str = "") -> Any:
    try:
        return TypeAdapter(tp).validate_python(data)
    except ValidationError as e:
        for err in e.errors():
            problems.append(Problem("error", rel, prefix + format_loc(err["loc"], data), err["msg"]))
        return None


def load_catalog(root: Path) -> Catalog:
    cat = Catalog(root=root)
    p = cat.problems

    def read_list(name: str, model: type) -> list:
        path = root / name
        if not path.exists():
            p.append(Problem("error", name, "", "파일이 없다"))
            return []
        return _validate(list[model], _read(path, name, p), name, p) or []

    categories = read_list("categories.yaml", Category)
    cat.categories = {c.code for c in categories} | {f"{c.code}.{ch.code}" for c in categories for ch in c.children}
    cat.merchants = {m.key: m for m in read_list("merchants.yaml", Merchant)}
    cat.payment_methods = {m.key: m for m in read_list("payment_methods.yaml", PaymentMethod)}
    cat.point_programs = {m.key: m for m in read_list("point_programs.yaml", PointProgram)}
    cat.reference = {m.key: m for m in read_list("reference.yaml", ReferenceValue)}

    for path in sorted((root / "issuers").glob("*.yaml")):
        rel = path.relative_to(root).as_posix()
        raw = _read(path, rel, p)
        issuer = _validate(IssuerFile, raw, rel, p)
        if issuer is None:
            continue
        if issuer.id != path.stem:
            p.append(Problem("error", rel, "id", f"파일 이름 {path.stem}과 다르다"))
        cat.issuers[issuer.id] = LoadedIssuer(rel, raw, issuer)

    for path in sorted((root / "cards").glob("*/*.yaml")):
        rel = path.relative_to(root).as_posix()
        raw = _read(path, rel, p)
        card = _validate(CardFile, raw, rel, p)
        if card is None:
            continue
        if card.id in cat.cards:
            p.append(Problem("error", rel, "id", f"{cat.cards[card.id].file}와 id가 겹친다"))
            continue
        issuer = cat.issuers.get(card.issuer)
        try:
            resolved = resolve_card(
                card.model_dump(by_alias=True, exclude_unset=True),
                issuer.issuer.model_dump(by_alias=True, exclude_unset=True) if issuer else None,
            )
        except ValueError as e:
            p.append(Problem("error", rel, "revisions", str(e)))
            continue
        revisions = []
        for r in resolved:
            rules = _validate(Rules, r.data, rel, p, prefix=f"revisions@{r.effective_from}.")
            if rules is not None:
                revisions.append((r, rules))
        cat.cards[card.id] = LoadedCard(rel, raw, card, revisions)
    return cat
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend
```

기대: `32 passed`, `All checks passed!`

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog/load.py backend/tests/catalog/conftest.py backend/tests/catalog/test_load.py
git commit -m "feat: 카탈로그 파일 읽기와 오류 위치 표시 추가" -m "작업 001. 오류 위치를 개정 날짜와 혜택 key로 쓴다"
```

---

## 과제 5: 교차 검사와 경고

설계 4.2 표의 검사를 전부 하고, 틀렸다고 단정할 수 없는 것은 경고로 남긴다.

**파일**
- 새로: `backend/cherry_core/catalog/check.py`
- 고치기: `backend/tests/catalog/conftest.py`
- 테스트: `backend/tests/catalog/test_check.py`, `backend/tests/catalog/test_warnings.py`

**인터페이스**
- 받는 것: 과제 3의 `catalog_files`, `is_canonical`. 과제 4의 `Catalog`, `LoadedCard`, `Problem`.
- 내놓는 것:
  - `check_catalog(cat: Catalog) -> list[Problem]`: 읽기 문제를 포함한 전체 문제
  - `check_rules(rules, cat, source_ids) -> list[tuple[level, path, message]]`
  - `path_exists(data, path) -> bool`
  - `benefit_keys(raw) -> set[str]`
  - `removed_benefit_keys(path, raw_now) -> set[str]`
- 기름값 기준값의 key는 `fuel_price_gasoline`이다.

- [x] **1단계: conftest에 교차 검사 도우미를 더한다**

`from cherry_core.catalog.canonical import canonical_text` 아래에 한 줄을 더한다.

```python
from cherry_core.catalog.check import check_catalog
```

파일 끝에 함수를 더한다.

```python
def problems_of(root: Path, level: str = "error") -> list[str]:
    """교차 검사까지 마친 문제 중 level인 것."""
    return [str(p) for p in check_catalog(load_catalog(root)) if p.level == level]
```

- [x] **2단계: 실패하는 테스트를 쓴다**

`backend/tests/catalog/test_check.py`

```python
"""교차 검사. 설계 4.2 표의 검사마다 한 곳만 틀린 카탈로그를 만들어 실패 위치를 확인한다."""

import pytest

from .conftest import benefit, problems_of, rev

CARD = "cards/shinhan/shinhan-test.yaml"
R = "revisions@2026-07-01."


def set_tiers(f):
    rev(f)["tiers"] = [100, 300000, 500000]


def table_key_not_in_tiers(f):
    rev(f)["limits"][0]["amount"] = {300000: 10000, 400000: 20000}


def table_starts_too_high(f):
    rev(f)["limits"][0]["amount"] = {500000: 20000}


def tier_from_not_in_tiers(f):
    benefit(f)["tiers"] = {"from": 250000}


def tier_from_after_to(f):
    benefit(f)["tiers"] = {"from": 500000, "to": 300000}


def unknown_category(f):
    benefit(f)["target"] = {"categories": ["bakery"]}


def unknown_merchant(f):
    benefit(f)["target"] = {"merchants": ["nowhere"]}


def unknown_payment(f):
    benefit(f)["when"] = [{"payment": ["zero_pay"]}]


def unknown_option(f):
    benefit(f)["when"] = [{"option": {"package": ["p1"]}}]


def unknown_choice(f):
    rev(f)["options"] = [
        {"key": "package", "title": "패키지", "change": "immediate", "choices": [{"key": "p1", "title": "1"}]}
    ]
    benefit(f)["when"] = [{"option": {"package": ["p9"]}}]


def unknown_fact(f):
    benefit(f)["when"] = [{"fact": "soldier"}]


def month_fact_as_condition(f):
    rev(f)["facts"] = [{"key": "birth_month", "type": "month", "scope": "user", "ask": "생일이 몇 월인가요"}]
    benefit(f)["when"] = [{"fact": "birth_month"}]


def ranked_with_one_member(f):
    rev(f)["ranked"] = [{"key": "top-area", "top": 1}]
    benefit(f)["when"] = [{"ranked": "top-area"}]


def month_total_on_txn_reward(f):
    benefit(f)["when"] = [{"month_total": {"min": 50000}}]


def unknown_program(f):
    benefit(f)["reward"] = {"type": "points", "program": "nope_point", "rate": 1}


def missing_shared(f):
    benefit(f)["limits"][1] = {"shared": "weekend"}


def undefined_stack(f):
    benefit(f)["stack"] = "pay"


def priority_order_incomplete(f):
    rev(f)["stacks"] = [{"key": "main", "pick": "priority", "order": [], "spill": "split"}]


def unknown_source(f):
    benefit(f)["source"] = "pdf"


def unknown_revision_source(f):
    rev(f)["source"] = "pdf"


def duplicate_benefit_key(f):
    rev(f)["benefits"].append(dict(benefit(f)))


def open_question_bad_path(f):
    f[CARD]["open_questions"] = [{"path": "revisions[0].spend.cancellation", "question": "취소 반영 달"}]


def id_differs_from_file(f):
    f[CARD]["id"] = "shinhan-other"


def issuer_missing(f):
    del f["issuers/shinhan.yaml"]


def merchant_unknown_category(f):
    f["merchants.yaml"][0]["category"] = "coffee"


def billing_cycle_basis(f):
    f["issuers/shinhan.yaml"]["defaults"][0]["spend"]["basis"] = "billing_cycle"


def per_liter_without_price(f):
    f["reference.yaml"] = []
    benefit(f)["reward"] = {"type": "billing_discount", "per_liter": 60}


CASES = [
    (set_tiers, R + "tiers"),
    (table_key_not_in_tiers, R + "limits[integrated].amount: 구간표 키 [400000]"),
    (table_starts_too_high, R + "limits[integrated].amount: 구간표의 가장 작은 키"),
    (tier_from_not_in_tiers, R + "benefits[cafe-10].tiers.from"),
    (tier_from_after_to, R + "benefits[cafe-10].tiers: from은 to 이하"),
    (unknown_category, R + "benefits[cafe-10].target: 업종 ['bakery']"),
    (unknown_merchant, R + "benefits[cafe-10].target: 가맹점 ['nowhere']"),
    (unknown_payment, R + "benefits[cafe-10].when[0].payment"),
    (unknown_option, R + "benefits[cafe-10].when[0].option: 옵션 package가 없다"),
    (unknown_choice, R + "benefits[cafe-10].when[0].option: 옵션 package에 선택지 ['p9']"),
    (unknown_fact, R + "benefits[cafe-10].when[0].fact"),
    (month_fact_as_condition, R + "benefits[cafe-10].when[0].fact: 사실 birth_month는 bool"),
    (ranked_with_one_member, R + "ranked[top-area]: 이 조건을 단 혜택이 둘 이상"),
    (month_total_on_txn_reward, R + "benefits[cafe-10].when[0].month_total"),
    (unknown_program, R + "benefits[cafe-10].reward.program"),
    (missing_shared, R + "benefits[cafe-10].limits[1].shared"),
    (undefined_stack, R + "benefits[cafe-10].stack"),
    (priority_order_incomplete, R + "stacks[main].order"),
    (unknown_source, R + "benefits[cafe-10].source"),
    (unknown_revision_source, R + "source"),
    (duplicate_benefit_key, R + "benefits: key가 겹친다"),
    (open_question_bad_path, CARD.removeprefix("") + ": open_questions"),
    (id_differs_from_file, ": id: 파일 이름"),
    (issuer_missing, ": issuer: issuers/shinhan.yaml이 없다"),
    (merchant_unknown_category, "merchants.yaml: [starbucks].category"),
    (billing_cycle_basis, R + "spend.basis"),
    (per_liter_without_price, R + "benefits[cafe-10].reward.per_liter"),
]


@pytest.mark.parametrize(("edit", "expected"), CASES, ids=[c[0].__name__ for c in CASES])
def test_each_check_reports_its_place(make_catalog, edit, expected):
    errors = problems_of(make_catalog(edit))
    assert any(expected in e for e in errors), errors


def test_open_question_path_by_key(make_catalog):
    def edit(f):
        f[CARD]["open_questions"] = [{"path": "revisions[0].benefits[cafe-10].reward.rate", "question": "비율"}]

    assert problems_of(make_catalog(edit)) == []


def test_non_canonical_file_is_an_error(make_catalog):
    root = make_catalog()
    path = root / CARD
    path.write_text(
        path.read_text(encoding="utf-8").replace("schema_version: 2\n", "") + "schema_version: 2\n", encoding="utf-8"
    )
    assert any("저장 형식이 아니다" in e for e in problems_of(root))
```

`backend/tests/catalog/test_warnings.py`

```python
"""경고. 틀렸다고 단정할 수 없어 검사는 통과시키고 목록으로 보여 준다. 설계 4.2."""

import copy
import subprocess

from cherry_core.catalog.check import benefit_keys

from .conftest import FILES, benefit, problems_of, rev, write_catalog

R = "revisions@2026-07-01."


def test_high_rate_without_limits(make_catalog):
    def edit(f):
        benefit(f)["limits"] = []

    root = make_catalog(edit)
    assert problems_of(root) == []
    assert any(R + "benefits[cafe-10]: 비율이 5% 이상" in w for w in problems_of(root, "warning"))


def test_decreasing_tier_table(make_catalog):
    root = make_catalog(lambda f: rev(f)["limits"][0].update(amount={300000: 20000, 500000: 10000}))
    assert any("구간이 높아지는데 값이 줄어든다" in w for w in problems_of(root, "warning"))


def test_unused_shared_limit(make_catalog):
    root = make_catalog(lambda f: benefit(f)["limits"].pop())
    assert any(R + "limits[integrated]: 쓰는 혜택이 없다" in w for w in problems_of(root, "warning"))


def test_empty_product_codes(make_catalog):
    root = make_catalog(lambda f: f["cards/shinhan/shinhan-test.yaml"].update(product_codes=[]))
    assert any("product_codes" in w for w in problems_of(root, "warning"))


def test_benefit_keys_include_patches():
    raw = {
        "revisions": [
            {"benefits": [{"key": "a"}, {"key": "b"}]},
            {"patch": {"benefits": {"c": {"title": "새 혜택"}, "b": None}}},
        ]
    }
    assert benefit_keys(raw) == {"a", "b", "c"}


def test_removed_key_against_last_commit(tmp_path):
    root = write_catalog(tmp_path / "catalog", copy.deepcopy(FILES))
    git = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com"]
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run([*git, "add", "."], cwd=tmp_path, check=True)
    subprocess.run([*git, "commit", "-q", "-m", "init"], cwd=tmp_path, check=True)
    files = copy.deepcopy(FILES)
    files["cards/shinhan/shinhan-test.yaml"]["revisions"][0]["benefits"][0]["key"] = "cafe-ten"
    write_catalog(root, files)
    assert any("사라졌다: ['cafe-10']" in w for w in problems_of(root, "warning"))
```

- [x] **3단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q
```

기대: conftest를 읽다가 `ModuleNotFoundError: No module named 'cherry_core.catalog.check'`

- [x] **4단계: 검사를 쓴다**

`backend/cherry_core/catalog/check.py`

```python
"""모델 밖의 교차 검사와 경고. 설계 4.2 검증 규칙."""

from __future__ import annotations

import re
import subprocess
from collections import Counter
from itertools import pairwise
from pathlib import Path
from typing import Any

import yaml

from .canonical import catalog_files, is_canonical
from .load import Catalog, LoadedCard, Problem
from .models import Benefit, Condition, Rules

FUEL_PRICE_KEY = "fuel_price_gasoline"
_PATH_TOKEN = re.compile(r"([^.\[\]]+)|\[([^\]]+)\]")


def check_catalog(cat: Catalog) -> list[Problem]:
    problems = list(cat.problems)
    for path in catalog_files(cat.root):
        try:
            canonical = is_canonical(path)
        except yaml.YAMLError:
            continue  # 읽기 오류는 load_catalog가 이미 남겼다
        if not canonical:
            rel = path.relative_to(cat.root).as_posix()
            problems.append(Problem("error", rel, "", "저장 형식이 아니다. format 명령으로 고친다"))
    problems += _check_common(cat)
    for issuer in cat.issuers.values():
        for q in issuer.issuer.open_questions:
            if not path_exists(issuer.raw, q.path):
                problems.append(Problem("error", issuer.file, "open_questions", f"path {q.path}가 가리키는 칸이 없다"))
    for card in cat.cards.values():
        problems += _check_card(card, cat)
    return problems


def _check_common(cat: Catalog) -> list[Problem]:
    out = []
    seen: dict[str, str] = {}
    for m in cat.merchants.values():
        if m.category not in cat.categories:
            out.append(Problem("error", "merchants.yaml", f"[{m.key}].category", f"업종 {m.category}가 없다"))
        for alias in m.aliases:
            norm = alias.replace(" ", "").lower()
            if norm in seen and seen[norm] != m.key:
                out.append(
                    Problem("error", "merchants.yaml", f"[{m.key}].aliases", f"별칭 {alias}가 {seen[norm]}와 겹친다")
                )
            seen[norm] = m.key
    return out


def _check_card(card: LoadedCard, cat: Catalog) -> list[Problem]:
    out = []
    c, f = card.card, card.file
    stem, parent = Path(f).stem, Path(f).parent.name
    if c.id != stem:
        out.append(Problem("error", f, "id", f"파일 이름 {stem}과 다르다"))
    if c.issuer != parent or not c.id.startswith(c.issuer + "-"):
        out.append(Problem("error", f, "issuer", f"카드사 폴더 {parent}와 id 앞부분이 issuer와 같아야 한다"))
    if c.issuer not in cat.issuers:
        out.append(Problem("error", f, "issuer", f"issuers/{c.issuer}.yaml이 없다"))
    if not c.product_codes:
        out.append(Problem("warning", f, "product_codes", "비어 있다. 갱신 때 같은 카드를 찾지 못한다"))
    source_ids = {s.id for s in c.sources}
    for q in c.open_questions:
        if not path_exists(card.raw, q.path):
            out.append(Problem("error", f, "open_questions", f"path {q.path}가 가리키는 칸이 없다"))
    for r, rules in card.revisions:
        prefix = f"revisions@{r.effective_from}."
        if r.source not in source_ids:
            out.append(Problem("error", f, prefix + "source", f"sources에 {r.source}가 없다"))
        out += [Problem(level, f, prefix + path, msg) for level, path, msg in check_rules(rules, cat, source_ids)]
    out += [
        Problem("warning", f, "revisions", f"직전 커밋에 있던 혜택 key가 사라졌다: {sorted(gone)}")
        for gone in [removed_benefit_keys(cat.root / f, card.raw)]
        if gone
    ]
    return out


def check_rules(rules: Rules, cat: Catalog, source_ids: set[str]) -> list[tuple[str, str, str]]:
    """개정 하나를 검사해 (level, path, message) 목록을 돌려준다."""
    out: list[tuple[str, str, str]] = []

    def err(path: str, msg: str) -> None:
        out.append(("error", path, msg))

    def warn(path: str, msg: str) -> None:
        out.append(("warning", path, msg))

    tiers = rules.tiers
    tierset = set(tiers)
    if tiers[0] != 0 or any(a >= b for a, b in pairwise(tiers)):
        err("tiers", "0부터 시작하는 오름차순이어야 한다")

    def table(value: Any, path: str, first: int | None) -> None:
        """first는 이 값이 적용되는 첫 구간. 쓰는 혜택이 없어 모르면 None."""
        if not isinstance(value, dict) or not value:
            return
        bad = sorted(k for k in value if k not in tierset)
        if bad:
            err(path, f"구간표 키 {bad}가 tiers에 없다")
        if first is not None and min(value) > first:
            err(path, f"구간표의 가장 작은 키 {min(value)}가 적용 첫 구간 {first}보다 크다")
        vals = [value[k] for k in sorted(value)]
        if any(b < a for a, b in pairwise(vals)):
            warn(path, "구간이 높아지는데 값이 줄어든다")

    def cats(values: list[str], path: str) -> None:
        bad = [v for v in values if v not in cat.categories]
        if bad:
            err(path, f"업종 {bad}가 categories.yaml에 없다")

    for name in ("benefits", "limits", "stacks", "options", "facts", "ranked"):
        keys = [x.key for x in getattr(rules, name)]
        dup = sorted({k for k in keys if keys.count(k) > 1})
        if dup:
            err(name, f"key가 겹친다: {dup}")

    options = {o.key: {ch.key for ch in o.choices} for o in rules.options}
    facts = {x.key: x for x in rules.facts}
    ranked_keys = {x.key for x in rules.ranked}
    shared_keys = {x.key for x in rules.limits}
    stack_keys = {x.key for x in rules.stacks} | {"main"}
    benefit_keys = {b.key for b in rules.benefits}

    def cond(c: Condition, path: str, benefit: Benefit | None) -> None:
        for name in ("payment", "payment_not"):
            bad = [x for x in getattr(c, name) or [] if x not in cat.payment_methods]
            if bad:
                err(f"{path}.{name}", f"결제수단 {bad}가 payment_methods.yaml에 없다")
        for key, choices in (c.option or {}).items():
            if key not in options:
                err(f"{path}.option", f"옵션 {key}가 없다")
            elif set(choices) - options[key]:
                err(f"{path}.option", f"옵션 {key}에 선택지 {sorted(set(choices) - options[key])}가 없다")
        if c.fact is not None:
            derived = c.fact == "birth_month_now" and "birth_month" in facts
            if c.fact not in facts and not derived:
                err(f"{path}.fact", f"사실 {c.fact}가 facts에 없다")
            elif c.fact in facts and facts[c.fact].type != "bool":
                err(f"{path}.fact", f"사실 {c.fact}는 bool이어야 조건으로 쓴다")
        if c.ranked is not None and c.ranked not in ranked_keys:
            err(f"{path}.ranked", f"ranked 그룹 {c.ranked}가 없다")
        if c.month_total is not None and (benefit is None or benefit.reward.basis != "month_total"):
            err(f"{path}.month_total", "reward.basis가 month_total인 혜택에만 쓴다")
        for i, sub in enumerate(c.any_of or []):
            cond(sub, f"{path}.any_of[{i}]", benefit)

    s = rules.spend
    if s.basis == "billing_cycle":
        err("spend.basis", "결제일 기준 실적은 이용기간 표가 모델에 들어간 뒤에 쓴다")
    cats(s.exclude_categories, "spend.exclude_categories")
    cats(list(s.month_offset), "spend.month_offset")
    for i, o in enumerate(s.cancellation_overrides):
        cond(o.when, f"spend.cancellation_overrides[{i}].when", None)
    be = rules.benefit_exclusions
    cats(be.categories, "benefit_exclusions.categories")
    for i, w in enumerate(be.when_any):
        cond(w, f"benefit_exclusions.when_any[{i}]", None)
    if rules.new_card:
        if rules.new_card.tier not in tierset:
            err("new_card.tier", f"구간 {rules.new_card.tier}가 tiers에 없다")
        for k, v in rules.new_card.tier_by_benefit.items():
            if k not in benefit_keys:
                err("new_card.tier_by_benefit", f"혜택 {k}가 없다")
            if v not in tierset:
                err("new_card.tier_by_benefit", f"구간 {v}가 tiers에 없다")

    shared_first: dict[str, int] = {}
    ranked_first: dict[str, int] = {}
    ranked_use: Counter[str] = Counter()
    for b in rules.benefits:
        bp = f"benefits[{b.key}]"
        start, end = tiers[0], tiers[-1]
        if b.tiers:
            if b.tiers.start is not None:
                if b.tiers.start not in tierset:
                    err(f"{bp}.tiers.from", f"구간 {b.tiers.start}가 tiers에 없다")
                start = b.tiers.start
            if b.tiers.end is not None:
                if b.tiers.end not in tierset:
                    err(f"{bp}.tiers.to", f"구간 {b.tiers.end}가 tiers에 없다")
                end = b.tiers.end
            if start > end:
                err(f"{bp}.tiers", "from은 to 이하여야 한다")
            if b.tiers.waived_when:
                cond(b.tiers.waived_when, f"{bp}.tiers.waived_when", b)
        cats(b.target.categories + b.target.exclude_categories, f"{bp}.target")
        bad = [m for m in b.target.merchants + b.target.exclude_merchants if m not in cat.merchants]
        if bad:
            err(f"{bp}.target", f"가맹점 {bad}가 merchants.yaml에 없다")
        for i, c in enumerate(b.when):
            cond(c, f"{bp}.when[{i}]", b)
            if c.ranked in ranked_keys:
                ranked_use[c.ranked] += 1
                ranked_first[c.ranked] = min(ranked_first.get(c.ranked, start), start)
        rw = b.reward
        if rw.program is not None and rw.program not in cat.point_programs:
            err(f"{bp}.reward.program", f"포인트 {rw.program}가 point_programs.yaml에 없다")
        if rw.per_liter is not None and FUEL_PRICE_KEY not in cat.reference:
            err(f"{bp}.reward.per_liter", f"reference.yaml에 {FUEL_PRICE_KEY}가 없다")
        table(rw.rate, f"{bp}.reward.rate", start)
        table(rw.fixed, f"{bp}.reward.fixed", start)
        for i, lim in enumerate(b.limits):
            lp = f"{bp}.limits[{i}]"
            if lim.shared is not None:
                if lim.shared not in shared_keys:
                    err(f"{lp}.shared", f"공유 한도 {lim.shared}가 limits에 없다")
                shared_first[lim.shared] = min(shared_first.get(lim.shared, start), start)
            for name in ("amount", "count", "base"):
                table(getattr(lim, name), f"{lp}.{name}", start)
            for j, a in enumerate(lim.adjust):
                cond(a.when, f"{lp}.adjust[{j}].when", b)
        if b.stack not in stack_keys:
            err(f"{bp}.stack", f"묶음 {b.stack}가 stacks에 없다")
        if b.source is not None and b.source not in source_ids:
            err(f"{bp}.source", f"sources에 {b.source}가 없다")
        rates = list(rw.rate.values()) if isinstance(rw.rate, dict) else [rw.rate] if rw.rate else []
        if rates and max(rates) >= 5 and not b.limits:
            warn(bp, "비율이 5% 이상인데 한도가 없다")

    for lim in rules.limits:
        lp = f"limits[{lim.key}]"
        if lim.key not in shared_first:
            warn(lp, "쓰는 혜택이 없다")
        for name in ("amount", "count", "base"):
            table(getattr(lim, name), f"{lp}.{name}", shared_first.get(lim.key))
        for j, a in enumerate(lim.adjust):
            cond(a.when, f"{lp}.adjust[{j}].when", None)
    for st in rules.stacks:
        members = sorted(b.key for b in rules.benefits if b.stack == st.key)
        if st.pick == "priority" and sorted(st.order) != members:
            err(f"stacks[{st.key}].order", f"묶음의 혜택 {members}이 빠짐없이 한 번씩 있어야 한다")
    for rk in rules.ranked:
        if ranked_use[rk.key] < 2:
            err(f"ranked[{rk.key}]", "이 조건을 단 혜택이 둘 이상이어야 한다")
        table(rk.top, f"ranked[{rk.key}].top", ranked_first.get(rk.key))
    return out


def path_exists(data: Any, path: str) -> bool:
    """open_questions의 path가 파일 안의 칸을 가리키는지. [숫자]는 순서, [이름]은 key로 찾는다."""
    node = data
    for name, sel in _PATH_TOKEN.findall(path):
        if name:
            if not isinstance(node, dict) or name not in node:
                return False
            node = node[name]
        elif isinstance(node, list) and sel.isdigit():
            if int(sel) >= len(node):
                return False
            node = node[int(sel)]
        elif isinstance(node, list):
            found = [x for x in node if isinstance(x, dict) and x.get("key") == sel]
            if not found:
                return False
            node = found[0]
        else:
            return False
    return True


def benefit_keys(raw: Any) -> set[str]:
    """파일에 적힌 모든 개정의 혜택 key."""
    keys: set[str] = set()
    revisions = raw.get("revisions") if isinstance(raw, dict) else None
    for entry in revisions or []:
        if not isinstance(entry, dict):
            continue
        for b in entry.get("benefits") or []:
            if isinstance(b, dict) and "key" in b:
                keys.add(b["key"])
        patched = (entry.get("patch") or {}).get("benefits")
        if isinstance(patched, dict):
            keys |= {k for k, v in patched.items() if v is not None}
    return keys


def removed_benefit_keys(path: Path, raw_now: Any) -> set[str]:
    """직전 커밋의 같은 파일에 있던 혜택 key 중 지금 없는 것. git이 없거나 새 파일이면 빈 집합."""
    try:
        r = subprocess.run(
            ["git", "show", f"HEAD:./{path.name}"],
            cwd=path.parent,
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
    except OSError:
        return set()
    if r.returncode != 0:
        return set()
    try:
        old = yaml.safe_load(r.stdout)
    except yaml.YAMLError:
        return set()
    return benefit_keys(old) - benefit_keys(raw_now)
```

- [x] **5단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend
```

기대: `67 passed`, `All checks passed!`. 경고 테스트 하나는 임시 폴더에 git 저장소를 만들므로 git이 있어야 한다.

- [x] **6단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog/check.py backend/tests/catalog/conftest.py backend/tests/catalog/test_check.py backend/tests/catalog/test_warnings.py
git commit -m "feat: 카탈로그 교차 검사와 경고 추가" -m "작업 001. 구간, 대상, 조건, 보상, 한도, 묶음, 옵션, 사실, 날짜, 근거, key를 검사하고
한도 없는 높은 비율, 줄어드는 구간표, 빈 상품 코드, 사라진 혜택 key를 경고한다"
```

---

## 과제 6: check와 format 명령

**파일**
- 새로: `backend/cherry_core/catalog/__main__.py`
- 테스트: `backend/tests/catalog/test_cli.py`

**인터페이스**
- 받는 것: `catalog_files`, `format_file`, `check_catalog`, `load_catalog`.
- 내놓는 것: `main(argv) -> int`. `check`는 카드마다 개정 수, 혜택 수, 문장으로 남긴 조건 수, 확인 필요 수를 찍고 오류가 있으면 1을 돌려준다. `--root`를 주지 않으면 저장소의 `catalog/`를 본다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/catalog/test_cli.py`

```python
"""check와 format 명령."""

from cherry_core.catalog.__main__ import main

from .conftest import benefit


def test_check_passes_and_prints_summary(make_catalog, capsys):
    root = make_catalog()
    assert main(["check", "--root", str(root)]) == 0
    out = capsys.readouterr().out
    assert "카드 1장" in out
    assert "shinhan-test: 개정 1, 혜택 1, 문장으로 남긴 조건 0, 확인 필요 0" in out
    assert "오류 0" in out


def test_check_fails_on_error(make_catalog, capsys):
    root = make_catalog(lambda f: benefit(f).update(stack="pay"))
    assert main(["check", "--root", str(root)]) == 1
    assert "benefits[cafe-10].stack" in capsys.readouterr().out


def test_format_rewrites_non_canonical_files(make_catalog, capsys):
    root = make_catalog()
    path = root / "merchants.yaml"
    path.write_text("- {name: 스타벅스, key: starbucks, category: cafe, aliases: [스타벅스, 스벅]}\n", encoding="utf-8")
    assert main(["format", "--root", str(root)]) == 0
    assert "merchants.yaml" in capsys.readouterr().out
    assert main(["check", "--root", str(root)]) == 0
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/catalog/test_cli.py
```

기대: `ModuleNotFoundError: No module named 'cherry_core.catalog.__main__'`

- [x] **3단계: 명령을 쓴다**

`backend/cherry_core/catalog/__main__.py`

```python
"""카탈로그 명령. check는 검증, format은 고정 저장 형식으로 다시 쓰기."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .canonical import catalog_files, format_file
from .check import check_catalog
from .load import load_catalog

DEFAULT_ROOT = Path(__file__).resolve().parents[3] / "catalog"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.catalog")
    ap.add_argument("command", choices=["check", "format"])
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    if args.command == "format":
        changed = [p for p in catalog_files(args.root) if format_file(p)]
        print(f"형식을 고친 파일 {len(changed)}개")
        for p in changed:
            print(f"  {p.relative_to(args.root).as_posix()}")
        return 0

    cat = load_catalog(args.root)
    problems = check_catalog(cat)
    errors = [p for p in problems if p.level == "error"]
    warnings = [p for p in problems if p.level == "warning"]
    print(f"카드 {len(cat.cards)}장")
    for card in cat.cards.values():
        if not card.revisions:
            continue
        rules = card.revisions[-1][1]
        unmodeled = len(rules.unmodeled) + len(rules.benefit_exclusions.unmodeled)
        unmodeled += sum(len(b.unmodeled) for b in rules.benefits)
        print(
            f"  {card.card.id}: 개정 {len(card.revisions)}, 혜택 {len(rules.benefits)}, "
            f"문장으로 남긴 조건 {unmodeled}, 확인 필요 {len(card.card.open_questions)}"
        )
    print(f"오류 {len(errors)}")
    for p in errors:
        print(f"  {p}")
    print(f"경고 {len(warnings)}")
    for p in warnings:
        print(f"  {p}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend
uvx ruff format --check backend
```

기대: `70 passed`, `All checks passed!`, 형식 검사에서 고칠 파일 없음.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog/__main__.py backend/tests/catalog/test_cli.py
git commit -m "feat: 카탈로그 check와 format 명령 추가" -m "작업 001"
```

---

## 과제 7: 카드 파일을 카드사 폴더로 옮기기

내용은 1판 그대로 두고 자리만 옮긴다. git이 이동으로 알아보게 하려고 내용 변경과 커밋을 나눈다. 설계 4.4 끝.

- [x] **1단계: 옮긴다**

```bash
for f in catalog/cards/*.yaml; do id=$(basename "$f" .yaml); iss=${id%%-*}; mkdir -p "catalog/cards/$iss"; git mv "$f" "catalog/cards/$iss/$id.yaml"; done
```

- [x] **2단계: 확인한다**

```bash
git status --short | grep -c "^R "
ls catalog/cards
```

기대: `20`. 폴더는 hana, hyundai, ibk, kakaobank, kb, lotte, nh, samsung, shinhan, woori의 10개다.

- [x] **3단계: 커밋 지점**

```bash
git commit -m "refactor: 카드 파일을 카드사 폴더로 이동" -m "작업 001. 내용은 1판 그대로다. 다음 커밋들에서 2판으로 다시 쓴다"
```

---

## 과제 8: 공통 파일

업종을 2단 트리로 바꾸고, 가맹점에 기본 청구 방식을 더한다. 결제수단, 포인트, 기준값 파일과 카드사 파일 뼈대 10개를 만든다. 설계 2.3, 2.5, 3.1.

- [x] **1단계: 스크립트를 `$SCRATCH/common_v2.py`에 쓴다**

`$SCRATCH/common_v2.py`

```python
"""2판 공통 파일을 만든다. 업종 트리, 가맹점 업종과 기본 청구 방식, 결제수단, 포인트, 기준값, 카드사 파일 뼈대.

사용: python common_v2.py <카탈로그 폴더> <기름값 원> <기름값 기준일 YYYY-MM-DD>
"""

import sys
from datetime import date
from pathlib import Path

import yaml
from cherry_core.catalog.canonical import canonical_text

ROOT = Path(sys.argv[1])
FUEL, FUEL_DAY = int(sys.argv[2]), date.fromisoformat(sys.argv[3])


def c(code, name, kakao=None, children=()):
    out = {"code": code, "name": name}
    if kakao:
        out["kakao"] = kakao
    if children:
        out["children"] = [
            dict(zip(("code", "name", "kakao"), ch))
            if len(ch) == 3
            else dict(zip(("code", "name"), ch))
            for ch in children
        ]
    return out


CATEGORIES = [
    c("cafe", "카페", "CE7"),
    c("convenience", "편의점", "CS2"),
    c(
        "restaurant",
        "음식점",
        "FD6",
        [
            ("general", "일반음식점"),
            ("fastfood", "패스트푸드"),
            ("bakery", "제과·제빵"),
        ],
    ),
    c("delivery_app", "배달앱"),
    c("grocery_mart", "마트", "MT1"),
    c("department_store", "백화점"),
    c("online_shopping", "온라인 쇼핑"),
    c("fuel", "주유", "OL7"),
    c(
        "transit",
        "대중교통",
        None,
        [
            ("bus_city", "시내버스"),
            ("subway", "지하철", "SW8"),
            ("bus_intercity", "시외·고속버스"),
            ("rail", "철도"),
        ],
    ),
    c("taxi", "택시"),
    c(
        "telecom",
        "통신요금",
        None,
        [("mobile", "이동통신"), ("internet_tv", "인터넷·TV")],
    ),
    c("streaming", "구독·스트리밍"),
    c("movie", "영화", "CT1"),
    c("hospital", "병원", "HP8"),
    c("pharmacy", "약국", "PM9"),
    c(
        "education",
        "교육",
        None,
        [
            ("academy", "학원", "AC5"),
            ("study_material", "학습지"),
            ("tuition", "대학 등록금"),
            ("school_fee", "유치원·초중고 납입금"),
        ],
    ),
    c(
        "travel",
        "여행",
        None,
        [
            ("airline", "항공"),
            ("agency", "여행사"),
            ("hotel", "숙박", "AD5"),
            ("duty_free", "면세점"),
        ],
    ),
    c(
        "utility",
        "공과금",
        None,
        [("electricity", "전기요금"), ("gas", "도시가스"), ("water", "수도요금")],
    ),
    c("tax", "세금"),
    c("insurance", "보험료", None, [("private", "민간 보험"), ("social", "4대보험")]),
    c("beauty", "뷰티", None, [("salon", "미용실"), ("cosmetics", "화장품")]),
    c("gift_card", "상품권"),
    c("prepaid_charge", "선불 충전"),
    c("apartment_fee", "아파트관리비"),
    c("rent", "임대료"),
    c("annual_fee", "연회비"),
    c("laundry", "세탁"),
    c("pc_room", "PC방"),
    c("sports", "스포츠·레저"),
    c("pet", "반려동물"),
    c("other", "기타"),
]
MERCHANT_CATEGORY = {
    "korail": "transit.rail",
    "srt": "transit.rail",
    "yanolja": "travel.hotel",
}
AUTOPAY = {"skt", "kt", "lg_uplus", "liiv_m"}
SUBSCRIPTION = {
    "netflix",
    "youtube_premium",
    "tving",
    "wavve",
    "disney_plus",
    "watcha",
    "spotv_now",
    "melon",
    "genie",
    "coupang_wow",
    "naver_plus_membership",
}
PAYMENT_METHODS = [
    {"key": "physical_card", "name": "실물카드"},
    {"key": "samsung_pay", "name": "삼성페이"},
    {"key": "apple_pay", "name": "애플페이"},
    {
        "key": "naver_pay",
        "name": "네이버페이",
        "statement_names": ["네이버페이", "NAVERPAY"],
    },
    {
        "key": "kakao_pay",
        "name": "카카오페이",
        "statement_names": ["카카오페이", "KAKAOPAY"],
    },
    {"key": "toss_pay", "name": "토스페이", "statement_names": ["토스페이", "TOSSPAY"]},
    {"key": "payco", "name": "페이코", "statement_names": ["페이코", "PAYCO"]},
    {"key": "smile_pay", "name": "스마일페이", "statement_names": ["스마일페이"]},
    {"key": "ssg_pay", "name": "SSGPAY", "statement_names": ["SSGPAY", "쓱페이"]},
    {"key": "l_pay", "name": "L.PAY", "statement_names": ["L.PAY", "엘페이"]},
    {"key": "coupay", "name": "쿠페이", "statement_names": ["쿠페이", "COUPAY"]},
    {"key": "kb_pay", "name": "KB Pay"},
    {"key": "shinhan_sol_pay", "name": "신한 SOL페이"},
    {"key": "hana_pay", "name": "하나Pay"},
    {"key": "woori_won_pay", "name": "우리WON페이", "statement_names": ["우리페이"]},
    {"key": "nh_pay", "name": "NH페이"},
]
POINT_PROGRAMS = [
    {"key": "mysinhan_point", "name": "마이신한포인트", "won_per_point": 1},
    {"key": "samsung_bigpoint", "name": "삼성카드 빅포인트", "won_per_point": 1},
    {"key": "hyundai_m_point", "name": "현대카드 M포인트", "won_per_point": 1},
    {"key": "hana_money", "name": "하나머니", "won_per_point": 1},
    {"key": "woori_moa_point", "name": "우리카드 모아포인트", "won_per_point": 1},
    {"key": "npay_point", "name": "네이버페이 포인트", "won_per_point": 1},
    {"key": "nol_point", "name": "NOL 포인트", "won_per_point": 1},
]
ISSUERS = {
    "shinhan": "신한카드",
    "samsung": "삼성카드",
    "hyundai": "현대카드",
    "kb": "KB국민카드",
    "lotte": "롯데카드",
    "hana": "하나카드",
    "woori": "우리카드",
    "nh": "NH농협카드",
    "ibk": "IBK기업은행",
    "kakaobank": "카카오뱅크",
}


def write(rel, data):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(canonical_text(data), encoding="utf-8", newline="\n")


write("categories.yaml", CATEGORIES)
merchants = yaml.safe_load((ROOT / "merchants.yaml").read_text(encoding="utf-8"))
for m in merchants:
    m["category"] = MERCHANT_CATEGORY.get(m["key"], m["category"])
    if m["key"] in AUTOPAY:
        m["billing"] = "autopay"
    elif m["key"] in SUBSCRIPTION:
        m["billing"] = "subscription"
write("merchants.yaml", merchants)
write("payment_methods.yaml", PAYMENT_METHODS)
write("point_programs.yaml", POINT_PROGRAMS)
write(
    "reference.yaml",
    [
        {
            "key": "fuel_price_gasoline",
            "value": FUEL,
            "unit": "원/L",
            "as_of": FUEL_DAY,
            "source": "한국석유공사 오피넷 전국 평균 휘발유 판매가격",
        }
    ],
)
for key, name in ISSUERS.items():
    if not (ROOT / "issuers" / f"{key}.yaml").exists():
        write(f"issuers/{key}.yaml", {"schema_version": 2, "id": key, "name": name})
print("공통 파일과 카드사 파일 뼈대를 썼다")
```

- [x] **2단계: 기름값을 확인한다**

한국석유공사 오피넷에서 실행하는 날의 전국 평균 휘발유 판매가격을 찾는다. 소수점 아래는 버리고 원 단위로 쓴다. 찾지 못하면 사용자에게 묻는다. 추측한 값을 넣지 않는다.

- [x] **3단계: 돌린다**

```bash
uv run --project backend python "$SCRATCH/common_v2.py" catalog <기름값> <확인한 날 YYYY-MM-DD>
```

기대: `공통 파일과 카드사 파일 뼈대를 썼다`

- [x] **4단계: 공통 파일에 오류가 없는지 확인한다**

카드 파일은 아직 1판이라 카드 파일 오류는 나온다. 공통 파일과 카드사 파일 줄만 본다.

```bash
uv run --project backend python -m cherry_core.catalog check | grep -E "^  (categories|merchants|payment_methods|point_programs|reference)\.yaml|^  issuers/"
```

기대: 출력 없음.

- [x] **5단계: 커밋 지점**

```bash
git add catalog/categories.yaml catalog/merchants.yaml catalog/payment_methods.yaml catalog/point_programs.yaml catalog/reference.yaml catalog/issuers
git commit -m "feat: 카탈로그 2판 공통 파일 추가" -m "작업 001. 업종 2단 트리, 가맹점 기본 청구 방식, 결제수단, 포인트,
기름값 기준값, 카드사 파일 10개"
```

---

## 과제 9: 기계 변환

1판에서 그대로 옮길 수 있는 것을 스크립트로 옮긴다. 이름 끝이 `-t1`, `-t2`인 구간 복제 혜택은 나머지 칸이 같으면 구간표 하나로 합친다. 설계 4.4의 1번.

- [x] **1단계: 스크립트를 `$SCRATCH/convert_v1.py`에 쓴다**

`$SCRATCH/convert_v1.py`

```python
"""1판 카드 파일을 2판으로 기계 변환한다. 한 번 쓰고 지우는 작업용이라 저장소에 넣지 않는다.

사용: python convert_v1.py <카탈로그 폴더> <판단 목록 파일>
카드 파일은 <카탈로그>/cards/<카드사>/<id>.yaml에 1판 내용으로 있어야 하고, 같은 자리에 2판으로 덮어쓴다.
"""

import collections
import re
import sys
from pathlib import Path

import yaml
from cherry_core.catalog.canonical import canonical_text

ROOT, TODO = Path(sys.argv[1]), Path(sys.argv[2])
CATEGORY = {
    "public_transit": "transit",
    "travel_airline": "travel.airline",
    "hotel": "travel.hotel",
}
POINTS = {
    "shinhan": "mysinhan_point",
    "samsung": "samsung_bigpoint",
    "hyundai": "hyundai_m_point",
    "hana": "hana_money",
    "woori": "woori_moa_point",
    "ibk": "npay_point",
}
REWARD = {"discount": "billing_discount", "points": "points", "cashback": "cashback"}
SAME = [
    "target_type",
    "target_values",
    "channel",
    "kind",
    "min_txn_amount",
    "counts_toward_integrated_cap",
]
VARYING = [
    "rate_pct",
    "fixed_amount",
    "max_per_txn",
    "monthly_cap_amount",
    "monthly_cap_count",
    "daily_cap_count",
]
SUFFIX = re.compile(r"-t\d+$")
todo: list[str] = []


def categories(values):
    return [CATEGORY.get(v, v) for v in values if v != "overseas"]


def by_tier(bs, field, tiers):
    """묶음의 값이 구간마다 같으면 값 하나, 다르면 구간표."""
    table = {tiers[b["min_tier_index"]]: b[field] for b in bs}
    distinct = set(table.values())
    if distinct == {None}:
        return None
    return distinct.pop() if len(distinct) == 1 else table


def benefit(card, bs, tiers, has_integrated):
    b0 = bs[0]
    key = SUFFIX.sub("", b0["id"])
    out = {"key": key, "title": b0["title"]}
    when = []
    if b0["target_type"] == "all":
        out["target"] = {"all": True}
    elif b0["target_type"] == "category":
        cats = categories(b0["target_values"])
        if "overseas" in b0["target_values"]:
            if cats:
                todo.append(
                    f"{card['id']} {key}: 해외와 다른 업종이 한 혜택에 섞였다. 지역 조건으로 혜택을 나눈다"
                )
            else:
                when.append({"region": "overseas"})
        out["target"] = {"categories": cats} if cats else {"all": True}
    else:
        out["target"] = {"merchants": list(b0["target_values"])}
    if b0["channel"] != "any":
        when.append({"channel": b0["channel"]})
    if b0["min_txn_amount"]:
        when.append({"amount": {"min": b0["min_txn_amount"]}})
    if when:
        out["when"] = when
    reward = {"type": REWARD[b0["kind"]]}
    if b0["kind"] == "points":
        reward["program"] = POINTS[card["issuer"]]
    rate, fixed = by_tier(bs, "rate_pct", tiers), by_tier(bs, "fixed_amount", tiers)
    reward.update({"rate": rate} if rate is not None else {"fixed": fixed})
    out["reward"] = reward
    limits = []
    for field, per, kind in [
        ("max_per_txn", "txn", "amount"),
        ("daily_cap_count", "day", "count"),
        ("monthly_cap_amount", "month", "amount"),
        ("monthly_cap_count", "month", "count"),
    ]:
        v = by_tier(bs, field, tiers)
        if v is not None:
            limits.append({"per": per, kind: v})
    if has_integrated and b0["counts_toward_integrated_cap"]:
        limits.append({"shared": "integrated"})
    if limits:
        out["limits"] = limits
    start = tiers[min(b["min_tier_index"] for b in bs)]
    if start:
        out["tiers"] = {"from": start}
    if len(bs) == 1 and SUFFIX.search(b0["id"]):
        todo.append(
            f"{card['id']} {key}: 이름 끝 -t가 붙은 단일 혜택이었다. 적용 구간 끝 to를 원문으로 정한다"
        )
    if any(b["conditions_not_modeled"] for b in bs):
        todo.append(f"{card['id']} {key}: 1판 notes의 조건을 구조로 옮긴다")
    if b0.get("notes"):
        out["notes"] = b0["notes"]
    return out


def convert(c):
    tiers = [t["min_spend"] for t in c["spend_tiers"]]
    caps = {
        t["min_spend"]: t["integrated_cap"]
        for t in c["spend_tiers"]
        if t["integrated_cap"]
    }
    r = c["spend_rule"]
    spend = {
        "basis": "prev_calendar_month"
        if c["spend_basis"] == "prev_calendar_month"
        else "none",
        "exclude_categories": categories(r["excluded_categories"]),
        "interest_free": "exclude"
        if r["exclude_interest_free_installment"]
        else "count",
        "installment": r["installment_basis"],
        "cancellation": r["cancellation_basis"],
        "exclude_applied": 1 if r["exclude_discounted"] else 0,
    }
    if "overseas" in r["excluded_categories"]:
        spend["regions"] = ["domestic"]
    rev = {
        "effective_from": c["updated_at"],
        "effective_from_estimated": True,
        "source": "page",
        "tiers": tiers,
        "spend": spend,
    }
    if caps:
        rev["limits"] = [{"key": "integrated", "per": "month", "amount": caps}]
    groups = collections.defaultdict(list)
    for b in c["benefits"]:
        groups[SUFFIX.sub("", b["id"])].append(b)
    benefits = []
    for bs in groups.values():
        mergeable = all(len({str(b[f]) for b in bs}) == 1 for f in SAME) and all(
            len({b[f] is None for b in bs}) == 1 for f in VARYING
        )
        if mergeable:
            benefits.append(benefit(c, bs, tiers, bool(caps)))
        else:
            todo.append(
                f"{c['id']} {bs[0]['id']}: 구간 혜택의 조건이 달라 합치지 못했다"
            )
            benefits += [
                benefit(c, [b], tiers, bool(caps)) | {"key": b["id"]} for b in bs
            ]
    rev["benefits"] = benefits
    out = {
        "schema_version": 2,
        "id": c["id"],
        "issuer": c["issuer"],
        "name": c["name"],
        "kind": c["kind"],
        "status": "on_sale" if c["active"] else "discontinued",
        "annual_fees": [
            {"scope": "domestic", "amount": c["annual_fee_domestic"]},
            {"scope": "global", "amount": c["annual_fee_global"]},
        ],
        "sources": [
            {
                "id": "page",
                "kind": "product_page",
                "url": c["source_url"],
                "fetched_at": c["updated_at"],
            }
        ],
        "checked_at": c["updated_at"],
        "revisions": [rev],
    }
    if c.get("notes"):
        out["notes"] = c["notes"]
    return out


for path in sorted((ROOT / "cards").glob("*/*.yaml")):
    v1 = yaml.safe_load(path.read_text(encoding="utf-8"))
    path.write_text(canonical_text(convert(v1)), encoding="utf-8", newline="\n")
TODO.write_text("\n".join(todo) + "\n", encoding="utf-8")
print(
    f"카드 {len(list((ROOT / 'cards').glob('*/*.yaml')))}장 변환, 판단할 것 {len(todo)}건"
)
```

- [x] **2단계: 돌린다**

```bash
uv run --project backend python "$SCRATCH/convert_v1.py" catalog "$SCRATCH/todo.txt"
```

기대: `카드 20장 변환, 판단할 것 131건`

- [x] **3단계: 형식과 검증을 확인한다**

```bash
uv run --project backend python -m cherry_core.catalog format
uv run --project backend python -m cherry_core.catalog check | grep -E "^오류|^경고"
```

기대: `형식을 고친 파일 0개`, `오류 0`, `경고 20`. 경고는 모두 빈 `product_codes`다.

- [x] **4단계: 판단 목록을 저장소에 둔다**

다른 PC에서도 이어 받을 수 있게 목록을 작업 폴더에 옮긴다.

```bash
uv run --project backend python - "$SCRATCH/todo.txt" <<'EOF'
import sys
from collections import defaultdict
from pathlib import Path

items = defaultdict(list)
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    card, rest = line.split(" ", 1)
    items[card].append(rest)
cards = sorted(p.stem for p in Path("catalog/cards").glob("*/*.yaml"))
out = ["# 001 카드별 판단 목록", "", "과제 9의 기계 변환이 남긴 것과 시행일 조사다. 과제 12에서 처리하면 `- [x]`로 바꾼다.", ""]
for card in cards:
    out += [f"## {card}", "", "- [ ] 첫 개정 시행일을 출시일과 부가서비스 변경 공지로 정한다"]
    out += [f"- [ ] {x}" for x in items[card]] + [""]
Path("docs/work/001-catalog-schema-v2/judgment.md").write_text("\n".join(out), encoding="utf-8", newline="\n")
print(sum(len(v) for v in items.values()) + len(cards))
EOF
```

기대: `151`. 기계 변환이 남긴 131건과 카드마다 시행일 조사 1건이다.

- [x] **5단계: 커밋 지점**

```bash
git add catalog/cards
git commit -m "feat: 카드 20장을 2판 형식으로 기계 변환" -m "작업 001. 구간마다 복제한 혜택 20묶음을 구간표로 합쳐 혜택 206개가 169개가 됐다.
조건을 구조로 옮기는 일은 카드별 판단 목록으로 남겼다"
git add docs/work/001-catalog-schema-v2/judgment.md
git commit -m "docs: 카탈로그 2판 카드별 판단 목록 추가" -m "작업 001. 기계 변환이 남긴 131건과 시행일 조사 20건"
```

---

## 과제 10: 카드사 공통 실적 규칙 올리기

같은 카드사 카드끼리 값이 같은 실적 규칙 칸을 카드사 파일 기본값으로 올린다. 올리기 전과 뒤에 합친 개정이 카드마다 같은지 스크립트가 확인한다. 설계 4.4의 3번.

- [x] **1단계: 스크립트를 `$SCRATCH/lift_defaults.py`에 쓴다**

`$SCRATCH/lift_defaults.py`

```python
"""같은 카드사 카드끼리 값이 같은 실적 규칙 칸을 카드사 파일 기본값으로 올린다. 한 번 쓰고 지우는 작업용.

사용: uv run --project backend python lift_defaults.py <카탈로그 폴더>
올리기 전과 뒤에 합친 개정이 카드마다 같은지 확인하고, 다르면 파일을 쓰지 않고 멈춘다.
"""

import sys
from collections import defaultdict
from pathlib import Path

import yaml
from cherry_core.catalog.canonical import canonical_text
from cherry_core.catalog.resolve import resolve_card

ROOT = Path(sys.argv[1])


def read(path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def write(path, data):
    path.write_text(canonical_text(data), encoding="utf-8", newline="\n")


by_issuer = defaultdict(list)
for path in sorted((ROOT / "cards").glob("*/*.yaml")):
    by_issuer[path.parent.name].append((path, read(path)))

for issuer, cards in sorted(by_issuer.items()):
    ipath = ROOT / "issuers" / f"{issuer}.yaml"
    issuer_raw = read(ipath)
    before = {p: resolve_card(raw, issuer_raw) for p, raw in cards}
    if len(cards) < 2:
        print(f"{issuer}: 카드 1장이라 기본값을 올리지 않는다")
        continue
    spends = [raw["revisions"][0]["spend"] for _, raw in cards]
    common = {
        k: v
        for k, v in spends[0].items()
        if all(s.get(k, object()) == v for s in spends[1:])
    }
    if not common:
        print(f"{issuer}: 카드끼리 같은 실적 규칙이 없다")
        continue
    for _, raw in cards:
        spend = raw["revisions"][0]["spend"]
        for k in common:
            del spend[k]
        if not spend:
            del raw["revisions"][0]["spend"]
    first = min(raw["revisions"][0]["effective_from"] for _, raw in cards)
    issuer_raw["defaults"] = [
        {"effective_from": first, "effective_from_estimated": True, "spend": common}
    ]
    for p, raw in cards:
        after = resolve_card(raw, issuer_raw)
        if [r.data for r in after] != [r.data for r in before[p]]:
            sys.exit(f"{p.name}: 올린 뒤 합친 개정이 달라졌다. 파일을 쓰지 않고 멈춘다")
    write(ipath, issuer_raw)
    for p, raw in cards:
        write(p, raw)
    print(f"{issuer}: 카드 {len(cards)}장에서 {sorted(common)}를 올렸다")
```

- [x] **2단계: 돌린다**

```bash
uv run --project backend python "$SCRATCH/lift_defaults.py" catalog
```

기대: 카드가 두 장 이상인 7개 카드사에서 `...를 올렸다`, ibk, kakaobank, nh는 `카드 1장이라 기본값을 올리지 않는다`.

- [x] **3단계: 확인한다**

```bash
uv run --project backend python -m cherry_core.catalog format
uv run --project backend python -m cherry_core.catalog check | grep -E "^오류|^경고"
```

기대: `오류 0`, `경고 20`.

- [x] **4단계: 커밋 지점**

```bash
git add catalog/cards catalog/issuers
git commit -m "refactor: 카드사 공통 실적 규칙을 카드사 파일로 이동" -m "작업 001. 올리기 전과 뒤에 합친 개정이 카드마다 같은 것을 확인했다"
```

---

## 과제 11: 에이전트와 규칙 파일을 2판에 맞추기

과제 12와 13의 에이전트가 2판 규칙으로 일하게 한다. 조사 에이전트는 검증 명령을 돌려야 하므로 Bash와 Edit을 쓴다.

**파일**
- 고치기: `.claude/agents/card-researcher.md`, `.claude/agents/card-verifier.md`, `.claude/rules/catalog.md`

- [x] **1단계: `.claude/agents/card-researcher.md`를 다시 쓴다**

````markdown
---
name: card-researcher
description: 카드 카탈로그 2판 파일을 쓰거나 고친다. 새 카드 조사, 1판에서 옮긴 조건의 구조화, 갱신 때 새 개정 추가에 쓴다. 맡은 카드 id를 알려 줘야 한다.
tools: WebSearch, WebFetch, Read, Edit, Write, Glob, Grep, Bash
---

맡은 카드 파일 `catalog/cards/<카드사>/<id>.yaml`과 그 카드사 파일 `catalog/issuers/<카드사>.yaml`만 고친다. 공통 파일인 categories, merchants, payment_methods, point_programs, reference는 고치지 않고 필요한 것을 보고서에 적는다. git 명령은 쓰지 않는다. Bash는 검증과 형식 명령에만 쓴다.

## 먼저 읽을 것

- `docs/work/001-catalog-schema-v2/design.md` 2절. 모든 칸의 뜻과 예시가 있다
- `.claude/rules/catalog.md`
- 맡은 파일과 같은 카드사의 다른 카드 파일, 그 카드사 파일

## 출처

- 값은 카드사 공식 상품 페이지나 카드사가 올린 상품설명서와 약관 PDF에서만 옮긴다. 검색 결과, 블로그, 카드 비교 사이트는 공식 페이지를 찾는 데만 쓴다.
- 확인하지 못한 값은 추측하지 않는다. 기본값을 넣고 `open_questions`에 path, question, assumed로 남긴다.
- 원문을 새로 봤으면 `sources`에 넣고, 그 원문에서 옮긴 혜택의 `source`에 id를 적는다.

## 옮기는 규칙

- 조건은 `when`, 여러 혜택이 같이 쓰는 한도는 개정의 `limits`에 key를 붙이고 혜택에서 `shared`로 가리킨다.
- 기본 적립을 대신하는 혜택은 같은 `stacks` 묶음에, 더해서 받는 혜택은 다른 묶음에 둔다.
- 사용자가 고르는 패키지와 모드는 `options`, 이번 달 이용액 순위로 고르는 영역은 `ranked`, 사용자에게 물을 것은 `facts`다.
- 결제 입력으로 판단할 수 없는 조건만 `unmodeled`에 문장으로 남긴다. 입점 매장 제외, 지정 품목, 다른 행사 할인과의 관계, 가족카드 합산 같은 것이다.
- 행사 혜택은 `valid_from`과 `valid_until`을 쓴다. 기존 값이 바뀌는 날이 정해져 있으면 그날 `patch` 개정을 더한다.
- 한 번 정한 혜택 key는 바꾸지 않는다. 혜택을 나눠야 하면 새 key를 만들고 보고한다.
- 파일에 주석을 쓰지 않는다. 사람용 메모는 `notes`에 쓴다.
- 고친 뒤 `uv run --project backend python -m cherry_core.catalog format`과 `check`를 돌린다. 맡은 파일에서 나온 오류가 0이어야 끝난다. 공통 파일에 없는 키 때문에 남는 오류는 보고서에 적는다.

## 보고

카드마다 10줄 이내 한국어로 쓴다.
- 파일 이름, 처리한 판단 목록 항목 수
- 새로 본 공식 원문
- `unmodeled`로 남긴 것
- `open_questions`로 남긴 것
- 새로 만든 혜택 key와 이유
- 공통 파일에 더해야 할 가맹점, 업종, 결제수단, 포인트
````

- [x] **2단계: `.claude/agents/card-verifier.md`의 "순서" 앞에 한 절을 더한다**

```markdown
## 먼저 읽을 것

- `docs/work/001-catalog-schema-v2/design.md` 2절. 2판 칸의 뜻
- 카드 파일만이 아니라 그 카드사 파일 `catalog/issuers/<카드사>.yaml`도 본다. 실적 규칙 일부는 카드사 기본값에서 온다
```

같은 파일 "순서" 3번의 끝에 문장을 더한다. `공유 한도는 limits의 key와 shared, 중복은 stacks, 고르는 패키지는 options, 이용액 순위는 ranked로 담겼는지 본다.`

- [x] **3단계: `.claude/rules/catalog.md`를 다시 쓴다**

````markdown
---
paths:
  - "catalog/**"
  - "backend/cherry_core/catalog/**"
---

# 카드 카탈로그 규칙

카탈로그는 2판이다. 칸의 뜻과 예시는 `docs/work/001-catalog-schema-v2/design.md` 2절과 3절, 코드는 `backend/cherry_core/catalog/models.py`가 기준이다.

## 파일

- 카드는 `catalog/cards/<카드사>/<카드 id>.yaml`, 카드사 공통 규칙은 `catalog/issuers/<카드사>.yaml`이다.
- 공통 파일은 `categories.yaml`, `merchants.yaml`, `payment_methods.yaml`, `point_programs.yaml`, `reference.yaml`이다. 여러 에이전트가 동시에 일할 때는 공통 파일을 한 곳에서만 고친다.
- 파일에 주석을 쓰지 않는다. `format`이 지운다. 사람용 메모는 `notes`에 쓴다.

## 값

- 값은 카드사 공식 상품 페이지나 카드사가 올린 상품설명서와 약관 PDF에서만 옮긴다.
- 확인하지 못한 값은 추측하지 않고 `open_questions`에 남긴다.
- 금액은 원 단위 정수, 비율은 퍼센트 숫자다.
- 결제 입력으로 판단할 수 없는 조건만 `unmodeled`에 문장으로 남긴다.
- 신규 발급이 끝난 카드도 지우지 않는다. `status`를 바꾼다.
- 한 번 정한 카드 id와 혜택 key는 바꾸지 않는다. 결제 기록이 그 key를 가리킨다.
- 카드사가 혜택을 바꾸면 옛 개정을 지우지 않고 새 개정을 더한다.

## 명령

- 검증: `uv run --project backend python -m cherry_core.catalog check`
- 형식: `uv run --project backend python -m cherry_core.catalog format`
- 파일을 고치면 훅이 검증을 돌린다. 오류가 나오면 그 자리에서 고친다.
````

- [x] **4단계: 커밋 지점**

```bash
git add .claude/agents/card-researcher.md .claude/agents/card-verifier.md .claude/rules/catalog.md
git commit -m "chore: 카드 조사와 대조 에이전트를 카탈로그 2판에 맞춤" -m "작업 001. 조사 에이전트가 검증 명령을 돌릴 수 있게 한다"
```

에이전트 정의는 세션을 시작할 때 읽힌다. 과제 12를 같은 세션에서 하면 general-purpose 에이전트를 띄우고, 1단계의 본문을 프롬프트 앞에 붙인다.

---

## 과제 12: 카드별 판단

1판 notes에 문장으로만 있던 규칙을 구조로 옮기고, 카드마다 첫 개정 시행일을 공식 근거로 정한다. 판단 목록은 `docs/work/001-catalog-schema-v2/judgment.md`에 있다. 설계 4.4의 4번과 4.6의 1번.

**나누는 방법.** 에이전트 6개를 동시에 띄운다. 에이전트는 자기 카드와 자기 카드사 파일만 고치므로 서로 부딪치지 않는다.

| 묶음 | 카드 | 판단 목록 수 |
|---|---|---|
| A | shinhan-cheoeum, shinhan-mrlife, shinhan-pointplan | 21 |
| B | samsung-id-on, samsung-taptap-o, hyundai-m, hyundai-the-green-ed4, hyundai-zero-edition3-discount | 29 |
| C | kb-easy-all-titanium, kb-my-wesh, kb-toktok | 33 |
| D | lotte-loca-classic, lotte-loca365, hana-travelog-check, hana-wonder2-daily, woori-every-point, woori-k-life-check | 25 |
| E | ibk-narasarang | 26 |
| F | nh-zgm-discount, kakaobank-friends-check | 17 |

**첫 개정 시행일 정하기.** 카드사가 부가서비스를 줄이려면 바뀌는 날의 6개월 전까지 홈페이지를 포함한 두 가지 이상의 방법으로 알려야 한다. 그래서 줄어든 날은 카드사 공지에 시행일로 남는다. 카드마다 다음 순서로 정한다.
1. 공식 페이지나 카드사 보도자료에서 출시일을 찾는다.
2. 카드사 홈페이지 공지에서 그 카드의 부가서비스 변경 안내를 출시 뒤부터 찾는다. 최소한 최근 1년은 끝까지 본다.
3. 출시일과 마지막 변경 시행일 중 늦은 날을 첫 개정의 `effective_from`으로 쓰고 `effective_from_estimated`를 지운다. 근거가 된 공지나 출시 안내는 `sources`에 넣는다. 공지는 `kind: notice`다. 카드 `notes`에 `첫 개정 시행일 근거: <sources id>`를 적는다.
4. 공지 목록을 끝까지 확인하지 못했으면 지금 날짜와 추정 표시를 그대로 두고, `open_questions`에 `revisions[0].effective_from`으로 남긴다.
5. 공지에서 앞으로 바뀔 내용을 찾으면 그 시행일에 `patch` 개정을 더한다.
6. 첫 개정 날짜를 앞당기면 카드사 파일 `defaults`의 첫 `effective_from`도 그 카드사 카드 중 가장 이른 첫 개정 날짜 이하로 맞춘다. 그러지 않으면 그 사이 개정에 공통 규칙이 빠져 검증 오류가 난다. 카드사 공통 약관의 시행일을 찾으면 그 날을 쓰고, 못 찾으면 추정 표시를 둔다.

1판 기록에 출시일이 이미 있는 카드는 the Green Edition4 2026-09-09, 현대카드M 2024-01-19, zgm 할인카드 2024-04-23이다. 이 경우에도 출시 뒤 변경 공지는 확인한다.

**묶음마다 특히 볼 것.** 1판 notes에서 뽑은 것이다. 에이전트는 이것만이 아니라 판단 목록과 notes 전부를 처리한다.
- A 신한
  - 교통카드 이용액은 전전월 실적에 들어간다. `spend.month_offset`으로 담는다.
  - Mr.Life에는 TIME 야간 할인의 시각 조건과 주말 조건이 있다. 주말 마트와 주유는 한도를 같이 쓴다.
  - Point Plan은 결제액 구간마다 적립률이 다르고, 자동납부는 2만원당 1천P다. 가족행사월 5월과 12월에는 한도가 늘어난다. SOL페이 추가 적립은 따로 더해 받는다.
  - 처음은 서비스마다 통합 한도가 따로 있다.
  - 세 카드 모두 신규 발급 특례와 간편결제 가맹점명 제외가 있다.
- B 삼성, 현대
  - iD ON의 많이 쓰는 영역 30%는 `ranked` top 1이다. 할인 받은 건의 실적 제외는 세 혜택에만 있다. 3% 한도를 넘기면 다음 결제부터 1%다.
  - taptap O는 패키지 6개가 `options`다. 영화는 연 12회 한도다.
  - 현대카드M과 the Green은 5% 영역 혜택이 기본 1.5%를 대신하고, 한도를 넘은 금액은 1.5%로 받는다. 해외와 국내 영역은 지역 조건으로 나눈다. the Green은 해외 취소만 취소 달에 뺀다.
- C KB
  - Easy all은 Auto와 DIY 모드가 `options`다. DIY는 `unsupported`다. 그룹 A부터 D까지 구간마다 상위 몇 개 영역을 받는지가 `ranked`다.
  - My WE:SH는 팩 3개가 `options`이고, 생일 달에는 한도가 두 배다.
  - 톡톡의 간편결제 10%는 다른 할인에 더해 받는다.
- D 롯데, 하나, 우리
  - LOCA 365는 건당 2만원 이상이 조건이고 스트리밍만 금액 조건이 없다. LOCA CLASSIC은 150만 구간에서 비율이 바뀐다.
  - 원더카드 2.0은 하나Pay에서 영역을 고른다. 트래블로그는 국내와 해외를 지역으로 나눈다.
  - EVERY POINT의 간편결제 2%는 기본 0.8%에 더해 받는다. K-LIFE는 혜택 받은 건의 50%만 실적에서 빠지고, 실적은 국내만 센다.
- E IBK
  - 사실 셋이 필요하다. 현역병, 병 급여이체, 마이태그다. 병 급여이체자는 나라·사랑 서비스의 구간 조건이 면제되고 PX 횟수 제한이 없다.
  - 나라·사랑의 편의점과 교통 할인은 20만 구간까지만 받는다.
  - PX 기본할인은 결제액 구간마다 비율이 다르고 한도를 같이 쓴다. PX 특별할인은 연 한도가 있다.
  - Npay 적립 횟수는 2026-12-31까지 5회, 7회, 10회이고 2027-01-01부터 5회다. 그날 `patch` 개정을 더한다. 혜택 key는 `npay-points`를 유지한다.
  - 행사 혜택은 `valid_until: 2026-12-31`이다. GS25 주요품목처럼 결제 때 빠지는 할인은 `onsite_discount`다.
  - 메가오더 평일과 주말은 요일 조건이다.
  - NOL 적립 한도는 다른 카드사 나라사랑카드와 같이 쓰므로 `unmodeled`다.
  - 확인 필요 네 가지는 `open_questions`에 넣는다. 과제 14에서 사용자에게 묻는다.
- F NH, 카카오뱅크
  - zgm은 기본할인에 하루 1만원 한도가 있다. 기본할인과 생활할인은 둘 중 큰 쪽만 받는다. 생활할인은 통합 2만원 한도가 있고 등록 달에는 없다.
  - 카카오뱅크는 평일과 주말·공휴일 적립률이 다르다. 행사 기간은 2026-02-01부터 2027-01-31까지다. 후불교통은 한 달 합산 5만원 이상이면 4천원이다. GS25와 저가커피 혜택은 횟수와 금액 한도를 같이 쓴다.

- [x] **1단계: 묶음마다 에이전트를 띄운다**

에이전트 종류는 `card-researcher`다. 같은 세션이면 과제 11의 설명대로 general-purpose를 쓴다. 프롬프트는 다음 틀에 묶음 값을 채운다.

````text
카탈로그 2판 카드별 판단을 맡는다. 맡은 카드: <묶음의 카드 id 목록>

해야 할 것
1. docs/work/001-catalog-schema-v2/judgment.md에서 맡은 카드의 항목을 전부 처리한다. judgment.md는 고치지 않고 처리한 항목을 보고서에 적는다. 여러 에이전트가 동시에 고치면 서로 덮어쓸 수 있어서, 표시는 에이전트가 모두 끝난 뒤 한 곳에서 한다.
2. 카드 파일의 notes와 혜택 notes에 적힌 조건을 하나씩 구조로 옮긴다. 옮긴 뒤 notes에는 원문 요약만 남긴다. 조건이 notes에만 있고 구조, unmodeled, open_questions 어디에도 없으면 안 된다.
3. 카드사 파일에 collect를 채운다. 상품 목록 주소, 수집 방법, 갱신 주기다. 수집 방법은 설계 문서 3절의 조사 결과를 따른다. 삼성과 BC는 blocked, 신한은 상품 API가 있어 api다. 공식 상품 목록 주소를 찾지 못하면 collect를 쓰지 않고 보고한다. 주소는 비워 둘 수 없는 칸이다.
4. 상품 코드를 알면 product_codes에 넣는다. 1판 notes의 entryId, cdPrdCd 같은 값이다.
5. 연회비 brand, search_names를 공식 문구로 채운다.
6. 카드마다 첫 개정 시행일을 계획 과제 12의 "첫 개정 시행일 정하기" 순서대로 정한다. 근거는 카드사 공식 공지와 공식 페이지만 쓴다.

묶음에서 특히 볼 것: <위 목록의 해당 묶음>

지켜야 할 것: .claude/agents/card-researcher.md 전부.
format 명령은 다른 에이전트의 파일까지 다시 쓰므로 쓰지 않는다. 자기 파일만 cherry_core.catalog.canonical.format_file로 고친다.
끝나면 check를 돌리고, 맡은 파일의 오류가 0인지 확인한 뒤 보고한다. 다른 에이전트가 고치는 중인 파일의 오류는 무시한다.
````

2026-09-29 실행 때는 이 틀과 그 묶음의 "특히 볼 것", "첫 개정 시행일 정하기", 판단 목록, card-researcher.md 본문을 합친 지시문 파일을 scratchpad에 만들어 에이전트에게 읽게 했다.

- [x] **2단계: 공통 파일을 한 번에 고친다**

에이전트 6개가 모두 끝나면 보고서의 "공통 파일에 더해야 할 것"을 모아 공통 파일에 더한다. 새 가맹점에는 한글 별칭을 2개 이상 넣는다.

- [x] **3단계: 전체를 확인한다**

```bash
uv run --project backend python -m cherry_core.catalog format
uv run --project backend python -m cherry_core.catalog check | grep -E "^오류|^경고"
grep -c "^- \[ \]" docs/work/001-catalog-schema-v2/judgment.md
```

기대: `오류 0`. 경고에는 빈 product_codes가 줄어 있다. 남은 판단 항목은 `0`이다.

- [x] **4단계: 커밋 지점**

공통 파일과 묶음마다 커밋을 나눈다.

```bash
git add catalog/merchants.yaml catalog/categories.yaml catalog/payment_methods.yaml catalog/point_programs.yaml
git commit -m "feat: 카드별 판단에서 나온 가맹점과 결제수단 추가" -m "작업 001"
git add catalog/cards/shinhan catalog/issuers/shinhan.yaml
git commit -m "feat: 신한카드 3장의 조건과 한도를 2판 구조로 옮김" -m "작업 001"
```

B부터 F까지 같은 방식으로 커밋한다. 메시지는 `feat: <카드사> 카드의 조건과 한도를 2판 구조로 옮김`이다. 판단 목록은 마지막에 따로 커밋한다.

```bash
git add docs/work/001-catalog-schema-v2/judgment.md
git commit -m "docs: 카드별 판단 목록 처리 결과 반영" -m "작업 001"
```

2026-09-29 실행 결과: 판단 목록 151건을 모두 처리했고 검증 오류와 경고는 0개다. 실행 중 검증기 버그 2개를 고쳤다. 카드사 기본값의 추정 시작일이 확정된 카드 개정을 추정으로 만들던 것과, 숫자처럼 보이는 글자를 따옴표 없이 쓰던 것이다. 그래서 이 문서 과제 2와 3에 넣은 코드는 그 뒤 고친 저장소 코드와 조금 다르다. 과제 13에서 볼 것은 judgment.md의 "과제 12 결과"에 있다.

---

## 과제 13: 원문 대조

조사한 에이전트와 다른 에이전트가 2판 파일을 공식 원문과 따로 대조한다. 설계 4.4의 5번.

- [x] **1단계: 묶음마다 `card-verifier` 에이전트를 띄운다**

과제 12와 같은 6묶음이다. 프롬프트는 `맡은 카드: <목록>. 카드 파일과 카드사 파일을 공식 원문과 대조하고 불일치 목록을 돌려준다`이다.

- [x] **2단계: 불일치를 기록하고 고친다**

`judgment.md` 끝에 `## 원문 대조 결과` 절을 만들고 불일치를 한 줄씩 적는다. 금액이 틀린 것과 조건이 빠진 것은 반드시 고친다. 표기만 다른 것은 고치되 판단이 갈리면 사용자에게 묻는다. 고치는 일은 그 묶음의 `card-researcher`에 맡기거나 직접 한다.

- [x] **3단계: 확인한다**

```bash
uv run --project backend python -m cherry_core.catalog format
uv run --project backend python -m cherry_core.catalog check | grep -E "^오류"
```

기대: `오류 0`

- [x] **4단계: 커밋 지점**

```bash
git add catalog docs/work/001-catalog-schema-v2/judgment.md
git commit -m "fix: 원문 대조로 찾은 카드 값 불일치 수정" -m "작업 001. 불일치 목록은 judgment.md 원문 대조 결과"
```

2026-09-29 실행 결과: 불일치를 모두 고쳤고 검증 오류와 경고는 0개, 검증기 테스트는 75개가 통과한다. 목록은 judgment.md "원문 대조 결과"에 있다. 계획과 달라진 점이 셋이다.
- 한 영역을 혜택 여럿으로 나눠도 순위를 합쳐 매기도록 혜택에 `area` 칸을 더했다. KB Easy all 해외/면세점과 삼성 iD ON 스타벅스 때문이다. 설계 2.8
- 커밋은 스키마, 공통 파일, 묶음 여섯으로 나눴다
- 고치는 에이전트도 judgment.md와 전체 format 명령을 쓰지 않고 맡은 파일만 형식을 맞췄다

---

## 과제 14: IBK 나라사랑카드 확인

사용자가 가진 카드라 직접 확인받는다. 설계 4.4의 6번, intent.md의 마지막 성공 기준.

- [x] **1단계: 네 가지를 묻는다**

1. 대중교통 20% 할인이 월 통합할인한도에 들어가는지
2. 편의점 All in One 할인이 하루 1회인지 2회인지
3. PX 할인이 결제할 때 빠지는지, 청구서에서 빠지는지
4. 메가오더 제휴 할인이 All in One 할인과 중복되는지

- [x] **2단계: 반영한다**

답을 받은 항목은 값을 고치고 `open_questions`에서 지운다. 답이 없는 항목은 `open_questions`에 남긴다. PX가 결제할 때 빠지면 보상 `type`을 `onsite_discount`로 바꾼다.

- [x] **3단계: 확인과 커밋 지점**

```bash
uv run --project backend python -m cherry_core.catalog check | grep -E "^오류"
git add catalog/cards/ibk/ibk-narasarang.yaml
git commit -m "fix: IBK 나라사랑카드 확인 항목 반영" -m "작업 001. 사용자가 확인한 값과 남은 확인 필요 항목"
```

2026-09-29 실행 결과: 편의점 1일 2회는 사용자가 확인해 확인 필요에서 뺐다. PX는 사용자가 처음에 현장할인으로 봤다가 청구할인 같다고 고쳐 청구할인을 유지했다. 공식 문구가 없어 확인 필요로 남겼다. 대중교통 통합한도와 메가오더 중복은 사용자도 몰라 확인 필요로 남았다. 사용자가 보내 준 PX 표는 파일의 구간, 할인율, 한도, 횟수와 같았다.

---

## 과제 15: 성공 기준 확인

intent.md의 성공 기준을 테스트와 보고로 하나씩 확인한다.

**파일**
- 테스트: `backend/tests/catalog/test_real_catalog.py`

- [x] **1단계: 실제 카탈로그 테스트를 쓴다**

`backend/tests/catalog/test_real_catalog.py`

```python
"""실제 카탈로그로 작업 001 성공 기준을 확인한다. docs/work/001-catalog-schema-v2/intent.md."""

import copy
import re
from datetime import date
from pathlib import Path

import pytest

from cherry_core.catalog.canonical import catalog_files, is_canonical
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.resolve import resolve_card, revision_for

ROOT = Path(__file__).resolve().parents[3] / "catalog"


@pytest.fixture(scope="module")
def cat():
    return load_catalog(ROOT)


def test_twenty_cards_pass_check(cat):
    assert [str(p) for p in check_catalog(cat) if p.level == "error"] == []
    assert len(cat.cards) == 20


def test_no_benefit_is_copied_per_tier(cat):
    copies = [
        f"{c.card.id}:{b.key}"
        for c in cat.cards.values()
        for _, rules in c.revisions
        for b in rules.benefits
        if re.search(r"-t\d+$", b.key)
    ]
    assert copies == []


def test_every_file_is_canonical():
    assert [p.relative_to(ROOT).as_posix() for p in catalog_files(ROOT) if not is_canonical(p)] == []


def _written_spend_keys(raw: dict) -> set[str]:
    keys = set()
    for entry in raw["revisions"]:
        keys |= set(entry.get("spend") or {})
        keys |= set((entry.get("patch") or {}).get("spend") or {})
    return keys


def test_issuer_default_change_reaches_every_card(cat):
    tested = 0
    for issuer_id, issuer in cat.issuers.items():
        cards = [c for c in cat.cards.values() if c.card.issuer == issuer_id]
        defaults = issuer.issuer.model_dump(by_alias=True, exclude_unset=True).get("defaults") or []
        if len(cards) < 2 or not defaults or not defaults[-1].get("spend"):
            continue
        written = set().union(*(_written_spend_keys(c.raw) for c in cards))
        free = [k for k in defaults[-1]["spend"] if k not in written]
        if not free:
            continue
        changed = copy.deepcopy(issuer.issuer.model_dump(by_alias=True, exclude_unset=True))
        changed["defaults"][-1]["spend"][free[0]] = "CHANGED"
        for c in cards:
            resolved = resolve_card(c.card.model_dump(by_alias=True, exclude_unset=True), changed)
            assert resolved[-1].data["spend"][free[0]] == "CHANGED", c.card.id
        tested += 1
    assert tested >= 1


def test_npay_change_splits_on_2027_01_01(cat):
    revisions = [r for r, _ in cat.cards["ibk-narasarang"].revisions]
    before = revision_for(revisions, date(2026, 12, 31))
    after = revision_for(revisions, date(2027, 1, 1))
    assert before.effective_from < date(2027, 1, 1) <= after.effective_from

    def npay(r):
        return next(b for b in r.data["benefits"] if b["key"] == "npay-points")

    assert npay(before) != npay(after)
```

- [x] **2단계: 돌린다**

```bash
uv run --project backend pytest -q
```

기대: `75 passed`

- [x] **3단계: 카드별 보고를 만든다**

```bash
uv run --project backend python - <<'EOF'
from pathlib import Path

from cherry_core.catalog.load import load_catalog

cat = load_catalog(Path("catalog"))
for c in cat.cards.values():
    rules = c.revisions[-1][1]
    first = c.revisions[0][0]
    mark = " 추정" if first.effective_from_estimated else ""
    print(f"### {c.card.id}. 혜택 {len(rules.benefits)}개, 첫 개정 {first.effective_from}{mark}")
    for b in rules.benefits:
        for u in b.unmodeled:
            print(f"- 문장으로 남김 {b.key}: {u}")
    for u in rules.unmodeled + rules.benefit_exclusions.unmodeled:
        print(f"- 문장으로 남김 카드 전체: {u}")
    for q in c.card.open_questions:
        print(f"- 확인 필요 {q.path}: {q.question}")
EOF
```

출력을 `judgment.md` 끝의 `## 결과` 절에 붙인다. 1판 혜택 수는 다음과 같다.

| 카드 | 1판 혜택 |
|---|---|
| hana-travelog-check | 2 |
| hana-wonder2-daily | 21 |
| hyundai-m | 2 |
| hyundai-the-green-ed4 | 4 |
| hyundai-zero-edition3-discount | 1 |
| ibk-narasarang | 36 |
| kakaobank-friends-check | 12 |
| kb-easy-all-titanium | 19 |
| kb-my-wesh | 8 |
| kb-toktok | 4 |
| lotte-loca-classic | 2 |
| lotte-loca365 | 8 |
| nh-zgm-discount | 10 |
| samsung-id-on | 6 |
| samsung-taptap-o | 12 |
| shinhan-cheoeum | 21 |
| shinhan-mrlife | 15 |
| shinhan-pointplan | 11 |
| woori-every-point | 2 |
| woori-k-life-check | 10 |

- [x] **4단계: 성공 기준을 하나씩 적는다**

`plan.md` 끝 `## 성공 기준 확인` 표에 기준마다 근거를 적는다.

| 성공 기준 | 근거 |
|---|---|
| 20장이 2판 검증을 통과한다 | `test_twenty_cards_pass_check` |
| 구조로 담을 수 있는데 문장으로만 남긴 조건이 없다 | 3단계 보고의 "문장으로 남김" 목록을 사용자가 검토 |
| 구간별 복제 혜택이 남지 않는다 | `test_no_benefit_is_copied_per_tier` |
| 같은 원문으로 두 번 갱신해도 차이가 없다 | `test_every_file_is_canonical`과 과제 3의 `format` 두 번 테스트. 갱신기는 하위 프로젝트 3에서 만든다 |
| 카드사 공통 규칙 하나를 바꾸면 그 카드사 카드 전부에 반영된다 | `test_issuer_default_change_reaches_every_card` |
| 시행일 전날과 당일이 다른 개정으로 해석된다 | `test_npay_change_splits_on_2027_01_01` |
| IBK 확인 필요 네 가지 | 과제 14 |
| 첫 개정 시행일 | 3단계 보고의 카드별 첫 개정 날짜. 추정으로 남은 카드는 확인 필요 항목에 있다 |

- [ ] **5단계: 사용자에게 보고하고 검토를 받는다**

2026-09-29 실행 결과: 테스트는 80개가 통과한다. 계획을 쓴 뒤 area 검사 테스트가 늘었다. 보고를 뽑다가 문장 조건 세 곳이 YAML 쉼표에서 잘린 것을 찾아 합쳤다. "문장으로 남김" 247개를 사용자 검토에 올렸다.

"문장으로 남김" 목록을 보여 주고, 구조로 담을 수 있는데 문장으로 남은 것이 있는지 확인받는다. 있으면 과제 12의 방법으로 고친다.

- [ ] **6단계: 커밋 지점**

```bash
git add backend/tests/catalog/test_real_catalog.py
git commit -m "test: 실제 카탈로그로 작업 001 성공 기준 테스트 추가" -m "작업 001"
git add docs/work/001-catalog-schema-v2/judgment.md docs/work/001-catalog-schema-v2/plan.md
git commit -m "docs: 카탈로그 2판 카드별 결과와 성공 기준 확인 추가" -m "작업 001"
```

---

## 과제 16: 파일 수정 뒤 검사를 2판으로 바꾸기

**파일**
- 고치기: `.claude/hooks/after_edit.py`, `.claude/settings.json`, `.claude/CLAUDE.md`, `README.md`
- 지우기: `tools/validate_catalog.py`

- [ ] **1단계: 훅을 고친다**

`.claude/hooks/after_edit.py`에서 다음 줄을

```python
    code, out = run(["uv", "run", "--script", "tools/validate_catalog.py"])
```

이렇게 바꾼다.

```python
    code, out = run(["uv", "run", "--project", "backend", "python", "-m", "cherry_core.catalog", "check"])
```

- [ ] **2단계: 권한과 명령 안내를 고친다**

`.claude/settings.json`의 `permissions.allow`에서 `"Bash(uv run --script tools/validate_catalog.py)"`를 `"Bash(uv run --project backend python -m cherry_core.catalog *)"`로 바꾼다.

`.claude/CLAUDE.md`의 명령 절 첫 줄을 다음 두 줄로 바꾼다.

```markdown
- 카탈로그 검증: `uv run --project backend python -m cherry_core.catalog check`
- 카탈로그 형식 고치기: `uv run --project backend python -m cherry_core.catalog format`
```

같은 절 둘째 줄의 `backend가 생긴 뒤부터`를 지운다.

`README.md` 폴더 절에서 `├── tools/         검증 스크립트` 줄을 지운다.

- [ ] **3단계: 1판 스크립트를 지운다**

```bash
git rm tools/validate_catalog.py
```

- [ ] **4단계: 훅이 막는지 확인한다**

저장소를 건드리지 않게 복사본에서 확인한다.

처음 한 번만 돌린다. 다시 돌리려면 `$SCRATCH/hooktest`를 지우고 돌린다.

```bash
H="$SCRATCH/hooktest"; mkdir -p "$H/backend" "$H/.claude/hooks"
cp -r backend/pyproject.toml backend/uv.lock backend/cherry_core "$H/backend/"
cp -r catalog "$H/"; cp .claude/hooks/after_edit.py "$H/.claude/hooks/"
F="$H/catalog/cards/kb/kb-toktok.yaml"; sed -i 's/^kind: credit$/kind: debit/' "$F"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(cygpath -m "$F")" | CLAUDE_PROJECT_DIR="$(cygpath -m "$H")" uv run --script .claude/hooks/after_edit.py; echo "exit $?"
sed -i 's/^kind: debit$/kind: credit/' "$F"
printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(cygpath -m "$F")" | CLAUDE_PROJECT_DIR="$(cygpath -m "$H")" uv run --script .claude/hooks/after_edit.py; echo "exit $?"
```

기대: 첫 번째는 `카탈로그 검증 실패`와 `cards/kb/kb-toktok.yaml: kind`가 나오고 `exit 2`. 두 번째는 `exit 0`.

- [ ] **5단계: 커밋 지점**

```bash
git add .claude/hooks/after_edit.py .claude/settings.json .claude/CLAUDE.md README.md
git commit -m "chore: 파일 수정 뒤 검사를 카탈로그 2판 검증기로 교체" -m "작업 001. 1판 검증 스크립트를 지운다"
```

---

## 과제 17: 전체 문서에 결론 합치기

기준은 전체 문서이고 작업 폴더는 이력이다. `/work` 스킬의 "끝" 절차다.

**파일**
- 고치기: `docs/2026-09-19-cherryconsume-design.md`, `docs/erd.md`, `docs/erd.html`, `docs/scenarios.md`, `README.md`

- [ ] **1단계: 설계 문서 6.2절 저장소 구조를 바꾼다**

코드 블록을 다음으로 바꾸고, 그 아래 `backend/`는 뒤에 FastAPI 패키지 `cherry_api`가 추가될 자리라는 문장은 둔다.

```
cherryConsume/
  backend/
    pyproject.toml
    uv.lock
    cherry_core/
      catalog/           # 카탈로그 2판 모델, 합치기, 검증, 저장 형식. 작업 001
        models.py
        resolve.py
        load.py
        check.py
        canonical.py
        __main__.py      # check, format 명령
    tests/
  catalog/
    categories.yaml      # 업종 2단 트리
    merchants.yaml       # 가맹점, 별칭, 기본 청구 방식
    payment_methods.yaml # 결제수단
    point_programs.yaml  # 포인트와 1포인트 가치
    reference.yaml       # 기름값 같은 기준값
    issuers/<카드사>.yaml
    cards/<카드사>/<카드 id>.yaml
  design/
  docs/
    work/                # 작업 단위별 의도, 설계, 계획
    history/             # 작업 기록
```

실적과 추천 계산 모듈은 작업 002에서 `cherry_core` 아래에 더한다는 문장을 코드 블록 아래에 더한다.

- [ ] **2단계: 6.3절 데이터 모델을 바꾼다**

"모두 Pydantic 모델. 금액 단위는 원, 정수." 다음부터 **Transaction 결제** 앞까지의 Card, SpendTier, SpendRule, Benefit 표 넷을 다음으로 바꾼다.

```markdown
**카탈로그 모델**은 2판이다. 칸마다의 뜻과 예시는 `docs/work/001-catalog-schema-v2/design.md` 2절, 코드는 `backend/cherry_core/catalog/models.py`가 기준이다.

| 모델 | 한 줄 설명 |
|---|---|
| CardFile | 카드 신원, 상품 코드, 발급 상태, 연회비, 공식 원문, 개정 목록, 확인 필요 항목 |
| Rules | 개정 하나의 규칙 전체. 구간, 실적 규칙, 신규 발급 특례, 모든 혜택 공통 제외, 사실, 옵션, 자동 선택, 공유 한도, 중복 묶음, 혜택, 문장으로 남긴 조건 |
| Benefit | 대상, 조건, 보상, 한도, 적용 구간, 중복 묶음, 행사 기간 |
| IssuerFile | 카드사 공통 규칙과 수집 설정 |

카드사 기본값과 패치를 합친 개정 전체가 계산의 입력이다. 결제일이 첫 개정보다 앞서면 첫 개정의 시행일이 추정일 때만 첫 개정을 쓴다.
```

**Transaction 결제** 표에서 `applied_benefit_id`와 `estimated_benefit` 줄을 지우고 다음 줄을 더한다.

```markdown
| region | domestic / overseas | 국내와 해외 |
| payment_method | str 또는 null | 결제수단. payment_methods.yaml의 키 |
| billing | normal / autopay / subscription / postpaid_transit / app_prepay / in_app | 청구 방식 |
| card_revision_id | int | 계산에 쓴 카드 개정 |
| source | manual / excel / notification | 결제가 들어온 곳 |
| benefits | TransactionBenefit[] | 입력 시점에 계산한 혜택. 중복 묶음이 여럿이면 여러 개. 혜택 key, 금액, 혜택 계산에 넣은 결제액 |
```

**UserCard 보유 카드** 표에 다음 줄을 더한다.

```markdown
| started_on | date 또는 null | 카드를 쓰기 시작한 날. 신규 발급 특례 |
| options | 옵션 선택 이력 | 옵션마다 고른 선택지와 적용 시작일 |
| facts | 사실 답 | 카드마다 다른 사실. 사람에 대한 사실은 사용자에게 한 번만 둔다 |
| last_payment_method | str 또는 null | 마지막에 쓴 결제수단 |
```

**출력 모델** 끝에 `조건부 혜택 ConditionalBenefit과 경고 코드 needs_input은 작업 001 설계 3.3절에서 정했고 이름은 작업 002에서 확정한다.`를 더한다.

- [ ] **3단계: 6.4절부터 6.10절을 맞춘다**

- 6.4절의 업종 표를 지우고 `업종은 catalog/categories.yaml의 2단 트리다. 자식 코드는 transit.subway처럼 쓰고 부모 코드는 자식 전부를 뜻한다. 목록과 카카오 업종 코드 대응은 그 파일이 기준이다. 해외는 업종이 아니라 결제의 지역이다.`로 바꾼다. 별칭표 문단 끝에 `가맹점에는 기본 청구 방식을 둔다. 통신사는 자동납부, 구독 서비스는 정기결제다.`를 더한다.
- 6.5절 첫 줄 앞에 `이 절의 계산 규칙은 1판 필드 이름으로 썼다. 2판 틀에 맞춘 계산 규칙은 작업 002에서 이 절을 다시 쓴다. 그때까지 필드 이름이 다르면 작업 001 설계가 우선한다.`를 더한다.
- 6.6절 본문을 지우고 다음으로 바꾼다. 카드 한 장이 파일 하나이고 카드사 공통 규칙은 카드사 파일에 있다는 것. 예시는 작업 001 설계 2.14절의 Mr.Life 주말 할인을 그대로 옮긴다. 검증 규칙은 작업 001 설계 4.2절을 가리킨다. 명령은 `check`와 `format`이다. 이 파일 형식이 하위 프로젝트 3 파이프라인의 출력 형식이 된다는 마지막 문장은 둔다.
- 6.7절 목록을 실제 20장으로 바꾼다. 롯데 LOCA CLASSIC, 하나 원더카드 2.0 DAILY, 우리 카드의정석2 EVERY POINT와 카드의정석 K-LIFE CHECK, NH 히어로즈 체크카드로 바꾼 것과 이유를 한 줄씩 적는다.
- 6.9절 끝에 `카탈로그 검증기 테스트는 backend/tests/catalog/에 있다. 실제 카탈로그로 작업 001 성공 기준을 확인하는 테스트도 있다.`를 더한다.
- 6.10절에서 `주말·시간대 조건`을 지운다. 2판에서 조건으로 담는다.

- [ ] **4단계: ERD를 바꾼다**

`docs/erd.md`와 `docs/erd.html`의 mermaid 블록을 같게 고친다. 두 파일의 블록은 같은 글이다.

카탈로그 영역에서 `spend_tiers`, `spend_rules`, `spend_rule_excluded_categories`, `benefits`, `benefit_targets`를 지우고 `cards`를 다음으로 바꾼 뒤 새 테이블을 더한다.

```
    cards {
        text id PK "issuer-slug"
        text issuer_code FK
        text name
        text[] search_names
        text kind "credit | check"
        text[] product_codes "카드사 내부 상품 코드"
        text status "on_sale | discontinued | closed"
        date status_since
        jsonb annual_fees
        jsonb sources "원문, 본문 지문, 심의필"
        date checked_at
    }
    card_revisions {
        bigint id PK
        text card_id FK
        date effective_from "card_id와 함께 고유"
        bool effective_from_estimated
        jsonb rules "합친 뒤의 개정 전체"
        text rules_sha256
        int schema_version
        timestamptz published_at
    }
    payment_methods {
        text key PK
        text name
        text[] statement_names
    }
    point_programs {
        text key PK
        text name
        numeric won_per_point
    }
    reference_values {
        text key PK
        numeric value
        text unit
        date as_of
        text source
    }
```

`categories`에 `text parent_code FK "자식 업종이면 부모"`, `merchants`에 `text billing "기본 청구 방식"`을 더한다.

사용자 영역을 고친다.

```
    user_card_options {
        bigint id PK
        uuid user_card_id FK
        text option_key
        text choice_key
        date effective_from
    }
    user_facts {
        uuid user_id PK,FK
        text key PK
        text value
    }
    user_card_facts {
        uuid user_card_id PK,FK
        text key PK
        text value
    }
    transaction_benefits {
        uuid transaction_id PK,FK
        text benefit_key PK
        int amount
        int base_amount "혜택 계산에 넣은 결제액"
    }
```

- `user_cards`에 `date started_on`, `text last_payment_method FK`를 더한다.
- `transactions`에서 `applied_benefit_id`와 `estimated_benefit`을 지우고 `text region`, `text payment_method FK`, `text billing`, `bigint card_revision_id FK`를 더한다.
- `recommendation_requests`에 `text region`, `text payment_method`를 더한다.
- `recommendation_results`에서 `applied_benefit_id`를 지우고 `jsonb applied`, `jsonb conditional`을 더한다.

관계 줄을 바꾼다. 지운 테이블의 줄을 지우고 다음을 더한다.

```
    cards ||--|{ card_revisions : "개정"
    card_revisions ||--o{ transactions : "계산에 쓴 개정"
    categories o|--o{ categories : "부모 업종"
    payment_methods o|--o{ transactions : "결제수단"
    user_cards ||--o{ user_card_options : "옵션 선택"
    users ||--o{ user_facts : "사람 사실"
    user_cards ||--o{ user_card_facts : "카드 사실"
    transactions ||--o{ transaction_benefits : "받은 혜택"
```

`benefits o|--o{ transactions : "적용 혜택"` 줄은 지운다. 첫 문단의 `테이블 19개`를 `테이블 22개`로, 카탈로그 영역 설명의 `cards부터 merchant_aliases까지`를 `cards부터 reference_values까지`로 바꾼다.

설계 메모의 첫 두 항목을 다음으로 바꾼다.

```markdown
- 카탈로그는 카드마다 개정 행을 쌓는다. 파이프라인이 카드사 기본값과 패치를 합친 개정 전체를 `card_revisions.rules`에 넣는다. 옛 개정은 지우지 않는다. 지난달 실적은 지난달 규칙으로 계산하기 때문이다.
- 결제는 계산에 쓴 개정을 `card_revision_id`로, 받은 혜택을 `transaction_benefits`의 혜택 key로 가리킨다. 혜택 key는 갱신해도 바꾸지 않는다. 한도 사용량은 기간 안의 `transaction_benefits`를 모아 계산한다.
```

`월 한도 소진량은 (user_card_id, applied_benefit_id, paid_at)으로 집계한다` 항목을 `transaction_benefits는 (transaction_id)로 읽고 결제의 (user_card_id, paid_at) 인덱스와 함께 쓴다`로 바꾼다.

- [ ] **5단계: 시나리오를 맞춘다**

- E6의 처리를 `spend.basis가 prev_calendar_month가 아닌 카드는 실적 계산을 하지 않고 홈에 실적 계산 미지원 배지와 공식 안내 링크를 보여 준다. 결제일 기준 실적은 이용기간 표가 모델에 들어간 뒤에 계산한다.`로, 새로 정한 것을 `결정. spend.basis`로 바꾼다.
- E9의 처리를 `결제의 region이 overseas. 해외 혜택과 해외 실적 제외는 카드 규칙의 지역 조건을 따른다.`로 바꾼다.
- E12의 처리를 `조건은 when으로 계산한다. 결제 입력으로 판단할 수 없는 조건만 unmodeled에 문장으로 남기고, 그 혜택은 조건이 없는 것처럼 계산하되 확인 필요를 붙인다.`로, 새로 정한 것을 `결정. 작업 001 설계 2.4, 2.13`으로 바꾼다.
- 4절 스키마 변경 목록 끝에 `카탈로그 2판으로 카탈로그 영역을 card_revisions 중심으로 바꿨다. 작업 001 설계 3.4`를 더한다.

- [ ] **6단계: README를 맞춘다**

- 문서 표의 ERD 줄을 `Postgres 테이블 22개`로 바꾼다.
- 현재 상태를 `하위 프로젝트 1을 진행하고 있습니다. 카탈로그 2판 검증기와 카드 20장을 만들었고, 다음은 실적과 추천 계산 엔진입니다.`로 바꾼다.
- 진행 순서 표의 1단계 상태를 `진행 중`으로 바꾼다.

- [ ] **7단계: 모순이 없는지 확인한다**

```bash
grep -n "integrated_cap\|min_tier_index\|conditions_not_modeled\|spend_basis\|applied_benefit_id\|estimated_benefit" docs/2026-09-19-cherryconsume-design.md docs/erd.md docs/erd.html docs/scenarios.md README.md
```

기대: 6.5절의 1판 계산 규칙과 시나리오 4절의 1판 변경 기록에만 나온다. 다른 곳에 나오면 2판 이름으로 고친다.

- [ ] **8단계: 커밋 지점**

```bash
git add docs/2026-09-19-cherryconsume-design.md docs/erd.md docs/erd.html docs/scenarios.md README.md
git commit -m "docs: 카탈로그 2판 결론을 설계 문서와 ERD에 반영" -m "작업 001. 저장소 구조, 데이터 모델, 업종 트리, 카탈로그 파일, ERD 22개 테이블, 시나리오 E6, E9, E12"
```

---

## 과제 18: 작업 마무리

- [ ] **1단계: 진행 상황을 고친다**

`.claude/progress.md`의 지금 위치를 작업 002 계산 엔진 준비로 바꾸고, 작업 001을 끝난 것으로 옮긴다.

- [ ] **2단계: 작업 기록을 쓴다**

`docs/history/`에 작업 기록을 쓰고 목록에 한 줄 더한다. 형식은 `docs/history/README.md`를 따른다. 구현 계획을 세운 요청부터 이 과제까지 사용자 요청을 원문 그대로 인용한다.

- [ ] **3단계: 전체를 확인한다**

```bash
uv run --project backend pytest -q
uv run --project backend python -m cherry_core.catalog check | grep -E "^오류"
git status --short
```

기대: `75 passed`, `오류 0`, 남은 변경은 1단계와 2단계 파일뿐.

- [ ] **4단계: 커밋 지점**

```bash
git add .claude/progress.md
git commit -m "chore: 작업 001을 끝난 것으로 진행 상황 갱신"
git add docs/history
git commit -m "docs: 작업 기록 카탈로그 2판 구현 추가"
```

---

## 성공 기준 확인

2026-09-29 과제 15에서 채웠다.

| 성공 기준 | 근거 | 결과 |
|---|---|---|
| 20장이 2판 검증을 통과한다 | `test_twenty_cards_pass_check` | 통과. NH는 zgm 할인카드 대신 히어로즈 체크카드다 |
| 구조로 담을 수 있는데 문장으로만 남긴 조건이 없다 | judgment.md "결과"의 "문장으로 남김" 목록. 과제 13 대조 에이전트가 구조로 담을 수 있는 것을 찾아 옮겼다 | 사용자 검토 |
| 구간별 복제 혜택이 남지 않는다 | `test_no_benefit_is_copied_per_tier` | 통과 |
| 같은 원문으로 두 번 갱신해도 차이가 없다 | `test_every_file_is_canonical`과 과제 3의 `format` 두 번 테스트. 갱신기는 하위 프로젝트 3에서 만든다 | 통과 |
| 카드사 공통 규칙 하나를 바꾸면 그 카드사 카드 전부에 반영된다 | `test_issuer_default_change_reaches_every_card` | 통과 |
| 시행일 전날과 당일이 다른 개정으로 해석된다 | `test_npay_change_splits_on_2027_01_01` | 통과 |
| IBK 확인 필요 네 가지 | 과제 14 | 편의점 1일 2회는 확인. 나머지 셋은 확인 필요로 명시 |
| 첫 개정 시행일 | judgment.md "결과"의 카드별 첫 개정 날짜 | 20장 모두 확정. 추정으로 남은 카드가 없다 |
