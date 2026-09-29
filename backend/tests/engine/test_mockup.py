"""화면 시안의 숫자를 시안 카드로 재현한다. 설계 6.3. 시안 카드는 tests/engine/mockup/에만 있는 지어낸 카드다.

시안 Mr.Life는 9월 1일에 등록하며 지난달 41만원으로 적었다. 9월 결제는 카페 3건, 편의점 1건, 기타 2건으로
이번 달 182,000원이다. 시안 IBK는 편의점 3건과 기타 1건으로 265,000원, 시안 ZERO는 쿠팡, 자동차세, 기타다.
"""

from datetime import date
from pathlib import Path

import pytest

from cherry_core.engine import Engine
from cherry_core.engine.models import Query, UserCard

from .conftest import at, pay

ROOT = Path(__file__).parent / "mockup"
NOW = at("2026-09-20T12:00")
SEPT = date(2026, 9, 1)


def mine(card_id, payments):
    return [p.model_copy(update={"user_card_id": card_id}) for p in payments]


@pytest.fixture(scope="module")
def home():
    eng = Engine.from_dir(ROOT)
    cards = [
        UserCard(id="mr", card_id="mock-mrlife", registered_on=SEPT, assumed_prev_month_spend=410000),
        UserCard(id="ibk", card_id="mock-ibk", registered_on=SEPT, assumed_prev_month_spend=250000),
        UserCard(id="zero", card_id="mock-zero", registered_on=SEPT),
    ]
    raw = {
        "mr": mine(
            "mr",
            [
                pay(10000, "2026-09-05T10:00", merchant="ediya"),
                pay(60000, "2026-09-08T12:00", category="other"),
                pay(10000, "2026-09-12T10:00", merchant="ediya"),
                pay(30000, "2026-09-15T18:00", merchant="gs25"),
                pay(59500, "2026-09-16T13:00", category="other"),
                pay(12500, "2026-09-19T14:20", merchant="starbucks"),
            ],
        ),
        "ibk": mine(
            "ibk",
            [
                pay(5700, "2026-09-06T09:00", merchant="gs25"),
                pay(5000, "2026-09-10T09:00", merchant="gs25"),
                pay(250000, "2026-09-11T19:00", category="other"),
                pay(4300, "2026-09-19T09:02", merchant="gs25"),
            ],
        ),
        "zero": mine(
            "zero",
            [
                pay(128000, "2026-09-18T11:00", category="tax"),
                pay(36900, "2026-09-18T21:00", merchant="coupang", channel="online"),
                pay(130143, "2026-09-20T10:00", category="other"),
            ],
        ),
    }
    results, saved = {}, {}
    for c in cards:
        rs = eng.price_month(c, raw[c.id])
        results[c.id] = rs
        saved[c.id] = [p.model_copy(update={"benefits": r.benefits}) for p, r in zip(raw[c.id], rs)]
    return eng, {c.id: c for c in cards}, results, saved


def test_1_saved_this_month(home):
    # 3쪽 홈 이번 달 아낀 돈 7,669원 = Mr.Life 4,500 + IBK 2,000 + ZERO 1,169
    _, _, results, _ = home
    assert {k: sum(r.value for r in rs) for k, rs in results.items()} == {"mr": 4500, "ibk": 2000, "zero": 1169}


def test_2_and_5_mrlife_status(home):
    # 3쪽과 6쪽. 지난달 41만 기준 30만 구간, 이번 달 182,000원, 유지까지 11.8만, 60만까지 41.8만. 4쪽 등록 41만이면 30만 구간
    eng, cards, _, saved = home
    s = eng.spend_status(cards["mr"], saved["mr"], SEPT)
    assert (s.tier, s.tier_source, s.prev_month_counted) == (300000, "assumed", 410000)
    assert (s.counted, s.to_keep, s.next_tier, s.to_next) == (182000, 118000, 600000, 418000)


def test_3_mrlife_limits(home):
    # 6쪽. 통합 1만 중 4,500 사용, 잔여 5,500. 카페 잔여 2,000/5,000, 편의점 잔여 3,500/5,000
    eng, cards, _, saved = home
    uses = {(u.key, u.per): u for u in eng.limit_status(cards["mr"], saved["mr"], NOW)}
    integrated, cafe, cvs = uses[("integrated", "month")], uses[("cafe-10", "month")], uses[("cvs-5", "month")]
    assert (integrated.used_amount, integrated.cap_amount - integrated.used_amount) == (4500, 5500)
    assert (cafe.cap_amount - cafe.used_amount, cafe.cap_amount) == (2000, 5000)
    assert (cvs.cap_amount - cvs.used_amount, cvs.cap_amount) == (3500, 5000)


def test_4_ibk_and_zero(home):
    # 3쪽. IBK 20만 구간 할인 잔여 3,000원, 이번 달 20만을 넘어 다음 달 구간 확정. ZERO 이번 달 1,169원
    eng, cards, results, saved = home
    uses = {(u.key, u.per): u for u in eng.limit_status(cards["ibk"], saved["ibk"], NOW)}
    assert uses[("integrated", "month")].cap_amount - uses[("integrated", "month")].used_amount == 3000
    s = eng.spend_status(cards["ibk"], saved["ibk"], SEPT)
    assert (s.tier, s.to_keep) == (200000, 0)
    assert sum(r.value for r in results["zero"]) == 1169


def test_6_and_7_records(home):
    # 7쪽 스타벅스 12,500원 1,000원, 실적 인정. 10쪽 GS25 4,300원 430원, 자동차세 0원 실적 제외, 쿠팡 36,900원 258원
    _, _, results, _ = home
    starbucks = results["mr"][5]
    assert [(b.key, b.value) for b in starbucks.benefits] == [("cafe-10", 1000)] and starbucks.spend[0].amount == 12500
    assert [b.value for b in results["ibk"][3].benefits] == [430]
    tax, coupang = results["zero"][0], results["zero"][1]
    assert tax.benefits == [] and tax.spend == [] and tax.warnings[0].data == {"reason": "category"}
    assert [b.value for b in coupang.benefits] == [258]


def test_8_category_tops(home):
    # 8쪽. 1만원 기준 카페 Mr.Life 1,000, 편의점 IBK 1,000, 음식점·온라인·대중교통 ZERO 70
    eng, cards, _, saved = home
    queries = [Query(category=c) for c in ["cafe", "convenience", "restaurant", "online_shopping", "transit"]]
    tops = [(rows[0].card_id, rows[0].value) for rows in eng.recommend(list(cards.values()), saved, queries, NOW)]
    assert tops == [("mock-mrlife", 1000), ("mock-ibk", 1000), ("mock-zero", 70), ("mock-zero", 70), ("mock-zero", 70)]


def test_9_starbucks_recommendation(home):
    # 9쪽. 1위 Mr.Life 1,000, 2위 ZERO 70, 3위 IBK 20. 스타벅스 20%는 90만 구간, 이번 달 18.2만이라 71.8만 더
    eng, cards, _, saved = home
    [rows] = eng.recommend(list(cards.values()), saved, [Query(merchant="starbucks")], NOW)
    assert [(r.card_id, r.value) for r in rows] == [("mock-mrlife", 1000), ("mock-zero", 70), ("mock-ibk", 20)]
    [lock] = [x for x in rows[0].locked if x.benefit == "sb-20"]
    assert (lock.required_tier, lock.remaining_this_month, lock.value_if_unlocked) == (900000, 718000, 2000)
    assert rows[0].counted


def test_10_import_preview_august():
    # 12쪽 8월 가져오기 미리보기. 스타벅스 6,100원 610원, 쿠팡 24,900원 혜택 없음, 자동차세 실적 제외
    eng = Engine.from_dir(ROOT)
    mr = UserCard(id="mr", card_id="mock-mrlife", registered_on=date(2026, 8, 1), assumed_prev_month_spend=410000)
    rs = eng.price_month(
        mr,
        mine(
            "mr",
            [
                pay(6100, "2026-08-29T10:00", merchant="starbucks"),
                pay(24900, "2026-08-28T20:00", merchant="coupang", channel="online"),
                pay(128000, "2026-08-25T11:00", category="tax"),
            ],
        ),
    )
    by_amount = {r.spend[0].amount if r.spend else 0: r for r in rs}
    assert [b.value for b in by_amount[6100].benefits] == [610]
    assert by_amount[24900].benefits == []
    assert by_amount[0].warnings[0].data == {"reason": "category"}


def test_11_cafe_limit_exhausted_and_reset():
    # 14쪽. 카페 한도 5,000원을 다 쓰면 0원과 limit_exhausted, 10월 1일에 초기화
    eng = Engine.from_dir(ROOT)
    mr = UserCard(id="mr", card_id="mock-mrlife", registered_on=SEPT, assumed_prev_month_spend=410000)
    cafe = [pay(10000, f"2026-09-{d:02d}T10:00", merchant="ediya") for d in (1, 2, 3, 4, 5, 6)]
    rs = eng.price_month(
        mr,
        mine(
            "mr",
            [pay(300000, "2026-09-07T12:00", category="other")]
            + cafe
            + [pay(10000, "2026-10-01T10:00", merchant="ediya")],
        ),
    )
    got = [sum(b.value for b in r.benefits) for r in rs]
    assert got == [1000, 1000, 1000, 1000, 1000, 0, 0, 1000]
    assert "limit_exhausted" in [w.code for w in rs[5].warnings]
