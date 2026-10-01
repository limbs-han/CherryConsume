"""서버 테스트. Docker의 Postgres로 돈다. 작업 005 설계 7절

CHERRY_TEST_DATABASE_URL이 없으면 건너뛴다. 묶음이 시작할 때 빈 DB를 새로 만들고 끝나면 지운다.
"""

from __future__ import annotations

import os
import uuid
from datetime import UTC, datetime

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg.conninfo import make_conninfo

from cherry_api.db import connect
from cherry_api.main import create_app

ADMIN_URL = os.environ.get("CHERRY_TEST_DATABASE_URL")
# 2026-09-15 21:00 한국 시간
START = datetime(2026, 9, 15, 12, 0, tzinfo=UTC)


@pytest.fixture(scope="session")
def db_url():
    if not ADMIN_URL:
        pytest.skip("CHERRY_TEST_DATABASE_URL이 없어 서버 테스트를 건너뛴다. docker compose up -d db 뒤 설정한다")
    name = f"cherry_test_{uuid.uuid4().hex[:8]}"
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"CREATE DATABASE {name}")
    yield make_conninfo(ADMIN_URL, dbname=name)
    with psycopg.connect(ADMIN_URL, autocommit=True) as admin:
        admin.execute(f"DROP DATABASE {name} WITH (FORCE)")


class Clock:
    def __init__(self) -> None:
        self.now = START

    def __call__(self) -> datetime:
        return self.now


@pytest.fixture(scope="session")
def clock():
    return Clock()


@pytest.fixture(scope="session")
def server(db_url, clock):
    with TestClient(create_app(database_url=db_url, dev_login=True, clock=clock)) as client:
        yield client


@pytest.fixture
def client(server, db_url, clock):
    """테스트마다 사용자 영역을 비우고 시계를 처음으로 돌린다. 카탈로그 표는 남긴다"""
    clock.now = START
    with connect(db_url) as conn:
        conn.execute("TRUNCATE users CASCADE")
    return server


@pytest.fixture
def db(db_url):
    with connect(db_url) as conn:
        yield conn


def login(client: TestClient, name: str = "jihan") -> dict:
    r = client.post("/auth/dev", json={"name": name})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}
