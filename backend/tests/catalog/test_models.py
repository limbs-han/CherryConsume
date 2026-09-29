"""한 객체 안에서 끝나는 규칙. 설계 2.4부터 2.11."""

import pytest
from pydantic import ValidationError

from cherry_core.catalog.models import Adjust, Condition, Fact, Limit, Option, Reward, SharedLimit, Target


def test_reward_needs_exactly_one_amount_rule():
    Reward(type="billing_discount", rate=10)
    Reward(type="billing_discount", per_unit={"unit": 20000, "amount": 1000})
    with pytest.raises(ValidationError, match="정확히 하나"):
        Reward(type="billing_discount", rate=10, fixed=1000)
    with pytest.raises(ValidationError, match="정확히 하나"):
        Reward(type="billing_discount")


def test_points_need_program_and_others_do_not():
    Reward(type="points", program="mysinhan_point", rate=1.5)
    with pytest.raises(ValidationError, match="program"):
        Reward(type="points", rate=1.5)
    with pytest.raises(ValidationError, match="program"):
        Reward(type="cashback", program="mysinhan_point", rate=1)


def test_rate_table_and_rate_range():
    Reward(type="billing_discount", rate={0: 0.5, 1500000: 1.0})
    with pytest.raises(ValidationError):
        Reward(type="billing_discount", rate=0)
    with pytest.raises(ValidationError):
        Reward(type="billing_discount", rate=101)


def test_money_is_strict_integer():
    Limit(per="txn", amount=1000)
    for bad in ["1000", 1000.5, True, -1]:
        with pytest.raises(ValidationError):
            Limit(per="txn", amount=bad)


def test_condition_is_not_empty():
    Condition(region="overseas")
    with pytest.raises(ValidationError, match="빈 조건"):
        Condition()
    with pytest.raises(ValidationError, match="빈 조건"):
        Condition(region=None)


def test_amount_range_and_time_format():
    Condition(amount={"min": 30000, "below": 100000})
    with pytest.raises(ValidationError, match="below보다 작아야"):
        Condition(amount={"min": 100000, "below": 30000})
    Condition(time={"from": "21:00", "to": "09:00"})
    with pytest.raises(ValidationError):
        Condition(time={"from": "25:00", "to": "09:00"})
    with pytest.raises(ValidationError):
        Condition.model_validate({"time": {"from": 1260, "to": "09:00"}})


def test_day_condition():
    Condition.model_validate({"day": {"in": ["sat", "sun"], "holidays": "exclude"}})
    Condition.model_validate({"day": {"holidays": "only"}})
    with pytest.raises(ValidationError, match="holidays: only"):
        Condition.model_validate({"day": {"holidays": "exclude"}})
    with pytest.raises(ValidationError):
        Condition.model_validate({"day": {"in": ["saturday"]}})


def test_limit_is_shared_or_spec():
    Limit(shared="integrated")
    Limit(per="month", count=10)
    with pytest.raises(ValidationError, match="shared를 쓰면"):
        Limit(shared="integrated", per="month", amount=1000)
    with pytest.raises(ValidationError, match="per와 amount"):
        Limit(per="month")
    with pytest.raises(ValidationError, match="amount, count, base"):
        SharedLimit(key="integrated", per="month")


def test_adjust_null_means_unlimited():
    a = Adjust.model_validate({"when": {"fact": "salary_transfer"}, "count": None})
    assert a.count is None
    with pytest.raises(ValidationError, match="multiply"):
        Adjust.model_validate({"when": {"fact": "salary_transfer"}})


def test_target_all_or_lists():
    Target(all=True)
    Target(merchants=["starbucks"])
    with pytest.raises(ValidationError, match="함께 쓰지 않는다"):
        Target(all=True, categories=["cafe"])
    with pytest.raises(ValidationError, match="하나를 쓴다"):
        Target()


def test_option_default_and_unsupported_are_choices():
    choices = [{"key": "auto", "title": "Auto"}, {"key": "diy", "title": "DIY"}]
    Option(key="mode", title="모드", choices=choices, default="auto", change="next_month", unsupported=["diy"])
    with pytest.raises(ValidationError, match="default"):
        Option(key="mode", title="모드", choices=choices, default="x", change="next_month")
    with pytest.raises(ValidationError, match="unsupported"):
        Option(key="mode", title="모드", choices=choices, change="next_month", unsupported=["x"])


def test_choice_fact_needs_choices():
    Fact(key="soldier", type="bool", scope="user", ask="현역 병사인가요")
    Fact(key="grade", type="choice", scope="user", ask="등급은", choices=["a", "b"])
    with pytest.raises(ValidationError, match="choices"):
        Fact(key="grade", type="choice", scope="user", ask="등급은")


def test_unknown_field_is_rejected():
    with pytest.raises(ValidationError, match="Extra inputs"):
        Reward.model_validate({"type": "billing_discount", "rate": 10, "rat": 5})
