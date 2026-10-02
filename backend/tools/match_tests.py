"""Python 시험 함수 이름과 Dart 시험 이름을 맞춰 빠진 것을 찾는다. 작업 006 설계 3절, 계획 단계 2의 7

돌리기: uv run --project backend python backend/tools/match_tests.py backend/tests/engine app/test/engine
Python은 test_*.py의 `def test_...`, Dart는 *_test.dart의 `test(`, `testWidgets(`, `group(` 이름 첫머리의 `test_...`를 센다. 매개변수를 붙인 `'test_x $way'`는 test_x다.
Python 엔진을 지우기 전에 빠짐 0이어야 한다. 빠진 것이 있으면 이름을 알리고 1로 끝난다.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# 일부러 옮기지 않은 시험과 그 까닭
SKIP = {
    "test_engine_refuses_catalog_with_rule_errors": "앱은 규칙을 다시 검사하지 않는다. backend/tests/catalog/test_app_json.py로 옮겼다",
}

PY = re.compile(r"^\s*(?:async\s+)?def (test_\w+)", re.MULTILINE)
DART = re.compile(r"\b(?:test|testWidgets|group)\(\s*'(test_\w+)")


def names(root: Path, glob: str, pattern: re.Pattern) -> set[str]:
    return {n for f in root.rglob(glob) for n in pattern.findall(f.read_text(encoding="utf-8"))}


def main(py_dir: str, dart_dir: str) -> int:
    py = names(Path(py_dir), "test_*.py", PY)
    dart = names(Path(dart_dir), "*_test.dart", DART)
    missing = sorted(py - dart - SKIP.keys())
    extra = sorted(dart - py)
    print(f"Python {len(py)}개, Dart {len(dart)}개, 일부러 뺀 것 {len(SKIP.keys() & py)}개")
    for n in missing:
        print(f"Dart에 없다: {n}")
    for n in extra:
        print(f"Python에 없다: {n}")
    if not missing:
        print("빠짐 0")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
