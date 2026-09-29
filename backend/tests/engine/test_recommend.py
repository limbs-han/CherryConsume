"""추천. 설계 4절. 기대값은 손계산이다."""

from datetime import date

from cherry_core.engine.models import Query

from .conftest import at, card, holder, pay, prev_month

NOW = at("2026-09-19T14:20")


def b(key, target, reward, **kw):
    return {"key": key, "target": target, "reward": reward, **kw}


def two_cards(engine):
    cafe = card(
        [
            b(
                "cafe-10",
                {"categories": ["cafe"]},
                {"type": "billing_discount", "rate": 10},
                limits=[{"per": "txn", "amount": 1000}],
            )
        ],
        id="test-cafe",
        tiers=(0,),
    )
    flat = card([b("all-07", {"all": True}, {"type": "billing_discount", "rate": 0.7})], id="test-flat", tiers=(0,))
    return engine(cafe, flat), holder(id="a", card_id="test-cafe"), holder(id="b", card_id="test-flat")


def test_order_by_value_and_default_amount(engine):
    # 1만원 기준: 카페 카드 1,000원, 0.7% 카드 70원. 시안 9쪽의 1위와 2위
    eng, cafe, flat = two_cards(engine)
    [rows] = eng.recommend([cafe, flat], {}, [Query(merchant="starbucks")], NOW)
    assert [(r.card_id, r.value) for r in rows] == [("test-cafe", 1000), ("test-flat", 70)]
    assert "default_amount_used" in [w.code for w in rows[0].warnings]


def test_tie_prefers_card_short_of_tier(engine):
    # 기대 혜택이 같으면 이번 결제가 실적에 들어가고 유지까지 남은 금액이 적은 카드가 앞. S5
    one = card([b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1})], id="test-one")
    two = card([b("all-1", {"all": True}, {"type": "billing_discount", "rate": 1})], id="test-two")
    eng = engine(one, two)
    a, c = holder(id="a", card_id="test-one"), holder(id="c", card_id="test-two")
    history = {
        "a": [
            p.model_copy(update={"user_card_id": "a"})
            for p in prev_month(350000) + [pay(100000, "2026-09-05T10:00", category="other")]
        ],
        "c": [
            p.model_copy(update={"user_card_id": "c"})
            for p in prev_month(350000) + [pay(250000, "2026-09-05T10:00", category="other")]
        ],
    }
    [rows] = eng.recommend([a, c], history, [Query(category="other", amount=10000)], NOW)
    assert [(r.card_id, r.to_keep) for r in rows] == [("test-two", 50000), ("test-one", 200000)]


def test_locked_benefit(engine):
    # 90만 구간 스타벅스 20%. 이번 달 18.2만이면 71.8만 더. 1만원 × 20% = 2,000. 시안 9쪽
    sb = b("sb-20", {"merchants": ["starbucks"]}, {"type": "billing_discount", "rate": 20}, tiers={"from": 900000})
    eng = engine(card([sb], id="test-mr", tiers=(0, 300000, 600000, 900000)))
    h = holder(id="m", card_id="test-mr")
    history = {
        "m": [
            p.model_copy(update={"user_card_id": "m"})
            for p in prev_month(410000) + [pay(182000, "2026-09-05T10:00", category="other")]
        ]
    }
    [rows] = eng.recommend([h], history, [Query(merchant="starbucks")], NOW)
    [lock] = rows[0].locked
    assert (lock.benefit, lock.required_tier, lock.remaining_this_month, lock.value_if_unlocked) == (
        "sb-20",
        900000,
        718000,
        2000,
    )


def test_conditional_payment_method_and_fact(engine):
    # 네이버페이면 +1,000원, 현역병이면 +1,500원
    benefits = [
        b(
            "npay",
            {"categories": ["cafe"]},
            {"type": "billing_discount", "rate": 10},
            when=[{"payment": ["naver_pay"]}],
        ),
        b("px", {"categories": ["convenience"]}, {"type": "billing_discount", "rate": 15}, when=[{"fact": "soldier"}]),
    ]
    eng = engine(
        card(
            benefits,
            id="test-c",
            tiers=(0,),
            facts=[{"key": "soldier", "type": "bool", "scope": "user", "ask": "현역병인가요"}],
        )
    )
    h = holder(id="c", card_id="test-c")
    [cafe_rows, cvs_rows] = eng.recommend(
        [h], {}, [Query(merchant="ediya", amount=10000), Query(merchant="gs25", amount=10000)], NOW
    )
    assert cafe_rows[0].value == 0
    assert [(c.benefit, c.needs, c.extra) for c in cafe_rows[0].conditional] == [
        ("npay", {"payment_method": "naver_pay"}, 1000)
    ]
    assert [(c.benefit, c.needs, c.extra) for c in cvs_rows[0].conditional] == [("px", {"fact": "soldier"}, 1500)]


def test_removed_card_and_category_query(engine):
    # 해지한 카드는 빼고, 업종만 준 질문은 업종별 1순위에 쓴다. S9, 시안 8쪽
    eng, cafe, flat = two_cards(engine)
    gone = cafe.model_copy(update={"removed": True})
    [rows] = eng.recommend([gone, flat], {}, [Query(category="cafe")], NOW)
    assert [r.card_id for r in rows] == ["test-flat"]


def test_recommend_does_not_use_later_payments(engine):
    # 지금보다 뒤에 적힌 결제는 한도 사용량에 넣지 않는다
    eng = engine(
        card(
            [
                b(
                    "cafe-10",
                    {"categories": ["cafe"]},
                    {"type": "billing_discount", "rate": 10},
                    limits=[{"per": "month", "amount": 1000}],
                )
            ],
            id="test-l",
            tiers=(0,),
        )
    )
    h = holder(id="l", card_id="test-l")
    later = pay(10000, "2026-09-25T10:00", merchant="ediya").model_copy(update={"user_card_id": "l"})
    priced = eng.price_month(h, [later])
    saved = [later.model_copy(update={"benefits": priced[0].benefits})]
    [rows] = eng.recommend([h], {"l": saved}, [Query(merchant="ediya", amount=10000)], NOW)
    assert rows[0].value == 1000


def test_limit_status_period(engine):
    eng = engine(
        card(
            [
                b(
                    "cafe-10",
                    {"categories": ["cafe"]},
                    {"type": "billing_discount", "rate": 10},
                    limits=[{"per": "month", "amount": 5000}, {"per": "day", "count": 1}],
                )
            ],
            id="test-s",
            tiers=(0,),
        )
    )
    h = holder(id="s", card_id="test-s")
    ps = [pay(30000, "2026-09-02T10:00", merchant="ediya").model_copy(update={"user_card_id": "s"})]
    saved = [ps[0].model_copy(update={"benefits": eng.price_month(h, ps)[0].benefits})]
    uses = {u.per: u for u in eng.limit_status(h, saved, at("2026-09-02T20:00"))}
    assert (uses["month"].used_amount, uses["month"].cap_amount) == (3000, 5000)
    assert (uses["day"].used_count, uses["day"].cap_count) == (1, 1)
    uses = {u.per: u for u in eng.limit_status(h, saved, at("2026-10-01T09:00"))}
    assert uses["month"].used_amount == 0 and uses["day"].used_count == 0
    assert date(2026, 10, 1)
