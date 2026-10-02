"""모르는 값 답하기. 카드 사실, 옵션, 쓰기 시작한 날, 사람 사실. 작업 005 설계 5e, E56

처음 답은 원래 그랬던 것이라 그 카드의 모든 결제에 쓴다. 바꾼 답은 옵션이면 카탈로그 change대로 오늘이나 다음 달
1일부터, 사실이면 이번 달 1일부터다. 2026-10-02 사용자가 정했다.
"""

from __future__ import annotations

import json
from datetime import date

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict, StrictBool, StrictInt, StrictStr

from cherry_core.catalog.models import Fact, Option
from cherry_core.engine.cond import add_months, local, month_of

from ..answers import FIRST, at_day, attach_answers
from ..auth import User
from ..deps import Conn, today
from ..payments import load_payments, repriced_from
from .me import engine_card
from .payments import checked_id, my_cards
from .records import lock_cards, store

router = APIRouter(prefix="/me")
Value = StrictBool | StrictInt | StrictStr


class CardAnswers(BaseModel):
    # 모르는 칸은 422다. 작업 005 의도 성공 기준 6
    model_config = ConfigDict(extra="forbid")
    facts: dict[str, Value] = {}
    options: dict[str, StrictStr] = {}
    # 보낸 때만 바꾼다. null이면 지운다
    started_on: date | None = None


class UserAnswers(BaseModel):
    model_config = ConfigDict(extra="forbid")
    facts: dict[str, Value]


def checked_value(f: Fact, v: object) -> object:
    ok = (
        (f.type == "bool" and isinstance(v, bool))
        or (f.type == "month" and type(v) is int and 1 <= v <= 12)
        or (f.type == "choice" and isinstance(v, str) and v in (f.choices or []))
    )
    if not ok:
        raise HTTPException(422, f"{f.key}의 답이 종류에 맞지 않다")
    return v


def answer_fact(conn, table: str, owner_col: str, owner: str, key: str, value: object, day: date) -> date | None:
    """사실 답 하나를 적고 바꾼 날을 돌려준다. 그날 쓰는 답과 같으면 적지 않고 None이다

    table과 owner_col은 사용자 입력이 아니라 이 파일의 값이다
    """
    rows = [
        (r["effective_from"], json.loads(r["value"]))
        for r in conn.execute(
            f"SELECT effective_from, value FROM {table} WHERE {owner_col} = %s AND key = %s", (owner, key)
        )
    ]
    eff = month_of(day) if rows else FIRST
    before = at_day([x for x in rows if x[0] < eff], eff)
    later = [x for x in rows if x[0] >= eff]
    if not rows or before != value:
        conn.execute(
            f"INSERT INTO {table} ({owner_col}, key, effective_from, value) VALUES (%s, %s, %s, %s)"
            f" ON CONFLICT ({owner_col}, key, effective_from) DO UPDATE SET value = EXCLUDED.value, answered_at = now()",
            (owner, key, eff, json.dumps(value)),
        )
        return None if later and at_day(rows, eff) == value else eff
    if not later:
        return None
    # 이번 달에 바꾼 답을 그 전 답으로 되돌린다
    conn.execute(f"DELETE FROM {table} WHERE {owner_col} = %s AND key = %s AND effective_from >= %s", (owner, key, eff))
    return eff


def answer_option(conn, uid: str, o: Option, choice: str, day: date) -> date | None:
    """옵션 답 하나를 적고 바꾼 날을 돌려준다. 다시 계산할 것이 없으면 None이다

    새 답은 그날부터 뒤로 예약된 답을 지운다. 지금 쓰는 답을 다시 고르면 예약만 지운다. 처음 답이 카탈로그 기본값과
    같으면 엔진 계산이 같아 적기만 하고 다시 계산하지 않는다. E18
    """
    rows = [
        (r["effective_from"], r["choice_key"])
        for r in conn.execute(
            "SELECT effective_from, choice_key FROM user_card_options WHERE user_card_id = %s AND option_key = %s",
            (uid, o.key),
        )
    ]
    eff = (day if o.change == "immediate" else add_months(month_of(day), 1)) if rows else FIRST
    before = at_day([x for x in rows if x[0] < eff], eff) if rows else o.default
    later = [x for x in rows if x[0] >= eff]
    if before == choice and not later:
        if not rows:
            conn.execute(
                "INSERT INTO user_card_options (user_card_id, option_key, choice_key, effective_from)"
                " VALUES (%s, %s, %s, %s)",
                (uid, o.key, choice, eff),
            )
        return None
    conn.execute(
        "DELETE FROM user_card_options WHERE user_card_id = %s AND option_key = %s AND effective_from >= %s",
        (uid, o.key, eff),
    )
    if before != choice:
        conn.execute(
            "INSERT INTO user_card_options (user_card_id, option_key, choice_key, effective_from)"
            " VALUES (%s, %s, %s, %s)",
            (uid, o.key, choice, eff),
        )
    return eff


def reprice(conn, request: Request, ids: list[str], starts: list[date]) -> int:
    """답이 바뀐 카드의 결제를 처음 바뀌는 달부터 마지막 결제가 든 달까지 다시 계산한다. 혜택이 바뀐 결제 수. E56"""
    if not starts:
        return 0
    engine, now = request.app.state.engine, request.app.state.clock()
    rows = attach_answers(conn, conn.execute("SELECT * FROM user_cards WHERE id = ANY(%s)", (ids,)).fetchall())
    loaded = load_payments(conn, ids)
    changed = 0
    for r in rows:
        payments = loaded[str(r["id"])]
        if not payments:
            continue
        first = month_of(local(min(q.paid_at for q in payments)).date())
        start = max(month_of(min(starts)), first)
        res = repriced_from(engine, engine_card(r), payments, start, now)
        changed += store(conn, request, r["card_id"], res, {q.id: q for q in payments}, set(), now)
    return changed


@router.put("/cards/{uid}/answers")
def card_answers(uid: str, body: CardAnswers, request: Request, user: User, conn: Conn) -> dict:
    """카드 사실, 옵션, 쓰기 시작한 날을 답한다. 시안 보드 6의 카드 정보. 작업 004 설계 3.1"""
    uid = checked_id(uid)
    rows = lock_cards(conn, user, {uid})
    if uid not in rows or rows[uid]["removed_at"] is not None:
        raise HTTPException(404, "보유 카드가 아니다")
    row, day = rows[uid], today(request)
    found = request.app.state.engine.ctx.rules_on(row["card_id"], day)
    facts = {f.key: f for f in found[1].facts if f.scope == "card"} if found else {}
    options = {o.key: o for o in found[1].options} if found else {}
    for key, value in body.facts.items():
        if key not in facts:
            raise HTTPException(422, f"이 카드에 묻는 사실이 아니다: {key}")
        checked_value(facts[key], value)
    for key, choice in body.options.items():
        if key not in options or choice not in {c.key for c in options[key].choices}:
            raise HTTPException(422, f"이 카드의 옵션 선택지가 아니다: {key}")
    moved = "started_on" in body.model_fields_set and body.started_on != row["started_on"]
    if moved and body.started_on is not None and body.started_on > day:
        raise HTTPException(422, "쓰기 시작한 날이 오늘보다 뒤다")
    starts = [answer_fact(conn, "user_card_facts", "user_card_id", uid, k, v, day) for k, v in body.facts.items()]
    starts += [answer_option(conn, uid, options[k], c, day) for k, c in body.options.items()]
    if moved:
        # 쓰기 시작한 날은 카드 한 장에 하나라 바꾸면 모든 결제에 쓴다
        conn.execute("UPDATE user_cards SET started_on = %s WHERE id = %s", (body.started_on, uid))
        starts.append(FIRST)
    return {"repriced": reprice(conn, request, [uid], [s for s in starts if s is not None])}


def user_fact_defs(request: Request, rows: list[dict]) -> dict[str, tuple[Fact, list[dict]]]:
    """가진 카드들의 사람 사실과 그 사실을 쓰는 카드. 오늘의 개정을 본다"""
    engine, day = request.app.state.engine, today(request)
    out: dict[str, tuple[Fact, list[dict]]] = {}
    for r in rows:
        found = engine.ctx.rules_on(r["card_id"], day)
        for f in found[1].facts if found else []:
            if f.scope == "user":
                out.setdefault(f.key, (f, []))[1].append(r)
    return out


@router.get("/facts")
def user_facts(request: Request, user: User, conn: Conn) -> list[dict]:
    """설정의 혜택 계산에 쓰는 답. 시안 보드 9"""
    defs = user_fact_defs(request, my_cards(conn, user))
    rows = conn.execute("SELECT key, effective_from, value FROM user_facts WHERE user_id = %s", (user,)).fetchall()
    day = today(request)
    return [
        {
            "key": key,
            "type": f.type,
            "ask": f.ask,
            "choices": f.choices,
            "answer": at_day([(r["effective_from"], json.loads(r["value"])) for r in rows if r["key"] == key], day),
            "cards": [c["name"] for c in cards],
        }
        for key, (f, cards) in sorted(defs.items())
    ]


@router.put("/facts")
def put_user_facts(body: UserAnswers, request: Request, user: User, conn: Conn) -> dict:
    """사람 사실을 답한다. 그 사실을 쓰는 카드를 모두 다시 계산한다"""
    defs = user_fact_defs(request, my_cards(conn, user))
    for key, value in body.facts.items():
        if key not in defs:
            raise HTTPException(422, f"가진 카드가 묻는 사람 사실이 아니다: {key}")
        checked_value(defs[key][0], value)
    # 해지한 카드도 그 사실을 쓰면 다시 계산한다. 엔진은 해지한 카드에도 사람 사실을 넣는다. E56
    every = conn.execute(
        "SELECT uc.*, c.name FROM user_cards uc JOIN cards c ON c.id = uc.card_id WHERE uc.user_id = %s", (user,)
    ).fetchall()
    using = user_fact_defs(request, every)
    ids = {str(c["id"]) for key in body.facts for c in using.get(key, (None, []))[1]}
    lock_cards(conn, user, ids)
    day = today(request)
    starts = [answer_fact(conn, "user_facts", "user_id", user, k, v, day) for k, v in body.facts.items()]
    return {"repriced": reprice(conn, request, sorted(ids), [s for s in starts if s is not None])}
