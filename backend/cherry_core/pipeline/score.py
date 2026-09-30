"""추출 결과를 정답 예시와 칸마다 비교한다. 설계 1절 7단계와 4절 4번.

두 값 모두 draft.clean_rules를 거친 합친 규칙이어야 한다. 기본값을 빼야 같은 뜻을 같은 칸으로 비교한다.
"""

from __future__ import annotations

import json
import re
from typing import Any

from cherry_core.catalog.canonical import normalize

# 돈과 무관한 글. 4절 4번
IGNORED = {"title", "notes", "evidence", "source", "unmodeled"}
_BENEFIT = re.compile(r"^benefits\[[^\]]*\]\.([^.\[]+)")


def _leaves(node: Any, path: str, out: dict[str, str]) -> None:
    if isinstance(node, dict):
        for k, v in node.items():
            if k not in IGNORED:
                _leaves(v, f"{path}.{k}" if path else str(k), out)
    elif isinstance(node, list) and node and all(isinstance(v, dict) and "key" in v for v in node):
        for v in node:
            _leaves({k: x for k, x in v.items() if k != "key"}, f"{path}[{v['key']}]", out)
    else:
        parent = path.rsplit(".", 1)[-1]
        out[path] = json.dumps(normalize(node, parent), ensure_ascii=False, sort_keys=True, default=str)


def _group(path: str) -> str:
    m = _BENEFIT.match(path)
    return f"benefits.{m.group(1)}" if m else re.split(r"[.\[]", path, maxsplit=1)[0]


def field_accuracy(expected: dict, actual: dict) -> dict[str, tuple[int, int]]:
    """칸 묶음마다 (맞은 칸, 전체 칸). 정답에만 있거나 추출에만 있는 칸은 틀린 것으로 센다."""
    e: dict[str, str] = {}
    a: dict[str, str] = {}
    _leaves(expected, "", e)
    _leaves(actual, "", a)
    out: dict[str, list[int]] = {}
    for path in e.keys() | a.keys():
        ok_total = out.setdefault(_group(path), [0, 0])
        ok_total[1] += 1
        if path in e and path in a and e[path] == a[path]:
            ok_total[0] += 1
    return {g: (ok, total) for g, (ok, total) in sorted(out.items())}


def total_accuracy(per_card: list[dict[str, tuple[int, int]]]) -> dict[str, float]:
    """카드 여러 장의 결과를 칸 묶음마다 합쳐 비율로 바꾼다. all은 모든 칸이다."""
    sums: dict[str, list[int]] = {}
    for result in per_card:
        for g, (ok, total) in result.items():
            for key in (g, "all"):
                s = sums.setdefault(key, [0, 0])
                s[0] += ok
                s[1] += total
    return {g: ok / total for g, (ok, total) in sorted(sums.items())}
