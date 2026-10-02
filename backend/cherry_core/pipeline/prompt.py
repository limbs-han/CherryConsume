"""추출 프롬프트와 답 형식. 설계 1절 4단계. ai_query에 그대로 넘긴다."""

from __future__ import annotations

import hashlib
import json
from datetime import date
from typing import Any

from cherry_core.catalog.load import Catalog
from cherry_core.catalog.models import OpenQuestion, Rules
from cherry_core.catalog.resolve import resolve_card
from cherry_core.pipeline.draft import clean_rules

VERSION = "3"  # 2026-10-01 답 형식을 프롬프트 글로 넣었다. 2026-10-02 형식 예시와 자주 틀린 형식 규칙 넷을 더했다
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
        *(f"{name}: {', '.join(keys)}" for name, keys in codes.items()),
        "답 형식. 아래 JSON 스키마를 따르는 JSON 객체 하나로만 답한다.\n"
        + json.dumps(answer_schema(), ensure_ascii=False, separators=(",", ":")),
    ]
    if example:
        name, rules = example
        parts.append(
            f"형식 예시. 다른 카드 {name}의 규칙이다. 값은 따라 하지 말고 모양만 본다. 이 모양이 답의 rules 칸에 들어간다.\n"
            + json.dumps(rules, ensure_ascii=False, default=str)
        )
    parts += [f'<원문 id="{sid}">\n{text}\n</원문>' for sid, text in docs]
    return "\n\n".join(parts)


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
    data = json.loads(text)
    day = data.get("effective_from")
    return {**data, "rules": _drop_nulls(data["rules"]), "effective_from": date.fromisoformat(day) if day else None}
