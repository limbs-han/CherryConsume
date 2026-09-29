"""손계산 표. 설계 6.1과 6.2. 과제 2에서는 표 형식만 본다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog

from .cases import load_cases

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
