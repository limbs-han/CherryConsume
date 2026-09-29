"""혜택 계산 규칙. 설계 3절. 기대값은 손계산이고 계산을 주석에 한 줄로 적는다."""

from datetime import date

from .conftest import at, card, codes, holder, pay, prev_month, values


def b(key, target, reward, **kw):
    return {"key": key, "target": target, "reward": reward, **kw}


CAFE = {"categories": ["cafe"]}
RATE10 = {"type": "billing_discount", "rate": 10}


def run(eng, payments, h=None):
    return eng.price_month(h or holder(), payments)


def test_rate_with_per_payment_cap(engine):
    # 스타벅스 12,500원 × 10% = 1,250 → 건당 최대 1,000원. 시안 7쪽
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "txn", "amount": 1000}])], tiers=(0,)))
    assert values(run(eng, [pay(12500, "2026-09-19T14:20", merchant="starbucks")])) == [{"cafe-10": 1000}]


def test_monthly_limit_just_before_and_after(engine):
    # 월 5천원. 4만5천원 결제로 4,500을 쓰면 다음 1만원 결제는 1,000이 아니라 남은 500. 그다음은 0
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 5000}])], tiers=(0,)))
    r = run(
        eng,
        [
            pay(45000, "2026-09-01T10:00", merchant="ediya"),
            pay(10000, "2026-09-02T10:00", merchant="ediya"),
            pay(10000, "2026-09-03T10:00", merchant="ediya"),
        ],
    )
    assert values(r) == [{"cafe-10": 4500}, {"cafe-10": 500}, {}]
    assert "limit_exhausted" in codes(r[1]) and "limit_exhausted" in codes(r[2])


def test_limit_resets_next_month(engine):
    # 9월 한도 5천원을 다 써도 10월 1일에 초기화. 시안 14쪽
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 5000}])], tiers=(0,)))
    r = run(eng, [pay(50000, "2026-09-30T23:00", merchant="ediya"), pay(10000, "2026-10-01T00:10", merchant="ediya")])
    assert values(r) == [{"cafe-10": 5000}, {"cafe-10": 1000}]


def test_shared_limit_between_benefits(engine):
    # 카페 10%와 편의점 5%가 통합 1만원을 같이 쓴다. 카페 3,000 + 편의점 1,500 = 4,500 사용. 시안 6쪽
    benefits = [
        b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 5000}, {"shared": "integrated"}]),
        b(
            "cvs-5",
            {"categories": ["convenience"]},
            {"type": "billing_discount", "rate": 5},
            limits=[{"per": "month", "amount": 5000}, {"shared": "integrated"}],
        ),
    ]
    eng = engine(card(benefits, tiers=(0,), limits=[{"key": "integrated", "per": "month", "amount": 10000}]))
    h = holder()
    pays = [pay(30000, "2026-09-02T10:00", merchant="ediya"), pay(30000, "2026-09-03T10:00", merchant="gs25")]
    r = run(eng, pays, h)
    assert values(r) == [{"cafe-10": 3000}, {"cvs-5": 1500}]
    saved = [p.model_copy(update={"benefits": x.benefits}) for p, x in zip(pays, r)]
    uses = {(u.key, u.per): u for u in eng.limit_status(h, saved, at("2026-09-20T12:00"))}
    assert uses[("integrated", "month")].used_amount == 4500 and uses[("integrated", "month")].cap_amount == 10000
    assert uses[("cafe-10", "month")].cap_amount - uses[("cafe-10", "month")].used_amount == 2000


def test_count_limit_per_day(engine):
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "day", "count": 1}])], tiers=(0,)))
    r = run(
        eng,
        [
            pay(5000, "2026-09-02T10:00", merchant="ediya"),
            pay(5000, "2026-09-02T15:00", merchant="ediya"),
            pay(5000, "2026-09-03T10:00", merchant="ediya"),
        ],
    )
    assert values(r) == [{"cafe-10": 500}, {}, {"cafe-10": 500}]


def test_base_limit_per_payment_and_month(engine):
    # 1회 5만원까지: 8만원 × 10%가 아니라 5만원 × 10% = 5,000
    eng = engine(card([b("mart", CAFE, RATE10, limits=[{"per": "txn", "base": 50000}])], tiers=(0,)))
    assert values(run(eng, [pay(80000, "2026-09-02T10:00", merchant="ediya")])) == [{"mart": 5000}]
    # 월 30만원까지: 28만원을 쓴 뒤 5만원 결제는 2만원만 넣어 2,000. 한도가 결제 도중 끝나는 경우
    eng = engine(card([b("mart", CAFE, RATE10, limits=[{"per": "month", "base": 300000}])], tiers=(0,)))
    r = run(eng, [pay(280000, "2026-09-02T10:00", merchant="ediya"), pay(50000, "2026-09-03T10:00", merchant="ediya")])
    assert values(r) == [{"mart": 28000}, {"mart": 2000}]
    assert r[1].benefits[0].base == 20000


def test_limit_table_by_tier(engine):
    # 통합 한도 {30만: 1만, 60만: 2만}. 60만 구간에서 25만원 × 10% = 25,000 → 20,000
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=[{"shared": "integrated"}], tiers={"from": 300000})],
            limits=[{"key": "integrated", "per": "month", "amount": {300000: 10000, 600000: 20000}}],
        )
    )
    assert values(run(eng, prev_month(600000) + [pay(250000, "2026-09-02T10:00", merchant="ediya")]))[1] == {
        "cafe-10": 20000
    }


def test_adjust_by_fact_multiply_and_months(engine):
    base = [{"per": "month", "amount": 1000, "count": 1, "adjust": [{"when": {"fact": "soldier"}, "count": None}]}]
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=base)],
            tiers=(0,),
            facts=[{"key": "soldier", "type": "bool", "scope": "user", "ask": "현역 병사인가요"}],
        )
    )
    two = [pay(5000, "2026-09-02T10:00", merchant="ediya"), pay(5000, "2026-09-03T10:00", merchant="ediya")]
    assert values(run(eng, two)) == [{"cafe-10": 500}, {}]  # 월 1회
    assert values(run(eng, two, holder(facts={"soldier": True}))) == [
        {"cafe-10": 500},
        {"cafe-10": 500},
    ]  # 횟수 제한 없음
    doubled = [
        {
            "per": "month",
            "amount": 1000,
            "adjust": [{"when": {"fact": "birth_month_now"}, "multiply": 2}, {"when": {"months": [5, 12]}, "add": 500}],
        }
    ]
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=doubled)],
            tiers=(0,),
            facts=[{"key": "birth_month", "type": "month", "scope": "user", "ask": "생일이 몇 월인가요"}],
        )
    )
    big = [pay(50000, "2026-09-02T10:00", merchant="ediya")]
    assert values(run(eng, big, holder(facts={"birth_month": 9}))) == [{"cafe-10": 2000}]  # 생일 달 두 배
    assert values(run(eng, [pay(50000, "2026-12-02T10:00", merchant="ediya")])) == [{"cafe-10": 1500}]  # 12월 +500


def test_tiers_to_and_waived_from_only(engine):
    # 나라사랑 편의점: 8만~20만 구간, 급여이체자는 하한 면제. 설계 2.2의 to는 그대로라 25만 구간은 받지 못한다
    nara = b(
        "nara-cvs",
        {"categories": ["convenience"]},
        RATE10,
        tiers={"from": 80000, "to": 200000, "waived_when": {"fact": "salary"}},
    )
    eng = engine(
        card(
            [nara],
            tiers=(0, 80000, 200000, 250000),
            facts=[{"key": "salary", "type": "bool", "scope": "card", "ask": "급여이체"}],
        )
    )
    gs = lambda: pay(5000, "2026-09-02T10:00", merchant="gs25")
    salary = holder(facts={"salary": True})
    assert values(run(eng, [gs()], salary)) == [{"nara-cvs": 500}]  # 0 구간이지만 면제
    assert values(run(eng, prev_month(250000) + [gs()], salary))[1] == {}  # 25만 구간은 급여이체자도 없음
    assert values(run(eng, prev_month(200000) + [gs()]))[1] == {"nara-cvs": 500}
    r = run(eng, [gs()])[0]
    assert r.benefits == [] and "needs_input" in codes(r)  # 급여이체 여부를 모르면 묻는다


def test_day_and_holidays(engine):
    weekend = lambda h: b("wk", CAFE, RATE10, when=[{"day": {"in": ["sat", "sun"], "holidays": h}}])
    sat_holiday = pay(10000, "2026-10-03T10:00", merchant="ediya")  # 개천절, 토요일
    mon_substitute = pay(10000, "2026-10-05T10:00", merchant="ediya")  # 개천절 대체공휴일, 월요일
    for mode, expected in [
        ("ignore", [1000, 0]),
        ("include", [1000, 1000]),
        ("exclude", [0, 0]),
        ("only", [1000, 1000]),
    ]:
        eng = engine(card([weekend(mode)], tiers=(0,)))
        got = [sum(v.values()) for v in values(run(eng, [sat_holiday, mon_substitute]))]
        assert got == expected, mode


def test_time_range_across_midnight(engine):
    eng = engine(card([b("night", CAFE, RATE10, when=[{"time": {"from": "21:00", "to": "09:00"}}])], tiers=(0,)))
    times = ["2026-09-02T23:30", "2026-09-03T08:59", "2026-09-03T09:00", "2026-09-03T20:59", "2026-09-03T21:00"]
    got = [bool(v) for v in values(run(eng, [pay(10000, t, merchant="ediya") for t in times]))]
    assert got == [True, True, False, False, True]


def test_unknown_payment_method(engine):
    # 결제수단을 모르면 저장한 결제는 혜택 0에 needs_input. 설계 3.1
    eng = engine(card([b("npay", CAFE, RATE10, when=[{"payment": ["naver_pay"]}])], tiers=(0,)))
    r = run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["payment_method"]]
    r = run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya", payment_method="naver_pay")])[0]
    assert values([r]) == [{"npay": 1000}]


def test_parent_category_target_is_unknown(engine):
    eng = engine(card([b("burger", {"categories": ["restaurant.fastfood"]}, RATE10)], tiers=(0,)))
    r = run(eng, [pay(10000, "2026-09-02T12:00", category="restaurant")])[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["category", "restaurant"]]
    assert values(run(eng, [pay(10000, "2026-09-02T12:00", category="restaurant.fastfood")])) == [{"burger": 1000}]


def test_common_exclusion_and_explicit_target(engine):
    # 공통 제외 업종이어도 혜택이 대상으로 직접 적었으면 받는다. 무이자할부는 늘 뺀다. 설계 3.2의 3
    benefits = [
        b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1}),
        b("tax-3", {"categories": ["tax"]}, {"type": "billing_discount", "rate": 3}, stack="tax"),
    ]
    eng = engine(
        card(
            benefits,
            tiers=(0,),
            stacks=[{"key": "tax"}],
            benefit_exclusions={"categories": ["tax"], "when_any": [{"interest_free": True}]},
        )
    )
    r = run(
        eng,
        [
            pay(100000, "2026-09-02T12:00", category="tax"),
            pay(100000, "2026-09-03T12:00", category="other", interest_free=True),
        ],
    )
    assert values(r) == [{"tax-3": 3000}, {}]


def test_stack_best_and_other_stack_adds(engine):
    # 같은 묶음은 큰 쪽 하나, 다른 묶음은 더한다. 카페 10% 1,000 vs 전가맹점 1% 100 → 1,000. 간편결제 묶음 2% 200 더함
    benefits = [
        b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1}),
        b("cafe-10", CAFE, RATE10),
        b(
            "pay-2",
            {"all": True},
            {"type": "billing_discount", "rate": 2},
            when=[{"payment": ["naver_pay"]}],
            stack="pay",
        ),
    ]
    eng = engine(card(benefits, tiers=(0,), stacks=[{"key": "pay"}]))
    assert values(run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya", payment_method="naver_pay")])) == [
        {"cafe-10": 1000, "pay-2": 200}
    ]


def test_priority_split(engine):
    # 현대카드M처럼 5% 영역 한도를 넘은 금액은 1.5%. 10만원: 5% 월 한도 2,000P → 4만원분, 나머지 6만원 × 1.5% = 900
    benefits = [
        b("base-1-5", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.5}),
        b(
            "area-5",
            CAFE,
            {"type": "points", "program": "test_point", "rate": 5},
            limits=[{"per": "month", "amount": 2000}],
        ),
    ]
    stacks = [{"key": "main", "pick": "priority", "order": ["area-5", "base-1-5"], "spill": "split"}]
    eng = engine(card(benefits, tiers=(0,), stacks=stacks))
    r = run(eng, [pay(100000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"area-5": 2000, "base-1-5": 900}]
    assert [x.base for x in r.benefits] == [40000, 60000]


def test_priority_without_split_moves_on_when_exhausted(engine):
    # 삼성 iD ON처럼 3% 한도를 다 쓴 다음 결제부터 1%. 같은 결제 안에서는 나누지 않는다
    benefits = [
        b("over-3", {"all": True}, {"type": "billing_discount", "rate": 3}, limits=[{"per": "month", "amount": 1000}]),
        b("over-1", {"all": True}, {"type": "billing_discount", "rate": 1}),
    ]
    eng = engine(
        card(benefits, tiers=(0,), stacks=[{"key": "main", "pick": "priority", "order": ["over-3", "over-1"]}])
    )
    r = run(eng, [pay(50000, "2026-09-02T10:00", category="other"), pay(10000, "2026-09-03T10:00", category="other")])
    assert values(r) == [{"over-3": 1000}, {"over-1": 100}]


def test_month_total_fixed(engine):
    # 카카오뱅크처럼 후불교통 한 달 합 5만원 이상이면 4천원. 3만 → 0, 2만5천 → 합 5만5천이라 4,000, 1만 → 0
    t = b(
        "transit-4000",
        {"categories": ["transit.subway"]},
        {"type": "cashback", "fixed": 4000, "basis": "month_total"},
        when=[{"month_total": {"min": 50000}}],
        limits=[{"per": "month", "count": 1}],
    )
    eng = engine(card([t], tiers=(0,)))
    r = run(
        eng,
        [
            pay(30000, "2026-09-10T08:00", category="transit.subway"),
            pay(25000, "2026-09-20T08:00", category="transit.subway"),
            pay(10000, "2026-09-25T08:00", category="transit.subway"),
        ],
    )
    assert values(r) == [{}, {"transit-4000": 4000}, {}]


def test_month_total_rate(engine):
    # LOCA 365처럼 한 달 합 2만원 이상이면 합의 10%, 월 5천원. 1만5천 → 0, 1만 → 합 2만5천의 10% 2,500, 3만 → 합 5만5천의 10% 5,500 중 한도 남은 2,500
    t = b(
        "transit-10",
        {"categories": ["transit.subway"]},
        {"type": "billing_discount", "rate": 10, "basis": "month_total"},
        when=[{"month_total": {"min": 20000}}],
        limits=[{"per": "month", "amount": 5000}],
    )
    eng = engine(card([t], tiers=(0,)))
    r = run(
        eng,
        [
            pay(15000, "2026-09-10T08:00", category="transit.subway"),
            pay(10000, "2026-09-20T08:00", category="transit.subway"),
            pay(30000, "2026-09-25T08:00", category="transit.subway"),
        ],
    )
    assert values(r) == [{}, {"transit-10": 2500}, {"transit-10": 2500}]


def test_ranked_area_and_final(engine):
    # 삼성 iD ON처럼 커피와 배달 중 이번 달 1위만 30%. 스타벅스와 이디야는 area coffee로 한 영역
    benefits = [
        b(
            "coffee",
            {"merchants": ["ediya"]},
            {"type": "billing_discount", "rate": 30},
            when=[{"ranked": "top"}],
            area="coffee",
            stack="area",
        ),
        b(
            "coffee-sb",
            {"merchants": ["starbucks"]},
            {"type": "billing_discount", "rate": 30},
            when=[{"ranked": "top"}],
            area="coffee",
            stack="area",
        ),
        b(
            "delivery",
            {"merchants": ["baemin"]},
            {"type": "billing_discount", "rate": 30},
            when=[{"ranked": "top"}],
            stack="area",
        ),
    ]
    eng = engine(card(benefits, tiers=(0,), ranked=[{"key": "top", "top": 1}], stacks=[{"key": "area"}]))
    h = holder()
    pays = [
        pay(10000, "2026-09-02T10:00", merchant="ediya"),
        pay(20000, "2026-09-03T19:00", merchant="baemin"),
        pay(15000, "2026-09-04T10:00", merchant="starbucks"),
    ]
    r = run(eng, pays, h)
    # 1: 커피 1만 1위 → 3,000. 2: 배달 2만이 커피 1만을 넘어 1위 → 6,000. 3: 커피 2만5천 → 1위 → 4,500
    assert values(r) == [{"coffee": 3000}, {"delivery": 6000}, {"coffee-sb": 4500}]
    assert "ranked_provisional" in codes(r[0])
    # 달이 끝나면 최종 순위로 다시 계산. 커피 2만5천이 배달 2만보다 커서 배달은 0. 설계 3.5
    saved = [p.model_copy(update={"benefits": x.benefits}) for p, x in zip(pays, r)]
    final = eng.price_month(h, saved, month=date(2026, 9, 1), final=True)
    assert values(final) == [{"coffee": 3000}, {}, {"coffee-sb": 4500}]
    assert "ranked_provisional" not in codes(final[0])


def test_onsite_discount_back_calculation(engine):
    # 현장할인 10%: 기록 9,000원 → 할인 전 10,000원, 할인 1,000원. 1만원 이상 조건은 할인 전 금액으로 본다. 실적은 9,000
    t = b(
        "px",
        {"categories": ["convenience"]},
        {"type": "onsite_discount", "rate": 10},
        when=[{"amount": {"min": 10000}}],
    )
    eng = engine(card([t], tiers=(0,)))
    r = run(eng, [pay(9000, "2026-09-02T10:00", merchant="gs25")])[0]
    assert values([r]) == [{"px": 1000}] and r.benefits[0].base == 10000 and r.spend[0].amount == 9000


def test_per_unit_per_liter_points_and_rounding(engine):
    per_unit = b(
        "unit",
        {"categories": ["other"]},
        {"type": "points", "program": "test_point", "per_unit": {"unit": 20000, "amount": 1000}},
    )
    assert values(run(engine(card([per_unit], tiers=(0,))), [pay(45000, "2026-09-02T10:00", category="other")])) == [
        {"unit": 2000}
    ]  # 2만원당 1천P, 남는 5천원은 버림
    fuel = b("fuel", {"categories": ["fuel"]}, {"type": "billing_discount", "per_liter": 60})
    assert values(run(engine(card([fuel], tiers=(0,))), [pay(85000, "2026-09-02T10:00", merchant="sk_energy")])) == [
        {"fuel": 3000}
    ]  # 85,000 ÷ 1,700 = 50L × 60
    half_up = b("m", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.5, "round": "round"})
    assert values(run(engine(card([half_up], tiers=(0,))), [pay(4639, "2026-09-02T10:00", category="other")])) == [
        {"m": 70}
    ]  # 69.585 반올림. 현대카드M 원문 예시
    floor = b("m", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.5})
    assert values(run(engine(card([floor], tiers=(0,))), [pay(4639, "2026-09-02T10:00", category="other")])) == [
        {"m": 69}
    ]


def test_options_default_change_and_missing(engine):
    opt = {
        "key": "pkg",
        "title": "패키지",
        "choices": [{"key": "p1", "title": "1"}, {"key": "p2", "title": "2"}],
        "change": "next_month",
    }
    benefits = [
        b("p1-cafe", CAFE, RATE10, when=[{"option": {"pkg": ["p1"]}}]),
        b("p2-cafe", CAFE, {"type": "billing_discount", "rate": 20}, when=[{"option": {"pkg": ["p2"]}}]),
    ]
    eng = engine(card(benefits, tiers=(0,), options=[opt]))
    sept = [pay(10000, "2026-09-20T10:00", merchant="ediya")]
    r = run(eng, sept)[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["option", "pkg"]]
    picks = [
        {"option": "pkg", "choice": "p1", "effective_from": date(2026, 9, 1)},
        {"option": "pkg", "choice": "p2", "effective_from": date(2026, 10, 1)},
    ]
    h = holder(options=picks)
    assert values(run(eng, sept + [pay(10000, "2026-10-02T10:00", merchant="ediya")], h)) == [
        {"p1-cafe": 1000},
        {"p2-cafe": 2000},
    ]
    eng = engine(card(benefits, tiers=(0,), options=[{**opt, "default": "p2"}]))
    assert values(run(eng, sept)) == [{"p2-cafe": 2000}]  # 고르지 않으면 카드사 기본값


def test_card_month_and_promo_period(engine):
    # 생활혜택은 카드 등록 달에는 없다. 행사 혜택은 기간 안에만
    benefits = [
        b("life", CAFE, RATE10, when=[{"card_month": {"min": 1}}]),
        b(
            "promo",
            {"merchants": ["gs25"]},
            {"type": "cashback", "fixed": 1000},
            valid_from=date(2026, 9, 10),
            valid_until=date(2026, 9, 30),
        ),
    ]
    eng = engine(card(benefits, tiers=(0,)))
    h = holder(started_on=date(2026, 9, 5))
    r = run(
        eng, [pay(10000, "2026-09-20T10:00", merchant="ediya"), pay(10000, "2026-10-02T10:00", merchant="ediya")], h
    )
    assert values(r) == [{}, {"life": 1000}]
    r = run(eng, [pay(10000, "2026-09-20T10:00", merchant="ediya")])[0]
    assert r.benefits == [] and r.warnings[0].data["needs"] == [["started_on"]]
    r = run(
        eng,
        [
            pay(5000, "2026-09-09T10:00", merchant="gs25"),
            pay(5000, "2026-09-10T10:00", merchant="gs25"),
            pay(5000, "2026-10-01T10:00", merchant="gs25"),
        ],
    )
    assert values(r) == [{}, {"promo": 1000}, {}]


def test_revision_estimated_and_missing(engine):
    eng = engine(card([b("cafe-10", CAFE, RATE10)], tiers=(0,), start=date(2026, 9, 1), estimated=True))
    r = run(eng, [pay(10000, "2026-08-20T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"cafe-10": 1000}] and "revision_estimated" in codes(r)
    eng = engine(card([b("cafe-10", CAFE, RATE10)], tiers=(0,), start=date(2026, 9, 1)))
    r = run(eng, [pay(10000, "2026-08-20T10:00", merchant="ediya")])[0]
    assert r.benefits == [] and codes(r) == ["no_revision"]


def test_unmodeled_is_computed_with_warning(engine):
    # E12. 문장으로 남긴 조건은 없는 것처럼 계산하고 문장을 경고에 담는다
    eng = engine(card([b("cafe-10", CAFE, RATE10, unmodeled=["백화점 안 매장은 제외"])], tiers=(0,)))
    r = run(eng, [pay(10000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"cafe-10": 1000}]
    assert [w.data for w in r.warnings if w.code == "check_conditions"] == [{"sentences": ["백화점 안 매장은 제외"]}]


def test_full_cancellation_gives_nothing(engine):
    # E5. 전액 취소된 결제는 혜택 0이고 한도도 쓰지 않는다
    eng = engine(card([b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 1000}])], tiers=(0,)))
    gone = pay(10000, "2026-09-02T10:00", merchant="ediya", cancelled_amount=10000, cancelled_at=at("2026-09-03T10:00"))
    assert values(run(eng, [gone, pay(10000, "2026-09-04T10:00", merchant="ediya")])) == [{}, {"cafe-10": 1000}]


def test_same_input_same_output_and_integers(engine):
    eng = engine(card([b("m", {"all": True}, {"type": "points", "program": "test_point", "rate": 1.3})], tiers=(0,)))
    pays = [pay(12345, "2026-09-02T10:00", category="other"), pay(67891, "2026-09-03T10:00", category="other")]
    first, second = run(eng, pays), run(eng, pays)
    assert first == second
    assert all(
        isinstance(x.value, int) and isinstance(x.amount, int) and isinstance(x.base, int)
        for r in first
        for x in r.benefits
    )
    assert values(first) == [{"m": 160}, {"m": 882}]  # 12,345 × 1.3% = 160.485, 67,891 × 1.3% = 882.583 → 버림


def test_new_card_tier_decides_ranked_top(engine):
    # KB Easy all처럼 상위 몇 개가 구간표인데 새 카드면 특례 구간으로 센다. 표 대조에서 찾았다
    benefits = [
        b("coffee", {"merchants": ["ediya"]}, RATE10, when=[{"ranked": "top"}], tiers={"from": 300000}),
        b("delivery", {"merchants": ["baemin"]}, RATE10, when=[{"ranked": "top"}], tiers={"from": 300000}),
    ]
    rules = {
        "ranked": [{"key": "top", "top": {300000: 1}}],
        "new_card": {"from": "registration", "until": "next_month_end", "tier": 300000},
    }
    eng = engine(card(benefits, **rules))
    r = run(eng, [pay(10000, "2026-09-10T10:00", merchant="ediya")], holder(started_on=date(2026, 9, 5)))
    assert values(r) == [{"coffee": 1000}]


def test_waived_unknown_reports_tier_and_input(engine):
    # 나라사랑처럼 급여이체자면 하한 면제인데 급여이체 여부를 모르면 구간 미달과 묻기를 함께 붙인다. 표 대조에서 찾았다
    nara = b(
        "nara-cvs", {"categories": ["convenience"]}, RATE10, tiers={"from": 80000, "waived_when": {"fact": "salary"}}
    )
    eng = engine(
        card([nara], tiers=(0, 80000), facts=[{"key": "salary", "type": "bool", "scope": "card", "ask": "급여이체"}])
    )
    r = run(eng, prev_month(79999) + [pay(8000, "2026-09-01T12:00", merchant="gs25")])[1]
    assert r.benefits == [] and {"tier_not_met", "needs_input"} <= set(codes(r))


def test_unknown_adjust_asks(engine):
    # My WE:SH처럼 한도 조건이 모름이면 한도를 늘리지 않고 묻는다. 표 대조에서 찾았다
    doubled = [{"per": "month", "amount": 1000, "adjust": [{"when": {"fact": "birth_month_now"}, "multiply": 2}]}]
    eng = engine(
        card(
            [b("cafe-10", CAFE, RATE10, limits=doubled)],
            tiers=(0,),
            facts=[{"key": "birth_month", "type": "month", "scope": "user", "ask": "생일"}],
        )
    )
    r = run(eng, [pay(50000, "2026-09-02T10:00", merchant="ediya")])[0]
    assert values([r]) == [{"cafe-10": 1000}]
    assert ["fact", "birth_month"] in next(w for w in r.warnings if w.code == "needs_input").data["needs"]


def test_onsite_discount_with_cap(engine):
    # 현장할인 20%에 건당 4만원 한도. 기록 170,000원이면 할인 4만원, 할인 전 210,000원. 식대로 212,500원으로 부풀리지 않는다
    t = b(
        "outback",
        {"categories": ["restaurant"]},
        {"type": "onsite_discount", "rate": 20},
        limits=[{"per": "txn", "amount": 40000}],
    )
    r = run(engine(card([t], tiers=(0,))), [pay(170000, "2026-09-02T19:00", category="restaurant")])[0]
    assert values([r]) == [{"outback": 40000}] and r.benefits[0].base == 210000


def test_limit_exhausted_only_for_period_limits(engine):
    # 건당 최대 1,000원으로 줄어든 것은 한도를 다 쓴 것이 아니다. 달 한도로 줄면 붙인다
    per_txn = b("cafe-10", CAFE, RATE10, limits=[{"per": "txn", "amount": 1000}])
    r = run(engine(card([per_txn], tiers=(0,))), [pay(12500, "2026-09-02T10:00", merchant="ediya")])[0]
    assert "limit_exhausted" not in codes(r)
    monthly = b("cafe-10", CAFE, RATE10, limits=[{"per": "month", "amount": 1000}])
    r = run(engine(card([monthly], tiers=(0,))), [pay(12500, "2026-09-02T10:00", merchant="ediya")])[0]
    assert "limit_exhausted" in codes(r)


def test_common_exclusion_skipped_only_for_listed_category(engine):
    # 가맹점만 적은 혜택은 결제 업종으로 공통 제외를 본다. 이마트에서 산 상품권 5만원은 0원, 장보기 5만원은 2,500원.
    # 업종을 직접 적은 혜택은 공통 제외보다 우선한다. 2026-09-29 사용자가 정했다. 설계 3.2의 3
    benefits = [
        b("gs-5", {"merchants": ["gs25"]}, {"type": "billing_discount", "rate": 5}),
        b("tax-3", {"categories": ["tax"]}, {"type": "billing_discount", "rate": 3}, stack="tax"),
    ]
    eng = engine(
        card(benefits, tiers=(0,), stacks=[{"key": "tax"}], benefit_exclusions={"categories": ["tax", "other"]})
    )
    r = run(
        eng,
        [
            pay(50000, "2026-09-02T10:00", merchant="gs25", category="other"),
            pay(50000, "2026-09-03T10:00", merchant="gs25"),
            pay(100000, "2026-09-04T10:00", category="tax"),
        ],
    )
    assert values(r) == [{}, {"gs-5": 2500}, {"tax-3": 3000}]
