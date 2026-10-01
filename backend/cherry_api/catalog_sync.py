"""카탈로그 파일을 카탈로그 표에 맞춘다. 작업 005 설계 4절

ERD의 외래 키가 카탈로그 표를 가리켜서 서버가 켜질 때 맞춘다. 지우지 않는다. 계산은 메모리의 엔진이 한다.
카드사와 카드는 지금 파일 내용으로 고친다. 개정은 내용이 바뀌면 새 행을 더해 옛 행을 남긴다.
"""

from __future__ import annotations

import hashlib
import json

import psycopg
from psycopg.types.json import Jsonb

from cherry_core.catalog.load import Catalog

from .db import LOCK


def rules_json(rules) -> dict:
    return rules.model_dump(mode="json", by_alias=True)


def rules_sha256(data: dict) -> str:
    text = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode()).hexdigest()


def sync_catalog(conn: psycopg.Connection, catalog: Catalog) -> None:
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (LOCK,))
        for code, loaded in catalog.issuers.items():
            conn.execute(
                "INSERT INTO issuers (code, name) VALUES (%s, %s)"
                " ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name",
                (code, loaded.issuer.name),
            )
        for card_id, loaded in catalog.cards.items():
            c = loaded.card
            conn.execute(
                """
                INSERT INTO cards (id, issuer_code, name, search_names, kind, product_codes, status, status_since,
                                   annual_fees, sources, checked_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (id) DO UPDATE SET
                    issuer_code = EXCLUDED.issuer_code, name = EXCLUDED.name, search_names = EXCLUDED.search_names,
                    kind = EXCLUDED.kind, product_codes = EXCLUDED.product_codes, status = EXCLUDED.status,
                    status_since = EXCLUDED.status_since, annual_fees = EXCLUDED.annual_fees,
                    sources = EXCLUDED.sources, checked_at = EXCLUDED.checked_at
                """,
                (
                    card_id,
                    c.issuer,
                    c.name,
                    c.search_names,
                    c.kind,
                    c.product_codes,
                    c.status,
                    c.status_since,
                    Jsonb([f.model_dump(mode="json") for f in c.annual_fees]),
                    Jsonb([s.model_dump(mode="json") for s in c.sources]),
                    c.checked_at,
                ),
            )
            for rev, rules in loaded.revisions:
                data = rules_json(rules)
                # 개정 행은 쌓기만 한다. 같은 날의 개정이 고쳐지면 새 행이 생기고 옛 행은 그대로다
                # 시행일이 추정인지는 해시에 들어가지 않아 그 칸만 고친다
                # ponytail: 해시는 Rules 모델 전체의 덤프다. 기본값 있는 칸을 모델에 더하면 모든 개정이 새 행이 된다
                conn.execute(
                    """
                    INSERT INTO card_revisions (card_id, effective_from, effective_from_estimated, rules, rules_sha256,
                                                schema_version)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (card_id, effective_from, rules_sha256) DO UPDATE SET
                        effective_from_estimated = EXCLUDED.effective_from_estimated
                    WHERE card_revisions.effective_from_estimated <> EXCLUDED.effective_from_estimated
                    """,
                    (
                        card_id,
                        rev.effective_from,
                        rev.effective_from_estimated,
                        Jsonb(data),
                        rules_sha256(data),
                        c.schema_version,
                    ),
                )
