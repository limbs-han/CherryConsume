"""세션 토큰, 카카오와 Google 로그인, 개발용 로그인, 탈퇴한 사용자 지우기. 작업 005 설계 3절, 5g"""

from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta
from typing import Annotated
from uuid import UUID

import httpx
import psycopg
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from .deps import Conn

TOKEN_DAYS = 365
# 탈퇴하면 30일 뒤 사용자 영역을 지운다. E27
PURGE_DAYS = 30
KAKAO_INFO = "https://kapi.kakao.com/v1/user/access_token_info"
GOOGLE_INFO = "https://oauth2.googleapis.com/tokeninfo"
GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


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


def login_as(request: Request, provider: str, uid: str) -> dict:
    """그 수단의 사용자로 세션을 만든다. 처음이면 사용자를 만든다. 탈퇴한 사용자는 403이다. E27, E29

    카카오와 Google을 부르는 동안 DB 연결을 잡지 않으려 확인이 끝난 뒤 연결을 잡는다
    """
    with request.app.state.pool.connection() as conn:
        row = conn.execute(
            "SELECT a.user_id, u.deleted_at FROM auth_identities a JOIN users u ON u.id = a.user_id"
            " WHERE a.provider = %s AND a.provider_uid = %s",
            (provider, uid),
        ).fetchone()
        if row is not None and row["deleted_at"] is not None:
            raise HTTPException(403, "탈퇴한 계정이에요. 탈퇴하고 30일이 지나면 다시 가입할 수 있어요")
        if row is None:
            user_id = conn.execute("INSERT INTO users DEFAULT VALUES RETURNING id").fetchone()["id"]
            # 같은 사람의 첫 로그인이 동시에 둘 오면 먼저 들어간 쪽의 사용자를 쓴다. 남는 빈 사용자는 만들지 않는다
            mine = conn.execute(
                "INSERT INTO auth_identities (user_id, provider, provider_uid) VALUES (%s, %s, %s)"
                " ON CONFLICT (provider, provider_uid) DO NOTHING RETURNING user_id",
                (user_id, provider, uid),
            ).fetchone()
            if mine is None:
                conn.execute("DELETE FROM users WHERE id = %s", (user_id,))
                user_id = conn.execute(
                    "SELECT user_id FROM auth_identities WHERE provider = %s AND provider_uid = %s", (provider, uid)
                ).fetchone()["user_id"]
        else:
            user_id = row["user_id"]
        return {"token": new_session(conn, user_id, request.app.state.clock())}


def ask(request: Request, method: str, url: str, **kw) -> httpx.Response:
    """카카오와 Google을 부른다. 닿지 않으면 502다

    ponytail: 5초는 연결, 쓰기, 읽기마다 걸린다. 로그인 횟수 제한은 1차에 두지 않는다. 설계 5h
    """
    try:
        return request.app.state.http.request(method, url, timeout=5, **kw)
    except httpx.HTTPError:
        raise HTTPException(502, "로그인 서버에 닿지 못했어요") from None


def json_of(r: httpx.Response) -> dict:
    """200인데 몸통이 JSON 객체가 아니면 그쪽 서버의 문제라 502다"""
    try:
        body = r.json()
    except ValueError:
        body = None
    if not isinstance(body, dict):
        raise HTTPException(502, "로그인 서버의 답을 읽지 못했어요")
    return body


# 토큰은 아스키 글자만이다. 머리글에 실을 수 없는 글자가 오면 422로 막는다
TOKEN = r"^[\x21-\x7e]+$"


class KakaoLogin(BaseModel):
    # 모르는 칸은 422다. 이메일이나 이름을 몰래 받지 않는다
    model_config = ConfigDict(extra="forbid")
    access_token: str = Field(min_length=1, max_length=4096, pattern=TOKEN)


class GoogleLogin(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id_token: str = Field(min_length=1, max_length=8192, pattern=TOKEN)


@router.post("/kakao")
def kakao_login(body: KakaoLogin, request: Request) -> dict:
    """앱이 카카오에서 받은 접근 토큰이 우리 앱의 것인지 보고 카카오 사용자 번호로 로그인한다. 작업 005 설계 5g"""
    app_id = request.app.state.kakao_app_id
    if not app_id:
        raise HTTPException(503, "카카오 로그인이 설정되지 않았다")
    r = ask(request, "GET", KAKAO_INFO, headers={"Authorization": f"Bearer {body.access_token}"})
    if r.status_code in (400, 401):
        raise HTTPException(401, "카카오 로그인을 확인하지 못했어요")
    if r.status_code != 200:
        raise HTTPException(502, "카카오 서버가 답하지 않았어요")
    info = json_of(r)
    # 다른 앱이 받은 토큰으로 우리 사용자가 되지 않게 우리 앱의 토큰인지 본다
    if str(info.get("app_id")) != str(app_id) or not info.get("id"):
        raise HTTPException(401, "카카오 로그인을 확인하지 못했어요")
    return login_as(request, "kakao", str(info["id"]))


@router.post("/google")
def google_login(body: GoogleLogin, request: Request) -> dict:
    """앱이 Google에서 받은 신분 토큰을 Google에 확인하고 Google 사용자 번호로 로그인한다. 작업 005 설계 5g

    신분 토큰에는 이메일, 이름, 사진 주소가 들어 있다. 사용자 번호만 쓰고 나머지는 저장하지도 로그에 남기지도 않는다
    ponytail: Google의 확인 API를 부른다. 로그인이 많아지면 Google 공개 키로 서명을 직접 본다
    """
    client_id = request.app.state.google_client_id
    if not client_id:
        raise HTTPException(503, "Google 로그인이 설정되지 않았다")
    r = ask(request, "POST", GOOGLE_INFO, data={"id_token": body.id_token})
    if r.status_code == 400:
        raise HTTPException(401, "Google 로그인을 확인하지 못했어요")
    if r.status_code != 200:
        raise HTTPException(502, "Google 서버가 답하지 않았어요")
    info = json_of(r)
    now = request.app.state.clock().timestamp()
    ok = (
        info.get("aud") == client_id
        and info.get("iss") in GOOGLE_ISSUERS
        and str(info.get("exp", "")).isdigit()
        and int(info["exp"]) > now
        and info.get("sub")
    )
    if not ok:
        raise HTTPException(401, "Google 로그인을 확인하지 못했어요")
    return login_as(request, "google", str(info["sub"]))


def purge_deleted(conn: psycopg.Connection, now: datetime) -> int:
    """탈퇴하고 30일이 지난 사용자와 만료된 세션을 지운다. 사용자 표는 모두 연쇄로 지워진다. 지운 사용자 수. E27"""
    conn.execute("DELETE FROM sessions WHERE expires_at <= %s", (now,))
    cur = conn.execute(
        "DELETE FROM users WHERE deleted_at IS NOT NULL AND deleted_at <= %s", (now - timedelta(days=PURGE_DAYS),)
    )
    return cur.rowcount


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
