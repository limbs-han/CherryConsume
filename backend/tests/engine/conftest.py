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
