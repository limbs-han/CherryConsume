"""칸마다 정확도. 설계 1절 7단계. 기대값은 칸을 손으로 센 것이다."""

import pytest

from cherry_core.pipeline.score import field_accuracy, total_accuracy

EXPECTED = {
    "tiers": [0, 300000],
    "benefits": [
        {
            "key": "cafe",
            "title": "카페",
            "target": {"categories": ["cafe", "bakery"]},
            "reward": {"type": "billing_discount", "rate": 10},
        }
    ],
}


def test_same_rules_score_full():
    assert field_accuracy(EXPECTED, EXPECTED) == {"benefits.reward": (2, 2), "benefits.target": (1, 1), "tiers": (1, 1)}


def test_wrong_value_and_invented_benefit_count_as_wrong():
    actual = {
        "tiers": [0, 300000],
        "benefits": [
            {
                "key": "cafe",
                "title": "다른 제목",  # 제목은 채점하지 않는다
                "target": {"categories": ["bakery", "cafe"]},  # 순서만 다르다
                "reward": {"type": "billing_discount", "rate": 5},
            },
            {"key": "extra", "target": {"all": True}, "reward": {"type": "cashback", "rate": 1}},
        ],
    }
    # target: cafe.categories 맞음, extra.all 틀림. reward: cafe.type 맞음, cafe.rate 틀림, extra 두 칸 틀림
    assert field_accuracy(EXPECTED, actual) == {"benefits.reward": (1, 4), "benefits.target": (1, 2), "tiers": (1, 1)}


def test_missing_benefit_counts_as_wrong():
    assert field_accuracy(EXPECTED, {"tiers": [0, 300000]}) == {
        "benefits.reward": (0, 2),
        "benefits.target": (0, 1),
        "tiers": (1, 1),
    }


def test_tier_table_keys_are_separate_fields():
    e = {"limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 20000}}]}
    a = {"limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 25000}}]}
    assert field_accuracy(e, a) == {"limits": (2, 3)}


def test_total_accuracy():
    got = total_accuracy([{"tiers": (1, 1), "benefits.reward": (1, 4)}, {"tiers": (0, 1)}])
    assert got == {"all": pytest.approx(2 / 6), "benefits.reward": 0.25, "tiers": 0.5}


VALID = {
    **EXPECTED,
    "spend": {"basis": "prev_calendar_month", "installment": "full_at_purchase", "cancellation": "cancel_month"},
}


def _answer(rules) -> str:
    import json

    return json.dumps({"rules": rules, "effective_from": None, "source": "page", "open_questions": []})


def test_answer_is_scored_against_the_golden_rules_json():
    # 과제 19. 정답은 silver.golden의 규칙 JSON이고 답은 cherry_extract가 남긴 모델 답 원문이다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    golden = json.dumps(clean_rules(VALID))
    wrong = {**VALID, "tiers": [0, 500000]}
    assert score_answer(golden, _answer(VALID)) == field_accuracy(clean_rules(VALID), clean_rules(VALID))
    assert score_answer(golden, _answer(wrong))["tiers"] == (0, 1)


@pytest.mark.parametrize("answer", [None, "답을 못 하겠다", '{"source": "page"}', '{"rules": {"tiers": "많이"}}'])
def test_unusable_answer_scores_zero_on_every_golden_field(answer):
    # 형식 오류로 초안을 못 만든 답도 채점에서 빠지지 않고 모든 칸이 틀린 것이다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    expected = clean_rules(VALID)
    result = score_answer(json.dumps(expected), answer)
    assert result == field_accuracy(expected, {})
    assert all(ok == 0 for ok, _ in result.values())


def test_summary_splits_tune_and_holdout():
    from cherry_core.pipeline.score import summarize

    full = {"tiers": (1, 1), "benefits.reward": (2, 2)}
    half = {"tiers": (0, 1), "benefits.reward": (1, 2)}
    out = summarize([("tune", full), ("tune", half), ("test", half)])
    assert out == {
        "tune.all": 4 / 6,
        "tune.benefits.reward": 3 / 4,
        "tune.tiers": 1 / 2,
        "holdout.all": 1 / 3,
        "holdout.benefits.reward": 1 / 2,
        "holdout.tiers": 0.0,
    }


def test_golden_null_that_a_model_cannot_write_is_not_scored():
    # 한도 조정의 "제한 없음" null은 모델 답에서 안 적은 것으로 지워진다. 설계 1절. 정답 쪽도 같게 지워 채점하지 않는다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    golden = clean_rules(VALID)
    golden["benefits"][0]["note_cap"] = None  # 모델이 적을 수 없는 null 칸
    result = score_answer(json.dumps(golden), _answer(VALID))
    assert all(ok == total for ok, total in result.values())
