"""카드 원문을 모델로 추출해 초안을 만든다. 작업 003 과제 18, 설계 1절 4단계와 5단계.

changes 모드는 silver.changes에서 아직 추출하지 않은 변경이 있는 카드만, 원문 id마다 가장 최근 문서로 추출한다.
초안과 사람이 정할 것은 silver.queue에 올린다. cherry_refresh가 변경 감지 뒤에 부른다.
golden 모드는 silver.golden의 카드를 첫 수집 원문으로 추출한다. 모델을 고르는 채점용이라 검수 대기에 올리지 않는다.
new_card 모드는 색인 card_index에서 카탈로그에 없는 카드의 새 초안을 만들고 검수 대기에 kind new_card로 올린다. 작업 008 설계 3절.
카탈로그는 골드에서 읽는다. 답은 cherry_core.pipeline.extract가 초안과 검사 결과로 바꾼다.
규칙 형식 검사에 걸린 카드는 이전 답과 오류를 붙여 한 번 더 묻는다. 판 7.
모델 호출이 실패한 카드는 끝난 것으로 치지 않고, 다 쓴 뒤 실행을 실패로 끝내 알린다. 다음 실행이 다시 추출한다.
모델이 비면 추출하지 않는다. 운영 모델은 과제 19에서 골랐다.
찍는 것은 개수뿐이다.
"""

import argparse
import hashlib
import re
import tempfile
import uuid
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.resolve import resolve_card
from cherry_core.pipeline.draft import issuer_defaults
from cherry_core.pipeline.extract import (
    QUEUED,
    pending_changes,
    process_answer,
    retry_errors,
    unqueued,
)
from cherry_core.pipeline.new_card import (
    SOURCE_IDS,
    card_head,
    drafted_cards,
    pick_new_cards,
    process_new_card,
)
from cherry_core.pipeline.prompt import (
    RESPONSE_FORMAT,
    VERSION,
    build_prompt,
    catalog_codes,
    example_for,
    retry_prompt,
)
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

# base_sha256은 초안을 만들 때 기준으로 삼은 골드 카드 파일의 해시다. 과제 20 검수 앱은 승인할 때 지금 골드와 다르면 막는다
DRAFTS = (
    "draft_id STRING, card_id STRING, issuer STRING, mode STRING, model STRING, prompt_version STRING, "
    "change_paths ARRAY<STRING>, doc_paths ARRAY<STRING>, answer STRING, status STRING, reason STRING, "
    "draft_yaml STRING, problems ARRAY<STRING>, created_at TIMESTAMP, base_sha256 STRING, retry_reason STRING"
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


def model_query(model: str, max_tokens: int) -> str:
    return (
        f"ai_query('{model}', prompt, responseFormat => '{RESPONSE_FORMAT}', failOnError => false, "
        f"modelParameters => named_struct('temperature', 0.0, 'max_tokens', {max_tokens})) AS out"
    )


def ask(
    spark: SparkSession, query: str, rows: list[tuple[str, str]]
) -> dict[str, tuple[str | None, str | None]]:
    """카드마다 (답, 호출 오류)."""
    out = {}
    for a in (
        spark.createDataFrame(rows, "card_id STRING, prompt STRING")
        .selectExpr("card_id", query)
        .collect()
    ):
        # 답 칸의 이름이 문서와 달라 이름에 기대지 않는다. errorMessage가 아닌 칸이 답이다. 2026-10-01 개발용 시험
        result = a.out.asDict()
        error = result.pop("errorMessage", None)
        out[a.card_id] = (next(iter(result.values()), None), error)
    return out


def ask_again(spark, query, first, answers, outcomes, judge, defaults_for):
    """규칙 형식에만 걸린 카드는 이전 답과 칸마다의 오류를 붙여 한 번 더 묻는다. 설계 1절 4단계 판 7.

    answers와 outcomes를 고쳐 쓴다. (다시 물은 카드와 프롬프트, 카드마다 retry_reason)을 돌려준다.
    처음 답의 까닭은 retry_reason에 남긴다. 다시 묻기 호출이 실패하면 처음 답으로 사람이 정하고 실패를 retry_reason에 적는다.
    """
    retry = []
    for cid, o in outcomes.items():
        errors = retry_errors(o, answers[cid][0], defaults_for(cid))
        if errors:
            retry.append((cid, retry_prompt(first[cid], answers[cid][0], errors)))
    retried: dict[str, str] = {}
    try:
        again = ask(spark, query, retry) if retry else {}
    except Exception as e:  # noqa: BLE001 첫 답은 이미 요금을 냈다. 다시 묻기가 통째로 실패해도 첫 답을 남긴다
        print(f"다시 묻기가 실패해 첫 답을 쓴다: {type(e).__name__}: {str(e)[:300]}")
        again = {}
        retried = {cid: f"다시 묻기 실패: {type(e).__name__}" for cid, _ in retry}
    for cid, (response, error) in again.items():
        if error or response is None:
            retried[cid] = f"다시 묻기 실패: {error}"[:500]
            continue
        retried[cid] = outcomes[cid].reason
        answers[cid] = (response, error)
        outcomes[cid] = judge(cid, response, error)
    return retry, retried


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument(
        "--model", default="", help="ai_query에 넘길 모델 이름. 비면 추출하지 않는다"
    )
    ap.add_argument(
        "--mode", choices=["changes", "golden", "new_card"], default="changes"
    )
    ap.add_argument(
        "--bronze",
        default="",
        help="new_card 모드에서 색인 카드 원문의 주소를 찾을 bronze 스키마",
    )
    ap.add_argument(
        "--issuer",
        default="",
        help="new_card 모드에서 이 카드사만. 쉼표로 잇는다. 비면 모두다",
    )
    ap.add_argument(
        "--limit",
        type=int,
        default=10,
        help="new_card 모드에서 이번에 만들 초안 수. 0은 모두다. 카드당 몇 센트다",
    )
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
    add_column(spark, f"{s}.drafts", "retry_reason", "STRING")

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

    def to_queue(rows: list[tuple]) -> None:
        # 검수 대기는 초안 표의 그 초안 행과 맞붙여 카드사 칸을 가져와 쓴다. 계보에 drafts에서 queue로 가는 선이 남는다
        # 작업 007 설계 2절
        (
            spark.createDataFrame(rows, QUEUE_ROW)
            .drop("issuer")
            .join(spark.table(f"{s}.drafts").select("draft_id", "issuer"), "draft_id")
            .withColumn("created_at", now)
            .write.mode("append")
            .saveAsTable(f"{s}.queue")
        )

    if args.mode == "new_card":
        new_cards(spark, args, s, files, cat, codes, now, to_queue)
        return

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
            to_queue(refill)
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
        example = example_for(cat, cid)
        # 예시 카드가 개정되면 프롬프트도 바뀌어 판 번호에 예시 카드와 개정 시행일을 붙인다
        version = f"{VERSION}+{example[2]}" if example else VERSION
        prompts.append(
            (
                cid,
                build_prompt(
                    lc.raw,
                    current,
                    [(r.source_id, r.text) for r in card_docs],
                    codes,
                    example[:2] if example else None,
                    # 정답 예시는 혜택 제목을 주지 않는다. 제목이 정답을 알려 준다. 설계 1절 4단계 판 11
                    titles=args.mode == "changes",
                ),
            )
        )
        days = [first_seen[p] for p in changed.get(cid, []) if p in first_seen]
        meta[cid] = (
            lc,
            issuer,
            [r.path for r in card_docs],
            min(days) if days else max(r.day for r in card_docs),
            version,
        )
    if not prompts:
        print(
            f"추출할 카드 0장, 골드에 없어 건너뛴 카드 {skipped}장, 검수 대기에 다시 올린 초안 {len(refill)}건"
        )
        return

    query = model_query(args.model, args.max_tokens)

    def judge(cid: str, response: str | None, error: str | None):
        lc, issuer, _, day, _ = meta[cid]
        return process_answer(
            files, lc.file, lc.raw, issuer, response, error, day, args.mode == "changes"
        )

    answers = ask(spark, query, prompts)
    outcomes = {cid: judge(cid, *v) for cid, v in answers.items()}

    # 정답 예시 모드는 채점처럼 카드사 기본값으로 채워 보고 남는 오류만 묻는다. 바뀐 원문 모드는 지금 값으로 이미 채웠다
    def defaults_for(cid: str) -> dict | None:
        _, issuer, _, day, _ = meta[cid]
        return issuer_defaults(issuer, day) if args.mode == "golden" else None

    retry, retried = ask_again(
        spark, query, dict(prompts), answers, outcomes, judge, defaults_for
    )

    drafts, queue, counts = [], [], defaultdict(int)
    for cid, (response, error) in answers.items():
        lc, _, doc_paths, _, version = meta[cid]
        out = outcomes[cid]
        draft_id = str(uuid.uuid4())
        counts[out.status] += 1
        counts["problems"] += bool(out.problems)
        base = hashlib.sha256(files[lc.file].encode("utf-8")).hexdigest()
        drafts.append(
            (
                draft_id,
                cid,
                lc.card.issuer,
                args.mode,
                args.model,
                version,
                changed.get(cid, []),
                doc_paths,
                response,
                out.status,
                out.reason or error,
                out.draft_yaml,
                out.problems,
                base,
                retried.get(cid),
            )
        )
        if args.mode == "changes" and out.status in QUEUED:
            source = (changed.get(cid) or doc_paths)[0]
            queue.append(
                (
                    out.status,
                    lc.card.issuer,
                    cid,
                    subject(out.reason, lc.card.name, out.problems),
                    source,
                    "open",
                    draft_id,
                )
            )

    # 초안은 Python에서 만들고, 카드사 칸은 원문 표에서 가져오고 카드는 바뀐 원문 표나 정답 예시 표와 맞붙여 쓴다
    # 그래야 계보에 그 표들에서 drafts로 가는 선이 남는다. 작업 007 설계 2절
    cards = (
        docs.groupBy("card_id")
        .agg(F.first("issuer").alias("issuer"))
        .join(
            (golden if args.mode == "golden" else spark.table(f"{s}.changes"))
            .select("card_id")
            .distinct(),
            "card_id",
        )
    )
    columns = DRAFTS.replace(", created_at TIMESTAMP", "")
    (
        spark.createDataFrame(drafts, columns)
        .drop("issuer")
        .join(cards, "card_id")
        .withColumn("created_at", now)
        .write.mode("append")
        .saveAsTable(f"{s}.drafts")
    )
    if queue:
        to_queue(queue)

    # 정답 예시 모드는 실적 규칙 빈칸만 남은 답도 고쳐진 것으로 센다. 운영은 그 빈칸을 지금 값으로 채워 초안을 만든다
    # 2026-10-02 판 9에서 다시 물은 9장 중 2장만 고쳐졌다고 찍혔지만 4장은 이런 카드였다
    def fixed(cid: str) -> bool:
        o = outcomes[cid]
        if o.status != "needs_human":
            return True
        return bool(o.errors) and not retry_errors(
            o, answers[cid][0], defaults_for(cid)
        )

    print(
        f"추출한 카드 {len(answers)}장, 초안 {counts['draft']}, 바뀐 것 없음 {counts['no_change']}, "
        f"사람이 정할 것 {counts['needs_human']}, 검사에 걸린 초안 {counts['problems']}, 모델 호출 실패 {counts['model_error']}, "
        f"검수 대기 {len(queue)}건, 다시 올린 초안 {len(refill)}건, 골드에 없어 건너뛴 카드 {skipped}장, "
        f"형식 오류로 다시 물은 카드 {len(retry)}장, 그중 고쳐진 카드 {sum(map(fixed, retried))}장, "
        f"다시 묻기 호출 실패 {sum(v.startswith('다시 묻기 실패') for v in retried.values())}장"
    )
    if counts["model_error"]:
        raise SystemExit(
            f"모델 호출이 실패한 카드 {counts['model_error']}장. 다음 실행에서 다시 추출한다"
        )


# 새 카드 초안은 이만큼씩 묻고 그때마다 쓴다. 시간 제한이나 비용 차단에 걸려도 요금을 낸 답은 남는다. 2026-10-05 위험 검토
NEW_CARD_GROUP = 20
# 새 카드 프롬프트 판. 1: 카드사 기본값과 종류 묻기를 더했다. 바뀐 원문과 정답 예시 프롬프트 판 VERSION과 따로 센다
NEW_CARD_VERSION = "new1"


def new_cards(spark, args, s, files, cat, codes, now, to_queue) -> None:
    """색인에서 카탈로그에 없는 카드의 새 초안을 만든다. 작업 008 설계 3절.

    색인 카드 원문은 card_id가 비어 있어 받은 주소로 찾는다. 주소마다 가장 최근 문서를 쓴다.
    머리는 색인에서, 규칙은 모델이 쓴다. 초안이 생긴 카드는 다음 실행에서 다시 고르지 않는다. 모델 호출이 실패한 카드는 고른다.
    """
    if not args.bronze:
        raise SystemExit("new_card 모드는 --bronze가 있어야 원문 주소를 찾는다")
    if args.limit < 0:
        raise SystemExit("--limit은 0 이상이다. 0은 모두다")
    today = datetime.now(ZoneInfo("Asia/Seoul")).date()
    mine = spark.table(f"{s}.drafts").where("mode = 'new_card'")
    # 앞 실행이 초안을 쓰고 검수 대기를 쓰기 전에 끊겼으면 여기서 메운다
    queued = {
        r.draft_id
        for r in spark.table(f"{s}.queue")
        .where("draft_id IS NOT NULL")
        .select("draft_id")
        .collect()
    }
    past = {
        r.draft_id: r for r in mine.where(F.col("status").isin(list(QUEUED))).collect()
    }
    refill = [
        (
            "new_card",
            past[d].issuer,
            past[d].card_id,
            subject(past[d].reason, past[d].card_id, past[d].problems),
            past[d].doc_paths[0],
            "open",
            d,
        )
        for d in unqueued([(d, r.status) for d, r in past.items()], queued)
    ]
    if refill:
        to_queue(refill)
    rows = [
        r.asDict()
        for r in spark.table(f"{s}.card_index")
        .select(
            "issuer",
            "card_id",
            "name",
            "kind",
            "code",
            "status",
            "discontinued_on",
            "page_url",
            "pdf_urls",
            "recommended",
        )
        .collect()
    ]
    drafted = drafted_cards(
        [tuple(r) for r in mine.select("card_id", "status", "reason").collect()],
        {r["card_id"] for r in rows if r["kind"]},
    )
    latest = Window.partitionBy("url").orderBy(
        F.col("fetched_at").desc(), F.col("path").desc()
    )
    docs = {
        r.url: r.asDict()
        for r in spark.table(f"{s}.documents")
        # 우리 카드 상세 응답은 상품 페이지와 주소가 같다. 원문 종류로 걸러 상세 응답을 원문으로 쓰지 않는다. 위험 검토
        .where("card_id IS NULL AND kind IN ('product_page', 'manual_pdf')")
        .join(
            spark.table(f"cherry.{args.bronze}.fetches")
            .select("path", "url")
            .dropDuplicates(["path"]),
            "path",
        )
        .withColumn("day", F.to_date("fetched_at"))
        .withColumn("n", F.row_number().over(latest))
        .where("n = 1")
        .select("url", "path", "day")
        .collect()
    }
    issuers = {i.strip() for i in args.issuer.split(",") if i.strip()} or None
    picked = pick_new_cards(
        rows, set(cat.cards), drafted, docs, today, issuers, args.limit or None
    )
    texts = {
        r.path: r.text
        for r in spark.table(f"{s}.documents")
        .where(
            F.col("path").isin([d["path"] for _, found in picked for _, _, d in found])
        )
        .select("path", "text")
        .collect()
    }
    example = example_for(cat, "")
    version = f"{VERSION}+{NEW_CARD_VERSION}" + (f"+{example[2]}" if example else "")
    prompts, meta = [], {}
    for r, found in picked:
        sources = [(kind, url, d["day"], texts[d["path"]]) for kind, url, d in found]
        fetched = max(day for _, _, day, _ in sources)
        issuer = cat.issuers[r["issuer"]].raw if r["issuer"] in cat.issuers else None
        prompt = build_prompt(
            {"id": r["card_id"], "name": r["name"]},
            {},
            [(SOURCE_IDS[kind], text) for kind, _, _, text in sources],
            codes,
            example[:2] if example else None,
            titles=False,
            defaults=issuer_defaults(issuer, fetched) or None,
            ask_kind=not r["kind"],
        )
        prompts.append((r["card_id"], prompt))
        meta[r["card_id"]] = (
            r,
            card_head(r, sources, fetched),
            issuer,
            fetched,
            [text for *_, text in sources],
            [d["path"] for _, _, d in found],
        )
    if not prompts:
        print(f"새 초안을 만들 카드 0장, 검수 대기에 다시 올린 초안 {len(refill)}건")
        return

    query = model_query(args.model, args.max_tokens)

    def judge(cid: str, response: str | None, error: str | None):
        _, head, issuer, fetched, card_texts, _ = meta[cid]
        return process_new_card(
            files, head, issuer, response, error, fetched, card_texts
        )

    def defaults_for(cid: str) -> dict:
        _, _, issuer, fetched, _, _ = meta[cid]
        return issuer_defaults(issuer, fetched)

    counts, queued, retried_cards = defaultdict(int), 0, 0
    for n in range(0, len(prompts), NEW_CARD_GROUP):
        group = prompts[n : n + NEW_CARD_GROUP]
        answers = ask(spark, query, group)
        outcomes = {cid: judge(cid, *v) for cid, v in answers.items()}
        retry, retried = ask_again(
            spark, query, dict(group), answers, outcomes, judge, defaults_for
        )
        retried_cards += len(retry)
        drafts, queue = [], []
        for cid, (response, error) in answers.items():
            r, _, _, _, _, paths = meta[cid]
            out = outcomes[cid]
            draft_id = str(uuid.uuid4())
            counts[out.status] += 1
            counts["problems"] += bool(out.problems)
            drafts.append(
                (
                    draft_id,
                    cid,
                    r["issuer"],
                    "new_card",
                    args.model,
                    version,
                    [],
                    paths,
                    response,
                    out.status,
                    out.reason or error,
                    out.draft_yaml,
                    out.problems,
                    # 새 카드 초안의 기준 해시는 카드사 파일이다. 승인할 때 바뀌었으면 멈춘다. 작업 008 11단계
                    hashlib.sha256(
                        files.get(f"issuers/{r['issuer']}.yaml", "").encode("utf-8")
                    ).hexdigest(),
                    retried.get(cid),
                )
            )
            if out.status in QUEUED:
                queue.append(
                    (
                        "new_card",
                        r["issuer"],
                        cid,
                        subject(out.reason, f"{r['name']} 새 카드", out.problems),
                        paths[0],
                        "open",
                        draft_id,
                    )
                )
        # 카드사 칸은 색인 표에서 가져와 쓴다. 계보에 card_index에서 drafts로 가는 선이 남는다. 작업 007 설계 2절
        # 그사이 색인 단계가 card_id를 바꿔도 요금을 낸 초안이 빠지지 않게 바깥 맞붙이기로 쓰고 빈 칸은 고른 행의 값을 쓴다
        cards = (
            spark.table(f"{s}.card_index")
            .where(F.col("card_id").isin(list(answers)))
            .select("card_id", F.col("issuer").alias("index_issuer"))
            .dropDuplicates(["card_id"])
        )
        (
            spark.createDataFrame(drafts, DRAFTS.replace(", created_at TIMESTAMP", ""))
            .join(cards, "card_id", "left")
            .withColumn("issuer", F.coalesce("index_issuer", "issuer"))
            .drop("index_issuer")
            .withColumn("created_at", now)
            .write.mode("append")
            .saveAsTable(f"{s}.drafts")
        )
        if queue:
            to_queue(queue)
        queued += len(queue)
        print(f"묶음 {n // NEW_CARD_GROUP + 1} 새 카드 {len(answers)}장을 썼다")
    print(
        f"새 카드 {len(prompts)}장, 초안 {counts['draft']}, 사람이 정할 것 {counts['needs_human']}, "
        f"검사에 걸린 초안 {counts['problems']}, 모델 호출 실패 {counts['model_error']}, 검수 대기 {queued}건, "
        f"다시 올린 초안 {len(refill)}건, 형식 오류로 다시 물은 카드 {retried_cards}장"
    )
    if counts["model_error"]:
        raise SystemExit(
            f"모델 호출이 실패한 카드 {counts['model_error']}장. 다음 실행에서 다시 추출한다. 두 번 실패한 카드는 건너뛴다"
        )


if __name__ == "__main__":
    main()
