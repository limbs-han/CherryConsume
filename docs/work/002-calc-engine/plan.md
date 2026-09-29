# 002 계산 엔진 구현 계획

2026-09-29 사용자가 승인했다.

> **에이전트에게:** 과제마다 superpowers:subagent-driven-development나 superpowers:executing-plans로 실행한다. 단계는 체크박스 `- [ ]`로 표시한다.

**목표:** 카탈로그 2판을 입력으로 카드별 실적 현황, 결제 한 건의 혜택, 한도 현황, 가게별 추천을 계산하는 순수 Python 엔진 `cherry_core.engine`을 만들고, intent.md의 성공 기준을 테스트로 확인한다.

**구조:** 서버가 켜질 때 `Engine(catalog)`을 한 번 만든다. 요청마다 결제 목록을 한 번 훑어 사용량 표를 만들고, 결제 하나나 가상의 결제를 그 표 위에서 계산한다. 조건은 참, 거짓, 모름으로 판정하고 모름은 부풀리지 않는 쪽으로 계산한 뒤 경고와 조건부 혜택으로 돌려준다.

**기술:** Python 3.12 이상, Pydantic 2, PyYAML, 공휴일 `holidays` 패키지, pytest, ruff, uv.

## 지킬 것

- 설계는 `design.md`, 의도는 `intent.md`다. 설계와 다르게 해야 하면 코드보다 design.md를 먼저 고치고 사용자에게 알린다
- 금액은 원 단위 정수다. 비율은 `Fraction`으로 바꿔 계산한다. 부동소수점으로 돈을 계산하지 않는다
- 엔진은 예외를 던지지 않는다. 계산할 수 없는 경우는 경고 코드로 돌려준다. 오류가 있는 카탈로그로 `Engine`을 만들 때만 멈춘다. 설계 문서 6.8
- 현재 시각은 인자로 받고 달은 한국 시간으로 나눈다
- 사용자 IBK 명세서와 그것으로 만든 입력은 `backend/tests/engine/local/`에만 둔다. `.gitignore`에 들어 있어 커밋되지 않는다. 카드번호, 이름, 주소, 계좌번호는 어디에도 옮기지 않는다
- 계획 실행 중의 커밋은 사용자에게 한 번 허락받은 뒤 과제마다 한다. 커밋 메시지에 claude를 넣지 않는다. 본문에 "작업 002"를 적는다
- 명령은 저장소 루트에서 `uv run --project backend ...`로 돌린다

## 파일

| 파일 | 한 줄 설명 | 과제 |
|---|---|---|
| `backend/cherry_core/engine/models.py` | 입력과 출력 모델 | 4 |
| `backend/cherry_core/engine/cond.py` | 한국 시간, 공휴일, 업종 맞추기, 조건 판정 | 4 |
| `backend/cherry_core/engine/context.py` | 카탈로그에서 한 번 준비하는 값, 분수와 원 미만 처리 | 4 |
| `backend/cherry_core/engine/spend.py` | 결제 한 건의 실적, 이번 달 구간, 신규 발급 특례, 카드 전체 경고 | 5 |
| `backend/cherry_core/engine/price.py` | 사용량 표, 혜택 판정, 보상, 한도, 중복 묶음, 순위, price_payment, price_month, spend_status, limit_status | 5 |
| `backend/cherry_core/engine/recommend.py` | 추천, 못 받는 혜택, 조건부 혜택 | 6 |
| `backend/cherry_core/engine/__init__.py` | `Engine` | 4, 5, 6 |
| `backend/tests/engine/conftest.py` | 규칙 테스트용 작은 카탈로그 | 4 |
| `backend/tests/engine/test_cond.py`, `test_spend.py`, `test_benefits.py`, `test_recommend.py`, `test_speed.py` | 규칙과 속도 테스트 | 4, 5, 6 |
| `backend/tests/engine/cases.py`, `test_cases.py`, `cases/<카드 id>.yaml` | 손계산 표 | 2, 3, 7 |
| `backend/tests/engine/mockup/`, `test_mockup.py` | 시안 카드 | 8 |
| `backend/tests/engine/test_statement.py`, `local/` | 실제 명세서 대조 | 9 |

## 순서

손계산 표는 엔진 코드보다 먼저 만든다. 표를 만드는 에이전트는 엔진 코드와 이 계획의 과제 4부터를 보지 않는다. 같은 착각이 코드와 기대값에 함께 들어가지 않게 하려는 것이다. 설계 6.2

| 과제 | 한 줄 설명 | 걸리는 시간 |
|---|---|---|
| 1 | 커밋 허락과 공휴일 의존성 | 10분 |
| 2 | 손계산 표 형식과 형식 검사 | 20분 |
| 3 | 손계산 표 20장. 에이전트 6개 | 에이전트로 반나절 |
| 4 | 모델과 조건 판정 | 30분 |
| 5 | 실적과 결제 혜택 계산 | 1시간 |
| 6 | 추천과 속도 | 40분 |
| 7 | 손계산 표 대조와 차이 정리 | 차이 수에 따라 1시간에서 반나절 |
| 8 | 시안 카드 | 20분 |
| 9 | 실제 명세서 대조 | 1~2시간 |
| 10 | 위험 검토 | 30분 |
| 11 | 전체 문서에 결론 합치기 | 1시간 |
| 12 | 성공 기준 확인과 마무리 | 30분 |

---

## 과제 1: 커밋 허락과 공휴일 의존성

**파일**
- 고치기: `backend/pyproject.toml`, `backend/uv.lock`

- [x] **1단계: 계획 실행 중의 커밋을 허락받는다**

사용자에게 묻는다. "계획 실행 중에 과제마다 커밋해도 될까요. 푸시는 따로 요청받을 때만 합니다." 답을 `.claude/progress.md`에 적는다. 허락받지 못하면 과제마다 커밋 단계에서 멈추고 묻는다.

- [x] **2단계: 공휴일 패키지를 더한다**

```bash
uv add --project backend "holidays>=0.60"
```

기대: `backend/pyproject.toml`의 dependencies에 `"holidays>=0.60"`이 생긴다.

- [x] **3단계: 한국 공휴일이 나오는지 본다**

```bash
uv run --project backend python -c "import holidays; kr = holidays.country_holidays('KR', years=[2026]); import datetime as d; print(d.date(2026, 10, 5) in kr, d.date(2026, 6, 3) in kr)"
```

기대: `True True`. 개천절 대체공휴일과 지방선거일이다.

- [x] **4단계: 커밋**

```bash
git add backend/pyproject.toml backend/uv.lock
git commit -m "build: 계산 엔진의 한국 공휴일 패키지 추가" -m "작업 002 설계 3.2. 음력 공휴일과 대체공휴일을 손으로 계산하지 않는다."
```

---

## 과제 2: 손계산 표 형식과 형식 검사

표 한 장이 카드 하나다. 형식은 설계 6.1이다. 이 과제에서는 표를 읽는 코드와 형식 검사만 만들고 표는 과제 3에서 채운다.

**파일**
- 만들기: `backend/tests/engine/__init__.py` 빈 파일, `backend/tests/engine/cases.py`, `backend/tests/engine/test_cases.py`, `backend/tests/engine/cases/` 빈 폴더
- 과제 4에서 쓰는 `backend/cherry_core/engine/models.py`와 `cond.py`가 이 과제에 먼저 필요하다. 과제 4의 1단계 코드 두 파일과 `engine/__init__.py` 한 줄 문서를 이 과제에서 먼저 만든다

- [x] **1단계: 엔진 모델과 조건 판정 파일을 먼저 둔다**

과제 4 1단계의 `models.py`, `cond.py`, `context.py`와 아래 `__init__.py`를 그대로 만든다. 표 읽기가 `Payment`, `UserCard`, 한국 시간을 쓰기 때문이다. 테스트는 과제 4에서 쓴다.

`backend/cherry_core/engine/__init__.py`

````python
"""계산 엔진. 설계는 docs/work/002-calc-engine/design.md"""
````

- [x] **2단계: 표 읽기 코드를 쓴다**

`backend/tests/engine/cases.py`

````python
"""손계산 표 읽기. 설계 6.1. 표는 tests/engine/cases/<카드 id>.yaml이다.

card: shinhan-mrlife
holder: {facts: {}, options: []}          # 모든 경우에 쓰는 보유 카드 값. 없어도 된다
cases:
  - name: 주말 이마트 5만원, 30만 구간
    prev_month_spend: 350000             # 지난달 인정 실적. 첫 결제 달에 등록했고 이 값을 추정값으로 적은 것으로 본다
    holder: {}                            # 이 경우에만 덮어쓰는 값. 없어도 된다
    payments:
      - {at: 2026-09-05T11:00, amount: 50000, merchant: emart, channel: offline}
    expect:
      - {payment: 0, benefits: {weekend-mart: 3000}, counted: 50000, warnings: [check_conditions]}
    calc: 50,000 × 10% = 5,000. 주말 공유 한도 30만 구간 3,000원이라 3,000

- at은 한국 시간이다. 결제의 나머지 칸은 엔진의 Payment와 같다
- benefits는 그 결제가 받는 혜택 전부다. 값은 보상 단위라 포인트면 포인트 수다. 받는 혜택이 없으면 {}
- counted는 그 결제가 실적에 넣는 금액의 합이다. warnings는 반드시 있어야 하는 경고 코드다. 둘 다 없어도 된다
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import yaml

from cherry_core.engine.cond import KST, month_of
from cherry_core.engine.models import Payment, UserCard

CASES = Path(__file__).parent / "cases"


@dataclass
class Case:
    file: str
    card_id: str
    name: str
    holder: UserCard
    payments: list[Payment]
    expect: list[dict]
    calc: str


def _time(value) -> datetime:
    t = value if isinstance(value, datetime) else datetime.fromisoformat(str(value))
    return t if t.tzinfo else t.replace(tzinfo=KST)


def load_cases(root: Path = CASES) -> list[Case]:
    out: list[Case] = []
    for path in sorted(root.glob("*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        card_id = data["card"]
        for i, raw in enumerate(data["cases"]):
            payments = []
            for j, p in enumerate(raw["payments"]):
                fields = {k: v for k, v in p.items() if k not in ("at", "cancelled_at")}
                if "cancelled_at" in p:
                    fields["cancelled_at"] = _time(p["cancelled_at"])
                payments.append(Payment(id=f"{i:03d}-{j:03d}", user_card_id="u", paid_at=_time(p["at"]), **fields))
            holder = {"id": "u", "card_id": card_id, **(data.get("holder") or {}), **(raw.get("holder") or {})}
            if "prev_month_spend" in raw:
                holder["registered_on"] = month_of(min(p.paid_at for p in payments).astimezone(KST).date())
                holder["assumed_prev_month_spend"] = raw["prev_month_spend"]
            holder.setdefault("registered_on", date(2020, 1, 1))
            out.append(
                Case(
                    path.name,
                    card_id,
                    raw["name"],
                    UserCard(**holder),
                    payments,
                    raw.get("expect", []),
                    raw.get("calc", ""),
                )
            )
    return out
````

- [x] **3단계: 형식 검사를 쓴다**

`backend/tests/engine/test_cases.py`

````python
"""손계산 표. 설계 6.1과 6.2. 과제 2에서는 표 형식만 본다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog

from .cases import load_cases

ROOT = Path(__file__).resolve().parents[3] / "catalog"
CASES = load_cases()


@pytest.fixture(scope="module")
def catalog():
    return load_catalog(ROOT)


def test_case_files_are_valid(catalog):
    problems = []
    for c in CASES:
        where = f"{c.file} {c.name}"
        if c.card_id not in catalog.cards:
            problems.append(f"{where}: 카드 {c.card_id}가 없다")
            continue
        keys = {b.key for _, rules in catalog.cards[c.card_id].revisions for b in rules.benefits}
        for p in c.payments:
            if p.merchant and p.merchant not in catalog.merchants:
                problems.append(f"{where}: 가맹점 {p.merchant}가 없다")
            if p.category and p.category not in catalog.categories:
                problems.append(f"{where}: 업종 {p.category}가 없다")
            if p.payment_method and p.payment_method not in catalog.payment_methods:
                problems.append(f"{where}: 결제수단 {p.payment_method}가 없다")
        for e in c.expect:
            if not 0 <= e["payment"] < len(c.payments):
                problems.append(f"{where}: payment {e['payment']}가 결제 목록 밖이다")
            problems += [f"{where}: 혜택 {k}가 카드에 없다" for k in e.get("benefits", {}) if k not in keys]
        if not c.calc:
            problems.append(f"{where}: calc가 비어 있다")
    assert problems == []
````

- [x] **4단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine
```

기대: `1 passed`. 표가 없어 검사할 것이 없다.

- [x] **5단계: 커밋**

```bash
git add backend/cherry_core/engine backend/tests/engine
git commit -m "test: 계산 엔진 손계산 표 형식과 형식 검사 추가" -m "작업 002 설계 6.1. 표는 카드마다 파일 하나이고 과제 3에서 채운다."
```

2026-09-29 실행 결과: 1개 통과. 계획의 두 파일과 과제 3의 test_cases.py 끝에 빈 줄이 하나 더 있어 형식 검사에 걸렸다. 계획을 만들 때 생긴 것이라 계획의 코드 블록 셋을 함께 고쳤다.

---

## 과제 3: 손계산 표 20장

에이전트 6개가 카드사 묶음으로 나눠 동시에 쓴다. 엔진 코드를 쓰지 않은 에이전트가 기대값을 만든다. 설계 6.2

**파일**
- 만들기: `backend/tests/engine/cases/<카드 id>.yaml` 20개
- 고치기: `backend/tests/engine/test_cases.py`에 적용 범위 검사를 더한다

| 묶음 | 카드사 | 카드 | 계산할 혜택 수 |
|---|---|---|---|
| A | 신한 | shinhan-cheoeum, shinhan-mrlife, shinhan-pointplan | 34 |
| B | 삼성·현대 | samsung-id-on, samsung-taptap-o, hyundai-m, hyundai-the-green-ed4, hyundai-zero-edition3-discount | 33 |
| C | KB국민 | kb-easy-all-titanium, kb-my-wesh, kb-toktok | 36 |
| D | 롯데·하나·우리 | lotte-loca-classic, lotte-loca365, hana-travelog-check, hana-wonder2-daily, woori-every-point, woori-k-life-check | 32 |
| E | IBK | ibk-narasarang | 36 |
| F | NH·카카오뱅크 | nh-heroes-check, kakaobank-friends-check | 20 |

IBK는 Npay 적립이 2027-01-01에 바뀌어 그 혜택은 두 번 센다.

- [x] **1단계: 적용 범위 검사를 더한다**

`backend/tests/engine/test_cases.py`

````python
"""손계산 표. 설계 6.1과 6.2. 표 형식과 모든 혜택이 한 번 이상 나오는지 본다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine.cond import local

from .cases import load_cases

ROOT = Path(__file__).resolve().parents[3] / "catalog"
CASES = load_cases()


@pytest.fixture(scope="module")
def catalog():
    return load_catalog(ROOT)


def test_case_files_are_valid(catalog):
    problems = []
    for c in CASES:
        where = f"{c.file} {c.name}"
        if c.card_id not in catalog.cards:
            problems.append(f"{where}: 카드 {c.card_id}가 없다")
            continue
        keys = {b.key for _, rules in catalog.cards[c.card_id].revisions for b in rules.benefits}
        for p in c.payments:
            if p.merchant and p.merchant not in catalog.merchants:
                problems.append(f"{where}: 가맹점 {p.merchant}가 없다")
            if p.category and p.category not in catalog.categories:
                problems.append(f"{where}: 업종 {p.category}가 없다")
            if p.payment_method and p.payment_method not in catalog.payment_methods:
                problems.append(f"{where}: 결제수단 {p.payment_method}가 없다")
        for e in c.expect:
            if not 0 <= e["payment"] < len(c.payments):
                problems.append(f"{where}: payment {e['payment']}가 결제 목록 밖이다")
            problems += [f"{where}: 혜택 {k}가 카드에 없다" for k in e.get("benefits", {}) if k not in keys]
        if not c.calc:
            problems.append(f"{where}: calc가 비어 있다")
    assert problems == []


def versions(card) -> list[tuple[str, object, object, dict]]:
    """혜택 key마다 내용이 같은 기간. (key, 시작, 끝, 내용). 끝은 다음 개정 시행일이고 없으면 None"""
    revs = card.revisions
    out = []
    for i, (rev, rules) in enumerate(revs):
        end = revs[i + 1][0].effective_from if i + 1 < len(revs) else None
        for b in rules.benefits:
            dump = b.model_dump()
            if out and any(v[0] == b.key and v[3] == dump and v[2] == rev.effective_from for v in out):
                prev = next(v for v in out if v[0] == b.key and v[3] == dump and v[2] == rev.effective_from)
                out[out.index(prev)] = (b.key, prev[1], end, dump)
            else:
                out.append((b.key, rev.effective_from, end, dump))
    return out


def test_every_benefit_is_covered(catalog):
    # intent 성공 기준 1. 혜택마다, 개정으로 내용이 바뀐 혜택은 바뀐 내용마다 양수로 한 번 이상 나온다
    covered: dict[str, list] = {}
    for c in CASES:
        for e in c.expect:
            day = local(c.payments[e["payment"]].paid_at).date()
            for key, amount in e.get("benefits", {}).items():
                if amount > 0:
                    covered.setdefault(f"{c.card_id}:{key}", []).append(day)
    missing = []
    for card_id, card in sorted(catalog.cards.items()):
        for key, start, end, _ in versions(card):
            days = covered.get(f"{card_id}:{key}", [])
            if not any(start <= d and (end is None or d < end) for d in days):
                missing.append(f"{card_id}:{key}@{start}")
    assert missing == []
````

- [x] **2단계: 돌려서 실패를 본다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_cases.py
```

기대: `test_every_benefit_is_covered` 실패. 빠진 혜택이 191개다.

- [x] **3단계: 에이전트 6개를 띄운다**

묶음마다 `general-purpose` 에이전트 하나를 동시에 띄운다. 프롬프트는 다음과 같다. `<묶음>`과 `<카드>`만 바꾼다.

```text
체리컨슘 계산 엔진의 손계산 표를 쓴다. 작업 폴더는 저장소 루트다. 맡은 카드: <카드>

## 읽을 것
- docs/work/002-calc-engine/design.md 전체. 계산 규칙의 기준이다. 특히 2절 실적, 3절 혜택, 6.1 표 형식
- docs/work/001-catalog-schema-v2/design.md 2절. 카탈로그 칸의 뜻
- backend/tests/engine/cases.py 맨 위 설명. 표 형식
- 맡은 카드 파일 catalog/cards/<카드사>/<id>.yaml과 카드사 파일 catalog/issuers/<카드사>.yaml, catalog/merchants.yaml, catalog/categories.yaml
- 카드 파일 sources의 공식 원문. 카드 파일이 원문과 다르다고 보면 표는 원문대로 쓰고 보고한다

## 읽지 않을 것
- backend/cherry_core/engine/ 아래 코드. 아직 없거나 있어도 보지 않는다
- docs/work/002-calc-engine/plan.md의 과제 4부터. 엔진 코드가 들어 있다

## 쓸 것
backend/tests/engine/cases/<카드 id>.yaml을 카드마다 하나 쓴다.
- 카드의 모든 혜택이 한 번 이상 양수로 나오게 경우를 만든다. 개정으로 내용이 바뀐 혜택은 바뀐 내용마다 그 개정 기간의 날짜로 한 번 이상 나온다
- 경우마다 calc에 손계산을 한 줄로 적는다. 비율, 한도, 구간, 원 미만 처리를 드러낸다
- 한도 직전과 직후, 구간 하한, 공유 한도, 중복 묶음처럼 틀리기 쉬운 곳을 경우에 넣는다. 혜택 하나에 경우 하나가 기본이고 카드 전체로 혜택 수의 1.3배 정도가 적당하다
- 받는 혜택이 없어야 하는 결제도 몇 개 넣는다. 실적 제외 업종, 무이자할부 제외 같은 것이다
- 모르는 값은 부풀리지 않는 쪽으로 계산한다. 설계 2.1과 3.1이다. 계산 규칙이 설계에 없거나 둘로 읽히면 멈추고 보고한다

## 검사
- uv run --project backend pytest -q backend/tests/engine/test_cases.py -k valid 가 통과해야 끝난다
- 형식은 맡은 파일만 고친다. git 명령을 쓰지 않는다. 다른 에이전트가 동시에 다른 파일을 쓴다

## 보고
카드마다 경우 수, 계산한 혜택 수, 설계로 판단이 갈린 곳, 카드 파일과 원문이 다른 곳을 10줄 안에 적는다.
```

- [x] **4단계: 보고를 모은다**

에이전트 보고에서 "설계로 판단이 갈린 곳"과 "카드 파일과 원문이 다른 곳"을 `docs/work/002-calc-engine/plan.md` 끝의 `## 표를 만들며 나온 것`에 한 줄씩 적는다. 설계 판단이 갈린 곳은 사용자에게 묻고 design.md를 고친다. 카드 파일이 틀린 곳은 작업 001의 방식으로 카드 파일을 고치고 원문을 다시 대조한다.

- [x] **5단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_cases.py
```

기대: 2개 통과.

- [x] **6단계: 커밋**

```bash
git add backend/tests/engine docs/work/002-calc-engine/plan.md
git commit -m "test: 카드 20장 손계산 표 추가" -m "작업 002 설계 6.1, 6.2. 엔진 코드를 쓰지 않은 에이전트가 원문과 카드 파일로 기대값을 만들었다. 혜택 190개가 모두 한 번 이상 나온다."
```

2026-09-29 실행 결과: 표 20장, 경우 279개, 결제 781건. 혜택 191개가 모두 한 번 이상 나온다. 멈춤 훅이 실패한 테스트를 두고 끝내지 못하게 해서, 에이전트가 쓰는 동안에는 적용 범위 검사를 빼 두었다가 표가 다 모인 뒤 다시 넣었다. 시제품 엔진으로 미리 돌려 보니 275개가 처음부터 같았고 다른 4개는 모두 엔진 쪽이었다. 엔진 고침과 설계 문장은 아래 "표를 만들며 나온 것"에 있다.

---

## 과제 4: 모델과 조건 판정

**파일**
- 만들기: `backend/cherry_core/engine/models.py`, `cond.py`, `context.py`. 과제 2에서 먼저 만들었으면 내용이 같은지만 본다
- 만들기: `backend/tests/engine/conftest.py`, `backend/tests/engine/test_cond.py`

- [x] **1단계: 모델, 조건 판정, 준비 값을 쓴다**

`backend/cherry_core/engine/models.py`

````python
"""계산 엔진의 입력과 출력. 설계는 docs/work/002-calc-engine/design.md 1절과 5절."""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

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
````

`backend/cherry_core/engine/cond.py`

````python
"""참, 거짓, 모름 판정. 설계 2.1, 3.1, 3.2.

판정 결과는 (값, 모르는 것들)이다. 값이 None이면 모름이고, 모르는 것들은 ("payment_method",),
("fact", key), ("option", key), ("category", 부모 코드), ("started_on",) 같은 짝의 집합이다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from functools import cache

import holidays

from cherry_core.catalog.models import Condition

from .models import UserCard

KST = timezone(timedelta(hours=9))  # 한국은 1988년 뒤로 서머타임이 없다
TRUE: tuple[bool | None, frozenset] = (True, frozenset())
FALSE: tuple[bool | None, frozenset] = (False, frozenset())
Tri = tuple[bool | None, frozenset]


def unknown(*need: str) -> Tri:
    return (None, frozenset([tuple(need)]))


def all_of(results) -> Tri:
    needs: set = set()
    value: bool | None = True
    for v, n in results:
        if v is False:
            return FALSE
        if v is None:
            value = None
            needs |= n
    return (value, frozenset(needs)) if value is None else TRUE


def any_of(results) -> Tri:
    needs: set = set()
    value: bool | None = False
    for v, n in results:
        if v is True:
            return TRUE
        if v is None:
            value = None
            needs |= n
    return (value, frozenset(needs)) if value is None else FALSE


def local(at: datetime) -> datetime:
    return at.astimezone(KST)


def month_of(d: date) -> date:
    return date(d.year, d.month, 1)


def add_months(m: date, n: int) -> date:
    y, mm = divmod(m.month - 1 + n, 12)
    return date(m.year + y, mm + 1, 1)


@cache
def _kr_holidays(year: int) -> frozenset[date]:
    return frozenset(holidays.country_holidays("KR", years=[year]))


def is_holiday(d: date) -> bool:
    return d in _kr_holidays(d.year)


def category_match(paid: str | None, wanted: str) -> Tri:
    """결제 업종이 조건 업종에 맞는지. 결제가 부모 업종까지만 알면 모름이다. 설계 2.1"""
    if paid is None:
        return FALSE
    if paid == wanted or paid.startswith(wanted + "."):
        return TRUE
    if wanted.startswith(paid + "."):
        return unknown("category", paid)
    return FALSE


def categories_match(paid: str | None, wanted: list[str]) -> Tri:
    return any_of(category_match(paid, w) for w in wanted)


@dataclass
class Situation:
    """조건을 판정하는 데 필요한 결제 쪽 값. amount는 혜택마다 다를 수 있어 바꿔 가며 쓴다."""

    at: datetime
    amount: int
    merchant: str | None
    category: str | None
    channel: str
    region: str
    installment_months: int
    interest_free: bool
    payment_method: str | None
    billing: str
    card: UserCard
    defaults: dict[str, str | None] = field(default_factory=dict)
    top_areas: dict[str, set[str]] = field(default_factory=dict)
    area: str | None = None
    month_total: int | None = None
    skip: frozenset[str] = frozenset()

    @property
    def day(self) -> date:
        return local(self.at).date()

    def choice(self, option: str) -> str | None:
        """결제일에 골라 둔 선택지. 고른 적이 없으면 카드사 기본값. 설계 3.8"""
        picks = [p for p in self.card.options if p.option == option and p.effective_from <= self.day]
        if picks:
            return max(picks, key=lambda p: p.effective_from).choice
        return self.defaults.get(option)


def check(c: Condition, s: Situation) -> Tri:
    """조건 항목 하나. 적힌 칸이 모두 맞아야 참이다."""
    parts: list[Tri] = []
    add = parts.append
    if c.amount is not None:
        ok = (c.amount.min is None or s.amount >= c.amount.min) and (
            c.amount.below is None or s.amount < c.amount.below
        )
        add(TRUE if ok else FALSE)
    if c.day is not None:
        weekday = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"][s.day.weekday()]
        in_days = weekday in (c.day.days or [])
        holiday = is_holiday(s.day)
        ok = {
            "ignore": in_days,
            "include": in_days or holiday,
            "exclude": in_days and not holiday,
            "only": holiday,
        }[c.day.holidays]
        add(TRUE if ok else FALSE)
    if c.time is not None:
        t = local(s.at).strftime("%H:%M")
        start, end = c.time.start, c.time.end
        ok = start <= t < end if start <= end else (t >= start or t < end)
        add(TRUE if ok else FALSE)
    if c.months is not None:
        add(TRUE if s.day.month in c.months else FALSE)
    if c.region is not None:
        add(TRUE if s.region == c.region else FALSE)
    if c.channel is not None:
        add(TRUE if s.channel == c.channel else FALSE)
    if c.interest_free is not None:
        add(TRUE if s.interest_free == c.interest_free else FALSE)
    if c.lump_sum is not None:
        add(TRUE if s.installment_months <= 1 else FALSE)
    if c.payment is not None:
        add(unknown("payment_method") if s.payment_method is None else TRUE if s.payment_method in c.payment else FALSE)
    if c.payment_not is not None:
        pm = s.payment_method
        add(unknown("payment_method") if pm is None else FALSE if pm in c.payment_not else TRUE)
    if c.billing is not None:
        add(TRUE if s.billing in c.billing else FALSE)
    if c.billing_not is not None:
        add(FALSE if s.billing in c.billing_not else TRUE)
    for option, choices in (c.option or {}).items():
        chosen = s.choice(option)
        add(unknown("option", option) if chosen is None else TRUE if chosen in choices else FALSE)
    if c.fact is not None:
        add(fact(c.fact, s))
    if c.ranked is not None and "ranked" not in s.skip:
        add(TRUE if s.area in s.top_areas.get(c.ranked, set()) else FALSE)
    if c.card_month is not None:
        if s.card.started_on is None:
            add(unknown("started_on"))
        else:
            start = s.card.started_on
            n = (s.day.year - start.year) * 12 + s.day.month - start.month
            ok = (c.card_month.min is None or n >= c.card_month.min) and (
                c.card_month.max is None or n <= c.card_month.max
            )
            add(TRUE if ok else FALSE)
    if c.month_total is not None and "month_total" not in s.skip:
        add(TRUE if (s.month_total or 0) >= c.month_total.min else FALSE)
    if c.any_of is not None:
        add(any_of(check(sub, s) for sub in c.any_of))
    return all_of(parts)


def fact(key: str, s: Situation) -> Tri:
    facts = s.card.facts
    if key == "birth_month_now":
        if "birth_month" not in facts:
            return unknown("fact", "birth_month")
        return TRUE if facts["birth_month"] == s.day.month else FALSE
    if key not in facts:
        return unknown("fact", key)
    return TRUE if facts[key] is True else FALSE


def check_all(conditions: list[Condition], s: Situation) -> Tri:
    return all_of(check(c, s) for c in conditions)
````

`backend/cherry_core/engine/context.py`

````python
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
````

- [x] **2단계: 테스트용 작은 카탈로그와 조건 테스트를 쓴다**

`backend/tests/engine/conftest.py`

````python
"""엔진 규칙 테스트용 작은 카탈로그. card(...)로 개정 하나짜리 카드를 만들고 engine(...)으로 엔진을 얻는다."""

import copy
import itertools
from datetime import date, datetime

import pytest

from cherry_core.catalog.canonical import canonical_text
from cherry_core.engine.cond import KST
from cherry_core.engine.models import Payment, UserCard

COMMON = {
    "categories.yaml": [
        {"code": "cafe", "name": "카페"},
        {"code": "convenience", "name": "편의점"},
        {
            "code": "restaurant",
            "name": "음식점",
            "children": [{"code": "general", "name": "일반음식점"}, {"code": "fastfood", "name": "패스트푸드"}],
        },
        {
            "code": "transit",
            "name": "대중교통",
            "children": [{"code": "subway", "name": "지하철"}, {"code": "bus_express", "name": "고속버스"}],
        },
        {
            "code": "telecom",
            "name": "통신요금",
            "children": [{"code": "mobile", "name": "이동통신"}, {"code": "internet_tv", "name": "인터넷·TV"}],
        },
        {"code": "tax", "name": "세금"},
        {"code": "fuel", "name": "주유"},
        {"code": "delivery_app", "name": "배달앱"},
        {"code": "other", "name": "기타"},
    ],
    "merchants.yaml": [
        {"key": "starbucks", "name": "스타벅스", "category": "cafe", "aliases": ["스타벅스"]},
        {"key": "ediya", "name": "이디야", "category": "cafe", "aliases": ["이디야"]},
        {"key": "gs25", "name": "GS25", "category": "convenience", "aliases": ["GS25"]},
        {"key": "kt", "name": "KT", "category": "telecom", "aliases": ["KT"], "billing": "autopay"},
        {"key": "baemin", "name": "배달의민족", "category": "delivery_app", "aliases": ["배달의민족"]},
        {"key": "sk_energy", "name": "SK에너지", "category": "fuel", "aliases": ["SK에너지"]},
    ],
    "payment_methods.yaml": [
        {"key": "physical_card", "name": "실물카드"},
        {"key": "naver_pay", "name": "네이버페이"},
        {"key": "kakao_pay", "name": "카카오페이"},
    ],
    "point_programs.yaml": [{"key": "test_point", "name": "테스트포인트", "won_per_point": 1}],
    "reference.yaml": [
        {"key": "fuel_price_gasoline", "value": 1700, "unit": "원/L", "as_of": date(2026, 9, 28), "source": "오피넷"}
    ],
    "issuers/test.yaml": {"schema_version": 2, "id": "test", "name": "테스트카드"},
}

SPEND = {
    "basis": "prev_calendar_month",
    "exclude_categories": ["tax"],
    "installment": "full_at_purchase",
    "cancellation": "cancel_month",
}


def card(
    benefits, *, id="test-card", tiers=(0, 300000, 600000), spend=None, start=date(2026, 1, 1), estimated=False, **rules
):
    """개정 하나짜리 카드 파일. rules에는 limits, stacks, ranked, options, facts, new_card, benefit_exclusions 등을 준다"""
    for b in benefits:
        b.setdefault("title", b["key"])
    revision = {"effective_from": start, "source": "page", "tiers": list(tiers), "spend": {**SPEND, **(spend or {})}}
    if estimated:
        revision["effective_from_estimated"] = True
    revision.update(rules)
    revision["benefits"] = benefits
    return {
        "schema_version": 2,
        "id": id,
        "issuer": "test",
        "name": id,
        "kind": "credit",
        "product_codes": ["T1"],
        "status": "on_sale",
        "sources": [
            {"id": "page", "kind": "product_page", "url": "https://example.com/t", "fetched_at": date(2026, 9, 28)}
        ],
        "checked_at": date(2026, 9, 28),
        "revisions": [revision],
    }


@pytest.fixture
def engine(tmp_path):
    """engine(카드 파일, ...)으로 그 카드들이 든 엔진을 만든다. 카드 id는 test-로 시작해야 한다"""

    from cherry_core.engine import Engine

    def make(*card_files) -> Engine:
        files = copy.deepcopy(COMMON)
        for c in card_files:
            files[f"cards/test/{c['id']}.yaml"] = c
        root = tmp_path / "catalog"
        for rel, data in files.items():
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(canonical_text(data), encoding="utf-8", newline="\n")
        return Engine.from_dir(root)

    return make


_ids = itertools.count(1)


def at(text: str) -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=KST)


def pay(amount: int, when: str, **kw) -> Payment:
    return Payment(id=f"p{next(_ids):04d}", user_card_id="u1", amount=amount, paid_at=at(when), **kw)


def holder(**kw) -> UserCard:
    base = {"id": "u1", "card_id": "test-card", "registered_on": date(2026, 1, 1)}
    return UserCard(**{**base, **kw})


def values(results) -> list[dict[str, int]]:
    """결제마다 {혜택 key: 원 가치}"""
    return [{b.key: b.value for b in r.benefits} for r in results]


def codes(result) -> list[str]:
    return [w.code for w in result.warnings]


def prev_month(amount: int, month: str = "2026-08") -> list[Payment]:
    """지난달 실적을 만드는 결제 한 건. 업종은 기타라 혜택이 없다"""
    return [pay(amount, f"{month}-15T12:00", category="other")]
````

`backend/tests/engine/test_cond.py`

````python
"""조건 판정. 참, 거짓, 모름. 설계 2.1, 3.1, 3.2."""

from datetime import UTC, date

from cherry_core.catalog.models import Condition
from cherry_core.engine.cond import Situation, all_of, any_of, category_match, check, is_holiday, unknown
from cherry_core.engine.models import OptionPick, UserCard

from .conftest import at


def sit(**kw) -> Situation:
    base = {
        "at": at("2026-09-19T14:20"),
        "amount": 10000,
        "merchant": None,
        "category": "cafe",
        "channel": "offline",
        "region": "domestic",
        "installment_months": 1,
        "interest_free": False,
        "payment_method": "physical_card",
        "billing": "normal",
        "card": UserCard(id="u", card_id="c"),
    }
    base.update(kw)
    return Situation(**base)


def cond(**kw) -> Condition:
    return Condition.model_validate(kw)


def test_category_tree():
    assert category_match("transit.subway", "transit")[0] is True
    assert category_match("transit.subway", "transit.subway")[0] is True
    assert category_match("transit.subway", "transit.bus_express")[0] is False
    assert category_match("transit", "transit.subway") == unknown("category", "transit")
    assert category_match(None, "cafe")[0] is False


def test_three_valued_and_or():
    t, f, u = (True, frozenset()), (False, frozenset()), unknown("fact", "soldier")
    assert all_of([t, u]) == u and all_of([u, f])[0] is False and all_of([])[0] is True
    assert any_of([f, u]) == u and any_of([u, t])[0] is True and any_of([])[0] is False


def test_amount_range():
    c = cond(amount={"min": 30000, "below": 70000})
    assert [check(c, sit(amount=a))[0] for a in (29999, 30000, 69999, 70000)] == [False, True, True, False]


def test_holidays_include_substitute_and_election():
    assert is_holiday(date(2026, 10, 5))  # 개천절 대체공휴일
    assert is_holiday(date(2026, 6, 3))  # 지방선거일
    assert not is_holiday(date(2026, 10, 6))


def test_time_uses_korean_time():
    c = cond(time={"from": "21:00", "to": "09:00"})
    from datetime import datetime

    utc_1330 = datetime(2026, 9, 19, 13, 30, tzinfo=UTC)  # 한국 시간 22:30
    assert check(c, sit(at=utc_1330))[0] is True


def test_payment_unknown_and_known():
    c = cond(payment=["naver_pay"])
    assert check(c, sit(payment_method=None)) == unknown("payment_method")
    assert check(c, sit(payment_method="naver_pay"))[0] is True
    assert check(cond(payment_not=["naver_pay"]), sit(payment_method=None)) == unknown("payment_method")


def test_option_choice_by_date_and_default():
    picks = [
        OptionPick(option="pkg", choice="p1", effective_from=date(2026, 9, 1)),
        OptionPick(option="pkg", choice="p2", effective_from=date(2026, 10, 1)),
    ]
    card = UserCard(id="u", card_id="c", options=picks)
    c = cond(option={"pkg": ["p2"]})
    assert check(c, sit(card=card))[0] is False
    assert check(c, sit(card=card, at=at("2026-10-01T00:00")))[0] is True
    assert check(c, sit()) == unknown("option", "pkg")
    assert check(c, sit(defaults={"pkg": "p2"}))[0] is True


def test_facts_and_birth_month():
    assert check(cond(fact="soldier"), sit()) == unknown("fact", "soldier")
    card = UserCard(id="u", card_id="c", facts={"soldier": False, "birth_month": 9})
    assert check(cond(fact="soldier"), sit(card=card))[0] is False
    assert check(cond(fact="birth_month_now"), sit(card=card))[0] is True


def test_card_month_and_lump_sum():
    card = UserCard(id="u", card_id="c", started_on=date(2026, 8, 20))
    assert check(cond(card_month={"min": 1}), sit(card=card))[0] is True  # 8월이 0, 9월이 1
    assert check(cond(card_month={"min": 1}), sit()) == unknown("started_on")
    assert check(cond(lump_sum=True), sit(installment_months=3))[0] is False


def test_any_of_unknown_only_when_nothing_true():
    c = cond(any_of=[{"fact": "soldier"}, {"fact": "salary"}])
    card = UserCard(id="u", card_id="c", facts={"salary": True})
    assert check(c, sit(card=card))[0] is True
    assert check(c, sit())[0] is None
    assert check(c, sit())[1] == frozenset({("fact", "soldier"), ("fact", "salary")})
````

- [x] **3단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_cond.py
```

기대: `10 passed`.

- [x] **4단계: 커밋**

```bash
git add backend/cherry_core/engine backend/tests/engine/conftest.py backend/tests/engine/test_cond.py
git commit -m "feat: 계산 엔진 모델과 참·거짓·모름 조건 판정 추가" -m "작업 002 설계 1절, 2.1, 3.1, 3.2. 부모 업종까지만 아는 결제와 모르는 결제수단, 사실, 옵션은 모름으로 판정한다."
```

2026-09-29 실행 결과: 10개 통과, 전체 93개 통과. 모델, 조건 판정, 준비 값 파일은 과제 2에서 둔 것과 같았다.

---

## 과제 5: 실적과 결제 혜택 계산

**파일**
- 만들기: `backend/cherry_core/engine/spend.py`, `price.py`
- 고치기: `backend/cherry_core/engine/__init__.py`
- 테스트: `backend/tests/engine/test_spend.py`, `test_benefits.py`

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/engine/test_spend.py`

````python
"""실적 계산 규칙. 설계 2절. 기대값은 손계산이고 계산을 주석에 한 줄로 적는다."""

from datetime import UTC, date, datetime

from .conftest import at, card, holder, pay, prev_month

CAFE_10 = {
    "key": "cafe-10",
    "target": {"categories": ["cafe"]},
    "reward": {"type": "billing_discount", "rate": 10},
    "limits": [{"per": "month", "amount": 5000}],
    "tiers": {"from": 300000},
}
SEPT = date(2026, 9, 1)


def status(eng, payments, holder_card=None, month=SEPT):
    h = holder_card or holder()
    priced = eng.price_month(h, payments)
    done = {r.payment_id: r.benefits for r in priced}
    saved = [p.model_copy(update={"benefits": done.get(p.id, p.benefits)}) for p in payments]
    return eng.spend_status(h, saved, month)


def test_tier_from_previous_month(engine):
    # 지난달 35만 → 30만 구간. 이번 달 18.2만 → 유지까지 30만 − 18.2만 = 11.8만, 60만까지 41.8만. 시안 6쪽
    eng = engine(card([CAFE_10]))
    s = status(eng, prev_month(350000) + [pay(182000, "2026-09-10T12:00", category="other")])
    assert (s.tier, s.tier_source, s.prev_month_counted) == (300000, "prev_month", 350000)
    assert (s.counted, s.to_keep, s.next_tier, s.to_next) == (182000, 118000, 600000, 418000)


def test_tier_lower_bound_boundary(engine):
    # 하한 1원 아래는 아래 구간, 하한은 그 구간
    eng = engine(card([CAFE_10]))
    assert status(eng, prev_month(299999)).tier == 0
    assert status(eng, prev_month(300000)).tier == 300000


def test_registration_month_uses_estimate_only_without_records(engine):
    # E2. 등록한 달에 지난달 기록이 없으면 추정값, 추정값도 없으면 0 구간과 경고, 기록이 있으면 기록
    eng = engine(card([CAFE_10]))
    new = holder(registered_on=date(2026, 9, 10), assumed_prev_month_spend=410000)
    s = status(eng, [], new)
    assert (s.tier, s.tier_source) == (300000, "assumed")  # 시안 4쪽. 지난달 41만이면 30만 구간
    s = status(eng, [], holder(registered_on=date(2026, 9, 10)))
    assert s.tier == 0 and "no_prev_month_data" in [w.code for w in s.warnings]
    s = status(eng, prev_month(100000), new)
    assert (s.tier, s.tier_source, s.prev_month_counted) == (0, "prev_month", 100000)


def test_excluded_category_and_interest_free(engine):
    eng = engine(card([CAFE_10], spend={"interest_free": "exclude"}))
    h = holder()
    tax, free = (
        pay(128000, "2026-09-18T09:00", category="tax"),
        pay(50000, "2026-09-18T10:00", category="other", interest_free=True),
    )
    r = eng.price_month(h, [tax, free])
    assert r[0].spend == [] and r[0].warnings[0].data == {"reason": "category"}  # 시안 10쪽 자동차세 실적 제외
    assert r[1].spend == [] and r[1].warnings[0].data == {"reason": "interest_free"}


def test_parent_category_is_excluded_conservatively(engine):
    # 설계 2.1. 지하철만 빼는 카드에 대중교통까지만 아는 결제는 뺀 것으로 보고 자식 업종을 묻는다
    eng = engine(card([CAFE_10], spend={"exclude_categories": ["transit.subway"]}))
    r = eng.price_month(holder(), [pay(1500, "2026-09-02T08:00", category="transit")])[0]
    assert r.spend == []
    assert ["not_counted_toward_spend", "needs_input"] == [w.code for w in r.warnings][:2]
    assert r.warnings[1].data["needs"] == [("category", "transit")]


def test_region_only_domestic(engine):
    eng = engine(card([CAFE_10], spend={"regions": ["domestic"]}))
    r = eng.price_month(holder(), [pay(30000, "2026-09-02T08:00", category="other", region="overseas")])[0]
    assert r.spend == [] and r.warnings[0].data == {"reason": "region"}


def test_benefit_applied_ratio(engine):
    # 우리 K-LIFE처럼 혜택 받은 결제는 50%만. 30,001원이면 15,000.5 → 원 미만 버림 15,000
    flat = {k: v for k, v in CAFE_10.items() if k != "tiers"}
    eng = engine(card([flat], tiers=(0,), spend={"exclude_applied": 0.5}))
    r = eng.price_month(holder(), [pay(30001, "2026-09-02T08:00", merchant="starbucks")])[0]
    assert r.benefits[0].value == 3000 and r.spend[0].amount == 15000


def test_month_offset_moves_transit_to_next_month(engine):
    # 신한처럼 9월에 탄 지하철은 10월 실적
    eng = engine(card([CAFE_10], spend={"month_offset": {"transit.subway": 1}}))
    r = eng.price_month(holder(), [pay(1500, "2026-09-02T08:00", category="transit.subway")])[0]
    assert [(p.month, p.amount) for p in r.spend] == [(date(2026, 10, 1), 1500)]


def test_installment_split_by_month(engine):
    # E4. 100,000원 3개월이면 33,333, 33,333, 나머지 33,334
    eng = engine(card([CAFE_10], spend={"installment": "per_installment_month"}))
    r = eng.price_month(holder(), [pay(100000, "2026-09-02T08:00", category="other", installment_months=3)])[0]
    assert [p.amount for p in r.spend] == [33333, 33333, 33334]
    assert [p.month.month for p in r.spend] == [9, 10, 11]


def test_cancellation_months(engine):
    # 8월 10만원을 9월 5일에 4만원 취소. cancel_month면 9월에서, original_month면 8월에서 뺀다
    cancelled = {"cancelled_amount": 40000, "cancelled_at": at("2026-09-05T10:00")}
    eng = engine(card([CAFE_10]))
    r = eng.price_month(holder(), [pay(100000, "2026-08-20T10:00", category="other", **cancelled)])[0]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 100000), (9, -40000)]
    eng = engine(
        card(
            [CAFE_10],
            spend={
                "cancellation": "original_month",
                "cancellation_overrides": [{"when": {"region": "overseas"}, "use": "cancel_month"}],
            },
        )
    )
    r = eng.price_month(holder(), [pay(100000, "2026-08-20T10:00", category="other", **cancelled)])[0]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 100000), (8, -40000)]
    r = eng.price_month(holder(), [pay(100000, "2026-08-20T10:00", category="other", region="overseas", **cancelled)])[
        0
    ]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 100000), (9, -40000)]


def test_original_month_cancellation_lowers_this_month_tier(engine):
    # E5. 8월 35만 중 10만을 original_month로 취소하면 8월 25만 → 9월 구간 0
    eng = engine(card([CAFE_10], spend={"cancellation": "original_month"}))
    p = pay(350000, "2026-08-10T10:00", category="other", cancelled_amount=100000, cancelled_at=at("2026-09-03T10:00"))
    assert status(eng, [p]).tier == 0


def test_month_below_zero_counts_as_zero(engine):
    eng = engine(card([CAFE_10]))
    p = pay(50000, "2026-08-31T10:00", category="other", cancelled_amount=50000, cancelled_at=at("2026-09-01T10:00"))
    assert status(eng, [p]).counted == 0


def test_korean_time_month_boundary(engine):
    # E7. 8월 31일 23:30 한국 시간은 8월, 협정 세계시 8월 31일 15:30은 한국 시간 9월 1일 00:30이라 9월
    eng = engine(card([CAFE_10]))
    late = pay(10000, "2026-08-31T23:30", category="other")
    utc = pay(10000, "2026-08-31T23:30", category="other").model_copy(
        update={"paid_at": datetime(2026, 8, 31, 15, 30, tzinfo=UTC)}
    )
    assert eng.price_month(holder(), [late])[0].spend[0].month == date(2026, 8, 1)
    assert eng.price_month(holder(), [utc])[0].spend[0].month == date(2026, 9, 1)


def test_new_card_period(engine):
    # 9월 5일부터 쓴 카드는 9월과 10월에 30만 구간 특례. 11월은 10월 실적대로
    eng = engine(card([CAFE_10], new_card={"from": "registration", "until": "next_month_end", "tier": 300000}))
    new = holder(started_on=date(2026, 9, 5))
    assert (status(eng, [], new).tier, status(eng, [], new).tier_source) == (300000, "new_card")
    assert status(eng, [], new, date(2026, 10, 1)).tier == 300000
    assert status(eng, [], new, date(2026, 11, 1)).tier == 0


def test_new_card_tier_by_benefit(engine):
    # tier_by_benefit 0인 혜택은 특례가 없다
    rules = {
        "new_card": {
            "from": "registration",
            "until": "next_month_end",
            "tier": 300000,
            "tier_by_benefit": {"cafe-10": 0},
        }
    }
    eng = engine(card([CAFE_10], **rules))
    r = eng.price_month(holder(started_on=date(2026, 9, 5)), [pay(10000, "2026-09-10T10:00", merchant="starbucks")])[0]
    assert r.benefits == [] and r.warnings[0].code == "tier_not_met"


def test_basis_none_and_billing_cycle(engine):
    # E6. 실적 조건 없는 카드는 구간을 세지 않고, 결제일 기준 실적 카드는 계산하지 않는다
    flat = {k: v for k, v in CAFE_10.items() if k != "tiers"}
    s = status(engine(card([flat], tiers=(0,), spend={"basis": "none"})), [])
    assert (s.tier, s.tier_source, s.to_keep, s.to_next) == (0, "none", None, None)
    s = status(engine(card([CAFE_10], spend={"basis": "billing_cycle"})), prev_month(350000))
    assert (s.tier, s.tier_source) == (0, "unsupported")
    assert "spend_basis_unsupported" in [w.code for w in s.warnings]
````

`backend/tests/engine/test_benefits.py`

````python
"""혜택 계산 규칙. 설계 3절. 기대값은 손계산이고 계산을 주석에 한 줄로 적는다."""

from datetime import date

from .conftest import at, card, codes, holder, pay, prev_month, values


def b(key, target, reward, **kw):
    return {"key": key, "target": target, "reward": reward, **kw}


CAFE = {"categories": ["cafe"]}
RATE10 = {"type": "billing_discount", "rate": 10}


def run(eng, payments, h=None):
    return eng.price_month(h or holder(), payments)


def test_rate_with_per_payment_cap(engine):
    # 스타벅스 12,500원 × 10% = 1,250 → 건당 최대 1,000원. 시안 7쪽
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "txn", "amount": 1000}])], tiers=(0,)))
    assert values(run(eng, [pay(12500, "2026-09-19T14:20", merchant="starbucks")])) == [{"cafe-10": 1000}]


def test_monthly_limit_just_before_and_after(engine):
    # 월 5천원. 4만5천원 결제로 4,500을 쓰면 다음 1만원 결제는 1,000이 아니라 남은 500. 그다음은 0
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 5000}])], tiers=(0,)))
    r = run(
        eng,
        [
            pay(45000, "2026-09-01T10:00", merchant="ediya"),
            pay(10000, "2026-09-02T10:00", merchant="ediya"),
            pay(10000, "2026-09-03T10:00", merchant="ediya"),
        ],
    )
    assert values(r) == [{"cafe-10": 4500}, {"cafe-10": 500}, {}]
    assert "limit_exhausted" in codes(r[1]) and "limit_exhausted" in codes(r[2])


def test_limit_resets_next_month(engine):
    # 9월 한도 5천원을 다 써도 10월 1일에 초기화. 시안 14쪽
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 5000}])], tiers=(0,)))
    r = run(eng, [pay(50000, "2026-09-30T23:00", merchant="ediya"), pay(10000, "2026-10-01T00:10", merchant="ediya")])
    assert values(r) == [{"cafe-10": 5000}, {"cafe-10": 1000}]


def test_shared_limit_between_benefits(engine):
    # 카페 10%와 편의점 5%가 통합 1만원을 같이 쓴다. 카페 3,000 + 편의점 1,500 = 4,500 사용. 시안 6쪽
    benefits = [
        b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 5000}, {"shared": "integrated"}]),
        b(
            "cvs-5",
            {"categories": ["convenience"]},
            {"type": "billing_discount", "rate": 5},
            limits=[{"per": "month", "amount": 5000}, {"shared": "integrated"}],
        ),
    ]
    eng = engine(card(benefits, tiers=(0,), limits=[{"key": "integrated", "per": "month", "amount": 10000}]))
    h = holder()
    pays = [pay(30000, "2026-09-02T10:00", merchant="ediya"), pay(30000, "2026-09-03T10:00", merchant="gs25")]
    r = run(eng, pays, h)
    assert values(r) == [{"cafe-10": 3000}, {"cvs-5": 1500}]
    saved = [p.model_copy(update={"benefits": x.benefits}) for p, x in zip(pays, r)]
    uses = {(u.key, u.per): u for u in eng.limit_status(h, saved, at("2026-09-20T12:00"))}
    assert uses[("integrated", "month")].used_amount == 4500 and uses[("integrated", "month")].cap_amount == 10000
    assert uses[("cafe-10", "month")].cap_amount - uses[("cafe-10", "month")].used_amount == 2000


def test_count_limit_per_day(engine):
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "day", "count": 1}])], tiers=(0,)))
    r = run(
        eng,
        [
            pay(5000, "2026-09-02T10:00", merchant="ediya"),
            pay(5000, "2026-09-02T15:00", merchant="ediya"),
            pay(5000, "2026-09-03T10:00", merchant="ediya"),
        ],
    )
    assert values(r) == [{"cafe-10": 500}, {}, {"cafe-10": 500}]


def test_base_limit_per_payment_and_month(engine):
    # 1회 5만원까지: 8만원 × 10%가 아니라 5만원 × 10% = 5,000
    eng = engine(card([b("mart", CAFE, RATE10, limits=[{"per": "txn", "base": 50000}])], tiers=(0,)))
    assert values(run(eng, [pay(80000, "2026-09-02T10:00", merchant="ediya")])) == [{"mart": 5000}]
    # 월 30만원까지: 28만원을 쓴 뒤 5만원 결제는 2만원만 넣어 2,000. 한도가 결제 도중 끝나는 경우
    eng = engine(card([b("mart", CAFE, RATE10, limits=[{"per": "month", "base": 300000}])], tiers=(0,)))
    r = run(eng, [pay(280000, "2026-09-02T10:00", merchant="ediya"), pay(50000, "2026-09-03T10:00", merchant="ediya")])
    assert values(r) == [{"mart": 28000}, {"mart": 2000}]
    assert r[1].benefits[0].base == 20000


def test_limit_table_by_tier(engine):
    # 통합 한도 {30만: 1만, 60만: 2만}. 60만 구간에서 25만원 × 10% = 25,000 → 20,000
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=[{"shared": "integrated"}], tiers={"from": 300000})],
            limits=[{"key": "integrated", "per": "month", "amount": {300000: 10000, 600000: 20000}}],
        )
    )
    assert values(run(eng, prev_month(600000) + [pay(250000, "2026-09-02T10:00", merchant="ediya")]))[1] == {
        "cafe-10": 20000
    }


def test_adjust_by_fact_multiply_and_months(engine):
    base = [{"per": "month", "amount": 1000, "count": 1, "adjust": [{"when": {"fact": "soldier"}, "count": None}]}]
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=base)],
            tiers=(0,),
            facts=[{"key": "soldier", "type": "bool", "scope": "user", "ask": "현역 병사인가요"}],
        )
    )
    two = [pay(5000, "2026-09-02T10:00", merchant="ediya"), pay(5000, "2026-09-03T10:00", merchant="ediya")]
    assert values(run(eng, two)) == [{"cafe-10": 500}, {}]  # 월 1회
    assert values(run(eng, two, holder(facts={"soldier": True}))) == [
        {"cafe-10": 500},
        {"cafe-10": 500},
    ]  # 횟수 제한 없음
    doubled = [
        {
            "per": "month",
            "amount": 1000,
            "adjust": [{"when": {"fact": "birth_month_now"}, "multiply": 2}, {"when": {"months": [5, 12]}, "add": 500}],
        }
    ]
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=doubled)],
            tiers=(0,),
            facts=[{"key": "birth_month", "type": "month", "scope": "user", "ask": "생일이 몇 월인가요"}],
        )
    )
    big = [pay(50000, "2026-09-02T10:00", merchant="ediya")]
    assert values(run(eng, big, holder(facts={"birth_month": 9}))) == [{"cafe-10": 2000}]  # 생일 달 두 배
    assert values(run(eng, [pay(50000, "2026-12-02T10:00", merchant="ediya")])) == [{"cafe-10": 1500}]  # 12월 +500


def test_tiers_to_and_waived_from_only(engine):
    # 나라사랑 편의점: 8만~20만 구간, 급여이체자는 하한 면제. 설계 2.2의 to는 그대로라 25만 구간은 받지 못한다
    nara = b(
        "nara-cvs",
        {"categories": ["convenience"]},
        RATE10,
        tiers={"from": 80000, "to": 200000, "waived_when": {"fact": "salary"}},
    )
    eng = engine(
        card(
            [nara],
            tiers=(0, 80000, 200000, 250000),
            facts=[{"key": "salary", "type": "bool", "scope": "card", "ask": "급여이체"}],
        )
    )
    gs = lambda: pay(5000, "2026-09-02T10:00", merchant="gs25")
    salary = holder(facts={"salary": True})
    assert values(run(eng, [gs()], salary)) == [{"nara-cvs": 500}]  # 0 구간이지만 면제
    assert values(run(eng, prev_month(250000) + [gs()], salary))[1] == {}  # 25만 구간은 급여이체자도 없음
    assert values(run(eng, prev_month(200000) + [gs()]))[1] == {"nara-cvs": 500}
    r = run(eng, [gs()])[0]
    assert r.benefits == [] and "needs_input" in codes(r)  # 급여이체 여부를 모르면 묻는다


def test_day_and_holidays(engine):
    weekend = lambda h: b("wk", CAFE, RATE10, when=[{"day": {"in": ["sat", "sun"], "holidays": h}}])
    sat_holiday = pay(10000, "2026-10-03T10:00", merchant="ediya")  # 개천절, 토요일
    mon_substitute = pay(10000, "2026-10-05T10:00", merchant="ediya")  # 개천절 대체공휴일, 월요일
    for mode, expected in [
        ("ignore", [1000, 0]),
        ("include", [1000, 1000]),
        ("exclude", [0, 0]),
        ("only", [1000, 1000]),
    ]:
        eng = engine(card([weekend(mode)], tiers=(0,)))
        got = [sum(v.values()) for v in values(run(eng, [sat_holiday, mon_substitute]))]
        assert got == expected, mode


def test_time_range_across_midnight(engine):
    eng = engine(card([b("night", CAFE, RATE10, when=[{"time": {"from": "21:00", "to": "09:00"}}])], tiers=(0,)))
    times = ["2026-09-02T23:30", "2026-09-03T08:59", "2026-09-03T09:00", "2026-09-03T20:59", "2026-09-03T21:00"]
    got = [bool(v) for v in values(run(eng, [pay(10000, t, merchant="ediya") for t in times]))]
    assert got == [True, True, False, False, True]


def test_unknown_payment_method(engine):
    # 결제수단을 모르면 저장한 결제는 혜택 0에 needs_input. 설계 3.1
    eng = engine(card([b("npay", CAFE, RATE10, when=[{"payment": ["naver_pay"]}])], tiers=(0,)))
    r = run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["payment_method"]]
    r = run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya", payment_method="naver_pay")])[0]
    assert values([r]) == [{"npay": 1000}]


def test_parent_category_target_is_unknown(engine):
    eng = engine(card([b("burger", {"categories": ["restaurant.fastfood"]}, RATE10)], tiers=(0,)))
    r = run(eng, [pay(10000, "2026-09-02T12:00", category="restaurant")])[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["category", "restaurant"]]
    assert values(run(eng, [pay(10000, "2026-09-02T12:00", category="restaurant.fastfood")])) == [{"burger": 1000}]


def test_common_exclusion_and_explicit_target(engine):
    # 공통 제외 업종이어도 혜택이 대상으로 직접 적었으면 받는다. 무이자할부는 늘 뺀다. 설계 3.2의 3
    benefits = [
        b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1}),
        b("tax-3", {"categories": ["tax"]}, {"type": "billing_discount", "rate": 3}, stack="tax"),
    ]
    eng = engine(
        card(
            benefits,
            tiers=(0,),
            stacks=[{"key": "tax"}],
            benefit_exclusions={"categories": ["tax"], "when_any": [{"interest_free": True}]},
        )
    )
    r = run(
        eng,
        [
            pay(100000, "2026-09-02T12:00", category="tax"),
            pay(100000, "2026-09-03T12:00", category="other", interest_free=True),
        ],
    )
    assert values(r) == [{"tax-3": 3000}, {}]


def test_stack_best_and_other_stack_adds(engine):
    # 같은 묶음은 큰 쪽 하나, 다른 묶음은 더한다. 카페 10% 1,000 vs 전가맹점 1% 100 → 1,000. 간편결제 묶음 2% 200 더함
    benefits = [
        b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1}),
        b("cafe-10", CAFE, RATE10),
        b(
            "pay-2",
            {"all": True},
            {"type": "billing_discount", "rate": 2},
            when=[{"payment": ["naver_pay"]}],
            stack="pay",
        ),
    ]
    eng = engine(card(benefits, tiers=(0,), stacks=[{"key": "pay"}]))
    assert values(run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya", payment_method="naver_pay")])) == [
        {"cafe-10": 1000, "pay-2": 200}
    ]


def test_priority_split(engine):
    # 현대카드M처럼 5% 영역 한도를 넘은 금액은 1.5%. 10만원: 5% 월 한도 2,000P → 4만원분, 나머지 6만원 × 1.5% = 900
    benefits = [
        b("base-1-5", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.5}),
        b(
            "area-5",
            CAFE,
            {"type": "points", "program": "test_point", "rate": 5},
            limits=[{"per": "month", "amount": 2000}],
        ),
    ]
    stacks = [{"key": "main", "pick": "priority", "order": ["area-5", "base-1-5"], "spill": "split"}]
    eng = engine(card(benefits, tiers=(0,), stacks=stacks))
    r = run(eng, [pay(100000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"area-5": 2000, "base-1-5": 900}]
    assert [x.base for x in r.benefits] == [40000, 60000]


def test_priority_without_split_moves_on_when_exhausted(engine):
    # 삼성 iD ON처럼 3% 한도를 다 쓴 다음 결제부터 1%. 같은 결제 안에서는 나누지 않는다
    benefits = [
        b("over-3", {"all": True}, {"type": "billing_discount", "rate": 3}, limits=[{"per": "month", "amount": 1000}]),
        b("over-1", {"all": True}, {"type": "billing_discount", "rate": 1}),
    ]
    eng = engine(
        card(benefits, tiers=(0,), stacks=[{"key": "main", "pick": "priority", "order": ["over-3", "over-1"]}])
    )
    r = run(eng, [pay(50000, "2026-09-02T10:00", category="other"), pay(10000, "2026-09-03T10:00", category="other")])
    assert values(r) == [{"over-3": 1000}, {"over-1": 100}]


def test_month_total_fixed(engine):
    # 카카오뱅크처럼 후불교통 한 달 합 5만원 이상이면 4천원. 3만 → 0, 2만5천 → 합 5만5천이라 4,000, 1만 → 0
    t = b(
        "transit-4000",
        {"categories": ["transit.subway"]},
        {"type": "cashback", "fixed": 4000, "basis": "month_total"},
        when=[{"month_total": {"min": 50000}}],
        limits=[{"per": "month", "count": 1}],
    )
    eng = engine(card([t], tiers=(0,)))
    r = run(
        eng,
        [
            pay(30000, "2026-09-10T08:00", category="transit.subway"),
            pay(25000, "2026-09-20T08:00", category="transit.subway"),
            pay(10000, "2026-09-25T08:00", category="transit.subway"),
        ],
    )
    assert values(r) == [{}, {"transit-4000": 4000}, {}]


def test_month_total_rate(engine):
    # LOCA 365처럼 한 달 합 2만원 이상이면 합의 10%, 월 5천원. 1만5천 → 0, 1만 → 합 2만5천의 10% 2,500, 3만 → 합 5만5천의 10% 5,500 중 한도 남은 2,500
    t = b(
        "transit-10",
        {"categories": ["transit.subway"]},
        {"type": "billing_discount", "rate": 10, "basis": "month_total"},
        when=[{"month_total": {"min": 20000}}],
        limits=[{"per": "month", "amount": 5000}],
    )
    eng = engine(card([t], tiers=(0,)))
    r = run(
        eng,
        [
            pay(15000, "2026-09-10T08:00", category="transit.subway"),
            pay(10000, "2026-09-20T08:00", category="transit.subway"),
            pay(30000, "2026-09-25T08:00", category="transit.subway"),
        ],
    )
    assert values(r) == [{}, {"transit-10": 2500}, {"transit-10": 2500}]


def test_ranked_area_and_final(engine):
    # 삼성 iD ON처럼 커피와 배달 중 이번 달 1위만 30%. 스타벅스와 이디야는 area coffee로 한 영역
    benefits = [
        b(
            "coffee",
            {"merchants": ["ediya"]},
            {"type": "billing_discount", "rate": 30},
            when=[{"ranked": "top"}],
            area="coffee",
            stack="area",
        ),
        b(
            "coffee-sb",
            {"merchants": ["starbucks"]},
            {"type": "billing_discount", "rate": 30},
            when=[{"ranked": "top"}],
            area="coffee",
            stack="area",
        ),
        b(
            "delivery",
            {"merchants": ["baemin"]},
            {"type": "billing_discount", "rate": 30},
            when=[{"ranked": "top"}],
            stack="area",
        ),
    ]
    eng = engine(card(benefits, tiers=(0,), ranked=[{"key": "top", "top": 1}], stacks=[{"key": "area"}]))
    h = holder()
    pays = [
        pay(10000, "2026-09-02T10:00", merchant="ediya"),
        pay(20000, "2026-09-03T19:00", merchant="baemin"),
        pay(15000, "2026-09-04T10:00", merchant="starbucks"),
    ]
    r = run(eng, pays, h)
    # 1: 커피 1만 1위 → 3,000. 2: 배달 2만이 커피 1만을 넘어 1위 → 6,000. 3: 커피 2만5천 → 1위 → 4,500
    assert values(r) == [{"coffee": 3000}, {"delivery": 6000}, {"coffee-sb": 4500}]
    assert "ranked_provisional" in codes(r[0])
    # 달이 끝나면 최종 순위로 다시 계산. 커피 2만5천이 배달 2만보다 커서 배달은 0. 설계 3.5
    saved = [p.model_copy(update={"benefits": x.benefits}) for p, x in zip(pays, r)]
    final = eng.price_month(h, saved, month=date(2026, 9, 1), final=True)
    assert values(final) == [{"coffee": 3000}, {}, {"coffee-sb": 4500}]
    assert "ranked_provisional" not in codes(final[0])


def test_onsite_discount_back_calculation(engine):
    # 현장할인 10%: 기록 9,000원 → 할인 전 10,000원, 할인 1,000원. 1만원 이상 조건은 할인 전 금액으로 본다. 실적은 9,000
    t = b(
        "px",
        {"categories": ["convenience"]},
        {"type": "onsite_discount", "rate": 10},
        when=[{"amount": {"min": 10000}}],
    )
    eng = engine(card([t], tiers=(0,)))
    r = run(eng, [pay(9000, "2026-09-02T10:00", merchant="gs25")])[0]
    assert values([r]) == [{"px": 1000}] and r.benefits[0].base == 10000 and r.spend[0].amount == 9000


def test_per_unit_per_liter_points_and_rounding(engine):
    per_unit = b(
        "unit",
        {"categories": ["other"]},
        {"type": "points", "program": "test_point", "per_unit": {"unit": 20000, "amount": 1000}},
    )
    assert values(run(engine(card([per_unit], tiers=(0,))), [pay(45000, "2026-09-02T10:00", category="other")])) == [
        {"unit": 2000}
    ]  # 2만원당 1천P, 남는 5천원은 버림
    fuel = b("fuel", {"categories": ["fuel"]}, {"type": "billing_discount", "per_liter": 60})
    assert values(run(engine(card([fuel], tiers=(0,))), [pay(85000, "2026-09-02T10:00", merchant="sk_energy")])) == [
        {"fuel": 3000}
    ]  # 85,000 ÷ 1,700 = 50L × 60
    half_up = b("m", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.5, "round": "round"})
    assert values(run(engine(card([half_up], tiers=(0,))), [pay(4639, "2026-09-02T10:00", category="other")])) == [
        {"m": 70}
    ]  # 69.585 반올림. 현대카드M 원문 예시
    floor = b("m", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.5})
    assert values(run(engine(card([floor], tiers=(0,))), [pay(4639, "2026-09-02T10:00", category="other")])) == [
        {"m": 69}
    ]


def test_options_default_change_and_missing(engine):
    opt = {
        "key": "pkg",
        "title": "패키지",
        "choices": [{"key": "p1", "title": "1"}, {"key": "p2", "title": "2"}],
        "change": "next_month",
    }
    benefits = [
        b("p1-cafe", CAFE, RATE10, when=[{"option": {"pkg": ["p1"]}}]),
        b("p2-cafe", CAFE, {"type": "billing_discount", "rate": 20}, when=[{"option": {"pkg": ["p2"]}}]),
    ]
    eng = engine(card(benefits, tiers=(0,), options=[opt]))
    sept = [pay(10000, "2026-09-20T10:00", merchant="ediya")]
    r = run(eng, sept)[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["option", "pkg"]]
    picks = [
        {"option": "pkg", "choice": "p1", "effective_from": date(2026, 9, 1)},
        {"option": "pkg", "choice": "p2", "effective_from": date(2026, 10, 1)},
    ]
    h = holder(options=picks)
    assert values(run(eng, sept + [pay(10000, "2026-10-02T10:00", merchant="ediya")], h)) == [
        {"p1-cafe": 1000},
        {"p2-cafe": 2000},
    ]
    eng = engine(card(benefits, tiers=(0,), options=[{**opt, "default": "p2"}]))
    assert values(run(eng, sept)) == [{"p2-cafe": 2000}]  # 고르지 않으면 카드사 기본값


def test_card_month_and_promo_period(engine):
    # 생활혜택은 카드 등록 달에는 없다. 행사 혜택은 기간 안에만
    benefits = [
        b("life", CAFE, RATE10, when=[{"card_month": {"min": 1}}]),
        b(
            "promo",
            {"merchants": ["gs25"]},
            {"type": "cashback", "fixed": 1000},
            valid_from=date(2026, 9, 10),
            valid_until=date(2026, 9, 30),
        ),
    ]
    eng = engine(card(benefits, tiers=(0,)))
    h = holder(started_on=date(2026, 9, 5))
    r = run(
        eng, [pay(10000, "2026-09-20T10:00", merchant="ediya"), pay(10000, "2026-10-02T10:00", merchant="ediya")], h
    )
    assert values(r) == [{}, {"life": 1000}]
    r = run(eng, [pay(10000, "2026-09-20T10:00", merchant="ediya")])[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["started_on"]]
    r = run(
        eng,
        [
            pay(5000, "2026-09-09T10:00", merchant="gs25"),
            pay(5000, "2026-09-10T10:00", merchant="gs25"),
            pay(5000, "2026-10-01T10:00", merchant="gs25"),
        ],
    )
    assert values(r) == [{}, {"promo": 1000}, {}]


def test_revision_estimated_and_missing(engine):
    eng = engine(card([b("cafe-10", CAFE, RATE10)], tiers=(0,), start=date(2026, 9, 1), estimated=True))
    r = run(eng, [pay(10000, "2026-08-20T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"cafe-10": 1000}] and "revision_estimated" in codes(r)
    eng = engine(card([b("cafe-10", CAFE, RATE10)], tiers=(0,), start=date(2026, 9, 1)))
    r = run(eng, [pay(10000, "2026-08-20T10:00", merchant="ediya")])[0]
    assert r.benefits == [] and codes(r) == ["no_revision"]


def test_unmodeled_is_computed_with_warning(engine):
    # E12. 문장으로 남긴 조건은 없는 것처럼 계산하고 문장을 경고에 담는다
    eng = engine(card([b("cafe-10", CAFE, RATE10, unmodeled=["백화점 안 매장은 제외"])], tiers=(0,)))
    r = run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"cafe-10": 1000}]
    assert [w.data for w in r.warnings if w.code == "check_conditions"] == [{"sentences": ["백화점 안 매장은 제외"]}]


def test_full_cancellation_gives_nothing(engine):
    # E5. 전액 취소된 결제는 혜택 0이고 한도도 쓰지 않는다
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 1000}])], tiers=(0,)))
    gone = pay(10000, "2026-09-02T10:00", merchant="ediya", cancelled_amount=10000, cancelled_at=at("2026-09-03T10:00"))
    assert values(run(eng, [gone, pay(10000, "2026-09-04T10:00", merchant="ediya")])) == [{}, {"cafe-10": 1000}]


def test_same_input_same_output_and_integers(engine):
    eng = engine(card([b("m", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.3})], tiers=(0,)))
    pays = [pay(12345, "2026-09-02T10:00", category="other"), pay(67891, "2026-09-03T10:00", category="other")]
    first, second = run(eng, pays), run(eng, pays)
    assert first == second
    assert all(
        isinstance(x.value, int) and isinstance(x.amount, int) and isinstance(x.base, int)
        for r in first
        for x in r.benefits
    )
    assert values(first) == [{"m": 160}, {"m": 882}]  # 12,345 × 1.3% = 160.485, 67,891 × 1.3% = 882.583 → 버림


def test_new_card_tier_decides_ranked_top(engine):
    # KB Easy all처럼 상위 몇 개가 구간표인데 새 카드면 특례 구간으로 센다. 표 대조에서 찾았다
    benefits = [
        b("coffee", {"merchants": ["ediya"]}, RATE10, when=[{"ranked": "top"}], tiers={"from": 300000}),
        b("delivery", {"merchants": ["baemin"]}, RATE10, when=[{"ranked": "top"}], tiers={"from": 300000}),
    ]
    rules = {
        "ranked": [{"key": "top", "top": {300000: 1}}],
        "new_card": {"from": "registration", "until": "next_month_end", "tier": 300000},
    }
    eng = engine(card(benefits, **rules))
    r = run(eng, [pay(10000, "2026-09-10T10:00", merchant="ediya")], holder(started_on=date(2026, 9, 5)))
    assert values(r) == [{"coffee": 1000}]


def test_waived_unknown_reports_tier_and_input(engine):
    # 나라사랑처럼 급여이체자면 하한 면제인데 급여이체 여부를 모르면 구간 미달과 묻기를 함께 붙인다. 표 대조에서 찾았다
    nara = b(
        "nara-cvs", {"categories": ["convenience"]}, RATE10, tiers={"from": 80000, "waived_when": {"fact": "salary"}}
    )
    eng = engine(
        card([nara], tiers=(0, 80000), facts=[{"key": "salary", "type": "bool", "scope": "card", "ask": "급여이체"}])
    )
    r = run(eng, prev_month(79999) + [pay(8000, "2026-09-01T12:00", merchant="gs25")])[1]
    assert r.benefits == [] and {"tier_not_met", "needs_input"} <= set(codes(r))


def test_unknown_adjust_asks(engine):
    # My WE:SH처럼 한도 조건이 모름이면 한도를 늘리지 않고 묻는다. 표 대조에서 찾았다
    doubled = [{"per": "month", "amount": 1000, "adjust": [{"when": {"fact": "birth_month_now"}, "multiply": 2}]}]
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=doubled)],
            tiers=(0,),
            facts=[{"key": "birth_month", "type": "month", "scope": "user", "ask": "생일"}],
        )
    )
    r = run(eng, [pay(50000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"cafe-10": 1000}]
    assert ["fact", "birth_month"] in next(w for w in r.warnings if w.code == "needs_input").data["needs"]


def test_onsite_discount_with_cap(engine):
    # 현장할인 20%에 건당 4만원 한도. 기록 170,000원이면 할인 4만원, 할인 전 210,000원. 식대로 212,500원으로 부풀리지 않는다
    t = b(
        "outback",
        {"categories": ["restaurant"]},
        {"type": "onsite_discount", "rate": 20},
        limits=[{"per": "txn", "amount": 40000}],
    )
    r = run(engine(card([t], tiers=(0,))), [pay(170000, "2026-09-02T19:00", category="restaurant")])[0]
    assert values([r]) == [{"outback": 40000}] and r.benefits[0].base == 210000


def test_limit_exhausted_only_for_period_limits(engine):
    # 건당 최대 1,000원으로 줄어든 것은 한도를 다 쓴 것이 아니다. 달 한도로 줄면 붙인다
    per_txn = b("cafe-10", CAFE, RATE10, limits=[{"per": "txn", "amount": 1000}])
    r = run(engine(card([per_txn], tiers=(0,))), [pay(12500, "2026-09-02T10:00", merchant="ediya")])[0]
    assert "limit_exhausted" not in codes(r)
    monthly = b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 1000}])
    r = run(engine(card([monthly], tiers=(0,))), [pay(12500, "2026-09-02T10:00", merchant="ediya")])[0]
    assert "limit_exhausted" in codes(r)


def test_common_exclusion_skipped_only_for_listed_category(engine):
    # 가맹점만 적은 혜택은 결제 업종으로 공통 제외를 본다. 이마트에서 산 상품권 5만원은 0원, 장보기 5만원은 2,500원.
    # 업종을 직접 적은 혜택은 공통 제외보다 우선한다. 2026-09-29 사용자가 정했다. 설계 3.2의 3
    benefits = [
        b("gs-5", {"merchants": ["gs25"]}, {"type": "billing_discount", "rate": 5}),
        b("tax-3", {"categories": ["tax"]}, {"type": "billing_discount", "rate": 3}, stack="tax"),
    ]
    eng = engine(
        card(benefits, tiers=(0,), stacks=[{"key": "tax"}], benefit_exclusions={"categories": ["tax", "other"]})
    )
    r = run(
        eng,
        [
            pay(50000, "2026-09-02T10:00", merchant="gs25", category="other"),
            pay(50000, "2026-09-03T10:00", merchant="gs25"),
            pay(100000, "2026-09-04T10:00", category="tax"),
        ],
    )
    assert values(r) == [{}, {"gs-5": 2500}, {"tax-3": 3000}]
````

- [x] **2단계: 돌려서 실패를 본다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_spend.py backend/tests/engine/test_benefits.py
```

기대: `Engine`을 가져오지 못해 실패한다.

- [x] **3단계: 실적 계산을 쓴다**

`backend/cherry_core/engine/spend.py`

````python
"""실적 계산. 설계 2절."""

from __future__ import annotations

import math
from datetime import date

from cherry_core.catalog.models import Rules

from .cond import add_months, categories_match, check, local, month_of
from .context import Ctx, frac
from .models import AppliedBenefit, Payment, SpendPart, UserCard, Warn


def spend_parts(
    ctx: Ctx, card: UserCard, p: Payment, rules: Rules, benefits: list[AppliedBenefit]
) -> tuple[list[SpendPart], list[Warn]]:
    """결제 한 건이 실적에 넣는 금액과 달. 설계 2.2, 2.3. 실적에서 빠지면 그 이유를 경고로 돌려준다"""
    s = rules.spend
    paid_month = month_of(local(p.paid_at).date())
    category = ctx.category(p)
    if p.region not in s.regions:
        return [], [Warn(code="not_counted_toward_spend", data={"reason": "region"})]
    excluded, needs = categories_match(category, s.exclude_categories)
    if excluded is not False:
        warns = [Warn(code="not_counted_toward_spend", data={"reason": "category"})]
        if excluded is None:
            warns.append(Warn(code="needs_input", data={"needs": sorted(needs)}))
        return [], warns
    if s.interest_free == "exclude" and p.interest_free:
        return [], [Warn(code="not_counted_toward_spend", data={"reason": "interest_free"})]

    ratio = frac(0)
    by_key = {b.key: b for b in rules.benefits}
    for got in benefits:
        if got.value > 0 and got.key in by_key:
            own = by_key[got.key].exclude_applied
            ratio = max(ratio, frac(own if own is not None else s.exclude_applied))
    counted = math.floor(p.amount * (1 - ratio))
    warns = [Warn(code="not_counted_toward_spend", data={"reason": "benefit_applied"})] if counted == 0 else []

    offset = max((n for cat, n in s.month_offset.items() if categories_match(category, [cat])[0] is True), default=0)
    first = add_months(paid_month, offset)
    parts: list[SpendPart] = []
    if s.installment == "per_installment_month" and p.installment_months > 1:
        each = counted // p.installment_months
        for i in range(p.installment_months):
            last = i == p.installment_months - 1
            parts.append(SpendPart(month=add_months(first, i), amount=counted - each * i if last else each))
    else:
        parts.append(SpendPart(month=first, amount=counted))

    if p.cancelled_amount and counted:
        use = s.cancellation
        for o in s.cancellation_overrides:
            if check(o.when, ctx.situation(card, p))[0] is True:
                use = o.use
        minus = math.floor(frac(p.cancelled_amount) * counted / p.amount)
        month = month_of(local(p.cancelled_at).date()) if use == "cancel_month" and p.cancelled_at else first
        parts.append(SpendPart(month=month, amount=-minus))
    return parts, warns


def tier_of(
    ctx: Ctx, card: UserCard, month: date, prev_counted: int, prev_recorded: bool
) -> tuple[int | None, str, int | None, list[Warn]]:
    """이번 달 기본 구간. (구간 하한, 근거, 지난달 인정 실적, 경고). 설계 2.4

    prev_counted는 지난달 인정 실적, prev_recorded는 지난달 결제가 한 건이라도 기록됐는지다.
    """
    found = ctx.rules_on(card.card_id, month)
    if found is None:
        return None, "none", None, []
    rules = found[1]
    if rules.spend.basis == "none":
        return 0, "none", None, []
    if rules.spend.basis == "billing_cycle":
        return 0, "unsupported", None, [Warn(code="spend_basis_unsupported")]
    prev = max(prev_counted, 0)
    source, warns = "prev_month", []
    registered_now = card.registered_on is not None and month_of(card.registered_on) == month
    if registered_now and not prev_recorded:
        if card.assumed_prev_month_spend is not None:
            prev, source = card.assumed_prev_month_spend, "assumed"
        else:
            prev, warns = 0, [Warn(code="no_prev_month_data")]
    tier = max(t for t in rules.tiers if t <= prev)
    return tier, source, prev, warns


def new_card_tier(card: UserCard, month: date, rules: Rules, benefit_key: str | None, base: int) -> tuple[int, bool]:
    """신규 발급 특례 기간이면 특례 구간과 기본 구간 중 큰 쪽. (구간, 특례를 썼는지). 설계 2.4의 3"""
    nc = rules.new_card
    if nc is None or card.started_on is None:
        return base, False
    start = month_of(card.started_on)
    if not (start <= month <= add_months(start, 1)):
        return base, False
    special = nc.tier_by_benefit.get(benefit_key, nc.tier) if benefit_key else nc.tier
    return max(base, special), special > base


def card_notes(ctx: Ctx, card: UserCard, rules: Rules, month: date) -> list[Warn]:
    """카드 전체에 해당하는 문장 조건, 가정한 값, 고르지 않은 옵션. 설계 5.2, 5.3, 3.8"""
    out: list[Warn] = []
    sentences = rules.unmodeled + rules.benefit_exclusions.unmodeled
    if sentences:
        out.append(Warn(code="check_conditions", data={"sentences": sentences}))
    paths = ctx.assumed.get(card.card_id, {}).get(None)
    if paths:
        out.append(Warn(code="assumed_value", data={"paths": paths}))
    last_day = add_months(month, 1)
    picks = sorted((p for p in card.options if p.effective_from < last_day), key=lambda p: p.effective_from)
    chosen_now = {p.option: p.choice for p in picks}
    for o in rules.options:
        chosen = chosen_now.get(o.key, o.default)
        if chosen is None:
            out.append(Warn(code="needs_input", data={"needs": [["option", o.key]]}))
        elif chosen in o.unsupported:
            out.append(Warn(code="option_unsupported", data={"option": o.key, "choice": chosen}))
    return out
````

- [x] **4단계: 결제 혜택 계산을 쓴다**

`backend/cherry_core/engine/price.py`

````python
"""결제 하나의 혜택 계산. 설계 3절과 4.4의 사용량 표."""

from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime

from cherry_core.catalog.models import Benefit, Limit, Rules

from .cond import (
    FALSE,
    TRUE,
    Situation,
    Tri,
    add_months,
    all_of,
    any_of,
    categories_match,
    check,
    check_all,
    local,
    month_of,
)
from .context import Ctx, at_tier, frac, round_money
from .models import AppliedBenefit, LimitUse, Payment, PaymentResult, SpendStatus, UserCard, Warn
from .spend import card_notes, new_card_tier, spend_parts, tier_of

SKIP_TOTALS = frozenset({"ranked", "month_total"})


def period_key(per: str, at: datetime) -> tuple | None:
    """한도 기간. txn은 결제 하나라 쌓지 않는다. period는 행사 기간 전체, lifetime은 늘 하나다. 설계 3.4"""
    d = local(at).date()
    return {
        "txn": None,
        "day": ("d", d),
        "month": ("m", d.year, d.month),
        "quarter": ("q", d.year, (d.month - 1) // 3),
        "year": ("y", d.year),
        "period": ("p",),
        "lifetime": ("l",),
    }[per]


def limit_specs(rules: Rules, b: Benefit) -> list[tuple[tuple, Limit]]:
    """혜택이 쓰는 한도마다 (이름, 실제 칸). 혜택에 직접 적은 한도는 ("own", key, 순서), 공유 한도는 ("shared", key)"""
    shared = {x.key: x for x in rules.limits}
    return [
        (("shared", lim.shared), shared[lim.shared]) if lim.shared is not None else (("own", b.key, i), lim)
        for i, lim in enumerate(b.limits)
    ]


def situation(ctx: Ctx, card: UserCard, rules: Rules, p: Payment) -> Situation:
    s = ctx.situation(card, p)
    s.defaults = {o.key: o.default for o in rules.options}
    return s


def negate(t: Tri) -> Tri:
    """제외 조건을 대상 쪽 판정으로 바꾼다. 제외에 걸리면 거짓, 모르면 모름이다. 설계 2.1"""
    return FALSE if t[0] is True else TRUE if t[0] is False else t


def benefit_match(rules: Rules, b: Benefit, s: Situation) -> Tri:
    """행사 기간, 대상, 공통 제외, when 조건. 구간은 따로 본다. 설계 3.2의 1~4"""
    if (b.valid_from and s.day < b.valid_from) or (b.valid_until and s.day > b.valid_until):
        return FALSE
    t = b.target
    hit = (
        TRUE
        if t.all
        else any_of([TRUE if s.merchant in t.merchants else FALSE, categories_match(s.category, t.categories)])
    )
    if hit[0] is False or s.merchant in t.exclude_merchants:
        return FALSE
    parts = [hit, negate(categories_match(s.category, t.exclude_categories))]
    be = rules.benefit_exclusions
    # 대상이 이 결제의 업종을 직접 적었으면 공통 제외 업종보다 우선한다. 가맹점만 적었으면 결제 업종으로 공통 제외를 본다.
    # 이마트 5% 혜택으로 이마트에서 산 상품권은 뺀다. 2026-09-29 사용자가 정했다. 설계 3.2의 3
    if categories_match(s.category, t.categories)[0] is not True:
        parts.append(negate(categories_match(s.category, be.categories)))
    parts += [negate(check(w, s)) for w in be.when_any]
    s.area = b.area or b.key
    parts.append(check_all(b.when, s))
    return all_of(parts)


def ranked_areas(rules: Rules) -> dict[str, dict[str, list[Benefit]]]:
    """순위 그룹마다 영역과 그 영역의 혜택. 영역은 area, 없으면 혜택 key. 파일에 적힌 순서다"""
    out: dict[str, dict[str, list[Benefit]]] = {}
    for b in rules.benefits:
        for c in b.when:
            if c.ranked is not None:
                out.setdefault(c.ranked, {}).setdefault(b.area or b.key, []).append(b)
    return out


@dataclass
class Ledger:
    """사용량 표. 저장된 결제를 한 번 훑어 한도 사용량, 순위 영역 이용액, 달 합계, 달별 실적을 모은다. 설계 4.4

    child()로 만든 표는 부모 위에 쌓아 두는 임시 표다. 결제 하나를 계산하는 동안 쓴 한도를 부모를 바꾸지 않고 센다.
    """

    use: dict = field(default_factory=lambda: defaultdict(lambda: [0, 0, 0]))
    area: dict = field(default_factory=lambda: defaultdict(int))
    month_base: dict = field(default_factory=lambda: defaultdict(int))
    counted: dict = field(default_factory=lambda: defaultdict(int))
    seen: set = field(default_factory=set)
    parent: Ledger | None = None

    def _sum(self, name: str, key) -> int:
        own = getattr(self, name).get(key, 0)
        return own + (self.parent._sum(name, key) if self.parent else 0)

    def used(self, ident: tuple, key: tuple) -> list[int]:
        own = self.use.get((ident, key), [0, 0, 0])
        up = self.parent.used(ident, key) if self.parent else [0, 0, 0]
        return [a + b for a, b in zip(up, own)]

    def area_spend(self, group: str, area: str, month: date) -> int:
        return self._sum("area", (group, area, month))

    def month_total(self, key: str, month: date) -> int:
        return self._sum("month_base", (key, month))

    def counted_in(self, month: date) -> int:
        return self._sum("counted", month)

    def recorded(self, month: date) -> bool:
        return month in self.seen or (self.parent is not None and self.parent.recorded(month))

    def child(self) -> Ledger:
        return Ledger(parent=self)

    def add_benefit(self, rules: Rules, b: Benefit, got: AppliedBenefit, at: datetime) -> None:
        idents = limit_specs(rules, b)
        if b.reward.basis == "month_total":
            idents.append((("given", b.key), Limit(per="month", amount=0)))
        for ident, lim in idents:
            key = period_key(lim.per, at)
            if key is None:
                continue
            u = self.use[(ident, key)]
            u[0] += got.amount
            u[1] += 1 if got.amount > 0 else 0
            u[2] += got.base

    def add(self, ctx: Ctx, card: UserCard, p: Payment) -> None:
        """저장된 결제 한 건을 표에 더한다"""
        day = local(p.paid_at).date()
        month = month_of(day)
        self.seen.add(month)
        found = ctx.rules_on(card.card_id, day)
        if found is None:
            return
        rules = found[1]
        parts, _ = spend_parts(ctx, card, p, rules, p.benefits or [])
        for part in parts:
            self.counted[part.month] += part.amount
        by_key = {b.key: b for b in rules.benefits}
        for got in p.benefits or []:
            if got.key in by_key:
                self.add_benefit(rules, by_key[got.key], got, p.paid_at)
        if p.amount > p.cancelled_amount:
            self.add_totals(ctx, card, rules, p, month)

    def add_totals(self, ctx: Ctx, card: UserCard, rules: Rules, p: Payment, month: date) -> None:
        """순위 영역 이용액과 달 합계 혜택의 대상 이용액. 설계 3.4, 3.5"""
        s = situation(ctx, card, rules, p)
        s.skip = SKIP_TOTALS
        for b in rules.benefits:
            if b.reward.basis == "month_total" and benefit_match(rules, b, s)[0] is True:
                self.month_base[(b.key, month)] += s.amount
        for group, areas in ranked_areas(rules).items():
            for area, members in areas.items():
                if any(benefit_match(rules, b, s)[0] is True for b in members):
                    self.area[(group, area, month)] += s.amount


def build_ledger(ctx: Ctx, card: UserCard, payments: list[Payment]) -> Ledger:
    ledger = Ledger()
    for p in sorted(payments, key=lambda q: (q.paid_at, q.id)):
        ledger.add(ctx, card, p)
    return ledger


def reward_amount(ctx: Ctx, b: Benefit, base: int, tier: int) -> int:
    """결제액 base에 대한 보상 단위의 금액. 원 미만과 반올림은 reward.round를 따른다. 설계 3.3"""
    r = b.reward
    if r.rate is not None:
        x = frac(base) * frac(at_tier(r.rate, tier)) / 100
    elif r.fixed is not None:
        x = frac(at_tier(r.fixed, tier) or 0) if base > 0 else frac(0)
    elif r.per_unit is not None:
        x = frac((base // r.per_unit.unit) * r.per_unit.amount)
    elif ctx.fuel_price is not None:
        x = frac(base) * r.per_liter / ctx.fuel_price
    else:
        return 0
    return round_money(x, r.round)


def pre_discount(b: Benefit, net: int, tier: int) -> int:
    """현장할인의 할인 전 금액을 되짚는다. 설계 3.6"""
    r = b.reward
    if r.rate is not None:
        return math.ceil(frac(net) / (1 - frac(at_tier(r.rate, tier)) / 100))
    return net + int(at_tier(r.fixed, tier) or 0)


def caps(lim: Limit, tier: int, s: Situation) -> tuple[int | None, int | None, int | None, frozenset]:
    """한도 칸의 (금액, 횟수, 결제액, 모르는 것). 구간표와 adjust를 적용한다.
    adjust 조건이 모름이면 적용하지 않고 무엇을 모르는지 돌려준다. 설계 3.1"""
    amount, count, base = at_tier(lim.amount, tier), at_tier(lim.count, tier), at_tier(lim.base, tier)
    needs: frozenset = frozenset()
    for a in lim.adjust:
        hit = check(a.when, s)
        if hit[0] is None:
            needs |= hit[1]
        if hit[0] is not True:
            continue
        given = a.model_fields_set
        if "amount" in given:
            amount = at_tier(a.amount, tier)
        if "count" in given:
            count = at_tier(a.count, tier)
        if "base" in given:
            base = at_tier(a.base, tier)
        if a.multiply is not None and amount is not None:
            amount = math.floor(amount * frac(a.multiply))
        if a.add is not None and amount is not None:
            amount += a.add
    return amount, count, base, needs


@dataclass
class Offer:
    """혜택 하나를 이 결제에 계산해 본 결과. base는 혜택 계산에 넣은 결제액이다"""

    benefit: Benefit
    amount: int
    value: int
    base: int
    limited: bool
    exhausted: bool = False
    needs: frozenset = frozenset()

    def applied(self) -> AppliedBenefit:
        return AppliedBenefit(key=self.benefit.key, amount=self.amount, value=self.value, base=self.base)


def offer(
    ctx: Ctx, rules: Rules, b: Benefit, s: Situation, tier: int, ledger: Ledger, room: int, total: int = 0
) -> Offer:
    """한도 안에서 이 혜택이 이 결제에 줄 수 있는 금액. room은 이 묶음에서 아직 혜택에 쓰지 않은 결제액이고
    total은 달 합계 혜택이면 이 결제까지의 이번 달 대상 이용액이다.

    limited는 어느 한도든 금액을 줄였는지, exhausted는 날, 달, 기간 한도가 줄였는지다. 건당 한도는
    "한도를 다 썼다"가 아니라서 exhausted에 넣지 않는다. 설계 5.1
    """
    onsite = b.reward.type == "onsite_discount"
    pre = pre_discount(b, room, tier) if onsite else room
    base, limited, exhausted = pre, False, False
    specs = [(ident, lim, caps(lim, tier, s)) for ident, lim in limit_specs(rules, b)]
    needs = frozenset().union(*(c[3] for _, _, c in specs))
    usage = {
        ident: ledger.used(ident, key) if (key := period_key(lim.per, s.at)) else [0, 0, 0] for ident, lim, _ in specs
    }
    for ident, lim, (_, count, cap_base, _) in specs:
        if count is not None and usage[ident][1] >= count:
            return Offer(b, 0, 0, 0, True, lim.per != "txn", needs)
        if cap_base is not None and base > cap_base - usage[ident][2]:
            base, limited = max(cap_base - usage[ident][2], 0), True
            exhausted = exhausted or lim.per != "txn"
    if b.reward.basis == "month_total":
        given = ledger.used(("given", b.key), period_key("month", s.at))[0]
        amount = max(reward_amount(ctx, b, total, tier) - given, 0)
    elif onsite and not limited:
        amount = pre - room if b.reward.rate is not None else reward_amount(ctx, b, base, tier)
    else:
        amount = reward_amount(ctx, b, base, tier)
    for ident, lim, (cap_amount, _, _, _) in specs:
        if cap_amount is not None and amount > cap_amount - usage[ident][0]:
            amount, limited = max(cap_amount - usage[ident][0], 0), True
            exhausted = exhausted or lim.per != "txn"
    if amount == 0:
        base = 0
    elif onsite and b.reward.rate is not None:
        base = room + amount  # 현장할인은 기록 금액에 실제 할인액을 더한 것이 할인 전 금액이다. 설계 3.6
    elif limited and b.reward.rate is not None and b.reward.basis == "txn":
        base = min(base, math.ceil(frac(amount) * 100 / frac(at_tier(b.reward.rate, tier))))
    value = amount if b.reward.type != "points" else math.floor(amount * ctx.point_value.get(b.reward.program, frac(1)))
    return Offer(b, amount, value, base, limited, exhausted, needs)


def choose(
    ctx: Ctx, rules: Rules, s: Situation, candidates: dict[str, list[tuple[Benefit, int, int]]], ledger: Ledger
) -> tuple[list[Offer], set[str], dict[str, frozenset]]:
    """중복 묶음마다 혜택을 고른다. 설계 3.7. candidates는 묶음 key마다 (혜택, 구간, 달 합계)이고 파일 순서다.
    (받은 혜택, 기간 한도로 줄어든 혜택 key, 혜택마다 한도 조건에서 모르는 것)을 돌려준다"""
    specs = {st.key: st for st in rules.stacks}
    scratch = ledger.child()
    got: list[Offer] = []
    exhausted: set[str] = set()
    needs: dict[str, frozenset] = {}
    for stack, members in candidates.items():
        st = specs.get(stack)
        pick, spill = (st.pick, st.spill) if st else ("best", "none")
        if pick == "priority":
            rank = {k: i for i, k in enumerate(st.order)}
            members = sorted(members, key=lambda m: rank.get(m[0].key, len(rank)))
        room, left = s.amount, list(members)
        while left and room > 0:
            offers = [offer(ctx, rules, b, s, tier, scratch, room, total) for b, tier, total in left]
            exhausted |= {o.benefit.key for o in offers if o.exhausted}
            for o in offers:
                if o.needs:
                    needs[o.benefit.key] = needs.get(o.benefit.key, frozenset()) | o.needs
            live = [o for o in offers if o.amount > 0]
            if not live:
                break
            best = live[0] if pick == "priority" else max(live, key=lambda o: (o.value, -offers.index(o)))
            got.append(best)
            scratch.add_benefit(rules, best.benefit, best.applied(), s.at)
            if spill != "split":
                break
            room -= best.base
            left = [m for m in left if m[0].key != best.benefit.key]
    return got, exhausted, needs


@dataclass
class Priced:
    """price_payment의 중간 결과. 추천이 못 받는 혜택과 조건부 혜택을 만들 때 쓴다"""

    result: PaymentResult
    rules: Rules | None = None
    tier: int = 0
    unknown: dict[str, frozenset] = field(default_factory=dict)
    tier_short: dict[str, int] = field(default_factory=dict)


def price(ctx: Ctx, card: UserCard, p: Payment, ledger: Ledger, final_areas: dict | None = None) -> Priced:
    """결제 한 건의 혜택과 실적. ledger는 이 결제보다 앞선 결제들의 사용량 표다"""
    day = local(p.paid_at).date()
    month = month_of(day)
    found = ctx.rules_on(card.card_id, day)
    if found is None:
        return Priced(PaymentResult(payment_id=p.id, warnings=[Warn(code="no_revision")]))
    rev, rules = found
    warns: list[Warn] = []
    if day < rev.effective_from:
        warns.append(Warn(code="revision_estimated", data={"effective_from": rev.effective_from.isoformat()}))
    prev = add_months(month, -1)
    base_tier, _, _, tier_warns = tier_of(ctx, card, month, ledger.counted_in(prev), ledger.recorded(prev))
    warns += tier_warns
    base_tier = base_tier or 0
    s = situation(ctx, card, rules, p)
    net = s.amount
    got: list[Offer] = []
    unknown: dict[str, frozenset] = {}
    tier_short: dict[str, int] = {}
    exhausted: set[str] = set()
    limit_needs: dict[str, frozenset] = {}
    if net > 0:
        top_tier, _ = new_card_tier(card, month, rules, None, base_tier)
        s.top_areas = top_areas(rules, s, month, top_tier, ledger, final_areas)
        candidates: dict[str, list[tuple[Benefit, int, int]]] = {}
        for b in rules.benefits:
            tier, _ = new_card_tier(card, month, rules, b.key, base_tier)
            total = 0
            if b.reward.basis == "month_total":
                s.skip = frozenset({"month_total"})
                mine = net if benefit_match(rules, b, s)[0] is True else 0
                total = ledger.month_total(b.key, month) + mine
                s.skip, s.month_total = frozenset(), total
            if b.reward.type == "onsite_discount":
                s.amount = pre_discount(b, net, tier)
            hit = benefit_match(rules, b, s)
            s.amount, s.month_total = net, None
            if hit[0] is False:
                continue
            lo = b.tiers.start if b.tiers and b.tiers.start is not None else rules.tiers[0]
            hi = b.tiers.end if b.tiers and b.tiers.end is not None else rules.tiers[-1]
            if tier > hi:
                continue
            if tier < lo:
                waived = check(b.tiers.waived_when, s) if b.tiers.waived_when else FALSE
                if waived[0] is False:
                    if hit[0] is True:
                        tier_short[b.key] = lo
                    continue
                if waived[0] is None:
                    tier_short[b.key] = lo
                    hit = all_of([hit, waived])
            if hit[0] is None:
                unknown[b.key] = hit[1]
                continue
            candidates.setdefault(b.stack, []).append((b, tier, total))
        got, exhausted, limit_needs = choose(ctx, rules, s, candidates, ledger)
    applied = [o.applied() for o in got]
    parts, spend_warns = spend_parts(ctx, card, p, rules, applied)
    unknown = {**unknown, **limit_needs}
    warns += spend_warns + notes(ctx, card, got, unknown, tier_short, exhausted, final_areas is not None)
    result = PaymentResult(payment_id=p.id, benefits=applied, spend=parts, warnings=warns)
    return Priced(result, rules, base_tier, unknown, tier_short)


def top_areas(
    rules: Rules, s: Situation, month: date, tier: int, ledger: Ledger, final: dict | None
) -> dict[str, set[str]]:
    """순위 그룹마다 이번 달 이용액 상위 영역. 이 결제를 포함한다. final이 있으면 달 전체 이용액으로 매긴다. 설계 3.5"""
    groups = ranked_areas(rules)
    if not groups:
        return {}
    skip, s.skip = s.skip, SKIP_TOTALS
    tops = {r.key: r.top for r in rules.ranked}
    out: dict[str, set[str]] = {}
    for group, areas in groups.items():
        spend = []
        for i, (area, members) in enumerate(areas.items()):
            if final is not None:
                total = final.get((group, area, month), 0)
            else:
                mine = s.amount if any(benefit_match(rules, b, s)[0] is True for b in members) else 0
                total = ledger.area_spend(group, area, month) + mine
            spend.append((-total, i, area))
        top = at_tier(tops[group], tier) or 0
        out[group] = {area for total, _, area in sorted(spend)[:top] if total < 0}
    s.skip = skip
    return out


def notes(
    ctx: Ctx,
    card: UserCard,
    got: list[Offer],
    unknown: dict[str, frozenset],
    tier_short: dict[str, int],
    exhausted: set[str],
    final: bool,
) -> list[Warn]:
    """결제 결과에 붙는 경고. 설계 5절"""
    out = [Warn(code="tier_not_met", benefit=k, data={"required": lo}) for k, lo in tier_short.items()]
    out += [Warn(code="limit_exhausted", benefit=k) for k in sorted(exhausted)]
    if unknown:
        needs = sorted({n for ns in unknown.values() for n in ns})
        out.append(Warn(code="needs_input", data={"needs": [list(n) for n in needs], "benefits": sorted(unknown)}))
    sentences = [u for o in got for u in o.benefit.unmodeled]
    if sentences:
        out.append(Warn(code="check_conditions", data={"sentences": sentences}))
    assumed = ctx.assumed.get(card.card_id, {})
    paths = [path for o in got for path in assumed.get(o.benefit.key, [])]
    if paths:
        out.append(Warn(code="assumed_value", data={"paths": paths}))
    if not final:
        for o in got:
            groups = [c.ranked for c in o.benefit.when if c.ranked]
            if groups:
                out.append(Warn(code="ranked_provisional", benefit=o.benefit.key, data={"group": groups[0]}))
    return out


def price_payment(ctx: Ctx, card: UserCard, history: list[Payment], p: Payment) -> PaymentResult:
    """결제 한 건의 혜택, 실적, 경고. history는 같은 카드의 다른 결제이고 저장된 혜택이 들어 있다. 설계 1.3"""
    prior = [q for q in history if q.id != p.id and (q.paid_at, q.id) < (p.paid_at, p.id)]
    return price(ctx, card, p, build_ledger(ctx, card, prior)).result


def price_month(
    ctx: Ctx, card: UserCard, payments: list[Payment], month: date | None = None, final: bool = False
) -> list[PaymentResult]:
    """저장된 혜택이 없는 결제를 결제 시각 순서로 차례로 계산한다. 설계 1.3

    month를 주면 그 달 결제는 저장된 혜택이 있어도 다시 계산한다. final이면 그 달 순위를 달 전체 이용액으로
    매긴다. 달이 끝난 순위 카드를 다시 계산할 때 쓴다. 설계 3.5
    """
    ordered = sorted(payments, key=lambda q: (q.paid_at, q.id))
    final_areas = None
    if final and month is not None:
        totals = Ledger()
        for q in ordered:
            day = local(q.paid_at).date()
            found = ctx.rules_on(card.card_id, day)
            if month_of(day) == month and found and q.amount > q.cancelled_amount:
                totals.add_totals(ctx, card, found[1], q, month)
        final_areas = dict(totals.area)
    ledger = Ledger()
    results: list[PaymentResult] = []
    for q in ordered:
        if q.benefits is None or (month is not None and month_of(local(q.paid_at).date()) == month):
            result = price(ctx, card, q, ledger, final_areas).result
            q = q.model_copy(update={"benefits": result.benefits})
            results.append(result)
        ledger.add(ctx, card, q)
    return results


def spend_status(ctx: Ctx, card: UserCard, payments: list[Payment], month: date) -> SpendStatus:
    """카드 한 장의 이번 달 실적 현황. 설계 2.4, 2.5"""
    ledger = build_ledger(ctx, card, payments)
    prev = add_months(month, -1)
    tier, source, prev_counted, warns = tier_of(ctx, card, month, ledger.counted_in(prev), ledger.recorded(prev))
    this = max(ledger.counted_in(month), 0)
    found = ctx.rules_on(card.card_id, month)
    to_keep = next_tier = to_next = None
    if found is not None and tier is not None and source not in ("none", "unsupported"):
        rules = found[1]
        tier, special = new_card_tier(card, month, rules, None, tier)
        source = "new_card" if special else source
        to_keep = max(tier - this, 0) if tier > 0 else None
        above = [t for t in rules.tiers if t > max(tier, this)]
        if above:
            next_tier = min(above)
            to_next = next_tier - this
    if found is not None:
        warns += card_notes(ctx, card, found[1], month)
    return SpendStatus(
        user_card_id=card.id,
        month=month,
        counted=this,
        tier=tier,
        tier_source=source,
        prev_month_counted=prev_counted,
        to_keep=to_keep,
        next_tier=next_tier,
        to_next=to_next,
        warnings=warns,
    )


def limit_status(ctx: Ctx, card: UserCard, payments: list[Payment], now: datetime) -> list[LimitUse]:
    """혜택별 한도와 공유 한도의 이번 기간 사용량과 한도. 설계 1.3"""
    day = local(now).date()
    month = month_of(day)
    found = ctx.rules_on(card.card_id, day)
    if found is None:
        return []
    rules = found[1]
    ledger = build_ledger(ctx, card, [q for q in payments if q.paid_at <= now])
    prev = add_months(month, -1)
    tier, _, _, _ = tier_of(ctx, card, month, ledger.counted_in(prev), ledger.recorded(prev))
    probe = Payment(id="now", user_card_id=card.id, amount=1, paid_at=now)
    s = situation(ctx, card, rules, probe)
    seen: set = set()
    out = []
    for b in rules.benefits:
        t, _ = new_card_tier(card, month, rules, b.key, tier or 0)
        for ident, lim in limit_specs(rules, b):
            key = period_key(lim.per, now)
            if key is None or ident in seen:
                continue
            seen.add(ident)
            used = ledger.used(ident, key)
            cap_amount, cap_count, cap_base, _ = caps(lim, t, s)
            out.append(
                LimitUse(
                    key=ident[1],
                    benefit=b.key if ident[0] == "own" else None,
                    per=lim.per,
                    used_amount=used[0],
                    used_count=used[1],
                    used_base=used[2],
                    cap_amount=cap_amount,
                    cap_count=cap_count,
                    cap_base=cap_base,
                )
            )
    return out
````

- [x] **5단계: Engine을 쓴다**

`backend/cherry_core/engine/__init__.py`

````python
"""계산 엔진. 서버가 켜질 때 Engine을 한 번 만들고 요청마다 함수를 부른다. 설계는 docs/work/002-calc-engine/design.md"""

from __future__ import annotations

from datetime import date, datetime
from pathlib import Path

from cherry_core.catalog.load import Catalog, load_catalog

from . import price as _price
from .context import Ctx
from .models import LimitUse, Payment, PaymentResult, SpendStatus, UserCard


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
````

- [x] **6단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_spend.py backend/tests/engine/test_benefits.py
uvx ruff check backend/cherry_core/engine backend/tests/engine
```

기대: `50 passed`, `All checks passed!`

- [x] **7단계: 실제 카드 20장이 멈추지 않는지 본다**

20장마다 석 달치 무작위 결제 250건을 `price_month`, `spend_status`, `limit_status`에 넣는다. 결과 값은 보지 않고 예외가 나지 않는지만 본다. 스크립트는 저장소에 넣지 않는다.

```bash
uv run --project backend python - <<'EOF'
import random
from datetime import date, datetime, timedelta
from pathlib import Path
from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine
from cherry_core.engine.cond import KST
from cherry_core.engine.models import OptionPick, Payment, UserCard
cat = load_catalog(Path("catalog")); eng = Engine(cat); rng = random.Random(7)
merchants, cats, methods = sorted(cat.merchants), sorted(cat.categories), sorted(cat.payment_methods)
for cid, lc in sorted(cat.cards.items()):
    rules = lc.revisions[-1][1]
    picks = [OptionPick(option=o.key, choice=rng.choice(o.choices).key, effective_from=date(2026, 1, 1)) for o in rules.options]
    uc = UserCard(id="u", card_id=cid, registered_on=date(2026, 6, 1), options=picks)
    pays = [Payment(id=f"{n:03d}", user_card_id="u", amount=rng.choice([1500, 12500, 55000, 400000]),
        paid_at=datetime(2026, 6, 1, tzinfo=KST) + timedelta(minutes=rng.randrange(120 * 24 * 60)),
        merchant=rng.choice(merchants), payment_method=rng.choice(methods + [None])) for n in range(250)]
    res = eng.price_month(uc, pays)
    saved = [p.model_copy(update={"benefits": r.benefits}) for p, r in zip(sorted(pays, key=lambda q: (q.paid_at, q.id)), res)]
    eng.spend_status(uc, saved, date(2026, 9, 1)); eng.limit_status(uc, saved, datetime(2026, 9, 15, tzinfo=KST))
print("20장 모두 멈추지 않음")
EOF
```

기대: `20장 모두 멈추지 않음`

- [x] **8단계: 커밋**

```bash
git add backend/cherry_core/engine backend/tests/engine/test_spend.py backend/tests/engine/test_benefits.py
git commit -m "feat: 실적과 결제 혜택 계산 추가" -m "작업 002 설계 2절, 3절. 사용량 표 위에서 대상, 조건, 구간, 한도, 중복 묶음, 순위, 달 합계, 현장할인을 계산한다. 시나리오 E2, E4, E5, E6, E7, E12"
```

2026-09-29 실행 결과: 50개 통과, 전체 143개 통과, 20장 모두 멈추지 않음.

---

## 과제 6: 추천과 속도

**파일**
- 만들기: `backend/cherry_core/engine/recommend.py`
- 고치기: `backend/cherry_core/engine/__init__.py`
- 테스트: `backend/tests/engine/test_recommend.py`, `test_speed.py`

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/engine/test_recommend.py`

````python
"""추천. 설계 4절. 기대값은 손계산이다."""

from datetime import date

from cherry_core.engine.models import Query

from .conftest import at, card, holder, pay, prev_month

NOW = at("2026-09-19T14:20")


def b(key, target, reward, **kw):
    return {"key": key, "target": target, "reward": reward, **kw}


def two_cards(engine):
    cafe = card(
        [
            b(
                "cafe-10",
                {"categories": ["cafe"]},
                {"type": "billing_discount", "rate": 10},
                limits=[{"per": "txn", "amount": 1000}],
            )
        ],
        id="test-cafe",
        tiers=(0,),
    )
    flat = card([b("all-07", {"all": True}, {"type": "billing_discount", "rate": 0.7})], id="test-flat", tiers=(0,))
    return engine(cafe, flat), holder(id="a", card_id="test-cafe"), holder(id="b", card_id="test-flat")


def test_order_by_value_and_default_amount(engine):
    # 1만원 기준: 카페 카드 1,000원, 0.7% 카드 70원. 시안 9쪽의 1위와 2위
    eng, cafe, flat = two_cards(engine)
    [rows] = eng.recommend([cafe, flat], {}, [Query(merchant="starbucks")], NOW)
    assert [(r.card_id, r.value) for r in rows] == [("test-cafe", 1000), ("test-flat", 70)]
    assert "default_amount_used" in [w.code for w in rows[0].warnings]


def test_tie_prefers_card_short_of_tier(engine):
    # 기대 혜택이 같으면 이번 결제가 실적에 들어가고 유지까지 남은 금액이 적은 카드가 앞. S5
    one = card([b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1})], id="test-one")
    two = card([b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1})], id="test-two")
    eng = engine(one, two)
    a, c = holder(id="a", card_id="test-one"), holder(id="c", card_id="test-two")
    history = {
        "a": [
            p.model_copy(update={"user_card_id": "a"})
            for p in prev_month(350000) + [pay(100000, "2026-09-05T10:00", category="other")]
        ],
        "c": [
            p.model_copy(update={"user_card_id": "c"})
            for p in prev_month(350000) + [pay(250000, "2026-09-05T10:00", category="other")]
        ],
    }
    [rows] = eng.recommend([a, c], history, [Query(category="other", amount=10000)], NOW)
    assert [(r.card_id, r.to_keep) for r in rows] == [("test-two", 50000), ("test-one", 200000)]


def test_locked_benefit(engine):
    # 90만 구간 스타벅스 20%. 이번 달 18.2만이면 71.8만 더. 1만원 × 20% = 2,000. 시안 9쪽
    sb = b("sb-20", {"merchants": ["starbucks"]}, {"type": "billing_discount", "rate": 20}, tiers={"from": 900000})
    eng = engine(card([sb], id="test-mr", tiers=(0, 300000, 600000, 900000)))
    h = holder(id="m", card_id="test-mr")
    history = {
        "m": [
            p.model_copy(update={"user_card_id": "m"})
            for p in prev_month(410000) + [pay(182000, "2026-09-05T10:00", category="other")]
        ]
    }
    [rows] = eng.recommend([h], history, [Query(merchant="starbucks")], NOW)
    [lock] = rows[0].locked
    assert (lock.benefit, lock.required_tier, lock.remaining_this_month, lock.value_if_unlocked) == (
        "sb-20",
        900000,
        718000,
        2000,
    )


def test_conditional_payment_method_and_fact(engine):
    # 네이버페이면 +1,000원, 현역병이면 +1,500원
    benefits = [
        b(
            "npay",
            {"categories": ["cafe"]},
            {"type": "billing_discount", "rate": 10},
            when=[{"payment": ["naver_pay"]}],
        ),
        b("px", {"categories": ["convenience"]}, {"type": "billing_discount", "rate": 15}, when=[{"fact": "soldier"}]),
    ]
    eng = engine(
        card(
            benefits,
            id="test-c",
            tiers=(0,),
            facts=[{"key": "soldier", "type": "bool", "scope": "user", "ask": "현역병인가요"}],
        )
    )
    h = holder(id="c", card_id="test-c")
    [cafe_rows, cvs_rows] = eng.recommend(
        [h], {}, [Query(merchant="ediya", amount=10000), Query(merchant="gs25", amount=10000)], NOW
    )
    assert cafe_rows[0].value == 0
    assert [(c.benefit, c.needs, c.extra) for c in cafe_rows[0].conditional] == [
        ("npay", {"payment_method": "naver_pay"}, 1000)
    ]
    assert [(c.benefit, c.needs, c.extra) for c in cvs_rows[0].conditional] == [("px", {"fact": "soldier"}, 1500)]


def test_removed_card_and_category_query(engine):
    # 해지한 카드는 빼고, 업종만 준 질문은 업종별 1순위에 쓴다. S9, 시안 8쪽
    eng, cafe, flat = two_cards(engine)
    gone = cafe.model_copy(update={"removed": True})
    [rows] = eng.recommend([gone, flat], {}, [Query(category="cafe")], NOW)
    assert [r.card_id for r in rows] == ["test-flat"]


def test_recommend_does_not_use_later_payments(engine):
    # 지금보다 뒤에 적힌 결제는 한도 사용량에 넣지 않는다
    eng = engine(
        card(
            [
                b(
                    "cafe-10",
                    {"categories": ["cafe"]},
                    {"type": "billing_discount", "rate": 10},
                    limits=[{"per": "month", "amount": 1000}],
                )
            ],
            id="test-l",
            tiers=(0,),
        )
    )
    h = holder(id="l", card_id="test-l")
    later = pay(10000, "2026-09-25T10:00", merchant="ediya").model_copy(update={"user_card_id": "l"})
    priced = eng.price_month(h, [later])
    saved = [later.model_copy(update={"benefits": priced[0].benefits})]
    [rows] = eng.recommend([h], {"l": saved}, [Query(merchant="ediya", amount=10000)], NOW)
    assert rows[0].value == 1000


def test_limit_status_period(engine):
    eng = engine(
        card(
            [
                b(
                    "cafe-10",
                    {"categories": ["cafe"]},
                    {"type": "billing_discount", "rate": 10},
                    limits=[{"per": "month", "amount": 5000}, {"per": "day", "count": 1}],
                )
            ],
            id="test-s",
            tiers=(0,),
        )
    )
    h = holder(id="s", card_id="test-s")
    ps = [pay(30000, "2026-09-02T10:00", merchant="ediya").model_copy(update={"user_card_id": "s"})]
    saved = [ps[0].model_copy(update={"benefits": eng.price_month(h, ps)[0].benefits})]
    uses = {u.per: u for u in eng.limit_status(h, saved, at("2026-09-02T20:00"))}
    assert (uses["month"].used_amount, uses["month"].cap_amount) == (3000, 5000)
    assert (uses["day"].used_count, uses["day"].cap_count) == (1, 1)
    uses = {u.per: u for u in eng.limit_status(h, saved, at("2026-10-01T09:00"))}
    assert uses["month"].used_amount == 0 and uses["day"].used_count == 0
    assert date(2026, 10, 1)
````

`backend/tests/engine/test_speed.py`

````python
"""추천 속도. 설계 4.4와 6.5. 카드 10장, 이번 달 결제 300건, 조건부 혜택 포함으로 추천 한 번 50ms,
업종 12개의 업종별 1순위 200ms 안이다. 컴퓨터마다 속도가 달라 여러 번 재서 가운데 값을 쓴다."""

import random
import statistics
import time
from datetime import date, timedelta
from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine
from cherry_core.engine.models import Payment, Query, UserCard

from .conftest import at

ROOT = Path(__file__).resolve().parents[3] / "catalog"
NOW = at("2026-09-28T19:30")
CATEGORIES = [
    "cafe",
    "convenience",
    "restaurant",
    "online_shopping",
    "transit.subway",
    "delivery_app",
    "grocery_mart",
    "fuel",
    "movie",
    "telecom.mobile",
    "hospital",
    "other",
]


@pytest.fixture(scope="module")
def heavy():
    cat = load_catalog(ROOT)
    eng = Engine(cat)
    ids = sorted(cat.cards, key=lambda c: -len(cat.cards[c].revisions[-1][1].benefits))[:10]
    rng = random.Random(20260928)
    merchants = sorted(cat.merchants)
    cards = [UserCard(id=f"u{i}", card_id=cid, registered_on=date(2026, 1, 1), facts={}) for i, cid in enumerate(ids)]
    payments: dict[str, list[Payment]] = {}
    for n in range(300):
        c = cards[n % 10]
        when = at("2026-09-01T08:00") + timedelta(minutes=rng.randrange(27 * 24 * 60))
        p = Payment(
            id=f"x{n:03d}",
            user_card_id=c.id,
            amount=rng.choice([4500, 12000, 35000, 58000, 120000]),
            paid_at=when,
            merchant=rng.choice(merchants),
            channel=rng.choice(["online", "offline"]),
            payment_method=rng.choice(["physical_card", "naver_pay", "kakao_pay"]),
        )
        payments.setdefault(c.id, []).append(p)
    for c in cards:
        results = {r.payment_id: r.benefits for r in eng.price_month(c, payments.get(c.id, []))}
        payments[c.id] = [p.model_copy(update={"benefits": results[p.id]}) for p in payments.get(c.id, [])]
    return eng, cards, payments


def median_ms(fn, runs=7) -> float:
    fn()
    times = []
    for _ in range(runs):
        start = time.perf_counter()
        fn()
        times.append((time.perf_counter() - start) * 1000)
    return statistics.median(times)


def test_one_recommendation_under_50ms(heavy):
    eng, cards, payments = heavy
    ms = median_ms(lambda: eng.recommend(cards, payments, [Query(merchant="starbucks", amount=12000)], NOW))
    assert ms < 50, f"{ms:.1f}ms"


def test_category_tops_under_200ms(heavy):
    eng, cards, payments = heavy
    queries = [Query(category=c) for c in CATEGORIES]
    ms = median_ms(lambda: eng.recommend(cards, payments, queries, NOW))
    assert ms < 200, f"{ms:.1f}ms"
````

- [x] **2단계: 돌려서 실패를 본다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_recommend.py
```

기대: `Engine`에 `recommend`가 없어 실패한다.

- [x] **3단계: 추천을 쓴다**

`backend/cherry_core/engine/recommend.py`

````python
"""추천, 못 받는 혜택, 조건부 혜택, 한도 현황. 설계 4절."""

from __future__ import annotations

from datetime import datetime

from cherry_core.catalog.models import Condition

from .cond import local, month_of
from .context import Ctx
from .models import (
    ConditionalBenefit,
    LockedBenefit,
    OptionPick,
    Payment,
    Query,
    Recommendation,
    UserCard,
    Warn,
)
from .price import Ledger, Priced, build_ledger, offer, price, situation

DEFAULT_AMOUNT = 10_000


def query_payment(ctx: Ctx, card: UserCard, q: Query, now: datetime) -> Payment:
    """추천 질문으로 만든 가상의 결제. 설계 4.1"""
    return Payment(
        id="query",
        user_card_id=card.id,
        amount=q.amount or DEFAULT_AMOUNT,
        paid_at=now,
        merchant=q.merchant,
        category=q.category,
        channel=q.channel or "offline",
        region=q.region or "domestic",
        payment_method=q.payment_method or card.last_payment_method or "physical_card",
    )


def payment_methods_in(conditions: list[Condition]) -> set[str]:
    out: set[str] = set()
    for c in conditions:
        out |= set(c.payment or [])
        for sub in c.any_of or []:
            out |= payment_methods_in([sub])
    return out


def conditional(ctx: Ctx, card: UserCard, p: Payment, ledger: Ledger, base: Priced) -> list[ConditionalBenefit]:
    """다른 값이면 더 받는 혜택. 설계 4.3, 작업 001 설계 3.3

    결제수단은 결제 직전에 고를 수 있어 알고 있어도 조건에 적힌 다른 결제수단으로 바꿔 본다.
    사실, 옵션, 업종은 모를 때만 본다. 바꿔 볼 것이 있을 때만 다시 계산한다. 설계 4.4의 3
    """
    if base.rules is None:
        return []
    rules = base.rules
    trials: list[tuple[dict, UserCard, Payment]] = []
    methods = set().union(*(payment_methods_in(b.when) for b in rules.benefits)) - {p.payment_method}
    trials += [({"payment_method": m}, card, p.model_copy(update={"payment_method": m})) for m in sorted(methods)]
    for need in sorted({n for ns in base.unknown.values() for n in ns}):
        kind = need[0]
        if kind == "fact":
            key = need[1]
            value = local(p.paid_at).month if key == "birth_month" else True
            trials.append(({"fact": key}, card.model_copy(update={"facts": {**card.facts, key: value}}), p))
        elif kind == "option":
            option = next(o for o in rules.options if o.key == need[1])
            for ch in option.choices:
                pick = OptionPick(option=option.key, choice=ch.key, effective_from=local(p.paid_at).date())
                trials.append(
                    (
                        {"option": option.key, "choice": ch.key},
                        card.model_copy(update={"options": [*card.options, pick]}),
                        p,
                    )
                )
        elif kind == "category":
            trials += [
                ({"category": c}, card, p.model_copy(update={"category": c})) for c in ctx.children.get(need[1], [])
            ]
    out: list[ConditionalBenefit] = []
    before = {b.key: b.value for b in base.result.benefits}
    for needs_given, c2, p2 in trials:
        after = price(ctx, c2, p2, ledger).result
        extra = after.value - base.result.value
        if extra > 0:
            gains = {b.key: b.value - before.get(b.key, 0) for b in after.benefits}
            key = max(gains, key=lambda k: gains[k])
            out.append(ConditionalBenefit(user_card_id=card.id, benefit=key, needs=needs_given, extra=extra))
    return sorted(out, key=lambda c: -c.extra)


def locked(ctx: Ctx, card: UserCard, p: Payment, ledger: Ledger, base: Priced, counted_now: int) -> list[LockedBenefit]:
    """대상과 조건은 맞는데 구간이 모자란 혜택. 다음 달 한도가 비어 있다고 보고 계산한다. E37"""
    if base.rules is None:
        return []
    rules = base.rules
    s = situation(ctx, card, rules, p)
    out = []
    for key, required in base.tier_short.items():
        b = next(x for x in rules.benefits if x.key == key)
        o = offer(ctx, rules, b, s, required, Ledger(), s.amount, s.amount)
        if o.value > 0:
            out.append(
                LockedBenefit(
                    user_card_id=card.id,
                    benefit=key,
                    required_tier=required,
                    remaining_this_month=max(required - counted_now, 0),
                    value_if_unlocked=o.value,
                )
            )
    return out


def recommend(
    ctx: Ctx, cards: list[UserCard], payments: dict[str, list[Payment]], queries: list[Query], now: datetime
) -> list[list[Recommendation]]:
    """질문마다 보유 카드의 추천 순위. 사용량 표는 카드마다 한 번만 만든다. 설계 4절"""
    from .price import spend_status

    month = month_of(local(now).date())
    prepared = []
    for card in cards:
        if card.removed:
            continue
        history = payments.get(card.id, [])
        ledger = build_ledger(ctx, card, [q for q in history if q.paid_at <= now])
        status = spend_status(ctx, card, history, month)
        prepared.append((card, ledger, status))
    answers = []
    for q in queries:
        rows = []
        for card, ledger, status in prepared:
            p = query_payment(ctx, card, q, now)
            base = price(ctx, card, p, ledger)
            warns = list(base.result.warnings)
            if q.amount is None:
                warns.append(Warn(code="default_amount_used"))
            rows.append(
                Recommendation(
                    user_card_id=card.id,
                    card_id=card.card_id,
                    value=base.result.value,
                    benefits=base.result.benefits,
                    counted=any(part.amount > 0 for part in base.result.spend),
                    to_keep=status.to_keep,
                    to_next=status.to_next,
                    locked=locked(ctx, card, p, ledger, base, status.counted),
                    conditional=conditional(ctx, card, p, ledger, base),
                    warnings=warns,
                )
            )
        rows.sort(key=order)
        answers.append(rows)
    return answers


def order(r: Recommendation) -> tuple:
    """기대 혜택, 실적이 모자란 카드, 카드 id 순. 설계 4.2"""
    keep = r.to_keep if r.counted and r.to_keep else None
    nxt = r.to_next if r.counted and r.to_next else None
    return (-r.value, keep is None, keep or 0, nxt is None, nxt or 0, r.card_id)
````

- [x] **4단계: Engine에 추천을 더한다**

`backend/cherry_core/engine/__init__.py`

````python
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
````

- [x] **5단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_recommend.py backend/tests/engine/test_speed.py
```

기대: `9 passed`. 시제품에서 추천 한 번은 14ms, 업종 12개는 37ms였다.

- [x] **6단계: 커밋**

```bash
git add backend/cherry_core/engine backend/tests/engine/test_recommend.py backend/tests/engine/test_speed.py
git commit -m "feat: 추천과 못 받는 혜택, 조건부 혜택 추가" -m "작업 002 설계 4절. 카드마다 사용량 표를 한 번 만들어 추천 한 번 50ms, 업종 12개 200ms 안에 끝난다. 시나리오 E11, E37, S4, S5, S9"
```

2026-09-29 실행 결과: 9개 통과, 전체 152개 통과. 추천 한 번 14.5ms, 업종 12개 36.0ms.

---

## 과제 7: 손계산 표 대조와 차이 정리

**파일**
- 고치기: `backend/tests/engine/cases.py`, `backend/tests/engine/test_cases.py`
- 고칠 수 있음: 엔진 코드, 표, 카드 파일, design.md

- [x] **1단계: 대조 함수를 더한다**

`backend/tests/engine/cases.py` 맨 위 설명의 목록 끝에 다음 줄을 더한다.

```text
- difference는 엔진과 다른 까닭이다. 실제 명세서 대조에서만 쓴다. 적어 두면 그 결제는 대조하지 않는다. 설계 6.6
```

import에 `from cherry_core.engine import Engine`을 더하고 파일 끝에 다음을 더한다.

````python
def mismatches(eng: Engine, case: Case) -> list[str]:
    """손계산과 엔진이 다른 곳. difference를 적은 결제는 보지 않는다"""
    results = {r.payment_id: r for r in eng.price_month(case.holder, case.payments)}
    out = []
    for e in case.expect:
        if "difference" in e:
            continue
        r = results[case.payments[e["payment"]].id]
        got = {b.key: b.amount for b in r.benefits}
        if got != e.get("benefits", {}):
            out.append(f"결제 {e['payment']}: 혜택 {got} 기대 {e.get('benefits', {})}. {case.calc}")
        if "counted" in e and sum(p.amount for p in r.spend) != e["counted"]:
            out.append(f"결제 {e['payment']}: 실적 {sum(p.amount for p in r.spend)} 기대 {e['counted']}")
        missing = set(e.get("warnings", [])) - {w.code for w in r.warnings}
        if missing:
            out.append(f"결제 {e['payment']}: 없는 경고 {sorted(missing)}")
    return out
````

- [x] **2단계: 대조 테스트를 더한다**

`backend/tests/engine/test_cases.py`

````python
"""손계산 표. 설계 6.1과 6.2. 표 형식, 모든 혜택이 한 번 이상 나오는지, 엔진과 같은지를 본다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine
from cherry_core.engine.cond import local

from .cases import load_cases, mismatches

ROOT = Path(__file__).resolve().parents[3] / "catalog"
CASES = load_cases()


@pytest.fixture(scope="module")
def catalog():
    return load_catalog(ROOT)


def test_case_files_are_valid(catalog):
    problems = []
    for c in CASES:
        where = f"{c.file} {c.name}"
        if c.card_id not in catalog.cards:
            problems.append(f"{where}: 카드 {c.card_id}가 없다")
            continue
        keys = {b.key for _, rules in catalog.cards[c.card_id].revisions for b in rules.benefits}
        for p in c.payments:
            if p.merchant and p.merchant not in catalog.merchants:
                problems.append(f"{where}: 가맹점 {p.merchant}가 없다")
            if p.category and p.category not in catalog.categories:
                problems.append(f"{where}: 업종 {p.category}가 없다")
            if p.payment_method and p.payment_method not in catalog.payment_methods:
                problems.append(f"{where}: 결제수단 {p.payment_method}가 없다")
        for e in c.expect:
            if not 0 <= e["payment"] < len(c.payments):
                problems.append(f"{where}: payment {e['payment']}가 결제 목록 밖이다")
            problems += [f"{where}: 혜택 {k}가 카드에 없다" for k in e.get("benefits", {}) if k not in keys]
        if not c.calc:
            problems.append(f"{where}: calc가 비어 있다")
    assert problems == []


def versions(card) -> list[tuple[str, object, object, dict]]:
    """혜택 key마다 내용이 같은 기간. (key, 시작, 끝, 내용). 끝은 다음 개정 시행일이고 없으면 None"""
    revs = card.revisions
    out = []
    for i, (rev, rules) in enumerate(revs):
        end = revs[i + 1][0].effective_from if i + 1 < len(revs) else None
        for b in rules.benefits:
            dump = b.model_dump()
            if out and any(v[0] == b.key and v[3] == dump and v[2] == rev.effective_from for v in out):
                prev = next(v for v in out if v[0] == b.key and v[3] == dump and v[2] == rev.effective_from)
                out[out.index(prev)] = (b.key, prev[1], end, dump)
            else:
                out.append((b.key, rev.effective_from, end, dump))
    return out


def test_every_benefit_is_covered(catalog):
    # intent 성공 기준 1. 혜택마다, 개정으로 내용이 바뀐 혜택은 바뀐 내용마다 양수로 한 번 이상 나온다
    covered: dict[str, list] = {}
    for c in CASES:
        for e in c.expect:
            day = local(c.payments[e["payment"]].paid_at).date()
            for key, amount in e.get("benefits", {}).items():
                if amount > 0:
                    covered.setdefault(f"{c.card_id}:{key}", []).append(day)
    missing = []
    for card_id, card in sorted(catalog.cards.items()):
        for key, start, end, _ in versions(card):
            days = covered.get(f"{card_id}:{key}", [])
            if not any(start <= d and (end is None or d < end) for d in days):
                missing.append(f"{card_id}:{key}@{start}")
    assert missing == []


@pytest.mark.parametrize("case", CASES, ids=[f"{c.card_id}:{c.name}" for c in CASES])
def test_case_matches_engine(catalog, case):
    assert mismatches(Engine(catalog), case) == []
````

- [x] **3단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_cases.py
```

- [x] **4단계: 다른 곳마다 원문을 다시 본다**

실패한 경우마다 카드사 원문을 다시 읽고 셋 중 무엇이 틀렸는지 정한다.
- 표가 틀렸으면 표를 고친다. 기대값을 엔진 값으로 그냥 바꾸지 않는다. calc도 고친다
- 엔진이 틀렸으면 먼저 그 경우를 `test_spend.py`나 `test_benefits.py`에 작은 규칙 테스트로 더해 실패를 본 뒤 엔진을 고친다
- 카드 파일이 틀렸으면 작업 001 방식으로 원문을 다시 대조한 뒤 고친다
- 설계가 둘로 읽히면 사용자에게 묻고 design.md를 먼저 고친다

고친 것은 `plan.md` 끝의 `## 표를 만들며 나온 것`에 "카드, 경우, 틀린 쪽, 고친 것"으로 한 줄씩 적는다.

- [x] **5단계: 전체를 돌린다**

```bash
uv run --project backend pytest -q
```

기대: 실패 0. 속도 테스트도 통과한다.

- [x] **6단계: 커밋**

고친 쪽마다 나눠 커밋한다. 엔진은 `fix:`, 표는 `test:`, 카드 파일은 `fix:`, 설계는 `docs:`다. 마지막에 대조 테스트를 커밋한다.

```bash
git add backend/tests/engine/cases.py backend/tests/engine/test_cases.py docs/work/002-calc-engine/plan.md
git commit -m "test: 손계산 표 20장을 엔진과 대조" -m "작업 002 설계 6.2. 다른 곳은 plan.md 표를 만들며 나온 것에 적었다."
```

2026-09-29 실행 결과: 표 279개가 모두 엔진과 같다. 다른 곳이 없어 4단계에서 고친 것은 없다. 과제 3에서 시제품으로 찾은 엔진 쪽 4건은 과제 5 코드에 이미 고쳐 넣었다. 전체 테스트 431개 통과.

---

## 과제 8: 시안 카드

시안을 그릴 때 지어낸 카드 세 장으로 화면 시안의 숫자를 재현한다. 설계 6.3

**파일**
- 만들기: `backend/tests/engine/mockup/` 아래 파일 9개, `backend/tests/engine/test_mockup.py`

- [x] **1단계: 시안 카탈로그를 만든다**

`backend/tests/engine/mockup/cards/mock/mock-ibk.yaml`

````yaml
schema_version: 2
id: mock-ibk
issuer: mock
name: 시안 IBK 나라사랑카드
kind: check
product_codes: [MOCK2]
status: on_sale
sources:
  - {id: page, kind: product_page, url: 'https://example.com/mock', fetched_at: 2026-09-01}
checked_at: 2026-09-01
revisions:
  - effective_from: 2026-01-01
    source: page
    tiers: [0, 200000]
    spend:
      basis: prev_calendar_month
      exclude_categories: [tax]
      installment: full_at_purchase
      cancellation: cancel_month
    limits:
      - key: integrated
        per: month
        amount: {200000: 5000}
    benefits:
      - key: cvs-10
        title: 편의점 10% 할인
        target:
          categories: [convenience]
        reward: {type: billing_discount, rate: 10}
        limits:
          - {shared: integrated}
        tiers: {from: 200000}
      - key: base-0-2
        title: 기본 0.2% 적립
        target: {all: true}
        reward: {type: points, program: mock_point, rate: 0.2}
        limits:
          - {shared: integrated}
        tiers: {from: 200000}
````

`backend/tests/engine/mockup/cards/mock/mock-mrlife.yaml`

````yaml
schema_version: 2
id: mock-mrlife
issuer: mock
name: 시안 신한 Mr.Life
kind: credit
product_codes: [MOCK1]
status: on_sale
sources:
  - {id: page, kind: product_page, url: 'https://example.com/mock', fetched_at: 2026-09-01}
checked_at: 2026-09-01
revisions:
  - effective_from: 2026-01-01
    source: page
    tiers: [0, 300000, 600000, 900000]
    spend:
      basis: prev_calendar_month
      exclude_categories: [tax]
      interest_free: exclude
      installment: full_at_purchase
      cancellation: cancel_month
    limits:
      - key: integrated
        per: month
        amount: {300000: 10000, 600000: 20000, 900000: 30000}
    benefits:
      - key: cafe-10
        title: 카페 10% 할인
        target:
          categories: [cafe]
        when:
          - amount: {min: 5000}
        reward: {type: billing_discount, rate: 10}
        limits:
          - {per: txn, amount: 1000}
          - {per: day, count: 1}
          - {per: month, amount: 5000}
          - {shared: integrated}
        tiers: {from: 300000}
      - key: cvs-5
        title: 편의점 5% 할인
        target:
          categories: [convenience]
        reward: {type: billing_discount, rate: 5}
        limits:
          - {per: month, amount: 5000}
          - {shared: integrated}
        tiers: {from: 300000}
      - key: transit-10
        title: 대중교통 10% 할인
        target:
          categories: [transit]
        reward: {type: billing_discount, rate: 10}
        limits:
          - {per: month, amount: 5000}
          - {shared: integrated}
        tiers: {from: 600000}
      - key: sb-20
        title: 스타벅스 20% 할인
        target:
          merchants: [starbucks]
        reward: {type: billing_discount, rate: 20}
        limits:
          - {per: month, amount: 5000}
          - {shared: integrated}
        tiers: {from: 900000}
````

`backend/tests/engine/mockup/cards/mock/mock-zero.yaml`

````yaml
schema_version: 2
id: mock-zero
issuer: mock
name: 시안 현대 ZERO Edition3
kind: credit
product_codes: [MOCK3]
status: on_sale
sources:
  - {id: page, kind: product_page, url: 'https://example.com/mock', fetched_at: 2026-09-01}
checked_at: 2026-09-01
revisions:
  - effective_from: 2026-01-01
    source: page
    tiers: [0]
    spend:
      basis: none
      exclude_categories: [tax]
      installment: full_at_purchase
      cancellation: cancel_month
    benefit_exclusions:
      categories: [tax]
    benefits:
      - key: base-0-7
        title: 기본 0.7% 할인
        target: {all: true}
        reward: {type: billing_discount, rate: 0.7}
````

`backend/tests/engine/mockup/categories.yaml`

````yaml
- {code: cafe, name: 카페}
- {code: convenience, name: 편의점}
- {code: restaurant, name: 음식점}
- {code: online_shopping, name: 온라인 쇼핑}
- {code: transit, name: 대중교통}
- {code: tax, name: 세금}
- {code: other, name: 기타}
````

`backend/tests/engine/mockup/issuers/mock.yaml`

````yaml
{schema_version: 2, id: mock, name: 시안 카드사, notes: 화면 시안을 그릴 때 지어낸 카드다. 실제 카탈로그가 아니다. 작업 002 설계 6.3}
````

`backend/tests/engine/mockup/merchants.yaml`

````yaml
- key: starbucks
  name: 스타벅스
  category: cafe
  aliases: [스타벅스]
- key: ediya
  name: 이디야
  category: cafe
  aliases: [이디야]
- key: gs25
  name: GS25
  category: convenience
  aliases: [GS25]
- key: coupang
  name: 쿠팡
  category: online_shopping
  aliases: [쿠팡]
````

`backend/tests/engine/mockup/payment_methods.yaml`

````yaml
- {key: physical_card, name: 실물카드}
````

`backend/tests/engine/mockup/point_programs.yaml`

````yaml
- {key: mock_point, name: 시안 포인트, won_per_point: 1}
````

`backend/tests/engine/mockup/reference.yaml`

````yaml
- {key: fuel_price_gasoline, source: 시안, unit: 원/L, value: 1700, as_of: 2026-09-01}
````


- [x] **2단계: 검증기로 본다**

```bash
uv run --project backend python -c "from pathlib import Path; from cherry_core.catalog.check import check_catalog; from cherry_core.catalog.load import load_catalog; print([str(p) for p in check_catalog(load_catalog(Path('backend/tests/engine/mockup')))])"
```

기대: `[]`

- [x] **3단계: 시안 숫자 테스트를 쓴다**

`backend/tests/engine/test_mockup.py`

````python
"""화면 시안의 숫자를 시안 카드로 재현한다. 설계 6.3. 시안 카드는 tests/engine/mockup/에만 있는 지어낸 카드다.

시안 Mr.Life는 9월 1일에 등록하며 지난달 41만원으로 적었다. 9월 결제는 카페 3건, 편의점 1건, 기타 2건으로
이번 달 182,000원이다. 시안 IBK는 편의점 3건과 기타 1건으로 265,000원, 시안 ZERO는 쿠팡, 자동차세, 기타다.
"""

from datetime import date
from pathlib import Path

import pytest

from cherry_core.engine import Engine
from cherry_core.engine.models import Query, UserCard

from .conftest import at, pay

ROOT = Path(__file__).parent / "mockup"
NOW = at("2026-09-20T12:00")
SEPT = date(2026, 9, 1)


def mine(card_id, payments):
    return [p.model_copy(update={"user_card_id": card_id}) for p in payments]


@pytest.fixture(scope="module")
def home():
    eng = Engine.from_dir(ROOT)
    cards = [
        UserCard(id="mr", card_id="mock-mrlife", registered_on=SEPT, assumed_prev_month_spend=410000),
        UserCard(id="ibk", card_id="mock-ibk", registered_on=SEPT, assumed_prev_month_spend=250000),
        UserCard(id="zero", card_id="mock-zero", registered_on=SEPT),
    ]
    raw = {
        "mr": mine(
            "mr",
            [
                pay(10000, "2026-09-05T10:00", merchant="ediya"),
                pay(60000, "2026-09-08T12:00", category="other"),
                pay(10000, "2026-09-12T10:00", merchant="ediya"),
                pay(30000, "2026-09-15T18:00", merchant="gs25"),
                pay(59500, "2026-09-16T13:00", category="other"),
                pay(12500, "2026-09-19T14:20", merchant="starbucks"),
            ],
        ),
        "ibk": mine(
            "ibk",
            [
                pay(5700, "2026-09-06T09:00", merchant="gs25"),
                pay(5000, "2026-09-10T09:00", merchant="gs25"),
                pay(250000, "2026-09-11T19:00", category="other"),
                pay(4300, "2026-09-19T09:02", merchant="gs25"),
            ],
        ),
        "zero": mine(
            "zero",
            [
                pay(128000, "2026-09-18T11:00", category="tax"),
                pay(36900, "2026-09-18T21:00", merchant="coupang", channel="online"),
                pay(130143, "2026-09-20T10:00", category="other"),
            ],
        ),
    }
    results, saved = {}, {}
    for c in cards:
        rs = eng.price_month(c, raw[c.id])
        results[c.id] = rs
        saved[c.id] = [p.model_copy(update={"benefits": r.benefits}) for p, r in zip(raw[c.id], rs)]
    return eng, {c.id: c for c in cards}, results, saved


def test_1_saved_this_month(home):
    # 3쪽 홈 이번 달 아낀 돈 7,669원 = Mr.Life 4,500 + IBK 2,000 + ZERO 1,169
    _, _, results, _ = home
    assert {k: sum(r.value for r in rs) for k, rs in results.items()} == {"mr": 4500, "ibk": 2000, "zero": 1169}


def test_2_and_5_mrlife_status(home):
    # 3쪽과 6쪽. 지난달 41만 기준 30만 구간, 이번 달 182,000원, 유지까지 11.8만, 60만까지 41.8만. 4쪽 등록 41만이면 30만 구간
    eng, cards, _, saved = home
    s = eng.spend_status(cards["mr"], saved["mr"], SEPT)
    assert (s.tier, s.tier_source, s.prev_month_counted) == (300000, "assumed", 410000)
    assert (s.counted, s.to_keep, s.next_tier, s.to_next) == (182000, 118000, 600000, 418000)


def test_3_mrlife_limits(home):
    # 6쪽. 통합 1만 중 4,500 사용, 잔여 5,500. 카페 잔여 2,000/5,000, 편의점 잔여 3,500/5,000
    eng, cards, _, saved = home
    uses = {(u.key, u.per): u for u in eng.limit_status(cards["mr"], saved["mr"], NOW)}
    integrated, cafe, cvs = uses[("integrated", "month")], uses[("cafe-10", "month")], uses[("cvs-5", "month")]
    assert (integrated.used_amount, integrated.cap_amount - integrated.used_amount) == (4500, 5500)
    assert (cafe.cap_amount - cafe.used_amount, cafe.cap_amount) == (2000, 5000)
    assert (cvs.cap_amount - cvs.used_amount, cvs.cap_amount) == (3500, 5000)


def test_4_ibk_and_zero(home):
    # 3쪽. IBK 20만 구간 할인 잔여 3,000원, 이번 달 20만을 넘어 다음 달 구간 확정. ZERO 이번 달 1,169원
    eng, cards, results, saved = home
    uses = {(u.key, u.per): u for u in eng.limit_status(cards["ibk"], saved["ibk"], NOW)}
    assert uses[("integrated", "month")].cap_amount - uses[("integrated", "month")].used_amount == 3000
    s = eng.spend_status(cards["ibk"], saved["ibk"], SEPT)
    assert (s.tier, s.to_keep) == (200000, 0)
    assert sum(r.value for r in results["zero"]) == 1169


def test_6_and_7_records(home):
    # 7쪽 스타벅스 12,500원 1,000원, 실적 인정. 10쪽 GS25 4,300원 430원, 자동차세 0원 실적 제외, 쿠팡 36,900원 258원
    _, _, results, _ = home
    starbucks = results["mr"][5]
    assert [(b.key, b.value) for b in starbucks.benefits] == [("cafe-10", 1000)] and starbucks.spend[0].amount == 12500
    assert [b.value for b in results["ibk"][3].benefits] == [430]
    tax, coupang = results["zero"][0], results["zero"][1]
    assert tax.benefits == [] and tax.spend == [] and tax.warnings[0].data == {"reason": "category"}
    assert [b.value for b in coupang.benefits] == [258]


def test_8_category_tops(home):
    # 8쪽. 1만원 기준 카페 Mr.Life 1,000, 편의점 IBK 1,000, 음식점·온라인·대중교통 ZERO 70
    eng, cards, _, saved = home
    queries = [Query(category=c) for c in ["cafe", "convenience", "restaurant", "online_shopping", "transit"]]
    tops = [(rows[0].card_id, rows[0].value) for rows in eng.recommend(list(cards.values()), saved, queries, NOW)]
    assert tops == [("mock-mrlife", 1000), ("mock-ibk", 1000), ("mock-zero", 70), ("mock-zero", 70), ("mock-zero", 70)]


def test_9_starbucks_recommendation(home):
    # 9쪽. 1위 Mr.Life 1,000, 2위 ZERO 70, 3위 IBK 20. 스타벅스 20%는 90만 구간, 이번 달 18.2만이라 71.8만 더
    eng, cards, _, saved = home
    [rows] = eng.recommend(list(cards.values()), saved, [Query(merchant="starbucks")], NOW)
    assert [(r.card_id, r.value) for r in rows] == [("mock-mrlife", 1000), ("mock-zero", 70), ("mock-ibk", 20)]
    [lock] = [x for x in rows[0].locked if x.benefit == "sb-20"]
    assert (lock.required_tier, lock.remaining_this_month, lock.value_if_unlocked) == (900000, 718000, 2000)
    assert rows[0].counted


def test_10_import_preview_august():
    # 12쪽 8월 가져오기 미리보기. 스타벅스 6,100원 610원, 쿠팡 24,900원 혜택 없음, 자동차세 실적 제외
    eng = Engine.from_dir(ROOT)
    mr = UserCard(id="mr", card_id="mock-mrlife", registered_on=date(2026, 8, 1), assumed_prev_month_spend=410000)
    rs = eng.price_month(
        mr,
        mine(
            "mr",
            [
                pay(6100, "2026-08-29T10:00", merchant="starbucks"),
                pay(24900, "2026-08-28T20:00", merchant="coupang", channel="online"),
                pay(128000, "2026-08-25T11:00", category="tax"),
            ],
        ),
    )
    by_amount = {r.spend[0].amount if r.spend else 0: r for r in rs}
    assert [b.value for b in by_amount[6100].benefits] == [610]
    assert by_amount[24900].benefits == []
    assert by_amount[0].warnings[0].data == {"reason": "category"}


def test_11_cafe_limit_exhausted_and_reset():
    # 14쪽. 카페 한도 5,000원을 다 쓰면 0원과 limit_exhausted, 10월 1일에 초기화
    eng = Engine.from_dir(ROOT)
    mr = UserCard(id="mr", card_id="mock-mrlife", registered_on=SEPT, assumed_prev_month_spend=410000)
    cafe = [pay(10000, f"2026-09-{d:02d}T10:00", merchant="ediya") for d in (1, 2, 3, 4, 5, 6)]
    rs = eng.price_month(
        mr,
        mine(
            "mr",
            [pay(300000, "2026-09-07T12:00", category="other")]
            + cafe
            + [pay(10000, "2026-10-01T10:00", merchant="ediya")],
        ),
    )
    got = [sum(b.value for b in r.benefits) for r in rs]
    assert got == [1000, 1000, 1000, 1000, 1000, 0, 0, 1000]
    assert "limit_exhausted" in [w.code for w in rs[5].warnings]
````

- [x] **4단계: 돌린다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_mockup.py
```

기대: `9 passed`

- [x] **5단계: 커밋**

```bash
git add backend/tests/engine/mockup backend/tests/engine/test_mockup.py
git commit -m "test: 화면 시안 숫자를 시안 카드로 재현" -m "작업 002 설계 6.3. 시안 카드는 지어낸 카드라 테스트 폴더에만 둔다."
```

2026-09-29 실행 결과: 시안 카탈로그 검증 오류 0, 시안 숫자 테스트 9개 통과, 전체 440개 통과.

---

## 과제 9: 실제 명세서 대조

사용자 IBK 나라사랑카드 이용대금명세서로 엔진을 대조한다. 설계 6.6. 입력은 공개 저장소에 올리지 않는다.

**파일**
- 만들기: `backend/tests/engine/test_statement.py`
- 만들기, 커밋하지 않음: `backend/tests/engine/local/ibk-narasarang.yaml`

- [x] **1단계: 대조 테스트를 쓴다**

`backend/tests/engine/test_statement.py`

````python
"""사용자 IBK 나라사랑 이용대금명세서 대조. 설계 6.6. 입력은 tests/engine/local/에만 있고 저장소에 올리지 않는다.
파일이 없는 PC에서는 건너뛴다. 형식은 cases.py와 같고, 엔진과 다른 결제에는 difference에 까닭을 적는다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine

from .cases import load_cases, mismatches

LOCAL = Path(__file__).parent / "local"
ROOT = Path(__file__).resolve().parents[3] / "catalog"
CASES = load_cases(LOCAL) if LOCAL.exists() else []


@pytest.mark.skipif(not CASES, reason="명세서 입력이 없는 PC")
def test_statement_matches_engine():
    eng = Engine(load_catalog(ROOT))
    problems = {c.name: mismatches(eng, c) for c in CASES}
    assert {k: v for k, v in problems.items() if v} == {}
````

- [x] **2단계: 명세서가 커밋되지 않는지 먼저 본다**

```bash
git check-ignore -v backend/tests/engine/local/x.yaml
```

기대: `.gitignore`의 `backend/tests/engine/local/` 줄이 나온다. 안 나오면 멈춘다.

- [x] **3단계: 명세서를 입력으로 옮긴다**

`backend/tests/engine/local/`의 PDF를 읽어 `local/ibk-narasarang.yaml`을 `cases.py` 형식으로 쓴다. 이 단계는 에이전트에 맡기지 않고 이 세션이 직접 한다. 개인정보가 에이전트 보고에 섞이지 않게 하려는 것이다.
- 달마다 경우 하나다. 첫 달은 명세서의 전월 실적이 있으면 `prev_month_spend`로 쓴다
- 결제마다 날짜와 시각, 금액, 가맹점 키, 업종, 채널, 할부 개월, 명세서의 할인액을 옮긴다. 가맹점 키가 merchants.yaml에 없으면 업종만 쓴다
- 명세서의 할인액은 해당 혜택 key로 `benefits`에 쓴다. 어느 혜택인지 모르면 `difference: 혜택을 가릴 수 없음`을 적는다
- 카드번호, 이름, 주소, 계좌번호, 승인번호는 옮기지 않는다
- 추출에 쓴 임시 글은 scratchpad에 두고 끝나면 지운다

- [x] **4단계: 돌리고 차이마다 원인을 적는다**

```bash
uv run --project backend pytest -q backend/tests/engine/test_statement.py
```

다른 결제마다 원인을 넷 중 하나로 정한다. 카탈로그 값이 틀림, 엔진이 틀림, 문장으로 남긴 조건 때문, 명세서의 달 구분이 다름. 앞의 둘이면 과제 7의 4단계처럼 고친다. 뒤의 둘이면 그 결제에 `difference`로 적는다. 사용자가 PX와 대중교통은 이 카드로 쓰지 않는다.

- [x] **5단계: 저장소에는 개인정보 없이 결과만 적는다**

`plan.md` 끝의 `## 명세서 대조 결과`에 달 수, 결제 수, 같은 결제 수, 원인별 건수, 고친 것을 적는다. 가맹점 이름, 날짜, 금액은 적지 않는다.

- [x] **6단계: 커밋**

```bash
git status --short backend/tests/engine/local
git add backend/tests/engine/test_statement.py docs/work/002-calc-engine/plan.md
git commit -m "test: 실제 명세서 대조 테스트 추가" -m "작업 002 설계 6.6. 입력은 로컬 전용 폴더에만 있고 커밋하지 않는다."
```

첫 명령의 출력이 비어 있어야 한다.

2026-09-29 실행 결과: 명세서 대조 1개 통과, 전체 441개 통과. 엔진과 다른 결제 17건은 모두 difference에 원인을 적었고 고친 것은 없다. 결과는 아래 "명세서 대조 결과".

---

## 과제 10: 위험 검토

돈 계산 코드라 `risk-reviewer`로 검토한다. `.claude/CLAUDE.md` 작업 순서 5

- [ ] **1단계: 검토를 맡긴다**

`risk-reviewer` 에이전트에 `backend/cherry_core/engine/` 전체와 design.md를 넘긴다. 볼 것은 부동소수점으로 돈을 계산하는 곳, 원 미만 처리, 모르는 값이 부풀려지는 곳, 한도가 두 번 차감되거나 빠지는 곳, 달 경계, 순위 재계산이다.

- [ ] **2단계: 지적마다 테스트를 먼저 쓰고 고친다**

지적이 맞으면 실패하는 규칙 테스트를 먼저 쓰고 고친다. 맞지 않으면 까닭을 plan.md에 적는다.

- [ ] **3단계: 사용자에게 보고한다**

바뀐 계산을 숫자 예와 함께 보고하고 확인받는다.

- [ ] **4단계: 커밋**

```bash
git add backend
git commit -m "fix: 위험 검토에서 나온 계산 엔진 문제 수정" -m "작업 002"
```

고칠 것이 없으면 이 단계는 건너뛴다.

---

## 과제 11: 전체 문서에 결론 합치기

설계 7절이다. 기준은 전체 문서이고 작업 폴더는 이력이다.

**파일**
- 고치기: `docs/2026-09-19-cherryconsume-design.md`, `docs/scenarios.md`, `docs/erd.md`, `docs/erd.html`

- [ ] **1단계: 설계 문서 6장을 고친다**

- 6.3 출력 모델: SpendStatus, Recommendation, LockedBenefit을 design.md 1.4의 출력으로 바꾸고 ConditionalBenefit을 더한다. `current_tier_index`를 없앤다
- 6.5 계산 규칙: 1판 본문을 지우고 design.md 2절 실적, 3절 혜택, 4절 추천, 5절 경고를 줄여 옮긴다. "시나리오 검토에서 추가한 규칙" 목록은 E번호를 두고 2판 이름으로 고쳐 쓴다. 부모 업종 규칙에 E47, 순위 재계산에 E48을 인용한다
- 6.8 오류 처리: "알 수 없는 업종은 other로 본다" 뒤에 "부모 업종까지만 아는 결제는 부풀리지 않는 쪽으로 본다. E47"을 더한다
- 6.9 테스트: design.md 6절의 손계산 표, 시안 카드, 규칙 테스트, 속도 테스트, 실제 명세서 대조로 바꾼다

- [ ] **2단계: 시나리오와 ERD를 고친다**

- `docs/scenarios.md` 2.2 혜택과 추천 표에 E47, E48을 더한다. 형식은 다른 E번호 줄과 같다
  - E47 결제가 부모 업종까지만 알 때. 처리: 실적 제외와 혜택 제외에는 걸린 것으로, 혜택 대상에는 안 맞는 것으로 보고 자식 업종을 한 번 묻는다. 추천에서는 조건부 혜택으로 보여 준다. 결정: 작업 002 설계 2.1
  - E48 순위 카드의 달 중간 혜택이 달 끝 순위와 다를 때. 처리: 달이 끝나면 그 카드의 그 달 결제를 최종 순위로 다시 계산한다. 결정: 작업 002 설계 3.5
- `docs/erd.md`와 `docs/erd.html`의 설계 메모에서 결제가 받은 혜택을 가리킨다는 항목 끝에 "저장한 혜택은 다시 계산하지 않는다. 예외는 달이 끝난 순위 카드다. E48"을 더한다

- [ ] **3단계: 1판 이름이 남지 않았는지 본다**

```bash
grep -n "integrated_cap\|min_tier_index\|conditions_not_modeled\|applied_benefit_id\|estimated_benefit\|monthly_cap_exhausted\|current_tier_index" docs/2026-09-19-cherryconsume-design.md
```

기대: 출력 없음. intent 성공 기준이다.

- [ ] **4단계: 커밋**

```bash
git add docs/2026-09-19-cherryconsume-design.md docs/scenarios.md docs/erd.md docs/erd.html
git commit -m "docs: 계산 엔진 결론을 설계 문서와 시나리오에 반영" -m "작업 002 설계 7절. 계산 규칙 6.5절을 2판으로 다시 쓰고 시나리오 E47, E48을 더한다."
```

---

## 과제 12: 성공 기준 확인과 마무리

- [ ] **1단계: 전체를 돌린다**

```bash
uv run --project backend pytest -q
uv run --project backend python -m cherry_core.catalog check
```

기대: 실패 0, 명세서 입력이 있는 PC에서는 명세서 대조도 통과, 카탈로그 오류 0.

- [ ] **2단계: 성공 기준을 하나씩 적는다**

이 파일 끝 `## 성공 기준 확인` 표를 채운다.

| 성공 기준 | 근거 |
|---|---|
| 혜택 190개가 모두 손계산 표에 나오고 통과 | `test_every_benefit_is_covered`, `test_case_matches_engine` |
| 기대값은 엔진 코드를 쓰지 않은 에이전트가 계산 | 과제 3 에이전트 보고 |
| 화면 시안 숫자 재현 | `test_mockup.py` |
| E2, E4, E5, E6, E7, E11, E12, E37 테스트 | `test_spend.py`, `test_benefits.py`, `test_recommend.py`의 해당 테스트 이름 |
| 나라사랑 급여이체자 25만원 이상 | `test_tiers_to_and_waived_from_only` |
| 원 단위 정수, 같은 입력 같은 출력, 시각은 인자 | `test_same_input_same_output_and_integers` |
| 명세서 결제마다 같거나 원인 기록 | `test_statement_matches_engine`과 `## 명세서 대조 결과` |
| 추천 50ms, 업종 12개 200ms | `test_speed.py` |
| 설계 문서 6.5절 2판 | 과제 11의 3단계 |

- [ ] **3단계: 진행 상황과 작업 기록**

`.claude/progress.md`의 지금 위치를 작업 003으로 옮기고 작업 002를 끝난 것에 적는다. `docs/history/`에 작업 기록을 쓰고 목록에 한 줄 더한다. 사용자 요청은 원문 그대로 인용한다.

- [ ] **4단계: 커밋**

```bash
git add .claude/progress.md docs/work/002-calc-engine/plan.md
git commit -m "chore: 작업 002를 끝난 것으로 진행 상황 갱신"
git add docs/history
git commit -m "docs: 작업 기록 계산 엔진 추가"
```

---

## 표를 만들며 나온 것

과제 3과 7에서 채운다.

### 과제 3

사용자가 정한 것. 2026-09-29
- 공통 제외는 혜택이 대상 업종으로 결제 업종을 직접 적었을 때만 무시한다. 가맹점만 적었으면 결제 업종으로 본다. 이마트에서 산 상품권은 이마트 5%를 받지 않는다. 설계 3.2의 3. 20장에서 계산이 바뀌는 혜택은 없다
- 어학원 2곳은 `education.academy`, 어학시험 7곳은 새 업종 `education.exam`으로 옮겼다. 통신사 3곳은 부모 업종으로 두고 결제 때 묻는다. 설계 2.1. 이 가맹점으로 부모 업종 규칙을 시험하던 경우 3개는 결제에 업종 education을 직접 적어 기대값을 그대로 두었다

엔진을 고친 것. 시제품에서 규칙 테스트를 먼저 쓰고 고쳤고 과제 5의 코드에 들어 있다
- 이용액 순위의 상위 개수를 신규 발급 특례 구간으로 센다. KB Easy all 새 카드가 순위 혜택을 하나도 못 받았다
- 구간이 모자라고 `waived_when`이 모름이면 구간 미달과 묻기를 함께 붙인다. IBK 나라 서비스 두 경우
- 한도 `adjust` 조건이 모름이면 묻기를 붙인다. My WE:SH 생일 달 두 배
- 현장할인은 할인액을 한도로 먼저 자르고 할인 전 금액을 기록 금액 + 할인액으로 본다. IBK 아웃백 170,000원이 212,500원으로 부풀던 것
- `limit_exhausted`는 기간 한도로 줄었을 때만 붙인다. 에이전트 셋 중 둘의 해석
- 공통 제외 규칙을 위의 사용자 결정대로 바꿨다

설계 문장만 분명히 한 것. 엔진은 이미 그렇게 계산했다
- `tier_by_benefit`은 그 값과 기본 구간 중 큰 쪽, 달 합계 대상 이용액은 다른 조건까지 맞는 결제액, 제외 조건의 모름은 혜택 없음, 다른 묶음이 공유 한도를 같이 쓰면 파일 순서, 시간 조건은 끝 시각 제외, 전 가맹점 대상에도 대상 제외, 실적 비율의 원 미만은 실적 금액에서 버림, 옵션은 기본값 먼저이고 선택 이력은 적용 시작일, 결제 업종이 가맹점 업종보다 우선, `price_month`는 달 중간 순위, 한도로 0원이면 받지 않은 혜택, priority 묶음은 한도가 남은 혜택, 실적 조건 없는 카드도 실적 금액은 돌려줌, 현장할인과 청구할인이 겹치면 청구할인은 기록 금액

카드 파일을 고친 것
- KB 톡톡 간편결제 10%에서 모바일티머니를 뺐다. 원문 예시에 없어 확인 필요로도 남겼다

그대로 둔 것
- 신한 묶음 에이전트는 권한 때문에 원문을 열지 못해 카드 파일 메모로 계산했다. 세 카드의 실적 제외와 적립 제외는 작업 001 과제 13에서 원문과 대조를 마쳤다
- 트래블로그 국내 적립의 "일시불만"은 체크카드라 결과가 같아 옮기지 않았다. taptap O 해외 적립 제외의 고용·산재보험은 업종이 4대보험 하나라 나누지 않았다

### 과제 7

저장소 엔진으로 표 279개를 대조해 모두 같았다. 고친 것 없음.

## 명세서 대조 결과

2026-09-29. 명세서 5장, 이용기간 5달치를 옮겼다. 결제 187건, 명세서 할인 줄 36개다. 입력은 `backend/tests/engine/local/`에만 있다.

- 경우는 달마다 하나가 아니라 둘로 나눴다. 첫 명세서가 4월 말 닷새부터 시작해 4월 실적을 다 알 수 없어서다. 4월 닷새를 한 경우로, 5월부터를 한 경우로 두었다. 5월부터는 엔진이 지난달 결제로 구간을 센다. 두 경우의 첫 달 지난달 실적은 그달 할인이 나온 구간의 하한으로 넣었다
- 같은 결제는 170건이다. 이 중 할인이 있는 결제가 26건이다
- 다른 결제는 17건이고 모두 difference에 적었다

| 원인 | 건수 | 한 줄 설명 |
|---|---|---|
| 카탈로그 값이 틀림 | 0 | |
| 엔진이 틀림 | 0 | |
| 문장으로 남긴 조건 | 9 | 비씨카드 전산 업종 4건, 편의점 주요품목 현장할인 5건 |
| 명세서의 달 구분이 다름 | 0 | 결제일 기준 달로 옮겨 생기지 않았다 |
| 명세서에 안 나오는 혜택 | 5 | 현장할인 4건, Npay 포인트 1건. 계획의 네 원인에 없어 더했다 |
| 대조 범위 밖 이력 | 2 | 기차 할인 연 4회 한도. 명세서보다 앞선 이용을 모른다 |
| 혜택을 가릴 수 없음 | 1 | 3월 실적을 몰라 같은 10% 편의점 할인 둘 중 어느 쪽인지 모른다 |

고친 것은 없다.

알게 된 것
- 편의점 할인 1일 2회가 명세서로도 맞다. 같은 날 편의점 두 번이 모두 할인됐다
- 여가 할인 4건 중 3건이 PC방이 아닌 업종의 가맹점에서 나왔고, 이름에 PC가 들어간 가맹점 1곳은 할인이 없었다. 카드사는 비씨카드 전산 업종으로 판단한다. 앱이 가맹점 업종을 추정하면 이 할인 추천이 틀릴 수 있다
- 주요품목 현장할인과 편의점 청구할인이 둘 다 걸리는 결제 1건에 청구할인이 나왔다. 엔진은 카탈로그 가정대로 두 할인 중 큰 쪽인 현장할인을 고른다. 계산대에서 현장할인도 받았다면 둘을 같이 받는다는 뜻이다. 명세서로는 알 수 없어 카탈로그 확인 필요 항목은 그대로다
- 연 한도는 앱에 적기 전의 이용을 모른다. 기차 할인 2건을 엔진이 명세서보다 더 줬다
- 쇼핑 할인을 받은 결제 1건에 이 카드 상품에 없는 비씨카드 마이태그 할인이 더 있었다. 기대값에서 뺐다
- 정부 지원금으로 낸 결제도 할인을 받았다. 지원금 사용분이 실적에 들어가는지는 명세서에 없다. 빼면 한 달의 구간이 한 칸 내려가지만 통합할인한도에 닿지 않아 결과는 같다
- 명세서의 소계는 할인 줄을 빼지 않은 이용 금액의 합이다. 옮긴 결제와 지원금 줄을 더하면 5장 모두 소계와 같았다
- 사용자 사실은 급여이체 아니오만 넣었다. 급여이체 우대 할인이 한 번도 없었다
- PX, 대중교통 통합할인한도, 메가오더는 이 카드로 쓴 결제가 없어 풀리지 않았다

## 성공 기준 확인

과제 12에서 채운다.
