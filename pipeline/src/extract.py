"""카드 원문을 모델로 추출해 초안을 만든다. 작업 003 과제 18, 설계 1절 4단계와 5단계.

changes 모드는 silver.changes에서 아직 추출하지 않은 변경이 있는 카드만, 원문 id마다 가장 최근 문서로 추출한다.
초안과 사람이 정할 것은 silver.queue에 올린다. cherry_refresh가 변경 감지 뒤에 부른다.
golden 모드는 silver.golden의 카드를 첫 수집 원문으로 추출한다. 모델을 고르는 채점용이라 검수 대기에 올리지 않는다.
카탈로그는 골드에서 읽는다. 답은 cherry_core.pipeline.extract가 초안과 검사 결과로 바꾼다.
모델 호출이 실패한 카드는 끝난 것으로 치지 않고, 다 쓴 뒤 실행을 실패로 끝내 알린다. 다음 실행이 다시 추출한다.
모델이 비면 추출하지 않는다. 과제 19에서 모델을 고르기 전까지 운영은 추출하지 않는다.
찍는 것은 개수뿐이다.
"""

import argparse
import hashlib
import re
import tempfile
import uuid
from collections import defaultdict
from pathlib import Path

from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.resolve import resolve_card
from cherry_core.pipeline.extract import (
    QUEUED,
    pending_changes,
    process_answer,
    unqueued,
)
from cherry_core.pipeline.prompt import (
    RESPONSE_FORMAT,
    VERSION,
    build_prompt,
    catalog_codes,
)
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

# base_sha256은 초안을 만들 때 기준으로 삼은 골드 카드 파일의 해시다. 과제 20 검수 앱은 승인할 때 지금 골드와 다르면 막는다
DRAFTS = (
    "draft_id STRING, card_id STRING, issuer STRING, mode STRING, model STRING, prompt_version STRING, "
    "change_paths ARRAY<STRING>, doc_paths ARRAY<STRING>, answer STRING, status STRING, reason STRING, "
    "draft_yaml STRING, problems ARRAY<STRING>, created_at TIMESTAMP, base_sha256 STRING"
)
# changes.py가 처음 만든 표다. 초안을 찾아가도록 draft_id 칸을 더한다. 검수 앱은 이 칸으로만 초안을 찾는다
QUEUE = (
    "kind STRING, issuer STRING, card_id STRING, subject STRING, source_path STRING, status STRING, "
    "created_at TIMESTAMP, draft_id STRING"
)
QUEUE_ROW = "kind STRING, issuer STRING, card_id STRING, subject STRING, source_path STRING, status STRING, draft_id STRING"
MODEL = re.compile(
    r"[\w.-]+"
)  # 모델 이름은 SQL에 그대로 들어가므로 글자를 좁힌다. fullmatch로 쓴다


def add_column(spark: SparkSession, table: str, name: str, kind: str) -> None:
    if name not in spark.table(table).columns:
        spark.sql(f"ALTER TABLE {table} ADD COLUMNS ({name} {kind})")


def subject(reason: str | None, name: str, problems: list[str] | None) -> str:
    return reason or f"{name} 초안, 검사에 걸린 곳 {len(problems or [])}개"


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument(
        "--model", default="", help="ai_query에 넘길 모델 이름. 비면 추출하지 않는다"
    )
    ap.add_argument("--mode", choices=["changes", "golden"], default="changes")
    ap.add_argument(
        "--split",
        choices=["tune", "test", "all"],
        default="tune",
        help="golden 모드에서 고를 정답 예시",
    )
    ap.add_argument(
        "--max-tokens",
        type=int,
        # 2026-10-01 개발용 시험에서 gpt-oss-120b가 32000을 "max_output_tokens 25000보다 크다"로 거절했다
        default=25000,
        help="답의 최대 토큰. 생각하는 모델은 생각한 몫도 여기 든다. 모델마다 상한이 있다",
    )
    args = ap.parse_args(argv)
    if not args.model:
        print("추출 모델이 비어 추출하지 않는다")
        return
    if not MODEL.fullmatch(args.model):
        raise SystemExit("모델 이름에 쓸 수 없는 글자가 있다")
    spark = SparkSession.builder.getOrCreate()
    # 받은 날을 한국 날짜로 센다. 원문에 시행일이 없을 때 초안의 추정 시행일이 이 날이다
    spark.conf.set("spark.sql.session.timeZone", "Asia/Seoul")
    s, g = f"cherry.{args.silver}", f"cherry.{args.gold}"
    for name, columns in (("drafts", DRAFTS), ("queue", QUEUE)):
        spark.sql(f"CREATE TABLE IF NOT EXISTS {s}.{name} ({columns})")
    add_column(spark, f"{s}.queue", "draft_id", "STRING")
    add_column(spark, f"{s}.drafts", "base_sha256", "STRING")

    files = {
        r.path: r.yaml
        for r in spark.table(f"{g}.catalog_files").select("path", "yaml").collect()
    }
    with tempfile.TemporaryDirectory() as tmp:
        for rel, text in files.items():
            (Path(tmp) / rel).parent.mkdir(parents=True, exist_ok=True)
            (Path(tmp) / rel).write_text(text, encoding="utf-8", newline="\n")
        cat = load_catalog(Path(tmp))
    codes = catalog_codes(cat)
    now = F.current_timestamp()

    docs = (
        spark.table(f"{s}.documents")
        .where("card_id IS NOT NULL")
        .withColumn("day", F.to_date("fetched_at"))
    )
    changed: dict[str, list[str]] = {}  # 카드마다 이번에 쓰는 변경 행의 새 경로
    refill: list[tuple] = []
    if args.mode == "golden":
        golden = spark.table(f"{s}.golden")
        if args.split != "all":
            golden = golden.where(F.col("split") == args.split)
        paths = [p for r in golden.collect() if r.sources for p in r.sources.values()]
        rows = docs.where(F.col("path").isin(paths)).collect()
    else:
        mine = spark.table(f"{s}.drafts").where("mode = 'changes'")
        # 앞 실행이 초안을 쓰고 검수 대기를 쓰기 전에 끊겼으면 여기서 메운다
        queued = {
            r.draft_id
            for r in spark.table(f"{s}.queue")
            .where("draft_id IS NOT NULL")
            .select("draft_id")
            .collect()
        }
        past = {
            r.draft_id: r
            for r in mine.where(F.col("status").isin(list(QUEUED))).collect()
        }
        for d in unqueued([(d, r.status) for d, r in past.items()], queued):
            r = past[d]
            source = (r.change_paths or r.doc_paths)[0]
            refill.append(
                (
                    r.status,
                    r.issuer,
                    r.card_id,
                    subject(r.reason, r.card_id, r.problems),
                    source,
                    "open",
                    d,
                )
            )
        if refill:
            spark.createDataFrame(refill, QUEUE_ROW).withColumn(
                "created_at", now
            ).write.mode("append").saveAsTable(f"{s}.queue")
        changed = pending_changes(
            [
                tuple(r)
                for r in spark.table(f"{s}.changes")
                .where("card_id IS NOT NULL")
                .select("card_id", "new_path")
                .collect()
            ],
            [
                (r.change_paths, r.status)
                for r in mine.select("change_paths", "status").collect()
            ],
        )
        latest = Window.partitionBy("card_id", "source_id").orderBy(
            F.col("fetched_at").desc(), F.col("path").desc()
        )
        rows = (
            docs.where(F.col("card_id").isin(list(changed)))
            .withColumn("n", F.row_number().over(latest))
            .where("n = 1")
            .collect()
        )
    # 원문에 시행일이 없으면 이번에 바뀐 원문을 처음 받은 날을 추정 시행일로 쓴다. 정답 예시는 원문을 받은 날이다
    first_seen = {
        r.path: r.day
        for r in docs.where(
            F.col("path").isin([p for v in changed.values() for p in v])
        ).collect()
    }
    by_card = defaultdict(list)
    for r in rows:
        by_card[r.card_id].append(r)

    prompts, meta, skipped = [], {}, 0
    for cid, card_docs in sorted(by_card.items()):
        lc = cat.cards.get(cid)
        if lc is None:
            # 골드 카탈로그에 없는 카드. 새 카드는 목록 비교가 검수 대기에 올린다
            skipped += 1
            continue
        card_docs.sort(key=lambda r: r.source_id)
        issuer = (
            cat.issuers[lc.card.issuer].raw if lc.card.issuer in cat.issuers else None
        )
        current = resolve_card(lc.raw, issuer)[-1].data
        prompts.append(
            (
                cid,
                build_prompt(
                    lc.raw, current, [(r.source_id, r.text) for r in card_docs], codes
                ),
            )
        )
        days = [first_seen[p] for p in changed.get(cid, []) if p in first_seen]
        meta[cid] = (
            lc,
            issuer,
            [r.path for r in card_docs],
            min(days) if days else max(r.day for r in card_docs),
        )
    if not prompts:
        print(
            f"추출할 카드 0장, 골드에 없어 건너뛴 카드 {skipped}장, 검수 대기에 다시 올린 초안 {len(refill)}건"
        )
        return

    query = (
        f"ai_query('{args.model}', prompt, responseFormat => '{RESPONSE_FORMAT}', failOnError => false, "
        f"modelParameters => named_struct('temperature', 0.0, 'max_tokens', {args.max_tokens})) AS out"
    )
    answers = (
        spark.createDataFrame(prompts, "card_id STRING, prompt STRING")
        .selectExpr("card_id", query)
        .collect()
    )

    drafts, queue, counts = [], [], defaultdict(int)
    for a in answers:
        lc, issuer, doc_paths, day = meta[a.card_id]
        # 답 칸의 이름이 문서와 달라 이름에 기대지 않는다. errorMessage가 아닌 칸이 답이다. 2026-10-01 개발용 시험
        result = a.out.asDict()
        error = result.pop("errorMessage", None)
        response = next(iter(result.values()), None)
        out = process_answer(files, lc.file, lc.raw, issuer, response, error, day)
        draft_id = str(uuid.uuid4())
        counts[out.status] += 1
        counts["problems"] += bool(out.problems)
        base = hashlib.sha256(files[lc.file].encode("utf-8")).hexdigest()
        drafts.append(
            (
                draft_id,
                a.card_id,
                lc.card.issuer,
                args.mode,
                args.model,
                VERSION,
                changed.get(a.card_id, []),
                doc_paths,
                response,
                out.status,
                out.reason or error,
                out.draft_yaml,
                out.problems,
                base,
            )
        )
        if args.mode == "changes" and out.status in QUEUED:
            source = (changed.get(a.card_id) or doc_paths)[0]
            queue.append(
                (
                    out.status,
                    lc.card.issuer,
                    a.card_id,
                    subject(out.reason, lc.card.name, out.problems),
                    source,
                    "open",
                    draft_id,
                )
            )

    columns = DRAFTS.replace(", created_at TIMESTAMP", "")
    spark.createDataFrame(drafts, columns).withColumn("created_at", now).write.mode(
        "append"
    ).saveAsTable(f"{s}.drafts")
    if queue:
        spark.createDataFrame(queue, QUEUE_ROW).withColumn(
            "created_at", now
        ).write.mode("append").saveAsTable(f"{s}.queue")
    print(
        f"추출한 카드 {len(answers)}장, 초안 {counts['draft']}, 바뀐 것 없음 {counts['no_change']}, "
        f"사람이 정할 것 {counts['needs_human']}, 검사에 걸린 초안 {counts['problems']}, 모델 호출 실패 {counts['model_error']}, "
        f"검수 대기 {len(queue)}건, 다시 올린 초안 {len(refill)}건, 골드에 없어 건너뛴 카드 {skipped}장"
    )
    if counts["model_error"]:
        raise SystemExit(
            f"모델 호출이 실패한 카드 {counts['model_error']}장. 다음 실행에서 다시 추출한다"
        )


if __name__ == "__main__":
    main()
