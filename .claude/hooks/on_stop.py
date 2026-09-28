"""Claude가 끝내기 전에 계산 코드가 바뀌었으면 테스트를 돌린다. 실패하면 exit 2로 계속 고치게 한다."""
import json, os, pathlib, subprocess, sys

sys.stderr.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or pathlib.Path(__file__).resolve().parents[2])

data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
if data.get("stop_hook_active") or not (ROOT / "backend" / "pyproject.toml").exists():
    sys.exit(0)  # 이미 한 번 막았거나 backend가 아직 없다


def run(cmd):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env={**os.environ, "PYTHONUTF8": "1"})
    return r.returncode, (r.stdout + r.stderr).strip()


_, changed = run(["git", "status", "--porcelain", "--", "backend"])
if not changed:
    sys.exit(0)
code, out = run(["uv", "run", "--project", "backend", "pytest", "-q", "-x"])
if code:
    print("backend 테스트가 실패해서 끝낼 수 없다. 고친 뒤 다시 끝내라.\n" + out[-3000:], file=sys.stderr)
    sys.exit(2)
