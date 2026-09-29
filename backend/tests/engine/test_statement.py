"""사용자 IBK 나라사랑 이용대금명세서 대조. 설계 6.6. 입력은 tests/engine/local/에만 있고 저장소에 올리지 않는다.
파일이 없는 PC에서는 건너뛴다. 형식은 cases.py와 같고, 엔진과 다른 결제에는 difference에 까닭을 적는다."""

from pathlib import Path

import pytest

from cherry_core.catalog.load import load_catalog
from cherry_core.engine import Engine

from .cases import load_cases, mismatches

LOCAL = Path(__file__).parent / "local"
ROOT = Path(__file__).resolve().parents[3] / "catalog"
CASES = load_cases(LOCAL) if LOCAL.exists() else []


@pytest.mark.skipif(not CASES, reason="명세서 입력이 없는 PC")
def test_statement_matches_engine():
    eng = Engine(load_catalog(ROOT))
    problems = {c.name: mismatches(eng, c) for c in CASES}
    assert {k: v for k, v in problems.items() if v} == {}
