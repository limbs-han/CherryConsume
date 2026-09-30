"""비용 차단 금액. 설계 4절 8번과 9번. 가입일 2026-10-05로 손으로 센 날짜다."""

from datetime import date
from decimal import Decimal

import pytest

from cherry_core.pipeline.cost import spend_window

SIGNUP = date(2026, 10, 5)


@pytest.mark.parametrize(
    ("today", "start", "limit"),
    [
        (date(2026, 10, 5), date(2026, 10, 5), 400),  # 체험 1일째
        (date(2026, 10, 18), date(2026, 10, 5), 400),  # 체험 14일째
        (date(2026, 10, 19), date(2026, 10, 19), 30),  # 15일째. 체험 중 쓴 금액은 넣지 않는다
        (date(2026, 10, 31), date(2026, 10, 19), 30),
        (date(2026, 11, 1), date(2026, 11, 1), 30),  # 새 달
    ],
)
def test_spend_window(today, start, limit):
    assert spend_window(today, SIGNUP) == (start, Decimal(limit))


def test_trial_across_months():
    signup = date(2026, 9, 25)
    assert spend_window(date(2026, 10, 2), signup) == (signup, Decimal(400))
    assert spend_window(date(2026, 10, 9), signup) == (date(2026, 10, 9), Decimal(30))
