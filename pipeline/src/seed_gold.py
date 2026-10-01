"""저장소의 카탈로그를 골드에 처음 올리고 정답 예시를 만든다. 작업 003 과제 17, 설계 4절 1번.

이 작업이 끝나면 카탈로그의 원본은 골드다. 행은 cherry_core.pipeline.seed가 만든다.
쓰기 전에 올린 카탈로그의 해시를 PC 값과 맞춘다. 올리기가 끊겨 파일이 빠지면 검사는 통과하고 카드만 줄기 때문이다.
gold.catalog_files에 행이 있으면 골드는 건드리지 않는다. 다시 쓰면 그 뒤에 승인된 개정을 저장소 판으로 덮는다.
정답 예시는 늘 다시 만든다. 사람이 나중에 더한 원문도 짝이 되고, 규칙은 해시로 확인한 첫 카탈로그에서 온다.
gold.catalog_files를 마지막에 쓴다. 앞에서 실패하면 다시 돌릴 수 있고, 카드 개정은 통째로 덮는다.
"""

import argparse
from pathlib import Path

from cherry_core.pipeline.seed import (
    INITIAL,
    digest,
    file_rows,
    golden_rows,
    load_checked,
    revision_rows,
)
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

FILES = "path STRING, yaml STRING, review_id STRING, updated_at TIMESTAMP"
REVISIONS = (
    "card_id STRING, issuer STRING, effective_from DATE, effective_from_estimated BOOLEAN, source STRING, "
    "rules STRING, review_id STRING, updated_at TIMESTAMP"
)
GOLDEN = (
    "card_id STRING, issuer STRING, split STRING, effective_from DATE, rules STRING, "
    "sources MAP<STRING, STRING>, created_at TIMESTAMP"
)


def without_last(ddl: str) -> str:
    """마지막 칸인 시각은 쓸 때 current_timestamp로 채운다."""
    return ddl.rsplit(", ", 1)[0]


def first_paths(spark: SparkSession, documents: str) -> dict[tuple[str, str], str]:
    """(카드, 원문 id)마다 처음 받은 원문의 경로. 정답 예시는 첫 수집 원문과 짝이다."""
    if not spark.catalog.tableExists(documents):
        return {}
    first = Window.partitionBy("card_id", "source_id").orderBy("fetched_at", "path")
    rows = (
        spark.table(documents)
        .where("card_id IS NOT NULL")
        .withColumn("n", F.row_number().over(first))
        .where("n = 1")
        .select("card_id", "source_id", "path")
        .collect()
    )
    return {(r.card_id, r.source_id): r.path for r in rows}


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--catalog-dir", required=True, help="저장소 catalog/를 올린 볼륨 폴더"
    )
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument(
        "--expect-files", default="", help="PC의 seed 명령이 찍은 카탈로그 파일 해시"
    )
    ap.add_argument(
        "--expect-revisions", default="", help="PC의 seed 명령이 찍은 카드 개정 해시"
    )
    args = ap.parse_args(argv)
    spark = SparkSession.builder.getOrCreate()
    files_t, revisions_t = (
        f"cherry.{args.gold}.catalog_files",
        f"cherry.{args.gold}.card_revisions",
    )
    golden_t, documents_t = (
        f"cherry.{args.silver}.golden",
        f"cherry.{args.silver}.documents",
    )

    root = Path(args.catalog_dir)
    cat = load_checked(root)  # 검사 오류가 있으면 ValueError로 멈춘다
    files, revisions = file_rows(root), revision_rows(cat)
    if (digest(files), digest(revisions)) != (args.expect_files, args.expect_revisions):
        raise SystemExit(
            "올린 카탈로그의 해시가 PC 값과 다르다. 빠진 파일이 있거나 다른 판을 올렸다"
        )
    for table, ddl in ((files_t, FILES), (revisions_t, REVISIONS), (golden_t, GOLDEN)):
        spark.sql(f"CREATE TABLE IF NOT EXISTS {table} ({ddl})")

    now = F.current_timestamp()
    if not spark.table(files_t).isEmpty():
        print("골드에 카탈로그가 이미 있어 정답 예시만 다시 만든다")
    else:
        (
            spark.createDataFrame(revisions, without_last(without_last(REVISIONS)))
            .withColumn("review_id", F.lit(INITIAL))
            .withColumn("updated_at", now)
            .write.mode("overwrite")
            .saveAsTable(revisions_t)
        )
        (
            spark.createDataFrame(files, without_last(without_last(FILES)))
            .withColumn("review_id", F.lit(INITIAL))
            .withColumn("updated_at", now)
            .write.mode("append")
            .saveAsTable(files_t)
        )
    (
        spark.createDataFrame(
            golden_rows(cat, first_paths(spark, documents_t)), without_last(GOLDEN)
        )
        .withColumn("created_at", now)
        .write.mode("overwrite")
        .option(
            "overwriteSchema", "true"
        )  # 칸을 더해도 다시 만들 수 있게 한다. 이 표는 늘 통째로 다시 쓴다
        .saveAsTable(golden_t)
    )

    stored_files = [
        tuple(r) for r in spark.table(files_t).select("path", "yaml").collect()
    ]
    stored_revisions = [
        tuple(r)
        for r in spark.table(revisions_t)
        .select(
            "card_id",
            "issuer",
            "effective_from",
            "effective_from_estimated",
            "source",
            "rules",
        )
        .collect()
    ]
    golden = spark.table(golden_t)
    tested = golden.where("split = 'test'").count()
    with_sources = golden.where("size(sources) > 0").count()
    print(f"골드 카탈로그 파일 {len(stored_files)}개 해시 {digest(stored_files)}")
    print(f"골드 카드 개정 {len(stored_revisions)}개 해시 {digest(stored_revisions)}")
    print(
        f"정답 예시 {golden.count()}장, 채점 전용 {tested}장, 첫 수집 원문이 있는 카드 {with_sources}장"
    )


if __name__ == "__main__":
    main()
