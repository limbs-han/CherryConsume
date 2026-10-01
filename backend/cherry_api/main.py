"""FastAPI 앱. `uvicorn cherry_api.main:create_app --factory`로 켠다. 작업 005 설계

환경변수
- CHERRY_DATABASE_URL: Postgres 주소. 꼭 있어야 한다
- CHERRY_CATALOG_DIR: 카탈로그 폴더. 기본은 저장소의 catalog/
- CHERRY_DEV_LOGIN: 1이면 개발용 로그인을 켠다. PC의 DB에만 켜진다. 끄고 켜면 개발용 사용자의 세션을 지운다
"""

from __future__ import annotations

import os
from collections.abc import Callable
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path

from fastapi import FastAPI, Request
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
from .routes import catalog, me, payments

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
        yield
        app.state.pool.close()

    # API 문서 화면은 개발할 때만 연다
    docs = {} if dev_login else {"docs_url": None, "redoc_url": None, "openapi_url": None}
    app = FastAPI(title="체리컨슘", lifespan=lifespan, **docs)
    app.add_exception_handler(RequestValidationError, validation_error)
    app.state.clock = clock or (lambda: datetime.now(UTC))
    app.include_router(auth.router)
    if dev_login:
        app.include_router(auth.dev_router)
    app.include_router(catalog.router)
    app.include_router(me.router)
    app.include_router(payments.router)
    return app
