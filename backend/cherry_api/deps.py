"""요청마다 쓰는 것. 연결 하나는 요청 하나의 트랜잭션이다. 예외가 나면 되돌리고 아니면 커밋한다"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date
from typing import Annotated

import psycopg
from fastapi import Depends, Request

from cherry_core.engine.cond import local


def get_conn(request: Request) -> Iterator[psycopg.Connection]:
    with request.app.state.pool.connection() as conn:
        yield conn


# scope="function"은 경로 함수가 끝나면 응답을 보내기 전에 커밋한다. 기본값은 응답 뒤에 커밋해서
# 앱이 저장된 줄 알았는데 커밋이 실패하거나, 로그인 직후 다음 요청이 세션을 못 찾을 수 있었다. 2026-10-01 위험 검토
Conn = Annotated[psycopg.Connection, Depends(get_conn, scope="function")]


def today(request: Request) -> date:
    """한국 시간의 오늘. 달 경계는 한국 시간이다. E7"""
    return local(request.app.state.clock()).date()
