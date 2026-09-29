"""고정 저장 형식. 설계 4.2와 4.3."""

from datetime import date

import yaml

from cherry_core.catalog.canonical import canonical_text, format_file, is_canonical

SAMPLE = {
    "schema_version": 2,
    "id": "kb-sample",
    "revisions": [
        {
            "effective_from": date(2026, 7, 1),
            "tiers": [0, 300000],
            "benefits": [{"key": "cafe-10", "reward": {"type": "billing_discount", "rate": 10}}],
        }
    ],
}


def test_same_content_gives_same_text_and_is_idempotent():
    once = canonical_text(SAMPLE)
    assert canonical_text(yaml.safe_load(once)) == once
    shuffled = dict(reversed(list(SAMPLE.items())))
    assert canonical_text(shuffled) == once


def test_key_order_and_set_like_lists():
    text = canonical_text(
        {
            "target": {"merchants": ["b", "a"]},
            "title": "t",
            "key": "k",
            "when": [{"day": {"in": ["sun", "sat"]}}],
            "tiers": [0, 500000, 300000],
        }
    )
    assert text.splitlines()[0] == "key: k"
    data = yaml.safe_load(text)
    assert data["target"]["merchants"] == ["a", "b"]
    assert data["when"][0]["day"]["in"] == ["sat", "sun"]
    assert data["tiers"] == [0, 500000, 300000]


def test_tier_table_keys_sorted_and_strings_kept():
    data = yaml.safe_load(
        canonical_text({"amount": {500000: 2, 300000: 1}, "from": "21:00", "notes": "첫 줄\n둘째 줄"})
    )
    assert list(data["amount"]) == [300000, 500000]
    assert data["from"] == "21:00"
    assert data["notes"] == "첫 줄\n둘째 줄"


def test_format_file_rewrites_only_when_needed(tmp_path):
    path = tmp_path / "x.yaml"
    path.write_text("title: t\nkey: k\nchecked_at: 2026-09-28\n", encoding="utf-8")
    assert not is_canonical(path)
    assert format_file(path) is True
    assert is_canonical(path)
    assert format_file(path) is False
    assert yaml.safe_load(path.read_text(encoding="utf-8"))["checked_at"] == date(2026, 9, 28)


def test_benefit_fields_in_reading_order():
    b = {
        "tiers": {"from": 300000},
        "limits": [],
        "reward": {"type": "cashback", "fixed": 1000},
        "target": {"all": True},
        "title": "t",
        "key": "k",
    }
    assert list(yaml.safe_load(canonical_text(b))) == ["key", "title", "target", "reward", "limits", "tiers"]
