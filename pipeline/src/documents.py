"""받은 원문 파일마다 글과 지문을 silver.documents에 쓴다. 작업 003 과제 15, 설계 1절 2단계.

bronze.fetches에 있고 silver.documents에 없는 경로만 처리한다. 처리한 파일은 다시 읽지 않으므로
ai_parse_document 요금은 새 PDF에만 나온다. PDF는 ai_parse_document 결과로, 나머지는 cherry_core가 글을 뽑는다.
찍는 것은 개수뿐이고 원문 내용은 찍지 않는다.
"""

import argparse
import json
from pathlib import Path

from cherry_core.pipeline.text import document_text, fingerprint
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

COLUMNS = (
    "path STRING, issuer STRING, card_id STRING, source_id STRING, kind STRING, fetched_at TIMESTAMP, "
    "sha256 STRING, method STRING, text STRING, fingerprint STRING, parsed_at TIMESTAMP"
)


def method(content: bytes, content_type: str) -> str:
    """document_text가 글을 뽑는 방법. 나중에 방법별로 글 품질을 보려고 남긴다."""
    if content.startswith(b"%PDF-"):
        return "ai_parse_document"
    if "json" in content_type:
        return "json"
    if "text/plain" in content_type:
        return "text"
    return "html"


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--bronze",
        required=True,
        help="bronze 스키마 이름. 개발용이면 개발자 이름이 붙는다",
    )
    ap.add_argument("--silver", required=True)
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
        .collect()
    )
    # 목록 파일만 먼저 올라오면 원문이 아직 없다. 빠진 것은 다음 실행에서 다시 본다
    missing = [r.path for r in new if not Path(f"{raw}/{r.path}").exists()]
    new = [r for r in new if r.path not in missing]
    # 내용이 같은 파일은 다시 읽지 않고 앞에서 뽑은 글을 쓴다. ai_parse_document는 같은 PDF도 읽을 때마다
    # 결과가 조금씩 달라, 다시 읽으면 바뀌지 않은 원문이 바뀐 것으로 잡힌다. 요금도 새 내용에만 나온다
    shas = sorted({r.sha256 for r in new})
    seen = {}
    if shas:
        for r in (
            spark.table(documents)
            .where(F.col("sha256").isin(shas))
            .select("sha256", "method", "text")
            .dropDuplicates(["sha256"])
            .collect()
        ):
            seen[r.sha256] = (r.method, r.text)
    first = {}  # 이번에 처음 보는 내용마다 대표 경로 하나
    for r in new:
        if r.sha256 not in seen:
            first.setdefault(r.sha256, r)
    files = {sha: Path(f"{raw}/{r.path}").read_bytes() for sha, r in first.items()}
    pdfs = {
        first[sha].path: sha for sha, body in files.items() if body.startswith(b"%PDF-")
    }
    parsed = {}
    if pdfs:
        rows = (
            spark.read.format("binaryFile")
            .load([f"{raw}/{p}" for p in pdfs])
            .select(
                "path",
                F.expr(
                    "to_json(ai_parse_document(content, map('version', '2.0')))"
                ).alias("parsed"),
            )
            .collect()
        )
        # binaryFile의 경로는 dbfs:로 시작할 수 있어 raw 볼륨 뒤의 상대 경로로 맞춘다
        parsed = {
            pdfs[r.path.split(f"{raw}/", 1)[1]]: json.loads(r.parsed) for r in rows
        }
    for sha, r in first.items():
        body = files[sha]
        seen[sha] = (
            method(body, r.content_type),
            document_text(body, r.content_type, parsed.get(sha)),
        )

    out = []
    for r in new:
        how, text = seen[r.sha256]
        out.append(
            (
                r.path,
                r.issuer,
                r.card_id,
                r.source_id,
                r.kind,
                r.fetched_at,
                r.sha256,
                how,
                text,
                fingerprint(text, r.kind),
            )
        )
    if out:
        (
            spark.createDataFrame(out, COLUMNS.rsplit(", parsed_at", 1)[0])
            .withColumn("parsed_at", F.current_timestamp())
            .write.mode("append")
            .saveAsTable(documents)
        )
    print(
        f"새 원문 {len(new)}개, 처음 보는 내용 {len(first)}개, 그중 PDF {len(pdfs)}개, 아직 없는 원문 {len(missing)}개"
    )


if __name__ == "__main__":
    main()
