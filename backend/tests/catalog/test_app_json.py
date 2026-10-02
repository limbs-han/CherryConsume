"""앱이 담는 카탈로그 JSON. 작업 006 설계 2절, 계획 단계 1의 2"""

import json
from pathlib import Path

import pytest

from cherry_core.catalog.__main__ import main
from cherry_core.catalog.app_json import SCHEMA, app_catalog_text, rules_sha256
from cherry_core.catalog.load import load_catalog

from .conftest import benefit, rev

REPO = Path(__file__).resolve().parents[3]
PAIRS = [
    (REPO / "catalog", REPO / "app" / "assets" / "catalog.json"),
    (REPO / "backend" / "tests" / "engine" / "mockup", REPO / "app" / "test" / "fixtures" / "mockup_catalog.json"),
]


@pytest.mark.parametrize(("root", "out"), PAIRS, ids=["catalog", "mockup"])
def test_committed_json_matches_the_catalog(root, out):
    # 카탈로그를 고치고 JSON을 다시 만들지 않으면 여기서 걸린다. 다시 만드는 명령은 python -m cherry_core.catalog json
    assert out.read_text(encoding="utf-8") == app_catalog_text(load_catalog(root))


def test_revisions_are_the_merged_rules():
    # 카드사 기본값과 패치를 합친 규칙을 그대로 쓴다. 앱은 합치는 규칙을 몰라도 된다
    cat = load_catalog(REPO / "catalog")
    data = json.loads(app_catalog_text(cat))
    [card] = [c for c in data["cards"] if c["id"] == "shinhan-mrlife"]
    want = [
        (str(r.effective_from), r.effective_from_estimated, rules.model_dump(mode="json", by_alias=True))
        for r, rules in cat.cards["shinhan-mrlife"].revisions
    ]
    assert [(r["effective_from"], r["effective_from_estimated"], r["rules"]) for r in card["revisions"]] == want
    assert all(r["sha256"] == rules_sha256(r["rules"]) for r in card["revisions"])
    # 개정에는 패치가 아니라 완성된 규칙만 있다
    assert all(
        set(r) == {"effective_from", "effective_from_estimated", "source", "sha256", "rules"} for r in card["revisions"]
    )
    assert data["schema"] == SCHEMA


def test_holidays_are_listed():
    data = json.loads(app_catalog_text(load_catalog(REPO / "catalog")))
    days = data["holidays"]
    assert days == sorted(days) and days[0] == "2020-01-01" and days[-1].startswith("2036-")
    # 2026년 지방선거일, 다시 공휴일이 된 제헌절, 토요일 개천절과 대체공휴일
    assert {"2026-06-03", "2026-07-17", "2026-10-03", "2026-10-05"} <= set(days)
    # 만든 시각은 넣지 않는다. 넣으면 다시 만들 때마다 커밋된 파일과 달라진다
    assert "generated_at" not in data and "exported_at" not in data


def test_json_command_writes_and_refuses_rule_errors(make_catalog, tmp_path, capsys):
    out = tmp_path / "catalog.json"
    assert main(["json", "--root", str(make_catalog()), "--out", str(out)]) == 0
    assert json.loads(out.read_text(encoding="utf-8"))["cards"][0]["id"] == "shinhan-test"
    out.unlink()
    # 검사 오류가 있는 카탈로그로는 만들지 않는다. 엔진이 계산하지 않던 카탈로그다. 설계 문서 6.8
    root = make_catalog(lambda f: rev(f).update(tiers=[300000, 500000]))
    assert main(["json", "--root", str(root), "--out", str(out)]) == 1
    assert not out.exists() and "오류" in capsys.readouterr().out
    root = make_catalog(lambda f: benefit(f).update(stack="pay"))
    assert main(["json", "--root", str(root), "--out", str(out)]) == 1


def test_billing_cycle_spend_is_written_like_the_engine_took_it(make_catalog, tmp_path):
    # 결제일 기준 실적은 검사가 오류로 막지만 엔진은 E6대로 받아 실적을 계산하지 않았다. 같은 기준을 쓴다
    def billing(f):
        f["issuers/shinhan.yaml"]["defaults"][0]["spend"]["basis"] = "billing_cycle"

    out = tmp_path / "catalog.json"
    assert main(["json", "--root", str(make_catalog(billing)), "--out", str(out)]) == 0
    rules = json.loads(out.read_text(encoding="utf-8"))["cards"][0]["revisions"][0]["rules"]
    assert rules["spend"]["basis"] == "billing_cycle"
