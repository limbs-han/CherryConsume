"""골드 첫 적재에 넣을 행. 작업 003 과제 17, 설계 4절 1번. 실제 카탈로그로 본다."""

import json
import shutil
from datetime import date
from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.draft import clean_rules, int_keys
from cherry_core.pipeline.seed import (
    TEST_CARDS,
    digest,
    file_rows,
    golden_rows,
    load_checked,
    main,
    revision_rows,
)

ROOT = Path(__file__).resolve().parents[3] / "catalog"


def test_file_rows_are_every_v2_file_as_is():
    rows = file_rows(ROOT)
    assert len(rows) == 35
    path, text = next(r for r in rows if r[0] == "cards/shinhan/shinhan-cheoeum.yaml")
    assert text == (ROOT / path).read_text(encoding="utf-8")
    assert all(not p.startswith("cards/") or p.count("/") == 2 for p, _ in rows)  # 1판 cards/*.yaml은 넣지 않는다


def test_revision_rows_are_clean_rules_of_each_revision():
    cat = load_catalog(ROOT)
    rows = revision_rows(cat)
    assert len(rows) == 22  # 카드 20장, 개정 22개
    _, issuer, day, estimated, source, rules = next(r for r in rows if r[0] == "shinhan-cheoeum")
    rev = cat.cards["shinhan-cheoeum"].revisions[-1][0]
    assert (issuer, day, estimated, source) == ("shinhan", rev.effective_from, rev.effective_from_estimated, rev.source)
    assert json.loads(rules) == json.loads(json.dumps(clean_rules(rev.data), default=str))


def test_golden_rows_split_and_first_sources():
    cat = load_catalog(ROOT)
    first = {("shinhan-cheoeum", "page"): "2026-10-01/shinhan/shinhan-cheoeum/page-abc.html"}
    rows = {r[0]: r for r in golden_rows(cat, first)}
    assert len(rows) == 20
    assert TEST_CARDS <= rows.keys()
    assert sorted(r[2] for r in rows.values()).count("test") == 5
    assert rows["shinhan-cheoeum"][2] == "test"
    assert rows["shinhan-cheoeum"][5] == {"page": "2026-10-01/shinhan/shinhan-cheoeum/page-abc.html"}
    assert rows["samsung-taptap-o"][5] == {}  # 삼성은 robots.txt가 막아 자동 수집 원문이 없다
    last = next(r for r in reversed(revision_rows(cat)) if r[0] == "shinhan-cheoeum")
    assert rows["shinhan-cheoeum"][3:5] == (last[2], last[5])  # 정답은 마지막 개정이고 그 시행일을 함께 둔다
    assert rows["ibk-narasarang"][3] == date(2027, 1, 1)  # 앞날 개정이 마지막인 카드


def test_rules_json_reads_back_to_the_same_rules():
    # 과제 18, 19, 20은 이 JSON을 다시 읽어 Rules로 비교한다. 구간 키는 int_keys로 정수로 되돌린다
    cat = load_catalog(ROOT)
    for card_id, _, day, *_, rules in revision_rows(cat):
        rev = next(r for r, _ in cat.cards[card_id].revisions if r.effective_from == day)
        assert clean_rules(int_keys(json.loads(rules))) == clean_rules(rev.data), card_id


def test_digest_ignores_order_and_matches_dates_read_back_from_spark():
    rows = [("b", date(2026, 1, 1)), ("a", date(2025, 1, 1))]
    assert digest(rows) == digest(list(reversed(rows)))
    assert digest(rows) != digest([("b", date(2026, 1, 2)), ("a", date(2025, 1, 1))])


def test_catalog_with_errors_is_refused(tmp_path):
    root = tmp_path / "catalog"
    shutil.copytree(ROOT, root)
    card = root / "cards/shinhan/shinhan-cheoeum.yaml"
    card.write_text(card.read_text(encoding="utf-8") + "\n\n", encoding="utf-8")  # 저장 형식이 아니다
    with pytest.raises(ValueError, match="오류"):
        load_checked(root)


def test_cli_prints_counts_and_digests(capsys):
    assert main([str(ROOT)]) == 0
    out = capsys.readouterr().out
    assert "카탈로그 파일 35개" in out
    assert "카드 개정 22개" in out
    assert out.count("해시 ") == 2
