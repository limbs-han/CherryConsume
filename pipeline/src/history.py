"""골드 카드 개정의 변경 이력을 쌓는다. 작업 010 설계 1절.

골드 card_revisions의 변경 데이터 피드를 AUTO CDC로 받아 card_revision_history에 천천히 바뀌는 차원 2형으로 쌓는다.
행이 바뀌면 옛 행을 지우지 않고 __END_AT으로 닫는다. 지금 맞는 행은 __END_AT이 비어 있다.
처음 돌 때는 변경 데이터 피드가 지금 표 전체를 넣기로 주어 따로 첫 적재를 하지 않는다.
승인은 규칙이 바뀐 개정을 같은 판 안에서 지우고 새로 넣는다. 그래서 순서 값을 판 번호, 판 안의 차례, 시각으로 묶어
지우기가 먼저 옛 행을 닫고 넣기가 뒤에 새 행을 열게 한다. __START_AT.at과 __END_AT.at이 그 행이 맞았던 시각이다.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

GOLD = spark.conf.get("cherry.gold")  # noqa: F821 파이프라인이 spark를 넣어 준다
# 원천은 지우고 다시 넣는 표라 이력이 지워지면 되살릴 곳이 없다. 운영은 전체 다시 쌓기를 막는다. 개발용은 연다
RESET_ALLOWED = spark.conf.get("cherry.history_reset_allowed", "false")  # noqa: F821


@dp.temporary_view(
    comment="card_revisions의 변경 데이터. 바뀌기 전 모습은 버리고 순서 값을 붙인다"
)
def card_revision_changes():
    return (
        spark.readStream.option("readChangeFeed", "true")  # noqa: F821
        .table(f"cherry.{GOLD}.card_revisions")
        # 지금 승인은 고치기를 쓰지 않아 생기지 않는다. 고치기를 쓰게 되면 고친 뒤 모습만 남긴다
        .where("_change_type != 'update_preimage'")
        .withColumn(
            "seq",
            F.struct(
                F.col("_commit_version").alias("version"),
                F.when(F.col("_change_type") == "delete", 0).otherwise(1).alias("step"),
                F.col("_commit_timestamp").alias("at"),
            ),
        )
    )


dp.create_streaming_table(
    "card_revision_history",
    comment="카드 개정의 변경 이력. 2형이고 __START_AT, __END_AT이 판 번호, 판 안의 차례, 시각이다",
    table_properties={"pipelines.reset.allowed": RESET_ALLOWED},
)

dp.create_auto_cdc_flow(
    target="card_revision_history",
    source="card_revision_changes",
    keys=["card_id", "effective_from"],
    sequence_by=F.col("seq"),
    apply_as_deletes=F.expr("_change_type = 'delete'"),
    except_column_list=["_change_type", "_commit_version", "_commit_timestamp", "seq"],
    stored_as_scd_type=2,
)
