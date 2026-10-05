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


def test_issuer_defaults_fill_what_the_model_left_out_when_scoring():
    # 카드사 공통 규칙은 카드 원문에 없을 때가 많다. 카드사 기본값은 카드의 정답이 아니라 공통 규칙이라 채워서 채점한다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    golden = clean_rules({**VALID, "spend": {**VALID["spend"], "exclude_categories": ["tax"]}})
    answer = {k: v for k, v in VALID.items() if k != "spend"}  # 모델이 실적 규칙을 적지 않았다
    defaults = {"spend": {**VALID["spend"], "exclude_categories": ["tax"]}}
    assert all(ok == total for ok, total in score_answer(json.dumps(golden), _answer(answer), defaults).values())
    assert score_answer(json.dumps(golden), _answer(answer))["spend"][0] == 0  # 채우지 않으면 형식 오류다


def test_issuer_defaults_merge_inside_maps_like_card_files():
    # 카드 파일을 합칠 때와 같이 맵 안까지 합친다. 모델이 month_offset 키 하나만 적어도 다른 키는 기본값을 쓴다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    spend = {**VALID["spend"], "month_offset": {"a": 1, "b": 2}}
    golden = clean_rules({**VALID, "spend": spend})
    answer = {**VALID, "spend": {"month_offset": {"a": 1}}}
    result = score_answer(json.dumps(golden), _answer(answer), {"spend": spend})
    assert result["spend"] == (5, 5)  # basis, installment, cancellation, month_offset.a, month_offset.b


def test_issuer_defaults_never_overwrite_what_the_model_wrote():
    # 모델이 interest_free를 exclude로 적었다. 정답은 기본값 count라 칸 하나가 더 있고 틀린다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    golden = clean_rules(VALID)
    answer = {**VALID, "spend": {**VALID["spend"], "interest_free": "exclude"}}
    defaults = {"spend": {**VALID["spend"], "interest_free": "count"}}
    assert score_answer(json.dumps(golden), _answer(answer), defaults)["spend"] == (3, 4)


def test_card_rule_unlike_the_issuer_default_is_still_wrong_when_left_out():
    # 카드가 세금을 실적에서 따로 뺀다. 모델이 실적 규칙을 적지 않으면 기본값으로 채워도 그 칸은 틀린다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    golden = clean_rules({**VALID, "spend": {**VALID["spend"], "exclude_categories": ["tax"]}})
    answer = {k: v for k, v in VALID.items() if k != "spend"}
    assert score_answer(json.dumps(golden), _answer(answer), {"spend": VALID["spend"]})["spend"] == (3, 4)


def test_partial_issuer_default_does_not_break_the_whole_answer():
    # 2026-10-02 신한 신규 회원 기본값은 구간 금액 tier가 없다. 모델이 신규 회원을 안 적은 답에 채우면 필수 칸이 빠져
    # 카드 전체가 0점이 됐다. 채워도 형식이 안 되는 묶음은 채우지 않는다. 신규 회원 3칸만 틀리고 나머지는 맞는다
    import json

    from cherry_core.pipeline.draft import clean_rules
    from cherry_core.pipeline.score import score_answer

    new_card = {"from": "registration", "until": "next_month_end", "tier": 300000}
    golden = clean_rules({**VALID, "new_card": new_card})
    defaults = {"new_card": {"from": "registration", "until": "next_month_end"}}
    result = score_answer(json.dumps(golden), _answer(VALID), defaults)
    assert result["new_card"] == (0, 3)
    assert result["benefits.reward"] == (2, 2) and result["spend"] == (3, 3) and result["tiers"] == (1, 1)


def test_new_card_answer_with_its_own_keys_is_matched_by_content():
    # 새 카드 추출은 key를 모델이 짓는다. key로 맞추면 내용이 같아도 모두 틀려 작업 008 12단계 첫 채점이 2.6%였다
    import copy
    import json

    from cherry_core.pipeline.draft import clean_rules, int_keys
    from cherry_core.pipeline.score import score_answer
    from tests.pipeline.test_draft import CURRENT

    golden = json.dumps(clean_rules(int_keys(copy.deepcopy(CURRENT))))
    renamed = copy.deepcopy(CURRENT)
    renamed["limits"][0]["key"] = "monthly-cap"
    renamed["benefits"][0]["key"] = "coffee-ten"
    renamed["benefits"][0]["limits"] = [{"per": "txn", "amount": 1000}, {"shared": "monthly-cap"}]
    plain = score_answer(golden, _answer(renamed))
    aligned = score_answer(golden, _answer(renamed), align=True)
    assert plain["benefits.reward"][0] == 0
    assert all(ok == total for ok, total in aligned.values())


def test_aligning_keys_pairs_each_golden_item_once_by_most_equal_fields():
    from cherry_core.pipeline.score import align_keys

    expected = {
        "benefits": [{"key": "a", "reward": {"rate": 10}, "target": {"all": True}}, {"key": "b", "reward": {"rate": 5}}]
    }
    actual = {
        "benefits": [
            {"key": "x", "reward": {"rate": 5}},
            {"key": "y", "reward": {"rate": 10}, "target": {"all": True}},
            {"key": "b", "reward": {"rate": 1}},
        ]
    }
    # 같은 칸이 가장 많은 짝부터 정한다. 짝이 없는 추출은 남고, 정답 key와 겹치면 이름을 바꿔 다른 혜택과 섞이지 않는다
    assert [b["key"] for b in align_keys(expected, actual)["benefits"]] == ["b", "a", "b~extra"]
