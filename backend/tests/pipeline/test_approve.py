"""승인 하나를 골드와 내보내기 폴더로 옮길 값. 작업 003 과제 20의 승인 부분, 설계 4절 7번. 실제 카탈로그로 본다."""

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest
import yaml

from cherry_core.catalog.canonical import canonical_text
from cherry_core.pipeline.approve import (
    _load,
    apply_changes,
    commit_json,
    lost,
    new_review_id,
    resume_or_start,
    revision_rows_after,
    unexpected_renewals,
)
from cherry_core.pipeline.export import REVIEW_ID, SUBJECT
from cherry_core.pipeline.seed import INITIAL, file_rows, load_checked, revision_rows

ROOT = Path(__file__).resolve().parents[3] / "catalog"
GOLD = dict(file_rows(ROOT))
OLD = [(*r, INITIAL) for r in revision_rows(load_checked(ROOT))]
PLAY = {"key": "coupang_play", "name": "쿠팡플레이", "billing": "subscription", "category": "streaming"}


def with_merchant(entry: dict) -> str:
    merchants = yaml.safe_load(GOLD["merchants.yaml"])
    merchants.append(entry)
    return canonical_text(merchants)


def edited(path: str, change) -> dict[str, str]:
    data = yaml.safe_load(GOLD[path])
    change(data)
    return {path: canonical_text(data)}


def renewed(incoming: dict[str, str]) -> set[str]:
    files, _ = apply_changes(GOLD, incoming)
    return {r[0] for r in revision_rows_after(files, OLD, "r-new") if r[-1] == "r-new"}


def test_changed_file_is_checked_and_returned():
    text = with_merchant({**PLAY, "aliases": ["쿠팡플레이"]})
    files, changed = apply_changes(GOLD, {"merchants.yaml": text, "categories.yaml": GOLD["categories.yaml"]})
    assert changed == {"merchants.yaml": text}  # 골드와 같은 파일은 바뀐 것으로 치지 않는다
    assert files["merchants.yaml"] == text and files["categories.yaml"] == GOLD["categories.yaml"]


def test_resumed_approval_counts_files_it_already_put_in_gold():
    text = with_merchant({**PLAY, "aliases": ["쿠팡플레이"]})
    after = {**GOLD, "merchants.yaml": text}  # 앞 실행이 골드에 넣고 끊겼다
    _, changed = apply_changes(after, {"merchants.yaml": text}, already=["merchants.yaml"])
    assert changed == {"merchants.yaml": text}


def drop_first_revision(card):
    card["revisions"] = card["revisions"][1:]


def drop_first_benefit(card):
    card["revisions"][0]["benefits"] = card["revisions"][0]["benefits"][1:]


@pytest.mark.parametrize(
    ("incoming", "reason"),
    [
        ({"merchants.yaml": GOLD["merchants.yaml"]}, "바뀐 파일이 없다"),
        ({"merchants.yaml": GOLD["merchants.yaml"] + "\n"}, "저장 형식이 아니다"),
        ({"../merchants.yaml": "x"}, "카탈로그 파일 경로가 아니다"),
        ({"cards/shinhan/notes.txt": "x"}, "카탈로그 파일 경로가 아니다"),
        ({"brands.yaml": "[]\n"}, "카탈로그 파일 경로가 아니다"),  # 공통 파일은 이미 있는 것만
        ({"merchants.yaml": with_merchant({**PLAY, "category": "nope"})}, "검사 오류"),
        # 지운 개정과 혜택을 다른 칸이 가리키면 검사가 먼저 막는다. 검사를 지나도 아래 lost가 막는다
        (edited("cards/ibk/ibk-narasarang.yaml", drop_first_revision), "검사 오류|사라진다"),
        (edited("cards/ibk/ibk-narasarang.yaml", drop_first_benefit), "검사 오류|사라진다"),
    ],
)
def test_bad_change_is_refused(incoming, reason):
    with pytest.raises(ValueError, match=reason):
        apply_changes(GOLD, incoming)


def test_lost_finds_removed_revisions_and_benefit_keys():
    old = _load(GOLD, checked=False)
    no_rev = _load({**GOLD, **edited("cards/ibk/ibk-narasarang.yaml", drop_first_revision)}, checked=False)
    no_key = _load({**GOLD, **edited("cards/ibk/ibk-narasarang.yaml", drop_first_benefit)}, checked=False)
    assert any("ibk-narasarang" in x for x in lost(old, no_rev))  # 첫 개정이 없으면 카드째 읽히지 않는다
    assert "ibk-narasarang 2026-01-05 혜택 aio-transit" in lost(old, no_key)
    assert lost(old, old) == []


def test_merchant_only_change_keeps_every_revision():
    assert renewed({"merchants.yaml": with_merchant({**PLAY, "aliases": ["쿠팡플레이"]})}) == set()


def test_card_change_renews_only_that_card_and_revisions_that_inherit_it():
    def retitle(card):
        card["revisions"][0]["benefits"][0]["title"] += "!"

    files, _ = apply_changes(GOLD, edited("cards/ibk/ibk-narasarang.yaml", retitle))
    rows = revision_rows_after(files, OLD, "r-new")
    ibk = [r for r in rows if r[0] == "ibk-narasarang"]
    assert [r[-1] for r in ibk] == ["r-new", "r-new"]  # 2027 개정도 앞 개정의 혜택을 이어받는다
    assert {r[0] for r in rows if r[-1] == "r-new"} == {"ibk-narasarang"}
    assert len(rows) == len(OLD)


def test_issuer_default_change_renews_cards_that_follow_it():
    def cancel_by_original_month(issuer):
        issuer["defaults"][-1]["spend"]["cancellation"] = "original_month"

    shinhan = {cid for cid, *_ in OLD if cid.startswith("shinhan-")}
    assert renewed(edited("issuers/shinhan.yaml", cancel_by_original_month)) == shinhan


def test_review_id_sorts_in_approval_order_and_fits_the_export_folder_rule():
    first = new_review_id(datetime(2026, 10, 1, 9, 5, 7, tzinfo=UTC), "merchants")
    later = new_review_id(datetime(2026, 10, 1, 10, 0, 0, tzinfo=UTC), "a")
    assert first == "r-20261001T090507Z-merchants"
    assert first < later
    assert REVIEW_ID.fullmatch(first)
    for label in ("쿠팡", "", "Merchants", "a/b"):
        with pytest.raises(ValueError):
            new_review_id(datetime(2026, 10, 1, tzinfo=UTC), label)


def test_commit_json_is_what_the_export_workflow_reads():
    meta = json.loads(commit_json("feat: 쿠팡플레이와 이마트 트레이더스 가맹점 추가", "r-1", "a" * 64, "b" * 64))
    assert SUBJECT.fullmatch(meta["subject"])
    assert (meta["review_id"], meta["base"], meta["result"]) == ("r-1", "a" * 64, "b" * 64)
    for subject in ("chore: 가맹점", "feat: 가맹점 추가."):  # 커밋 훅이 막을 제목은 승인에서 막는다
        with pytest.raises(ValueError, match="subject"):
            commit_json(subject, "r-1", "a", "b")


def test_line_the_commit_hook_calls_a_secret_is_refused():
    # 실제 카드 원문 주소에 나올 수 있는 모양이다. 저장소의 커밋 훅이 이 테스트 파일을 막지 않게 이어 붙인다
    text = with_merchant({**PLAY, "aliases": ["sk" + "-telecom-membership-benefit-guide"]})
    with pytest.raises(ValueError, match="비밀값"):
        apply_changes(GOLD, {"merchants.yaml": text})


def test_lost_finds_a_removed_last_revision():
    def drop_last_revision(card):
        card["revisions"] = card["revisions"][:-1]

    gone = lost(
        _load(GOLD, checked=False),
        _load({**GOLD, **edited("cards/ibk/ibk-narasarang.yaml", drop_last_revision)}, checked=False),
    )
    assert gone == ["ibk-narasarang 2027-01-01 개정"]


def test_renewal_outside_the_changed_files_stops_the_approval():
    rows = [("a", "x", None, False, "page", "{}", "r-new"), ("b", "y", None, False, "page", "{}", "initial")]
    assert unexpected_renewals(rows, {"cards/x/a.yaml": ""}, "r-new") == []
    assert unexpected_renewals(rows, {"issuers/x.yaml": ""}, "r-new") == []
    assert unexpected_renewals(rows, {"merchants.yaml": ""}, "r-new") == ["a"]  # 규칙 코드가 바뀐 경우


MINE = {
    "review_id": "r-1",
    "subject": "feat: 가맹점 더하기",
    "base": "base",
    "result": "result",
    "paths": ["merchants.yaml"],
    "finished": False,
}
ME = {"review_id": "r-1", "source": "m-1", "subject": "feat: 가맹점 더하기"}
OTHER = {"review_id": "r-0", "source": "m-0", "subject": "feat: 업종 더하기"}


@pytest.mark.parametrize(
    ("mine", "unfinished", "gold", "expect", "outcome"),
    [
        (None, [], "base", "base", None),  # 새 승인
        (None, [], "other", "base", "PC 값과 다르다"),  # 저장소가 골드를 따라잡지 못했다
        (
            None,
            [OTHER],
            "base",
            "base",
            "끊긴 승인 r-0이 있다. 폴더 이름 m-0, 제목 'feat: 업종 더하기'",
        ),  # 끊긴 승인을 먼저 끝낸다
        (MINE, [ME], "base", "", MINE),  # 골드에 쓰기 전에 끊겼다
        (MINE, [ME], "result", "", MINE),  # 골드에 쓴 뒤 끊겼다
        (MINE, [ME], "other", "", "이 승인 밖에서 바뀌었다"),
        ({**MINE, "finished": True}, [], "result", "", "이미 끝난 승인"),
    ],
)
def test_resume_or_start(mine, unfinished, gold, expect, outcome):
    if isinstance(outcome, str):
        with pytest.raises(ValueError, match=outcome):
            resume_or_start(mine, unfinished, gold, expect)
    else:
        assert resume_or_start(mine, unfinished, gold, expect) == outcome


def test_draft_subject_names_the_card_and_the_changed_revision():
    # 과제 20. 검수 앱 승인은 제목을 비워 보내고 작업이 카드 파일로 만든다. 삼성 iD ON의 마지막 개정은 2026-07-30이다
    from cherry_core.pipeline.approve import draft_subject

    text = GOLD["cards/samsung/samsung-id-on.yaml"]
    card = yaml.safe_load(text)
    assert draft_subject(text) == "feat: 삼성 iD ON 카드 2026-07-30 개정 반영"
    assert SUBJECT.fullmatch(draft_subject(text))
    # 2026-10-02 위험 검토. 바뀐 개정의 시행일을 쓰고, 판매 중이던 카드가 멈췄을 때만 발급 중단이다
    first = canonical_text({**card, "revisions": [{**card["revisions"][0], "source": "disclosure"}, *card["revisions"][1:]]})
    assert draft_subject(first, text) == "feat: 삼성 iD ON 카드 2021-09-01 개정 반영"
    gone = canonical_text({**card, "status": "discontinued"})
    assert draft_subject(gone, text) == "feat: 삼성 iD ON 카드 발급 중단 반영"
    assert draft_subject(gone, gone) == "feat: 삼성 iD ON 카드 2026-07-30 개정 반영"  # 이미 멈춘 카드
    # 과거 개정을 가운데 끼우면 뒤 개정의 순번이 밀려도 끼운 개정의 시행일을 쓴다. 다시 검토
    middle = {**card["revisions"][1], "effective_from": "2024-03-01"}
    inserted = canonical_text({**card, "revisions": [card["revisions"][0], middle, card["revisions"][1]]})
    assert draft_subject(inserted, text) == "feat: 삼성 iD ON 카드 2024-03-01 개정 반영"


@pytest.mark.parametrize(
    ("decision", "records", "plan"),
    [
        ("approve", [], ("start", None)),
        ("approve", [{"decision": "approved", "source": "app-1", "finished": False}], ("resume", "app-1")),
        ("approve", [{"decision": "approved", "source": "app-1", "finished": True}], ("close", None)),
        ("reject", [], ("reject", None)),
        ("reject", [{"decision": "rejected", "source": None, "finished": True}], ("close", None)),
    ],
)
def test_draft_plan_resumes_or_closes_instead_of_doing_it_twice(decision, records, plan):
    # 2026-10-02 위험 검토. 앱은 버튼마다 새 폴더 이름을 만든다. 끊긴 앱 승인은 그 기록의 폴더로 이어 하고, 끝났으면 대기 건만 닫는다
    from cherry_core.pipeline.approve import draft_plan

    assert draft_plan(decision, records) == plan


@pytest.mark.parametrize(
    ("decision", "records", "reason"),
    [
        ("reject", [{"decision": "approved", "source": "app-1", "finished": False}], "승인한 초안"),
        ("approve", [{"decision": "rejected", "source": None, "finished": True}], "반려한 초안"),
    ],
)
def test_draft_plan_never_leaves_approval_and_rejection_together(decision, records, reason):
    from cherry_core.pipeline.approve import draft_plan

    with pytest.raises(ValueError, match=reason):
        draft_plan(decision, records)


def test_resume_message_sends_an_app_approval_back_to_the_app():
    # 다시 검토. 끊긴 앱 승인을 손 승인으로 이으면 저장 형식 맞추기와 대기 건 닫기가 빠진다
    unfinished = [{"review_id": "r-20261002T090000Z-draft", "source": "app-1", "subject": "feat: 카드 개정 반영", "draft_id": "d-1"}]
    with pytest.raises(ValueError, match="검수 앱에서 초안 d-1을 다시 승인"):
        resume_or_start(None, unfinished, "x", "x")


def test_stale_exports_are_pending_folders_older_than_a_day_and_a_half():
    # 2026-10-02 사용자가 정했다. export는 매일 돌아 오래 남은 폴더는 실패한 것이다. 그 위에 앱 승인을 쌓지 않는다
    # 예약 실행이 늦을 수 있어 36시간을 넘은 것만 센다. 다시 검토
    from cherry_core.pipeline.approve import stale_exports

    now = datetime(2026, 10, 3, 21, 0, tzinfo=UTC)
    names = ["r-20261002T080459Z-ranked-cancel", "r-20261003T083000Z-draft", "bad-name"]
    assert stale_exports(names, now) == ["r-20261002T080459Z-ranked-cancel", "bad-name"]


def new_card_file(card_id: str = "nh-newcard-test") -> dict[str, str]:
    card = yaml.safe_load(GOLD["cards/nh/nh-heroes-check.yaml"])
    card.update(id=card_id, name="농협 새 카드 시험", search_names=[], product_codes=["NEWTEST"])
    card.pop("short_name", None)
    return {f"cards/nh/{card_id}.yaml": canonical_text(card)}


def test_new_card_is_approved_at_a_new_path():
    from cherry_core.pipeline.approve import new_card_path

    upload = new_card_file()
    assert new_card_path(upload, GOLD, "nh") == "cards/nh/nh-newcard-test.yaml"
    files, changed = apply_changes(GOLD, upload)
    assert list(changed) == ["cards/nh/nh-newcard-test.yaml"] and set(GOLD) < set(files)
    # 새 카드는 이번 검수 번호를 받고 다른 카드 개정은 그대로다
    assert renewed(upload) == {"nh-newcard-test"}


@pytest.mark.parametrize(
    ("upload", "reason"),
    [
        (lambda: new_card_file() | {"cards/nh/nh-other.yaml": "x"}, "하나만"),
        (lambda: {"cards/kb/kb-newcard-test.yaml": "x"}, "cards/nh/"),
        (lambda: {"cards/nh/nh-heroes-check.yaml": GOLD["cards/nh/nh-heroes-check.yaml"]}, "이미 있는 카드"),
        (lambda: {"issuers/nh.yaml": GOLD["issuers/nh.yaml"]}, "cards/nh/"),
    ],
)
def test_new_card_upload_must_be_one_new_file_of_the_issuer(upload, reason):
    from cherry_core.pipeline.approve import new_card_path

    with pytest.raises(ValueError, match=reason):
        new_card_path(upload(), GOLD, "nh")


def test_resumed_new_card_approval_accepts_the_path_it_already_put_in_gold():
    from cherry_core.pipeline.approve import new_card_path

    upload = new_card_file()
    gold = GOLD | upload
    assert (
        new_card_path(upload, gold, "nh", already={"cards/nh/nh-newcard-test.yaml"}) == "cards/nh/nh-newcard-test.yaml"
    )


def test_new_card_subject_says_it_is_new():
    from cherry_core.pipeline.approve import draft_subject

    (text,) = new_card_file().values()
    assert draft_subject(text, new=True) == "feat: 농협 새 카드 시험 새 카드 추가"
    assert SUBJECT.fullmatch(draft_subject(text, new=True))


def test_new_card_that_matches_a_gold_card_of_the_issuer_is_a_conflict():
    from cherry_core.pipeline.approve import new_card_conflicts

    ((path, text),) = new_card_file().items()
    assert new_card_conflicts(text, GOLD, "nh", path) == []
    # 같은 상품이 다른 id로 두 번 들어가면 승인으로는 지울 수 없다. 2026-10-05 위험 검토
    heroes = yaml.safe_load(GOLD["cards/nh/nh-heroes-check.yaml"])
    same_code = {**yaml.safe_load(text), "product_codes": list(heroes["product_codes"])}
    same_name = {**yaml.safe_load(text), "name": heroes["name"].replace(" ", "")}
    for card in (same_code, same_name):
        found = new_card_conflicts(canonical_text(card), GOLD, "nh", path)
        assert found and found[0].startswith("cards/nh/nh-heroes-check.yaml")


@pytest.mark.parametrize(
    ("change", "reason"),
    [
        (lambda c: c.update(id="nh-other-id"), "파일 이름"),
    ],
)
def test_new_card_with_wrong_id_or_numbers_the_app_cannot_hold_is_refused(change, reason):
    ((path, text),) = new_card_file().items()
    card = yaml.safe_load(text)
    change(card)
    # 카드 검사와 export의 catalog json 숫자 검사를 승인에서도 한다. 승인만 지나고 export에서 막히면 저장소를 손으로 맞춰야 한다
    with pytest.raises(ValueError, match=reason):
        apply_changes(GOLD, {path: canonical_text(card)})


def test_new_card_id_must_start_with_its_issuer():
    ((_, text),) = new_card_file().items()
    card = {**yaml.safe_load(text), "id": "kb-newcard-test"}
    with pytest.raises(ValueError, match="카드사 폴더"):
        apply_changes(GOLD, {"cards/nh/kb-newcard-test.yaml": canonical_text(card)})


def test_new_card_with_numbers_the_app_cannot_hold_is_refused():
    ((path, text),) = new_card_file().items()
    card = yaml.safe_load(text)
    card["revisions"][0]["benefits"][0]["reward"]["rate"] = 0.33333
    with pytest.raises(ValueError, match="소수"):
        apply_changes(GOLD, {path: canonical_text(card)})
