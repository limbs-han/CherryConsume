"""손계산 표. 설계 6.1과 6.2. 표 형식, 모든 혜택이 한 번 이상 나오는지, 엔진과 같은지를 본다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine
from cherry_core.engine.cond import local

from .cases import load_cases, mismatches

ROOT = Path(__file__).resolve().parents[3] / "catalog"
CASES = load_cases()


@pytest.fixture(scope="module")
def catalog():
    return load_catalog(ROOT)


def test_case_files_are_valid(catalog):
    problems = []
    for c in CASES:
        where = f"{c.file} {c.name}"
        if c.card_id not in catalog.cards:
            problems.append(f"{where}: 카드 {c.card_id}가 없다")
            continue
        keys = {b.key for _, rules in catalog.cards[c.card_id].revisions for b in rules.benefits}
        for p in c.payments:
            if p.merchant and p.merchant not in catalog.merchants:
                problems.append(f"{where}: 가맹점 {p.merchant}가 없다")
            if p.category and p.category not in catalog.categories:
                problems.append(f"{where}: 업종 {p.category}가 없다")
            if p.payment_method and p.payment_method not in catalog.payment_methods:
                problems.append(f"{where}: 결제수단 {p.payment_method}가 없다")
        for e in c.expect:
            if not 0 <= e["payment"] < len(c.payments):
                problems.append(f"{where}: payment {e['payment']}가 결제 목록 밖이다")
            problems += [f"{where}: 혜택 {k}가 카드에 없다" for k in e.get("benefits", {}) if k not in keys]
        if not c.calc:
            problems.append(f"{where}: calc가 비어 있다")
    assert problems == []


def versions(card) -> list[tuple[str, object, object, dict]]:
    """혜택 key마다 내용이 같은 기간. (key, 시작, 끝, 내용). 끝은 다음 개정 시행일이고 없으면 None"""
    revs = card.revisions
    out = []
    for i, (rev, rules) in enumerate(revs):
        end = revs[i + 1][0].effective_from if i + 1 < len(revs) else None
        for b in rules.benefits:
            dump = b.model_dump()
            if out and any(v[0] == b.key and v[3] == dump and v[2] == rev.effective_from for v in out):
                prev = next(v for v in out if v[0] == b.key and v[3] == dump and v[2] == rev.effective_from)
                out[out.index(prev)] = (b.key, prev[1], end, dump)
            else:
                out.append((b.key, rev.effective_from, end, dump))
    return out


def test_every_benefit_is_covered(catalog):
    # intent 성공 기준 1. 혜택마다, 개정으로 내용이 바뀐 혜택은 바뀐 내용마다 양수로 한 번 이상 나온다
    covered: dict[str, list] = {}
    for c in CASES:
        for e in c.expect:
            day = local(c.payments[e["payment"]].paid_at).date()
            for key, amount in e.get("benefits", {}).items():
                if amount > 0:
                    covered.setdefault(f"{c.card_id}:{key}", []).append(day)
    missing = []
    for card_id, card in sorted(catalog.cards.items()):
        for key, start, end, _ in versions(card):
            days = covered.get(f"{card_id}:{key}", [])
            if not any(start <= d and (end is None or d < end) for d in days):
                missing.append(f"{card_id}:{key}@{start}")
    assert missing == []


@pytest.mark.parametrize("case", CASES, ids=[f"{c.card_id}:{c.name}" for c in CASES])
def test_case_matches_engine(catalog, case):
    assert mismatches(Engine(catalog), case) == []
