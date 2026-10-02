"""이용 내역 엑셀 가져오기. 작업 005 설계 5f, 계획 슬라이스 6. S11, E30~E35, E51, E57

신한카드 Mr.Life를 지난달 41만 원으로 등록해 30만 구간이다. 편의점 10%는 하루 종일, 하루 1회라 GS25 4,300원은
430원이다. 야간 식음료 10%는 21시부터라 21시 카페 4,500원은 450원이다. 시계는 2026-09-15 21:00 한국 시간이다.
"""

import json

from .test_payments import MRLIFE, pay
from .test_records import records_of, setup

ZERO = {"card_id": "hyundai-zero-edition3-discount"}
HEAD = "이용일자,이용시간,가맹점명,이용금액,할부,승인번호,취소여부"


def csv(*lines: str) -> bytes:
    return "\n".join([HEAD, *lines]).encode("cp949")


def preview(client, headers, data: bytes, **params):
    r = client.post("/me/imports/preview", params=params, content=data, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def save(client, headers, p: dict, mapping: dict | None = None):
    # 앱처럼 판정받은 행을 모두 보낸다. 짝을 차지한 겹친 행이 빠지면 다시 판정이 달라진다
    rows = [r for r in p["rows"] if "paid_at" in r]
    r = client.post("/me/imports", json={"rows": rows, "mapping": mapping}, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


def statuses(p: dict) -> list:
    return [(r["status"], r.get("reason")) for r in p["rows"]]


MONTH = csv(
    '2026.09.10,21:30,GS25 강남점,"4,300",일시불,A1001,',
    '2026.09.11,,이마트 성수점,"120,000",3개월,A1002,',
    '2026.09.12,22:00,GS25 강남점,"-4,300",일시불,A1001,취소',
    '합계,,,"120,000",,,',
)


def test_month_twice_goes_in_once(client):
    # S11 성공 기준. 9월 10일 21시 30분 GS25 4,300원은 430원, 9월 11일 이마트 12만 원 3개월은 0원이다. 9월 12일 GS25 전액
    # 취소는 승인번호가 같은 9월 10일 결제에 붙어 0원이 된다. 이마트는 시각이 없어 그날 12시이고 시각을 모른다. 3개월은
    # 무이자인지 몰라 유이자로 넣고 센다. 같은 파일을 다시 올리면 셋 모두 겹쳐 아무것도 들어가지 않는다
    headers, [mrlife] = setup(client, MRLIFE)
    p = preview(client, headers, MONTH, user_card_id=mrlife)
    assert statuses(p) == [("new", None), ("new", None), ("cancel", None)]
    assert p["summary"] == {
        "rows": 3,
        "new": 2,
        "amount": 124300,
        "duplicates": 0,
        "cancels": 1,
        "orphans": 0,
        "skipped": 0,
        "errors": 0,
        "uncategorized": 0,
        "interest_unknown": 1,
        "easy_pay": 0,
        "untimed": 1,
    }
    assert p["rows"][1]["paid_at"] == "2026-09-11T12:00:00+09:00" and p["rows"][1]["timed"] is False
    done = save(client, headers, p)
    assert (done["imported"], done["cancels"], done["duplicates"]) == (2, 1, 0)
    got = {
        r["merchant_name"]: (r["value"], r["cancelled_amount"], r["time_known"]) for r in records_of(client, headers)
    }
    assert got == {"GS25 강남점": (0, 4300, True), "이마트 성수점": (0, 0, False)}
    again = preview(client, headers, MONTH, user_card_id=mrlife)
    assert [s for s, _ in statuses(again)] == ["duplicate", "duplicate", "duplicate"]
    assert len(records_of(client, headers)) == 2


def test_partial_cancels_on_two_days_go_in_once(client):
    # 높음 1번. 1만 원 결제에 9월 12일 3,000원, 9월 13일 2,000원 취소가 있다. 남은 5,000원의 10%로 500원이다. 같은
    # 파일을 다시 올려도 취소는 5,000원 그대로다
    headers, [mrlife] = setup(client, MRLIFE)
    data = csv(
        '2026.09.10,21:00,GS25,"10,000",,A2001,',
        '2026.09.12,10:00,GS25,"-3,000",,A2001,취소',
        '2026.09.13,10:00,GS25,"-2,000",,A2001,취소',
    )
    save(client, headers, preview(client, headers, data, user_card_id=mrlife))
    [row] = records_of(client, headers)
    assert (row["value"], row["cancelled_amount"]) == (500, 5000)
    again = preview(client, headers, data, user_card_id=mrlife)
    assert [s for s, _ in statuses(again)] == ["duplicate", "duplicate", "duplicate"]
    [row] = records_of(client, headers)
    assert row["cancelled_amount"] == 5000


def test_same_rows_in_one_file_are_two_payments(client):
    # 중간 5번. 시각 없는 파일의 같은 날 GS25 1,500원 두 줄은 두 결제다. 이미 있는 결제와만 겹침을 본다
    headers, [mrlife] = setup(client, MRLIFE)
    p = preview(client, headers, csv("2026.09.10,,GS25,1500,,,", "2026.09.10,,GS25,1500,,,"), user_card_id=mrlife)
    assert [s for s, _ in statuses(p)] == ["new", "new"]


def test_manual_payment_overlaps_within_ten_minutes(client):
    # E31, 2026-10-02 사용자가 넓혔다. 직접 넣은 21시 3분 "GS25" 4,300원과 파일의 21시 "GS25 역삼점" 4,300원은 10분 안이고
    # 한 이름이 다른 이름을 담아 겹친다. 21시 20분이면 다른 결제다. 원 결제가 없는 취소는 저장하지 않는다. E32
    headers, [mrlife] = setup(client, MRLIFE)
    pay(client, headers, mrlife, 4300, "GS25", at="2026-09-14T21:03:00+09:00")
    data = csv(
        '2026.09.14,21:00,GS25 역삼점,"4,300",,,',
        '2026.09.14,21:20,GS25 역삼점,"4,300",,,',
        '2026.09.13,10:00,CU 역삼점,"-2,000",,,취소',
    )
    p = preview(client, headers, data, user_card_id=mrlife)
    assert statuses(p) == [("duplicate", None), ("new", None), ("orphan", "원 결제를 찾지 못했어요")]


def test_cancel_with_approval_finds_a_manual_payment(client):
    # 중간 6번. 직접 넣은 결제에는 승인번호가 없다. 승인번호가 같은 결제가 없으면 가맹점과 금액으로 찾는다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 10000, "GS25", at="2026-09-10T21:00:00+09:00")["id"]
    save(
        client, headers, preview(client, headers, csv('2026.09.12,10:00,GS25,"-10,000",,A9,취소'), user_card_id=mrlife)
    )
    assert {r["id"]: r["cancelled_amount"] for r in records_of(client, headers)} == {tid: 10000}


def test_cancel_on_a_payment_already_cancelled_in_the_app(client):
    # 중간 13번. 앱에서 3,000원 취소를 적은 결제에 승인번호 없는 파일의 취소가 오면 겹치는지 몰라 넣지 않는다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 10000, "GS25", at="2026-09-10T21:00:00+09:00")["id"]
    body = {"cancelled_amount": 3000, "cancelled_at": "2026-09-14T10:00:00+09:00"}
    assert client.post(f"/me/payments/{tid}/cancel", json=body, headers=headers).status_code == 200
    p = preview(client, headers, csv('2026.09.12,10:00,GS25,"-3,000",,,취소'), user_card_id=mrlife)
    assert statuses(p) == [("orphan", "앱에서 적은 취소가 있어 겹치는지 몰라요. 기록에서 확인해 주세요")]


def test_two_cancels_go_to_two_payments(client):
    # 낮음 22번. 9월 5일과 8일의 GS25 1만 원에 1만 원 취소가 둘이면 하나씩 붙는다
    headers, [mrlife] = setup(client, MRLIFE)
    data = csv(
        "2026.09.05,21:00,GS25,10000,,,",
        "2026.09.08,21:00,GS25,10000,,,",
        "2026.09.10,10:00,GS25,-10000,,,취소",
        "2026.09.11,10:00,GS25,-10000,,,취소",
    )
    save(client, headers, preview(client, headers, data, user_card_id=mrlife))
    assert sorted(r["cancelled_amount"] for r in records_of(client, headers)) == [10000, 10000]


def test_undo_two_batches_in_any_order(client):
    # 중간 12번. 1만 원 결제에 묶음 1이 3,000원, 묶음 2가 2,000원 취소를 붙였다. 묶음 1을 되돌리면 2,000원이 남고, 묶음 2도
    # 되돌리면 0원이다. 남은 5,000원 취소면 500원, 2,000원이면 남은 8,000원의 10%로 800원, 0원이면 1,000원이다
    headers, [mrlife] = setup(client, MRLIFE)
    tid = pay(client, headers, mrlife, 10000, "GS25", at="2026-09-10T21:00:00+09:00")["id"]
    one = save(
        client, headers, preview(client, headers, csv("2026.09.12,10:00,GS25,-3000,,,취소"), user_card_id=mrlife)
    )
    two = save(
        client, headers, preview(client, headers, csv("2026.09.13,10:00,GS25,-2000,,,취소"), user_card_id=mrlife)
    )

    def row():
        [r] = records_of(client, headers)
        return r["id"], r["cancelled_amount"], r["value"]

    assert row() == (tid, 5000, 500)
    assert client.delete(f"/me/imports/{one['id']}", headers=headers).status_code == 200
    assert row() == (tid, 2000, 800)
    assert client.delete(f"/me/imports/{two['id']}", headers=headers).status_code == 200
    assert row() == (tid, 0, 1000)
    assert client.delete(f"/me/imports/{two['id']}", headers=headers).status_code == 404


def test_undo_removes_imported_payments(client):
    # E34. 가져온 결제는 지워지고 목록에 되돌린 시각이 남는다
    headers, [mrlife] = setup(client, MRLIFE)
    done = save(client, headers, preview(client, headers, csv("2026.09.15,12:00,이마트,30000,,,"), user_card_id=mrlife))
    [batch] = client.get("/me/imports", headers=headers).json()
    assert (batch["id"], batch["imported_count"], batch["undone_at"]) == (done["id"], 1, None)
    assert client.delete(f"/me/imports/{done['id']}", headers=headers).status_code == 200
    assert records_of(client, headers) == []
    assert client.get("/me/imports", headers=headers).json()[0]["undone_at"] is not None


def test_earlier_imported_payment_takes_the_daily_limit(client):
    # E51. 편의점 10%는 하루 1회다. 직접 넣은 9월 14일 21시 30분 GS25 4,300원이 430원이었다. 같은 날 21시 GS25 5,000원을
    # 가져오면 앞선 결제가 하루 1회를 먼저 써 500원이고 21시 30분 결제는 0원이다. 금액이 달라 겹치지 않는다
    headers, [mrlife] = setup(client, MRLIFE)
    late = pay(client, headers, mrlife, 4300, "GS25", at="2026-09-14T21:30:00+09:00")["id"]
    data = csv('2026.09.14,21:00,GS25 역삼점,"5,000",,,')
    assert save(client, headers, preview(client, headers, data, user_card_id=mrlife))["repriced"] == 1
    values = {r["id"]: r["value"] for r in records_of(client, headers)}
    assert values[late] == 0 and sorted(values.values()) == [0, 500]


def test_untimed_payment_does_not_get_a_night_benefit(client):
    # E57. 야간 식음료는 21시부터다. 시각이 있는 21시 30분 스타벅스 4,500원은 450원이다. 시각이 없는 같은 날 스타벅스는
    # 시각을 몰라 0원이다
    headers, [mrlife] = setup(client, MRLIFE)
    data = csv("2026.09.10,21:30,스타벅스,4500,,,", "2026.09.11,,스타벅스,4500,,,")
    save(client, headers, preview(client, headers, data, user_card_id=mrlife))
    assert sorted(r["value"] for r in records_of(client, headers)) == [0, 450]


def test_easy_pay_future_rows_and_card_column(client):
    # 결제수단은 가맹점명이 간편결제 이름으로 시작하면 그 결제수단이다. 지금보다 하루 넘게 뒤의 결제는 읽지 못한 행이다.
    # 카드 이름 열로 나누고 보유 카드에 없는 카드의 행은 건너뛴다. E33. 고른 카드가 있으면 카드 이름 열보다 앞선다
    headers, [mrlife, zero] = setup(client, MRLIFE, ZERO)
    lines = [
        "카드명,이용일자,가맹점명,이용금액",
        "신한카드 Mr.Life,2026.09.10,네이버페이 스타벅스,4300",
        "현대카드ZERO Edition3(할인형),2026.09.10,이마트,10000",
        "롯데카드 LOCA 365,2026.09.10,이마트,20000",
        "신한카드 Mr.Life,2026.12.10,이마트,20000",
    ]
    data = "\n".join(lines).encode()
    p = preview(client, headers, data)
    assert [(r["status"], r["user_card_id"]) for r in p["rows"]] == [
        ("new", mrlife),
        ("new", zero),
        ("skipped", None),
        ("error", None),
    ]
    assert (p["rows"][0]["payment_method"], p["rows"][3]["reason"]) == ("naver_pay", "지금보다 뒤의 결제예요")
    assert p["summary"]["easy_pay"] == 1
    chosen = preview(client, headers, data, user_card_id=zero)
    assert [r["user_card_id"] for r in chosen["rows"][:3]] == [zero, zero, zero]


def test_mapping_is_kept_when_saving(client):
    # E30. 열 이름을 못 찾으면 머리 줄과 열 이름을 준다. 짝지은 열 번호로 읽고, 저장할 때 남겨 같은 모양의 다음 파일에
    # 쓴다. 미리보기만 하고 그만두면 남기지 않는다
    headers, [mrlife] = setup(client, MRLIFE)
    data = "날,곳,값\n2026.09.10,GS25,4300\n".encode()
    p = preview(client, headers, data, user_card_id=mrlife)
    assert (p["needs_mapping"], p["header_row"], p["headers"], p["rows"]) == (True, 0, ["날", "곳", "값"], [])
    mapping = {"row": 0, "columns": {"date": 0, "merchant": 1, "amount": 2}}
    read = preview(client, headers, data, user_card_id=mrlife, mapping=json.dumps(mapping))
    assert read["summary"]["new"] == 1
    assert preview(client, headers, data, user_card_id=mrlife)["needs_mapping"] is True
    save(client, headers, read, {"signature": read["signature"], "columns": read["mapping"]})
    later = preview(client, headers, "날,곳,값\n2026.09.11,CU,1000\n".encode(), user_card_id=mrlife)
    assert later["summary"]["new"] == 1


def test_bad_files_and_requests(client):
    headers, [mrlife] = setup(client, MRLIFE)
    url = "/me/imports/preview"
    old = client.post(url, params={"user_card_id": mrlife}, content=b"\xd0\xcf\x11\xe0" + b"0" * 64, headers=headers)
    assert old.status_code == 422 and "xlsx" in old.json()["detail"]
    # 카드 이름 열이 없으면 카드를 골라야 한다
    assert client.post(url, content=MONTH, headers=headers).status_code == 422
    big = client.post(url, params={"user_card_id": mrlife}, content=b"0" * 2_100_000, headers=headers)
    assert big.status_code == 413
    bad = client.post(url, params={"user_card_id": mrlife, "mapping": "{"}, content=MONTH, headers=headers)
    assert bad.status_code == 422
    row = {
        "user_card_id": mrlife,
        "paid_at": "2026-09-10T21:30:00+09:00",
        "timed": True,
        "merchant_name": "GS25",
        "amount": 4300,
        "installment_months": 1,
        "approval_no": None,
        "cancel": False,
    }
    # 빈 저장, 5년보다 오래된 행, 남의 카드는 받지 않는다
    assert client.post("/me/imports", json={"rows": []}, headers=headers).status_code == 422
    old_row = {**row, "paid_at": "2019-01-01T12:00:00+09:00"}
    assert client.post("/me/imports", json={"rows": [old_row]}, headers=headers).status_code == 422
    _, [theirs] = setup(client, MRLIFE, name="other")
    r = client.post("/me/imports", json={"rows": [{**row, "user_card_id": theirs}]}, headers=headers)
    assert r.status_code == 404


def test_past_month_cancel_on_a_ranked_card_without_the_cancel_month(client):
    # 중간 11번, E55. 삼성 iD ON은 순위 영역의 취소 달 칸이 비어 있다. 지나간 8월 스타벅스의 취소를 가져오면 순위를 다시
    # 매기지 않으려 넣지 않고 기록에서 직접 적게 한다
    headers, [ion] = setup(client, {"card_id": "samsung-id-on"})
    pay(client, headers, ion, 300000, "이마트", at="2026-07-10T12:00:00+09:00")
    pay(client, headers, ion, 10000, "스타벅스", at="2026-08-05T12:00:00+09:00")
    p = preview(client, headers, csv("2026.08.20,10:00,스타벅스,-5000,,,취소"), user_card_id=ion)
    assert statuses(p) == [("orphan", "이 카드는 순위 혜택의 취소 달을 몰라요. 기록에서 직접 적어 주세요")]


def test_save_matches_the_preview(client):
    # 재검토 높음 1번. 직접 넣은 12시 GS25 1,500원과 파일의 12시 2분, 12시 6분 GS25 1,500원이다. 12시 2분이 겹치고 12시 6분은
    # 새 결제다. 저장도 1건이다. 묶음 1이 9월 12일 3,000원 취소를 붙인 결제에 같은 날 3,000원 취소가 두 줄 오면 하나는
    # 겹치고 하나는 진짜 두 번째 취소다. 저장하면 취소가 6,000원이고 남은 4,000원의 10%로 400원이다
    headers, [mrlife] = setup(client, MRLIFE)
    pay(client, headers, mrlife, 1500, "GS25", at="2026-09-10T12:00:00+09:00")
    p = preview(
        client, headers, csv("2026.09.10,12:02,GS25,1500,,,", "2026.09.10,12:06,GS25,1500,,,"), user_card_id=mrlife
    )
    assert p["summary"]["new"] == 1
    assert save(client, headers, p)["imported"] == 1
    other, [card] = setup(client, MRLIFE, name="b")
    tid = pay(client, other, card, 10000, "GS25", at="2026-09-10T21:00:00+09:00")["id"]
    save(client, other, preview(client, other, csv("2026.09.12,10:00,GS25,-3000,,,취소"), user_card_id=card))
    two = csv("2026.09.12,10:00,GS25,-3000,,,취소", "2026.09.12,11:00,GS25,-3000,,,취소")
    p = preview(client, other, two, user_card_id=card)
    assert [s for s, _ in statuses(p)] == ["duplicate", "cancel"]
    assert save(client, other, p)["cancels"] == 1
    assert {r["id"]: (r["cancelled_amount"], r["value"]) for r in records_of(client, other)} == {tid: (6000, 400)}


def test_same_approval_in_new_rows_is_one_payment(client):
    # 재검토 중간 3번. 승인 줄과 매입 줄처럼 새 행 둘의 승인번호가 같으면 한 결제다. 저장이 500이 되지 않는다
    headers, [mrlife] = setup(client, MRLIFE)
    data = csv("2026.09.10,21:00,GS25,4300,,B5001,", "2026.09.11,09:00,GS25,4300,,B5001,")
    p = preview(client, headers, data, user_card_id=mrlife)
    assert [s for s, _ in statuses(p)] == ["new", "duplicate"]
    assert save(client, headers, p)["imported"] == 1


def test_untimed_cancel_after_a_timed_payment_on_the_same_day(client):
    # 재검토 중간 6번. 9월 12일 21시 30분 GS25 4,300원과 시각 없는 같은 날 취소가 한 파일에 있으면 붙는다. 취소 시각은 결제보다
    # 앞서지 않아 그 결제를 고칠 수 있다
    headers, [mrlife] = setup(client, MRLIFE)
    data = csv("2026.09.12,21:30,GS25,4300,,,", "2026.09.12,,GS25,-4300,,,취소")
    save(client, headers, preview(client, headers, data, user_card_id=mrlife))
    [row] = records_of(client, headers)
    assert row["cancelled_amount"] == 4300 and row["cancelled_at"] >= row["paid_at"]
    body = {"user_card_id": mrlife, "amount": 4300, "merchant_name": "GS25 역삼점", "paid_at": row["paid_at"]}
    assert client.patch(f"/me/payments/{row['id']}", json=body, headers=headers).status_code == 200


def test_editing_an_untimed_payment_keeps_the_time_unknown(client):
    # 재검토 중간 5번. 시각 없는 결제의 가게만 고치면 시각은 여전히 모른다. 시각을 바꾸면 안다. E57
    headers, [mrlife] = setup(client, MRLIFE)
    save(client, headers, preview(client, headers, csv("2026.09.11,,스타벅스,4500,,,"), user_card_id=mrlife))
    [row] = records_of(client, headers)
    body = {"user_card_id": mrlife, "amount": 4500, "merchant_name": "스타벅스 역삼", "paid_at": row["paid_at"]}
    client.patch(f"/me/payments/{row['id']}", json=body, headers=headers)
    assert records_of(client, headers)[0]["time_known"] is False
    client.patch(f"/me/payments/{row['id']}", json=body | {"paid_at": "2026-09-11T21:30:00+09:00"}, headers=headers)
    [row] = records_of(client, headers)
    assert (row["time_known"], row["value"]) == (True, 450)


def test_ten_minutes_is_the_edge(client):
    # E31 경계. 직접 넣은 21시 GS25 4,300원과 파일의 21시 10분은 겹치고 21시 10분 1초는 다른 결제다
    headers, [mrlife] = setup(client, MRLIFE)
    pay(client, headers, mrlife, 4300, "GS25", at="2026-09-10T21:00:00+09:00")
    pay(client, headers, mrlife, 4300, "GS25", at="2026-09-11T21:00:00+09:00")
    data = csv("2026.09.10,21:10:00,GS25,4300,,,", "2026.09.11,21:10:01,GS25,4300,,,")
    assert [s for s, _ in statuses(preview(client, headers, data, user_card_id=mrlife))] == ["duplicate", "new"]


def test_body_size_edge(client):
    # 2,000,000바이트는 받고 2,000,001바이트는 413이다
    headers, [mrlife] = setup(client, MRLIFE)
    head = (HEAD + chr(10)).encode("cp949")
    # 짧은 줄로 채운다. 한 칸이 너무 길면 csv가 읽지 못한다
    line = b"x" * 999 + bytes([10])
    filler = line * ((2_000_000 - len(head)) // len(line))
    ok = head + filler + b"x" * (2_000_000 - len(head) - len(filler))
    assert len(ok) == 2_000_000
    url = "/me/imports/preview"
    assert client.post(url, params={"user_card_id": mrlife}, content=ok, headers=headers).status_code == 200
    assert client.post(url, params={"user_card_id": mrlife}, content=ok + b" ", headers=headers).status_code == 413
