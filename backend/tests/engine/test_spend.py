"""실적 계산 규칙. 설계 2절. 기대값은 손계산이고 계산을 주석에 한 줄로 적는다."""

from datetime import UTC, date, datetime

import pytest
from pydantic import ValidationError

from .conftest import at, card, holder, pay, prev_month

CAFE_10 = {
    "key": "cafe-10",
    "target": {"categories": ["cafe"]},
    "reward": {"type": "billing_discount", "rate": 10},
    "limits": [{"per": "month", "amount": 5000}],
    "tiers": {"from": 300000},
}
SEPT = date(2026, 9, 1)


def status(eng, payments, holder_card=None, month=SEPT):
    h = holder_card or holder()
    priced = eng.price_month(h, payments)
    done = {r.payment_id: r.benefits for r in priced}
    saved = [p.model_copy(update={"benefits": done.get(p.id, p.benefits)}) for p in payments]
    return eng.spend_status(h, saved, month)


def test_tier_from_previous_month(engine):
    # 지난달 35만 → 30만 구간. 이번 달 18.2만 → 유지까지 30만 − 18.2만 = 11.8만, 60만까지 41.8만. 시안 6쪽
    eng = engine(card([CAFE_10]))
    s = status(eng, prev_month(350000) + [pay(182000, "2026-09-10T12:00", category="other")])
    assert (s.tier, s.tier_source, s.prev_month_counted) == (300000, "prev_month", 350000)
    assert (s.counted, s.to_keep, s.next_tier, s.to_next) == (182000, 118000, 600000, 418000)


def test_tier_lower_bound_boundary(engine):
    # 하한 1원 아래는 아래 구간, 하한은 그 구간
    eng = engine(card([CAFE_10]))
    assert status(eng, prev_month(299999)).tier == 0
    assert status(eng, prev_month(300000)).tier == 300000


def test_registration_month_uses_estimate_only_without_records(engine):
    # E2. 등록한 달에 지난달 기록이 없으면 추정값, 추정값도 없으면 0 구간과 경고, 기록이 있으면 기록
    eng = engine(card([CAFE_10]))
    new = holder(registered_on=date(2026, 9, 10), assumed_prev_month_spend=410000)
    s = status(eng, [], new)
    assert (s.tier, s.tier_source) == (300000, "assumed")  # 시안 4쪽. 지난달 41만이면 30만 구간
    s = status(eng, [], holder(registered_on=date(2026, 9, 10)))
    assert s.tier == 0 and "no_prev_month_data" in [w.code for w in s.warnings]
    s = status(eng, prev_month(100000), new)
    assert (s.tier, s.tier_source, s.prev_month_counted) == (0, "prev_month", 100000)


def test_excluded_category_and_interest_free(engine):
    eng = engine(card([CAFE_10], spend={"interest_free": "exclude"}))
    h = holder()
    tax, free = (
        pay(128000, "2026-09-18T09:00", category="tax"),
        pay(50000, "2026-09-18T10:00", category="other", interest_free=True),
    )
    r = eng.price_month(h, [tax, free])
    assert r[0].spend == [] and r[0].warnings[0].data == {"reason": "category"}  # 시안 10쪽 자동차세 실적 제외
    assert r[1].spend == [] and r[1].warnings[0].data == {"reason": "interest_free"}


def test_parent_category_is_excluded_conservatively(engine):
    # 설계 2.1. 지하철만 빼는 카드에 대중교통까지만 아는 결제는 뺀 것으로 보고 자식 업종을 묻는다
    eng = engine(card([CAFE_10], spend={"exclude_categories": ["transit.subway"]}))
    r = eng.price_month(holder(), [pay(1500, "2026-09-02T08:00", category="transit")])[0]
    assert r.spend == []
    assert ["not_counted_toward_spend", "needs_input"] == [w.code for w in r.warnings][:2]
    assert r.warnings[1].data["needs"] == [("category", "transit")]


def test_region_only_domestic(engine):
    eng = engine(card([CAFE_10], spend={"regions": ["domestic"]}))
    r = eng.price_month(holder(), [pay(30000, "2026-09-02T08:00", category="other", region="overseas")])[0]
    assert r.spend == [] and r.warnings[0].data == {"reason": "region"}


def test_benefit_applied_ratio(engine):
    # 우리 K-LIFE처럼 혜택 받은 결제는 50%만. 30,001원이면 15,000.5 → 원 미만 버림 15,000
    flat = {k: v for k, v in CAFE_10.items() if k != "tiers"}
    eng = engine(card([flat], tiers=(0,), spend={"exclude_applied": 0.5}))
    r = eng.price_month(holder(), [pay(30001, "2026-09-02T08:00", merchant="starbucks")])[0]
    assert r.benefits[0].value == 3000 and r.spend[0].amount == 15000


def test_month_offset_moves_transit_to_next_month(engine):
    # 신한처럼 9월에 탄 지하철은 10월 실적
    eng = engine(card([CAFE_10], spend={"month_offset": {"transit.subway": 1}}))
    r = eng.price_month(holder(), [pay(1500, "2026-09-02T08:00", category="transit.subway")])[0]
    assert [(p.month, p.amount) for p in r.spend] == [(date(2026, 10, 1), 1500)]


def test_installment_split_by_month(engine):
    # E4. 100,000원 3개월이면 33,333, 33,333, 나머지 33,334
    eng = engine(card([CAFE_10], spend={"installment": "per_installment_month"}))
    r = eng.price_month(holder(), [pay(100000, "2026-09-02T08:00", category="other", installment_months=3)])[0]
    assert [p.amount for p in r.spend] == [33333, 33333, 33334]
    assert [p.month.month for p in r.spend] == [9, 10, 11]


def test_cancellation_months(engine):
    # 8월 10만원을 9월 5일에 4만원 취소. cancel_month면 9월에서, original_month면 8월에서 뺀다
    cancelled = {"cancelled_amount": 40000, "cancelled_at": at("2026-09-05T10:00")}
    eng = engine(card([CAFE_10]))
    r = eng.price_month(holder(), [pay(100000, "2026-08-20T10:00", category="other", **cancelled)])[0]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 100000), (9, -40000)]
    eng = engine(
        card(
            [CAFE_10],
            spend={
                "cancellation": "original_month",
                "cancellation_overrides": [{"when": {"region": "overseas"}, "use": "cancel_month"}],
            },
        )
    )
    r = eng.price_month(holder(), [pay(100000, "2026-08-20T10:00", category="other", **cancelled)])[0]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 100000), (8, -40000)]
    r = eng.price_month(holder(), [pay(100000, "2026-08-20T10:00", category="other", region="overseas", **cancelled)])[
        0
    ]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 100000), (9, -40000)]


def test_original_month_cancellation_lowers_this_month_tier(engine):
    # E5. 8월 35만 중 10만을 original_month로 취소하면 8월 25만 → 9월 구간 0
    eng = engine(card([CAFE_10], spend={"cancellation": "original_month"}))
    p = pay(350000, "2026-08-10T10:00", category="other", cancelled_amount=100000, cancelled_at=at("2026-09-03T10:00"))
    assert status(eng, [p]).tier == 0


def test_month_below_zero_counts_as_zero(engine):
    eng = engine(card([CAFE_10]))
    p = pay(50000, "2026-08-31T10:00", category="other", cancelled_amount=50000, cancelled_at=at("2026-09-01T10:00"))
    assert status(eng, [p]).counted == 0


def test_korean_time_month_boundary(engine):
    # E7. 8월 31일 23:30 한국 시간은 8월, 협정 세계시 8월 31일 15:30은 한국 시간 9월 1일 00:30이라 9월
    eng = engine(card([CAFE_10]))
    late = pay(10000, "2026-08-31T23:30", category="other")
    utc = pay(10000, "2026-08-31T23:30", category="other").model_copy(
        update={"paid_at": datetime(2026, 8, 31, 15, 30, tzinfo=UTC)}
    )
    assert eng.price_month(holder(), [late])[0].spend[0].month == date(2026, 8, 1)
    assert eng.price_month(holder(), [utc])[0].spend[0].month == date(2026, 9, 1)


def test_new_card_period(engine):
    # 9월 5일부터 쓴 카드는 9월과 10월에 30만 구간 특례. 11월은 10월 실적대로
    eng = engine(card([CAFE_10], new_card={"from": "registration", "until": "next_month_end", "tier": 300000}))
    new = holder(started_on=date(2026, 9, 5))
    assert (status(eng, [], new).tier, status(eng, [], new).tier_source) == (300000, "new_card")
    assert status(eng, [], new, date(2026, 10, 1)).tier == 300000
    assert status(eng, [], new, date(2026, 11, 1)).tier == 0


def test_new_card_tier_by_benefit(engine):
    # tier_by_benefit 0인 혜택은 특례가 없다
    rules = {
        "new_card": {
            "from": "registration",
            "until": "next_month_end",
            "tier": 300000,
            "tier_by_benefit": {"cafe-10": 0},
        }
    }
    eng = engine(card([CAFE_10], **rules))
    r = eng.price_month(holder(started_on=date(2026, 9, 5)), [pay(10000, "2026-09-10T10:00", merchant="starbucks")])[0]
    assert r.benefits == [] and r.warnings[0].code == "tier_not_met"


def test_basis_none_and_billing_cycle(engine):
    # E6. 실적 조건 없는 카드는 구간을 세지 않고, 결제일 기준 실적 카드는 계산하지 않는다
    flat = {k: v for k, v in CAFE_10.items() if k != "tiers"}
    s = status(engine(card([flat], tiers=(0,), spend={"basis": "none"})), [])
    assert (s.tier, s.tier_source, s.to_keep, s.to_next) == (0, "none", None, None)
    s = status(engine(card([CAFE_10], spend={"basis": "billing_cycle"})), prev_month(350000))
    assert (s.tier, s.tier_source) == (0, "unsupported")
    assert "spend_basis_unsupported" in [w.code for w in s.warnings]


def test_partial_cancellation_counts_like_remaining_amount(engine):
    # 혜택 받은 결제는 50%. 10,001원 중 5,000원 취소면 남은 5,001원의 50% 2,500.5 → 2,500. 5,000 − 2,500 = 2,500을 뺀다
    flat = {k: v for k, v in CAFE_10.items() if k != "tiers"}
    eng = engine(card([flat], tiers=(0,), spend={"exclude_applied": 0.5}))
    p = pay(10001, "2026-09-02T08:00", merchant="starbucks", cancelled_amount=5000, cancelled_at=at("2026-09-03T08:00"))
    r = eng.price_month(holder(), [p])[0]
    assert sum(x.amount for x in r.spend) == 2500


def test_cancellation_cannot_exceed_payment_and_needs_time():
    # 결제보다 큰 취소와 시각 없는 취소는 받지 않는다. 취소한 달 기준 카드에서 달을 정할 수 없다. E5
    with pytest.raises(ValidationError):
        pay(30000, "2026-09-02T08:00", cancelled_amount=50000, cancelled_at=at("2026-09-03T08:00"))
    with pytest.raises(ValidationError):
        pay(30000, "2026-09-02T08:00", cancelled_amount=10000)


def test_month_recompute_after_original_month_cancellation(engine):
    # 8월 100만원 중 10만원을 9월 10일에 결제한 달 기준으로 취소하면 9월 구간이 100만에서 50만으로 내려간다.
    # 서버가 9월을 다시 계산해 9월 5일 5% 5,000원이 1.5% 1,500원이 된다. 2026-09-29 사용자가 정했다. E5
    rates = [
        {**CAFE_10, "key": "cafe-5", "reward": {"type": "billing_discount", "rate": 5}, "tiers": {"from": 1000000}},
        {**CAFE_10, "key": "cafe-15", "reward": {"type": "billing_discount", "rate": 1.5}, "tiers": {"to": 500000}},
    ]
    for r in rates:
        r.pop("limits")
    eng = engine(card(rates, tiers=(0, 500000, 1000000), spend={"cancellation": "original_month"}))
    aug = [pay(900000, "2026-08-10T10:00", category="other"), pay(100000, "2026-08-20T10:00", category="other")]
    sept = pay(100000, "2026-09-05T10:00", merchant="starbucks")
    first = eng.price_month(holder(), aug + [sept])
    assert [b.value for b in first[2].benefits] == [5000]
    saved = [p.model_copy(update={"benefits": r.benefits}) for p, r in zip(aug + [sept], first)]
    saved[1] = saved[1].model_copy(update={"cancelled_amount": 100000, "cancelled_at": at("2026-09-10T10:00")})
    again = eng.price_month(holder(), saved, month=SEPT)
    assert [b.value for b in again[0].benefits] == [1500]


CAFE_MIN_5 = {
    "key": "cafe-min-5",
    "target": {"categories": ["cafe"]},
    "when": [{"amount": {"min": 10000}}],
    "reward": {"type": "billing_discount", "rate": 5},
    "tiers": {"from": 300000},
}


def cancel_on(amount: int, when: str = "2026-09-03T10:00") -> dict:
    return {"cancelled_amount": amount, "cancelled_at": at(when)}


def test_cancelled_benefit_payment_keeps_paid_month_spend(engine):
    # E5, 설계 문서 6.5. 혜택 받은 결제를 실적에서 다 빼고 취소한 달 기준인 카드. 7월 30만으로 8월 30만 구간
    # 8월 카페 2만 원은 10% 2,000원을 받아 실적 0. 기타 29만 원으로 8월 실적 29만. 9월 3일 카페 전액 취소에도 처음 실적이 0이라
    # 뺄 것이 없다. 저장된 기록으로 다시 세도 8월 29만, 9월 0원 구간이다. 취소 뒤 빈 혜택으로 세면 8월이 31만이 되었다
    eng = engine(card([CAFE_10], spend={"exclude_applied": 1, "cancellation": "cancel_month"}))
    payments = [
        *prev_month(300000, "2026-07"),
        pay(20000, "2026-08-10T10:00", category="cafe", **cancel_on(20000)),
        pay(290000, "2026-08-20T10:00", category="other"),
    ]
    s = status(eng, payments)
    assert (s.prev_month_counted, s.tier) == (290000, 0)


def test_cancel_half_excluded_benefit_payment(engine):
    # 혜택 받은 결제를 반만 빼는 카드. 8월 카페 2만 원은 10% 2,000원을 받아 실적 1만
    # 9월 전액 취소면 8월에 1만을 넣고 9월에서 1만을 뺀다
    eng = engine(card([CAFE_10], spend={"exclude_applied": 0.5, "cancellation": "cancel_month"}))
    payments = [*prev_month(300000, "2026-07"), pay(20000, "2026-08-10T10:00", category="cafe", **cancel_on(20000))]
    r = eng.price_month(holder(), payments)[1]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 10000), (9, -10000)]


def test_partial_cancel_never_adds_spend(engine):
    # 8월 카페 12,000원은 1만 원 이상 5%로 600원을 받고 반만 빼 실적 6,000. 9월에 5,000원을 취소하면 남은 7,000원은 혜택을 잃어
    # 실적이 7,000이 되어야 하는지 카드사 문구가 없다. 취소로 실적을 늘리지 않는다. 부풀리지 않는 쪽이다. 확인 필요
    eng = engine(card([CAFE_MIN_5], spend={"exclude_applied": 0.5, "cancellation": "cancel_month"}))
    payments = [*prev_month(300000, "2026-07"), pay(12000, "2026-08-10T10:00", category="cafe", **cancel_on(5000))]
    r = eng.price_month(holder(), payments)[1]
    assert [(p.month.month, p.amount) for p in r.spend] == [(8, 6000)]


def test_cancel_benefit_payment_in_paid_month_basis(engine):
    # 결제한 달 기준이어도 혜택 받아 실적 0인 결제는 전액 취소로 뺄 것이 없다. 8월은 기타 29만 그대로
    eng = engine(card([CAFE_10], spend={"exclude_applied": 1, "cancellation": "original_month"}))
    payments = [
        *prev_month(300000, "2026-07"),
        pay(20000, "2026-08-10T10:00", category="cafe", **cancel_on(20000)),
        pay(290000, "2026-08-20T10:00", category="other"),
    ]
    assert status(eng, payments).prev_month_counted == 290000
