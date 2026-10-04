"""추출 결과로 카드 파일 초안을 만들고 검사한다. 설계 1절 4단계와 5단계."""

from __future__ import annotations

import copy
import tempfile
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ValidationError

from cherry_core.catalog.canonical import canonical_text, normalize
from cherry_core.catalog.check import check_catalog, path_exists
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.models import BenefitExclusions, NewCard, Rules, Spend
from cherry_core.catalog.resolve import DEFAULT_KEYS, merge, resolve_card, revision_for

SECTIONS: dict[str, type[BaseModel]] = {"spend": Spend, "new_card": NewCard, "benefit_exclusions": BenefitExclusions}


def int_keys(node: Any) -> Any:
    """JSON은 맵 키가 글자뿐이라 '300000' 같은 구간 키를 정수로 되돌린다."""
    if isinstance(node, dict):
        return {(int(k) if isinstance(k, str) and k.isdigit() else k): int_keys(v) for k, v in node.items()}
    if isinstance(node, list):
        return [int_keys(v) for v in node]
    return node


def _whole(node: Any) -> Any:
    """10.0처럼 소수점 아래가 없는 비율을 10으로 되돌린다. 카탈로그 파일은 정수로 적는다."""
    if isinstance(node, dict):
        return {k: _whole(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_whole(v) for v in node]
    return int(node) if isinstance(node, float) and node.is_integer() else node


def clean_rules(rules: dict) -> dict:
    """모델로 검사하고 기본값인 칸을 뺀다. 같은 뜻이면 같은 모양이 되어 비교할 수 있다."""
    return _whole(Rules.model_validate(rules).model_dump(by_alias=True, exclude_defaults=True))


def issuer_defaults(issuer: dict | None, day: date) -> dict:
    """day에 적용되는 카드사 기본값. resolve_card와 같이 마지막 항목 하나만 쓴다."""
    current = [d for d in (issuer or {}).get("defaults", []) if d["effective_from"] <= day]
    return {k: current[-1][k] for k in DEFAULT_KEYS if current and current[-1].get(k) is not None}


def fill_defaults(raw: dict, defaults: dict | None) -> dict:
    """모델이 적지 않은 실적 규칙, 신규 회원, 혜택 제외 칸을 카드사 기본값으로 채운다. 채점과 정답 예시 다시 묻기가 쓴다.

    카드 파일을 합칠 때와 같이 맵 안까지 합치고, 모델이 적은 값은 덮지 않는다.
    채워도 그 묶음이 형식에 맞지 않으면 채우지 않는다. 신한 신규 회원 기본값은 구간 금액이 없어 카드가 채운다.
    2026-10-02 판 3에서 이것 하나로 신한 Point Plan 전체가 0점이 됐다.
    """
    out = dict(raw)
    for k, base in (defaults or {}).items():
        merged = merge(base, out.get(k) or {}, k)
        try:
            SECTIONS[k].model_validate(merged)
        except ValidationError:
            continue
        out[k] = merged
    return out


def _dicts(node: Any) -> list[dict]:
    return [x for x in node if isinstance(x, dict)] if isinstance(node, list) else []


def _limit_kind(limit: dict) -> str:
    return str(limit.get("shared") or limit.get("per"))


def _top_level(model: type[BaseModel], data: dict) -> dict:
    """맨 위 칸마다 값. 안 적은 칸은 모델 기본값으로 채우고, 기본값이 없는 칸은 비워 둔다."""
    out = {}
    for name, info in model.model_fields.items():
        key = info.alias or name
        if key in data:
            out[key] = data[key]
        elif not info.is_required():
            out[key] = info.get_default(call_default_factory=True)
    return normalize(out)


def card_content(rules: dict, defaults: dict) -> dict:
    """합친 규칙에서 카드사 기본값과 같은 칸을 뺀다.

    남긴 칸만 카드 개정에 적어야 카드사 기본값이 나중에 바뀔 때 이 카드도 따라간다.
    비교 전에 양쪽 모두 모델 기본값을 채운다. 카드사는 exclude인데 카드는 기본값 count인 칸도 남기고,
    카드사 기본값에 없는 필수 칸도 남기기 위해서다.
    """
    out = copy.deepcopy(rules)
    for k, model in SECTIONS.items():
        if k not in out or k not in defaults:
            continue
        mine, base = _top_level(model, out[k]), _top_level(model, defaults[k])
        rest = {key: v for key, v in mine.items() if key not in base or base[key] != v}
        if rest:
            out[k] = rest
        else:
            del out[k]
    return out


def make_draft(
    card: dict, issuer: dict | None, extracted: dict, fetched: date, keep_current: bool = False
) -> dict | None:
    """추출 결과를 카드 파일의 개정으로 넣는다. 지금 규칙과 같으면 None.

    extracted는 {"rules": 합친 규칙, "effective_from": 날짜나 None, "source": 원문 id, "open_questions": [...]}다.
    시행일이 마지막 개정과 같으면 그 개정을 고치고, 뒤면 새 개정을 더한다. 앞이면 사람이 정하도록 ValueError를 낸다.
    keep_current는 바뀐 원문 추출에서 켠다. 모델이 적지 않은 실적 규칙 칸을 그 카드의 지금 값으로 채우고
    채운 묶음마다 확인 필요 항목을 단다. 공지처럼 실적 규칙이 없는 원문이 많아서다.
    카드사 기본값으로 채우면 카드가 따로 정한 실적 규칙이 조용히 사라진다. 2026-10-02 위험 검토.
    정답 예시 채점에서는 끈다. 채운 값이 정답에서 와서 점수가 부풀기 때문이다. 그때 빠진 칸은 모델 기본값이고
    필수 칸이 빠지면 형식 오류다. 채점은 카드사 기본값으로 따로 채워 잰다. score.score_answer
    """
    raw = int_keys(extracted["rules"])
    resolved = resolve_card(card, issuer)
    current = resolved[-1].data
    notes = []
    if keep_current:
        # 실적 규칙에는 근거 문장 칸이 없어 바뀐 칸마다 확인 필요 항목을 단다. 형식 예시를 베낀 값도 여기서 드러난다
        then = (revision_for(resolved, extracted.get("effective_from") or fetched) or resolved[-1]).data
        for k in SECTIONS:
            now, mine = then.get(k), raw.get(k)
            if not isinstance(now, dict) or (mine is not None and not isinstance(mine, dict)):
                continue
            missing = sorted(set(now) - set(mine or {}))
            moved = sorted(f for f, v in (mine or {}).items() if f in now and normalize(v, f) != normalize(now[f], f))
            if missing:
                raw[k] = {**now, **(mine or {})}
                notes.append(f"{k}의 {', '.join(missing)}: 원문에서 찾지 못해 지금 값을 두었다")
            if moved:
                notes.append(f"{k}의 {', '.join(moved)}: 원문에서 읽은 값이 지금 값과 다르다")
        # 프롬프트 판 6과 7은 금액을 못 찾은 한도를 빼라고 한다. 빠진 한도는 승인하면 한도 없이 계산된다. 2026-10-02 위험 검토
        # 이상한 모양의 답은 건너뛰어 형식 검사가 형식 오류로 잡게 한다. 그래야 한 번 더 묻는다
        mine_limits = {x.get("key") for x in _dicts(raw.get("limits")) if isinstance(x.get("key"), str)}
        gone = [x["key"] for x in then.get("limits", []) if x["key"] not in mine_limits]
        if gone:
            notes.append(
                f"limits의 {', '.join(gone)}: 원문에서 찾지 못해 초안에서 빠졌다. 이대로 승인하면 이 한도 없이 계산한다"
            )
        mine_benefits = {b["key"]: b for b in _dicts(raw.get("benefits")) if isinstance(b.get("key"), str)}
        for b in then.get("benefits", []):
            mine = mine_benefits.get(b["key"])
            if mine is None:
                notes.append(f"benefits의 {b['key']}: 원문에서 찾지 못해 초안에서 빠졌다")
                continue
            # 공유 한도는 이름, 직접 적은 한도는 기간으로 센다. 같은 기간이 둘일 수 있어 개수로 센다
            lost = Counter(map(_limit_kind, b.get("limits", []))) - Counter(
                map(_limit_kind, _dicts(mine.get("limits")))
            )
            if lost:
                notes.append(
                    f"benefits[{b['key']}]의 limits {', '.join(sorted(lost))}: 지금 한도가 초안에 없다. "
                    "이대로 승인하면 그 한도 없이 계산한다"
                )
        # 순위 영역의 취소 달도 근거 문장 칸이 없다. 모델이 빼면 사람이 넣은 값이 조용히 지워진다. E55 위험 검토
        # raw는 int_keys가 새로 만든 것이라 고쳐도 extracted는 그대로다
        mine_ranked = {x["key"]: x for x in _dicts(raw.get("ranked")) if isinstance(x.get("key"), str)}
        for x in then.get("ranked", []):
            mine = mine_ranked.get(x["key"])
            if mine is None:
                notes.append(f"ranked의 {x['key']}: 원문에서 찾지 못해 초안에서 빠졌다")
            elif x.get("cancellation") is None:
                continue
            elif mine.get("cancellation") is None:
                mine["cancellation"] = x["cancellation"]
                notes.append(f"ranked[{x['key']}]의 cancellation: 원문에서 찾지 못해 지금 값을 두었다")
            elif mine["cancellation"] != x["cancellation"]:
                notes.append(f"ranked[{x['key']}]의 cancellation: 원문에서 읽은 값이 지금 값과 다르다")
    rules = clean_rules(raw)
    if rules == clean_rules(current):
        return None
    out = copy.deepcopy(card)
    revisions = out["revisions"]
    last = revisions[-1]["effective_from"]
    day = extracted.get("effective_from")
    estimated = day is None
    if estimated:
        day = fetched
    if day < last:
        raise ValueError(f"추출한 시행일 {day}가 마지막 개정 {last}보다 앞이다")
    entry = {"effective_from": day, "source": extracted["source"], **card_content(rules, issuer_defaults(issuer, day))}
    if day == last:
        revisions[-1] = entry
    else:
        revisions.append(entry)
    # 같은 시행일이라 마지막 개정을 갈아 끼우면 그 안을 가리키던 옛 질문의 주소가 깨질 수 있다
    # 질문은 버리지 않고 주소만 그 개정으로 옮긴다. 옛 주소는 질문 글 앞에 붙인다. 2026-10-02 카카오뱅크
    replaced = f"revisions[{len(revisions) - 1}]"
    questions = [
        q
        if path_exists(out, q["path"]) or not (q["path"] + ".").startswith(replaced + ".")
        else {**q, "path": replaced, "question": f"{q['path']}: {q['question']}"}
        for q in out.get("open_questions", [])
    ]
    if estimated:
        entry["effective_from_estimated"] = True
        path = f"revisions[{len(revisions) - 1}].effective_from"
        questions.append({"path": path, "question": "원문에서 시행일을 찾지 못해 수집한 날로 두었다"})
    here = f"revisions[{len(revisions) - 1}]"
    asks = [{"path": here, "question": note} for note in notes] + model_questions(out, here, extracted)
    questions += [a for a in asks if a not in questions]
    if questions:
        out["open_questions"] = questions
    for s in out["sources"]:
        if s["id"] == extracted["source"]:
            s["fetched_at"] = fetched
    out["checked_at"] = fetched
    return out


def model_questions(card: dict, here: str, extracted: dict) -> list[dict]:
    """모델이 준 확인 필요 항목. here는 새 개정의 주소다. 새 카드 초안도 쓴다."""
    out = []
    for q in extracted.get("open_questions", []):
        q = q if isinstance(q, dict) else {"question": str(q)}
        if not q.get("question"):
            continue
        # 모델이 준 주소가 새 개정 안에 있으면 쓴다. 지은 주소면 질문 글 앞에 붙이고 주소는 새 개정으로 둔다
        given = str(q.get("path") or "").removeprefix("rules.")
        if given and path_exists(card, f"{here}.{given}"):
            asked = {"path": f"{here}.{given}", "question": q["question"]}
        else:
            asked = {"path": here, "question": f"{given}: {q['question']}" if given else q["question"]}
        if q.get("assumed") is not None:
            asked["assumed"] = q["assumed"]
        out.append(asked)
    return out


def check_draft(files: dict[str, str], path: str, card: dict) -> list[str]:
    """카탈로그 파일 전체에 초안 하나를 넣고 검사한다. 초안 파일의 오류와 경고만 돌려준다.

    files는 카탈로그 폴더 기준 경로와 고정 형식 YAML 본문이다. path도 같은 기준이다.
    """
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, text in {**files, path: canonical_text(card)}.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8", newline="\n")
        return [f"{p.level}: {p.path}: {p.message}" for p in check_catalog(load_catalog(root)) if p.file == path]
