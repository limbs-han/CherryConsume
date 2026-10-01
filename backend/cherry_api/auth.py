"""세션 토큰과 개발용 로그인. 작업 005 설계 3절"""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta
from typing import Annotated
from uuid import UUID

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from .deps import Conn

TOKEN_DAYS = 365


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_session(conn: psycopg.Connection, user_id: UUID, now: datetime) -> str:
    token = secrets.token_urlsafe(32)
    conn.execute(
        "INSERT INTO sessions (token_sha256, user_id, created_at, expires_at) VALUES (%s, %s, %s, %s)",
        (token_hash(token), user_id, now, now + timedelta(days=TOKEN_DAYS)),
    )
    return token


def bearer(request: Request) -> str:
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(401, "로그인이 필요하다")
    return token


def current_user(request: Request, conn: Conn) -> UUID:
    """토큰의 사용자. 만료된 세션과 탈퇴한 사용자는 막는다. 탈퇴는 즉시 막아야 해서 요청마다 DB를 본다"""
    row = conn.execute(
        "SELECT s.user_id FROM sessions s JOIN users u ON u.id = s.user_id"
        " WHERE s.token_sha256 = %s AND s.expires_at > %s AND u.deleted_at IS NULL",
        (token_hash(bearer(request)), request.app.state.clock()),
    ).fetchone()
    if row is None:
        raise HTTPException(401, "로그인이 필요하다")
    return row["user_id"]


User = Annotated[UUID, Depends(current_user)]

router = APIRouter(prefix="/auth")


@router.post("/logout", status_code=204)
def logout(request: Request, conn: Conn) -> None:
    conn.execute("DELETE FROM sessions WHERE token_sha256 = %s", (token_hash(bearer(request)),))


class DevLogin(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str = Field(min_length=1, max_length=40)


# 개발용 로그인을 켠 서버에만 붙는다. 끈 서버에는 경로가 없어 404다
dev_router = APIRouter(prefix="/auth")


@dev_router.post("/dev")
def dev_login(body: DevLogin, request: Request, conn: Conn) -> dict:
    row = conn.execute(
        "SELECT a.user_id, u.deleted_at FROM auth_identities a JOIN users u ON u.id = a.user_id"
        " WHERE a.provider = 'dev' AND a.provider_uid = %s",
        (body.name,),
    ).fetchone()
    if row is not None and row["deleted_at"] is not None:
        raise HTTPException(403, "탈퇴한 사용자다")
    if row is None:
        user_id = conn.execute("INSERT INTO users DEFAULT VALUES RETURNING id").fetchone()["id"]
        conn.execute(
            "INSERT INTO auth_identities (user_id, provider, provider_uid) VALUES (%s, 'dev', %s)", (user_id, body.name)
        )
    else:
        user_id = row["user_id"]
    return {"token": new_session(conn, user_id, request.app.state.clock())}
