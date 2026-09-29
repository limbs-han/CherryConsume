"""실제 카탈로그로 작업 001 성공 기준을 확인한다. docs/work/001-catalog-schema-v2/intent.md."""

import copy
import re
from datetime import date
from pathlib import Path

import pytest

from cherry_core.catalog.canonical import catalog_files, is_canonical
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.resolve import resolve_card, revision_for

ROOT = Path(__file__).resolve().parents[3] / "catalog"


@pytest.fixture(scope="module")
def cat():
    return load_catalog(ROOT)


def test_twenty_cards_pass_check(cat):
    assert [str(p) for p in check_catalog(cat) if p.level == "error"] == []
    assert len(cat.cards) == 20


def test_no_benefit_is_copied_per_tier(cat):
    copies = [
        f"{c.card.id}:{b.key}"
        for c in cat.cards.values()
        for _, rules in c.revisions
        for b in rules.benefits
        if re.search(r"-t\d+$", b.key)
    ]
    assert copies == []


def test_every_file_is_canonical():
    assert [p.relative_to(ROOT).as_posix() for p in catalog_files(ROOT) if not is_canonical(p)] == []


def _written_spend_keys(raw: dict) -> set[str]:
    keys = set()
    for entry in raw["revisions"]:
        keys |= set(entry.get("spend") or {})
        keys |= set((entry.get("patch") or {}).get("spend") or {})
    return keys


def test_issuer_default_change_reaches_every_card(cat):
    tested = 0
    for issuer_id, issuer in cat.issuers.items():
        cards = [c for c in cat.cards.values() if c.card.issuer == issuer_id]
        defaults = issuer.issuer.model_dump(by_alias=True, exclude_unset=True).get("defaults") or []
        if len(cards) < 2 or not defaults or not defaults[-1].get("spend"):
            continue
        written = set().union(*(_written_spend_keys(c.raw) for c in cards))
        free = [k for k in defaults[-1]["spend"] if k not in written]
        if not free:
            continue
        changed = copy.deepcopy(issuer.issuer.model_dump(by_alias=True, exclude_unset=True))
        changed["defaults"][-1]["spend"][free[0]] = "CHANGED"
        for c in cards:
            resolved = resolve_card(c.card.model_dump(by_alias=True, exclude_unset=True), changed)
            assert resolved[-1].data["spend"][free[0]] == "CHANGED", c.card.id
        tested += 1
    assert tested >= 1


def test_npay_change_splits_on_2027_01_01(cat):
    revisions = [r for r, _ in cat.cards["ibk-narasarang"].revisions]
    before = revision_for(revisions, date(2026, 12, 31))
    after = revision_for(revisions, date(2027, 1, 1))
    assert before.effective_from < date(2027, 1, 1) <= after.effective_from

    def npay(r):
        return next(b for b in r.data["benefits"] if b["key"] == "npay-points")

    assert npay(before) != npay(after)
