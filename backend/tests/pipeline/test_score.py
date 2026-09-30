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
