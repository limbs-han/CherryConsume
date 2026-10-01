"""카드사 목록에서 새 카드와 사라진 카드를 가린다. 작업 003 과제 16, 설계 1절 3단계."""

from __future__ import annotations

import re

_SPACE = re.compile(r"\s+")


def _key(text: str) -> str:
    """띄어쓰기와 대소문자만 다른 이름은 같은 카드로 본다."""
    return _SPACE.sub("", text).casefold()


def list_changes(
    old_text: str, new_text: str, removed_names: list[str], added_names: list[str], known: set[str]
) -> tuple[list[str], list[str]]:
    """(새 카드, 사라진 카드). 이름은 모델이 지난 목록과 비교해 바뀐 줄에서만 뽑은 것이다.

    새 카드는 새 글에만 있는 이름이고, 사라진 카드는 옛 글에만 있는 이름이다. 그래서 모델이 줄에 없는 글자를
    지어낸 이름과, 바뀌지 않은 메뉴 글은 빠진다. known은 카탈로그의 name과 search_names다.
    같은 쪽에서 짧은 이름이 긴 이름 안에 들어 있으면 긴 이름만 남긴다. 모델이 이름과 그 앞부분을 함께 뽑기 때문이다.
    ponytail: 글에 들어 있는지를 글자 포함으로 본다. "X"처럼 짧은 이름은 어디에나 들어 있어 새 카드로도 사라진 카드로도
    잡히지 않는다. "ZERO"와 "ZERO Edition3"이 함께 새로 나오면 "ZERO"는 빠진다. 그런 카드가 나오면 줄 단위로 비교한다.
    """
    old, new, seen = _key(old_text), _key(new_text), {_key(n) for n in known}
    fresh = _longest(
        {n for n in added_names if _key(n) and _key(n) in new and _key(n) not in old and _key(n) not in seen}
    )
    gone = _longest({n for n in removed_names if _key(n) and _key(n) in old and _key(n) not in new})
    return fresh, gone


def _longest(names: set[str]) -> list[str]:
    keys = {n: _key(n) for n in names}
    return sorted(n for n in names if not any(keys[n] != k and keys[n] in k for k in keys.values()))
