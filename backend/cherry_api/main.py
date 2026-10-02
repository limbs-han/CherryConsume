"""FastAPI 앱. `uvicorn cherry_api.main:create_app --factory`로 켠다. 작업 005 설계

환경변수
- CHERRY_DATABASE_URL: Postgres 주소. 꼭 있어야 한다
- CHERRY_CATALOG_DIR: 카탈로그 폴더. 기본은 저장소의 catalog/
- CHERRY_DEV_LOGIN: 1이면 개발용 로그인을 켠다. PC의 DB에만 켜진다. 끄고 켜면 개발용 사용자의 세션을 지운다
- CHERRY_KAKAO_APP_ID: 카카오 앱 ID. 앱이 보낸 토큰이 우리 앱의 것인지 본다. 없으면 카카오 로그인이 503이다
- CHERRY_GOOGLE_CLIENT_ID: Google 웹 클라이언트 ID. 없으면 Google 로그인이 503이다
"""

from __future__ import annotations

import asyncio
import logging
import os
from collections.abc import Callable
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from psycopg.conninfo import conninfo_to_dict
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine

from . import auth
from .catalog_sync import revision_ids, sync_catalog
from .db import migrate
from .payments import alias_index
from .routes import answers, catalog, imports, me, payments, recommend, records

REPO = Path(__file__).resolve().parents[2]
LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    """422 본문에서 받은 값을 뺀다. 카드번호 같은 값을 보내면 응답에 그대로 되돌아왔다. 2026-10-01 위험 검토"""
    # 모르는 칸은 칸 이름에 값을 넣어 보낼 수도 있어 위치도 뺀다
    detail = [
        {
            k: v
            for k, v in e.items()
            if k not in ("input", "ctx") and not (k == "loc" and e["type"] == "extra_forbidden")
        }
        for e in exc.errors()
    ]
    return JSONResponse({"detail": detail}, status_code=422)


def create_app(
    database_url: str | None = None,
    catalog_dir: Path | None = None,
    dev_login: bool | None = None,
    clock: Callable[[], datetime] | None = None,
    kakao_app_id: str | None = None,
    google_client_id: str | None = None,
    http: httpx.Client | None = None,
) -> FastAPI:
    database_url = database_url or os.environ["CHERRY_DATABASE_URL"]
    catalog_dir = Path(catalog_dir or os.environ.get("CHERRY_CATALOG_DIR") or REPO / "catalog")
    if dev_login is None:
        dev_login = os.environ.get("CHERRY_DEV_LOGIN") == "1"
    # 개발용 로그인은 이름만 알면 들어간다. 운영 DB에 켜진 채로 배포되지 않게 PC의 DB에서만 켠다
    # ponytail: PC의 주소로 운영 DB에 이어 주는 SSH 터널이나 프록시는 가리지 못한다
    info = conninfo_to_dict(database_url)
    hosts = {h for key in ("host", "hostaddr") for h in str(info.get(key) or "").split(",") if h}
    if dev_login and not hosts <= LOCAL_HOSTS:
        raise RuntimeError("개발용 로그인은 PC의 DB에서만 켠다")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        # 카탈로그에 오류가 있으면 엔진이 만들어지지 않아 서버가 켜지지 않는다. 작업 002 설계
        app.state.catalog = load_catalog(catalog_dir)
        app.state.engine = Engine(app.state.catalog)
        app.state.aliases = alias_index(app.state.catalog)
        app.state.billing_bound = recommend.billing_bound(app.state.catalog)
        tree = app.state.catalog.category_tree
        app.state.category_names = {c.code: c.name for c in tree} | {
            f"{c.code}.{ch.code}": ch.name for c in tree for ch in c.children
        }
        app.state.pool = ConnectionPool(database_url, kwargs={"row_factory": dict_row}, open=True)
        with app.state.pool.connection() as conn:
            migrate(conn)
            sync_catalog(conn, app.state.catalog)
            app.state.revision_ids = revision_ids(conn, app.state.catalog)
            if not dev_login:
                # 켜 둔 동안 받은 개발용 토큰이 끈 뒤에도 1년 동안 살아 있지 않게 한다
                conn.execute(
                    "DELETE FROM sessions WHERE user_id IN (SELECT user_id FROM auth_identities WHERE provider = 'dev')"
                )
        purger = asyncio.create_task(purge_daily(app))
        yield
        purger.cancel()
        app.state.pool.close()

    async def purge_daily(app: FastAPI) -> None:
        """켜질 때와 24시간마다 탈퇴하고 30일이 지난 사용자를 지운다. E27"""

        def once() -> None:
            with app.state.pool.connection() as conn:
                auth.purge_deleted(conn, app.state.clock())

        # 한 번 실패해도 멈추지 않는다. DB가 잠깐 끊겨도 탈퇴한 사람이 30일 뒤 지워진다는 약속을 지킨다
        while True:
            try:
                await run_in_threadpool(once)
                wait = 24 * 60 * 60
            except Exception:
                logging.getLogger("cherry_api").exception("탈퇴한 사용자를 지우지 못했다. 1시간 뒤 다시 한다")
                wait = 60 * 60
            await asyncio.sleep(wait)

    # API 문서 화면은 개발할 때만 연다
    docs = {} if dev_login else {"docs_url": None, "redoc_url": None, "openapi_url": None}
    app = FastAPI(title="체리컨슘", lifespan=lifespan, **docs)
    app.add_exception_handler(RequestValidationError, validation_error)
    app.state.clock = clock or (lambda: datetime.now(UTC))
    app.state.kakao_app_id = kakao_app_id or os.environ.get("CHERRY_KAKAO_APP_ID")
    app.state.google_client_id = google_client_id or os.environ.get("CHERRY_GOOGLE_CLIENT_ID")
    app.state.http = http or httpx.Client()
    app.include_router(auth.router)
    if dev_login:
        app.include_router(auth.dev_router)
    app.include_router(catalog.router)
    app.include_router(me.router)
    app.include_router(payments.router)
    app.include_router(recommend.router)
    app.include_router(records.router)
    app.include_router(answers.router)
    app.include_router(imports.router)
    return app
