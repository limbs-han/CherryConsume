"""받은 원문 파일마다 글과 지문을 silver.documents에 쓴다. 작업 003 과제 15, 설계 1절 2단계.

bronze.fetches에 있고 silver.documents에 없는 경로만 처리한다. 처리한 파일은 다시 읽지 않으므로
ai_parse_document 요금은 새 PDF에만 나온다. PDF는 ai_parse_document 결과로, 나머지는 cherry_core가 글을 뽑는다.
글 뽑기와 지문은 pandas UDF로 Spark 안에서 하고, 쓰는 행은 fetches 표에서 이어 와 계보에 fetches에서 documents로 가는 선이 남는다.
처음 보는 내용을 묶음으로 나눠 묶음마다 한 번씩 쓴다. 쓰기 전에 같은 DataFrame을 세거나 모으면 ai_parse_document를 또 부르므로,
개수는 쓴 뒤 표를 다시 읽어 센다. 시간 제한으로 끊겨도 쓴 묶음은 남아 다음 실행이 남은 것만 해석한다. 작업 008 6단계.
작업 007 설계 2절. 찍는 것은 개수뿐이고 원문 내용은 찍지 않는다.
"""

import argparse
import time
from pathlib import Path

import pandas as pd
from cherry_core.pipeline.text import fingerprint, method_and_text
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

COLUMNS = (
    "path STRING, issuer STRING, card_id STRING, source_id STRING, kind STRING, fetched_at TIMESTAMP, "
    "sha256 STRING, method STRING, text STRING, fingerprint STRING, parsed_at TIMESTAMP"
)


@F.pandas_udf("method STRING, text STRING")
def texts(
    content: pd.Series, content_type: pd.Series, parsed: pd.Series
) -> pd.DataFrame:
    return pd.DataFrame(
        [method_and_text(b, t, p) for b, t, p in zip(content, content_type, parsed)],
        columns=["method", "text"],
    )


@F.pandas_udf("string")
def fingerprints(text: pd.Series, kind: pd.Series) -> pd.Series:
    return pd.Series([fingerprint(t, k) for t, k in zip(text, kind)])


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--bronze",
        required=True,
        help="bronze 스키마 이름. 개발용이면 개발자 이름이 붙는다",
    )
    ap.add_argument("--silver", required=True)
    ap.add_argument(
        "--chunk", type=int, default=50, help="한 번에 쓰는 처음 보는 내용 수"
    )
    args = ap.parse_args(argv)
    spark = SparkSession.builder.getOrCreate()
    fetches, documents = (
        f"cherry.{args.bronze}.fetches",
        f"cherry.{args.silver}.documents",
    )
    raw = f"/Volumes/cherry/{args.bronze}/raw"
    spark.sql(f"CREATE TABLE IF NOT EXISTS {documents} ({COLUMNS})")

    new = (
        spark.table(fetches)
        .join(spark.table(documents).select("path"), "path", "left_anti")
        .dropDuplicates(["path"])
    )
    rows = new.select("path", "sha256").collect()
    # 목록 파일만 먼저 올라오면 원문이 아직 없다. 빠진 것은 다음 실행에서 다시 본다
    missing = [r.path for r in rows if not Path(f"{raw}/{r.path}").exists()]
    if missing:
        new = new.where(~F.col("path").isin(missing))
        rows = [r for r in rows if r.path not in missing]
    # 내용이 같은 파일은 다시 읽지 않고 앞에서 뽑은 글을 쓴다. ai_parse_document는 같은 PDF도 읽을 때마다
    # 결과가 조금씩 달라, 다시 읽으면 바뀌지 않은 원문이 바뀐 것으로 잡힌다. 요금도 새 내용에만 나온다
    seen = (
        spark.table(documents)
        .where(F.col("sha256").isin(sorted({r.sha256 for r in rows})))
        .select("sha256", "method", "text")
        .dropDuplicates(["sha256"])
    )
    known = {r.sha256 for r in seen.select("sha256").collect()}
    first = {}  # 이번에 처음 보는 내용마다 대표 경로 하나
    for r in sorted(rows, key=lambda r: r.path):
        if r.sha256 not in known:
            first.setdefault(r.sha256, r.path)

    # 첫 수집처럼 PDF가 수백 개 오면 시간 제한 안에 끝나지 않을 수 있어 묶음마다 쓴다. 이미 아는 내용의 경로는 첫 묶음에 쓴다
    new_shas = list(first)
    groups = [
        new_shas[n : n + args.chunk] for n in range(0, len(new_shas), args.chunk)
    ] or [[]]
    for n, group in enumerate(groups):
        started = time.monotonic()
        shas = set(group) | (known if n == 0 else set())
        paths = [r.path for r in rows if r.sha256 in shas]
        if not paths:
            continue
        by_sha = seen
        if group:
            body = (
                spark.read.format("binaryFile")
                .load([f"{raw}/{first[sha]}" for sha in group])
                # binaryFile의 경로는 dbfs:로 시작할 수 있어 raw 볼륨 뒤의 상대 경로로 맞춘다
                .select(
                    F.substring_index("path", f"{raw}/", -1).alias("path"), "content"
                )
                .join(new.select("path", "sha256", "content_type"), "path")
            )
            is_pdf = F.expr("substr(content, 1, 5) = X'255044462D'")  # %PDF-
            parsed = body.where(is_pdf).withColumn(
                "parsed",
                F.expr("to_json(ai_parse_document(content, map('version', '2.0')))"),
            )
            others = body.where(~is_pdf).withColumn(
                "parsed", F.lit(None).cast("string")
            )
            by_sha = (
                parsed.unionByName(others)
                .select("sha256", texts("content", "content_type", "parsed").alias("t"))
                .select("sha256", "t.method", "t.text")
                .unionByName(seen)
            )
        (
            new.where(F.col("path").isin(paths))
            .join(by_sha, "sha256")
            .withColumn("fingerprint", fingerprints("text", "kind"))
            .withColumn("parsed_at", F.current_timestamp())
            .select(*[c.split()[0] for c in COLUMNS.split(", ")])
            .write.mode("append")
            .saveAsTable(documents)
        )
        # 첫 1일 수집에서 PDF 해석 속도를 재려고 묶음마다 걸린 시간을 찍는다
        if len(groups) > 1:
            print(
                f"묶음 {n + 1}/{len(groups)} 원문 {len(paths)}개, {time.monotonic() - started:.0f}초"
            )
    # 맞붙이기에서 경로가 어긋나면 행이 오류 없이 빠지고, 다음 실행이 같은 PDF를 또 해석해 요금이 다시 나온다
    # 그래서 쓴 행을 다시 읽어 세고 모자라면 실패로 끝내 알린다
    written = (
        spark.table(documents).where(F.col("path").isin([r.path for r in rows])).count()
        if rows
        else 0
    )
    if written < len(rows):
        raise SystemExit(
            f"새 원문 {len(rows)}개 가운데 {written}개만 썼다. 경로 맞추기를 본다"
        )
    pdfs = (
        spark.table(documents)
        .where(
            F.col("path").isin(list(first.values()))
            & (F.col("method") == "ai_parse_document")
        )
        .count()
        if first
        else 0
    )
    print(
        f"새 원문 {len(rows)}개, 처음 보는 내용 {len(first)}개, 그중 PDF {pdfs}개, 아직 없는 원문 {len(missing)}개"
    )


if __name__ == "__main__":
    main()
