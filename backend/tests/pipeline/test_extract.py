"""추출 답을 초안과 검수 대기로 바꾸기. 설계 1절 4단계와 5단계. 2026-10-01 답은 JSON만 강제한다."""

import copy
import json

import pytest

from cherry_core.pipeline.extract import pending_changes, process_answer, unqueued
from tests.catalog.conftest import FILES, write_catalog
from tests.pipeline.test_draft import CARD, CURRENT, FETCHED, ISSUER, PATH


@pytest.fixture
def files(tmp_path):
    root = write_catalog(tmp_path / "catalog", copy.deepcopy(FILES))
    return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in root.rglob("*.yaml")}


def answer(rate=10, effective_from=None, **patch) -> str:
    rules = copy.deepcopy(CURRENT)
    rules["benefits"][0]["reward"]["rate"] = rate
    rules.update(patch)
    return json.dumps({"rules": rules, "effective_from": effective_from, "source": "page", "open_questions": []})


def run(files, response, error=None):
    return process_answer(files, PATH, CARD, ISSUER, response, error, FETCHED)


def test_same_rules_make_no_draft(files):
    out = run(files, answer())
    assert (out.status, out.draft_yaml, out.problems) == ("no_change", None, [])


def test_changed_rate_makes_checked_draft(files):
    out = run(files, answer(rate=5))
    assert out.status == "draft"
    assert "rate: 5" in out.draft_yaml
    assert out.problems == []


def test_draft_that_fails_check_is_kept_with_problems(files):
    rules = copy.deepcopy(CURRENT)
    rules["benefits"][0]["target"]["categories"] = ["nope"]
    response = json.dumps({"rules": rules, "effective_from": "2026-11-01", "source": "page", "open_questions": []})
    out = run(files, response)
    assert out.status == "draft"
    assert out.problems and out.problems[0].startswith("error: ")


@pytest.mark.parametrize(
    ("response", "reason"),
    [
        ("답을 못 하겠다", "답을 초안으로 바꾸지 못했다"),  # JSON이 아니다
        ("[]", "답을 초안으로 바꾸지 못했다"),  # 객체가 아니다
        (json.dumps({"effective_from": None, "source": "page"}), "답을 초안으로 바꾸지 못했다"),  # rules가 없다
        (answer(rate="많이"), "규칙 형식 오류 2곳: benefits.0.reward.rate"),  # 숫자나 구간별 맵이어야 한다
        (answer(rate=5, effective_from="2026-06-01"), "앞이다"),  # 마지막 개정보다 앞선 시행일
    ],
)
def test_unusable_answer_goes_to_a_person(files, response, reason):
    out = run(files, response)
    assert out.status == "needs_human"
    assert reason in out.reason
    assert out.draft_yaml is None


def test_model_error_is_retried_not_sent_to_a_person(files):
    # 처리량 초과나 시간 초과는 답이 아니다. 다음 실행에서 다시 추출한다
    out = run(files, None, error="REQUEST_LIMIT_EXCEEDED")
    assert (out.status, out.reason) == ("model_error", "모델 호출 실패: REQUEST_LIMIT_EXCEEDED")


def test_pending_changes_skip_done_ones_but_retry_model_errors():
    changes = [("a", "p1"), ("a", "p2"), ("b", "p3"), ("c", "p4"), ("a", "p1")]
    drafts = [(["p1"], "draft"), (["p3"], "model_error"), (["p4"], "needs_human")]
    assert pending_changes(changes, drafts) == {"a": ["p2"], "b": ["p3"]}


def test_drafts_missing_from_the_queue_are_put_back():
    drafts = [("d1", "draft"), ("d2", "needs_human"), ("d3", "no_change"), ("d4", "model_error"), ("d5", "draft")]
    assert unqueued(drafts, {"d5"}) == ["d1", "d2"]


def test_changes_mode_keeps_current_spend_through_process_answer(files):
    rules = copy.deepcopy(CURRENT)
    rules["benefits"][0]["reward"]["rate"] = 5
    del rules["spend"]  # 공지처럼 실적 규칙이 없는 원문
    response = json.dumps({"rules": rules, "effective_from": None, "source": "page", "open_questions": []})
    kept = process_answer(files, PATH, CARD, ISSUER, response, None, FETCHED, keep_current=True)
    assert kept.status == "draft" and "원문에서 찾지 못해 지금 값을 두었다" in kept.draft_yaml
    graded = process_answer(files, PATH, CARD, ISSUER, response, None, FETCHED)  # 채점은 채우지 않는다
    assert graded.status == "needs_human"


def test_format_error_lists_each_field_for_a_second_ask(files):
    # 2026-10-02 판 6. 모델이 지금 한도 key만 보고 금액 없는 한도를 적었다. 칸마다 오류 문구를 모아 한 번 더 묻는다
    out = run(files, answer(rate=5, limits=[{"key": "integrated", "per": "month"}]))
    assert out.status == "needs_human"
    assert out.errors == ["limits.0: Value error, amount, count, base 중 하나 이상을 쓴다"]


@pytest.mark.parametrize(
    "response",
    [
        "답을 못 하겠다",  # JSON이 아니다. 잘린 답은 다시 물어도 같이 잘린다
        answer(rate=5, effective_from="2026-06-01"),  # 마지막 개정보다 앞선 시행일은 사람이 정할 일이다
    ],
)
def test_only_format_errors_are_asked_again(files, response):
    out = run(files, response)
    assert out.status == "needs_human"
    assert out.errors == []


def test_golden_mode_asks_again_only_what_issuer_defaults_cannot_fill(files):
    # 2026-10-02 위험 검토. 운영은 빠진 실적 규칙을 지금 값으로 채워 다시 묻지 않는다. 정답 예시 모드는 채점처럼
    # 카드사 기본값으로 채워 보고, 그래도 남는 형식 오류만 알려 주고 다시 묻는다
    from cherry_core.pipeline.extract import retry_errors

    def without_installment(**patch):
        rules = json.loads(answer(rate=5, **patch))["rules"]
        del rules["spend"]["installment"]
        return json.dumps({"rules": rules, "effective_from": None, "source": "page", "open_questions": []})

    full = {"spend": {"basis": "prev_calendar_month", "installment": "full_at_purchase", "cancellation": "cancel_month"}}
    response = without_installment()
    out = run(files, response)
    assert out.errors == ["spend.installment: Field required"]
    assert retry_errors(out, response, full) == []  # 기본값으로 채우면 맞는다
    assert retry_errors(out, response, {"spend": {"basis": "prev_calendar_month"}}) == out.errors  # 기본값에도 없다
    assert retry_errors(out, response, None) == out.errors  # 바뀐 원문 모드는 지금 값으로 채운 뒤의 오류다
    assert retry_errors(run(files, answer(rate=5)), answer(rate=5), None) == []  # 형식 오류가 없다
    # 채울 수 있는 칸의 오류는 빼고 남는 오류만 알려 준다. 모델이 할부 값을 지어 기본값을 덮지 않게 한다
    response = without_installment(limits=[{"key": "integrated", "per": "month"}])
    out = run(files, response)
    assert retry_errors(out, response, full) == ["limits.0: Value error, amount, count, base 중 하나 이상을 쓴다"]
