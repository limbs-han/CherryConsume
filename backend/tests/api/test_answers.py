"""모르는 값 묻기. 카드 사실, 옵션, 쓰기 시작한 날, 사람 사실. 작업 005 설계 5e, 계획 슬라이스 5. E56

시계는 2026-09-15 21:00 한국 시간이다. 처음 답은 그 카드의 모든 결제에, 바꾼 답은 바뀌는 날부터 쓴다.
2026-10-02 사용자가 정했다.
"""

from .test_payments import pay
from .test_records import records_of, setup

TAPTAP = {"card_id": "samsung-taptap-o", "assumed_prev_month_spend": 300000}
NARA = {"card_id": "ibk-narasarang"}


def answer(client, headers, uid, **body):
    r = client.put(f"/me/cards/{uid}/answers", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def test_first_option_answer_reprices_and_a_change_waits(client):
    # 삼성 taptap O를 지난달 30만 원으로 등록해 30만 구간이다. 패키지를 모르면 9월 10일 스타벅스 1만 원은 0원이다.
    # 처음 p1이라고 답하면 패키지 1~3의 스타벅스 50%로 5,000원이다. p4로 바꾸면 이 옵션은 다음 달부터라 9월은
    # 그대로 5,000원이고 카드 상세에 10월부터 p4가 보인다
    headers, [tap] = setup(client, TAPTAP)
    tid = pay(client, headers, tap, 10000, "스타벅스", at="2026-09-10T12:00:00+09:00")["id"]
    assert records_of(client, headers)[0]["value"] == 0
    assert answer(client, headers, tap, options={"package": "p1"})["repriced"] == 1
    assert [(r["id"], r["value"]) for r in records_of(client, headers)] == [(tid, 5000)]
    assert answer(client, headers, tap, options={"package": "p4"})["repriced"] == 0
    assert records_of(client, headers)[0]["value"] == 5000
    [package] = client.get(f"/me/cards/{tap}", headers=headers).json()["questions"]["options"]
    assert (package["answer"], package["pending"]) == ("p1", {"value": "p4", "from": "2026-10-01"})
    # 같은 답을 다시 하면 아무것도 하지 않는다
    assert answer(client, headers, tap, options={"package": "p4"})["repriced"] == 0


def test_card_fact_change_applies_from_this_month(client):
    # IBK 나라사랑 철도 5%는 8만 구간부터인데 병 급여이체를 받으면 실적이 면제된다. 추정값 없이 등록해 8월과 9월이 0원
    # 구간이라 KTX 2만 원은 0원이다. 처음 급여이체를 받았다고 답하면 두 달 모두 1,000원이다. 9월에 받지 않았다로 바꾸면
    # 한국 시간 이번 달 1일부터라 8월 31일 23시 59분은 1,000원 그대로이고 9월 1일 0시는 0원이다
    headers, [nara] = setup(client, NARA)
    pay(client, headers, nara, 20000, "KTX", at="2026-08-31T23:59:00+09:00")
    pay(client, headers, nara, 20000, "KTX", at="2026-09-01T00:00:00+09:00")

    def values():
        return [records_of(client, headers, m)[0]["value"] for m in ("2026-08", "2026-09")]

    assert values() == [0, 0]
    assert answer(client, headers, nara, facts={"salary_transfer": True})["repriced"] == 2
    assert values() == [1000, 1000]
    assert answer(client, headers, nara, facts={"salary_transfer": False})["repriced"] == 1
    assert values() == [1000, 0]
    # 이번 달에 바꾼 답을 다시 받았다로 되돌리면 이번 달 답을 지운다
    assert answer(client, headers, nara, facts={"salary_transfer": True})["repriced"] == 1
    assert values() == [1000, 1000]
    facts = {q["key"]: q for q in client.get(f"/me/cards/{nara}", headers=headers).json()["questions"]["facts"]}
    assert facts["salary_transfer"]["answer"] is True
    # 사람 사실인 현역병 여부는 카드 정보에 없다. 설정에서 묻는다
    assert "soldier" not in facts


def test_started_on_answer_reprices_every_payment(client):
    # taptap O를 추정값 없이 등록하면 0원 구간이라 9월 10일 CGV 1만 원은 0원이다. 쓰기 시작한 날을 9월 1일로 답하면
    # 신규 발급 특례로 영화에 30만 구간을 줘 5,000원이다
    headers, [tap] = setup(client, {"card_id": "samsung-taptap-o"})
    pay(client, headers, tap, 10000, "CGV", at="2026-09-10T12:00:00+09:00")
    assert answer(client, headers, tap, started_on="2026-09-01")["repriced"] == 1
    assert records_of(client, headers)[0]["value"] == 5000
    assert client.get(f"/me/cards/{tap}", headers=headers).json()["started_on"] == "2026-09-01"


def test_bad_answers(client):
    headers, [tap, nara] = setup(client, TAPTAP, NARA)
    url = f"/me/cards/{tap}/answers"
    for body in (
        {"options": {"package": "p9"}},
        {"options": {"nothing": "p1"}},
        {"facts": {"salary_transfer": True}},
        {"started_on": "2026-12-01"},
        {"card_number": "1234"},
    ):
        assert client.put(url, json=body, headers=headers).status_code == 422, body
    nara_url = f"/me/cards/{nara}/answers"
    # 종류가 bool이면 참과 거짓만 받는다. 사람 사실은 카드 답으로 받지 않는다
    assert client.put(nara_url, json={"facts": {"salary_transfer": "yes"}}, headers=headers).status_code == 422
    assert client.put(nara_url, json={"facts": {"soldier": True}}, headers=headers).status_code == 422
    other, _ = setup(client, NARA, name="other")
    assert client.put(nara_url, json={"facts": {"salary_transfer": True}}, headers=other).status_code == 404


def test_user_fact_reprices_every_card_that_uses_it(client):
    # 사람 사실 현역병 여부. IBK 나라사랑 PX 3만 원 미만 15%는 현역병이거나 급여이체를 받아야 한다. 9월 10일 PX 2만 원은
    # 둘 다 몰라 0원이다. 설정에서 현역병이라고 답하면 15%로 3,000원이다
    headers, [nara] = setup(client, NARA)
    pay(client, headers, nara, 20000, "PX", at="2026-09-10T12:00:00+09:00")
    [soldier] = client.get("/me/facts", headers=headers).json()
    assert (soldier["key"], soldier["type"], soldier["answer"], soldier["cards"]) == (
        "soldier",
        "bool",
        None,
        ["IBK나라사랑카드"],
    )
    r = client.put("/me/facts", json={"facts": {"soldier": True}}, headers=headers)
    assert r.json() == {"repriced": 1}
    assert records_of(client, headers)[0]["value"] == 3000
    assert client.get("/me/facts", headers=headers).json()[0]["answer"] is True
    # 카드 사실은 설정에서 받지 않는다. 종류가 틀린 답도 422다
    for facts in ({"salary_transfer": True}, {"soldier": "yes"}):
        assert client.put("/me/facts", json={"facts": facts}, headers=headers).status_code == 422
    # 묻는 카드가 없으면 목록이 비고 답도 받지 않는다
    other, _ = setup(client, TAPTAP, name="other")
    assert client.get("/me/facts", headers=other).json() == []
    assert client.put("/me/facts", json={"facts": {"soldier": True}}, headers=other).status_code == 422


def test_ask_child_category_after_saving(client):
    # E47. IBK 나라사랑을 지난달 20만 원으로 등록해 20만 구간이다. 이동통신 자동납부 5%는 업종이 이동통신이어야 하는데
    # "KT 요금"은 통신요금까지만 알아 0원이고 자식 업종을 묻는다. 이동통신이라고 고치면 5만 원의 5% 2,500원이 월
    # 2천 원 한도에 걸려 2,000원이고 더 묻지 않는다
    headers, [nara] = setup(client, {"card_id": "ibk-narasarang", "assumed_prev_month_spend": 200000})
    saved = pay(client, headers, nara, 50000, "KT 요금")
    assert saved["value"] == 0
    ask = saved["ask_category"]
    assert (ask["parent"], ask["parent_name"]) == ("telecom", "통신요금")
    assert [c["code"] for c in ask["children"]] == ["telecom.internet_tv", "telecom.mobile"]
    body = {
        "user_card_id": nara,
        "amount": 50000,
        "merchant_name": "KT 요금",
        "paid_at": "2026-09-15T21:00:00+09:00",
        "category": "telecom.mobile",
    }
    edited = client.patch(f"/me/payments/{saved['id']}", json=body, headers=headers).json()
    assert (edited["value"], edited["ask_category"]) == (2000, None)


def test_recommendation_shows_what_an_answer_would_add(client):
    # 설계 5c의 미뤄 둔 것. taptap O 30만 구간에서 스타벅스 1만 원은 패키지를 몰라 0원이다. 패키지 1~3이면 50%로 5,000원,
    # 4~6이면 커피 30%로 3,000원이라 가장 큰 p1의 5,000원을 묻는다. IBK PX 2만 원은 현역병이나 급여이체면 3,000원이다
    headers, [tap, nara] = setup(client, TAPTAP, NARA)

    def asks(merchant, amount):
        body = {"merchant_name": merchant, "amount": amount}
        rows = client.post("/me/recommendations", json=body, headers=headers).json()["ranking"]
        return {r["user_card_id"]: [(a["kind"], a["key"], a.get("choice"), a["extra"]) for a in r["ask"]] for r in rows}

    assert asks("스타벅스", 10000)[tap] == [("option", "package", "p1", 5000)]
    assert sorted(asks("PX", 20000)[nara]) == [("fact", "salary_transfer", None, 3000), ("fact", "soldier", None, 3000)]


def test_option_default_reservation_and_immediate_change(client):
    # 재검토 중간 2번. 하나 원더 조합은 기본값이 DAILY라 처음 DAILY라고 답해도 계산이 같아 다시 계산하지 않는다.
    # 오늘부터 바뀌는 옵션이라 custom으로 바꾸면 예약 없이 바로 답이 된다. taptap O는 p1을 쓰는 중에 p4를 예약했다가
    # p1을 다시 누르면 예약만 지운다. 낮음 9번
    headers, [wonder, tap] = setup(client, {"card_id": "hana-wonder2-daily"}, TAPTAP)
    pay(client, headers, wonder, 10000, "스타벅스", at="2026-09-10T12:00:00+09:00")
    assert answer(client, headers, wonder, options={"combo": "daily"})["repriced"] == 0
    [combo] = client.get(f"/me/cards/{wonder}", headers=headers).json()["questions"]["options"]
    assert (combo["answer"], combo["pending"]) == ("daily", None)
    answer(client, headers, wonder, options={"combo": "custom"})
    [combo] = client.get(f"/me/cards/{wonder}", headers=headers).json()["questions"]["options"]
    assert (combo["answer"], combo["pending"]) == ("custom", None)
    answer(client, headers, tap, options={"package": "p1"})
    answer(client, headers, tap, options={"package": "p4"})
    answer(client, headers, tap, options={"package": "p1"})
    [package] = client.get(f"/me/cards/{tap}", headers=headers).json()["questions"]["options"]
    assert (package["answer"], package["pending"]) == ("p1", None)


def test_birth_month(client):
    # 재검토 중간 4번. KB My WE:SH 먹는데 진심은 배달앱 5%, 월 5천 원까지다. 생일 달이고 쓰기 시작한 지 한 달이 지났으면
    # 한도가 2배다. 지난달 40만 원으로 등록하고 8월 1일부터 썼다. 9월 10일 배민 20만 원은 5%로 1만 원이라 한도 5천 원이다.
    # 생일이 9월이라고 답하면 한도 1만 원이라 1만 원이다. 달은 1~12의 정수만 받는다
    headers, [wesh] = setup(
        client, {"card_id": "kb-my-wesh", "assumed_prev_month_spend": 400000, "started_on": "2026-08-01"}
    )
    pay(client, headers, wesh, 200000, "배민", at="2026-09-10T12:00:00+09:00")
    answer(client, headers, wesh, options={"pack": "eat"})
    assert records_of(client, headers)[0]["value"] == 5000
    for wrong in (True, 13, "9"):
        assert client.put("/me/facts", json={"facts": {"birth_month": wrong}}, headers=headers).status_code == 422
    assert client.put("/me/facts", json={"facts": {"birth_month": 9}}, headers=headers).json() == {"repriced": 1}
    assert records_of(client, headers)[0]["value"] == 10000


def test_user_fact_reprices_a_removed_card(client):
    # 재검토 중간 3번. 사람 사실은 그 사실을 쓰는 카드를 모두 다시 계산한다. IBK를 해지했다가 다시 등록한 사람이 현역병이라고
    # 답하면 해지한 옛 카드의 9월 10일 PX 2만 원도 3,000원이다
    headers, [old] = setup(client, NARA)
    pay(client, headers, old, 20000, "PX", at="2026-09-10T12:00:00+09:00")
    assert client.delete(f"/me/cards/{old}", headers=headers).status_code == 200
    assert client.get("/me/facts", headers=headers).json() == []
    client.post("/me/cards", json=NARA, headers=headers)
    assert client.put("/me/facts", json={"facts": {"soldier": True}}, headers=headers).json() == {"repriced": 1}
    assert records_of(client, headers)[0]["value"] == 3000
