"""카탈로그에 없는 카드의 새 초안. 작업 008 설계 3절. 모델 답은 고정값으로 흉내 낸다."""

import copy
import json
from datetime import date

import pytest
import yaml

from cherry_core.pipeline.new_card import card_head, pick_new_cards, process_new_card
from tests.catalog.conftest import FILES, write_catalog
from tests.pipeline.test_draft import CURRENT, ISSUER

FETCHED = date(2026, 10, 5)
ROW = {
    "issuer": "shinhan",
    "card_id": "shinhan-t0002",
    "name": "신한카드 새 카드",
    "kind": "credit",
    "code": "T0002",
    "status": "on_sale",
    "discontinued_on": None,
}
DOCS = [
    ("product_page", "https://www.shinhancard.com/new", FETCHED, "신한카드 새 카드\n카페 10% 할인"),
    ("manual_pdf", "https://www.shinhancard.com/new.pdf", date(2026, 10, 4), "상품설명서\n이 카드는 신용카드입니다."),
]


@pytest.fixture
def files(tmp_path):
    root = write_catalog(tmp_path / "catalog", copy.deepcopy(FILES))
    return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in root.rglob("*.yaml")}


def answer(effective_from="2026-09-01", **extra) -> str:
    rules = copy.deepcopy(CURRENT)
    del rules["spend"]  # 원문에 실적 규칙이 없다. 카드사 기본값을 따른다
    return json.dumps(
        {"rules": rules, "effective_from": effective_from, "source": "page", "open_questions": [], **extra},
        ensure_ascii=False,
    )


def run(files, response, row=ROW, error=None):
    head = card_head(row, DOCS, FETCHED)
    return process_new_card(files, head, ISSUER, response, error, FETCHED, [d[3] for d in DOCS])


def test_head_comes_from_the_index_row_not_the_model():
    head = card_head({**ROW, "status": "discontinued", "discontinued_on": date(2025, 3, 1)}, DOCS, FETCHED)
    assert head == {
        "schema_version": 2,
        "id": "shinhan-t0002",
        "issuer": "shinhan",
        "name": "신한카드 새 카드",
        "kind": "credit",
        "product_codes": ["T0002"],
        "status": "discontinued",
        "status_since": date(2025, 3, 1),
        "sources": [
            {"id": "page", "kind": "product_page", "url": "https://www.shinhancard.com/new", "fetched_at": FETCHED},
            {
                "id": "manual",
                "kind": "manual_pdf",
                "url": "https://www.shinhancard.com/new.pdf",
                "fetched_at": date(2026, 10, 4),
            },
        ],
        "checked_at": FETCHED,
    }


def test_rules_from_the_model_become_the_first_revision_with_issuer_defaults(files):
    out = run(files, answer())
    assert (out.status, out.problems) == ("draft", [])
    card = yaml.safe_load(out.draft_yaml)
    (revision,) = card["revisions"]
    assert revision["effective_from"] == date(2026, 9, 1) and revision["source"] == "page"
    # 카드사 기본값과 같은 칸은 적지 않아 카드사 기본값이 바뀌면 따라간다
    assert "spend" not in revision and revision["benefits"][0]["key"] == "cafe-10"
    assert {"path": "revisions[0]", "question": "spend: 원문에서 찾지 못해 카드사 기본값을 따른다"} in card[
        "open_questions"
    ]
    assert "연회비" in card["notes"]


def test_missing_date_uses_fetch_day_and_asks(files):
    card = yaml.safe_load(run(files, answer(effective_from=None)).draft_yaml)
    assert card["revisions"][0]["effective_from"] == FETCHED and card["revisions"][0]["effective_from_estimated"]
    assert any(q["path"] == "revisions[0].effective_from" for q in card["open_questions"])


def test_unknown_kind_comes_from_model_only_with_evidence_in_the_text(files):
    row = {**ROW, "kind": None}
    out = run(files, answer(kind="credit", kind_evidence="이 카드는  신용카드입니다."), row)
    card = yaml.safe_load(out.draft_yaml)
    assert card["kind"] == "credit"
    assert any(q["path"] == "kind" and "이 카드는 신용카드입니다." in q["question"] for q in card["open_questions"])


@pytest.mark.parametrize(
    "extra",
    [
        {"kind": "credit", "kind_evidence": "원문에 없는 문장"},
        {"kind": None, "kind_evidence": None},
        {"kind": "hybrid", "kind_evidence": "이 카드는 신용카드입니다."},
        {},
    ],
)
def test_unknown_kind_without_evidence_needs_a_person(files, extra):
    out = run(files, answer(**extra), {**ROW, "kind": None})
    assert out.status == "needs_human" and "카드 종류" in out.reason and out.draft_yaml is None


def test_format_error_is_asked_again(files):
    rules = copy.deepcopy(CURRENT)
    rules["benefits"][0]["reward"]["rate"] = "많이"
    response = json.dumps({"rules": rules, "effective_from": None, "source": "page", "open_questions": []})
    out = run(files, response)
    assert out.status == "needs_human" and out.errors


def test_model_error_is_retried_next_run(files):
    assert run(files, None, error="timeout").status == "model_error"


def index_row(card_id, name, **kw):
    base = {
        "issuer": "shinhan",
        "card_id": card_id,
        "name": name,
        "kind": "credit",
        "code": None,
        "status": "on_sale",
        "discontinued_on": None,
        "page_url": f"https://x.test/{card_id}",
        "pdf_urls": [],
        "recommended": False,
    }
    return {**base, **kw}


def test_pick_new_cards_skips_catalog_drafted_corporate_old_and_docless_cards():
    rows = [
        index_row("shinhan-test", "카탈로그 카드"),
        index_row("shinhan-a", "초안 있는 카드"),
        index_row("shinhan-b", "신한 법인카드"),
        index_row("shinhan-c", "옛 카드", status="discontinued", discontinued_on=date(2020, 1, 1)),
        index_row("shinhan-d", "원문 없는 카드"),
        index_row("shinhan-e", "새 카드", pdf_urls=["https://x.test/e-new.pdf", "https://x.test/e-old.pdf"]),
        index_row("shinhan-f", "추천 카드", recommended=True),
    ]
    docs = {
        f"https://x.test/{c}": {"path": f"{c}.html"} for c in ("shinhan-test", "shinhan-a", "shinhan-b", "shinhan-c")
    }
    docs |= {
        "https://x.test/shinhan-e": {"path": "e.html"},
        "https://x.test/e-new.pdf": {"path": "e-new.pdf"},
        "https://x.test/e-old.pdf": {"path": "e-old.pdf"},
        "https://x.test/shinhan-f": {"path": "f.html"},
    }
    picked = pick_new_cards(rows, {"shinhan-test"}, {"shinhan-a"}, docs, FETCHED)
    # 추천 카드를 먼저 고른다. PDF는 가장 최근 것 하나만 쓴다
    assert [(r["card_id"], [(k, d["path"]) for k, _, d in found]) for r, found in picked] == [
        ("shinhan-f", [("product_page", "f.html")]),
        ("shinhan-e", [("product_page", "e.html"), ("manual_pdf", "e-new.pdf")]),
    ]
    assert [r["card_id"] for r, _ in pick_new_cards(rows, {"shinhan-test"}, {"shinhan-a"}, docs, FETCHED, limit=1)] == [
        "shinhan-f"
    ]
    assert pick_new_cards(rows, set(), set(), docs, FETCHED, issuers={"kb"}) == []


def test_requested_card_is_picked_after_recommended_and_before_the_rest():
    # 작업 008 14단계. 설문으로 요청이 온 카드는 그 카드사를 한 장만 돌려도 초안이 생겨야 한다
    rows = [
        index_row("shinhan-a", "가 카드"),
        index_row("shinhan-b", "나 카드", requested=True),
        index_row("shinhan-c", "다 카드", recommended=True),
        index_row("shinhan-d", "라 카드", requested=None),  # 칸이 생기기 전 행
    ]
    docs = {f"https://x.test/shinhan-{c}": {"path": f"{c}.html"} for c in "abcd"}
    picked = pick_new_cards(rows, set(), set(), docs, FETCHED)
    assert [r["card_id"] for r, _ in picked] == ["shinhan-c", "shinhan-b", "shinhan-a", "shinhan-d"]


def test_card_sent_to_a_person_for_unknown_kind_is_drafted_again_once_the_index_knows_it():
    from cherry_core.pipeline.new_card import KIND_REASON, drafted_cards

    drafts = [
        ("nh-a", "needs_human", KIND_REASON),
        ("nh-b", "needs_human", KIND_REASON),
        ("nh-c", "draft", None),
        ("nh-d", "model_error", "모델 호출 실패: timeout"),
        ("nh-e", "needs_human", "규칙 형식 오류 2곳: benefits"),
    ]
    # 색인이 nh-a의 종류를 알게 되면 다시 고른다. 모델 호출이 실패한 카드와 형식 오류가 한 번인 카드도 다시 고른다
    assert drafted_cards(drafts, typed={"nh-a", "nh-e"}) == {"nh-b", "nh-c"}


def test_card_with_a_format_error_is_drafted_again_only_once():
    # 2026-10-06 첫 전체 추출에서 형식 오류 242장 대부분이 카탈로그 포인트 목록에 없는 포인트였다. 목록을 채운 뒤 한 번 더 묻는다
    from cherry_core.pipeline.new_card import drafted_cards

    fmt = "규칙 형식 오류 1곳: benefits.0.reward"
    drafts = [
        ("kb-a", "needs_human", fmt),
        ("kb-b", "needs_human", fmt),
        ("kb-b", "needs_human", fmt),
        ("kb-c", "needs_human", fmt),
        ("kb-c", "draft", None),
    ]
    assert drafted_cards(drafts, typed=set()) == {"kb-b", "kb-c"}


def test_spend_the_model_read_differently_from_issuer_defaults_is_asked(files):
    rules = copy.deepcopy(CURRENT)
    rules["spend"]["installment"] = "per_installment_month"
    response = json.dumps({"rules": rules, "effective_from": "2026-09-01", "source": "page", "open_questions": []})
    card = yaml.safe_load(run(files, response).draft_yaml)
    # 형식 예시의 실적 규칙을 베끼면 카드사 기본값을 조용히 덮는다. 2026-10-05 위험 검토
    assert card["revisions"][0]["spend"] == {"installment": "per_installment_month"}
    assert any(
        q["question"].startswith("spend의 installment: 원문에서 읽은 값이 카드사 기본값과 다르다")
        for q in card["open_questions"]
    )


def test_every_spend_value_is_asked_when_the_issuer_has_no_defaults(files):
    head = card_head(ROW, DOCS, FETCHED)
    out = process_new_card(files, head, None, answer_with_spend(), None, FETCHED, [d[3] for d in DOCS])
    card = yaml.safe_load(out.draft_yaml)
    assert any(
        q["question"].startswith("spend의 basis, cancellation, exclude_categories, installment: 카드사 기본값이 없어")
        for q in card["open_questions"]
    )


def answer_with_spend(**kw) -> str:
    return json.dumps({"rules": copy.deepcopy(CURRENT), "source": "page", "open_questions": [], **kw})


def test_benefit_without_limits_is_asked(files):
    rules = copy.deepcopy(CURRENT)
    del rules["spend"]
    del rules["benefits"][0]["limits"]
    response = json.dumps({"rules": rules, "effective_from": "2026-09-01", "source": "page", "open_questions": []})
    card = yaml.safe_load(run(files, response).draft_yaml)
    # 프롬프트는 금액을 못 찾은 한도를 빼라고 한다. 새 카드는 견줄 지금 값이 없어 한도 없는 혜택마다 묻는다
    assert any(q["question"].startswith("benefits[cafe-10]: 한도를 적지 않았다") for q in card["open_questions"])


def test_date_before_issuer_defaults_writes_full_rules(files):
    out = run(files, answer(effective_from="2025-06-01"))
    assert out.status == "draft" and out.problems == []
    card = yaml.safe_load(out.draft_yaml)
    # 그날에는 카드사 기본값이 없어 받은 날의 기본값을 카드에 그대로 적는다
    assert card["revisions"][0]["spend"]["basis"] == "prev_calendar_month"
    assert any("카드사 기본값이 시행일 뒤에 시작" in q["question"] for q in card["open_questions"])


def test_future_date_starts_at_the_fetch_day_and_asks(files):
    card = yaml.safe_load(run(files, answer(effective_from="2026-11-01")).draft_yaml)
    assert card["revisions"][0]["effective_from"] == FETCHED and card["revisions"][0]["effective_from_estimated"]
    assert any("2026-11-01" in q["question"] for q in card["open_questions"])


@pytest.mark.parametrize(
    "extra",
    [
        {"kind": "credit", "kind_evidence": "신용카드"},
        {"kind": "check", "kind_evidence": "이 카드는 신용카드입니다."},
    ],
)
def test_short_or_mismatched_kind_evidence_needs_a_person(files, extra):
    # 메뉴의 "신용카드" 한 낱말이나 고른 종류와 어긋난 문장은 근거가 아니다. 2026-10-05 위험 검토
    out = run(files, answer(**extra), {**ROW, "kind": None})
    assert out.status == "needs_human" and "카드 종류" in out.reason


def test_cards_whose_model_call_failed_twice_are_left_for_a_person():
    from cherry_core.pipeline.new_card import drafted_cards

    failed = [("nh-a", "model_error", "x"), ("nh-a", "model_error", "x"), ("nh-b", "model_error", "x")]
    assert drafted_cards(failed, typed=set()) == {"nh-a"}
