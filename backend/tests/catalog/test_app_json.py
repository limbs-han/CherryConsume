"""앱이 담는 카탈로그 JSON. 작업 006 설계 2절, 계획 단계 1의 2"""

import json
from pathlib import Path

import pytest

from cherry_core.catalog.__main__ import main
from cherry_core.catalog.app_json import SCHEMA, app_catalog_text, number_errors, rules_sha256
from cherry_core.catalog.load import load_catalog

from .conftest import benefit, rev

REPO = Path(__file__).resolve().parents[3]
PAIRS = [
    (REPO / "catalog", REPO / "app" / "assets" / "catalog.json"),
    (REPO / "app" / "test" / "engine" / "mockup", REPO / "app" / "test" / "fixtures" / "mockup_catalog.json"),
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
    # 지문은 서버의 card_revisions와 같게 규칙 전체의 덤프로 만든다
    assert [r["sha256"] for r in card["revisions"]] == [rules_sha256(w[2]) for w in want]
    # 개정에는 패치가 아니라 완성된 규칙만 있다
    assert all(
        set(r) == {"effective_from", "effective_from_estimated", "source", "sha256", "rules"} for r in card["revisions"]
    )
    assert data["schema"] == SCHEMA


def test_adjust_keeps_only_written_fields():
    # 한도 조정의 null은 제한 없음이고 칸을 안 쓴 것과 다르다. 엔진은 적힌 칸으로 가린다. 앱이 같은 것을 보게 한다
    data = json.loads(app_catalog_text(load_catalog(REPO / "catalog")))
    [ibk] = [c for c in data["cards"] if c["id"] == "ibk-narasarang"]
    limits = [lim for r in ibk["revisions"] for lim in r["rules"]["limits"]]
    limits += [lim for r in ibk["revisions"] for b in r["rules"]["benefits"] for lim in b["limits"]]
    adjusts = [a for lim in limits for a in lim["adjust"]]
    # IBK의 조정은 모두 횟수만 바꾼다. 둘은 횟수 제한을 없애는 null이다
    assert {tuple(sorted(a)) for a in adjusts} == {("count", "when")}
    assert sorted(a["count"] for a in adjusts if a["count"] is not None) == [2, 2, 6, 6]
    assert [a["count"] for a in adjusts].count(None) == 2


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


def test_json_refuses_what_the_engine_refused(make_catalog, tmp_path, capsys):
    # 엔진 시험 test_engine_refuses_catalog_with_rule_errors의 나머지 둘을 옮겼다. 그대로 두면 계산 도중 예외가 나거나
    # 한도가 사라진다. 설계 문서 6.8, 작업 006 설계 3절
    out = tmp_path / "catalog.json"

    def waived(f):
        # 하한을 풀면 0 구간인데 한도표에 0 구간 값이 없다
        rev(f)["facts"] = [{"key": "vip", "type": "bool", "scope": "card", "ask": "우수 고객인가요"}]
        benefit(f).update(
            tiers={"from": 300000, "waived_when": {"fact": "vip"}},
            limits=[{"per": "month", "amount": {300000: 1000, 500000: 2000}}],
        )

    def onsite_100(f):
        benefit(f).update(reward={"type": "onsite_discount", "rate": 100})

    for edit, where in ((waived, "limits"), (onsite_100, "reward.rate")):
        assert main(["json", "--root", str(make_catalog(edit)), "--out", str(out)]) == 1, edit.__name__
        assert not out.exists()
        assert where in capsys.readouterr().out, edit.__name__


def test_json_refuses_numbers_the_app_cannot_hold(make_catalog, tmp_path, capsys):
    # 앱 엔진은 64비트 정수 분수로 계산해 Python Fraction처럼 한계가 없지 않다. 소수 넷째 자리를 넘거나 10만 이상인 소수는
    # 계산 중 넘쳐 조용히 틀린 금액이 될 수 있어 JSON을 만들지 않는다. 2026-10-02 작업 006 단계 2 위험 검토
    out = tmp_path / "catalog.json"

    def rate(x):
        return lambda f: benefit(f).update(reward={"type": "billing_discount", "rate": x})

    for ok in (12.3456, 1.0001):
        assert main(["json", "--root", str(make_catalog(rate(ok))), "--out", str(out)]) == 0, ok
        out.unlink()
    capsys.readouterr()
    for bad in (12.34567, 1.00015):
        assert main(["json", "--root", str(make_catalog(rate(bad))), "--out", str(out)]) == 1, bad
        assert not out.exists() and "reward.rate" in capsys.readouterr().out
    # 비율 말고도 모든 수를 본다. 크기 경계는 비율 규칙 검사보다 커서 함수로 본다
    assert number_errors({"a": 10**12 - 1, "b": True, "c": 99999.9999}) == []
    assert number_errors({"c": 100000.0}) == ["c: 앱이 정확히 계산하지 못하는 소수 100000.0"]
    assert number_errors({"a": [10**12]}) == ["a[0]: 앱이 정확히 계산하지 못하는 정수 1000000000000"]


def test_short_name_only_when_written(make_catalog, tmp_path):
    # 작업 011 설계 2.4. 짧은 이름은 적은 카드와 카드사에만 담는다. 비운 칸까지 담으면 모든 폰이 받는 파일이 괜히 바뀐다
    def short(f):
        f["issuers/shinhan.yaml"]["short_name"] = "신한"
        f["cards/shinhan/shinhan-test.yaml"]["short_name"] = "신한 테스트"

    out = tmp_path / "catalog.json"
    assert main(["json", "--root", str(make_catalog(short)), "--out", str(out)]) == 0
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["issuers"] == [{"id": "shinhan", "name": "신한카드", "short_name": "신한"}]
    assert data["cards"][0]["short_name"] == "신한 테스트"

    assert main(["json", "--root", str(make_catalog()), "--out", str(out)]) == 0
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["issuers"] == [{"id": "shinhan", "name": "신한카드"}]
    assert "short_name" not in data["cards"][0]


def test_billing_cycle_spend_is_written_like_the_engine_took_it(make_catalog, tmp_path):
    # 결제일 기준 실적은 검사가 오류로 막지만 엔진은 E6대로 받아 실적을 계산하지 않았다. 같은 기준을 쓴다
    def billing(f):
        f["issuers/shinhan.yaml"]["defaults"][0]["spend"]["basis"] = "billing_cycle"

    out = tmp_path / "catalog.json"
    assert main(["json", "--root", str(make_catalog(billing)), "--out", str(out)]) == 0
    rules = json.loads(out.read_text(encoding="utf-8"))["cards"][0]["revisions"][0]["rules"]
    assert rules["spend"]["basis"] == "billing_cycle"
