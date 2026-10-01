"""결제 기록. 작업 005 계획 슬라이스 2

신한카드 Mr.Life 2026-07-15 개정. 편의점 10% 할인은 30만 구간부터, 1회 승인금액 1만 원까지, 하루 1회, 월 5회.
신한 공통 규칙은 카카오페이, 네이버페이, 페이코, 토스페이 결제와 무이자할부를 혜택에서 뺀다. 할부는 결제한 달에 다 넣는다.
현대 ZERO Edition3 할인형은 구간 없이 모든 가맹점 0.8% 할인이다. 시계는 2026-09-15 21:00 한국 시간이다.
"""

from datetime import UTC, datetime

from .conftest import login

MRLIFE = {"card_id": "shinhan-mrlife", "assumed_prev_month_spend": 410000}


def setup(client, *cards, name="jihan"):
    headers = login(client, name)
    ids = [client.post("/me/cards", json=c, headers=headers).json()["id"] for c in cards or (MRLIFE,)]
    return headers, ids


def pay(client, headers, card_id, amount, merchant, at="2026-09-15T21:00:00+09:00", **more):
    body = {"user_card_id": card_id, "amount": amount, "merchant_name": merchant, "paid_at": at, **more}
    r = client.post("/me/payments", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


def test_categories_and_payment_methods(client):
    cats = client.get("/catalog/categories").json()
    restaurant = next(c for c in cats if c["code"] == "restaurant")
    assert {"code": "restaurant.general", "name": "일반음식점"} in restaurant["children"]
    assert {"key": "physical_card", "name": "실물카드"} in client.get("/catalog/payment-methods").json()


def test_draft_fills_from_merchant(client):
    headers, [mrlife] = setup(client)
    d = client.post("/me/payments/draft", json={"amount": 4300, "merchant_name": "GS25 테헤란점"}, headers=headers)
    d = d.json()
    assert (d["merchant"], d["category"], d["category_name"], d["channel"]) == (
        "gs25",
        "convenience",
        "편의점",
        "offline",
    )
    assert d["pick"] == mrlife
    # 4,300원의 10%는 430원
    est = d["estimate"]
    assert (est["value"], est["payment_method"], est["counted"]) == (430, "physical_card", True)
    assert est["benefits"] == [{"key": "time-convenience", "title": "편의점 10% 할인", "amount": 430, "value": 430}]


def test_save_then_home(client, db):
    headers, [mrlife] = setup(client)
    saved = pay(client, headers, mrlife, 4300, "GS25 테헤란점")
    assert saved["value"] == 430
    home = client.get("/me/home", headers=headers).json()
    assert home["benefit_total"] == 430
    spend = home["cards"][0]["spend"]
    # 30만 구간을 지키려면 300,000 - 4,300 = 295,700원
    assert (spend["counted"], spend["to_keep"], spend["to_next"]) == (4300, 295700, 495700)
    row = db.execute("SELECT * FROM transaction_benefits").fetchone()
    assert (row["benefit_key"], row["amount"], row["value"], row["base_amount"]) == ("time-convenience", 430, 430, 4300)


def test_second_convenience_same_day_is_zero(client):
    # 편의점 할인은 하루 1회다. E10
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    assert pay(client, headers, mrlife, 5000, "GS25", at="2026-09-15T22:00:00+09:00")["value"] == 0
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 430


def test_earlier_payment_reprices_the_month(client):
    # E52. 같은 날 21시 4,300원이 430원을 받은 뒤 10시 5,000원을 넣는다. 편의점 할인은 하루 1회라
    # 카드사처럼 시각 순서로 다시 계산하면 10시가 5,000원의 10%인 500원, 21시가 0원이다. 합계 500원
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    saved = pay(client, headers, mrlife, 5000, "GS25", at="2026-09-15T10:00:00+09:00")
    assert (saved["value"], saved["repriced"]) == (500, 1)
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 500


def test_earlier_payment_on_another_day_keeps_values(client):
    # 하루 1회 한도는 날마다라 9월 14일 결제는 9월 15일 결제와 겹치지 않는다. 500원과 430원으로 합계 930원
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    assert pay(client, headers, mrlife, 5000, "GS25", at="2026-09-14T10:00:00+09:00")["value"] == 500
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 930


def test_last_month_payment_reprices_this_month(client):
    # E53. 추정 41만으로 30만 구간이라 9월 15일 GS25 4,300원이 430원을 받았다
    # 8월 20일 이마트 1만 원을 넣으면 E2대로 8월 기록 1만 원이 구간을 정해 9월은 0원 구간이다. 430원이 0원이 된다
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    saved = pay(client, headers, mrlife, 10000, "이마트", at="2026-08-20T12:00:00+09:00")
    assert saved["repriced"] == 1
    home = client.get("/me/home", headers=headers).json()
    assert (home["benefit_total"], home["cards"][0]["spend"]["tier"]) == (0, 0)


def test_last_month_payment_with_the_same_tier_keeps_values(client):
    # 8월 이마트 30만 원은 30만 구간 하한 그대로라 9월 구간이 바뀌지 않는다. 430원이 남는다
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    saved = pay(client, headers, mrlife, 300000, "이마트", at="2026-08-20T12:00:00+09:00")
    assert saved["repriced"] == 0
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 430


def test_payment_method_follows_each_card(client):
    # 신한 공통 규칙은 네이버페이 결제를 혜택에서 빼지만 Mr.Life 파일은 그 제외를 빈 목록으로 덮는다
    # Mr.Life 원문에 간편결제 제외 문구가 없어서다. 카드별 규칙을 따라 Mr.Life는 네이버페이도 430원이다
    # Point Plan은 공통 규칙을 그대로 따라 네이버페이면 0원, 실물카드면 1만 원의 0.5%인 50포인트, 1포인트 1원
    headers, [mrlife, plan] = setup(
        client, MRLIFE, {"card_id": "shinhan-pointplan", "assumed_prev_month_spend": 410000}
    )
    assert pay(client, headers, mrlife, 4300, "GS25", payment_method="naver_pay")["value"] == 430
    assert pay(client, headers, plan, 10000, "GS25", payment_method="naver_pay")["value"] == 0
    later = "2026-09-15T21:30:00+09:00"
    assert pay(client, headers, plan, 10000, "GS25", at=later, payment_method="physical_card")["value"] == 50
    # 다음 결제의 결제수단은 그 카드로 마지막에 쓴 것으로 채운다. S3
    d = client.post(
        "/me/payments/draft", json={"amount": 4300, "merchant_name": "GS25", "user_card_id": mrlife}, headers=headers
    ).json()
    assert d["estimate"]["payment_method"] == "naver_pay"


def test_payment_points_to_the_revision_used(client, db):
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    t = db.execute("SELECT card_revision_id FROM transactions").fetchone()
    rev = db.execute(
        "SELECT id FROM card_revisions WHERE id = %s AND card_id = 'shinhan-mrlife' AND effective_from = '2026-07-15'",
        (t["card_revision_id"],),
    ).fetchone()
    assert rev is not None
    assert (
        client.app.state.revision_ids[("shinhan-mrlife", rev and __import__("datetime").date(2026, 7, 15))] == rev["id"]
    )


def test_last_month_payment_beats_the_guess(client):
    # E2. 등록한 달에 지난달 결제를 넣으면 추정 41만 대신 그 결제의 합 50만으로 구간을 정한다
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 500000, "이마트 성수점", at="2026-08-20T12:00:00+09:00")
    spend = client.get("/me/home", headers=headers).json()["cards"][0]["spend"]
    assert (spend["tier"], spend["tier_source"], spend["prev_month_counted"]) == (500000, "prev_month", 500000)


def test_installment_counts_in_the_month_paid(client):
    # E4. 신한은 할부를 결제한 달에 다 넣는다. 3개월 할부 30만 원은 이번 달 30만 원이고 30만 구간을 지켰다
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 300000, "이마트", installment_months=3)
    spend = client.get("/me/home", headers=headers).json()["cards"][0]["spend"]
    assert (spend["counted"], spend["to_keep"]) == (300000, 0)


def test_ranking_picks_the_best_card(client):
    # GS25 1만 원. Mr.Life는 10%로 1,000원, ZERO는 0.8%로 80원
    headers, [mrlife, zero] = setup(client, MRLIFE, {"card_id": "hyundai-zero-edition3-discount"})
    d = client.post("/me/payments/draft", json={"amount": 10000, "merchant_name": "GS25"}, headers=headers).json()
    assert [(r["user_card_id"], r["value"]) for r in d["ranking"]] == [(mrlife, 1000), (zero, 80)]
    assert d["pick"] == mrlife
    picked = client.post(
        "/me/payments/draft", json={"amount": 10000, "merchant_name": "GS25", "user_card_id": zero}, headers=headers
    ).json()
    assert (picked["pick"], picked["estimate"]["value"]) == (zero, 80)


def test_longest_alias_wins_and_online_channel(client):
    # "쿠팡이츠"에는 별칭 "쿠팡"과 "쿠팡이츠"가 함께 들어 있다. 긴 쪽인 배달앱이다. 배달앱은 온라인으로 채운다
    headers, _ = setup(client)
    d = client.post("/me/payments/draft", json={"merchant_name": "쿠팡이츠"}, headers=headers).json()
    assert (d["merchant"], d["category"], d["channel"]) == ("coupang_eats", "delivery_app", "online")


def test_unknown_merchant_leaves_category_empty(client):
    # E16. 못 찾은 가게는 업종을 비우고 이름은 적은 그대로 둔다
    headers, [mrlife] = setup(client)
    d = client.post("/me/payments/draft", json={"merchant_name": "동네 카페 달빛"}, headers=headers).json()
    assert (d["merchant"], d["category"], d["estimate"]) == (None, None, None)
    # 업종을 고르면 그 업종으로 계산한다. 21시 카페는 Mr.Life 야간 식음료 10%로 450원
    assert pay(client, headers, mrlife, 4500, "동네 카페 달빛", category="cafe")["value"] == 450


def test_bad_payments(client, clock):
    headers, [mrlife] = setup(client)
    base = {"user_card_id": mrlife, "amount": 4300, "paid_at": "2026-09-15T21:00:00+09:00"}

    def status(**more):
        return client.post("/me/payments", json={**base, **more}, headers=headers).status_code

    assert status(paid_at="2026-09-17T00:00:00+09:00") == 422  # 하루 넘게 뒤
    assert status(category="nope") == 422
    assert status(payment_method="nope") == 422
    assert status(amount=0) == 422
    assert status(interest_free=True) == 422  # 일시불은 무이자할부가 아니다
    assert status(card_number="1234-5678-9012-3456") == 422
    assert status(user_card_id="not-a-uuid") == 404
    _, [theirs] = setup(client, name="other")
    assert client.post("/me/payments", json={**base, "user_card_id": theirs}, headers=headers).status_code == 404


def test_benefit_total_is_this_month_only(client, clock):
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    clock.now = datetime(2026, 10, 2, 3, 0, tzinfo=UTC)
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 0


def test_same_time_payments_follow_entry_order(client):
    # 같은 시각의 두 결제는 먼저 넣은 결제가 하루 1회 한도를 쓴다. 무작위 id면 절반은 두 번째도 500원을 받았다
    for n in range(8):
        headers, [mrlife] = setup(client, name=f"same-{n}")
        pay(client, headers, mrlife, 4300, "GS25")
        assert pay(client, headers, mrlife, 5000, "GS25")["value"] == 0


def test_convenience_cap_is_per_payment(client):
    # 1회 승인금액 1만 원까지 할인이라 10,001원도 1,000원이다
    headers, [mrlife] = setup(client)
    assert pay(client, headers, mrlife, 10001, "GS25")["value"] == 1000


def test_benefit_total_uses_korean_month(client, clock):
    # 9월 30일 23:30 한국 시간은 UTC로 9월 30일 14:30이다. 10월 1일 00:30 한국 시간에는 지난달 혜택이다
    clock.now = datetime(2026, 9, 30, 14, 45, tzinfo=UTC)
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25", at="2026-09-30T23:30:00+09:00")
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 430
    clock.now = datetime(2026, 9, 30, 15, 30, tzinfo=UTC)
    assert client.get("/me/home", headers=headers).json()["benefit_total"] == 0


def test_merchant_names_that_must_not_match(client):
    # 2026-10-01 위험 검토 두 번이 찾은 이름. 짧은 별칭이 다른 가게에 걸리면 안 된다
    headers, _ = setup(client)
    wrong = [
        "롯데하이마트 강남점",
        "COSTCO",
        "파고다 토익학원",
        "카카오TV",
        "카카오페이지",
        "멜론빵 가게",
        "멜론빵 전문점",
        "컬리헤어 역삼점",
        "토익스터디카페 강남점",
        "옥션하우스 강남점",
        "자라섬 캠핑장",
        "자라탕 전문점",
        "Tropical Juice",
        "STEPS 댄스",
        "desktop shop",
        "Arnold",
        "스타벅스역삼점",
        "쿠팡플레이",
        "이마트트레이더스 월계점",
    ]
    # 띄어 쓴 "이마트 트레이더스", "쿠팡 플레이"는 아직 이마트, 쿠팡으로 걸린다. 2026-10-01 사용자가 다른 가게로 보기로 했고
    # 두 가맹점은 카탈로그 원본인 골드에 넣는다. 들어오면 여기서 traders, coupang_play로 시험한다
    for name in wrong:
        d = client.post("/me/payments/draft", json={"merchant_name": name}, headers=headers).json()
        assert d["merchant"] is None, name
    right = {
        "스타벅스 역삼점": "starbucks",
        "GS25 테헤란점": "gs25",
        "이마트24 역삼점": "emart24",
        "LOTTE MART 잠실점": "lotte_mart",
        "쿠팡이츠": "coupang_eats",
    }
    for name, key in right.items():
        d = client.post("/me/payments/draft", json={"merchant_name": name}, headers=headers).json()
        assert d["merchant"] == key, name


def test_streaming_is_online(client):
    headers, _ = setup(client)
    d = client.post("/me/payments/draft", json={"merchant_name": "넷플릭스"}, headers=headers).json()
    assert (d["category"], d["channel"]) == ("streaming", "online")


def test_ranking_value_matches_the_estimate(client):
    # 순위 금액도 할부까지 넣어 계산한다. 1순위로 고른 카드의 순위 금액과 예상 혜택이 같다
    headers, _ = setup(client, MRLIFE, {"card_id": "hyundai-zero-edition3-discount"})
    body = {"amount": 30000, "merchant_name": "이마트", "installment_months": 3, "interest_free": True}
    d = client.post("/me/payments/draft", json=body, headers=headers).json()
    assert d["ranking"][0]["value"] == d["estimate"]["value"]
    assert d["ranking"][0]["user_card_id"] == d["pick"]


def test_billing_is_frozen_when_saved(client, db):
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4300, "GS25")
    assert db.execute("SELECT billing FROM transactions").fetchone()["billing"] == "normal"


def test_deferred_spend_chain_skips_a_month(client, clock):
    # 신한은 지하철 실적을 다음 달에 넣는다. 8월 31일 지하철 1만 원은 9월 실적이다
    # 9월 이마트 29만에 더해 9월 실적이 30만이 되어 10월이 30만 구간이 된다. 9월 구간은 그대로 0원이다
    # 그래서 9월에서 멈추지 않고 10월까지 봐야 10월 5일 GS25 4,300원이 0원에서 430원이 된다
    clock.now = datetime(2026, 8, 1, 3, 0, tzinfo=UTC)
    headers, [mrlife] = setup(client)
    clock.now = datetime(2026, 9, 10, 3, 0, tzinfo=UTC)
    pay(client, headers, mrlife, 290000, "이마트", at="2026-09-10T12:00:00+09:00")
    clock.now = datetime(2026, 10, 5, 3, 0, tzinfo=UTC)
    assert pay(client, headers, mrlife, 4300, "GS25", at="2026-10-05T12:00:00+09:00")["value"] == 0
    clock.now = datetime(2026, 10, 15, 3, 0, tzinfo=UTC)
    saved = pay(client, headers, mrlife, 10000, "지하철", at="2026-08-31T12:00:00+09:00", category="transit.subway")
    assert saved["repriced"] == 1
    home = client.get("/me/home", headers=headers).json()
    assert (home["cards"][0]["spend"]["tier"], home["benefit_total"]) == (300000, 430)


def test_same_value_puts_the_card_short_of_its_tier_first(client):
    # 이마트 3만 원 3개월 무이자. Mr.Life는 평일이라 주말 마트 할인이 없고, ZERO는 현대 공통 규칙이 무이자할부를 뺀다
    # 둘 다 0원이면 설계 4.2대로 30만 구간까지 실적이 모자란 Mr.Life가 앞이다
    headers, [mrlife, zero] = setup(client, MRLIFE, {"card_id": "hyundai-zero-edition3-discount"})
    body = {"amount": 30000, "merchant_name": "이마트", "installment_months": 3, "interest_free": True}
    d = client.post("/me/payments/draft", json=body, headers=headers).json()
    assert [(r["user_card_id"], r["value"]) for r in d["ranking"]] == [(mrlife, 0), (zero, 0)]


def test_earlier_payment_reprices_through_this_month(client, clock, db):
    # IBK 나라사랑 철도 5% 할인은 1회 2천 원, 월 2회, 연 4회이고 8만 구간부터다
    # 3/20, 4/10, 4/15, 5/10 KTX 10만 원이 연 4회를 다 쓴 뒤 3/25 KTX 10만 원을 넣는다
    # 시각 순서로 이번 달까지 다시 계산하면 3/20, 3/25, 4/10, 4/15가 2천 원씩이고 5/10은 연 4회를 넘어 0원. 합계 8천 원
    # 4월 구간은 3월 실적 20만, 5월 구간은 4월 실적 20만이라 모두 8만 이상이다
    clock.now = datetime(2026, 3, 1, 3, 0, tzinfo=UTC)
    headers, [ibk] = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 300000})
    for day in ("2026-03-20", "2026-04-10", "2026-04-15", "2026-05-10"):
        clock.now = datetime.fromisoformat(f"{day}T03:00:00+00:00")
        assert pay(client, headers, ibk, 100000, "KTX", at=f"{day}T12:00:00+09:00")["value"] == 2000, day
    clock.now = datetime(2026, 5, 20, 3, 0, tzinfo=UTC)
    saved = pay(client, headers, ibk, 100000, "KTX", at="2026-03-25T12:00:00+09:00")
    assert (saved["value"], saved["repriced"]) == (2000, 1)
    total = db.execute("SELECT coalesce(sum(value), 0) AS v FROM transaction_benefits").fetchone()["v"]
    assert total == 8000
    may = db.execute(
        "SELECT coalesce(sum(b.value), 0) AS v FROM transactions t JOIN transaction_benefits b ON b.transaction_id = t.id"
        " WHERE t.paid_at = '2026-05-10T12:00:00+09:00'"
    ).fetchone()["v"]
    assert may == 0


def test_ranking_uses_the_repriced_spend_flag(client):
    # 이마트 3만 원 3개월 무이자. LOCA 365는 무이자할부를 실적에서 빼고 ZERO는 실적 기준이 없다. 둘 다 혜택 0원
    # 일시불로 본 추천은 LOCA 365를 실적 인정으로 보지만 다시 계산하면 둘 다 실적에 들지 않아 카드 id 순으로 ZERO가 앞이다
    headers, [loca, zero] = setup(
        client,
        {"card_id": "lotte-loca365", "assumed_prev_month_spend": 600000},
        {"card_id": "hyundai-zero-edition3-discount"},
    )
    body = {"amount": 30000, "merchant_name": "이마트", "installment_months": 3, "interest_free": True}
    d = client.post("/me/payments/draft", json=body, headers=headers).json()
    assert [(r["user_card_id"], r["value"]) for r in d["ranking"]] == [(zero, 0), (loca, 0)]


def test_unchanged_payments_are_not_rewritten(client, clock, db):
    # 9/15 10시 결제를 넣으면 9월을 다시 계산하지만 9/14 결제는 값이 그대로라 다시 쓰지 않는다. E25의 updated_at을 지킨다
    headers, [mrlife] = setup(client)
    pay(client, headers, mrlife, 4500, "스타벅스 역삼점", at="2026-09-14T12:00:00+09:00")
    pay(client, headers, mrlife, 4300, "GS25")
    clock.now = datetime(2026, 9, 15, 13, 0, tzinfo=UTC)
    assert pay(client, headers, mrlife, 5000, "GS25", at="2026-09-15T10:00:00+09:00")["repriced"] == 1
    row = db.execute("SELECT updated_at FROM transactions WHERE merchant_key = 'starbucks'").fetchone()
    assert row["updated_at"] == datetime(2026, 9, 15, 12, 0, tzinfo=UTC)


def test_draft_shows_the_merchant_found(client):
    headers, _ = setup(client)
    d = client.post("/me/payments/draft", json={"merchant_name": "GS25 테헤란점"}, headers=headers).json()
    assert d["merchant_display"] == "GS25"
