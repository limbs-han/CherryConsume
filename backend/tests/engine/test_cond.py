"""조건 판정. 참, 거짓, 모름. 설계 2.1, 3.1, 3.2."""

from datetime import UTC, date

from cherry_core.catalog.models import Condition
from cherry_core.engine.cond import Situation, all_of, any_of, category_match, check, is_holiday, unknown
from cherry_core.engine.models import OptionPick, UserCard

from .conftest import at


def sit(**kw) -> Situation:
    base = {
        "at": at("2026-09-19T14:20"),
        "amount": 10000,
        "merchant": None,
        "category": "cafe",
        "channel": "offline",
        "region": "domestic",
        "installment_months": 1,
        "interest_free": False,
        "payment_method": "physical_card",
        "billing": "normal",
        "card": UserCard(id="u", card_id="c"),
    }
    base.update(kw)
    return Situation(**base)


def cond(**kw) -> Condition:
    return Condition.model_validate(kw)


def test_category_tree():
    assert category_match("transit.subway", "transit")[0] is True
    assert category_match("transit.subway", "transit.subway")[0] is True
    assert category_match("transit.subway", "transit.bus_express")[0] is False
    assert category_match("transit", "transit.subway") == unknown("category", "transit")
    assert category_match(None, "cafe")[0] is False


def test_three_valued_and_or():
    t, f, u = (True, frozenset()), (False, frozenset()), unknown("fact", "soldier")
    assert all_of([t, u]) == u and all_of([u, f])[0] is False and all_of([])[0] is True
    assert any_of([f, u]) == u and any_of([u, t])[0] is True and any_of([])[0] is False


def test_amount_range():
    c = cond(amount={"min": 30000, "below": 70000})
    assert [check(c, sit(amount=a))[0] for a in (29999, 30000, 69999, 70000)] == [False, True, True, False]


def test_holidays_include_substitute_and_election():
    assert is_holiday(date(2026, 10, 5))  # 개천절 대체공휴일
    assert is_holiday(date(2026, 6, 3))  # 지방선거일
    assert not is_holiday(date(2026, 10, 6))


def test_time_uses_korean_time():
    c = cond(time={"from": "21:00", "to": "09:00"})
    from datetime import datetime

    utc_1330 = datetime(2026, 9, 19, 13, 30, tzinfo=UTC)  # 한국 시간 22:30
    assert check(c, sit(at=utc_1330))[0] is True


def test_payment_unknown_and_known():
    c = cond(payment=["naver_pay"])
    assert check(c, sit(payment_method=None)) == unknown("payment_method")
    assert check(c, sit(payment_method="naver_pay"))[0] is True
    assert check(cond(payment_not=["naver_pay"]), sit(payment_method=None)) == unknown("payment_method")


def test_option_choice_by_date_and_default():
    picks = [
        OptionPick(option="pkg", choice="p1", effective_from=date(2026, 9, 1)),
        OptionPick(option="pkg", choice="p2", effective_from=date(2026, 10, 1)),
    ]
    card = UserCard(id="u", card_id="c", options=picks)
    c = cond(option={"pkg": ["p2"]})
    assert check(c, sit(card=card))[0] is False
    assert check(c, sit(card=card, at=at("2026-10-01T00:00")))[0] is True
    assert check(c, sit()) == unknown("option", "pkg")
    assert check(c, sit(defaults={"pkg": "p2"}))[0] is True


def test_facts_and_birth_month():
    assert check(cond(fact="soldier"), sit()) == unknown("fact", "soldier")
    card = UserCard(id="u", card_id="c", facts={"soldier": False, "birth_month": 9})
    assert check(cond(fact="soldier"), sit(card=card))[0] is False
    assert check(cond(fact="birth_month_now"), sit(card=card))[0] is True


def test_card_month_and_lump_sum():
    card = UserCard(id="u", card_id="c", started_on=date(2026, 8, 20))
    assert check(cond(card_month={"min": 1}), sit(card=card))[0] is True  # 8월이 0, 9월이 1
    assert check(cond(card_month={"min": 1}), sit()) == unknown("started_on")
    assert check(cond(lump_sum=True), sit(installment_months=3))[0] is False


def test_any_of_unknown_only_when_nothing_true():
    c = cond(any_of=[{"fact": "soldier"}, {"fact": "salary"}])
    card = UserCard(id="u", card_id="c", facts={"salary": True})
    assert check(c, sit(card=card))[0] is True
    assert check(c, sit())[0] is None
    assert check(c, sit())[1] == frozenset({("fact", "soldier"), ("fact", "salary")})
