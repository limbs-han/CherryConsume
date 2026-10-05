"""카드 개정 이력의 원천 표 설정. 작업 010 설계 1절.

골드 card_revisions에 변경 데이터 피드를 켜고, 이력 작업이 늦게 돌아도 변경 파일과 로그가 남게 보존 기간을 늘린다.
승인 작업은 개정 표를 쓰기 전에, 골드 첫 적재는 덮어쓰기가 표 설정을 지울 수 있어 쓰고 난 뒤에 부른다. 둘 다 서비스 주체로 돌아 운영 표 설정을 바꿀 수 있다.
"""

from __future__ import annotations

CHANGE_FEED = {
    "delta.enableChangeDataFeed": "true",
    # 비용 차단이 이력 작업을 한 달 멈춰도 밀린 변경을 읽을 수 있게 한다. 기본은 변경 파일 7일, 로그 30일이다
    "delta.deletedFileRetentionDuration": "interval 60 days",
    "delta.logRetentionDuration": "interval 60 days",
}


def change_feed_sql(table: str, current: dict[str, str]) -> str | None:
    """설정이 모자라면 채우는 ALTER 문, 다 맞으면 None. current는 SHOW TBLPROPERTIES의 키와 값이다.

    같은 값을 다시 쓰면 표에 새 판이 생겨 표 바뀜 트리거가 이력 작업을 한 번 더 돌리므로 모자란 것만 쓴다.
    """
    missing = {k: v for k, v in CHANGE_FEED.items() if current.get(k, "").lower() != v}
    if not missing:
        return None
    props = ", ".join(f"'{k}' = '{v}'" for k, v in missing.items())
    return f"ALTER TABLE {table} SET TBLPROPERTIES ({props})"
