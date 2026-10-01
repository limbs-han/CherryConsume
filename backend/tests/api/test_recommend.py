"""추천. 작업 005 계획 슬라이스 3. S4

신한카드 Mr.Life 30만 구간. 야간 식음료 10%는 21시부터 9시, 1회 1만 원까지, 하루 1회. 편의점 10%는 하루 1회.
현대 ZERO Edition3 할인형은 모든 가맹점 0.8%. 시계는 2026-09-15 화요일 21:00 한국 시간이다.
"""

from datetime import UTC, datetime

from .conftest import login
from .test_payments import MRLIFE, pay

ZERO = {"card_id": "hyundai-zero-edition3-discount"}


def setup(client, *cards, name="jihan"):
    headers = login(client, name)
    ids = [client.post("/me/cards", json=c, headers=headers).json()["id"] for c in cards]
    return headers, ids


def ask(client, headers, **body):
    r = client.post("/me/recommendations", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def test_cafe_at_night(client, db):
    # 21시 스타벅스 1만 원. Mr.Life 야간 식음료 10%로 1,000원, ZERO 0.8%로 80원
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    r = ask(client, headers, merchant_name="스타벅스 역삼점", amount=10000)
    assert (r["merchant"], r["category"], r["category_name"]) == ("starbucks", "cafe", "카페")
    top, second = r["ranking"]
    assert (top["user_card_id"], top["value"], top["title"], top["rewards"]) == (
        mrlife,
        1000,
        "야간 식음료 10% 할인",
        ["billing_discount"],
    )
    assert (second["user_card_id"], second["value"]) == (zero, 80)
    # 요청 한 행과 카드 수만큼 순위 행이 남는다. 설계 문서 4.1
    n = db.execute(
        "SELECT (SELECT count(*) FROM recommendation_requests) AS q, (SELECT count(*) FROM recommendation_results) AS r"
    ).fetchone()
    assert (n["q"], n["r"]) == (1, 2)


def test_cafe_at_noon(client, clock):
    # 12시에는 야간 식음료가 아니라 Mr.Life 0원, ZERO 80원이 1순위
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    clock.now = datetime(2026, 9, 15, 3, 0, tzinfo=UTC)
    r = ask(client, headers, merchant_name="스타벅스", amount=10000)
    assert [(x["user_card_id"], x["value"]) for x in r["ranking"]] == [(zero, 80), (mrlife, 0)]


def test_no_amount_is_ten_thousand(client):
    # E11. 금액을 비우면 1만 원으로 계산하고 금액 칸은 비운 채 돌려준다
    headers, _ = setup(client, MRLIFE, ZERO)
    r = ask(client, headers, merchant_name="스타벅스")
    assert (r["amount"], r["ranking"][0]["value"]) == (None, 1000)


def test_exhausted_limit(client):
    # E10. 편의점 할인을 오늘 한 번 쓰면 Mr.Life는 GS25에서 0원이고 한도 소진으로 보인다. ZERO 80원이 1순위
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    pay(client, headers, mrlife, 4300, "GS25")
    r = ask(client, headers, merchant_name="GS25", amount=10000)
    assert [(x["user_card_id"], x["value"], x["exhausted"]) for x in r["ranking"]] == [
        (zero, 80, False),
        (mrlife, 0, True),
    ]


def test_pay_with_another_method(client):
    # IBK 나라사랑 25만 구간. 이마트에는 실물카드로 받는 IBK 혜택이 없고, 네이버페이로 내면 Npay 10% 적립이
    # 1회 1,000원까지라 1만 원에 1,000원을 더 받는다. 1포인트 1원
    headers, _ = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 300000})
    r = ask(client, headers, merchant_name="이마트", amount=10000)
    [row] = r["ranking"]
    assert row["value"] == 0
    assert {"payment_method": "naver_pay", "name": "네이버페이", "extra": 1000} in row["pay_with"]


def test_top_by_category(client):
    # 업종별 지금 1순위. 업종 12개, 1만 원 기준. 21시 카페는 Mr.Life 1,000원, 화요일 마트는 주말이 아니라 ZERO 80원
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    rows = client.get("/me/recommendations/top", headers=headers).json()
    assert len(rows) == 12
    by = {r["category"]: r for r in rows}
    assert (by["cafe"]["user_card_id"], by["cafe"]["value"], by["cafe"]["category_name"]) == (mrlife, 1000, "카페")
    assert (by["grocery_mart"]["user_card_id"], by["grocery_mart"]["value"]) == (zero, 80)


def test_recent_merchants(client):
    headers, [mrlife] = setup(client, MRLIFE)
    pay(client, headers, mrlife, 4300, "GS25 테헤란점", at="2026-09-15T10:00:00+09:00")
    pay(client, headers, mrlife, 4500, "스타벅스 역삼점", at="2026-09-15T11:00:00+09:00")
    pay(client, headers, mrlife, 4300, "GS25 테헤란점", at="2026-09-15T12:00:00+09:00")
    assert client.get("/me/recent-merchants", headers=headers).json() == ["GS25 테헤란점", "스타벅스 역삼점"]


def test_payment_follows_the_recommendation(client, db):
    # S4. 추천에서 결제를 기록하면 결제에 추천 요청 id가 붙는다. 남의 요청 id는 404
    headers, [mrlife] = setup(client, MRLIFE)
    request_id = ask(client, headers, merchant_name="GS25", amount=4300)["request_id"]
    pay(client, headers, mrlife, 4300, "GS25", recommendation_request_id=request_id)
    row = db.execute("SELECT recommendation_request_id FROM transactions").fetchone()
    assert str(row["recommendation_request_id"]) == request_id
    other, [theirs] = setup(client, MRLIFE, name="other")
    body = {
        "user_card_id": theirs,
        "amount": 4300,
        "merchant_name": "GS25",
        "paid_at": "2026-09-15T21:00:00+09:00",
        "recommendation_request_id": request_id,
    }
    assert client.post("/me/payments", json=body, headers=other).status_code == 404


def test_no_cards(client):
    # E17. 카드가 없으면 순위가 비고 업종별 1순위도 빈다
    headers, _ = setup(client)
    assert ask(client, headers, merchant_name="GS25")["ranking"] == []
    assert client.get("/me/recommendations/top", headers=headers).json() == []


def test_unknown_field_is_422(client):
    headers, _ = setup(client, MRLIFE)
    assert client.post("/me/recommendations", json={"card_number": "1234"}, headers=headers).status_code == 422


def test_points_card_says_points(client):
    # 신한 Point Plan 40만 구간. GS25 1만 원은 3만 원 미만 0.5% 적립이라 50포인트, 1포인트 1원. 적립으로 보인다. E13
    headers, _ = setup(client, {"card_id": "shinhan-pointplan", "assumed_prev_month_spend": 410000})
    [row] = ask(client, headers, merchant_name="GS25", amount=10000)["ranking"]
    assert (row["value"], row["rewards"]) == (50, ["points"])


def test_top_skips_categories_missing_from_the_catalog(client, monkeypatch):
    # 카탈로그에서 영화 업종이 빠져도 추천 탭이 오류로 덮이지 않고 그 줄만 빠진다
    headers, _ = setup(client, MRLIFE)
    names = dict(client.app.state.category_names)
    names.pop("movie")
    monkeypatch.setattr(client.app.state, "category_names", names)
    rows = client.get("/me/recommendations/top", headers=headers).json()
    assert len(rows) == 11 and "movie" not in {r["category"] for r in rows}


def test_recent_merchants_are_mine_and_four(client):
    headers, [mrlife] = setup(client, MRLIFE)
    for n, name in enumerate(["가게1", "가게2", "가게3", "가게4", "가게5"]):
        pay(client, headers, mrlife, 1000, name, at=f"2026-09-15T1{n}:00:00+09:00")
    other, [theirs] = setup(client, MRLIFE, name="other")
    pay(client, other, theirs, 1000, "남의 가게", at="2026-09-15T20:00:00+09:00")
    assert client.get("/me/recent-merchants", headers=headers).json() == ["가게5", "가게4", "가게3", "가게2"]


def test_billing_bound_category_is_not_calculated(client, db):
    # 지하철은 IBK 나라사랑 대중교통 20%처럼 후불교통 조건이 붙는다. 가게 없이 업종만 물으면 청구 방식을 몰라
    # ZERO 80원을 1순위로 잘못 보인다. 담을 수 없는 질문이라 계산하지 않고 미지원으로 돌려준다
    headers, _ = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 300000}, ZERO)
    r = ask(client, headers, category="transit.subway", amount=10000)
    assert (r["unsupported"], r["ranking"], r["request_id"]) == ("billing", [], None)
    assert db.execute("SELECT count(*) AS n FROM recommendation_requests").fetchone()["n"] == 0
    top = client.get("/me/recommendations/top", headers=headers).json()
    assert not {"transit.subway", "transit.bus_city", "telecom.mobile"} & {t["category"] for t in top}
