"""상품공시실 원문에서 카드 색인 silver.card_index를 만든다. 작업 008 설계 1절, 계획 4.6.

묶음 고르기, 단종 안전장치, card_id 정하기는 cherry_core.pipeline.card_index에 있고 Spark 없이 테스트한다.
원문은 글로 바꾸기 전 그대로 raw 볼륨에서 읽는다. 글 뽑기가 PDF와 상품 페이지 주소를 버리기 때문이다.
행은 Python에서 만들고 documents 표와 원문 경로로 맞붙여 MERGE한다. 그래야 계보에 documents에서 card_index로 가는 선이 남는다.
사라진 카드는 지우지 않는다. 판매 중이던 카드가 묶음에 없으면 단종으로 바꾸고 그 묶음의 한국 날짜를 추정 단종일로 둔다.
카드다모아 묶음은 카드사 묶음 뒤에 따로 다룬다. 판매 중 색인 행 가운데 추천 카드와 짝인 것만 recommended를 켠다. 계획 4.7.
requested는 사람이 카드 요청 설문 답을 보고 SQL로 켠다. 이 작업은 그 칸을 바꾸지 않는다. 작업 008 설계 5절.
한 카드사가 실패해도 다른 카드사는 계속하고, 끝에 실패한 카드사를 모아 실패로 끝내 알림을 받는다.
찍는 것은 개수와 짝을 못 찾은 행의 이름뿐이다. 카드 이름은 공개된 상품 이름이다.
"""

import argparse
from dataclasses import replace
from pathlib import Path

import yaml
from cherry_core.pipeline.card_index import pick_batches, settle_ids, too_many_dropped
from cherry_core.pipeline.disclosure import (
    KnownCard,
    card_ids,
    merge_rows,
    must_have_rows,
    read,
    recommended_keys,
    row_key,
)
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

INDEX = (
    "issuer STRING, key STRING, name STRING, kind STRING, code STRING, card_id STRING, status STRING, "
    "launched_on DATE, discontinued_on DATE, discontinued_estimated BOOLEAN, page_url STRING, pdf_urls ARRAY<STRING>, "
    "recommended BOOLEAN, first_seen TIMESTAMP, last_seen TIMESTAMP, source_path STRING, requested BOOLEAN"
)
ROW = (
    "issuer STRING, key STRING, name STRING, kind STRING, code STRING, card_id STRING, status STRING, "
    "launched_on DATE, discontinued_on DATE, page_url STRING, pdf_urls ARRAY<STRING>, source_path STRING"
)
DAMOA = "carddamoa"
# 추정 단종일은 한국 날짜다. 새벽 수집이면 UTC 날짜가 하루 앞이다
SEEN_DAY = "to_date(from_utc_timestamp(:seen, 'Asia/Seoul'))"


def known_cards(spark: SparkSession, gold: str) -> list[KnownCard]:
    out = []
    for row in (
        spark.table(f"cherry.{gold}.catalog_files")
        .where("path LIKE 'cards/%'")
        .select("yaml")
        .collect()
    ):
        card = yaml.safe_load(row.yaml)
        names = (card["name"], *card.get("search_names", []))
        out.append(
            KnownCard(
                card["id"],
                card["issuer"],
                names,
                tuple(str(c) for c in card.get("product_codes") or []),
            )
        )
    return out


def lineage(spark: SparkSession, documents: str, rows: list, schema: str):
    """계산한 행을 원문 행과 경로로 맞붙인다. 계산한 행만 쓰면 Unity Catalog 계보가 끊긴다.

    경로가 어긋나 빠진 행이 있으면 쓰기 전에 멈춘다.
    """
    joined = (
        spark.table(documents)
        .select("path")
        .join(
            spark.createDataFrame(rows, schema), F.col("path") == F.col("source_path")
        )
        .drop("path")
    )
    if joined.count() != len(rows):
        raise ValueError("계산한 행과 맞붙인 원문 행 수가 다르다")
    return joined


def index_issuer(
    spark, index, documents, raw, issuer, batch, known, catalog_ids
) -> None:
    seen = batch[0].fetched_at
    rows = []
    for d in batch:
        got = read(issuer, d.source_id, Path(f"{raw}/{d.path}").read_bytes())
        if not got and must_have_rows(issuer, d.source_id):
            raise ValueError(f"{d.source_id} 응답에서 카드를 하나도 못 읽었다")
        rows += [replace(r, source_path=d.path) for r in got]
    merged, unmatched = merge_rows(rows)
    unique, keys = [], set()
    for r in merged:
        if row_key(r) not in keys:
            keys.add(row_key(r))
            unique.append(r)
    current = (
        spark.table(index)
        .where(F.col("issuer") == issuer)
        .select("key", "card_id", "status")
        .collect()
    )
    reason = too_many_dropped(
        {r.key for r in current if r.status == "on_sale"},
        {row_key(r) for r in unique if r.status == "on_sale"},
    )
    if reason:
        raise ValueError(f"{reason}. 읽기 함수를 본다")
    own = card_ids(unique, [])
    settled = settle_ids(
        issuer,
        [
            (row_key(r), cid, in_catalog, own_id, r.status == "on_sale")
            for r, (cid, in_catalog), (own_id, _) in zip(
                unique, card_ids(unique, known), own
            )
        ],
        {r.key: (r.card_id, r.status == "on_sale") for r in current},
        catalog_ids,
    )
    ids = settled.ids
    computed = [
        (issuer, row_key(r), r.name, r.kind, r.code, cid, r.status, r.launched_on, r.discontinued_on,
         r.page_url, list(r.pdf_urls), r.source_path)
        for r, cid in zip(unique, ids)
    ]  # fmt: skip
    lineage(spark, documents, computed, ROW).createOrReplaceTempView("batch")
    spark.sql(
        f"""MERGE INTO {index} t USING batch s ON t.issuer = s.issuer AND t.key = s.key
        WHEN MATCHED THEN UPDATE SET
          name = s.name, kind = coalesce(s.kind, t.kind), code = coalesce(s.code, t.code), card_id = s.card_id,
          status = s.status,
          discontinued_on = CASE WHEN s.status = 'on_sale' THEN NULL
            ELSE coalesce(s.discontinued_on, t.discontinued_on, CASE WHEN t.status = 'on_sale' THEN {SEEN_DAY} END) END,
          discontinued_estimated = CASE WHEN s.status = 'on_sale' OR s.discontinued_on IS NOT NULL THEN false
            WHEN t.discontinued_on IS NOT NULL THEN t.discontinued_estimated
            ELSE t.status = 'on_sale' END,
          launched_on = coalesce(s.launched_on, t.launched_on), page_url = coalesce(s.page_url, t.page_url),
          pdf_urls = s.pdf_urls, last_seen = :seen, source_path = s.source_path
        WHEN NOT MATCHED THEN INSERT (issuer, key, name, kind, code, card_id, status, launched_on, discontinued_on,
          discontinued_estimated, page_url, pdf_urls, recommended, first_seen, last_seen, source_path, requested)
          VALUES (s.issuer, s.key, s.name, s.kind, s.code, s.card_id, s.status, s.launched_on, s.discontinued_on,
          false, s.page_url, s.pdf_urls, false, :seen, :seen, s.source_path, false)
        WHEN NOT MATCHED BY SOURCE AND t.issuer = :issuer AND t.status = 'on_sale' THEN
          UPDATE SET status = 'discontinued', discontinued_on = {SEEN_DAY}, discontinued_estimated = true""",
        args={"seen": seen, "issuer": issuer},
    )
    if settled.moves:
        # 카탈로그 id를 새 판에 넘긴 옛 행 가운데 이번 묶음에 없는 행은 위 MERGE가 id를 못 바꿔 따로 고친다
        moves = spark.createDataFrame(
            list(settled.moves.items()), "key STRING, card_id STRING"
        )
        moves.createOrReplaceTempView("moves")
        spark.sql(
            f"""MERGE INTO {index} t USING moves s ON t.issuer = :issuer AND t.key = s.key
            WHEN MATCHED THEN UPDATE SET card_id = s.card_id""",
            args={"issuer": issuer},
        )
    print(
        f"{issuer} 원문 {len(batch)}개, 색인 {len(unique)}장, 판매 중 {sum(r.status == 'on_sale' for r in unique)}장, "
        f"카탈로그 짝 {sum(cid in catalog_ids for cid in ids)}장, 열쇠 겹침 {len(merged) - len(unique)}장, "
        f"짝 없는 보충 행 {len(unmatched)}개"
    )
    for note in settled.notes:
        print(f"  {note}")
    for r in unmatched[:20]:
        print(f"  짝 없음 {r.name or r.detail_ref}")


def recommend(spark, index, documents, raw, batch) -> None:
    recs = []
    for d in batch:
        content = Path(f"{raw}/{d.path}").read_bytes()
        recs += [
            replace(r, source_path=d.path) for r in read(DAMOA, d.source_id, content)
        ]
    if not recs:
        raise ValueError(
            "카드다모아 응답에서 추천 카드를 하나도 못 읽었다. 읽기 함수를 본다"
        )
    current = [
        (r.issuer, r.key, r.name, r.page_url)
        for r in spark.table(index)
        .where("status = 'on_sale'")
        .select("issuer", "key", "name", "page_url")
        .collect()
    ]
    found, missing = recommended_keys(recs, current)
    rows = [(issuer, key, r.source_path) for (issuer, key), r in found.items()]
    schema = "issuer STRING, key STRING, source_path STRING"
    lineage(spark, documents, rows, schema).createOrReplaceTempView("recommended")
    spark.sql(
        f"""MERGE INTO {index} t USING recommended s ON t.issuer = s.issuer AND t.key = s.key
        WHEN MATCHED AND NOT t.recommended THEN UPDATE SET recommended = true
        WHEN NOT MATCHED BY SOURCE AND t.recommended THEN UPDATE SET recommended = false"""
    )
    print(f"카드다모아 추천 {len(recs)}장, 색인 짝 {len(found)}장")
    for r in missing:
        print(f"  추천 짝 없음 {r.issuer} {r.name}")


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bronze", required=True)
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    args = ap.parse_args(argv)
    spark = SparkSession.builder.getOrCreate()
    fetches = f"cherry.{args.bronze}.fetches"
    documents, index = (
        f"cherry.{args.silver}.documents",
        f"cherry.{args.silver}.card_index",
    )
    raw = f"/Volumes/cherry/{args.bronze}/raw"
    spark.sql(f"CREATE TABLE IF NOT EXISTS {index} ({INDEX})")
    if "requested" not in spark.table(index).columns:
        # 작업 008 13단계 전에 만든 표. 요청 표시는 지금까지 없었으니 모두 false다
        spark.sql(f"ALTER TABLE {index} ADD COLUMNS (requested BOOLEAN)")
        spark.sql(f"UPDATE {index} SET requested = false WHERE requested IS NULL")

    lines = (
        spark.table(fetches)
        .where("kind = 'disclosure'")
        .select("issuer", "source_id", "path", "fetched_at")
        .collect()
    )
    done = {
        r.issuer: r.seen
        for r in spark.table(index)
        .groupBy("issuer")
        .agg(F.max("last_seen").alias("seen"))
        .collect()
    }
    parsed = {
        r.path
        for r in spark.table(documents)
        .where("kind = 'disclosure'")
        .select("path")
        .collect()
    }
    batches, waiting = pick_batches(lines, done, parsed)
    for issuer in waiting:
        print(f"{issuer} 공시 묶음은 아직 글 뽑기 전이라 다음 실행에서 읽는다")
    known = known_cards(spark, args.gold)
    catalog_ids = {k.card_id for k in known}

    failed = []
    # 카드다모아는 카드사 색인이 다 바뀐 뒤에 짝짓는다
    for issuer in sorted(batches, key=lambda i: (i == DAMOA, i)):
        try:
            if issuer == DAMOA:
                recommend(spark, index, documents, raw, batches[issuer])
            else:
                index_issuer(
                    spark,
                    index,
                    documents,
                    raw,
                    issuer,
                    batches[issuer],
                    known,
                    catalog_ids,
                )
        except Exception as e:  # noqa: BLE001 한 카드사가 깨져도 나머지 카드사는 색인한다
            failed.append(issuer)
            print(f"{issuer} 실패: {type(e).__name__} {e}")
    if not batches:
        print("새 공시 묶음이 없다")
    if failed:
        raise SystemExit(f"색인 실패 카드사: {', '.join(failed)}")


if __name__ == "__main__":
    main()
