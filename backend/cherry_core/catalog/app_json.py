"""앱이 담는 카탈로그 JSON. 카드사 기본값과 패치를 합친 개정과 한국 공휴일을 한 파일에 쓴다. 작업 006 설계 2절"""

from __future__ import annotations

import hashlib
import json
from datetime import date
from fractions import Fraction

import holidays

from .check import check_rules
from .load import Catalog
from .models import Rules

# 앱이 아는 형식 번호. 칸의 뜻이 바뀌면 올린다. 앱은 자기보다 큰 번호의 파일을 쓰지 않는다
SCHEMA = 1
# 만든 해로 정하면 해가 바뀔 때 다시 만든 파일이 커밋된 파일과 달라진다. 끝 해가 다가오면 올린다
HOLIDAY_YEARS = range(2020, 2037)
# 앱 엔진은 64비트 정수 분수로 계산한다. 소수가 이 안이면 금액 계산이 넘치지 않는다. 2026-10-02 작업 006 단계 2 위험 검토
MAX_DENOMINATOR = 10_000
MAX_DECIMAL = 100_000
# 금액과 구간처럼 정수로 적힌 수의 끝. 2^53을 넘으면 Dart가 소수로 읽고, 분수와 곱하면 넘친다
MAX_INTEGER = 10**12


def rules_sha256(data: dict) -> str:
    """개정 규칙의 지문. 앱 결제의 `revision_sha`로 남는 값이다"""
    text = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode()).hexdigest()


def rule_errors(cat: Catalog) -> list[str]:
    """엔진이 계산을 거절하던 오류. 결제일 기준 실적은 검사가 오류로 막지만 엔진은 E6대로 받았다. 설계 문서 6.8"""
    errors = [str(p) for p in cat.problems if p.level == "error"]
    for card in cat.cards.values():
        ids = {s.id for s in card.card.sources}
        errors += [
            f"{card.file}: {e[1]}: {e[2]}"
            for _, rules in card.revisions
            for e in check_rules(rules, cat, ids)
            if e[0] == "error" and e[1] != "spend.basis"
        ]
    return errors


def number_errors(data: dict) -> list[str]:
    """앱이 정확히 담지 못하는 수. 소수 넷째 자리를 넘거나 10만 이상인 소수, 1조 이상인 정수면 Dart 분수가 넘쳐 조용히 틀린 금액이 될 수 있다"""
    errors: list[str] = []

    def walk(x, path: str) -> None:
        if isinstance(x, float):
            if Fraction(repr(x)).denominator > MAX_DENOMINATOR or abs(x) >= MAX_DECIMAL:
                errors.append(f"{path}: 앱이 정확히 계산하지 못하는 소수 {x!r}")
        elif isinstance(x, int) and not isinstance(x, bool) and abs(x) >= MAX_INTEGER:
            errors.append(f"{path}: 앱이 정확히 계산하지 못하는 정수 {x!r}")
        elif isinstance(x, dict):
            for k, v in x.items():
                walk(v, f"{path}.{k}" if path else k)
        elif isinstance(x, list):
            for i, v in enumerate(x):
                walk(v, f"{path}[{i}]")

    walk(data, "")
    return errors


def app_rules(rules: Rules) -> dict:
    """한도 조정은 적어 둔 칸만 쓴다. null은 제한 없음이라 칸을 안 쓴 것과 다르고 엔진은 적힌 칸으로 가린다"""
    data = rules.model_dump(mode="json", by_alias=True)

    def adjusts(models: list, dumps: list) -> None:
        for limit, d in zip(models, dumps, strict=True):
            d["adjust"] = [a.model_dump(mode="json", by_alias=True, exclude_unset=True) for a in limit.adjust]

    adjusts(rules.limits, data["limits"])
    for b, d in zip(rules.benefits, data["benefits"], strict=True):
        adjusts(b.limits, d["limits"])
    return data


def app_catalog(cat: Catalog) -> dict:
    def dump(model, **kw) -> dict:
        return model.model_dump(mode="json", by_alias=True, **kw)

    cards = []
    for card in sorted(cat.cards.values(), key=lambda c: c.card.id):
        revisions = []
        for r, rules in card.revisions:
            revisions.append(
                {
                    "effective_from": r.effective_from.isoformat(),
                    "effective_from_estimated": r.effective_from_estimated,
                    "source": r.source,
                    # 규칙 전체의 덤프로 만든다. 앱 결제가 계산에 쓴 개정을 이 값으로 남긴다
                    "sha256": rules_sha256(dump(rules)),
                    "rules": app_rules(rules),
                }
            )
        # 짧은 이름은 적은 카드에만 담는다. 비운 칸까지 담으면 모든 폰이 받는 파일이 바뀐다. 작업 011 설계 2.4
        unset = {"short_name"} if card.card.short_name is None else set()
        cards.append({**dump(card.card, exclude={"revisions", *unset}), "revisions": revisions})
    days: set[date] = set(holidays.country_holidays("KR", years=list(HOLIDAY_YEARS)))
    return {
        "schema": SCHEMA,
        "holidays": [d.isoformat() for d in sorted(days)],
        "categories": [dump(c) for c in cat.category_tree],
        "merchants": [dump(m) for m in cat.merchants.values()],
        "payment_methods": [dump(m) for m in cat.payment_methods.values()],
        "point_programs": [dump(m) for m in cat.point_programs.values()],
        "reference": [dump(m) for m in cat.reference.values()],
        "issuers": [
            {
                "id": i.issuer.id,
                "name": i.issuer.name,
                **({"short_name": i.issuer.short_name} if i.issuer.short_name else {}),
            }
            for _, i in sorted(cat.issuers.items())
        ],
        "cards": cards,
    }


def app_catalog_text(cat: Catalog) -> str:
    """줄을 나눠 쓴다. 바뀐 곳을 diff로 읽고, 커밋 훅이 줄 하나 때문에 파일 전체를 막지 않게 한다"""
    return json.dumps(app_catalog(cat), ensure_ascii=False, indent=1) + "\n"
