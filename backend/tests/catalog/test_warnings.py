"""경고. 틀렸다고 단정할 수 없어 검사는 통과시키고 목록으로 보여 준다. 설계 4.2."""

import copy
import subprocess

from cherry_core.catalog.check import benefit_keys

from .conftest import FILES, benefit, problems_of, rev, write_catalog

R = "revisions@2026-07-01."


def test_high_rate_without_limits(make_catalog):
    def edit(f):
        benefit(f)["limits"] = []

    root = make_catalog(edit)
    assert problems_of(root) == []
    assert any(R + "benefits[cafe-10]: 비율이 5% 이상" in w for w in problems_of(root, "warning"))


def test_decreasing_tier_table(make_catalog):
    root = make_catalog(lambda f: rev(f)["limits"][0].update(amount={300000: 20000, 500000: 10000}))
    assert any("구간이 높아지는데 값이 줄어든다" in w for w in problems_of(root, "warning"))


def test_unused_shared_limit(make_catalog):
    root = make_catalog(lambda f: benefit(f)["limits"].pop())
    assert any(R + "limits[integrated]: 쓰는 혜택이 없다" in w for w in problems_of(root, "warning"))


def test_empty_product_codes(make_catalog):
    root = make_catalog(lambda f: f["cards/shinhan/shinhan-test.yaml"].update(product_codes=[]))
    assert any("product_codes" in w for w in problems_of(root, "warning"))


def test_benefit_keys_include_patches():
    raw = {
        "revisions": [
            {"benefits": [{"key": "a"}, {"key": "b"}]},
            {"patch": {"benefits": {"c": {"title": "새 혜택"}, "b": None}}},
        ]
    }
    assert benefit_keys(raw) == {"a", "b", "c"}


def test_removed_key_against_last_commit(tmp_path):
    root = write_catalog(tmp_path / "catalog", copy.deepcopy(FILES))
    git = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com"]
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run([*git, "add", "."], cwd=tmp_path, check=True)
    subprocess.run([*git, "commit", "-q", "-m", "init"], cwd=tmp_path, check=True)
    files = copy.deepcopy(FILES)
    files["cards/shinhan/shinhan-test.yaml"]["revisions"][0]["benefits"][0]["key"] = "cafe-ten"
    write_catalog(root, files)
    assert any("사라졌다: ['cafe-10']" in w for w in problems_of(root, "warning"))
