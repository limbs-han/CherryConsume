"""combined 사본으로 앱 카탈로그 JSON을 만들고 실제 Dart 엔진으로 새 카드, 기존 카드, 교육비 연결 사례를 돌린다.

package.py가 읽는 combined/new-tests.json, existing-tests.json, school-tests.json을 쓴다. 2026-10-10 expand1 합치기에서 만들었다.
"""

import json
import shutil
import subprocess
from pathlib import Path

from cherry_core.catalog.app_json import app_catalog
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import load_catalog

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
OUT = BASE / "combined"

cat = load_catalog(OUT / "catalog")
problems = check_catalog(cat)
print("오류", [str(p) for p in problems if p.level == "error"])
print("경고", [str(p) for p in problems if p.level == "warning"])
(OUT / "catalog.json").write_text(
    json.dumps(app_catalog(cat), ensure_ascii=False), encoding="utf-8"
)


def run(name, cases, *extra):
    r = subprocess.run(
        [
            shutil.which("dart") or "dart",
            f"--packages={ROOT / 'app/.dart_tool/package_config.json'}",
            str(BASE / "check_engine.dart"),
            str(OUT / "catalog.json"),
            str(cases),
            *extra,
        ],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=ROOT,
    )
    line = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""
    print(name, line[:500], r.stderr[-500:])
    (OUT / f"{name}.json").write_text(line + "\n", encoding="utf-8")


run("new-tests", OUT / "cases")
run("existing-tests", ROOT / "app/test/engine/cases")
run("school-tests", OUT / "school-cases", "skip-benefit-coverage")
