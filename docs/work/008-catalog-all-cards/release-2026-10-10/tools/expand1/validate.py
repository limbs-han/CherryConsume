"""expand1 사본 검사. 카탈로그 검사, 앱 카탈로그 JSON 만들기, 손계산 사례를 실제 Dart 엔진으로 돌리기.

저장소 루트에서 `uv run --project backend python tmp/release-card-expansion/expand1/validate.py [카드 id ...]`.
카드 id를 주면 그 카드의 사례만 돌린다. needed_common.json이 있으면 공통 가맹점과 업종 제안을 메모리에서만 합친다.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

from cherry_core.catalog.app_json import app_catalog
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.models import CategoryChild, Merchant

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]


def main(only):
    cat = load_catalog(BASE / "catalog")
    # 카드마다 needed/<카드>.json에 공통 가맹점과 업종 제안을 둔다. 같은 key는 한 번만 합친다
    needed, seen = [], set()
    for f in sorted((BASE / "needed").glob("*.json")):
        for item in json.loads(f.read_text(encoding="utf-8")):
            d = item["definition"]
            key = (item["file"], d.get("key") or f"{d.get('parent')}.{d.get('code')}")
            if key not in seen:
                seen.add(key)
                needed.append(item)
    for item in needed:
        d = item["definition"]
        if item["file"] == "merchants.yaml":
            cat.merchants[d["key"]] = Merchant.model_validate(d)
        else:
            parent = next(c for c in cat.category_tree if c.code == d["parent"])
            parent.children.append(
                CategoryChild.model_validate({"code": d["code"], "name": d["name"]})
            )
            cat.categories.add(d["parent"] + "." + d["code"])
    problems = check_catalog(cat)
    out = {
        "errors": [str(p) for p in problems if p.level == "error"],
        "warnings": [str(p) for p in problems if p.level == "warning"],
    }
    (BASE / "catalog.json").write_text(
        json.dumps(app_catalog(cat), ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(out, ensure_ascii=False, indent=1))
    cases = BASE / "cases"
    if only:
        # 여러 에이전트가 함께 돌려도 겹치지 않게 카드 묶음마다 폴더를 따로 둔다
        cases = BASE / ("cases-run-" + "-".join(sorted(only)))
        cases.mkdir(exist_ok=True)
        for f in cases.glob("*.yaml"):
            f.unlink()
        for card in only:
            src = BASE / "cases" / f"{card}.yaml"
            (cases / src.name).write_text(
                src.read_text(encoding="utf-8"), encoding="utf-8"
            )
    run = subprocess.run(
        [
            shutil.which("dart") or "dart",
            f"--packages={ROOT / 'app/.dart_tool/package_config.json'}",
            str(BASE.parent / "check_engine.dart"),
            str(BASE / "catalog.json"),
            str(cases),
        ],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=ROOT,
    )
    print(run.stdout[-4000:], run.stderr[-2000:])
    sys.exit(1 if out["errors"] or run.returncode else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
