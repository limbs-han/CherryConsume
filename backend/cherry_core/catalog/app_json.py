"""앱이 담는 카탈로그 JSON. 카드사 기본값과 패치를 합친 개정과 한국 공휴일을 한 파일에 쓴다. 작업 006 설계 2절"""

from __future__ import annotations

import hashlib
import json
from datetime import date

import holidays

from .check import check_rules
from .load import Catalog

# 앱이 아는 형식 번호. 칸의 뜻이 바뀌면 올린다. 앱은 자기보다 큰 번호의 파일을 쓰지 않는다
SCHEMA = 1
# 만든 해로 정하면 해가 바뀔 때 다시 만든 파일이 커밋된 파일과 달라진다. 끝 해가 다가오면 올린다
HOLIDAY_YEARS = range(2020, 2037)


def rules_sha256(data: dict) -> str:
    """개정 규칙의 지문. 서버의 card_revisions와 같은 값이다"""
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


def app_catalog(cat: Catalog) -> dict:
    def dump(model, **kw) -> dict:
        return model.model_dump(mode="json", by_alias=True, **kw)

    cards = []
    for card in sorted(cat.cards.values(), key=lambda c: c.card.id):
        revisions = []
        for r, rules in card.revisions:
            data = dump(rules)
            revisions.append(
                {
                    "effective_from": r.effective_from.isoformat(),
                    "effective_from_estimated": r.effective_from_estimated,
                    "source": r.source,
                    "sha256": rules_sha256(data),
                    "rules": data,
                }
            )
        cards.append({**dump(card.card, exclude={"revisions"}), "revisions": revisions})
    days: set[date] = set(holidays.country_holidays("KR", years=list(HOLIDAY_YEARS)))
    return {
        "schema": SCHEMA,
        "holidays": [d.isoformat() for d in sorted(days)],
        "categories": [dump(c) for c in cat.category_tree],
        "merchants": [dump(m) for m in cat.merchants.values()],
        "payment_methods": [dump(m) for m in cat.payment_methods.values()],
        "point_programs": [dump(m) for m in cat.point_programs.values()],
        "reference": [dump(m) for m in cat.reference.values()],
        "issuers": [{"id": i.issuer.id, "name": i.issuer.name} for _, i in sorted(cat.issuers.items())],
        "cards": cards,
    }


def app_catalog_text(cat: Catalog) -> str:
    """줄을 나눠 쓴다. 바뀐 곳을 diff로 읽고, 커밋 훅이 줄 하나 때문에 파일 전체를 막지 않게 한다"""
    return json.dumps(app_catalog(cat), ensure_ascii=False, indent=1) + "\n"
