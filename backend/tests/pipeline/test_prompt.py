"""추출 프롬프트와 답 형식. 설계 1절 4단계."""

import json
from datetime import date

from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.prompt import build_prompt, catalog_codes, parse_answer, response_schema
from tests.catalog.conftest import FILES


def test_schema_is_json_with_rules_and_shared_defs():
    fmt = response_schema()
    schema = fmt["json_schema"]["schema"]
    json.dumps(fmt)
    assert {"tiers", "spend", "benefits"} <= set(schema["properties"]["rules"]["properties"])
    assert "$defs" not in schema["properties"]["rules"]
    assert {"Benefit", "Condition", "OpenQuestion"} <= set(schema["$defs"])


def test_prompt_has_current_keys_codes_and_documents(make_catalog):
    card = FILES["cards/shinhan/shinhan-test.yaml"]
    current = {"benefits": [{"key": "cafe-10", "title": "카페 10% 할인"}]}
    codes = catalog_codes(load_catalog(make_catalog()))
    prompt = build_prompt(card, current, [("page", "카페 10% 할인\n월 최대 1만원")], codes)
    assert '"key": "cafe-10"' in prompt
    assert "가맹점: starbucks(스타벅스)" in prompt
    assert '<원문 id="page">\n카페 10% 할인\n월 최대 1만원\n</원문>' in prompt


def test_parse_answer_turns_date_text_into_date():
    answer = {"rules": {}, "effective_from": "2026-11-01", "source": "page", "open_questions": []}
    assert parse_answer(json.dumps(answer))["effective_from"] == date(2026, 11, 1)
    assert parse_answer(json.dumps({**answer, "effective_from": None}))["effective_from"] is None


def test_parse_answer_treats_null_as_not_written():
    rules = {"tiers": [0], "new_card": None, "benefits": [{"key": "a", "valid_until": None}]}
    answer = {"rules": rules, "effective_from": None, "source": "page", "open_questions": []}
    assert parse_answer(json.dumps(answer))["rules"] == {"tiers": [0], "benefits": [{"key": "a"}]}
