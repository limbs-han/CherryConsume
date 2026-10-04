"""색인 단계 pipeline/src/index.py의 판단. Spark 없이 테스트한다. 작업 008 계획 4.6.

묶음 고르기, 판매 중 카드가 한꺼번에 사라지는 것을 막는 안전장치, card_id 정하기다.
"""

from __future__ import annotations

import hashlib
import re
from collections.abc import Iterable
from dataclasses import dataclass, field
from typing import Any

# 지난번 판매 중 카드 가운데 이만큼 넘게 판매 중에서 빠지면 읽기가 깨진 것으로 보고 쓰지 않는다
MAX_DROP = 0.5


def pick_batches(
    fetches: Iterable[Any], done: dict[str, Any], parsed: set[str]
) -> tuple[dict[str, list[Any]], list[str]]:
    """({카드사: 마지막 묶음의 목록 파일 줄}, 아직 글 뽑기 전이라 미룬 카드사).

    fetches는 bronze.fetches의 공시 줄이고 issuer, path, fetched_at이 있다. 수집기는 한 카드사의 공시를 다 받았을 때만
    같은 받은 시각으로 저장하므로 그 시각의 줄 전부가 한 묶음이다. documents는 같은 날 같은 내용의 경로를 다시 넣지 않아
    documents로 고르면 같은 날 두 번째 묶음이 일부만 잡힌다. 그래서 목록 파일 줄로 고른다.
    done은 카드사마다 색인에 넣은 마지막 묶음의 받은 시각이다. 그보다 늦은 묶음만 고른다.
    묶음의 경로가 하나라도 documents에 없으면 원문이 아직 안 올라온 것이라 다음 실행으로 미룬다.
    """
    latest: dict[str, Any] = {}
    rows = list(fetches)
    for r in rows:
        if r.issuer not in latest or r.fetched_at > latest[r.issuer]:
            latest[r.issuer] = r.fetched_at
    batches: dict[str, list[Any]] = {}
    waiting = []
    for issuer, at in sorted(latest.items()):
        if done.get(issuer) is not None and at <= done[issuer]:
            continue
        batch = sorted(
            {r.path: r for r in rows if r.issuer == issuer and r.fetched_at == at}.values(), key=lambda r: r.path
        )
        if any(r.path not in parsed for r in batch):
            waiting.append(issuer)
        else:
            batches[issuer] = batch
    return batches, waiting


def too_many_dropped(previous_on_sale: set[str], now_on_sale: set[str]) -> str | None:
    """지난번 판매 중 열쇠 가운데 절반 넘게 이번 판매 중에서 빠지면 까닭을 돌려준다. 읽기가 깨졌을 때 단종 오판을 막는다.

    판매 상태를 잘못 읽어도 행 수는 그대로일 수 있어 행 수가 아니라 판매 중 열쇠를 비교한다. KB 9999.12.31 같은 경우다.
    """
    if not previous_on_sale:
        return None
    dropped = len(previous_on_sale - now_on_sale)
    if dropped > len(previous_on_sale) * MAX_DROP:
        return f"지난번 판매 중 {len(previous_on_sale)}장 가운데 {dropped}장이 판매 중에서 빠진다"
    return None


@dataclass
class Settled:
    ids: list[str]  # 묶음 행마다 쓸 card_id
    moves: dict[str, str] = field(default_factory=dict)  # 묶음에 없는 기존 열쇠의 새 card_id
    notes: list[str] = field(default_factory=list)  # 사람이 볼 것


def key_id(issuer: str, key: str) -> str:
    """열쇠로 만든 id. 묶음에 없는 행에 새 id를 줄 때 쓴다. card_ids가 만드는 id와 같은 꼴이다."""
    kind, _, value = key.partition(":")
    if kind == "name":
        return f"{issuer}-n" + hashlib.sha1(value.encode()).hexdigest()[:10]
    return f"{issuer}-" + (re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "x")


def settle_ids(
    issuer: str,
    rows: list[tuple[str, str, bool, str, bool]],
    existing: dict[str, tuple[str, bool]],
    catalog_ids: set[str],
) -> Settled:
    """묶음 행과 색인에 있는 행의 card_id를 정한다.

    rows는 묶음 행마다 (열쇠, card_ids의 id, 카탈로그 짝인지, 카탈로그 없이 만든 id, 판매 중인지)이고,
    existing은 그 카드사 색인의 {열쇠: (card_id, 판매 중인지)}다.

    - 색인에 이미 있는 행은 id를 지킨다. 사람이 정한 id를 다음 실행이 덮지 않게 한다.
    - 만든 id를 가진 행이 카탈로그 카드와 짝지어지면 카탈로그 id로 바꾼다. 승인으로 새 카드가 카탈로그에 들어온 경우다.
    - 카탈로그 id 하나는 한 행만 갖는다. 그 id를 가진 행이 단종이거나 이번 묶음에 없고 짝을 찾은 행이 판매 중이면 옮긴다.
      옛 판이 발급 중단되고 같은 이름의 새 판이 나온 경우다. 옛 행은 만든 id를 받는다.
    - 만든 id가 다른 행의 id와 겹치면 뒤에 -2, -3을 붙인다.
    """
    batch = {r[0]: r for r in rows}
    holder = {cid: key for key, (cid, _) in existing.items() if cid in catalog_ids}
    assigned: dict[str, str] = {}
    released: set[str] = set()
    notes: list[str] = []
    for key, cid, in_catalog, own, on_sale in rows:
        if not in_catalog:
            continue
        mine = existing.get(key, (None, False))[0]
        if mine is not None and mine not in catalog_ids and not _made(mine, own, key_id(issuer, key)):
            notes.append(f"{key}는 사람이 정한 id {mine}을 지키고 카탈로그 {cid} 짝은 쓰지 않는다")
            continue
        held = holder.get(cid)
        if held is not None and held != key:
            held_on_sale = batch[held][4] if held in batch else False
            if not on_sale or held_on_sale:
                notes.append(f"카탈로그 {cid}는 {held}가 가져 {key}는 만든 id를 쓴다")
                continue
            released.add(held)
            notes.append(f"카탈로그 {cid}를 판매 중이 아닌 {held}에서 판매 중인 {key}로 옮긴다")
        assigned[key] = cid
        holder[cid] = key

    final: dict[str, str] = {}
    for key, *_ in rows:
        mine = existing.get(key, (None, False))[0]
        if key in assigned:
            final[key] = assigned[key]
        elif mine is not None and key not in released:
            final[key] = mine
    used = {cid for key, (cid, _) in existing.items() if key not in batch and key not in released}
    used |= set(final.values())

    def fresh(candidate: str) -> str:
        out, n = candidate, 2
        while out in used or out in catalog_ids:
            out, n = f"{candidate}-{n}", n + 1
        used.add(out)
        return out

    ids = [final[key] if key in final else fresh(own) for key, _, _, own, _ in rows]
    moves = {key: fresh(key_id(issuer, key)) for key in sorted(released) if key not in batch}
    return Settled(ids, moves, notes)


def _made(card_id: str, *made: str) -> bool:
    # 만든 id이거나 겹쳐 -2, -3이 붙은 만든 id
    return any(re.fullmatch(re.escape(m) + r"(-\d+)?", card_id) for m in made)
