"""한 달 비용 차단 금액. 설계 4절 8번과 9번. 달러 금액은 Decimal로 다룬다."""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

TRIAL_DAYS = 14
TRIAL_LIMIT = Decimal(400)
MONTH_LIMIT = Decimal(30)


def spend_window(today: date, signup: date) -> tuple[date, Decimal]:
    """(합산을 시작하는 날, 차단 금액).

    체험 14일은 가입한 날부터 합산해 400달러에서 멈춘다. 그 뒤로는 달마다 30달러다.
    체험 크레딧으로 쓴 금액은 체험이 끝난 달의 30달러에 넣지 않는다.
    """
    trial_end = signup + timedelta(days=TRIAL_DAYS)
    if today < trial_end:
        return signup, TRIAL_LIMIT
    return max(today.replace(day=1), trial_end), MONTH_LIMIT
