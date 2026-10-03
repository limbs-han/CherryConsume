"""카탈로그 파일의 고정 저장 형식. 설계 4.2 저장 형식.

같은 내용이면 언제나 같은 글자가 나오게 키 순서, 들여쓰기, 집합 성격 목록의 순서를 고정한다.
카탈로그 파일에는 주석을 쓰지 않는다. 사람이 읽을 메모는 notes 칸에 쓴다.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml

KEY_ORDER = [
    "schema_version",
    "id",
    "key",
    "code",
    "issuer",
    "name",
    "title",
    "search_names",
    "kind",
    "product_codes",
    "status",
    "status_since",
    "type",
    "scope",
    "ask",
    "brand",
    "form",
    "annual_fees",
    "sources",
    "url",
    "fetched_at",
    "text_sha256",
    "review_no",
    "review_valid_until",
    "checked_at",
    "collect",
    "list_url",
    "method",
    "interval_days",
    "notice_url",
    "disclosure_url",
    "defaults",
    "revisions",
    "effective_from",
    "effective_from_estimated",
    "source",
    "patch",
    "tiers",
    "spend",
    "basis",
    "regions",
    "exclude_categories",
    "interest_free",
    "lump_sum",
    "installment",
    "cancellation",
    "cancellation_overrides",
    "use",
    "month_offset",
    "exclude_applied",
    "new_card",
    "until",
    "tier",
    "tier_by_benefit",
    "benefit_exclusions",
    "when_any",
    "facts",
    "options",
    "choices",
    "default",
    "change",
    "unsupported",
    "ranked",
    "top",
    "by",
    "limits",
    "stacks",
    "pick",
    "order",
    "spill",
    "benefits",
    "target",
    "all",
    "categories",
    "merchants",
    "exclude_merchants",
    "when",
    "in",
    "holidays",
    "from",
    "to",
    "min",
    "below",
    "max",
    "months",
    "region",
    "channel",
    "payment",
    "payment_not",
    "billing",
    "billing_not",
    "option",
    "fact",
    "card_month",
    "month_total",
    "any_of",
    "waived_when",
    "reward",
    "program",
    "rate",
    "fixed",
    "per_unit",
    "per_liter",
    "round",
    "shared",
    "per",
    "unit",
    "amount",
    "count",
    "multiply",
    "add",
    "adjust",
    "stack",
    "valid_from",
    "valid_until",
    "unmodeled",
    "open_questions",
    "path",
    "question",
    "assumed",
    "category",
    "aliases",
    "statement_names",
    "won_per_point",
    "value",
    "as_of",
    "kakao",
    "children",
    "notes",
]
_RANK = {k: i for i, k in enumerate(KEY_ORDER)}
# 혜택은 읽는 순서대로 쓴다. 대상, 조건, 보상, 한도, 구간
BENEFIT_ORDER = [
    "key",
    "title",
    "source",
    "evidence",
    "target",
    "when",
    "area",
    "reward",
    "limits",
    "tiers",
    "stack",
    "exclude_applied",
    "valid_from",
    "valid_until",
    "unmodeled",
    "notes",
]
_BENEFIT_RANK = {k: i for i, k in enumerate(BENEFIT_ORDER)}
SET_FIELDS = {
    "search_names",
    "product_codes",
    "regions",
    "exclude_categories",
    "categories",
    "merchants",
    "exclude_merchants",
    "in",
    "months",
    "payment",
    "payment_not",
    "billing",
    "billing_not",
    "unsupported",
    "statement_names",
}
WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def normalize(node: Any, parent: Any = None) -> Any:
    if isinstance(node, dict):
        if node and all(isinstance(k, int) and not isinstance(k, bool) for k in node):
            items = sorted(node.items())
        else:
            rank = _BENEFIT_RANK if "reward" in node else _RANK
            items = sorted(node.items(), key=lambda kv: (rank.get(kv[0], len(rank)), str(kv[0])))
        return {k: normalize(v, k) for k, v in items}
    if isinstance(node, list):
        items = [normalize(v) for v in node]
        if parent in SET_FIELDS and all(isinstance(v, (str, int)) and not isinstance(v, bool) for v in items):
            if parent == "in" and all(v in WEEKDAYS for v in items):
                return sorted(items, key=WEEKDAYS.index)
            return sorted(items, key=lambda v: (isinstance(v, str), v))
        return items
    return node


class _Dumper(yaml.SafeDumper):
    def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:
        return super().increase_indent(flow, False)


# YAML 1.2로 읽는 도구는 09256 같은 글자를 숫자로 읽는다. 숫자처럼 보이는 글자는 늘 따옴표로 감싼다
_NUMBER_LIKE = re.compile(r"[-+]?(\.\d+|\d[\d_]*(\.\d*)?)([eE][-+]?\d+)?")


def _represent_str(dumper: yaml.SafeDumper, value: str) -> yaml.Node:
    if "\n" in value:
        style = "|"
    elif _NUMBER_LIKE.fullmatch(value):
        style = "'"
    else:
        style = None
    return dumper.represent_scalar("tag:yaml.org,2002:str", value, style=style)


_Dumper.add_representer(str, _represent_str)


def canonical_text(data: Any) -> str:
    return yaml.dump(
        normalize(data),
        Dumper=_Dumper,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=None,
        width=10_000,
        indent=2,
    )


def catalog_files(root: Path) -> list[Path]:
    """2판 카탈로그 파일. 1판 카드 파일 catalog/cards/*.yaml은 포함하지 않는다."""
    return sorted([*root.glob("*.yaml"), *root.glob("issuers/*.yaml"), *root.glob("cards/*/*.yaml")])


def is_canonical(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    return text == canonical_text(yaml.safe_load(text))


def format_file(path: Path) -> bool:
    """고정 형식으로 다시 쓴다. 바뀌었으면 True."""
    text = path.read_text(encoding="utf-8")
    new = canonical_text(yaml.safe_load(text))
    if new == text:
        return False
    path.write_text(new, encoding="utf-8", newline="\n")
    return True
