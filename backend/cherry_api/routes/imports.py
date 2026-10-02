"""이용 내역 엑셀 가져오기. 미리보기, 저장, 목록, 되돌리기. 작업 005 설계 5f, 설계 문서 8절. S11, E30~E35, E51, E57"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta

import psycopg
from fastapi import APIRouter, HTTPException, Request
from fastapi.concurrency import run_in_threadpool
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, ValidationError, field_validator

from cherry_core.engine.cond import KST, local, month_of

from ..auth import User, current_user
from ..deps import Conn
from ..imports import Unreadable, approval_key, find_header, parse_rows, read_table, signature, top_row, top_rows
from ..payments import load_payments, match_merchant, new_id, ranked_past, repriced_from
from .catalog import MAX_SPEND
from .me import engine_card
from .payments import PaymentFields, checked_id, filled, my_cards, payment_of
from .records import lock_cards, revision_for, store

router = APIRouter(prefix="/me/imports")
MAX_BYTES = 2_000_000
NOON = time(12, 0)
# 직접 넣은 결제와 파일의 행이 같은 결제로 보이는 시각 차이. 결제 알림의 겹침과 같다. 2026-10-02 사용자가 정했다. E31
NEAR = timedelta(minutes=10)
OLDEST = timedelta(days=365 * 5)


class ImportRow(BaseModel):
    """미리보기의 행. 저장할 때 앱이 판정받은 행을 모두 돌려보낸다. 서버가 같은 행으로 다시 판정한다"""

    model_config = ConfigDict(extra="ignore")
    user_card_id: str
    paid_at: AwareDatetime
    # 파일에 시각이 있었는가. 없으면 그날 12시이고 시각 조건은 모름이다. E57
    timed: bool
    merchant_name: str = Field(min_length=1, max_length=100)
    amount: int = Field(strict=True, gt=0, le=MAX_SPEND)
    installment_months: int = Field(strict=True, ge=1, le=36)
    interest_free: bool = False
    overseas: bool = False
    approval_no: str | None = Field(default=None, max_length=40)
    cancel: bool

    @field_validator("approval_no")
    @classmethod
    def _blank(cls, v: str | None) -> str | None:
        return (v.strip() or None) if v is not None else None


class Mapping(BaseModel):
    model_config = ConfigDict(extra="forbid")
    signature: str = Field(pattern=r"^[0-9a-f]{64}$")
    columns: dict[str, int]


class SaveBody(BaseModel):
    model_config = ConfigDict(extra="forbid")
    # 겹친 행과 넣지 않는 취소 행도 보낸다. 미리보기에서 짝을 차지한 행이 빠지면 다시 판정이 달라진다
    rows: list[ImportRow] = Field(min_length=1, max_length=3000)
    # 사용자가 짝지은 열. 저장할 때 남겨 같은 모양의 다음 파일에 쓴다. 미리보기만 보고 그만두면 남기지 않는다. E30
    mapping: Mapping | None = None


@dataclass
class Pay:
    """판정에 쓰는 결제. 이미 있는 결제와 이번 파일의 새 결제다"""

    id: str
    user_card_id: str
    paid_at: datetime
    timed: bool
    amount: int
    merchant: str
    key: str | None
    approval: str | None
    cancelled_amount: int = 0
    cancelled_at: datetime | None = None
    saved: bool = False
    # 이 결제에 가져오기가 붙인 취소. (날짜, 금액)이다. 되돌린 묶음의 것은 뺀다
    imported: list[tuple[date, int]] = field(default_factory=list)
    taken: set[int] = field(default_factory=set)
    used: bool = False

    @property
    def manual_cancel(self) -> bool:
        """앱에서 적은 취소가 있는가. 결제의 취소액이 가져오기가 붙인 취소의 합보다 크면 그렇다"""
        return self.cancelled_amount > sum(a for _, a in self.imported)


def norm(name: str) -> str:
    return re.sub(r"\s", "", name).lower()


def same_merchant(a: Pay, name: str, key: str | None) -> bool:
    """가맹점명이 같거나 한쪽이 다른 쪽을 담거나 같은 가맹점으로 알아보면 같다. E31"""
    b = norm(name)
    if a.merchant == b or (a.key is not None and a.key == key):
        return True
    return min(len(a.merchant), len(b)) >= 2 and (a.merchant in b or b in a.merchant)


def near(a: Pay, r: ImportRow) -> bool:
    if a.timed and r.timed:
        return abs(a.paid_at - r.paid_at) <= NEAR
    return local(a.paid_at).date() == local(r.paid_at).date()


def before(a: Pay, r: ImportRow) -> bool:
    if a.timed and r.timed:
        return a.paid_at <= r.paid_at
    return local(a.paid_at).date() <= local(r.paid_at).date()


def method_of(catalog, merchant: str) -> tuple[str, str]:
    """(결제수단, 가게 이름). 가맹점명이 간편결제 이름으로 시작하면 그 결제수단이고 가게는 나머지로 찾는다. 아니면
    실물카드다. 2026-10-02 사용자가 정했다. 작업 001 설계 3절"""
    text = merchant.strip()
    for key, m in catalog.payment_methods.items():
        for name in m.statement_names:
            if norm(text).startswith(norm(name)):
                rest = text[len(name) :] if text.lower().startswith(name.lower()) else text
                return key, rest.strip(" ()*_-") or text
    return "physical_card", text


def plan(conn, request: Request, cards: dict[str, dict], rows: list[ImportRow], now: datetime) -> list[dict]:
    """행마다 new, duplicate, cancel, orphan을 정한다. 같은 날의 결제를 그날의 취소보다 먼저 본다. E31, E32"""
    catalog, aliases = request.app.state.catalog, request.app.state.aliases
    pool: list[Pay] = []
    by_id: dict[str, Pay] = {}
    for r in conn.execute(
        "SELECT id, user_card_id, paid_at, time_known, amount, merchant_name, merchant_key, approval_no,"
        " cancelled_amount, cancelled_at FROM transactions WHERE user_card_id = ANY(%s) AND deleted_at IS NULL"
        " ORDER BY paid_at, id",
        (list(cards),),
    ):
        p = Pay(
            id=str(r["id"]),
            user_card_id=str(r["user_card_id"]),
            paid_at=r["paid_at"],
            timed=r["time_known"],
            amount=r["amount"],
            merchant=norm(r["merchant_name"] or ""),
            key=r["merchant_key"],
            approval=approval_key(r["approval_no"]),
            cancelled_amount=r["cancelled_amount"],
            cancelled_at=r["cancelled_at"],
            saved=True,
        )
        pool.append(p)
        by_id[p.id] = p
    for c in conn.execute(
        "SELECT c.transaction_id, c.amount, c.cancelled_at FROM import_cancels c"
        " JOIN import_batches b ON b.id = c.import_batch_id WHERE b.undone_at IS NULL AND c.transaction_id = ANY(%s)",
        (list(by_id),),
    ):
        by_id[str(c["transaction_id"])].imported.append((local(c["cancelled_at"]).date(), c["amount"]))
    engine = request.app.state.engine

    def ranked_unknown(p: Pay) -> bool:
        """취소 달 칸이 빈 순위 카드의 지나간 달 결제인가. 취소 경로처럼 순위를 다시 매기지 않으려 붙이지 않는다. E55"""
        card = engine_card(cards[p.user_card_id])
        found = engine.ctx.rules_on(card.card_id, local(p.paid_at).date())
        unknown = found is not None and any(g.cancellation is None for g in found[1].ranked)
        return unknown and ranked_past(engine, card, month_of(local(p.paid_at).date()), now)

    out: list[dict] = [{} for _ in rows]
    # 한쪽 시각을 모르면 12시라 시각 순서가 틀릴 수 있어 날짜, 결제와 취소, 시각 순서로 본다. E57
    order = sorted(range(len(rows)), key=lambda i: (local(rows[i].paid_at).date(), rows[i].cancel, rows[i].paid_at))
    for i in order:
        r = rows[i]
        key = match_merchant(aliases, method_of(catalog, r.merchant_name)[1])
        same_card = [p for p in pool if p.user_card_id == r.user_card_id]
        if r.cancel:
            out[i] = cancel_of(r, key, same_card, ranked_unknown)
            continue
        ap = approval_key(r.approval_no)
        # 이미 있는 결제 하나는 파일의 한 행만 겹친다. 파일 안의 똑같은 두 행은 두 결제다
        # 가장 맞는 결제와 짝짓는다. 승인번호나 가맹점이 같은 것, 그다음 시각이 가까운 것이다
        hit = min(
            (p for p in same_card if p.saved and not p.used and duplicate(p, r, key)),
            key=lambda p: (not ((ap and p.approval == ap) or (key and p.key == key)), abs(p.paid_at - r.paid_at)),
            default=None,
        )
        if hit is not None:
            hit.used = True
            out[i] = {"status": "duplicate"}
            continue
        # 새 행끼리 승인번호가 같으면 같은 결제다. 승인 줄과 매입 줄, 달마다 찍힌 할부 줄이 그렇다
        if ap and any(not p.saved and p.approval == ap for p in same_card):
            out[i] = {"status": "duplicate"}
            continue
        p = Pay(new_id(), r.user_card_id, r.paid_at, r.timed, r.amount, norm(r.merchant_name), key, ap)
        pool.append(p)
        out[i] = {"status": "new", "id": p.id}
    return out


def duplicate(p: Pay, r: ImportRow, key: str | None) -> bool:
    """겹침. 승인번호가 둘 다 있으면 그것만 본다. 없으면 같은 금액, 가까운 시각, 같은 가맹점이다. E31"""
    ap = approval_key(r.approval_no)
    if p.approval and ap:
        return p.approval == ap
    return p.amount == r.amount and near(p, r) and same_merchant(p, r.merchant_name, key)


def cancel_of(r: ImportRow, key: str | None, same_card: list[Pay], ranked_unknown) -> dict:
    """취소 행을 앞선 원 결제에 붙인다. E32, E5"""
    earlier = sorted((p for p in same_card if before(p, r)), key=lambda p: p.paid_at)
    ap = approval_key(r.approval_no)
    found = [p for p in earlier if ap and p.approval == ap]
    if not found:
        # 승인번호가 같은 결제가 없으면 가맹점과 금액으로 찾는다. 직접 넣은 결제에는 승인번호가 없다
        found = [p for p in earlier if same_merchant(p, r.merchant_name, key) and p.amount >= r.amount]
    if not found:
        return {"status": "orphan", "reason": "원 결제를 찾지 못했어요"}
    day = local(r.paid_at).date()
    # 같은 파일을 다시 올렸으면 가져오기가 이미 붙인 같은 날 같은 금액의 취소다
    for p in reversed(found):
        j = next((j for j, (d, a) in enumerate(p.imported) if d == day and a == r.amount and j not in p.taken), None)
        if j is not None:
            p.taken.add(j)
            return {"status": "duplicate"}
    fit = [p for p in found if p.amount - p.cancelled_amount >= r.amount]
    if not fit:
        return {"status": "orphan", "reason": "결제 금액보다 많이 취소됐어요"}
    p = fit[-1]
    if p.saved and p.manual_cancel:
        return {"status": "orphan", "reason": "앱에서 적은 취소가 있어 겹치는지 몰라요. 기록에서 확인해 주세요"}
    if p.cancelled_at is not None and month_of(local(p.cancelled_at).date()) != month_of(day):
        # 취소 시각은 결제마다 하나라 다른 달의 추가 취소는 담지 못한다. 설계 문서 6.5
        return {"status": "orphan", "reason": "다른 달에 더 취소된 금액은 아직 담지 못해요"}
    if p.saved and ranked_unknown(p):
        return {"status": "orphan", "reason": "이 카드는 순위 혜택의 취소 달을 몰라요. 기록에서 직접 적어 주세요"}
    p.cancelled_amount += r.amount
    # 취소는 결제보다 앞서지 않는다. 한쪽 시각을 모르면 12시라 결제보다 앞설 수 있다
    at = max(r.paid_at, p.paid_at)
    p.cancelled_at = max(p.cancelled_at, at) if p.cancelled_at else at
    return {"status": "cancel", "target": p.id}


def card_of(cards: dict[str, dict], catalog, name: str | None) -> str | None:
    """카드 이름 열을 보유 카드와 맞춘다. 이름이 같은 카드가 먼저고, 없으면 파일 이름이 카드 이름을 담는 카드가 한 장일
    때만이다. 괄호 안의 카드번호 끝자리와 상품 구분은 뺀다. E33"""
    if name is None:
        return None

    def bare(n: str) -> str:
        return norm(re.sub(r"\(.*?\)", "", n))

    wanted = bare(name)
    names = {
        uid: [bare(n) for n in [catalog.cards[r["card_id"]].card.name, *catalog.cards[r["card_id"]].card.search_names]]
        for uid, r in cards.items()
    }
    exact = [uid for uid, ns in names.items() if wanted in ns]
    if exact:
        return exact[0]
    part = [uid for uid, ns in names.items() if any(len(n) >= 4 and n in wanted for n in ns)]
    return part[0] if len(part) == 1 else None


def _auth(request: Request) -> str:
    with request.app.state.pool.connection() as conn:
        return str(current_user(request, conn))


@router.post("/preview")
async def preview(request: Request, user_card_id: str | None = None, mapping: str | None = None) -> dict:
    """파일을 읽어 미리보기를 준다. 파일은 메모리에서 읽고 바로 버린다. E35

    로그인은 짧게 확인하고 연결을 놓는다. 몸통을 다 받은 뒤 연결을 다시 잡는다. 느린 업로드가 연결 풀을 붙잡지 않게 한다.
    읽기와 판정은 다른 요청을 막지 않게 따로 돈다
    """
    user = await run_in_threadpool(_auth, request)
    length = request.headers.get("content-length", "")
    if length.isdigit() and int(length) > MAX_BYTES:
        raise HTTPException(413, "파일이 2MB보다 커요. 기간을 나눠 올려 주세요")
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > MAX_BYTES:
            raise HTTPException(413, "파일이 2MB보다 커요. 기간을 나눠 올려 주세요")
        chunks.append(chunk)
    return await run_in_threadpool(_preview_in, request, user, b"".join(chunks), user_card_id, mapping)


def _preview_in(request: Request, user: str, data: bytes, user_card_id: str | None, mapping: str | None) -> dict:
    with request.app.state.pool.connection() as conn:
        return _preview(request, user, conn, data, user_card_id, mapping)


def _preview(request: Request, user: str, conn, data: bytes, user_card_id: str | None, mapping: str | None) -> dict:
    try:
        table = read_table(data, "")
        picked = json.loads(mapping) if mapping else None
        if picked is not None and not isinstance(picked, dict):
            raise Unreadable("열 짝이 맞지 않아요")
        start, cols = (None, None) if picked is None else find_header(table, picked)
    except (Unreadable, ValueError) as e:
        raise HTTPException(422, str(e) if isinstance(e, Unreadable) else "열 짝이 맞지 않아요") from None
    del data
    if picked is None:
        saved = {
            r["signature"]: r["mapping"]
            for r in conn.execute("SELECT signature, mapping FROM import_mappings WHERE user_id = %s", (user,))
        }
        # 사용자가 짝지은 열을 자동으로 찾은 열보다 먼저 쓴다. 자동이 틀려 고친 짝이 다음에도 쓰인다. E30
        for i, row in enumerate(table[:20]):
            if signature(row, user) in saved:
                try:
                    start, cols = find_header(table, {"row": i, "columns": saved[signature(row, user)]})
                except Unreadable:
                    start, cols = None, None
                break
        if start is None:
            start, cols = find_header(table)
    if start is None or cols is None:
        top = top_row(table) if table else 0
        return {
            "needs_mapping": True,
            "header_row": top,
            "headers": [str(c or "").strip() for c in table[top]] if table else [],
            "mapping": None,
            "signature": signature(table[top], user) if table else None,
            "top_rows": top_rows(table),
            "rows": [],
            "summary": None,
        }
    cards = {str(r["id"]): r for r in my_cards(conn, user)}
    chosen = checked_id(user_card_id) if user_card_id else None
    if chosen is not None and chosen not in cards:
        raise HTTPException(404, "보유 카드가 아니다")
    if "card" not in cols and chosen is None:
        raise HTTPException(422, "어느 카드의 내역인지 골라 주세요")
    catalog, now = request.app.state.catalog, request.app.state.clock()
    shown: list[dict] = []
    rows: list[ImportRow] = []
    for p in parse_rows(table, start, cols):
        base = {
            "line": p.line,
            "merchant_name": p.merchant,
            "amount": p.amount,
            "cancel": p.cancel,
            "user_card_id": None,
        }
        at = datetime.combine(p.day, p.at or NOON, KST) if p.day else None
        if p.error is None and at is not None and at > now + timedelta(days=1):
            p.error = "지금보다 뒤의 결제예요"
        if p.error is None and at is not None and at < now - OLDEST:
            p.error = "5년보다 오래된 결제예요"
        if p.error:
            shown.append(base | {"status": "error", "reason": p.error})
            continue
        # 고른 카드가 있으면 그 카드다. 없으면 카드 이름 열로 나눈다. E33
        uid = chosen or card_of(cards, catalog, p.card)
        if uid is None:
            shown.append(base | {"status": "skipped", "reason": "보유 카드가 아니에요"})
            continue
        try:
            row = ImportRow(
                user_card_id=uid,
                paid_at=at,
                timed=p.at is not None,
                merchant_name=p.merchant[:100],
                amount=p.amount,
                installment_months=p.installment_months,
                interest_free=bool(p.interest_free),
                overseas=p.overseas,
                approval_no=p.approval_no,
                cancel=p.cancel,
            )
        except ValidationError:
            shown.append(base | {"status": "error", "reason": "금액이나 할부를 읽지 못했어요"})
            continue
        rows.append(row)
        extra = {"interest_unknown": p.interest_free is None, "payment_method": method_of(catalog, p.merchant)[0]}
        shown.append(base | row.model_dump(mode="json") | extra)
    judged = iter(plan(conn, request, cards, rows, now))
    aliases, merchants, names = request.app.state.aliases, catalog.merchants, request.app.state.category_names
    for s in shown:
        if "paid_at" not in s:
            continue
        s |= {k: v for k, v in next(judged).items() if k in ("status", "reason")}
        key = match_merchant(aliases, method_of(catalog, s["merchant_name"])[1])
        s["category_name"] = names.get(merchants[key].category) if key else None
        s["card_name"] = cards[s["user_card_id"]]["name"]
    new = [s for s in shown if s["status"] == "new"]
    count = {k: sum(s["status"] == k for s in shown) for k in ("duplicate", "cancel", "orphan", "skipped", "error")}
    return {
        "needs_mapping": False,
        "header_row": start,
        "headers": [str(c or "").strip() for c in table[start]],
        "mapping": cols,
        "signature": signature(table[start], user),
        "top_rows": top_rows(table),
        "rows": shown,
        "summary": {
            "rows": len(shown),
            "new": len(new),
            "amount": sum(s["amount"] for s in new),
            "duplicates": count["duplicate"],
            "cancels": count["cancel"],
            "orphans": count["orphan"],
            "skipped": count["skipped"],
            "errors": count["error"],
            "uncategorized": sum(s["category_name"] is None for s in new),
            # 무이자인지 모르는 할부. 유이자로 넣는다. 2026-10-02 사용자가 정했다
            "interest_unknown": sum(s["interest_unknown"] for s in new),
            # 가맹점명으로 알아본 간편결제. 나머지는 실물카드다
            "easy_pay": sum(s["payment_method"] != "physical_card" for s in new),
            "untimed": sum(not s["timed"] for s in new),
        },
    }


@router.post("", status_code=201)
def save(body: SaveBody, request: Request, user: User, conn: Conn) -> dict:
    """미리보기의 행을 저장한다. 서버가 겹침과 취소를 다시 판정한다. 가져온 결제가 든 가장 앞 달부터 다시 계산한다. E51"""
    now, engine, catalog = request.app.state.clock(), request.app.state.engine, request.app.state.catalog
    if any(r.paid_at > now + timedelta(days=1) or r.paid_at < now - OLDEST for r in body.rows):
        raise HTTPException(422, "지금보다 뒤이거나 5년보다 오래된 결제가 있다")
    rows = [r.model_copy(update={"user_card_id": checked_id(r.user_card_id)}) for r in body.rows]
    ids = {r.user_card_id for r in rows}
    cards = lock_cards(conn, user, ids)
    if any(i not in cards or cards[i]["removed_at"] is not None for i in ids):
        raise HTTPException(404, "보유 카드가 아니다")
    judged = plan(conn, request, cards, rows, now)
    batch = conn.execute(
        "INSERT INTO import_batches (user_id, row_count, imported_count, duplicate_count, cancel_count)"
        " VALUES (%s, %s, 0, 0, 0) RETURNING id",
        (user, len(rows)),
    ).fetchone()["id"]
    loaded = load_payments(conn, sorted(ids))
    new: dict[str, ImportRow] = {}
    cancels: dict[str, list[ImportRow]] = {}
    for r, j in zip(rows, judged, strict=True):
        if j["status"] == "new":
            new[j["id"]] = r
        elif j["status"] == "cancel":
            cancels.setdefault(j["target"], []).append(r)
    payments: dict[str, list] = {uid: [] for uid in ids}
    starts: dict[str, list[date]] = {uid: [] for uid in ids}
    for pid, r in new.items():
        method, shop = method_of(catalog, r.merchant_name)
        # 가게는 간편결제 이름을 뺀 나머지로 찾는다. 기록에는 파일의 가맹점명을 그대로 둔다
        fields = PaymentFields(
            merchant_name=shop,
            paid_at=r.paid_at,
            installment_months=r.installment_months,
            interest_free=r.interest_free and r.installment_months > 1,
            region="overseas" if r.overseas else "domestic",
            payment_method=method,
        )
        p = payment_of(cards[r.user_card_id], fields, r.amount, filled(request, fields), pid)
        payments[r.user_card_id].append(p.model_copy(update={"time_known": r.timed}))
        starts[r.user_card_id].append(month_of(local(p.paid_at).date()))
    for uid in ids:
        payments[uid] = [*loaded[uid], *payments[uid]]
        for k, q in enumerate(payments[uid]):
            if q.id in cancels:
                lines = cancels[q.id]
                # 취소는 결제보다 앞서지 않는다
                at = max([q.paid_at, *(r.paid_at for r in lines)] + ([q.cancelled_at] if q.cancelled_at else []))
                payments[uid][k] = q.model_copy(
                    update={"cancelled_amount": q.cancelled_amount + sum(r.amount for r in lines), "cancelled_at": at}
                )
                starts[uid].append(month_of(local(q.paid_at).date()))
    by_id = {q.id: q for ps in payments.values() for q in ps}
    try:
        _insert(conn, request, user, batch, cards, new, by_id, now)
    except psycopg.errors.UniqueViolation:
        # 판정은 같은 승인번호를 겹침으로 보지만 다른 요청과 겹치면 여기서 막힌다
        raise HTTPException(409, "같은 승인번호의 결제가 이미 있다. 다시 미리보기 해 주세요") from None
    for target, lines in cancels.items():
        q = by_id[target]
        if target not in new:
            # 지금 카탈로그로 다시 계산하니 개정 연결도 결제일의 지금 개정으로 맞춘다. 위험 검토 12번
            revision = revision_for(request, cards[q.user_card_id]["card_id"], q.paid_at)
            conn.execute(
                "UPDATE transactions SET cancelled_amount = %s, cancelled_at = %s, card_revision_id = %s,"
                " updated_at = %s WHERE id = %s",
                (q.cancelled_amount, q.cancelled_at, revision, now, target),
            )
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO import_cancels (import_batch_id, transaction_id, amount, cancelled_at)"
                " VALUES (%s, %s, %s, %s)",
                [(batch, target, r.amount, max(r.paid_at, q.paid_at)) for r in lines],
            )
    repriced = 0
    for uid in ids:
        if not starts[uid]:
            continue
        res = repriced_from(engine, engine_card(cards[uid]), payments[uid], min(starts[uid]), now)
        before_ = {q.id: q for q in loaded[uid]}
        always = {q.id for q in payments[uid] if q.id in new or q.id in cancels}
        repriced += store(conn, request, cards[uid]["card_id"], res, before_, always, now)
    counts = {
        "imported": len(new),
        "duplicates": sum(j["status"] == "duplicate" for j in judged),
        "cancels": sum(len(v) for v in cancels.values()),
        "orphans": sum(j["status"] == "orphan" for j in judged),
    }
    conn.execute(
        "UPDATE import_batches SET imported_count = %s, duplicate_count = %s, cancel_count = %s WHERE id = %s",
        (counts["imported"], counts["duplicates"], counts["cancels"], batch),
    )
    if body.mapping is not None:
        conn.execute(
            "INSERT INTO import_mappings (user_id, signature, mapping) VALUES (%s, %s, %s)"
            " ON CONFLICT (user_id, signature) DO UPDATE SET mapping = EXCLUDED.mapping, updated_at = now()",
            (user, body.mapping.signature, json.dumps(body.mapping.columns)),
        )
    return {"id": batch, **counts, "repriced": repriced}


def _insert(conn, request: Request, user: str, batch: int, cards: dict, new: dict, by_id: dict, now: datetime) -> None:
    """가져온 새 결제를 넣는다. 시각을 아는지, 승인번호, 묶음을 함께 적는다"""
    for pid, r in new.items():
        q, card_id = by_id[pid], cards[r.user_card_id]["card_id"]
        conn.execute(
            """
            INSERT INTO transactions (id, user_id, user_card_id, amount, merchant_name, merchant_key, category_code,
                                      paid_at, time_known, installment_months, interest_free_installment, channel,
                                      region, payment_method, billing, card_revision_id, approval_no, import_batch_id,
                                      cancelled_amount, cancelled_at, source, created_at, updated_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'excel', %s, %s)
            """,
            (
                pid,
                user,
                r.user_card_id,
                q.amount,
                r.merchant_name,
                q.merchant,
                q.category,
                q.paid_at,
                q.time_known,
                q.installment_months,
                q.interest_free,
                q.channel,
                q.region,
                q.payment_method,
                q.billing,
                revision_for(request, card_id, q.paid_at),
                r.approval_no,
                batch,
                q.cancelled_amount,
                q.cancelled_at,
                now,
                now,
            ),
        )


@router.get("")
def batches(user: User, conn: Conn) -> list[dict]:
    rows = conn.execute(
        "SELECT id, row_count, imported_count, duplicate_count, cancel_count, created_at, undone_at"
        " FROM import_batches WHERE user_id = %s ORDER BY id DESC",
        (user,),
    ).fetchall()
    return [
        r
        | {
            "created_at": r["created_at"].isoformat(),
            "undone_at": r["undone_at"].isoformat() if r["undone_at"] else None,
        }
        for r in rows
    ]


@router.delete("/{bid}")
def undo(bid: int, request: Request, user: User, conn: Conn) -> dict:
    """묶음 되돌리기. 가져온 결제를 지우고 이 묶음이 붙인 취소만 뺀 뒤 다시 계산한다. 다른 묶음의 취소는 남는다. E34"""
    batch = conn.execute(
        "SELECT id FROM import_batches WHERE id = %s AND user_id = %s AND undone_at IS NULL FOR UPDATE", (bid, user)
    ).fetchone()
    if batch is None:
        raise HTTPException(404, "가져온 묶음이 아니다")
    ids = {
        str(r["user_card_id"])
        for r in conn.execute(
            "SELECT user_card_id FROM transactions WHERE import_batch_id = %s"
            " UNION SELECT t.user_card_id FROM import_cancels c JOIN transactions t ON t.id = c.transaction_id"
            " WHERE c.import_batch_id = %s",
            (bid, bid),
        )
    }
    cards = lock_cards(conn, user, ids) if ids else {}
    now, engine = request.app.state.clock(), request.app.state.engine
    loaded = load_payments(conn, sorted(ids))
    gone = {q.id for ps in loaded.values() for q in ps} & {
        str(r["id"])
        for r in conn.execute("SELECT id FROM transactions WHERE import_batch_id = %s AND deleted_at IS NULL", (bid,))
    }
    mine: dict[str, int] = {}
    for c in conn.execute("SELECT transaction_id, amount FROM import_cancels WHERE import_batch_id = %s", (bid,)):
        mine[str(c["transaction_id"])] = mine.get(str(c["transaction_id"]), 0) + c["amount"]
    others: dict[str, tuple[datetime, int]] = {}
    for c in conn.execute(
        "SELECT c.transaction_id, max(c.cancelled_at) AS at, sum(c.amount) AS amount FROM import_cancels c"
        " JOIN import_batches b ON b.id = c.import_batch_id"
        " WHERE b.undone_at IS NULL AND b.id <> %s AND c.transaction_id = ANY(%s) GROUP BY c.transaction_id",
        (bid, list(mine)),
    ):
        others[str(c["transaction_id"])] = (c["at"], c["amount"])
    conn.execute(
        "UPDATE transactions SET deleted_at = %s, updated_at = %s WHERE import_batch_id = %s AND deleted_at IS NULL",
        (now, now, bid),
    )
    conn.execute("UPDATE import_batches SET undone_at = %s WHERE id = %s", (now, bid))
    repriced = 0
    for uid in ids:
        payments, months, back = [], [], set()
        for q in loaded[uid]:
            if q.id in gone:
                months.append(month_of(local(q.paid_at).date()))
                continue
            if q.id in mine:
                amount = max(q.cancelled_amount - mine[q.id], 0)
                other_at, other_amount = others.get(q.id, (None, 0))
                # 남은 취소가 다른 묶음의 것뿐이면 그 가운데 가장 늦은 시각이다. 앱에서 적은 취소가 남으면 지금 시각을 둔다
                at = None if not amount else other_at if other_at and amount <= other_amount else q.cancelled_at
                q = q.model_copy(update={"cancelled_amount": amount, "cancelled_at": at})
                conn.execute(
                    "UPDATE transactions SET cancelled_amount = %s, cancelled_at = %s, card_revision_id = %s,"
                    " updated_at = %s WHERE id = %s",
                    (amount, at, revision_for(request, cards[uid]["card_id"], q.paid_at), now, q.id),
                )
                months.append(month_of(local(q.paid_at).date()))
                back.add(q.id)
            payments.append(q)
        if not months:
            continue
        res = repriced_from(engine, engine_card(cards[uid]), payments, min(months), now)
        repriced += store(conn, request, cards[uid]["card_id"], res, {q.id: q for q in loaded[uid]}, back, now)
    return {"id": bid, "repriced": repriced}
