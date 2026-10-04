"""받은 원문 파일마다 글과 지문을 silver.documents에 쓴다. 작업 003 과제 15, 설계 1절 2단계.

bronze.fetches에 있고 silver.documents에 없는 경로만 처리한다. 처리한 파일은 다시 읽지 않으므로
ai_parse_document 요금은 새 PDF에만 나온다. PDF는 ai_parse_document 결과로, 나머지는 cherry_core가 글을 뽑는다.
글 뽑기와 지문은 pandas UDF로 Spark 안에서 하고, 쓰는 행은 fetches 표에서 이어 와 계보에 fetches에서 documents로 가는 선이 남는다.
처음 보는 내용을 묶음으로 나눠 묶음마다 한 번씩 쓴다. 쓰기 전에 같은 DataFrame을 세거나 모으면 ai_parse_document를 또 부르므로,
개수는 쓴 뒤 표를 다시 읽어 센다. 시간 제한으로 끊겨도 쓴 묶음은 남아 다음 실행이 남은 것만 해석한다. 작업 008 6단계.
작업 007 설계 2절. 찍는 것은 개수뿐이고 원문 내용은 찍지 않는다.
HTML 원문 옆에 같은 이름의 .png가 있으면 수집기가 혜택을 이미지로 넣은 페이지로 보고 찍은 화면이다. 그 사진을
ai_parse_document로 해석한 글을 쓰고 method는 screenshot이다. HTML 원문마다 본문 이미지 수를 image_count에 적는다. 작업 008 8단계.
같은 원문의 가장 최근 사진 문서와 페이지 글이 같으면 사진을 다시 해석하지 않고 그 글을 쓴다.
PDF 옆에 같은 이름의 .md가 있으면 집 PC 수집기가 Docling으로 해석한 글이라 그것을 쓰고 method는 docling이다.
ai_parse_document는 .md가 없는 PDF에만 부른다. 작업 008 9단계.
"""

import argparse
import time
from pathlib import Path

import pandas as pd
from cherry_core.pipeline.text import (
    body_stats,
    fingerprint,
    method_and_text,
    same_page_text,
)
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

COLUMNS = (
    "path STRING, issuer STRING, card_id STRING, source_id STRING, kind STRING, fetched_at TIMESTAMP, "
    "sha256 STRING, method STRING, text STRING, fingerprint STRING, parsed_at TIMESTAMP, image_count INT"
)


@F.pandas_udf("method STRING, text STRING")
def texts(
    content: pd.Series, content_type: pd.Series, parsed: pd.Series, markdown: pd.Series
) -> pd.DataFrame:
    return pd.DataFrame(
        [
            method_and_text(b, t, p, m)
            for b, t, p, m in zip(content, content_type, parsed, markdown)
        ],
        columns=["method", "text"],
    )


@F.pandas_udf("int")
def image_counts(content: pd.Series, content_type: pd.Series) -> pd.Series:
    # HTML 원문만 센다. PDF와 JSON은 비운다
    return pd.Series(
        [
            None
            if b.startswith(b"%PDF-") or "json" in (t or "")
            else body_stats(b.decode("utf-8", "replace"))[0]
            for b, t in zip(content, content_type)
        ],
        dtype="Int64",
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
    if "image_count" not in spark.table(documents).columns:
        spark.sql(f"ALTER TABLE {documents} ADD COLUMNS (image_count INT)")

    new = (
        spark.table(fetches)
        .join(spark.table(documents).select("path"), "path", "left_anti")
        .dropDuplicates(["path"])
    )
    rows = new.select("path", "sha256", "issuer", "card_id", "source_id").collect()
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
        .select("sha256", "method", "text", "image_count")
    )
    # 찍은 화면이 있는 HTML은 같은 원문의 가장 최근 사진 문서와 페이지 글이 같으면 그 글을 다시 쓴다. 사진 해석은
    # 할 때마다 글이 조금씩 달라, 다시 해석하면 바뀌지 않은 페이지가 바뀐 원문으로 잡혀 추출 요금이 난다
    shot_paths = {
        r.path
        for r in rows
        if r.path.endswith(".html")
        and Path(f"{raw}/{r.path[: -len('.html')]}.png").exists()
    }
    again = {}  # 이번 HTML 경로에서 글을 다시 쓸 앞 사진 문서의 경로로
    if shot_paths:
        last = {
            (d.issuer, d.card_id, d.source_id): d.path
            for d in spark.table(documents)
            .where("method = 'screenshot'")
            .withColumn(
                "rank",
                F.row_number().over(
                    Window.partitionBy("issuer", "card_id", "source_id").orderBy(
                        F.col("fetched_at").desc()
                    )
                ),
            )
            .where("rank = 1")
            .select("issuer", "card_id", "source_id", "path")
            .collect()
        }
        for r in rows:
            prev = last.get((r.issuer, r.card_id, r.source_id))
            if (
                r.path in shot_paths
                and prev
                and Path(f"{raw}/{prev}").exists()
                and same_page_text(
                    Path(f"{raw}/{prev}").read_bytes(),
                    Path(f"{raw}/{r.path}").read_bytes(),
                )
            ):
                again[r.path] = prev
    if again:
        seen = seen.unionByName(
            spark.createDataFrame(list(again.items()), "path STRING, prev STRING")
            .join(new.select("path", "sha256"), "path")
            .join(
                spark.table(documents).select(
                    F.col("path").alias("prev"), "method", "text", "image_count"
                ),
                "prev",
            )
            .select("sha256", "method", "text", "image_count")
        )
    seen = seen.dropDuplicates(["sha256"])
    known = {r.sha256 for r in seen.select("sha256").collect()}
    first = {}  # 이번에 처음 보는 내용마다 대표 경로 하나
    for r in sorted(rows, key=lambda r: r.path):
        if r.sha256 not in known:
            first.setdefault(r.sha256, r.path)

    # 집 PC 수집기가 Docling으로 해석해 둔 PDF는 같은 이름의 .md다. 그 PDF에는 ai_parse_document를 부르지 않는다
    # 크기가 0인 .md는 없는 것으로 본다. 빈 글을 쓰면 카드가 비워진다
    md_paths = set()
    for path in first.values():
        md = Path(f"{raw}/{path[: -len('.pdf')]}.md")
        if path.endswith(".pdf") and md.exists() and md.stat().st_size > 0:
            md_paths.add(path)

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
            pdfs = body.where(is_pdf)
            no_text = F.lit(None).cast("string")
            mds = [
                first[sha][: -len(".pdf")] + ".md"
                for sha in group
                if first[sha] in md_paths
            ]
            markdown = None
            if mds:
                markdown = (
                    spark.read.format("binaryFile")
                    .load([f"{raw}/{p}" for p in mds])
                    .select(
                        F.regexp_replace(
                            F.substring_index("path", f"{raw}/", -1), r"\.md$", ".pdf"
                        ).alias("path"),
                        F.col("content").cast("string").alias("markdown"),
                    )
                )
                pdfs = pdfs.join(markdown, "path", "left_anti")
            parsed = pdfs.withColumn(
                "parsed",
                F.expr("to_json(ai_parse_document(content, map('version', '2.0')))"),
            ).withColumn("markdown", no_text)
            if markdown is not None:
                parsed = parsed.unionByName(
                    body.join(markdown, "path").withColumn("parsed", no_text)
                )
            others = body.where(~is_pdf).withColumn("markdown", no_text)
            # 수집기가 찍은 화면은 HTML과 같은 이름의 .png다. 있으면 그 사진을 해석한 글을 쓴다
            shots = [
                first[sha][: -len(".html")] + ".png"
                for sha in group
                if first[sha] in shot_paths
            ]
            if shots:
                parsed_shots = (
                    spark.read.format("binaryFile")
                    .load([f"{raw}/{p}" for p in shots])
                    .select(
                        F.regexp_replace(
                            F.substring_index("path", f"{raw}/", -1), r"\.png$", ".html"
                        ).alias("path"),
                        F.expr(
                            "to_json(ai_parse_document(content, map('version', '2.0')))"
                        ).alias("parsed"),
                    )
                )
                others = others.join(parsed_shots, "path", "left")
            else:
                others = others.withColumn("parsed", F.lit(None).cast("string"))
            by_sha = (
                parsed.unionByName(others)
                .select(
                    "sha256",
                    texts("content", "content_type", "parsed", "markdown").alias("t"),
                    image_counts("content", "content_type").alias("image_count"),
                )
                .select("sha256", "t.method", "t.text", "image_count")
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
    parsed_counts = (
        {
            r.method: r["count"]
            for r in spark.table(documents)
            .where(F.col("path").isin(list(first.values())))
            .groupBy("method")
            .count()
            .collect()
        }
        if first
        else {}
    )
    print(
        f"새 원문 {len(rows)}개, 처음 보는 내용 {len(first)}개, 그중 PDF {parsed_counts.get('ai_parse_document', 0)}개, "
        f"Docling PDF {parsed_counts.get('docling', 0)}개, "
        f"사진 해석 {parsed_counts.get('screenshot', 0)}개, 앞 사진 글 다시 쓰기 {len(again)}개, 아직 없는 원문 {len(missing)}개"
    )
    # .md와 PDF의 경로가 어긋나면 행은 남지만 ai_parse_document로 해석돼 요금이 난다. 쓴 뒤라도 알려 경로를 고친다
    if parsed_counts.get("docling", 0) != len(md_paths):
        raise SystemExit(
            f".md가 있는 PDF {len(md_paths)}개 가운데 {parsed_counts.get('docling', 0)}개만 Docling 글로 썼다. 경로 맞추기를 본다"
        )


if __name__ == "__main__":
    main()
