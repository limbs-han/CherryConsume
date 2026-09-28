"""파일을 고친 직후 검사. 실패하면 exit 2로 오류를 Claude에게 돌려준다."""
import json, os, pathlib, subprocess, sys

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(os.environ.get("CLAUDE_PROJECT_DIR") or pathlib.Path(__file__).resolve().parents[2])
ENV = {**os.environ, "PYTHONUTF8": "1"}


def run(cmd):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=ENV)
    return r.returncode, (r.stdout + r.stderr).strip()


data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
path = (data.get("tool_input") or {}).get("file_path")
if not path:
    sys.exit(0)
try:
    rel = pathlib.Path(path).resolve().relative_to(ROOT.resolve()).as_posix()
except ValueError:
    sys.exit(0)  # 저장소 밖 파일은 검사하지 않는다

problems = []
if rel.startswith("catalog/") and rel.endswith((".yaml", ".yml")):
    code, out = run(["uv", "run", "--script", "tools/validate_catalog.py"])
    if code:
        problems.append("카탈로그 검증 실패\n" + out[-3000:])
elif rel.endswith(".py"):
    # ponytail: ruff 버전을 고정하지 않음. backend가 생기면 dev 의존성으로 고정하고 그 버전을 쓴다
    run(["uvx", "ruff", "format", "--quiet", rel])
    code, out = run(["uvx", "ruff", "check", "--fix", "--quiet", rel])
    if code:
        problems.append("ruff 검사 실패\n" + out[-3000:])

if problems:
    print("\n\n".join(problems), file=sys.stderr)
    sys.exit(2)
