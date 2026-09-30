"""카드사 목록에서 새 카드와 사라진 카드를 가린다. 작업 003 과제 16."""

from __future__ import annotations

import re

_SPACE = re.compile(r"\s+")


def _key(name: str) -> str:
    """띄어쓰기와 대소문자만 다른 이름은 같은 카드로 본다."""
    return _SPACE.sub("", name).casefold()


def list_changes(previous: list[str] | None, current: list[str], known: set[str]) -> tuple[list[str], list[str]]:
    """(새 카드, 사라진 카드). previous가 없으면 첫 목록이라 기준으로만 쓰고 둘 다 빈다.

    known은 카탈로그의 name과 search_names다. 이미 아는 카드는 새 카드에서 뺀다.
    """
    if previous is None:
        return [], []
    before, now, seen = {_key(n) for n in previous}, {_key(n) for n in current}, {_key(n) for n in known}
    new = sorted({n for n in current if _key(n) not in before and _key(n) not in seen})
    gone = sorted({n for n in previous if _key(n) not in now})
    return new, gone
