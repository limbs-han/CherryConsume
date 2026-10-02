"""카카오와 Google 로그인, 탈퇴, 30일 뒤 삭제. 작업 005 설계 5g, 계획 슬라이스 7. S1, S10, E27, E29, E36

카카오와 Google은 가짜 응답으로 대신한다. 시계는 2026-09-15 21:00 한국 시간이다.
"""

from datetime import timedelta

import httpx
import pytest
from fastapi.testclient import TestClient

from cherry_api.auth import purge_deleted
from cherry_api.db import connect
from cherry_api.main import create_app

KAKAO_APP = "123456"
GOOGLE_CLIENT = "web-client.apps.googleusercontent.com"
NOW = 1789473600  # 2026-09-15 12:00 UTC


def fake(request: httpx.Request) -> httpx.Response:
    if request.url.host == "kapi.kakao.com":
        token = request.headers.get("authorization", "").removeprefix("Bearer ")
        apps = {"kakao-a": (1001, KAKAO_APP), "kakao-b": (1002, KAKAO_APP), "kakao-other": (1003, "999")}
        if token == "kakao-down":
            return httpx.Response(500)
        if token == "kakao-html":
            return httpx.Response(200, text="<html>점검 중</html>")
        if token == "kakao-no-app":
            return httpx.Response(200, json={"id": 1004, "expires_in": 3600})
        if token == "kakao-slow":
            raise httpx.ReadTimeout("느리다", request=request)
        if token not in apps:
            return httpx.Response(401, json={"code": -401, "msg": "this access token does not exist"})
        uid, app = apps[token]
        return httpx.Response(200, json={"id": uid, "expires_in": 3600, "app_id": int(app)})
    if request.url.host == "oauth2.googleapis.com":
        token = dict(httpx.QueryParams(request.content.decode()))["id_token"]
        good = {"aud": GOOGLE_CLIENT, "sub": "g-1", "iss": "https://accounts.google.com", "exp": str(NOW + 3600)}
        claims = {
            "google-a": good,
            "google-other-aud": good | {"aud": "other.apps.googleusercontent.com"},
            "google-expired": good | {"exp": str(NOW - 1)},
            "google-bad-iss": good | {"iss": "https://evil.example.com"},
        }
        if token == "google-down":
            return httpx.Response(503)
        if token not in claims:
            return httpx.Response(400, json={"error": "invalid_token"})
        return httpx.Response(200, json=claims[token])
    return httpx.Response(404)


@pytest.fixture
def social(db_url, clock, client):
    """가짜 카카오와 Google을 붙인 서버. client가 사용자 영역을 비운다"""
    http = httpx.Client(transport=httpx.MockTransport(fake))
    app = create_app(
        database_url=db_url,
        dev_login=True,
        clock=clock,
        kakao_app_id=KAKAO_APP,
        google_client_id=GOOGLE_CLIENT,
        http=http,
    )
    with TestClient(app) as c:
        yield c


def kakao(c, token):
    return c.post("/auth/kakao", json={"access_token": token})


def google(c, token):
    return c.post("/auth/google", json={"id_token": token})


def bearer(r) -> dict:
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def test_kakao_first_login_makes_a_user_and_again_finds_it(social):
    # S1, S10. 처음 로그인하면 사용자를 만들고, 다른 기기에서 같은 카카오로 들어오면 같은 사용자다
    first = bearer(kakao(social, "kakao-a"))
    card = social.post("/me/cards", json={"card_id": "shinhan-mrlife"}, headers=first).json()["id"]
    again = bearer(kakao(social, "kakao-a"))
    assert [c["id"] for c in social.get("/me/home", headers=again).json()["cards"]] == [card]
    assert social.get("/me/account", headers=again).json()["provider"] == "kakao"


def test_bad_tokens_are_401_and_a_down_provider_is_502(social):
    # 다른 앱의 카카오 토큰, 없는 토큰, 받는 쪽이 다르거나 만료되거나 발급자가 다른 Google 토큰은 401이다
    for r in (
        kakao(social, "kakao-other"),
        kakao(social, "nope"),
        google(social, "google-other-aud"),
        google(social, "google-expired"),
        google(social, "google-bad-iss"),
        google(social, "nope"),
    ):
        assert r.status_code == 401, r.text
    assert kakao(social, "kakao-no-app").status_code == 401
    # 카카오나 Google이 실패하거나, 늦거나, JSON이 아닌 답을 주면 502다
    for r in (
        kakao(social, "kakao-down"),
        kakao(social, "kakao-html"),
        kakao(social, "kakao-slow"),
        google(social, "google-down"),
    ):
        assert r.status_code == 502, r.text
    # 머리글에 실을 수 없는 글자는 422다. 토큰은 응답에 되돌아오지 않는다
    bad = kakao(social, "가")
    assert bad.status_code == 422 and "가" not in bad.text
    assert social.post("/auth/kakao", json={"access_token": "kakao-a", "email": "x"}).status_code == 422


def test_same_person_with_kakao_and_google_is_two_users(social):
    # E29. 1차는 합치지 않는다
    a = bearer(kakao(social, "kakao-a"))
    b = bearer(google(social, "google-a"))
    social.post("/me/cards", json={"card_id": "shinhan-mrlife"}, headers=a)
    assert social.get("/me/home", headers=b).json()["cards"] == []
    assert social.get("/me/account", headers=b).json()["provider"] == "google"


def test_withdraw_blocks_at_once_and_purges_after_30_days(social, db_url, clock):
    # E27. 탈퇴하면 그 토큰과 다른 기기의 토큰이 바로 401이고, 다시 로그인하면 403이다. 30일 뒤 지우면 사용자 표가 비고
    # 같은 카카오로 새로 가입한다
    a = bearer(kakao(social, "kakao-a"))
    other_device = bearer(kakao(social, "kakao-a"))
    social.post("/me/cards", json={"card_id": "shinhan-mrlife"}, headers=a)
    assert social.delete("/me", headers=a).status_code == 200
    assert social.get("/me/home", headers=a).status_code == 401
    assert social.get("/me/home", headers=other_device).status_code == 401
    assert kakao(social, "kakao-a").status_code == 403
    with connect(db_url) as conn:
        assert purge_deleted(conn, clock() + timedelta(days=29)) == 0
        assert purge_deleted(conn, clock() + timedelta(days=30)) == 1
        assert conn.execute("SELECT count(*) AS n FROM user_cards").fetchone()["n"] == 0
    fresh = bearer(kakao(social, "kakao-a"))
    assert social.get("/me/home", headers=fresh).json()["cards"] == []


def test_purge_also_drops_expired_sessions(social, db_url, clock):
    # 설계 5h. 1년이 지난 세션은 쓸 수 없고 지우기 때 함께 지운다
    bearer(kakao(social, "kakao-a"))
    with connect(db_url) as conn:

        def sessions():
            return conn.execute("SELECT count(*) AS n FROM sessions").fetchone()["n"]

        purge_deleted(conn, clock() + timedelta(days=364))
        assert sessions() == 1
        purge_deleted(conn, clock() + timedelta(days=365))
        assert sessions() == 0


def test_not_configured_is_503(db_url, clock, client):
    with TestClient(create_app(database_url=db_url, dev_login=True, clock=clock)) as c:
        assert kakao(c, "kakao-a").status_code == 503
        assert google(c, "google-a").status_code == 503
