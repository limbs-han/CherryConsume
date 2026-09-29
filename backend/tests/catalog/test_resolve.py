"""카드사 기본값 합치기, 패치, 날짜로 개정 고르기. 설계 1절과 2.12, 4.3."""

from datetime import date

import pytest

from cherry_core.catalog.resolve import merge, resolve_card, revision_for

SPEND = {
    "basis": "prev_calendar_month",
    "exclude_categories": ["tax"],
    "installment": "full_at_purchase",
    "cancellation": "cancel_month",
}


def issuer(*defaults):
    return {"schema_version": 2, "id": "kb", "name": "KB국민카드", "defaults": list(defaults)}


def card(*revisions):
    return {"id": "kb-test", "revisions": list(revisions)}


def rev(day, **rules):
    return {"effective_from": day, "source": "page", **rules}


def test_merge_maps_and_null_deletes():
    assert merge({"a": 1, "b": {"c": 2, "d": 3}}, {"b": {"c": 9, "d": None}}) == {"a": 1, "b": {"c": 9}}


def test_merge_keyed_list_by_key():
    base = [{"key": "a", "rate": 1, "limits": [{"per": "day", "count": 1}]}, {"key": "b", "rate": 2}]
    patch = {"a": {"limits": [{"per": "month", "count": 5}]}, "b": None, "c": {"rate": 3}}
    assert merge(base, patch) == [
        {"key": "a", "rate": 1, "limits": [{"per": "month", "count": 5}]},
        {"key": "c", "rate": 3},
    ]


def test_merge_list_replaces_whole_list():
    assert merge({"tiers": [0, 300000]}, {"tiers": [0, 400000]}) == {"tiers": [0, 400000]}


def test_merge_keyed_patch_on_keyless_list_fails():
    with pytest.raises(ValueError, match="key가 없는 목록"):
        merge([{"per": "day", "count": 1}], {"x": {"count": 2}})


def test_card_overrides_only_the_fields_it_writes():
    out = resolve_card(
        card(rev(date(2026, 7, 1), tiers=[0], spend={"cancellation": "original_month"})),
        issuer({"effective_from": date(2026, 1, 1), "spend": SPEND}),
    )
    assert out[0].data["spend"] == {**SPEND, "cancellation": "original_month"}


def test_issuer_default_change_reaches_every_card():
    kb = issuer(
        {"effective_from": date(2026, 1, 1), "spend": SPEND},
        {"effective_from": date(2026, 10, 1), "spend": {**SPEND, "exclude_categories": ["tax", "utility"]}},
    )
    for c in [card(rev(date(2026, 7, 1), tiers=[0])), card(rev(date(2026, 8, 1), tiers=[0, 300000]))]:
        out = resolve_card(c, kb)
        assert [r.effective_from for r in out][-1] == date(2026, 10, 1)
        assert revision_for(out, date(2026, 9, 30)).data["spend"]["exclude_categories"] == ["tax"]
        assert revision_for(out, date(2026, 10, 1)).data["spend"]["exclude_categories"] == ["tax", "utility"]


def test_patch_revision_splits_the_day_before_and_the_day():
    npay = {"key": "npay-points", "limits": [{"per": "month", "count": {250000: 5, 500000: 7, 1000000: 10}}]}
    c = card(
        rev(date(2026, 7, 27), tiers=[0, 250000, 500000, 1000000], benefits=[npay]),
        {
            "effective_from": date(2027, 1, 1),
            "source": "page",
            "patch": {"benefits": {"npay-points": {"limits": [{"per": "month", "count": 5}]}}},
        },
    )
    out = resolve_card(c, None)
    before, after = revision_for(out, date(2026, 12, 31)), revision_for(out, date(2027, 1, 1))
    assert before.effective_from == date(2026, 7, 27)
    assert after.effective_from == date(2027, 1, 1)
    assert before.data["benefits"][0]["limits"][0]["count"] == {250000: 5, 500000: 7, 1000000: 10}
    assert after.data["benefits"][0]["limits"][0]["count"] == 5
    assert after.data["tiers"] == [0, 250000, 500000, 1000000]


def test_before_first_revision_uses_it_only_when_estimated():
    known = resolve_card(card(rev(date(2026, 9, 28), tiers=[0])), None)
    assert revision_for(known, date(2026, 8, 15)) is None
    guessed = resolve_card(card({**rev(date(2026, 9, 28), tiers=[0]), "effective_from_estimated": True}), None)
    assert revision_for(guessed, date(2026, 8, 15)).effective_from == date(2026, 9, 28)
