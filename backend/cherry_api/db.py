"""DB 연결과 마이그레이션. 작업 005 설계 2절"""

from __future__ import annotations

import hashlib
from pathlib import Path

import psycopg
from psycopg.rows import dict_row

MIGRATIONS = Path(__file__).parent / "migrations"
# 서버 여러 대가 함께 켜져도 마이그레이션과 카탈로그 맞추기는 한 대만 한다
LOCK = 5005


def connect(url: str) -> psycopg.Connection:
    """서버와 테스트는 모두 행을 dict로 받는다."""
    return psycopg.connect(url, row_factory=dict_row)


def migrate(conn: psycopg.Connection) -> list[str]:
    """돌리지 않은 마이그레이션을 번호 순서로 돌리고 돌린 파일 이름을 돌려준다. 하나라도 실패하면 모두 되돌린다."""
    ran = []
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (LOCK,))
        conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations"
            " (version text PRIMARY KEY, sha256 text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())"
        )
        done = {r["version"]: r["sha256"] for r in conn.execute("SELECT version, sha256 FROM schema_migrations")}
        files = sorted(MIGRATIONS.glob("*.sql"))
        numbers = [f.name.split("_", 1)[0] for f in files]
        if len(numbers) != len(set(numbers)):
            raise RuntimeError("마이그레이션 번호가 겹친다")
        # 돌린 것보다 앞 번호가 새로 들어오면 운영 DB와 새 DB에서 도는 순서가 달라진다
        late = [f.name for f in files if f.name not in done and done and f.name < max(done)]
        if late:
            raise RuntimeError(f"이미 돌린 것보다 앞 번호의 마이그레이션이 새로 들어왔다: {late}")
        for f in files:
            text = f.read_text(encoding="utf-8")
            sha = hashlib.sha256(text.encode()).hexdigest()
            if f.name in done:
                # 돌린 파일을 고치면 새 DB와 옛 DB의 표가 몰래 달라진다. 고칠 것은 새 번호로 더한다
                if done[f.name] != sha:
                    raise RuntimeError(f"이미 돌린 마이그레이션이 바뀌었다: {f.name}")
                continue
            conn.execute(text)
            conn.execute("INSERT INTO schema_migrations (version, sha256) VALUES (%s, %s)", (f.name, sha))
            ran.append(f.name)
    return ran
