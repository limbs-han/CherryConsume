"""카드 개정 이력의 원천 표 설정. 작업 010 설계 1절."""

from cherry_core.pipeline.history import CHANGE_FEED, change_feed_sql

T = "cherry.gold.card_revisions"


def test_missing_settings_are_set_together():
    assert change_feed_sql(T, {"delta.minReaderVersion": "3"}) == (
        f"ALTER TABLE {T} SET TBLPROPERTIES ("
        "'delta.enableChangeDataFeed' = 'true', "
        "'delta.deletedFileRetentionDuration' = 'interval 60 days', "
        "'delta.logRetentionDuration' = 'interval 60 days')"
    )


def test_nothing_to_do_when_all_set():
    # 같은 값을 다시 쓰면 표에 새 판이 생겨 표 바뀜 트리거가 이력 작업을 한 번 더 돌린다
    assert change_feed_sql(T, {**CHANGE_FEED, "delta.enableChangeDataFeed": "TRUE"}) is None


def test_only_the_missing_one_is_set():
    current = {**CHANGE_FEED, "delta.logRetentionDuration": "interval 30 days"}
    assert change_feed_sql(T, current) == (
        f"ALTER TABLE {T} SET TBLPROPERTIES ('delta.logRetentionDuration' = 'interval 60 days')"
    )
