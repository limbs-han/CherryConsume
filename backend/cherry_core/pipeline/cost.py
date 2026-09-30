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


def is_over(spent: Decimal, limit: Decimal, unpriced: int) -> bool:
    """차단할지. 설계 4절 8번 "30달러를 넘으면"이라 한도와 같은 금액은 아직 넘지 않았다.

    가격을 찾지 못한 사용량이 있으면 쓴 금액을 모르는 것이라 넘은 것으로 본다.
    """
    return spent > limit or unpriced > 0


GUARD_TAG = "cherry_guard"  # 값은 번들 대상 이름. 차단 작업은 자기 대상의 작업만 건드린다
PAUSED_TAG = "cherry_guard_paused"  # 차단 작업이 멈춘 칸 이름. 이 표시가 있는 칸만 다시 켠다
PAUSABLE = ("schedule", "trigger", "continuous")


def guard_changes(settings: dict, target: str, over: bool) -> dict | None:
    """작업 설정 하나에서 바꿀 칸을 돌려준다. 바꿀 것이 없으면 None.

    한도를 넘었으면 이 대상의 작업 중 켜진 예약과 트리거를 멈추고 멈춘 칸을 표시한다.
    한도 밑이면 표시된 칸만 다시 켠다. 사람이 멈춘 칸은 표시가 없어 건드리지 않는다.
    """
    tags = settings.get("tags") or {}
    if tags.get(GUARD_TAG) != target:
        return None
    if over:
        # pause_status가 빠진 칸은 켜진 것이다. 그래서 PAUSED가 아닌 것을 모두 멈춘다
        keys = [k for k in PAUSABLE if settings.get(k) and settings[k].get("pause_status") != "PAUSED"]
        if not keys:
            return None
        # 앞서 멈춘 칸의 표시는 남긴다. 덮어쓰면 그 칸을 새 달에 다시 켜지 못한다
        marked = set(keys) | set(tags.get(PAUSED_TAG, "").split("-"))
        return {
            **{k: {**settings[k], "pause_status": "PAUSED"} for k in keys},
            "tags": {**tags, PAUSED_TAG: "-".join(k for k in PAUSABLE if k in marked)},
        }
    if PAUSED_TAG not in tags:
        return None
    keys = [k for k in tags[PAUSED_TAG].split("-") if settings.get(k)]
    rest = {k: v for k, v in tags.items() if k != PAUSED_TAG}
    return {**{k: {**settings[k], "pause_status": "UNPAUSED"} for k in keys}, "tags": rest}
