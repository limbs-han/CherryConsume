"""한 달 비용이 한도를 넘으면 cherry_guard 작업을 멈추고 SQL 웨어하우스와 앱을 끈다. 설계 4절 8번과 9번.

6시간마다 작업 cherry_cost_guard로 돈다. 한도 밑으로 돌아오면 이 작업이 멈춘 예약과 트리거만 다시 켠다.
청구 기록은 보통 12시간 늦게 들어오고 새 작업 공간은 더 늦어서, 한도를 넘긴 순간이 아니라 기록이 들어온 뒤에 멈춘다.
가격을 찾지 못한 사용량이 있거나 청구 기록을 읽지 못하면 쓴 금액을 모르는 것이라 멈춘다. Genie 무료 사용량은 세지 않는다.
그때와 한도를 넘어 새로 멈춘 때, 무엇 하나 멈추지 못한 때는 실행을 실패로 끝내 알림 메일이 가게 한다.
찍는 것은 합산 시작일, 쓴 금액, 한도, 멈춤 여부와 개수뿐이다.
"""

import argparse
from datetime import UTC, date, datetime
from decimal import Decimal

from cherry_core.pipeline.cost import GUARD_TAG, guard_changes, is_over, spend_window
from databricks.sdk import WorkspaceClient
from pyspark.sql import SparkSession

# 가격 행이 없거나 가격 칸이 비면 곱이 NULL이라 합계에서 빠진다. 그런 사용량은 unpriced로 센다
# GENIE_FREE_USAGE는 공식 문서상 무료이고 가격 행이 없어 unpriced로 세지 않는다. 설계 4절 8번
# 합계에서는 빼지 않아 나중에 가격이 붙으면 쓴 금액에 들어간다. <=>는 sku_name이 NULL인 행도 세게 한다
SPENT = """
SELECT
  coalesce(sum(u.usage_quantity * p.pricing.effective_list.default), 0) AS spent,
  count_if(p.pricing.effective_list.default IS NULL AND NOT (u.sku_name <=> 'GENIE_FREE_USAGE')) AS unpriced
FROM system.billing.usage u
LEFT JOIN system.billing.list_prices p
  ON u.sku_name = p.sku_name AND u.cloud = p.cloud AND u.usage_unit = p.usage_unit
 AND u.usage_end_time >= p.price_start_time
 AND (p.price_end_time IS NULL OR u.usage_end_time < p.price_end_time)
 AND p.currency_code = 'USD'
WHERE u.usage_date >= :start
"""
WAREHOUSE_OFF = {"STOPPED", "STOPPING", "DELETED", "DELETING"}
APP_ON = {"ACTIVE", "STARTING", "UPDATING"}


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--signup", type=date.fromisoformat, required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--limit", type=Decimal, help="시험용. 한도를 이 금액으로 바꾼다")
    args = ap.parse_args(argv)

    # 청구 기록의 usage_date는 UTC 날짜라 오늘도 UTC로 잡는다. 카드 계산의 한국 시간 규칙과 다르다
    start, limit = spend_window(datetime.now(UTC).date(), args.signup)
    if args.limit is not None:
        limit = args.limit
    # 하나가 실패해도 나머지는 멈춘다. 실패는 모았다가 끝에서 실행을 실패로 끝내 알림 메일이 가게 한다
    # 이름은 공개 기록에 남지 않게 찍지 않고 오류 종류만 모은다
    errors: list[str] = []
    try:
        row = (
            SparkSession.builder.getOrCreate().sql(SPENT, args={"start": start}).first()
        )
        spent, unpriced = Decimal(row.spent), row.unpriced
        over = is_over(spent, limit, unpriced)
    except Exception as e:  # noqa: BLE001
        # 쓴 금액을 통째로 모르는 것이라 넘은 것으로 본다. 서비스 주체의 청구 기록 읽기 권한이 빠지면 여기로 온다
        spent, unpriced, over = None, 0, True
        errors.append(f"청구 기록 조회 {type(e).__name__}")

    w = WorkspaceClient()
    changed = stopped_warehouses = stopped_apps = 0

    def listing(kind: str, call) -> list:
        """목록 조회가 실패해도 다음 종류는 계속 멈춘다."""
        try:
            return list(call())
        except Exception as e:  # noqa: BLE001
            errors.append(f"{kind} 목록 {type(e).__name__}")
            return []

    for listed in listing("작업", w.jobs.list):
        tags = (listed.settings.tags if listed.settings else None) or {}
        if tags.get(GUARD_TAG) != args.target:
            continue
        try:
            # update는 tags를 합쳐 지운 표시가 남는다. 2026-10-01 운영 시험에서 다시 켠 뒤에도 표시가 남아
            # 배포 워크플로가 차단된 달로 보고 배포를 계속 건너뛸 뻔했다. reset으로 설정 전체를 덮어 표시까지 지운다
            # SDK 형식을 거치면 SDK가 모르는 칸이 소리 없이 빠져 reset에서 지워질 수 있다. 서버가 준 JSON을 그대로 돌려보낸다
            current = w.api_client.do(
                "GET", "/api/2.2/jobs/get", query={"job_id": listed.job_id}
            )["settings"]
            new = guard_changes(current, args.target, over)
            if new:
                w.api_client.do(
                    "POST",
                    "/api/2.2/jobs/reset",
                    body={"job_id": listed.job_id, "new_settings": {**current, **new}},
                )
                changed += 1
        except Exception as e:  # noqa: BLE001
            errors.append(f"작업 {type(e).__name__}")
        if over:
            # 설정 바꾸기가 실패해도 돌고 있는 실행은 멈춘다
            try:
                w.jobs.cancel_all_runs(job_id=listed.job_id)
            except Exception as e:  # noqa: BLE001
                errors.append(f"실행 취소 {type(e).__name__}")
    if over:
        # 목록에는 이 계정이 권한을 가진 웨어하우스만 나온다. 권한은 docs/databricks.md 3단계에서 준다
        for wh in listing("웨어하우스", w.warehouses.list):
            if wh.state is not None and wh.state.value in WAREHOUSE_OFF:
                continue
            try:
                w.warehouses.stop(wh.id)
                stopped_warehouses += 1
            except Exception as e:  # noqa: BLE001
                errors.append(f"웨어하우스 {type(e).__name__}")
        for app in listing("앱", w.apps.list):
            state = (
                app.compute_status.state.value
                if app.compute_status and app.compute_status.state
                else None
            )
            if state not in APP_ON:
                continue
            try:
                w.apps.stop(app.name)
                stopped_apps += 1
            except Exception as e:  # noqa: BLE001
                errors.append(f"앱 {type(e).__name__}")
    shown = "모름" if spent is None else f"{spent}달러"
    print(
        f"합산 시작일 {start}, 쓴 금액 {shown}, 한도 {limit}달러, 가격 없는 사용량 {unpriced}건, 멈춤 {over}, "
        f"바꾼 작업 {changed}개, 끈 웨어하우스 {stopped_warehouses}개, 끈 앱 {stopped_apps}개"
    )
    problems = list(errors)
    if unpriced:
        problems.append(f"가격을 찾지 못한 사용량 {unpriced}건")
    if over and (changed or stopped_warehouses or stopped_apps):
        # 새로 멈춘 순간에만 알린다. 이미 멈춘 달의 다음 실행은 바꿀 것이 없어 성공으로 끝난다
        problems.append("한도를 넘어 새로 멈췄다")
    if problems:
        raise SystemExit("비용 차단 알림: " + ", ".join(problems))


if __name__ == "__main__":
    main()
