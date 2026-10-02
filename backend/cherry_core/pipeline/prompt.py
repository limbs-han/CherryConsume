"""추출 프롬프트와 답 형식. 설계 1절 4단계. ai_query에 그대로 넘긴다."""

from __future__ import annotations

import hashlib
import json
from datetime import date
from types import NoneType, UnionType
from typing import Annotated, Any, Literal, Union, get_args, get_origin

from pydantic import BaseModel

from cherry_core.catalog.load import Catalog
from cherry_core.catalog.models import OpenQuestion, Rules
from cherry_core.catalog.resolve import resolve_card
from cherry_core.pipeline.draft import clean_rules

# 2: 답 형식을 글로. 3: 형식 예시와 형식 규칙 넷. 4: 칸 안내, 지금 한도 key, 지어낸 칸 막기
# 5: 지금 한도는 key 이름만, 한도마다 금액을 적는 규칙, 칸 안내를 모든 모델로
# 6: 금액을 못 찾은 한도는 적지 않고 묻기. 판 5에서 금액 없는 한도로 4장이 형식 오류였다
# 7: 형식 검사에 걸린 답은 오류를 알려 주고 한 번 더 묻기. retry_prompt
# 8: 다시 물을 때 필수 칸은 빼지 않고 그대로 두기, 정답 예시는 기본값으로 채워 맞으면 다시 묻지 않기
# 9: 정답 예시는 카드사 기본값으로 채운 뒤 남는 오류만 알려 주기. 2026-10-02 다시 검토
VERSION = "9"
# 형식 예시로 보여 줄 다듬기용 카드. 형식 요소를 고루 가진 짧은 카드다. 앞의 것을 쓰고, 자기 자신을 추출할 때는 다음 것을 쓴다
# 채점 전용 카드가 없는 카드사에서 골랐다. 같은 카드사 카드는 규칙이 닮아 예시를 베끼면 채점 점수가 부푼다. 2026-10-02 위험 검토
EXAMPLE_CARDS = ("nh-heroes-check", "lotte-loca365")
# Databricks 구조화 출력은 $ref, anyOf, pattern과 64개 넘는 키를 받지 않아 JSON만 강제한다. 설계 1절 4단계
RESPONSE_FORMAT = json.dumps({"type": "json_object"})
INSTRUCTIONS = """\
너는 한국 카드사의 공식 원문에서 카드 혜택 규칙을 옮긴다. 답은 주어진 JSON 형식으로만 쓴다.
- 원문에 적힌 것만 옮긴다. 원문으로 확인하지 못한 값은 만들지 않고 open_questions에 무엇을 확인해야 하는지 적는다.
- 금액은 원 단위 정수다. 1만원은 10000이다. 비율은 퍼센트 숫자다. 10%는 10이다.
- 전월실적 구간은 tiers에 구간 하한을 적는다. 구간마다 다른 값은 {"구간 하한": 값} 맵으로 쓴다.
- 지금 혜택에 같은 혜택이 있으면 그 key를 그대로 쓴다. 새 혜택이면 영어 소문자, 숫자, -로 새 key를 만든다.
- 업종, 가맹점, 결제수단, 포인트는 아래 목록의 key만 쓴다. 맞는 key가 없으면 그 조건을 unmodeled에 문장으로 남긴다.
- 혜택마다 값을 옮긴 원문 문장을 evidence에 원문 그대로 적는다.
- 시행일은 원문에 적힌 날짜만 effective_from에 YYYY-MM-DD로 쓴다. 없으면 null이다.
- source는 가장 많이 근거로 삼은 원문의 id다.
- 원문에 없는 칸은 아예 적지 않는다. null, 빈 목록, 빈 객체, false로 채우지 않는다.
- 혜택의 target에는 all: true, categories, merchants 가운데 하나 이상을 적는다.
- 혜택 limits의 shared는 규칙 맨 위 limits에 key로 정의한 한도만 가리킨다. 정의하지 않은 이름을 쓰지 않는다.
- reward.type처럼 정해진 값이 있는 칸은 답 형식의 enum 가운데 하나만 쓴다.
- 규칙 맨 위 limits의 key는 지금 한도 key에 같은 한도가 있으면 그대로 쓴다. 주어지는 것은 이름뿐이고 per, amount, count, base는 원문에서 읽어 적는다.
- 맨 위 limits의 한도마다, 그리고 shared를 쓰지 않는 혜택 limits마다 per와 함께 amount, count, base 가운데 하나 이상을 적는다. 혜택 limits에 shared를 쓰면 다른 칸은 적지 않는다.
- 금액, 횟수, 기준 금액을 원문에서 찾지 못한 한도는 limits에 적지 않는다. 그 한도를 가리키는 shared도 적지 않고, 무엇을 확인해야 하는지 open_questions에 적는다.
- 칸 이름은 답 형식과 칸 안내에 있는 것만 쓴다. 담을 수 없는 조건은 혜택 조건이면 그 혜택의 unmodeled에, 실적이나 공통 규칙이면 규칙 맨 위 unmodeled에 문장으로 남긴다. target이나 when 안에 unmodeled를 두지 않는다.
"""


def answer_schema() -> dict:
    """답의 JSON 스키마. 프롬프트에 글로 넣는다. 카탈로그 모델이 바뀌면 답 형식도 따라 바뀐다."""
    rules = Rules.model_json_schema(by_alias=True)
    defs = {**rules.pop("$defs", {}), "OpenQuestion": OpenQuestion.model_json_schema()}
    schema = {
        "type": "object",
        "properties": {
            "rules": rules,
            "effective_from": {"anyOf": [{"type": "string", "format": "date"}, {"type": "null"}]},
            "source": {"type": "string"},
            "open_questions": {"type": "array", "items": {"$ref": "#/$defs/OpenQuestion"}},
        },
        "required": ["rules", "effective_from", "source", "open_questions"],
        "$defs": defs,
    }
    return schema


def _shape(ann: Any) -> str:
    """칸 안내에 보여 줄 값 모양. 정해진 값은 a|b, 다른 모델은 그 이름, 목록은 [안의 모양]. 숫자와 글은 비운다."""
    origin = get_origin(ann)
    if origin is Annotated:
        return _shape(get_args(ann)[0])
    if origin in (Union, UnionType):
        return " 또는 ".join(x for x in (_shape(a) for a in get_args(ann) if a is not NoneType) if x)
    if origin is Literal:
        return "|".join(str(v).lower() if isinstance(v, bool) else str(v) for v in get_args(ann))
    if origin is list:
        inner = _shape(get_args(ann)[0])
        return f"[{inner}]" if inner else ""
    if isinstance(ann, type) and issubclass(ann, BaseModel):
        return ann.__name__
    return ""


def _models(ann: Any) -> list[type[BaseModel]]:
    if isinstance(ann, type) and issubclass(ann, BaseModel):
        return [ann]
    return [m for a in get_args(ann) for m in _models(a)]


def field_guide() -> str:
    """모델마다 쓸 수 있는 칸 이름과 값 모양. 1만6천 자 스키마 안에서 칸 이름을 못 찾고 지어내는 것을 막는다.

    Rules에서 닿는 모델을 모두 보여 준다. 2026-10-02 운영 채점에서 모델이 없는 칸 이름을 지어냈다.
    """
    order: list[type[BaseModel]] = []
    todo: list[type[BaseModel]] = [Rules]
    while todo:
        cls = todo.pop(0)
        if cls not in order:
            order.append(cls)
            todo += [m for info in cls.model_fields.values() for m in _models(info.annotation)]
    lines = []
    for cls in order:
        fields = []
        for name, info in cls.model_fields.items():
            shape = _shape(info.annotation)
            fields.append(f"{info.alias or name}({shape})" if shape else info.alias or name)
        lines.append(f"{cls.__name__}: {', '.join(fields)}")
    return "\n".join(lines)


def catalog_codes(cat: Catalog) -> dict[str, list[str]]:
    return {
        "업종": sorted(cat.categories),
        "가맹점": sorted(f"{k}({m.name})" for k, m in cat.merchants.items()),
        "결제수단": sorted(f"{k}({m.name})" for k, m in cat.payment_methods.items()),
        "포인트": sorted(f"{k}({m.name})" for k, m in cat.point_programs.items()),
    }


def example_for(cat: Catalog, card_id: str) -> tuple[str, dict, str] | None:
    """(카드 이름, 합친 규칙, 꼬리표) 형식 예시. 추출하는 카드 자신과 채점 전용 카드는 보여 주지 않는다.

    합친 규칙을 그대로 보여 준다. 답의 rules가 합친 규칙이고, 카드 칸만 남기면 필수 칸이 빠져 예시가 형식에 맞지 않는다.
    꼬리표는 예시 카드, 개정 시행일, 예시 내용 해시 앞 8자리다. 예시가 바뀌면 프롬프트도 바뀌어 초안의 프롬프트 판에 붙인다.
    """
    for cid in EXAMPLE_CARDS:
        if cid != card_id and cid in cat.cards:
            lc = cat.cards[cid]
            issuer = cat.issuers[lc.card.issuer].raw if lc.card.issuer in cat.issuers else None
            rev = resolve_card(lc.raw, issuer)[-1]
            rules = clean_rules(rev.data)
            sha = hashlib.sha256(
                json.dumps(rules, ensure_ascii=False, sort_keys=True, default=str).encode()
            ).hexdigest()
            return lc.card.name, rules, f"{cid}@{rev.effective_from}#{sha[:8]}"
    return None


def build_prompt(
    card: dict,
    current: dict,
    docs: list[tuple[str, str]],
    codes: dict[str, list[str]],
    example: tuple[str, dict] | None = None,
) -> str:
    """card는 카드 파일, current는 지금 합친 규칙, docs는 (원문 id, 글) 목록, example은 example_for의 값이다."""
    benefits = [{"key": b["key"], "title": b["title"]} for b in current.get("benefits", [])]
    parts = [
        INSTRUCTIONS,
        f"카드: {card['name']} ({card['id']})",
        "지금 혜택: " + json.dumps(benefits, ensure_ascii=False),
        # 이름만 준다. 2026-10-02 판 4에서 key와 기간을 주었더니 모델이 그 모양을 베껴 금액 없는 한도를 적었다
        # 기간은 정답 예시 채점에서 정답이 그대로 샌다. 위험 검토
        "지금 한도 key: " + (", ".join(x["key"] for x in current.get("limits", [])) or "없음"),
        *(f"{name}: {', '.join(keys)}" for name, keys in codes.items()),
        "답 형식. 아래 JSON 스키마를 따르는 JSON 객체 하나로만 답한다.\n"
        + json.dumps(answer_schema(), ensure_ascii=False, separators=(",", ":")),
        "칸 안내. 모델 이름: 칸(값 모양). 이 이름만 쓴다.\n" + field_guide(),
    ]
    if example:
        name, rules = example
        parts.append(
            f"형식 예시. 다른 카드 {name}의 규칙이다. 값은 따라 하지 말고 모양만 본다. 이 모양이 답의 rules 칸에 들어간다.\n"
            + json.dumps(rules, ensure_ascii=False, default=str)
        )
    parts += [f'<원문 id="{sid}">\n{text}\n</원문>' for sid, text in docs]
    return "\n\n".join(parts)


def retry_prompt(prompt: str, answer: str, errors: list[str]) -> str:
    """규칙 형식 검사에 걸린 답을 한 번 더 묻는 프롬프트. 처음 프롬프트 뒤에 이전 답과 칸마다의 오류를 붙인다. 설계 1절 4단계."""
    ask = (
        "이전 답은 rules 안의 아래 칸이 규칙 형식에 맞지 않았다. 위의 지시와 답 형식을 따라 고친 JSON 객체 하나로 다시 답한다. "
        "원문으로 고칠 수 없는 값은 지어내지 않는다. 지시에서 빼라고 한 칸만 빼고 open_questions에 적는다. "
        "그 밖의 칸은 고칠 수 없으면 이전 답 그대로 둔다."
    )
    return "\n\n".join([prompt, f"<이전 답>\n{answer}\n</이전 답>", ask + "\n" + "\n".join(f"- {e}" for e in errors)])


def _drop_nulls(node: Any) -> Any:
    if isinstance(node, dict):
        return {k: _drop_nulls(v) for k, v in node.items() if v is not None}
    if isinstance(node, list):
        return [_drop_nulls(v) for v in node]
    return node


def parse_answer(text: str) -> dict:
    """ai_query의 답을 make_draft가 받는 모양으로 바꾼다.

    답 형식에 칸이 모두 보이면 모델이 모르는 칸에도 null을 적는다. 그래서 규칙 안의 null은 안 적은 것으로 본다.
    한도 조정의 '제한 없음' null은 이 때문에 LLM이 적을 수 없고, 검수에서 사람이 적는다.
    """
    # 2026-10-02 qwen 답 두 장이 코드 묶음 표시나 설명 글로 시작해 읽지 못했다. 처음 {부터 마지막 }까지 읽는다
    start, end = text.find("{"), text.rfind("}")
    data = json.loads(text[start : end + 1] if 0 <= start < end else text)
    day = data.get("effective_from")
    return {**data, "rules": _drop_nulls(data["rules"]), "effective_from": date.fromisoformat(day) if day else None}
