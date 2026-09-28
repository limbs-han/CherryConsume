"""세션 시작 때 git 훅 경로를 맞추고 현재 상태와 진행 상황을 보여 준다. 출력은 Claude의 맥락에 들어간다."""
import os, pathlib, subprocess, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or pathlib.Path(__file__).resolve().parents[2])


def git(*args):
    r = subprocess.run(["git", "-c", "core.quotepath=false", *args], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.stdout.strip()


lines = []
if git("config", "--get", "core.hooksPath") != ".githooks":
    git("config", "core.hooksPath", ".githooks")
    lines.append("git 훅 경로를 .githooks로 맞췄다.")

status = git("status", "--short").splitlines()
lines.append(f"브랜치 {git('branch', '--show-current')}. 변경 파일 {len(status)}개")
lines += status[:15] + (["..."] if len(status) > 15 else [])

progress = ROOT / ".claude" / "progress.md"
if progress.exists():
    lines += ["", progress.read_text(encoding="utf-8")]
print("\n".join(lines))
