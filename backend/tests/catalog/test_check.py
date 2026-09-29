"""교차 검사. 설계 4.2 표의 검사마다 한 곳만 틀린 카탈로그를 만들어 실패 위치를 확인한다."""

import pytest

from .conftest import benefit, problems_of, rev

CARD = "cards/shinhan/shinhan-test.yaml"
R = "revisions@2026-07-01."


def set_tiers(f):
    rev(f)["tiers"] = [100, 300000, 500000]


def table_key_not_in_tiers(f):
    rev(f)["limits"][0]["amount"] = {300000: 10000, 400000: 20000}


def table_starts_too_high(f):
    rev(f)["limits"][0]["amount"] = {500000: 20000}


def tier_from_not_in_tiers(f):
    benefit(f)["tiers"] = {"from": 250000}


def tier_from_after_to(f):
    benefit(f)["tiers"] = {"from": 500000, "to": 300000}


def unknown_category(f):
    benefit(f)["target"] = {"categories": ["bakery"]}


def unknown_merchant(f):
    benefit(f)["target"] = {"merchants": ["nowhere"]}


def unknown_payment(f):
    benefit(f)["when"] = [{"payment": ["zero_pay"]}]


def unknown_option(f):
    benefit(f)["when"] = [{"option": {"package": ["p1"]}}]


def unknown_choice(f):
    rev(f)["options"] = [
        {"key": "package", "title": "패키지", "change": "immediate", "choices": [{"key": "p1", "title": "1"}]}
    ]
    benefit(f)["when"] = [{"option": {"package": ["p9"]}}]


def unknown_fact(f):
    benefit(f)["when"] = [{"fact": "soldier"}]


def month_fact_as_condition(f):
    rev(f)["facts"] = [{"key": "birth_month", "type": "month", "scope": "user", "ask": "생일이 몇 월인가요"}]
    benefit(f)["when"] = [{"fact": "birth_month"}]


def ranked_with_one_member(f):
    rev(f)["ranked"] = [{"key": "top-area", "top": 1}]
    benefit(f)["when"] = [{"ranked": "top-area"}]


def month_total_on_txn_reward(f):
    benefit(f)["when"] = [{"month_total": {"min": 50000}}]


def unknown_program(f):
    benefit(f)["reward"] = {"type": "points", "program": "nope_point", "rate": 1}


def missing_shared(f):
    benefit(f)["limits"][1] = {"shared": "weekend"}


def undefined_stack(f):
    benefit(f)["stack"] = "pay"


def priority_order_incomplete(f):
    rev(f)["stacks"] = [{"key": "main", "pick": "priority", "order": [], "spill": "split"}]


def unknown_source(f):
    benefit(f)["source"] = "pdf"


def unknown_revision_source(f):
    rev(f)["source"] = "pdf"


def duplicate_benefit_key(f):
    rev(f)["benefits"].append(dict(benefit(f)))


def open_question_bad_path(f):
    f[CARD]["open_questions"] = [{"path": "revisions[0].spend.cancellation", "question": "취소 반영 달"}]


def id_differs_from_file(f):
    f[CARD]["id"] = "shinhan-other"


def issuer_missing(f):
    del f["issuers/shinhan.yaml"]


def merchant_unknown_category(f):
    f["merchants.yaml"][0]["category"] = "coffee"


def billing_cycle_basis(f):
    f["issuers/shinhan.yaml"]["defaults"][0]["spend"]["basis"] = "billing_cycle"


def per_liter_without_price(f):
    f["reference.yaml"] = []
    benefit(f)["reward"] = {"type": "billing_discount", "per_liter": 60}


CASES = [
    (set_tiers, R + "tiers"),
    (table_key_not_in_tiers, R + "limits[integrated].amount: 구간표 키 [400000]"),
    (table_starts_too_high, R + "limits[integrated].amount: 구간표의 가장 작은 키"),
    (tier_from_not_in_tiers, R + "benefits[cafe-10].tiers.from"),
    (tier_from_after_to, R + "benefits[cafe-10].tiers: from은 to 이하"),
    (unknown_category, R + "benefits[cafe-10].target: 업종 ['bakery']"),
    (unknown_merchant, R + "benefits[cafe-10].target: 가맹점 ['nowhere']"),
    (unknown_payment, R + "benefits[cafe-10].when[0].payment"),
    (unknown_option, R + "benefits[cafe-10].when[0].option: 옵션 package가 없다"),
    (unknown_choice, R + "benefits[cafe-10].when[0].option: 옵션 package에 선택지 ['p9']"),
    (unknown_fact, R + "benefits[cafe-10].when[0].fact"),
    (month_fact_as_condition, R + "benefits[cafe-10].when[0].fact: 사실 birth_month는 bool"),
    (ranked_with_one_member, R + "ranked[top-area]: 이 조건을 단 혜택이 둘 이상"),
    (month_total_on_txn_reward, R + "benefits[cafe-10].when[0].month_total"),
    (unknown_program, R + "benefits[cafe-10].reward.program"),
    (missing_shared, R + "benefits[cafe-10].limits[1].shared"),
    (undefined_stack, R + "benefits[cafe-10].stack"),
    (priority_order_incomplete, R + "stacks[main].order"),
    (unknown_source, R + "benefits[cafe-10].source"),
    (unknown_revision_source, R + "source"),
    (duplicate_benefit_key, R + "benefits: key가 겹친다"),
    (open_question_bad_path, CARD.removeprefix("") + ": open_questions"),
    (id_differs_from_file, ": id: 파일 이름"),
    (issuer_missing, ": issuer: issuers/shinhan.yaml이 없다"),
    (merchant_unknown_category, "merchants.yaml: [starbucks].category"),
    (billing_cycle_basis, R + "spend.basis"),
    (per_liter_without_price, R + "benefits[cafe-10].reward.per_liter"),
]


@pytest.mark.parametrize(("edit", "expected"), CASES, ids=[c[0].__name__ for c in CASES])
def test_each_check_reports_its_place(make_catalog, edit, expected):
    errors = problems_of(make_catalog(edit))
    assert any(expected in e for e in errors), errors


def test_open_question_path_by_key(make_catalog):
    def edit(f):
        f[CARD]["open_questions"] = [{"path": "revisions[0].benefits[cafe-10].reward.rate", "question": "비율"}]

    assert problems_of(make_catalog(edit)) == []


def test_non_canonical_file_is_an_error(make_catalog):
    root = make_catalog()
    path = root / CARD
    path.write_text(
        path.read_text(encoding="utf-8").replace("schema_version: 2\n", "") + "schema_version: 2\n", encoding="utf-8"
    )
    assert any("저장 형식이 아니다" in e for e in problems_of(root))
