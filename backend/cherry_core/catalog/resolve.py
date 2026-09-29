"""카드사 기본값 합치기, 패치 적용, 날짜로 개정 고르기. 설계 1절 카드사 파일과 2.12."""

from __future__ import annotations

import copy
from dataclasses import dataclass
from datetime import date
from typing import Any

META_KEYS = ("effective_from", "effective_from_estimated", "source", "patch")
DEFAULT_KEYS = ("spend", "new_card", "benefit_exclusions")
KEYED_LISTS = ("benefits", "limits", "stacks", "options", "facts", "ranked")


@dataclass(frozen=True)
class ResolvedRevision:
    effective_from: date
    effective_from_estimated: bool
    source: str
    data: dict[str, Any]


def merge(base: Any, patch: Any, field: str | None = None) -> Any:
    """patch를 base 위에 얹는다.

    맵은 키마다 합치고 값 null은 그 키를 지운다. key가 있는 목록에 맵을 얹으면 key로 짝을 맞춰 합친다.
    그 밖의 목록과 값은 통째로 바꾼다.
    """
    if isinstance(patch, dict) and (isinstance(base, list) or (base is None and field in KEYED_LISTS)):
        return _merge_keyed(base or [], patch)
    if isinstance(patch, dict) and isinstance(base, dict):
        out = copy.deepcopy(base)
        for k, v in patch.items():
            if v is None:
                out.pop(k, None)
            else:
                out[k] = merge(out.get(k), v, k)
        return out
    return copy.deepcopy(patch)


def _merge_keyed(base: list, patch: dict) -> list:
    if not all(isinstance(item, dict) and "key" in item for item in base):
        raise ValueError("key가 없는 목록에는 맵으로 패치할 수 없다. 목록 전체를 다시 쓴다")
    items = {item["key"]: copy.deepcopy(item) for item in base}
    for k, v in patch.items():
        if v is None:
            items.pop(k, None)
        elif not isinstance(v, dict):
            raise ValueError(f"key {k}의 패치는 맵이어야 한다")
        elif k in items:
            items[k] = merge(items[k], v)
        else:
            items[k] = {"key": k, **copy.deepcopy(v)}
    return list(items.values())


def card_contents(revisions: list[dict]) -> list[tuple[dict, dict]]:
    """개정 항목마다 (메타, 그 날짜의 카드 규칙 전체)를 돌려준다. 패치는 앞 개정에 얹는다."""
    out: list[tuple[dict, dict]] = []
    prev: dict | None = None
    for entry in revisions:
        meta = {k: entry[k] for k in META_KEYS if k in entry}
        if "patch" in entry:
            if prev is None:
                raise ValueError("첫 개정은 patch로 쓸 수 없다")
            content = merge(prev, entry["patch"])
        else:
            content = {k: copy.deepcopy(v) for k, v in entry.items() if k not in META_KEYS}
        out.append((meta, content))
        prev = content
    return out


def resolve_card(card: dict, issuer: dict | None) -> list[ResolvedRevision]:
    """카드 파일과 카드사 파일을 합쳐 날짜마다 개정 전체를 만든다.

    날짜는 카드 개정 날짜와, 카드 첫 개정 뒤에 생긴 카드사 기본값 날짜를 합친 것이다.
    카드 파일에 적은 칸이 카드사 기본값보다 우선한다.
    """
    contents = card_contents(card["revisions"])
    defaults = (issuer or {}).get("defaults", [])
    first = contents[0][0]["effective_from"]
    days = {meta["effective_from"] for meta, _ in contents}
    days |= {d["effective_from"] for d in defaults if d["effective_from"] > first}
    out = []
    for day in sorted(days):
        meta, content = [c for c in contents if c[0]["effective_from"] <= day][-1]
        current = [d for d in defaults if d["effective_from"] <= day]
        base = {k: current[-1][k] for k in DEFAULT_KEYS if current and current[-1].get(k) is not None}
        # 카드 개정이 시작하는 날이면 카드의 추정 표시를 따른다. 카드사 기본값이 그날 바뀌는 것으로
        # 적혀 있어도 그 날짜는 카드 개정 날짜에 맞춰 둔 것일 수 있다. 기본값만 바뀌는 날이면 기본값을 따른다
        if meta["effective_from"] == day:
            estimated = meta.get("effective_from_estimated", False)
        else:
            estimated = any(d["effective_from"] == day and d.get("effective_from_estimated", False) for d in defaults)
        out.append(ResolvedRevision(day, estimated, meta["source"], merge(base, content)))
    return out


def revision_for(revisions: list[ResolvedRevision], day: date) -> ResolvedRevision | None:
    """day에 적용되는 개정. day가 첫 개정보다 앞이면 첫 개정의 시행일이 추정일 때만 첫 개정을 쓴다."""
    current = [r for r in revisions if r.effective_from <= day]
    if current:
        return current[-1]
    first = revisions[0]
    return first if first.effective_from_estimated else None
