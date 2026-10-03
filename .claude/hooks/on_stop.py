"""Claude가 끝내기 전에 계산 코드가 바뀌었으면 테스트를 돌린다. 실패하면 exit 2로 계속 고치게 한다.

backend가 바뀌면 카탈로그와 파이프라인 pytest를, 앱의 계산 엔진이나 폰 저장소가 바뀌면 그 Dart 시험을 돌린다.
엔진은 작업 006에서 Dart로 옮겼다. 2026-10-03 사용자가 정했다
"""

import json
import os
import pathlib
import shutil
import subprocess
import sys

sys.stderr.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(
    os.environ.get("CLAUDE_PROJECT_DIR") or pathlib.Path(__file__).resolve().parents[2]
)

data = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
if data.get("stop_hook_active"):
    sys.exit(0)  # 이미 한 번 막았다


def run(cmd, cwd=ROOT):
    r = subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env={**os.environ, "PYTHONUTF8": "1"},
        check=False,
    )
    return r.returncode, (r.stdout + r.stderr).strip()


def changed(*paths):
    return run(["git", "status", "--porcelain", "--", *paths])[1]


fails = []
if (ROOT / "backend" / "pyproject.toml").exists() and changed("backend"):
    code, out = run(["uv", "run", "--project", "backend", "pytest", "-q", "-x"])
    if code:
        fails.append("backend 테스트가 실패했다.\n" + out[-3000:])
# flutter는 Windows에서 .bat라 전체 경로로 부른다
flutter = shutil.which("flutter")
if flutter and changed(
    "app/lib/engine", "app/lib/store", "app/test/engine", "app/test/store"
):
    code, out = run([flutter, "test", "test/engine", "test/store"], cwd=ROOT / "app")
    if code:
        fails.append("앱 계산 엔진과 저장소 시험이 실패했다.\n" + out[-3000:])
if fails:
    print("\n\n".join(fails) + "\n고친 뒤 다시 끝내라.", file=sys.stderr)
    sys.exit(2)
