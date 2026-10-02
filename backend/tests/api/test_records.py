"""기록, 고치기, 취소, 지우기, 카드 상세와 해지. 작업 005 계획 슬라이스 4. S7, S8, S9

신한카드 Mr.Life. 구간 0, 30만, 50만, 100만. 편의점 10%는 30만 구간부터 1회 1만 원까지, 하루 1회, 월 5회.
통합 한도는 30만 구간에서 월 1만 원. 상품권은 실적에서 빠진다. 시계는 2026-09-15 21:00 한국 시간이다.
"""

from .conftest import login
from .test_payments import MRLIFE, pay

ZERO = {"card_id": "hyundai-zero-edition3-discount"}
NO_GUESS = {"card_id": "shinhan-mrlife"}


def setup(client, *cards, name="jihan"):
    headers = login(client, name)
    ids = [client.post("/me/cards", json=c, headers=headers).json()["id"] for c in cards]
    return headers, ids


def edit(client, headers, tid, card, amount, merchant, at="2026-09-15T21:00:00+09:00", **more):
    body = {"user_card_id": card, "amount": amount, "merchant_name": merchant, "paid_at": at, **more}
    r = client.patch(f"/me/payments/{tid}", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def total(client, headers):
    return client.get("/me/home", headers=headers).json()["benefit_total"]


def test_records_of_a_month(client):
    # 8월 이마트 30만 원으로 9월도 30만 구간이다. 9월은 GS25 4,300원 430원, 낮 스타벅스 4,500원 0원,
    # 상품권 1만 원 0원에 실적 제외. 9월 3건, 18,800원, 혜택 430원
    headers, [mrlife] = setup(client, NO_GUESS)
    pay(client, headers, mrlife, 300000, "이마트", at="2026-08-20T12:00:00+09:00")
    pay(client, headers, mrlife, 4300, "GS25")
    pay(client, headers, mrlife, 4500, "스타벅스", at="2026-09-14T12:00:00+09:00")
    pay(client, headers, mrlife, 10000, "상품권", at="2026-09-13T12:00:00+09:00", category="gift_card")
    r = client.get("/me/payments", headers=headers).json()
    assert (r["month"], r["count"], r["amount"], r["benefit_total"]) == ("2026-09-01", 3, 18800, 430)
    rows = [(x["merchant_name"], x["value"], x["counted"]) for x in r["payments"]]
    assert rows == [("GS25", 430, True), ("스타벅스", 0, True), ("상품권", 0, False)]
    assert r["payments"][0]["rewards"] == ["billing_discount"]
    august = client.get("/me/payments", params={"month": "2026-08"}, headers=headers).json()
    assert august["count"] == 1


def test_records_filtered_by_card(client):
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    pay(client, headers, mrlife, 4300, "GS25")
    pay(client, headers, zero, 10000, "이마트")
    r = client.get("/me/payments", params={"card": zero}, headers=headers).json()
    assert [(x["user_card_id"], x["value"]) for x in r["payments"]] == [(zero, 80)]


def test_edit_reprices_only_that_payment(client):
    # E50. GS25 4,300원을 1만 원으로 고치면 10%로 1,000원
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 4300, "GS25")["id"]
    assert edit(client, headers, tid, mrlife, 10000, "GS25")["value"] == 1000
    assert total(client, headers) == 1000


def test_edit_last_month_reprices_this_month(client):
    # E54. 8월 30만 원으로 9월 30만 구간이라 GS25 430원. 8월을 20만 원으로 고치면 9월이 0원 구간이라 0원
    headers, [mrlife] = setup(client, NO_GUESS)
    aug = pay(client, headers, mrlife, 300000, "이마트", at="2026-08-20T12:00:00+09:00")["id"]
    pay(client, headers, mrlife, 4300, "GS25")
    r = edit(client, headers, aug, mrlife, 200000, "이마트", at="2026-08-20T12:00:00+09:00")
    assert r["repriced"] == 1
    assert total(client, headers) == 0


def test_delete_last_month_reprices_this_month(client):
    # E54. 추정값 없이 등록해 8월 30만 원이 9월 구간을 정한다. 8월 결제를 지우면 지난달 기록이 없어 0원 구간이다
    headers, [mrlife] = setup(client, NO_GUESS)
    aug = pay(client, headers, mrlife, 300000, "이마트", at="2026-08-20T12:00:00+09:00")["id"]
    pay(client, headers, mrlife, 4300, "GS25")
    assert total(client, headers) == 430
    assert client.delete(f"/me/payments/{aug}", headers=headers).json()["repriced"] == 1
    assert total(client, headers) == 0
    assert client.get("/me/payments", params={"month": "2026-08"}, headers=headers).json()["count"] == 0


def test_cancel_full_and_partial(client):
    # E5. 4,300원 전액 취소면 0원. 1만 원 결제의 5,000원 취소면 남은 5,000원의 10%로 500원
    headers, [mrlife] = setup(client, MRLIFE)
    small = pay(client, headers, mrlife, 4300, "GS25")["id"]
    body = {"cancelled_amount": 4300, "cancelled_at": "2026-09-15T21:10:00+09:00"}
    assert client.post(f"/me/payments/{small}/cancel", json=body, headers=headers).json()["value"] == 0
    big = pay(client, headers, mrlife, 10000, "GS25", at="2026-09-14T21:00:00+09:00")["id"]
    body = {"cancelled_amount": 5000, "cancelled_at": "2026-09-14T22:00:00+09:00"}
    assert client.post(f"/me/payments/{big}/cancel", json=body, headers=headers).json()["value"] == 500
    spend = client.get("/me/home", headers=headers).json()["cards"][0]["spend"]
    # 실적은 0원과 남은 5,000원
    assert spend["counted"] == 5000


def test_move_payment_to_another_card(client):
    # GS25 4,300원을 ZERO로 옮기면 0.8%로 34원. 원 미만은 버린다
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    tid = pay(client, headers, mrlife, 4300, "GS25")["id"]
    assert edit(client, headers, tid, zero, 4300, "GS25")["value"] == 34
    cards = {c["card_id"]: c for c in client.get("/me/home", headers=headers).json()["cards"]}
    assert cards["shinhan-mrlife"]["spend"]["counted"] == 0


def test_bad_changes(client):
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 4300, "GS25")["id"]
    other, [theirs] = setup(client, MRLIFE, name="other")
    body = {"user_card_id": theirs, "amount": 100, "merchant_name": "x", "paid_at": "2026-09-15T21:00:00+09:00"}
    assert client.patch(f"/me/payments/{tid}", json=body, headers=other).status_code == 404
    assert client.delete(f"/me/payments/{tid}", headers=other).status_code == 404
    too_much = {"cancelled_amount": 5000, "cancelled_at": "2026-09-15T21:10:00+09:00"}
    assert client.post(f"/me/payments/{tid}/cancel", json=too_much, headers=headers).status_code == 422
    early = {"cancelled_amount": 100, "cancelled_at": "2026-09-15T20:00:00+09:00"}
    assert client.post(f"/me/payments/{tid}/cancel", json=early, headers=headers).status_code == 422
    client.delete(f"/me/payments/{tid}", headers=headers)
    assert client.delete(f"/me/payments/{tid}", headers=headers).status_code == 404


def test_card_detail(client):
    # GS25 4,300원 뒤 편의점 월 5회 가운데 1회, 통합 한도 월 1만 원 가운데 430원을 썼다
    headers, [mrlife] = setup(client, MRLIFE)
    pay(client, headers, mrlife, 4300, "GS25")
    d = client.get(f"/me/cards/{mrlife}", headers=headers).json()
    limits = {x["title"]: x for x in d["limits"]}
    assert (limits["편의점 10% 할인"]["used_count"], limits["편의점 10% 할인"]["cap_count"]) == (1, 5)
    assert (limits["통합 한도"]["used_amount"], limits["통합 한도"]["cap_amount"]) == (430, 10000)
    # 30만 구간에서 받는 혜택은 모두 30만부터라 못 받는 혜택이 없다
    assert d["locked"] == []
    assert d["revision_from"] == "2026-07-15" and d["check_sentences"]


def test_card_detail_locked_benefits(client):
    # E37. 추정값 없이 0원 구간이면 30만부터인 혜택 10개를 못 받는다. 이번 달 4,300원을 써 30만까지 295,700원
    headers, [mrlife] = setup(client, NO_GUESS)
    pay(client, headers, mrlife, 4300, "GS25")
    locked = client.get(f"/me/cards/{mrlife}", headers=headers).json()["locked"]
    assert len(locked) == 10
    assert {(x["required_tier"], x["remaining"]) for x in locked} == {(300000, 295700)}


def test_remove_card(client):
    # S9. 해지하면 홈과 추천에서 빠지고 기록과 받은 혜택 합계에는 남는다
    headers, [mrlife] = setup(client, MRLIFE)
    pay(client, headers, mrlife, 4300, "GS25")
    assert client.delete(f"/me/cards/{mrlife}", headers=headers).status_code == 200
    home = client.get("/me/home", headers=headers).json()
    assert (home["cards"], home["benefit_total"]) == ([], 430)
    assert client.get("/me/payments", headers=headers).json()["count"] == 1
    assert client.post("/me/recommendations", json={"merchant_name": "GS25"}, headers=headers).json()["ranking"] == []
    assert client.get(f"/me/cards/{mrlife}", headers=headers).status_code == 404
    body = {"user_card_id": mrlife, "amount": 1000, "merchant_name": "GS25", "paid_at": "2026-09-15T21:00:00+09:00"}
    assert client.post("/me/payments", json=body, headers=headers).status_code == 404


def test_cancel_keeps_the_month_spend_of_a_benefit_payment(client):
    # E5. KB 톡톡은 혜택 받은 결제를 실적에서 빼고 취소한 달 기준이다. 7월 30만으로 8월 30만 구간
    # 8/10 스타벅스 2만 원은 50%가 월 1만 원 한도를 채워 1만 원 할인, 실적 0. 8/20 기타 29만이라 8월 실적 29만, 9월 0원 구간
    # 9/3에 8월 스타벅스를 전액 취소해도 처음 실적이 0이라 8월은 29만 그대로다. 9월은 0원 구간이고 다시 계산할 결제도 없다
    headers, [kb] = setup(client, {"card_id": "kb-toktok"})
    method = {"payment_method": "physical_card"}
    pay(client, headers, kb, 300000, "기타", at="2026-07-20T12:00:00+09:00", category="other", **method)
    sb = pay(client, headers, kb, 20000, "스타벅스", at="2026-08-10T08:30:00+09:00", **method)
    assert sb["value"] == 10000
    pay(client, headers, kb, 290000, "기타", at="2026-08-20T12:00:00+09:00", category="other", **method)
    assert pay(client, headers, kb, 10000, "스타벅스", at="2026-09-05T08:30:00+09:00", **method)["value"] == 0
    body = {"cancelled_amount": 20000, "cancelled_at": "2026-09-03T10:00:00+09:00"}
    r = client.post(f"/me/payments/{sb['id']}/cancel", json=body, headers=headers).json()
    assert (r["value"], r["repriced"]) == (0, 0)
    # 저장된 기록으로 다시 세도 9월은 0원 구간이다. 엔진이 취소하지 않은 결제로 다시 계산해 처음 실적을 센다
    spend = client.get("/me/home", headers=headers).json()["cards"][0]["spend"]
    assert (spend["tier"], spend["prev_month_counted"]) == (0, 290000)


def test_records_show_spend_like_the_engine_after_cancel(client):
    # 삼성 taptap O는 혜택 받은 결제를 실적에서 뺀다. 7월 30만으로 8월 30만 구간. 8/10 CGV 15,000원은 1만 원 이상 5,000원 할인으로 실적 0
    # 9/3에 6,000원을 부분 취소하면 남은 9,000원은 1만 원 미만이라 할인이 없다. 취소로 실적을 늘리지 않아 엔진은 8월 0원이다
    # 기록 목록도 엔진처럼 실적 제외로 보여야 한다
    headers, [card] = setup(client, {"card_id": "samsung-taptap-o"})
    pay(client, headers, card, 300000, "기타", at="2026-07-20T12:00:00+09:00", category="other")
    cgv = pay(client, headers, card, 15000, "CGV 강남", at="2026-08-10T19:00:00+09:00")
    assert cgv["value"] == 5000
    body = {"cancelled_amount": 6000, "cancelled_at": "2026-09-03T10:00:00+09:00"}
    assert client.post(f"/me/payments/{cgv['id']}/cancel", json=body, headers=headers).json()["value"] == 0
    rows = client.get("/me/payments", params={"month": "2026-08"}, headers=headers).json()["payments"]
    assert [(x["merchant_name"], x["counted"]) for x in rows] == [("CGV 강남", False)]
