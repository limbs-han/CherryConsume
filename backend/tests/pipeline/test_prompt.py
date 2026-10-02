"""추출 프롬프트와 답 형식. 설계 1절 4단계."""

import json
from datetime import date

import pytest

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


def test_field_guide_names_the_real_fields():
    # 2026-10-02 운영 채점에서 모델이 when.amount.max, when.days, target.region 같은 없는 칸을 지어냈다
    from cherry_core.pipeline.prompt import field_guide

    guide = field_guide()
    assert "AmountRange: min, below" in guide
    assert "channel(online|offline)" in guide
    assert "day(Days)" in guide and "Days: in(" in guide
    assert "Target: all, categories, merchants, exclude_categories, exclude_merchants" in guide
    assert "type(billing_discount|onsite_discount|points|cashback)" in guide
    # Rules에서 닿는 모델은 모두 나온다. 한도 조정과 맨 위 칸도 빠지지 않는다
    for name in ("Rules", "SharedLimit", "Adjust", "PerUnit", "CardMonth", "CancellationOverride", "Option", "Fact"):
        assert any(line.startswith(f"{name}: ") for line in guide.splitlines()), name


def test_prompt_shows_current_limit_keys_only(make_catalog):
    # 공유 한도 이름은 정답을 만든 사람이 지은 것이다. 알려 주지 않으면 금액이 맞아도 다른 한도가 된다
    # 2026-10-02 판 4에서 key와 기간을 주었더니 모델이 그 모양을 베껴 금액 없는 한도를 적었다. 기간은 정답도 샌다
    card = FILES["cards/shinhan/shinhan-test.yaml"]
    current = {"limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000}}], "benefits": []}
    prompt = build_prompt(card, current, [], catalog_codes(load_catalog(make_catalog())))
    line = next(x for x in prompt.splitlines() if x.startswith("지금 한도"))
    assert line == "지금 한도 key: integrated"
    assert "칸 안내." in prompt


@pytest.mark.parametrize(
    "text",
    [
        '```json\n{"rules": {}, "effective_from": null, "source": "page"}\n```',
        '답은 아래와 같다.\n{"rules": {}, "effective_from": null, "source": "page"}',
    ],
)
def test_parse_answer_strips_text_around_the_json(text):
    # 2026-10-02 qwen 답 두 장이 JSON으로 시작하지 않아 읽지 못했다
    assert parse_answer(text)["source"] == "page"


def test_parse_answer_refuses_two_objects():
    # 앞뒤 글을 걷어 낼 때 객체 둘을 하나로 읽지 않는다. 읽지 못한 답은 사람이 정할 것으로 간다
    with pytest.raises(json.JSONDecodeError):
        parse_answer('{"rules": {}} 그리고 {"rules": {}}')


def test_second_ask_shows_the_previous_answer_and_each_error():
    # 2026-10-02 판 7. 형식 검사에 걸린 카드만 이전 답과 오류를 붙여 한 번 더 묻는다
    from cherry_core.pipeline.prompt import retry_prompt

    errors = ["limits.0: Value error, amount, count, base 중 하나 이상을 쓴다", "spend.installment: Field required"]
    text = retry_prompt("처음 프롬프트", '{"rules": {}}', errors)
    assert text.startswith("처음 프롬프트\n\n")
    assert '<이전 답>\n{"rules": {}}\n</이전 답>' in text
    assert text.endswith("\n- " + errors[0] + "\n- " + errors[1])


def test_instructions_explain_ranked_cancellation():
    # 2026-10-02 E55 검토. 칸 이름이 spend.cancellation과 같아 모델이 실적 규칙을 베낄 수 있다
    from cherry_core.pipeline.prompt import INSTRUCTIONS

    assert (
        "- ranked의 cancellation은 순위 영역 이용금액의 취소를 어느 달에 반영하는지다. "
        "원문에 순위 영역의 취소를 따로 적었을 때만 쓰고, spend.cancellation을 옮겨 적지 않는다.\n"
    ) in INSTRUCTIONS
