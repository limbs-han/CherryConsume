"""카탈로그 파일을 카탈로그 표에 맞춘다. 작업 005 설계 4절

ERD의 외래 키가 카탈로그 표를 가리켜서 서버가 켜질 때 맞춘다. 지우지 않는다. 계산은 메모리의 엔진이 한다.
카드사와 카드는 지금 파일 내용으로 고친다. 개정은 내용이 바뀌면 새 행을 더해 옛 행을 남긴다.
"""

from __future__ import annotations

import hashlib
import json
from datetime import date

import psycopg
from psycopg.types.json import Jsonb

from cherry_core.catalog.load import Catalog

from .db import LOCK


def rules_json(rules) -> dict:
    return rules.model_dump(mode="json", by_alias=True)


def rules_sha256(data: dict) -> str:
    text = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode()).hexdigest()


def alias_key(alias: str) -> str:
    """별칭 비교 값. 카탈로그 검사의 별칭 겹침 검사와 같다"""
    return alias.replace(" ", "").lower()


def revision_ids(conn: psycopg.Connection, catalog: Catalog) -> dict[tuple[str, date], int]:
    """지금 카탈로그의 개정마다 같은 내용의 행 번호. 결제가 계산에 쓴 개정을 가리킬 때 쓴다. 작업 005 설계 5b절"""
    out = {}
    for card_id, loaded in catalog.cards.items():
        for rev, rules in loaded.revisions:
            row = conn.execute(
                "SELECT id FROM card_revisions WHERE card_id = %s AND effective_from = %s AND rules_sha256 = %s",
                (card_id, rev.effective_from, rules_sha256(rules_json(rules))),
            ).fetchone()
            out[(card_id, rev.effective_from)] = row["id"]
    return out


def sync_catalog(conn: psycopg.Connection, catalog: Catalog) -> None:
    with conn.transaction():
        conn.execute("SELECT pg_advisory_xact_lock(%s)", (LOCK,))
        rows = [(c.code, c.name, c.kakao, None) for c in catalog.category_tree]
        rows += [(f"{c.code}.{ch.code}", ch.name, ch.kakao, c.code) for c in catalog.category_tree for ch in c.children]
        for row in rows:  # 부모가 자식보다 먼저 들어간다
            conn.execute(
                "INSERT INTO categories (code, name_ko, kakao_group_code, parent_code) VALUES (%s, %s, %s, %s)"
                " ON CONFLICT (code) DO UPDATE SET name_ko = EXCLUDED.name_ko,"
                " kakao_group_code = EXCLUDED.kakao_group_code, parent_code = EXCLUDED.parent_code",
                row,
            )
        for m in catalog.merchants.values():
            conn.execute(
                "INSERT INTO merchants (key, name, category_code, billing) VALUES (%s, %s, %s, %s)"
                " ON CONFLICT (key) DO UPDATE SET name = EXCLUDED.name, category_code = EXCLUDED.category_code,"
                " billing = EXCLUDED.billing",
                (m.key, m.name, m.category, m.billing),
            )
            for alias in m.aliases:
                conn.execute(
                    "INSERT INTO merchant_aliases (alias, merchant_key) VALUES (%s, %s)"
                    " ON CONFLICT (alias) DO UPDATE SET merchant_key = EXCLUDED.merchant_key",
                    (alias_key(alias), m.key),
                )
        # 별칭은 다른 표가 가리키지 않아 카탈로그에서 지운 것은 지운다. 옛 가맹점을 가리킨 채 남지 않게 한다
        keep = [alias_key(a) for m in catalog.merchants.values() for a in m.aliases]
        conn.execute("DELETE FROM merchant_aliases WHERE NOT (alias = ANY(%s))", (keep,))
        for pm in catalog.payment_methods.values():
            conn.execute(
                "INSERT INTO payment_methods (key, name, statement_names) VALUES (%s, %s, %s)"
                " ON CONFLICT (key) DO UPDATE SET name = EXCLUDED.name, statement_names = EXCLUDED.statement_names",
                (pm.key, pm.name, pm.statement_names),
            )
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
