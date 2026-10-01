"""세션과 개발용 로그인. 작업 005 계획 슬라이스 1의 4단계, 의도 성공 기준 7"""

from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

from cherry_api.main import create_app

from .conftest import login


def test_dev_login_is_missing_when_off(db_url, server):
    with TestClient(create_app(database_url=db_url, dev_login=False)) as off:
        assert off.post("/auth/dev", json={"name": "jihan"}).status_code == 404


def test_dev_login_reads_the_env(db_url, server, monkeypatch):
    monkeypatch.setenv("CHERRY_DEV_LOGIN", "true")
    with TestClient(create_app(database_url=db_url)) as off:
        assert off.post("/auth/dev", json={"name": "jihan"}).status_code == 404
    monkeypatch.setenv("CHERRY_DEV_LOGIN", "1")
    with TestClient(create_app(database_url=db_url)) as on:
        assert on.post("/auth/dev", json={"name": "jihan"}).status_code == 200


def test_dev_login_only_on_a_local_db(monkeypatch):
    with pytest.raises(RuntimeError, match="PC의 DB"):
        create_app(database_url="postgresql://cherry:x@db.example.com:5432/cherry", dev_login=True)
    with pytest.raises(RuntimeError, match="PC의 DB"):
        create_app(database_url="postgresql://cherry:x@localhost:5432/cherry?hostaddr=203.0.113.5", dev_login=True)


def test_dev_tokens_end_when_dev_login_is_off(client, db_url):
    # 켜 둔 동안 받은 토큰으로 끈 서버에 들어가지 못한다
    headers = login(client)
    with TestClient(create_app(database_url=db_url, dev_login=False)) as off:
        assert off.get("/me/home", headers=headers).status_code == 401


def test_api_docs_only_in_dev(db_url, server):
    assert server.get("/docs").status_code == 200
    with TestClient(create_app(database_url=db_url, dev_login=False)) as off:
        assert off.get("/docs").status_code == 404
        assert off.get("/openapi.json").status_code == 404


def test_same_name_is_same_user(client, db):
    login(client)
    login(client)
    assert db.execute("SELECT count(*) AS n FROM users").fetchone()["n"] == 1
    assert db.execute("SELECT count(*) AS n FROM sessions").fetchone()["n"] == 2


def test_token_is_not_stored(client, db):
    token = login(client)["Authorization"].removeprefix("Bearer ")
    stored = db.execute("SELECT token_sha256 FROM sessions").fetchone()["token_sha256"]
    assert stored != token and len(stored) == 64


def test_no_token_is_401(client):
    assert client.get("/me/home").status_code == 401
    assert client.get("/me/home", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_logged_out_token_is_401(client):
    headers = login(client)
    assert client.post("/auth/logout", headers=headers).status_code == 204
    assert client.get("/me/home", headers=headers).status_code == 401


def test_expired_token_is_401(client, clock):
    headers = login(client)
    clock.now += timedelta(days=366)
    assert client.get("/me/home", headers=headers).status_code == 401


def test_deleted_user_is_401_at_once(client, db):
    # 설계 문서 4.3절 5번. 탈퇴하면 즉시 로그인을 막는다
    headers = login(client)
    db.execute("UPDATE users SET deleted_at = now()")
    db.commit()
    assert client.get("/me/home", headers=headers).status_code == 401
    assert client.post("/auth/dev", json={"name": "jihan"}).status_code == 403
