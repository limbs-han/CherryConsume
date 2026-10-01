"""수집기 목록 파일을 bronze.fetches에 쌓는다. 작업 003 과제 15.

수집기가 raw 볼륨의 manifests/에 올린 JSON 줄 한 줄이 한 행이다. 원문 파일은 볼륨에 그대로 두고 경로만 적는다.
목록 파일 경로와 적재 시각을 더하고, path나 sha256이 빈 행은 품질 규칙으로 뺀다.
"""

from pyspark import pipelines as dp
from pyspark.sql import functions as F

RAW = spark.conf.get("cherry.raw")  # noqa: F821 파이프라인이 spark를 넣어 준다

SCHEMA = (
    "issuer STRING, card_id STRING, source_id STRING, kind STRING, url STRING, browser BOOLEAN, "
    "path STRING, fetched_at TIMESTAMP, content_type STRING, sha256 STRING"
)


@dp.table(
    name="fetches",
    comment="수집기 목록 파일 한 줄이 한 행. 원문 파일은 raw 볼륨의 path에 있다",
)
@dp.expect_or_drop("path_present", "path IS NOT NULL AND path <> ''")
@dp.expect_or_drop("sha256_present", "sha256 IS NOT NULL AND sha256 <> ''")
def fetches():
    return (
        spark.readStream.format("cloudFiles")  # noqa: F821
        .option("cloudFiles.format", "json")
        .schema(SCHEMA)
        .load(f"{RAW}/manifests/")
        .select(
            "*",
            F.col("_metadata.file_path").alias("manifest_path"),
            F.current_timestamp().alias("loaded_at"),
        )
    )
