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
    # 서버 시험 가운데 폰에서 할 일이 없는 것. 작업 006 설계 4절 "시험"
    "test_unknown_field_is_422": "모르는 칸 막기는 바깥 요청을 막던 것이라 옮기지 않는다",
    "test_no_request_field_looks_like_a_card_number": "표 칸 이름 시험으로 바꿨다. app/test/store/db_test.dart",
    "test_cards_are_per_user": "사용자가 한 명이다",
    "test_same_client_id_saves_once": "같은 번호 다시 보내기 E24는 서버가 없어 필요 없다",
    "test_catalog_is_in_tables": "카탈로그 표가 없다. 메모리의 카탈로그가 대신한다",
    "test_catalog_sync_twice_changes_nothing": "카탈로그 표가 없다. 메모리의 카탈로그가 대신한다",
    "test_changed_revision_adds_a_row": "카탈로그 표가 없다. 메모리의 카탈로그가 대신한다",
    "test_payment_catalog_tables": "카탈로그 표가 없다. 메모리의 카탈로그가 대신한다",
    "test_moved_alias_follows_the_catalog": "카탈로그 표가 없다. 메모리의 카탈로그가 대신한다",
    "test_revision_changed_and_changed_back": "카탈로그 표가 없다. 메모리의 카탈로그가 대신한다",
    "test_changed_migration_stops_the_server": "표 정의는 코드의 목록이다. 출시하면 낸 SQL의 지문을 시험에 박는다",
    "test_migration_number_rules": "표 정의는 코드의 목록이라 번호가 목록 순서다",
    "test_every_table_has_row_security": "Supabase가 없다",
    "test_dev_login_is_missing_when_off": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_dev_login_reads_the_env": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_dev_login_only_on_a_local_db": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_dev_tokens_end_when_dev_login_is_off": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_api_docs_only_in_dev": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_same_name_is_same_user": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_token_is_not_stored": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_no_token_is_401": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_logged_out_token_is_401": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_expired_token_is_401": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_deleted_user_is_401_at_once": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_kakao_first_login_makes_a_user_and_again_finds_it": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_bad_tokens_are_401_and_a_down_provider_is_502": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_same_person_with_kakao_and_google_is_two_users": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_withdraw_blocks_at_once_and_purges_after_30_days": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_purge_also_drops_expired_sessions": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
    "test_not_configured_is_503": "로그인과 탈퇴, 개발용 로그인, 세션이 없다",
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
