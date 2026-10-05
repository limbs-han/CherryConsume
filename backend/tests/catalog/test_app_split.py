"""카드 목록 파일과 카드별 규칙 파일. 작업 014 설계 1절, 5절, 6절"""

import copy
import hashlib
import io
import json
import shutil
import zipfile
from pathlib import Path

import pytest

from cherry_core.catalog.__main__ import main
from cherry_core.catalog.app_json import SPLIT_SCHEMA, app_catalog, app_split, card_text, index_text
from cherry_core.catalog.load import load_catalog

from .conftest import benefit

REPO = Path(__file__).resolve().parents[3]
INFO = {
    "id",
    "issuer",
    "name",
    "short_name",
    "search_names",
    "kind",
    "status",
    "status_since",
    "annual_fees",
    "checked_at",
}
SHARED = ("holidays", "categories", "merchants", "payment_methods", "point_programs", "reference", "issuers")


@pytest.fixture(scope="module")
def real():
    cat = load_catalog(REPO / "catalog")
    text, cards = app_split(cat)
    return app_catalog(cat), text, json.loads(text), cards


def keys(x) -> set[str]:
    if isinstance(x, dict):
        return set(x) | {k for v in x.values() for k in keys(v)}
    if isinstance(x, list):
        return {k for v in x for k in keys(v)}
    return set()


def test_index_holds_the_shared_files_and_card_heads(real):
    full, _, index, cards = real
    assert index["schema"] == SPLIT_SCHEMA == 2
    for k in SHARED:
        assert index[k] == full[k], k
    assert [c["id"] for c in index["cards"]] == [c["id"] for c in full["cards"]] == sorted(cards)
    for c, f in zip(index["cards"], full["cards"], strict=True):
        assert set(c) - {"revisions", "file_sha256"} <= INFO
        assert {k: c[k] for k in INFO if k in c} == {k: f[k] for k in INFO if k in f}
        # 카드 추가 검색이 규칙 파일을 열지 않고 이달 구간을 고르게 개정마다 시행일과 구간을 둔다. 설계 4절
        assert c["revisions"] == [
            {
                "effective_from": r["effective_from"],
                "effective_from_estimated": r["effective_from_estimated"],
                "tiers": r["rules"]["tiers"],
            }
            for r in f["revisions"]
        ]


def test_card_files_keep_rules_without_what_the_app_does_not_read(real):
    full, _, _, cards = real
    # 근거 문장이 실제로 있어야 이 시험이 뺀 것을 본다
    assert any(b["evidence"] for f in full["cards"] for r in f["revisions"] for b in r["rules"]["benefits"])
    for f in full["cards"]:
        c = json.loads(cards[f["id"]])
        assert set(c) == {"schema", "id", "open_questions", "revisions"}
        assert (c["schema"], c["id"], c["open_questions"]) == (2, f["id"], f["open_questions"])
        for r, fr in zip(c["revisions"], f["revisions"], strict=True):
            want = copy.deepcopy(fr["rules"])
            for b in want["benefits"]:
                del b["evidence"], b["notes"]
            # 개정 지문은 빼기 전의 전체 규칙으로 만든 값 그대로다. 결제의 revision_sha가 바뀌지 않는다. 성공 기준 9
            assert r == {**fr, "rules": want}
    assert not {"evidence", "notes", "sources"} & set().union(*(keys(json.loads(t)) for t in cards.values()))


def test_index_points_at_each_file_by_its_sha(real):
    _, text, index, cards = real
    for c in index["cards"]:
        assert c["file_sha256"] == hashlib.sha256(cards[c["id"]].encode()).hexdigest()
    # 카드 하나가 목록 파일 한 줄이고 규칙 파일은 한 줄이다. 승인 하나가 목록에서 바꾸는 줄이 하나가 된다
    lines = text.splitlines()
    for c in index["cards"]:
        assert sum(line.startswith(f'{{"id":"{c["id"]}"') for line in lines) == 1
    assert all(t.endswith("\n") and t.count("\n") == 1 for t in cards.values())


def test_billing_bound_collects_billing_conditions(make_catalog, real):
    def nested(f):
        benefit(f)["when"] = [{"any_of": [{"billing": ["postpaid_transit"]}, {"channel": "online"}]}]

    assert json.loads(app_split(load_catalog(make_catalog()))[0])["billing_bound"] == []
    assert json.loads(app_split(load_catalog(make_catalog(nested)))[0])["billing_bound"] == ["cafe"]
    bound = real[2]["billing_bound"]
    assert bound and bound == sorted(set(bound))


def test_sizes_at_1500_cards(real):
    # 저장소 카드 20장을 id를 바꿔 75번 복사한다. 설계 6절, 의도 성공 기준 1과 4
    _, _, index, cards = real
    heads, files = [], {}
    for i in range(75):
        for c in index["cards"]:
            cid = f"{c['id']}-{i}"
            files[cid] = card_text({**json.loads(cards[c["id"]]), "id": cid})
            heads.append({**c, "id": cid, "file_sha256": hashlib.sha256(files[cid].encode()).hexdigest()})
    assert len(files) == 1500
    assert len(index_text({**index, "cards": heads}).encode()) < 1_500_000
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for cid, t in files.items():
            z.writestr(f"cards/{cid}.json", t)
    assert len(buf.getvalue()) < 5_000_000


def test_one_card_change_rewrites_its_file_and_one_index_line(tmp_path):
    # 의도 성공 기준 10
    root = tmp_path / "catalog"
    shutil.copytree(REPO / "catalog", root)
    before_text, before = app_split(load_catalog(root))
    path = root / "cards" / "shinhan" / "shinhan-mrlife.yaml"
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("title: ", "title: 시험 ", 1), encoding="utf-8", newline="\n")
    after_text, after = app_split(load_catalog(root))
    assert [k for k in before if before[k] != after[k]] == ["shinhan-mrlife"]
    changed = [a for a, b in zip(before_text.splitlines(), after_text.splitlines(), strict=True) if a != b]
    assert len(changed) == 1 and changed[0].startswith('{"id":"shinhan-mrlife"')


def test_json_split_writes_the_folder_and_drops_files_of_removed_cards(make_catalog, tmp_path):
    out = tmp_path / "split"
    (out / "cards").mkdir(parents=True)
    (out / "cards" / "gone.json").write_text("{}\n", encoding="utf-8")
    default = REPO / "app" / "assets" / "catalog.json"
    kept = default.read_bytes()
    assert main(["json", "--root", str(make_catalog()), "--split", str(out)]) == 0
    assert sorted(p.name for p in (out / "cards").iterdir()) == ["shinhan-test.json"]
    index = json.loads((out / "index.json").read_text(encoding="utf-8"))
    body = (out / "cards" / "shinhan-test.json").read_bytes()
    assert index["cards"][0]["file_sha256"] == hashlib.sha256(body).hexdigest()
    # 단계 1에서는 저장소의 한 파일을 건드리지 않는다. 계획 지킬 것
    assert default.read_bytes() == kept
