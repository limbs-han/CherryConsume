"""추출 프롬프트와 답 형식. 설계 1절 4단계."""

import json
from datetime import date

from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.prompt import RESPONSE_FORMAT, answer_schema, build_prompt, catalog_codes, parse_answer
from tests.catalog.conftest import FILES


def test_schema_is_json_with_rules_and_shared_defs():
    schema = answer_schema()
    json.dumps(schema)
    assert {"tiers", "spend", "benefits"} <= set(schema["properties"]["rules"]["properties"])
    assert "$defs" not in schema["properties"]["rules"]
    assert {"Benefit", "Condition", "OpenQuestion"} <= set(schema["$defs"])


def test_answer_is_json_only_and_schema_goes_in_the_prompt(make_catalog):
    # 2026-10-01 구조화 출력이 $ref, anyOf, 64개 넘는 키를 받지 않아 JSON만 강제하고 형식은 글로 준다
    assert json.loads(RESPONSE_FORMAT) == {"type": "json_object"}
    card = FILES["cards/shinhan/shinhan-test.yaml"]
    prompt = build_prompt(card, {}, [], catalog_codes(load_catalog(make_catalog())))
    assert json.dumps(answer_schema(), ensure_ascii=False, separators=(",", ":")) in prompt


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


def test_example_is_another_tune_card_with_its_rules():
    # 2026-10-01 개발용 시험에서 형식 오류가 11장 중 9장이었다. 다른 카드의 규칙을 모양 예시로 넣는다
    from pathlib import Path

    from cherry_core.pipeline.prompt import EXAMPLE_CARDS, example_for
    from cherry_core.pipeline.seed import TEST_CARDS

    cat = load_catalog(Path(__file__).resolve().parents[3] / "catalog")
    assert not set(EXAMPLE_CARDS) & TEST_CARDS  # 채점 전용 카드는 예시로 쓰지 않는다
    # 같은 카드사 카드는 규칙이 닮아 예시를 베끼면 채점 점수가 부푼다
    assert not {cat.cards[c].card.issuer for c in EXAMPLE_CARDS} & {cat.cards[c].card.issuer for c in TEST_CARDS}
    name, rules, tag = example_for(cat, "shinhan-cheoeum")
    assert tag.startswith(f"{EXAMPLE_CARDS[0]}@{cat.cards[EXAMPLE_CARDS[0]].revisions[-1][0].effective_from}#")
    assert rules["benefits"]
    assert name == cat.cards[EXAMPLE_CARDS[0]].card.name
    assert {b["key"] for b in rules["benefits"]} == {
        b.key for b in cat.cards[EXAMPLE_CARDS[0]].revisions[-1][1].benefits
    }
    assert example_for(cat, EXAMPLE_CARDS[0])[0] == cat.cards[EXAMPLE_CARDS[1]].card.name  # 자기 자신은 예시가 아니다


def test_prompt_shows_the_example_as_shape_only(make_catalog):
    card = FILES["cards/shinhan/shinhan-test.yaml"]
    codes = catalog_codes(load_catalog(make_catalog()))
    example = ("예시카드", {"tiers": [0, 300000], "benefits": [{"key": "x"}]})
    prompt = build_prompt(card, {}, [], codes, example)
    assert "형식 예시. 다른 카드 예시카드의 규칙이다. 값은 따라 하지 말고 모양만 본다." in prompt
    assert '{"tiers": [0, 300000], "benefits": [{"key": "x"}]}' in prompt
    assert "형식 예시" not in build_prompt(card, {}, [], codes)


def test_every_example_is_valid_rules():
    # 예시가 형식에 맞지 않으면 모델이 따라 하다 형식 오류를 낸다
    from pathlib import Path

    from cherry_core.catalog.models import Rules
    from cherry_core.pipeline.draft import int_keys
    from cherry_core.pipeline.prompt import example_for

    cat = load_catalog(Path(__file__).resolve().parents[3] / "catalog")
    for cid in cat.cards:
        Rules.model_validate(int_keys(json.loads(json.dumps(example_for(cat, cid)[1], default=str))))
