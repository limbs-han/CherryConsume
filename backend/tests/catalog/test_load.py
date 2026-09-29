"""파일 읽기와 오류 위치."""

from cherry_core.catalog.load import format_loc, load_catalog

from .conftest import benefit, load_problems, rev


def test_valid_catalog_has_no_errors(make_catalog):
    root = make_catalog()
    cat = load_catalog(root)
    assert load_problems(root) == []
    card = cat.cards["shinhan-test"]
    rules = card.revisions[0][1]
    assert rules.spend.exclude_categories == ["tax"]
    assert "transit.subway" in cat.categories


def test_error_path_uses_benefit_key(make_catalog):
    root = make_catalog(lambda f: benefit(f)["reward"].update(rat=5))
    assert any("revisions@2026-07-01.benefits[cafe-10].reward.rat" in e for e in load_problems(root))


def test_missing_issuer_default_field_is_reported(make_catalog):
    root = make_catalog(lambda f: f["issuers/shinhan.yaml"]["defaults"][0]["spend"].pop("installment"))
    assert any("revisions@2026-07-01.spend.installment" in e for e in load_problems(root))


def test_yaml_syntax_error_is_reported(make_catalog):
    root = make_catalog()
    (root / "merchants.yaml").write_text("- key: [broken\n", encoding="utf-8")
    assert any(e.startswith("merchants.yaml: YAML을 읽지 못했다") for e in load_problems(root))


def test_revisions_must_ascend(make_catalog):
    def edit(f):
        f["cards/shinhan/shinhan-test.yaml"]["revisions"].append({**rev(f), "effective_from": rev(f)["effective_from"]})

    assert any("오름차순" in e for e in load_problems(make_catalog(edit)))


def test_format_loc():
    data = {"benefits": [{"key": "a"}, {"title": "no key"}]}
    assert format_loc(("benefits", 0, "reward"), data) == "benefits[a].reward"
    assert format_loc(("benefits", 1, "reward"), data) == "benefits[1].reward"
