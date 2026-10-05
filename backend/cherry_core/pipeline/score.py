"""추출 결과를 정답 예시와 칸마다 비교한다. 설계 1절 7단계와 4절 4번.

두 값 모두 draft.clean_rules를 거친 합친 규칙이어야 한다. 기본값을 빼야 같은 뜻을 같은 칸으로 비교한다.
"""

from __future__ import annotations

import copy
import json
import re
from typing import Any

from cherry_core.catalog.canonical import normalize
from cherry_core.pipeline.draft import clean_rules, fill_defaults, int_keys
from cherry_core.pipeline.prompt import _drop_nulls, parse_answer

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


def _same_fields(a: dict, b: dict) -> int:
    """key를 뺀 두 항목에서 값이 같은 칸 수."""
    la: dict[str, str] = {}
    lb: dict[str, str] = {}
    _leaves({k: v for k, v in a.items() if k != "key"}, "", la)
    _leaves({k: v for k, v in b.items() if k != "key"}, "", lb)
    return sum(la[p] == lb[p] for p in la.keys() & lb.keys())


def align_keys(expected: dict, actual: dict) -> dict:
    """추출의 맨 위 한도와 혜택 key를 정답의 key로 바꾼다. 작업 008 12단계.

    새 카드 추출은 key를 모델이 지어 key로 맞추면 내용이 같아도 모두 틀린다. 정답 항목마다 같은 칸이 가장 많은 추출 항목과
    짝짓는다. 같은 칸이 많은 짝부터 정하고 정답 하나에 하나만 짝짓는다. 한도 key를 바꾸면 혜택의 shared도 따라 바꾼다.
    짝이 없는 추출 항목이 정답 key와 같은 이름이면 다른 항목과 섞이지 않게 이름 뒤에 ~extra를 붙인다.
    """
    out = copy.deepcopy(actual)
    for section in ("limits", "benefits"):
        mine, theirs = out.get(section) or [], expected.get(section) or []
        if not (isinstance(mine, list) and isinstance(theirs, list)):
            continue
        pairs = sorted(
            (
                (_same_fields(a, e), i, j)
                for i, a in enumerate(mine)
                if isinstance(a, dict)
                for j, e in enumerate(theirs)
                if isinstance(e, dict)
            ),
            key=lambda x: (-x[0], x[1], x[2]),
        )
        renamed, used = {}, set()
        for same, i, j in pairs:
            if same and i not in renamed and j not in used:
                renamed[i], used = theirs[j].get("key"), used | {j}
        taken = {theirs[j].get("key") for j in used}
        moves = {}
        for i, a in enumerate(mine):
            if not isinstance(a, dict):
                continue
            new = renamed.get(i) or (f"{a.get('key')}~extra" if a.get("key") in taken else a.get("key"))
            moves[a.get("key")] = new
            a["key"] = new
        if section == "limits":
            for b in out.get("benefits") or []:
                for lim in (b.get("limits") or []) if isinstance(b, dict) else []:
                    if isinstance(lim, dict) and lim.get("shared") in moves:
                        lim["shared"] = moves[lim["shared"]]
    return out


def score_answer(
    golden_rules: str, answer: str | None, defaults: dict | None = None, align: bool = False
) -> dict[str, tuple[int, int]]:
    """정답 예시 규칙 JSON과 모델 답 원문을 칸마다 비교한다. 과제 19.

    golden_rules는 silver.golden의 rules다. answer는 cherry_extract가 silver.drafts에 남긴 답 원문이다.
    답을 읽지 못하거나 규칙 형식에 맞지 않으면 정답의 모든 칸을 틀린 것으로 센다. 형식 오류도 모델의 실력이다.
    정답의 null 칸은 채점하지 않는다. 한도 조정의 "제한 없음" null은 모델 답에서 안 적은 것으로 지워져 모델이 맞힐 수 없다.
    defaults는 그 카드사의 실적 규칙, 신규 회원, 혜택 제외 기본값이다. 모델이 적지 않은 칸을 이 값으로 채워 채점한다.
    카드 원문에 없는 카드사 공통 규칙을 맞힌 것으로 본다. 카드가 기본값과 다르게 정했는데 모델이 못 적었으면 틀린 것이다.
    기본값을 그 카드사 카드들의 상품 페이지에서 옮긴 곳이 있어 이 세 묶음 점수는 부풀 수 있다.
    그래서 채점 작업은 채우지 않은 점수도 같이 남긴다. 2026-10-02 위험 검토
    align은 새 카드 프롬프트로 뽑은 답에서 켠다. key를 내용으로 맞춘 뒤 채점한다. align_keys
    """
    expected = _drop_nulls(int_keys(json.loads(golden_rules)))
    try:
        raw = int_keys(parse_answer(answer)["rules"]) if answer else None
        actual = clean_rules(fill_defaults(raw, defaults)) if raw is not None else {}
    except Exception:  # noqa: BLE001 모델의 답은 어떤 모양이든 올 수 있다
        actual = {}
    return field_accuracy(expected, align_keys(expected, actual) if align else actual)


def summarize(cards: list[tuple[str, dict[str, tuple[int, int]]]]) -> dict[str, float]:
    """(정답 예시 split, 카드 결과)를 다듬기용 tune과 채점 전용 holdout으로 나눠 합친다. MLflow 지표 이름이다."""
    out: dict[str, float] = {}
    for split, name in (("tune", "tune"), ("test", "holdout")):
        out |= {f"{name}.{g}": v for g, v in total_accuracy([r for s, r in cards if s == split]).items()}
    return out
