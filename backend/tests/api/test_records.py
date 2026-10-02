"""기록, 고치기, 취소, 지우기, 카드 상세와 해지. 작업 005 계획 슬라이스 4. S7, S8, S9

신한카드 Mr.Life. 구간 0, 30만, 50만, 100만. 편의점 10%는 30만 구간부터 1회 1만 원까지, 하루 1회, 월 5회.
통합 한도는 30만 구간에서 월 1만 원. 상품권은 실적에서 빠진다. 시계는 2026-09-15 21:00 한국 시간이다.
"""

from datetime import UTC, datetime

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


def nara_year(client, *more):
    """IBK 나라사랑 철도 5%는 8만 구간부터 월 2회, 연 4회, 1회 2천 원까지. 취소는 취소한 달 실적에서 뺀다.
    5월 이마트 8만 원으로 6월이 8만 구간이다. 6월과 7월은 이마트 4만 원과 KTX 2만 원 두 번으로 실적 8만이고 KTX는
    5%로 1,000원씩이다. 연 4회를 다 써 8월 KTX 2만 원은 0원이다. 6월, 7월, 8월 혜택 합은 2,000, 2,000, 0원이다"""
    headers, ids = setup(client, {"card_id": "ibk-narasarang"}, *more)
    may = pay(client, headers, ids[0], 80000, "이마트", at="2026-05-20T12:00:00+09:00")["id"]
    for month in ("06", "07"):
        pay(client, headers, ids[0], 40000, "이마트", at=f"2026-{month}-02T12:00:00+09:00")
        pay(client, headers, ids[0], 20000, "KTX", at=f"2026-{month}-10T12:00:00+09:00")
        pay(client, headers, ids[0], 20000, "KTX", at=f"2026-{month}-20T12:00:00+09:00")
    pay(client, headers, ids[0], 20000, "KTX", at="2026-08-10T12:00:00+09:00")

    def totals():
        months = ("2026-06", "2026-07", "2026-08")
        return [
            client.get("/me/payments", params={"month": m}, headers=headers).json()["benefit_total"] for m in months
        ]

    assert totals() == [2000, 2000, 0]
    return headers, ids, may, totals


def test_edit_reprices_every_month_after_the_first_changed_tier(client):
    # E54 범위. 5월을 79,999원으로 고치면 6월만 0원 구간이 되어 6월 KTX 2건이 0원이다. 7월과 8월 구간은 그대로지만
    # 연 횟수가 2회 남아 8월 KTX가 1,000원이다. 다시 계산해 혜택이 바뀐 다른 결제는 6월 2건과 8월 1건이다
    headers, [nara], may, totals = nara_year(client)
    r = edit(client, headers, may, nara, 79999, "이마트", at="2026-05-20T12:00:00+09:00")
    assert totals() == [0, 2000, 1000]
    assert r["repriced"] == 3


def test_cancel_in_cancel_month_reprices_from_the_month_after(client):
    # E5, E54. 5월 이마트 8만 원 가운데 1만 원을 6월 5일 취소하면 6월 실적에서 빠져 6월 실적이 7만이다. 6월 구간은 5월
    # 실적 그대로 8만이고 7월만 0원 구간이다. 7월 KTX가 0원, 연 2회가 남아 8월 KTX가 1,000원이다
    headers, _, may, totals = nara_year(client)
    body = {"cancelled_amount": 10000, "cancelled_at": "2026-06-05T12:00:00+09:00"}
    assert client.post(f"/me/payments/{may}/cancel", json=body, headers=headers).status_code == 200
    assert totals() == [2000, 0, 1000]


def test_move_payment_reprices_the_old_card(client):
    # E54. 5월 이마트를 현대카드ZERO로 옮기면 나라사랑의 5월 실적이 0원이라 6월이 0원 구간이다. 6월 KTX가 0원,
    # 8월 KTX가 1,000원이다
    headers, [_, zero], may, totals = nara_year(client, ZERO)
    edit(client, headers, may, zero, 80000, "이마트", at="2026-05-20T12:00:00+09:00")
    assert totals() == [0, 2000, 1000]


def test_edit_reprices_a_payment_in_next_month(client, clock):
    # 위험 검토 13번. 시계가 9월 30일 21시면 하루 뒤인 10월 1일 결제까지 받는다. 9월 이마트 30만 원으로 10월이
    # 30만 구간이라 GS25 4,300원이 430원이다. 9월을 20만 원으로 고치면 10월이 0원 구간이라 0원이다
    clock.now = datetime(2026, 9, 30, 12, 0, tzinfo=UTC)
    headers, [mrlife] = setup(client, NO_GUESS)
    sep = pay(client, headers, mrlife, 300000, "이마트", at="2026-09-20T12:00:00+09:00")["id"]
    assert pay(client, headers, mrlife, 4300, "GS25", at="2026-10-01T10:00:00+09:00")["value"] == 430
    edit(client, headers, sep, mrlife, 200000, "이마트", at="2026-09-20T12:00:00+09:00")
    october = client.get("/me/payments", params={"month": "2026-10"}, headers=headers).json()
    assert october["benefit_total"] == 0


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
    # 위험 검토 15번. 주말 주유는 할인받는 결제액 월 30만 원 한도만 있다. 그래도 한도 줄에 보인다
    fuel = [x for x in d["limits"] if x["cap_base"] is not None]
    assert [(x["per"], x["used_base"], x["cap_base"]) for x in fuel] == [("month", 0, 300000)]
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


def test_card_detail_hides_what_the_card_does_not_give(client):
    # 위험 검토 9번과 10번. 삼성 taptap O를 추정값 없이 등록하면 0원 구간이다. 혜택은 모두 30만 구간부터라 받는 혜택의
    # 한도가 없다. 패키지 옵션은 고르지 않았고 기본값이 없어 패키지 혜택 6개는 구간이 올라도 받지 못한다. 못 받는 혜택은
    # 대중교통, 택시, 이동통신, 영화 4개다
    headers, [tap] = setup(client, {"card_id": "samsung-taptap-o"})
    d = client.get(f"/me/cards/{tap}", headers=headers).json()
    assert d["limits"] == []
    assert len(d["locked"]) == 4
    assert not [x for x in d["locked"] if "패키지" in x["title"]]


def test_card_detail_counts_unconfirmed_values_it_uses(client):
    # 위험 검토 14번. Mr.Life의 확인 필요 항목은 카드 전체 2개와 혜택별 3개다. 혜택별 3개는 모두 30만 구간부터라
    # 0원 구간이면 2개, 30만 구간이면 5개를 센다
    for card, count in ((NO_GUESS, 2), (MRLIFE, 5)):
        headers, [uid] = setup(client, card, name=f"count{count}")
        assert client.get(f"/me/cards/{uid}", headers=headers).json()["assumed_count"] == count


def test_card_detail_hides_limits_of_unpicked_options(client):
    # 위험 검토 10번 재검토. taptap O를 지난달 30만 원으로 등록하면 30만 구간이다. 대중교통과 택시가 함께 쓰는 월 5천 원,
    # 이동통신 월 5천 원, 영화 월 2회와 연 12회가 보인다. 패키지는 고르지 않아 패키지 혜택과 그 한도는 숨는다
    headers, [tap] = setup(client, {"card_id": "samsung-taptap-o", "assumed_prev_month_spend": 300000})
    d = client.get(f"/me/cards/{tap}", headers=headers).json()
    assert sorted(((x["per"], x["cap_amount"], x["cap_count"]) for x in d["limits"]), key=str) == [
        ("month", 5000, None),
        ("month", 5000, None),
        ("month", None, 2),
        ("year", None, 12),
    ]
    assert d["locked"] == []


def test_card_detail_tells_apart_benefits_with_the_same_title(client):
    # 재검토 중간 1번. IBK 나라사랑에는 "편의점 10% 청구할인"이 둘이다. 하나는 8만~20만 구간 월 2회, 하나는 25만 구간부터
    # 월 10회다. 8만 구간이면 월 2회만 보이고 25만 구간 혜택은 못 받는 혜택에 있다. 25만 구간이면 월 10회만 보인다
    title = "편의점 10% 청구할인"
    low_headers, [low] = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 80000})
    high_headers, [high] = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 250000}, name="b")
    d = client.get(f"/me/cards/{low}", headers=low_headers).json()
    assert [x["cap_count"] for x in d["limits"] if x["title"] == title] == [2]
    assert [x["required_tier"] for x in d["locked"] if x["title"] == title] == [250000]
    d = client.get(f"/me/cards/{high}", headers=high_headers).json()
    assert [x["cap_count"] for x in d["limits"] if x["title"] == title] == [10]
    assert not [x for x in d["locked"] if x["title"] == title]


def test_card_detail_leaves_out_ended_events(client, clock):
    # 재검토 중간 2번. IBK 슈마커 1만 원 청구할인은 2026-09-30에 끝난다. 10월 2일 카드 상세에는 그 한도가 없다
    headers, [nara] = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 80000})
    shoe = [b for b in client.get(f"/me/cards/{nara}", headers=headers).json()["limits"] if "슈마커" in b["title"]]
    clock.now = datetime(2026, 10, 2, 3, 0, tzinfo=UTC)
    d = client.get(f"/me/cards/{nara}", headers=headers).json()
    assert shoe and not [b for b in d["limits"] if "슈마커" in b["title"]]


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


def records_of(client, headers, month="2026-09"):
    return client.get("/me/payments", params={"month": month}, headers=headers).json()["payments"]


def test_edit_cannot_move_a_payment_after_its_cancel(client):
    # 위험 검토 6번. 9월 14일 21시 결제를 22시에 일부 취소했다. 결제 시각을 15일로 고치면 취소보다 뒤라 422다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 10000, "GS25", at="2026-09-14T21:00:00+09:00")["id"]
    cancel = {"cancelled_amount": 5000, "cancelled_at": "2026-09-14T22:00:00+09:00"}
    assert client.post(f"/me/payments/{tid}/cancel", json=cancel, headers=headers).status_code == 200
    body = {"user_card_id": mrlife, "amount": 10000, "merchant_name": "GS25", "paid_at": "2026-09-15T21:00:00+09:00"}
    assert client.patch(f"/me/payments/{tid}", json=body, headers=headers).status_code == 422
    edit(client, headers, tid, mrlife, 10000, "GS25", at="2026-09-14T20:00:00+09:00")


def test_more_cancel_in_another_month_is_unsupported(client):
    # 위험 검토 5번. 8월 결제를 8월에 3,000원 취소했다. 9월에 더 취소해 합을 5,000원으로 올리면 취소 시각이 하나라
    # 담지 못해 422다. 금액을 그대로 두고 시각만 9월로 고치는 것은 받는다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 10000, "이마트", at="2026-08-20T12:00:00+09:00")["id"]
    url = f"/me/payments/{tid}/cancel"
    aug = {"cancelled_amount": 3000, "cancelled_at": "2026-08-25T12:00:00+09:00"}
    assert client.post(url, json=aug, headers=headers).status_code == 200
    more = {"cancelled_amount": 5000, "cancelled_at": "2026-09-10T12:00:00+09:00"}
    assert client.post(url, json=more, headers=headers).status_code == 422
    # 합 대신 이번 취소 2,000원만 적어 달을 바꾸면 8월 3,000원 취소가 사라진다. 이것도 막는다
    less = {"cancelled_amount": 2000, "cancelled_at": "2026-09-10T12:00:00+09:00"}
    assert client.post(url, json=less, headers=headers).status_code == 422
    moved = {"cancelled_amount": 3000, "cancelled_at": "2026-09-10T12:00:00+09:00"}
    assert client.post(url, json=moved, headers=headers).status_code == 200
    # 취소한 적 없는 결제는 되돌릴 것이 없어 422다
    other = pay(client, headers, mrlife, 4300, "GS25")["id"]
    zero = {"cancelled_amount": 0, "cancelled_at": "2026-09-15T21:10:00+09:00"}
    assert client.post(f"/me/payments/{other}/cancel", json=zero, headers=headers).status_code == 422


def test_cancel_zero_undoes_the_cancel(client):
    # 위험 검토 16번. GS25 4,300원을 전액 취소하면 0원이다. 0원 취소로 되돌리면 다시 430원이고 취소 시각도 지운다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 4300, "GS25")["id"]
    url = f"/me/payments/{tid}/cancel"
    full = {"cancelled_amount": 4300, "cancelled_at": "2026-09-15T21:10:00+09:00"}
    assert client.post(url, json=full, headers=headers).json()["value"] == 0
    assert records_of(client, headers)[0]["cancelled_at"] is not None
    undo = {"cancelled_amount": 0, "cancelled_at": "2026-09-15T21:20:00+09:00"}
    assert client.post(url, json=undo, headers=headers).json()["value"] == 430
    row = records_of(client, headers)[0]
    assert (row["cancelled_amount"], row["cancelled_at"], row["value"]) == (0, None, 430)


def test_payment_without_a_revision_is_not_counted(client):
    # 위험 검토 17번. Mr.Life 개정은 2026-07-15부터다. 7월 1일 결제는 맞는 개정이 없어 계산하지 않고 실적에도 넣지 않는다
    headers, [mrlife] = setup(client, NO_GUESS)
    pay(client, headers, mrlife, 10000, "이마트", at="2026-07-01T12:00:00+09:00")
    [row] = records_of(client, headers, "2026-07")
    assert (row["value"], row["counted"]) == (0, False)


def test_past_month_ranked_benefit_uses_the_month_end_rank(client):
    # 위험 검토 7번, E48. 삼성 iD ON은 30만 구간부터 그 달 이용액 1위 영역만 30% 할인, 월 1만 원까지다. 7월 이마트
    # 30만 원으로 8월이 30만 구간이다. 8월 5일 스타벅스 1만 원은 그때 커피가 1위라 3,000원이었다. 8월 20일 배민 2만 원이
    # 들어오면 8월 끝 1위는 배달이라 스타벅스 0원, 배민 6,000원이다. 배민을 5,000원으로 고치면 다시 커피가 1위라
    # 스타벅스 3,000원, 배민 0원이다
    headers, [ion] = setup(client, {"card_id": "samsung-id-on"})
    pay(client, headers, ion, 300000, "이마트", at="2026-07-10T12:00:00+09:00")
    assert pay(client, headers, ion, 10000, "스타벅스", at="2026-08-05T12:00:00+09:00")["value"] == 3000
    baemin = pay(client, headers, ion, 20000, "배민", at="2026-08-20T12:00:00+09:00")
    assert baemin["value"] == 6000

    def august():
        return {r["merchant_name"]: r["value"] for r in records_of(client, headers, "2026-08")}

    assert august() == {"스타벅스": 0, "배민": 6000}
    edit(client, headers, baemin["id"], ion, 5000, "배민", at="2026-08-20T12:00:00+09:00")
    assert august() == {"스타벅스": 3000, "배민": 0}


def total_of(client, headers, month="2026-09"):
    return client.get("/me/payments", params={"month": month}, headers=headers).json()["benefit_total"]


def test_cancel_does_not_rerank_a_past_month(client):
    # 재검토 중간 3번. 삼성 iD ON은 영역 이용액의 취소를 취소 접수월에 넣는데 엔진은 결제한 달에서 뺀다. 담을 칸이 없어
    # 취소로 지나간 달 순위를 다시 매기지 않는다. 8월 스타벅스 1만 5천 원 4,500원, 배민 1만 2천 원 0원이다. 9월 3일 스타벅스
    # 5,000원 취소를 적으면 스타벅스만 남은 1만 원의 30%로 3,000원이고 배민은 0원 그대로다
    headers, [ion] = setup(client, {"card_id": "samsung-id-on"})
    pay(client, headers, ion, 300000, "이마트", at="2026-07-10T12:00:00+09:00")
    star = pay(client, headers, ion, 15000, "스타벅스", at="2026-08-05T12:00:00+09:00")
    assert star["value"] == 4500
    assert pay(client, headers, ion, 12000, "배민", at="2026-08-20T12:00:00+09:00")["value"] == 0
    cancel = {"cancelled_amount": 5000, "cancelled_at": "2026-09-03T12:00:00+09:00"}
    assert client.post(f"/me/payments/{star['id']}/cancel", json=cancel, headers=headers).status_code == 200
    august = {r["merchant_name"]: r["value"] for r in records_of(client, headers, "2026-08")}
    assert august == {"스타벅스": 3000, "배민": 0}


def test_move_last_month_payment_into_this_month(client):
    # 위험 검토 19번. 8월 이마트 30만 원으로 9월이 30만 구간이라 GS25 4,300원 430원이다. 이마트를 9월 1일로 옮기면
    # 8월 실적이 0원이라 9월이 0원 구간이고 GS25도 0원이다
    headers, [mrlife] = setup(client, NO_GUESS)
    aug = pay(client, headers, mrlife, 300000, "이마트", at="2026-08-20T12:00:00+09:00")["id"]
    pay(client, headers, mrlife, 4300, "GS25")
    edit(client, headers, aug, mrlife, 300000, "이마트", at="2026-09-01T12:00:00+09:00")
    assert total_of(client, headers) == 0


def test_tier_boundary_299999_and_300000(client):
    # 위험 검토 19번. 8월 실적 299,999원이면 9월이 0원 구간이라 GS25 0원, 30만 원으로 고치면 30만 구간이라 430원이다
    headers, [mrlife] = setup(client, NO_GUESS)
    aug = pay(client, headers, mrlife, 299999, "이마트", at="2026-08-20T12:00:00+09:00")["id"]
    pay(client, headers, mrlife, 4300, "GS25")
    assert total_of(client, headers) == 0
    edit(client, headers, aug, mrlife, 300000, "이마트", at="2026-08-20T12:00:00+09:00")
    assert total_of(client, headers) == 430


def test_edit_a_cancelled_payment_keeps_the_cancel(client):
    # 위험 검토 19번. GS25 1만 원 가운데 5,000원을 취소해 500원이다. 1만 2,000원으로 고치면 취소는 그대로라 남은
    # 7,000원의 10%로 700원이다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 10000, "GS25", at="2026-09-14T21:00:00+09:00")["id"]
    cancel = {"cancelled_amount": 5000, "cancelled_at": "2026-09-14T22:00:00+09:00"}
    assert client.post(f"/me/payments/{tid}/cancel", json=cancel, headers=headers).json()["value"] == 500
    assert edit(client, headers, tid, mrlife, 12000, "GS25", at="2026-09-14T21:00:00+09:00")["value"] == 700


def test_edit_a_payment_on_a_removed_card(client):
    # 위험 검토 19번. 해지한 카드의 결제도 그 카드 그대로 고친다. GS25 4,300원을 1만 원으로 고치면 1,000원이다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 4300, "GS25")["id"]
    assert client.delete(f"/me/cards/{mrlife}", headers=headers).status_code == 200
    assert edit(client, headers, tid, mrlife, 10000, "GS25")["value"] == 1000
