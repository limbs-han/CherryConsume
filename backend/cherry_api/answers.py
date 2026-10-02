"""모르는 값의 답. 카드 사실, 사람 사실, 옵션. 작업 005 설계 5e"""

from __future__ import annotations

import json
from datetime import date

from cherry_core.engine.models import FactPick, OptionPick

# 처음 답은 원래 그랬던 것을 알려 준 것이라 모든 결제에 쓴다. 2026-10-02 사용자가 정했다
FIRST = date.min


def attach_answers(conn, rows: list[dict]) -> list[dict]:
    """보유 카드 행마다 옵션 답과 사실 답을 붙인다. engine_card가 읽는다. 사람 사실은 그 사람의 모든 카드에 넣는다"""
    for r in rows:
        r["options"], r["fact_picks"] = [], []
    if not rows:
        return rows
    by = {str(r["id"]): r for r in rows}
    ids = list(by)
    for o in conn.execute(
        "SELECT user_card_id, option_key, choice_key, effective_from FROM user_card_options WHERE user_card_id = ANY(%s)",
        (ids,),
    ):
        pick = OptionPick(option=o["option_key"], choice=o["choice_key"], effective_from=o["effective_from"])
        by[str(o["user_card_id"])]["options"].append(pick)
    for f in conn.execute(
        "SELECT user_card_id, key, value, effective_from FROM user_card_facts WHERE user_card_id = ANY(%s)", (ids,)
    ):
        by[str(f["user_card_id"])]["fact_picks"].append(fact_pick(f))
    users = {r["user_id"] for r in rows}
    for f in conn.execute(
        "SELECT user_id, key, value, effective_from FROM user_facts WHERE user_id = ANY(%s)", (list(users),)
    ):
        for r in rows:
            if r["user_id"] == f["user_id"]:
                r["fact_picks"].append(fact_pick(f))
    return rows


def fact_pick(row: dict) -> FactPick:
    return FactPick(key=row["key"], value=json.loads(row["value"]), effective_from=row["effective_from"])


def at_day(rows: list[tuple[date, object]], day: date):
    """그날 쓰는 답. rows는 (바꾼 날, 답)이다. 없으면 None"""
    picks = [v for d, v in sorted(rows, key=lambda x: x[0]) if d <= day]
    return picks[-1] if picks else None
