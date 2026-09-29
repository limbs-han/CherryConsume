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
