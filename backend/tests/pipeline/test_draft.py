"""추출 결과로 만든 카드 초안. 설계 1절 4단계와 5단계.

테스트 카탈로그는 tests/catalog/conftest.py의 FILES다. CURRENT는 그 카드의 지금 규칙을 손으로 합친 것이고,
구간 키는 LLM이 JSON으로 돌려주는 모양대로 글자로 적었다.
"""

import copy
from datetime import date

import pytest
from pydantic import ValidationError

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


def card_with_own_spend():
    card = copy.deepcopy(CARD)
    card["revisions"][0]["spend"] = {"interest_free": "exclude"}  # 카드사 기본값 count와 다르게 카드가 정했다
    return card


def test_changes_mode_keeps_current_values_for_spend_the_model_left_out():
    # 2026-10-02 위험 검토. 카드사 기본값으로 채우면 카드가 따로 정한 실적 규칙이 조용히 사라진다
    card = card_with_own_spend()
    for drop in (["spend"], ["spend", "installment"]):  # 묶음을 통째로 빼거나 칸 하나를 뺐다
        answer = extracted(rate=5)
        node = answer["rules"]
        for k in drop[:-1]:
            node = node[k]
        del node[drop[-1]]
        draft = make_draft(card, ISSUER, answer, FETCHED, keep_current=True)
        assert draft["revisions"][-1]["spend"] == {"interest_free": "exclude"}
        asked = [q for q in draft["open_questions"] if "지금 값을 두었다" in q["question"]]
        assert asked and asked[0]["path"] == f"revisions[{len(draft['revisions']) - 1}]"


def test_golden_mode_does_not_fill_what_the_model_left_out():
    # 채점에서 채우면 채운 값이 정답에서 와서 점수가 부푼다. 필수 칸이 빠지면 형식 오류다
    answer = extracted(rate=5)
    del answer["rules"]["spend"]["installment"]
    with pytest.raises(ValidationError):
        make_draft(card_with_own_spend(), ISSUER, answer, FETCHED)


def test_model_questions_keep_assumed_and_good_paths(files):
    answer = extracted(rate=5)
    answer["open_questions"] = [
        {"path": "benefits[cafe-10].reward.rate", "question": "할인율이 맞는가", "assumed": 5},
        {"path": "benefits[?key='cafe-10'].target", "question": "테이크아웃도 되는가"},  # 카드 파일에 없는 주소
        "주말에도 되는가",  # 글만 왔다
        {"path": "tiers"},  # 질문이 없다
    ]
    draft = make_draft(CARD, ISSUER, answer, FETCHED)
    here = f"revisions[{len(draft['revisions']) - 1}]"
    assert draft["open_questions"][-3:] == [
        {"path": f"{here}.benefits[cafe-10].reward.rate", "question": "할인율이 맞는가", "assumed": 5},
        {"path": here, "question": "benefits[?key='cafe-10'].target: 테이크아웃도 되는가"},
        {"path": here, "question": "주말에도 되는가"},
    ]
    assert check_draft(files, PATH, draft) == []


def test_changes_mode_flags_spend_the_model_read_differently():
    # 형식 예시의 실적 규칙을 베낀 값처럼 지금 값과 다른 칸도 사람이 보게 한다. 실적 규칙에는 근거 문장 칸이 없다
    answer = extracted(rate=5, cancellation="original_month")
    draft = make_draft(card_with_own_spend(), ISSUER, answer, FETCHED, keep_current=True)
    asked = [q["question"] for q in draft["open_questions"]]
    assert "spend의 cancellation: 원문에서 읽은 값이 지금 값과 다르다" in asked


def test_existing_question_into_a_replaced_revision_keeps_its_text(files):
    # 2026-10-02 카카오뱅크. 같은 시행일이라 마지막 개정을 갈아 끼우면 그 안을 가리키던 옛 질문의 주소가 깨졌다
    card = card_with_own_spend()
    card["open_questions"] = [{"path": "revisions[0].spend.interest_free", "question": "무이자 할부가 빠지는가", "assumed": "exclude"}]
    draft = make_draft(card, ISSUER, extracted(date(2026, 7, 1), rate=5), FETCHED)  # 원문은 무이자 할부를 말하지 않는다
    assert "interest_free" not in draft["revisions"][0].get("spend", {})
    assert draft["open_questions"][0] == {
        "path": "revisions[0]",
        "question": "revisions[0].spend.interest_free: 무이자 할부가 빠지는가",
        "assumed": "exclude",
    }
    assert check_draft(files, PATH, draft) == []


def test_changes_mode_flags_limits_the_model_dropped():
    # 2026-10-02 위험 검토. 판 6과 7은 금액을 못 찾은 한도를 빼라고 한다. 이대로 승인하면 한도 없이 계산해 혜택이 부푼다
    answer = extracted(rate=5)
    answer["rules"]["limits"] = []
    answer["rules"]["benefits"][0]["limits"] = []
    draft = make_draft(card_with_own_spend(), ISSUER, answer, FETCHED, keep_current=True)
    asked = [q["question"] for q in draft["open_questions"]]
    assert "limits의 integrated: 원문에서 찾지 못해 초안에서 빠졌다. 이대로 승인하면 이 한도 없이 계산한다" in asked
    assert "benefits[cafe-10]의 limits integrated, txn: 지금 한도가 초안에 없다. 이대로 승인하면 그 한도 없이 계산한다" in asked


def test_changes_mode_flags_benefits_the_model_dropped():
    answer = extracted(rate=5)
    answer["rules"]["benefits"][0]["key"] = "cafe-5"  # 지금 혜택 cafe-10이 초안에 없다
    draft = make_draft(card_with_own_spend(), ISSUER, answer, FETCHED, keep_current=True)
    asked = [q["question"] for q in draft["open_questions"]]
    assert "benefits의 cafe-10: 원문에서 찾지 못해 초안에서 빠졌다" in asked


def test_changes_mode_flags_a_benefit_limit_dropped_among_others():
    # 2026-10-02 다시 검토. 공유 한도만 남고 건당 1천원 한도가 빠지면 5만원 결제에 5% 할인이 1천원이 아니라 2천5백원이 된다
    answer = extracted(rate=5)
    answer["rules"]["benefits"][0]["limits"] = [{"shared": "integrated"}]
    draft = make_draft(card_with_own_spend(), ISSUER, answer, FETCHED, keep_current=True)
    asked = [q["question"] for q in draft["open_questions"]]
    assert "benefits[cafe-10]의 limits txn: 지금 한도가 초안에 없다. 이대로 승인하면 그 한도 없이 계산한다" in asked


@pytest.mark.parametrize("limits", [5, True, [{"key": ["integrated"], "per": "month", "amount": 1}]])
def test_changes_mode_odd_limits_stay_a_format_error(limits):
    # 이상한 모양의 답도 바뀐 원문 모드에서 형식 오류가 되어야 한 번 더 묻는다
    answer = extracted(rate=5)
    answer["rules"]["limits"] = limits
    with pytest.raises(ValidationError):
        make_draft(card_with_own_spend(), ISSUER, answer, FETCHED, keep_current=True)


def card_with_ranked():
    card = card_with_own_spend()
    # 사람이 넣은 순위 영역 취소 달이다. Ranked는 key와 top만 있으면 형식에 맞는다
    card["revisions"][0]["ranked"] = [{"key": "top-area", "top": 1, "cancellation": "cancel_month"}]
    return card


def test_changes_mode_keeps_current_ranked_cancellation_the_model_left_out():
    # 2026-10-02 E55 위험 검토. 모델이 cancellation을 빼면 사람이 넣은 순위 영역 취소 달이 조용히 지워진다
    answer = extracted(rate=5)
    answer["rules"]["ranked"] = [{"key": "top-area", "top": 1}]
    draft = make_draft(card_with_ranked(), ISSUER, answer, FETCHED, keep_current=True)
    assert draft["revisions"][-1]["ranked"] == [{"key": "top-area", "top": 1, "cancellation": "cancel_month"}]
    assert answer["rules"]["ranked"] == [{"key": "top-area", "top": 1}]  # 추출 결과는 그대로다
    asked = [q["question"] for q in draft["open_questions"]]
    assert "ranked[top-area]의 cancellation: 원문에서 찾지 못해 지금 값을 두었다" in asked


def test_changes_mode_flags_ranked_cancellation_the_model_read_differently():
    answer = extracted(rate=5)
    answer["rules"]["ranked"] = [{"key": "top-area", "top": 1, "cancellation": "original_month"}]
    draft = make_draft(card_with_ranked(), ISSUER, answer, FETCHED, keep_current=True)
    assert draft["revisions"][-1]["ranked"] == [{"key": "top-area", "top": 1, "cancellation": "original_month"}]
    asked = [q["question"] for q in draft["open_questions"]]
    assert "ranked[top-area]의 cancellation: 원문에서 읽은 값이 지금 값과 다르다" in asked


def test_changes_mode_flags_ranked_the_model_dropped():
    draft = make_draft(card_with_ranked(), ISSUER, extracted(rate=5), FETCHED, keep_current=True)
    assert "ranked" not in draft["revisions"][-1]
    asked = [q["question"] for q in draft["open_questions"]]
    assert "ranked의 top-area: 원문에서 찾지 못해 초안에서 빠졌다" in asked
