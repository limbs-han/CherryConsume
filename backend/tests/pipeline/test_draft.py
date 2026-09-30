"""추출 결과로 만든 카드 초안. 설계 1절 4단계와 5단계.

테스트 카탈로그는 tests/catalog/conftest.py의 FILES다. CURRENT는 그 카드의 지금 규칙을 손으로 합친 것이고,
구간 키는 LLM이 JSON으로 돌려주는 모양대로 글자로 적었다.
"""

import copy
from datetime import date

import pytest

from cherry_core.pipeline.draft import check_draft, int_keys, make_draft
from tests.catalog.conftest import FILES, write_catalog

CARD = FILES["cards/shinhan/shinhan-test.yaml"]
ISSUER = FILES["issuers/shinhan.yaml"]
PATH = "cards/shinhan/shinhan-test.yaml"
FETCHED = date(2026, 10, 1)
CURRENT = {
    "tiers": [0, 300000, 500000],
    "spend": {
        "basis": "prev_calendar_month",
        "exclude_categories": ["tax"],
        "installment": "full_at_purchase",
        "cancellation": "cancel_month",
    },
    "limits": [{"key": "integrated", "per": "month", "amount": {"300000": 10000, "500000": 20000}}],
    "benefits": [
        {
            "key": "cafe-10",
            "title": "카페 10% 할인",
            "target": {"categories": ["cafe"]},
            "reward": {"type": "billing_discount", "rate": 10},
            "limits": [{"per": "txn", "amount": 1000}, {"shared": "integrated"}],
            "tiers": {"from": 300000},
        }
    ],
}


def extracted(effective_from=None, rate=10, **spend):
    rules = copy.deepcopy(CURRENT)
    rules["benefits"][0]["reward"]["rate"] = rate
    rules["spend"].update(spend)
    return {"rules": rules, "effective_from": effective_from, "source": "page"}


def test_int_keys():
    assert int_keys({"amount": {"300000": 10000}, "key": "a"}) == {"amount": {300000: 10000}, "key": "a"}


def test_same_rules_make_no_draft():
    assert make_draft(CARD, ISSUER, extracted(), FETCHED) is None


def test_changed_rate_adds_revision_without_issuer_defaults():
    draft = make_draft(CARD, ISSUER, extracted(date(2026, 11, 1), rate=5), FETCHED)
    assert draft["revisions"][0] == CARD["revisions"][0]
    assert draft["revisions"][1] == {
        "effective_from": date(2026, 11, 1),
        "source": "page",
        "tiers": [0, 300000, 500000],
        "limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 20000}}],
        "benefits": [
            {
                "key": "cafe-10",
                "title": "카페 10% 할인",
                "target": {"categories": ["cafe"]},
                "reward": {"type": "billing_discount", "rate": 5},
                "limits": [{"per": "txn", "amount": 1000}, {"shared": "integrated"}],
                "tiers": {"from": 300000},
            }
        ],
    }
    assert draft["checked_at"] == FETCHED
    assert draft["sources"][0]["fetched_at"] == FETCHED
    assert CARD["checked_at"] == date(2026, 9, 28)  # 원본은 그대로다


def test_card_specific_spend_is_kept():
    draft = make_draft(CARD, ISSUER, extracted(date(2026, 11, 1), installment="per_installment_month"), FETCHED)
    assert draft["revisions"][1]["spend"] == {"installment": "per_installment_month"}


def test_card_value_equal_to_model_default_is_kept_when_issuer_differs():
    issuer = copy.deepcopy(ISSUER)
    issuer["defaults"][0]["spend"]["interest_free"] = "exclude"
    rules = extracted(date(2026, 11, 1))  # 카드 규칙은 interest_free를 적지 않았다. 모델 기본값 count다
    draft = make_draft(CARD, issuer, rules, FETCHED)
    assert draft["revisions"][1]["spend"] == {"interest_free": "count"}


def test_required_field_missing_from_issuer_is_kept():
    issuer, card = copy.deepcopy(ISSUER), copy.deepcopy(CARD)
    del issuer["defaults"][0]["spend"]["cancellation"]
    card["revisions"][0]["spend"] = {"cancellation": "cancel_month"}  # 카드사가 안 정한 칸은 카드가 정한다
    draft = make_draft(card, issuer, extracted(date(2026, 11, 1), rate=5), FETCHED)
    assert draft["revisions"][1]["spend"] == {"cancellation": "cancel_month"}


def test_missing_date_uses_fetch_day_and_asks():
    draft = make_draft(CARD, ISSUER, extracted(rate=5), FETCHED)
    rev = draft["revisions"][1]
    assert (rev["effective_from"], rev["effective_from_estimated"]) == (FETCHED, True)
    assert draft["open_questions"] == [
        {"path": "revisions[1].effective_from", "question": "원문에서 시행일을 찾지 못해 수집한 날로 두었다"}
    ]


def test_same_date_corrects_last_revision():
    draft = make_draft(CARD, ISSUER, extracted(date(2026, 7, 1), rate=5), FETCHED)
    assert len(draft["revisions"]) == 1
    assert draft["revisions"][0]["benefits"][0]["reward"]["rate"] == 5


def test_earlier_date_needs_a_person():
    with pytest.raises(ValueError, match="앞이다"):
        make_draft(CARD, ISSUER, extracted(date(2026, 6, 1), rate=5), FETCHED)


@pytest.fixture
def files(tmp_path):
    root = write_catalog(tmp_path / "catalog", copy.deepcopy(FILES))
    return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in root.rglob("*.yaml")}


def test_good_draft_passes_check(files):
    assert check_draft(files, PATH, make_draft(CARD, ISSUER, extracted(rate=5), FETCHED)) == []


def test_bad_draft_reports_its_problems(files):
    bad = extracted(date(2026, 11, 1))
    bad["rules"]["benefits"][0]["target"]["categories"] = ["nope"]
    problems = check_draft(files, PATH, make_draft(CARD, ISSUER, bad, FETCHED))
    assert problems and all(p.startswith("error: revisions@2026-11-01.benefits[cafe-10]") for p in problems)
