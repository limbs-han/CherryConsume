"""승인된 파일을 저장소로 옮기기. 설계 4절 7번."""

import json

import pytest

from cherry_core.pipeline.export import apply_export, main

CARD = "cards/shinhan/shinhan-test.yaml"


@pytest.fixture
def dirs(tmp_path):
    export, repo = tmp_path / "export", tmp_path / "repo"
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
    msg = tmp_path / "msg.txt"
    assert main([str(export), "--repo", str(repo), "--message-file", str(msg)]) == 0
    assert msg.read_text(encoding="utf-8").startswith("feat: 신한카드 테스트")
    assert "바뀐 파일 1개" in capsys.readouterr().out
