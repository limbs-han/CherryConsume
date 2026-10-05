"""git 훅. 임시 저장소를 만들어 훅을 실제로 돌린다. 작업 013 13-21, 13-22, 13-50"""

import subprocess
import sys
from pathlib import Path

HOOKS = Path(__file__).resolve().parents[2] / ".githooks"


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, check=True).stdout


def repo(tmp_path: Path) -> Path:
    git(tmp_path, "init", "-q")
    # 임시 저장소에만 둔다. 사용자 git 설정은 건드리지 않는다
    git(tmp_path, "config", "user.name", "tester")
    git(tmp_path, "config", "user.email", "tester@example.com")
    return tmp_path


def commit(repo: Path, path: str, text: str = "x") -> str:
    f = repo / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding="utf-8")
    git(repo, "add", path)
    git(repo, "commit", "-q", "-m", f"chore: {path}")
    return git(repo, "rev-parse", "HEAD").strip()


def hook(name: str, repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(HOOKS / name), *args], cwd=repo, capture_output=True, text=True, encoding="utf-8",
        check=False,
    )


def test_pre_push_checks_every_pushed_commit_that_touches_catalog(tmp_path):
    # 끝 커밋 하나만 보면 앞 커밋의 어긋난 앱 JSON이 그대로 올라간다. 13-21
    sys.path.insert(0, str(HOOKS))
    try:
        from pre_push import pushed
    finally:
        sys.path.remove(str(HOOKS))
    r = repo(tmp_path)
    base = commit(r, "catalog/a.yaml")
    git(r, "update-ref", "refs/remotes/origin/master", base)
    first = commit(r, "catalog/a.yaml", "y")
    commit(r, "docs/note.md")
    last = commit(r, "app/assets/catalog.json", "{}")
    assert pushed(str(r), last) == [last, first]


def test_commit_msg_ignores_editor_comment_lines(tmp_path):
    # 편집기로 커밋하면 git이 바뀐 파일 목록을 # 줄로 붙인다. .claude/ 경로에 걸리면 안 된다. 13-22
    msg = tmp_path / "MSG"
    msg.write_text(
        "docs: 진행 상황 고치기\n\n"
        "# Please enter the commit message for your changes.\n"
        "# Changes to be committed:\n"
        "#\tmodified:   .claude/progress.md\n",
        encoding="utf-8",
    )
    assert hook("commit_msg.py", tmp_path, str(msg)).returncode == 0
    msg.write_text("docs: claude가 쓴 기록 정리\n", encoding="utf-8")
    assert hook("commit_msg.py", tmp_path, str(msg)).returncode == 1


def test_pre_commit_blocks_new_history_with_taken_number(tmp_path):
    # 세션 둘이 같은 번호의 작업 기록을 올린 일이 두 번 있었다. 옛 겹침은 두고 새로 겹치는 것만 막는다. 13-50
    r = repo(tmp_path)
    commit(r, "docs/history/50-a.md")
    commit(r, "docs/history/50-b.md")
    (r / "docs/history/50-c.md").write_text("x", encoding="utf-8")
    git(r, "add", "docs/history/50-c.md")
    blocked = hook("pre_commit.py", r)
    assert blocked.returncode == 1
    assert "50" in blocked.stderr
    git(r, "rm", "-q", "--cached", "docs/history/50-c.md")
    (r / "docs/history/51-d.md").write_text("x", encoding="utf-8")
    git(r, "add", "docs/history/51-d.md")
    assert hook("pre_commit.py", r).returncode == 0
