"""승인된 파일을 저장소로 옮기기. 설계 4절 7번."""

import json

import pytest

from cherry_core.pipeline.export import apply_export, commit_message, main
from cherry_core.pipeline.seed import digest, file_rows

CARD = "cards/shinhan/shinhan-test.yaml"
SUBJECT = "feat: 신한카드 테스트 2026-11-01 개정 반영"


def seal(export, repo, **meta):
    """승인할 때처럼 승인 전과 후의 카탈로그 해시를 commit.json에 적는다."""
    before = dict(file_rows(repo / "catalog"))
    added = {
        p.relative_to(export / "catalog").as_posix(): p.read_text(encoding="utf-8")
        for p in (export / "catalog").rglob("*.yaml")
    }
    body = {
        "subject": SUBJECT,
        "review_id": export.name,
        "base": digest(list(before.items())),
        "result": digest(list({**before, **added}.items())),
        **meta,
    }
    (export / "commit.json").write_text(json.dumps(body), encoding="utf-8")


@pytest.fixture
def dirs(tmp_path):
    export, repo = tmp_path / "r-0001", tmp_path / "repo"  # 폴더 이름이 검수 기록 번호다
    (export / "catalog/cards/shinhan").mkdir(parents=True)
    (repo / "catalog/cards/shinhan").mkdir(parents=True)
    (export / "commit.json").write_text(
        json.dumps({"subject": "feat: 신한카드 테스트 2026-11-01 개정 반영", "review_id": "r-0001"}), encoding="utf-8"
    )
    return export, repo


def test_copies_changed_files_and_writes_message(dirs):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new\n", encoding="utf-8")
    (export / "catalog/issuers").mkdir()
    (export / "catalog/issuers/shinhan.yaml").write_text("same\n", encoding="utf-8")
    (repo / "catalog/issuers").mkdir()
    (repo / "catalog/issuers/shinhan.yaml").write_text("same\n", encoding="utf-8")
    seal(export, repo)

    changed, message = apply_export(export, repo)

    assert changed == [f"catalog/{CARD}"]
    assert (repo / "catalog" / CARD).read_text(encoding="utf-8") == "new\n"
    assert message == "feat: 신한카드 테스트 2026-11-01 개정 반영\n\n검수 기록 r-0001\n작업 003\n"


def test_rejects_non_yaml(dirs):
    export, repo = dirs
    (export / "catalog/run.sh").write_text("echo\n", encoding="utf-8")
    with pytest.raises(ValueError, match="YAML이 아니다"):
        apply_export(export, repo)


def test_cli_writes_message_file(dirs, tmp_path, capsys):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new\n", encoding="utf-8")
    seal(export, repo)
    msg = tmp_path / "msg.txt"
    assert main([str(export), "--repo", str(repo), "--message-file", str(msg)]) == 0
    assert msg.read_text(encoding="utf-8").startswith("feat: 신한카드 테스트")
    assert "바뀐 파일 1개" in capsys.readouterr().out


def test_rejects_folder_without_yaml(dirs):
    # 검수 앱이 파일을 엉뚱한 자리에 쓰면 아무것도 커밋하지 않고 done/으로 가지 않게 한다
    export, repo = dirs
    with pytest.raises(ValueError, match="YAML이 없다"):
        apply_export(export, repo)


def test_rejects_unknown_entry_beside_catalog(dirs):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new\n", encoding="utf-8")
    (export / "cards").mkdir()
    with pytest.raises(ValueError, match="모르는 것"):
        apply_export(export, repo)


@pytest.mark.parametrize(
    "meta",
    [
        {"subject": 'Revert "feat: 신한카드"', "review_id": "r-0001"},  # 커밋 훅이 검사를 건너뛰는 모양
        {"subject": "feat: 신한카드\n다른 줄", "review_id": "r-0001"},
        {"subject": "chore: 신한카드", "review_id": "r-0001"},
        {"subject": "feat: 신한카드 개정 반영", "review_id": "r-0002"},  # 폴더 이름과 다르다
        {"subject": "feat: 신한카드 개정 반영"},
    ],
)
def test_rejects_bad_commit_meta(dirs, meta):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new\n", encoding="utf-8")
    (export / "commit.json").write_text(json.dumps(meta), encoding="utf-8")
    with pytest.raises(ValueError, match="commit.json"):
        apply_export(export, repo)


def test_refuses_when_repo_is_not_the_catalog_the_approval_started_from(dirs):
    # 앞선 승인이 빠졌거나 저장소를 직접 고쳤다. 옛 판으로 새 판을 덮지 않는다
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new", encoding="utf-8")
    seal(export, repo)
    (repo / "catalog" / CARD).write_text("hand edit", encoding="utf-8")
    with pytest.raises(ValueError, match="승인할 때의 골드와 다르다"):
        apply_export(export, repo)
    assert (repo / "catalog" / CARD).read_text(encoding="utf-8") == "hand edit"


def test_refuses_when_result_is_not_the_approved_gold(dirs):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new", encoding="utf-8")
    seal(export, repo, result="0" * 64)
    with pytest.raises(ValueError, match="승인한 골드와 다르다"):
        apply_export(export, repo)


@pytest.mark.parametrize(
    "subject",
    ["feat: 신한카드 개정 반영.", "feat: 기능 추가", "feat:  두 칸", "feat: Claude가 고친 신한카드"],
)
def test_commit_message_refuses_what_the_commit_hook_would_refuse(subject):
    with pytest.raises(ValueError, match="commit.json"):
        commit_message(subject, "r-0001")


def test_folder_already_in_the_repo_finishes_without_changes(dirs):
    # 저장소에 올린 뒤 done/으로 옮기다 끊긴 폴더가 다음 밤에 다시 온 경우
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new", encoding="utf-8")
    seal(export, repo)
    apply_export(export, repo)
    changed, message = apply_export(export, repo)
    assert changed == []
    assert message.startswith(SUBJECT)
