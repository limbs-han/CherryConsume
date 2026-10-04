"""색인 단계의 판단. 작업 008 계획 4.6과 위험 검토."""

from datetime import UTC, datetime
from types import SimpleNamespace as Row

from cherry_core.pipeline.card_index import key_id, pick_batches, settle_ids, too_many_dropped

AM, PM = datetime(2026, 10, 4, 3, tzinfo=UTC), datetime(2026, 10, 4, 15, tzinfo=UTC)


def fetch(issuer, path, at):
    return Row(issuer=issuer, path=path, fetched_at=at)


def test_batch_is_every_manifest_line_of_the_latest_fetch_even_if_paths_repeat_today():
    # 같은 날 두 번 받으면 내용이 같은 응답은 경로가 같아 documents에 새로 들어가지 않는다. 묶음은 목록 파일 줄로 고른다
    rows = [
        fetch("samsung", "d/samsung/recommend-a.html", AM),
        fetch("samsung", "d/samsung/check-b.html", AM),
        fetch("samsung", "d/samsung/recommend-c.html", PM),
        fetch("samsung", "d/samsung/check-b.html", PM),
    ]
    parsed = {r.path for r in rows}
    batches, waiting = pick_batches(rows, {}, parsed)
    assert [r.path for r in batches["samsung"]] == ["d/samsung/check-b.html", "d/samsung/recommend-c.html"]
    assert waiting == []


def test_batch_already_indexed_is_skipped_and_unparsed_batch_waits():
    rows = [fetch("kb", "kb/1", AM), fetch("nh", "nh/1", PM), fetch("nh", "nh/2", PM)]
    batches, waiting = pick_batches(rows, {"kb": AM}, {"kb/1", "nh/1"})
    assert batches == {}
    assert waiting == ["nh"]


def test_drop_guard_compares_on_sale_keys_not_row_counts():
    before = {f"code:{n}" for n in range(10)}
    assert too_many_dropped(set(), set()) is None
    assert too_many_dropped(before, before - {"code:1", "code:2", "code:3", "code:4", "code:5"}) is None
    assert "6장" in too_many_dropped(before, {"code:0", "code:1", "code:2", "code:3"})


CATALOG = {"lotte-loca365", "kb-toktok", "hyundai-zero"}


def test_existing_ids_are_kept_and_made_id_upgrades_to_catalog():
    rows = [
        ("code:9", "kb-toktok", True, "kb-9", True),
        ("code:8", "kb-8", False, "kb-8", True),
        ("code:7", "kb-7", False, "kb-7", True),
    ]
    # code:9는 만든 id였는데 승인으로 카탈로그에 들어와 짝지어졌다. code:8은 사람이 고친 id라 지킨다. code:7은 새 행이다
    existing = {"code:9": ("kb-9", True), "code:8": ("kb-renamed-by-human", True)}
    got = settle_ids("kb", rows, existing, CATALOG)
    assert got.ids == ["kb-toktok", "kb-renamed-by-human", "kb-7"]
    assert got.moves == {}


def test_human_id_is_kept_even_when_a_catalog_name_matches():
    got = settle_ids("kb", [("code:5", "kb-toktok", True, "kb-5", True)], {"code:5": ("kb-chosen", True)}, CATALOG)
    assert got.ids == ["kb-chosen"]
    assert "사람이 정한 id" in got.notes[0]


def test_catalog_id_moves_from_discontinued_old_edition_in_batch_to_new_one():
    rows = [("ref:1", "lotte-1", False, "lotte-1", False), ("ref:2", "lotte-loca365", True, "lotte-2", True)]
    existing = {"ref:1": ("lotte-loca365", True)}
    got = settle_ids("lotte", rows, existing, CATALOG)
    assert got.ids == ["lotte-1", "lotte-loca365"]
    assert "옮긴다" in got.notes[0]


def test_catalog_id_moves_from_row_missing_in_batch_and_old_row_gets_key_id():
    # 판매 중 카드만 싣는 목록에서 옛 판이 사라지고 새 판이 나왔다. 옛 행은 단종으로 바뀌고 새 id를 받는다
    rows = [("code:ZE4", "hyundai-zero", True, "hyundai-ze4", True)]
    existing = {"code:ZE3": ("hyundai-zero", True)}
    got = settle_ids("hyundai", rows, existing, CATALOG)
    assert got.ids == ["hyundai-zero"]
    assert got.moves == {"code:ZE3": "hyundai-ze3"}


def test_catalog_id_stays_when_its_holder_is_still_on_sale():
    rows = [("ref:1", "lotte-1", False, "lotte-1", True), ("ref:2", "lotte-loca365", True, "lotte-2", True)]
    got = settle_ids("lotte", rows, {"ref:1": ("lotte-loca365", True)}, CATALOG)
    assert got.ids == ["lotte-loca365", "lotte-2"]


def test_made_id_that_collides_gets_a_number():
    # 카드 코드가 옛 행에서 새 행으로 옮겨 가면 새 행이 만든 id가 옛 행의 id와 같아진다
    rows = [("ref:2", "hyundai-nve3", False, "hyundai-nve3", True)]
    got = settle_ids("hyundai", rows, {"ref:1": ("hyundai-nve3", False)}, CATALOG)
    assert got.ids == ["hyundai-nve3-2"]


def test_key_id_matches_card_ids_shape():
    assert key_id("hyundai", "ref:181608") == "hyundai-181608"
    assert key_id("lotte", "code:P14312-A14312") == "lotte-p14312-a14312"
    assert key_id("hana", "name:원더20daily").startswith("hana-n")
