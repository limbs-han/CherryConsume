"""추천 속도. 설계 4.4와 6.5. 카드 10장, 이번 달 결제 300건, 조건부 혜택 포함으로 추천 한 번 50ms,
업종 12개의 업종별 1순위 200ms 안이다. 컴퓨터마다 속도가 달라 여러 번 재서 가운데 값을 쓴다.
결제 10건에 1건은 반을 취소한다. 취소한 결제는 처음 실적을 셀 때 한 번 더 계산해 느리다. 설계 6.5"""

import random
import statistics
import time
from datetime import date, timedelta
from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine
from cherry_core.engine.models import Payment, Query, UserCard

from .conftest import at

ROOT = Path(__file__).resolve().parents[3] / "catalog"
NOW = at("2026-09-28T19:30")
CATEGORIES = [
    "cafe",
    "convenience",
    "restaurant",
    "online_shopping",
    "transit.subway",
    "delivery_app",
    "grocery_mart",
    "fuel",
    "movie",
    "telecom.mobile",
    "hospital",
    "other",
]


@pytest.fixture(scope="module")
def heavy():
    cat = load_catalog(ROOT)
    eng = Engine(cat)
    ids = sorted(cat.cards, key=lambda c: -len(cat.cards[c].revisions[-1][1].benefits))[:10]
    rng = random.Random(20260928)
    merchants = sorted(cat.merchants)
    cards = [UserCard(id=f"u{i}", card_id=cid, registered_on=date(2026, 1, 1), facts={}) for i, cid in enumerate(ids)]
    payments: dict[str, list[Payment]] = {}
    for n in range(300):
        c = cards[n % 10]
        when = at("2026-09-01T08:00") + timedelta(minutes=rng.randrange(27 * 24 * 60))
        p = Payment(
            id=f"x{n:03d}",
            user_card_id=c.id,
            amount=rng.choice([4500, 12000, 35000, 58000, 120000]),
            paid_at=when,
            merchant=rng.choice(merchants),
            channel=rng.choice(["online", "offline"]),
            payment_method=rng.choice(["physical_card", "naver_pay", "kakao_pay"]),
        )
        if n % 10 == 0:
            p = p.model_copy(update={"cancelled_amount": p.amount // 2, "cancelled_at": when + timedelta(hours=1)})
        payments.setdefault(c.id, []).append(p)
    for c in cards:
        results = {r.payment_id: r.benefits for r in eng.price_month(c, payments.get(c.id, []))}
        payments[c.id] = [p.model_copy(update={"benefits": results[p.id]}) for p in payments.get(c.id, [])]
    return eng, cards, payments


def median_ms(fn, runs=7) -> float:
    fn()
    times = []
    for _ in range(runs):
        start = time.perf_counter()
        fn()
        times.append((time.perf_counter() - start) * 1000)
    return statistics.median(times)


def test_one_recommendation_under_50ms(heavy):
    eng, cards, payments = heavy
    ms = median_ms(lambda: eng.recommend(cards, payments, [Query(merchant="starbucks", amount=12000)], NOW))
    assert ms < 50, f"{ms:.1f}ms"


def test_category_tops_under_200ms(heavy):
    eng, cards, payments = heavy
    queries = [Query(category=c) for c in CATEGORIES]
    ms = median_ms(lambda: eng.recommend(cards, payments, queries, NOW))
    assert ms < 200, f"{ms:.1f}ms"
