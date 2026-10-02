"""카드 검색, 등록 미리보기, 카드 등록과 홈. 작업 005 계획 슬라이스 1의 5, 6단계

신한카드 Mr.Life 2026-07-15 개정의 구간은 0, 30만, 50만, 100만이다. 새 카드 특례 구간은 30만이다.
시계는 2026-09-15 21:00 한국 시간이다.
"""

import re
from datetime import UTC, datetime

from .conftest import login


def names(rows):
    return [r["name"] for r in rows]


def test_search_by_name_and_alias(client):
    assert "신한카드 Mr.Life" in names(client.get("/catalog/cards", params={"q": "mr"}).json())
    assert names(client.get("/catalog/cards", params={"q": "미스터 라이프"}).json()) == ["신한카드 Mr.Life"]


def test_search_by_issuer(client):
    rows = client.get("/catalog/cards", params={"issuer": "shinhan"}).json()
    assert {r["issuer"] for r in rows} == {"shinhan"}
    assert len(rows) == 3


def test_search_row(client):
    row = client.get("/catalog/cards", params={"q": "mr.life"}).json()[0]
    # 연회비는 국내 전용 15,000원과 해외 겸용 18,000원 중 국내 전용
    assert row == {
        "id": "shinhan-mrlife",
        "name": "신한카드 Mr.Life",
        "issuer": "shinhan",
        "issuer_name": "신한카드",
        "kind": "credit",
        "annual_fee": 15000,
        "tiers": [300000, 500000, 1000000],
    }


def test_discontinued_card_is_hidden(client, monkeypatch):
    # E19
    card = client.app.state.catalog.cards["shinhan-mrlife"].card
    monkeypatch.setattr(card, "status", "discontinued")
    assert "신한카드 Mr.Life" not in names(client.get("/catalog/cards").json())
    assert client.get("/catalog/cards/shinhan-mrlife/preview").status_code == 404


def test_issuer_chips(client):
    chips = client.get("/catalog/issuers").json()
    assert len(chips) == 10
    assert {"code": "shinhan", "name": "신한카드"} in chips


def test_preview_with_last_month(client):
    # 지난달 41만은 30만 이상 50만 미만이라 30만 구간. 그 구간에서 받는 혜택은 30만부터인 10개 모두
    r = client.get("/catalog/cards/shinhan-mrlife/preview", params={"prev": 410000}).json()
    assert (r["tier"], r["tier_source"]) == (300000, "assumed")
    # 카드 안내 경고는 늘 붙는다. 조건을 문장으로만 담은 혜택과 공식 문구로 확인하지 못한 값이 있다
    assert r["warnings"] == ["check_conditions", "assumed_value"]
    assert r["tiers"] == [300000, 500000, 1000000]
    assert len(r["benefits"]) == 10 and "편의점 10% 할인" in r["benefits"]


def test_preview_without_last_month(client):
    # E1. 비우면 최저 구간 0원과 no_prev_month_data. 0원 구간에서 받는 혜택은 없다
    r = client.get("/catalog/cards/shinhan-mrlife/preview").json()
    assert (r["tier"], r["benefits"], r["warnings"][0]) == (0, [], "no_prev_month_data")


def test_preview_new_card(client):
    # 이번 달에 받은 새 카드는 실적이 없어도 특례 30만 구간이다
    r = client.get("/catalog/cards/shinhan-mrlife/preview", params={"started_on": "2026-09-01"}).json()
    assert (r["tier"], r["tier_source"]) == (300000, "new_card")


def test_preview_new_card_skips_package_benefits(client):
    # 삼성카드 taptap O는 새 카드 특례 30만 구간이지만 패키지 혜택 6개는 특례 구간이 0원이라 받지 못한다
    # 패키지 혜택은 옵션을 골라야 받는다. 고르지 않은 패키지끼리는 서로 배타라 목록에 넣지 않는다
    r = client.get("/catalog/cards/samsung-taptap-o/preview", params={"started_on": "2026-09-01"}).json()
    assert (r["tier"], r["tier_source"]) == (300000, "new_card")
    assert "대중교통 10% 할인" in r["benefits"]
    assert [b for b in r["benefits"] if b.startswith("[패키지")] == []


def test_preview_uses_the_default_option(client):
    # 하나 원더2 DAILY는 조합 옵션의 기본값이 daily라 고르지 않아도 그 조합 혜택을 받는다. 엔진과 같다
    r = client.get("/catalog/cards/hana-wonder2-daily/preview", params={"prev": 410000}).json()
    assert r["tier"] == 400000
    assert "배달앱 10% 할인" in r["benefits"]


def test_preview_spend_upper_bound(client):
    assert client.get("/catalog/cards/shinhan-mrlife/preview", params={"prev": 100_000_001}).status_code == 422


def test_add_card_and_home(client):
    headers = login(client)
    body = {"card_id": "shinhan-mrlife", "assumed_prev_month_spend": 410000}
    assert client.post("/me/cards", json=body, headers=headers).status_code == 201
    home = client.get("/me/home", headers=headers).json()
    assert home["month"] == "2026-09-01" and home["benefit_total"] == 0
    [card] = home["cards"]
    assert (card["card_id"], card["name"], card["issuer_name"]) == ("shinhan-mrlife", "신한카드 Mr.Life", "신한카드")
    assert card["tiers"] == [300000, 500000, 1000000]
    # 이번 달 실적 0원. 30만 구간을 지키려면 30만, 다음 50만 구간까지 50만
    assert card["spend"] == {
        "counted": 0,
        "tier": 300000,
        "tier_source": "assumed",
        "prev_month_counted": 410000,
        "to_keep": 300000,
        "next_tier": 500000,
        "to_next": 500000,
        "warnings": [
            {"code": "check_conditions", "benefit": None, "data": card["spend"]["warnings"][0]["data"]},
            {"code": "assumed_value", "benefit": None, "data": card["spend"]["warnings"][1]["data"]},
        ],
    }


def test_home_after_month_change(client, clock):
    # S6, E7. 9월 30일 15:30 UTC는 한국 시간 10월 1일 00:30이다. 등록한 달이 지나 추정값을 쓰지 않는다
    headers = login(client)
    client.post("/me/cards", json={"card_id": "shinhan-mrlife", "assumed_prev_month_spend": 410000}, headers=headers)
    clock.now = datetime(2026, 9, 30, 15, 30, tzinfo=UTC)
    home = client.get("/me/home", headers=headers).json()
    assert home["month"] == "2026-10-01"
    spend = home["cards"][0]["spend"]
    assert (spend["tier"], spend["tier_source"], spend["to_keep"], spend["to_next"]) == (0, "prev_month", None, 300000)


def test_home_just_before_month_change(client, clock):
    # 9월 30일 14:59:59 UTC는 한국 시간 9월 30일 23:59:59라 아직 9월이다
    headers = login(client)
    client.post("/me/cards", json={"card_id": "shinhan-mrlife", "assumed_prev_month_spend": 410000}, headers=headers)
    clock.now = datetime(2026, 9, 30, 14, 59, 59, tzinfo=UTC)
    home = client.get("/me/home", headers=headers).json()
    assert (home["month"], home["cards"][0]["spend"]["tier"]) == ("2026-09-01", 300000)


def test_card_without_tiers(client):
    # 현대 ZERO Edition3 할인형은 구간이 0원 하나라 실적 무관이다
    headers = login(client)
    client.post("/me/cards", json={"card_id": "hyundai-zero-edition3-discount"}, headers=headers)
    card = client.get("/me/home", headers=headers).json()["cards"][0]
    assert (card["tiers"], card["headline"]) == ([], "국내외 가맹점 0.8% 할인")
    assert (card["spend"]["to_keep"], card["spend"]["next_tier"]) == (None, None)


def test_same_card_again_is_409(client):
    headers = login(client)
    client.post("/me/cards", json={"card_id": "shinhan-mrlife"}, headers=headers)
    assert client.post("/me/cards", json={"card_id": "shinhan-mrlife"}, headers=headers).status_code == 409


def test_unknown_field_is_422(client):
    # 의도 성공 기준 6. 카드번호 같은 칸은 받지 않고, 오류 응답에도 보낸 값을 되돌리지 않는다
    headers = login(client)
    body = {"card_id": "shinhan-mrlife", "card_number": "1234-5678-9012-3456"}
    r = client.post("/me/cards", json=body, headers=headers)
    assert r.status_code == 422
    assert "1234" not in r.text


def test_no_request_field_looks_like_a_card_number(client):
    # 의도 성공 기준 6. 모든 경로의 요청 칸과 쿼리 칸 이름에 카드번호, 끝자리, 유효기간, CVC처럼 보이는 것이 없다
    schema = client.app.openapi()
    names = {k for s in schema["components"]["schemas"].values() for k in s.get("properties", {})}
    names |= {p["name"] for path in schema["paths"].values() for op in path.values() for p in op.get("parameters", [])}
    looks = re.compile(r"card_?(no|num)|number|^pan$|cvc|cvv|expir|last_?4|digits", re.IGNORECASE)
    assert "user_card_id" in names and [n for n in names if looks.search(n)] == []


def test_unknown_card_is_404(client):
    headers = login(client)
    assert client.post("/me/cards", json={"card_id": "nope-card"}, headers=headers).status_code == 404


def test_cards_are_per_user(client):
    a, b = login(client, "a"), login(client, "b")
    client.post("/me/cards", json={"card_id": "shinhan-mrlife"}, headers=a)
    assert client.get("/me/home", headers=b).json()["cards"] == []
