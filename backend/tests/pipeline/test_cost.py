"""비용 차단 금액. 설계 4절 8번과 9번. 가입일 2026-10-05로 손으로 센 날짜다."""

from datetime import date
from decimal import Decimal

import pytest

from cherry_core.pipeline.cost import guard_changes, is_over, spend_window

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


def job(target="prod", schedule="UNPAUSED", trigger=None, **tags):
    settings = {"name": "ingest", "tags": {"cherry_guard": target, **tags} if target else dict(tags)}
    if schedule:
        settings["schedule"] = {
            "quartz_cron_expression": "0 0 3 * * ?",
            "timezone_id": "Asia/Seoul",
            "pause_status": schedule,
        }
    if trigger:
        settings["trigger"] = {"file_arrival": {"url": "/Volumes/x"}, "pause_status": trigger}
    return settings


def test_over_limit_pauses_guarded_job_and_marks_it():
    assert guard_changes(job(), "prod", over=True) == {
        "schedule": {"quartz_cron_expression": "0 0 3 * * ?", "timezone_id": "Asia/Seoul", "pause_status": "PAUSED"},
        "tags": {"cherry_guard": "prod", "cherry_guard_paused": "schedule"},
    }


def test_over_limit_pauses_schedule_and_trigger_together():
    new = guard_changes(job(trigger="UNPAUSED"), "prod", over=True)
    assert (new["schedule"]["pause_status"], new["trigger"]["pause_status"]) == ("PAUSED", "PAUSED")
    assert new["tags"]["cherry_guard_paused"] == "schedule-trigger"


def test_other_target_untagged_and_already_paused_are_left_alone():
    assert guard_changes(job(target="dev"), "prod", over=True) is None
    assert guard_changes(job(target=None), "prod", over=True) is None
    assert guard_changes(job(schedule="PAUSED"), "prod", over=True) is None  # 사람이 멈춘 작업


def test_under_limit_resumes_only_what_the_guard_paused():
    paused = job(schedule="PAUSED", trigger="PAUSED", cherry_guard_paused="schedule")
    assert guard_changes(paused, "prod", over=False) == {
        "schedule": {"quartz_cron_expression": "0 0 3 * * ?", "timezone_id": "Asia/Seoul", "pause_status": "UNPAUSED"},
        "tags": {"cherry_guard": "prod"},
    }  # 트리거는 사람이 멈춘 것이라 그대로 둔다


def test_under_limit_leaves_unmarked_jobs():
    assert guard_changes(job(schedule="PAUSED"), "prod", over=False) is None
    assert guard_changes(job(), "prod", over=False) is None


@pytest.mark.parametrize(
    ("spent", "unpriced", "over"),
    [
        ("29.99", 0, False),
        ("30.00", 0, False),  # 설계 4절 8번은 "30달러를 넘으면"이라 같으면 아직 아니다
        ("30.01", 0, True),
        ("0", 1, True),  # 가격을 모르는 사용량이 있으면 쓴 금액을 모르니 넘은 것으로 본다
    ],
)
def test_is_over(spent, unpriced, over):
    assert is_over(Decimal(spent), Decimal(30), unpriced) is over


def test_missing_pause_status_counts_as_running():
    settings = job()
    del settings["schedule"]["pause_status"]
    assert guard_changes(settings, "prod", over=True)["schedule"]["pause_status"] == "PAUSED"


def test_marker_is_merged_not_overwritten():
    # 한도를 넘은 동안 사람이 예약만 다시 켰다. 트리거 표시가 지워지면 새 달에 트리거를 영영 못 켠다
    settings = job(schedule="UNPAUSED", trigger="PAUSED", cherry_guard_paused="schedule-trigger")
    assert guard_changes(settings, "prod", over=True)["tags"]["cherry_guard_paused"] == "schedule-trigger"
