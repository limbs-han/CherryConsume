"""바뀐 원문과 카드사 목록의 새 카드, 사라진 카드를 가린다. 작업 003 과제 16, 설계 1절 3단계.

원문마다 가장 최근 문서와 그 직전 문서의 지문을 비교해 다르면 없어진 줄과 새 줄을 silver.changes에 쓴다.
처음 받은 원문은 정답 예시와 짝이라 바뀐 것으로 보지 않는다. 지문은 조회수를 가리고, 공지와 목록은 숫자를 가린다.
카드사 목록은 지난 목록과 비교해 바뀐 줄에서만 ai_query로 카드 이름을 뽑는다. 목록 전체를 다시 뽑으면 긴 목록은 뽑을 때마다
이름이 달라 가짜 새 카드와 사라진 카드가 쌓였다. 뽑은 이름은 silver.card_lists에, 새 카드와 사라진 카드는 silver.queue에 쓴다.
처음 받은 목록은 비교할 것이 없어 모델을 부르지 않는다.
찍는 것은 개수뿐이다.
"""

import argparse
import json
import re

import yaml
from cherry_core.pipeline.lists import list_changes
from cherry_core.pipeline.text import changed_lines
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

CHANGES = (
    "issuer STRING, card_id STRING, source_id STRING, kind STRING, old_path STRING, new_path STRING, "
    "removed ARRAY<STRING>, added ARRAY<STRING>, detected_at TIMESTAMP"
)
CARD_LISTS = (
    "issuer STRING, path STRING, old_path STRING, removed_names ARRAY<STRING>, added_names ARRAY<STRING>, "
    "model STRING, extracted_at TIMESTAMP"
)
QUEUE = "kind STRING, issuer STRING, card_id STRING, subject STRING, source_path STRING, status STRING, created_at TIMESTAMP"
LIST_PROMPT = (
    "아래 줄들은 한국 카드사의 카드 상품 목록 페이지에서 지난번과 달라진 줄이다. 이 줄들에 적힌 카드 상품 이름만 원문에 적힌 그대로 모두 뽑는다. "
    "신용카드, 체크카드 같은 분류 이름, 메뉴, 광고, 설명은 뽑지 않는다. 카드 이름이 없으면 빈 목록을 낸다.\n\n"
)
LIST_FORMAT = json.dumps(
    {
        "type": "json_schema",
        "json_schema": {
            "name": "card_names",
            "schema": {
                "type": "object",
                "properties": {"names": {"type": "array", "items": {"type": "string"}}},
                "required": ["names"],
            },
            "strict": True,
        },
    }
)
MODEL = re.compile(r"^[\w.-]+$")  # 모델 이름은 SQL에 그대로 들어가므로 글자를 좁힌다


def known_names(spark: SparkSession, gold: str) -> set[str]:
    """카탈로그의 name과 search_names. 과제 17의 골드 표가 생기기 전에는 비어 새 이름이 모두 검수 대기로 간다."""
    table = f"cherry.{gold}.catalog_files"
    if not spark.catalog.tableExists(table):
        return set()
    names = set()
    for row in spark.table(table).where("path LIKE 'cards/%'").select("yaml").collect():
        card = yaml.safe_load(row.yaml)
        names |= {card["name"], *card.get("search_names", [])}
    return names


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument(
        "--model",
        default="",
        help="카드 이름을 뽑을 모델의 서빙 엔드포인트 이름. 비면 목록은 보지 않는다",
    )
    ap.add_argument(
        "--list-issuers",
        default="",
        help="목록을 볼 카드사 id를 쉼표로 잇는다. 비면 목록은 보지 않는다",
    )
    args = ap.parse_args(argv)
    if args.model and not MODEL.match(args.model):
        raise SystemExit("모델 이름에 쓸 수 없는 글자가 있다")
    spark = SparkSession.builder.getOrCreate()
    s = f"cherry.{args.silver}"
    for name, columns in (
        ("changes", CHANGES),
        ("card_lists", CARD_LISTS),
        ("queue", QUEUE),
    ):
        spark.sql(f"CREATE TABLE IF NOT EXISTS {s}.{name} ({columns})")

    latest_two = (
        spark.table(f"{s}.documents")
        .withColumn(
            "rank",
            F.row_number().over(
                Window.partitionBy("issuer", "card_id", "source_id").orderBy(
                    F.col("fetched_at").desc()
                )
            ),
        )
        .where("rank <= 2")
        .collect()
    )
    pairs: dict[tuple, dict[int, object]] = {}
    for r in latest_two:
        pairs.setdefault((r.issuer, r.card_id, r.source_id), {})[r["rank"]] = r
    done = {
        r.new_path for r in spark.table(f"{s}.changes").select("new_path").collect()
    }

    changes = []
    for (issuer, card_id, source_id), docs in pairs.items():
        new, old = docs[1], docs.get(2)
        if old is None or new.path in done or new.fingerprint == old.fingerprint:
            continue
        removed, added = changed_lines(old.text, new.text, new.kind)
        if removed or added:
            changes.append(
                (
                    issuer,
                    card_id,
                    source_id,
                    new.kind,
                    old.path,
                    new.path,
                    removed,
                    added,
                )
            )
    if changes:
        (
            spark.createDataFrame(changes, CHANGES.rsplit(", detected_at", 1)[0])
            .withColumn("detected_at", F.current_timestamp())
            .write.mode("append")
            .saveAsTable(f"{s}.changes")
        )

    queued = extracted = 0
    known = known_names(spark, args.gold)
    issuers = (
        [i.strip() for i in args.list_issuers.split(",") if i.strip()]
        if args.model
        else []
    )
    seen = {r.path for r in spark.table(f"{s}.card_lists").select("path").collect()}

    def names_in(lines: list[str]) -> list[str]:
        if not lines:
            return []
        answer = spark.sql(
            f"SELECT ai_query('{args.model}', :prompt, responseFormat => :fmt) AS out",
            args={"prompt": LIST_PROMPT + "\n".join(lines), "fmt": LIST_FORMAT},
        ).first()
        return json.loads(answer.out)["names"]

    for issuer in issuers:
        docs = pairs.get((issuer, None, "list"), {})
        new, old = docs.get(1), docs.get(2)
        # 처음 받은 목록, 그대로인 목록, 이미 본 목록은 모델을 부르지 않는다
        if (
            new is None
            or old is None
            or new.path in seen
            or new.fingerprint == old.fingerprint
        ):
            continue
        removed, added = changed_lines(old.text, new.text, "list")
        removed_names, added_names = names_in(removed), names_in(added)
        extracted += 1
        spark.createDataFrame(
            [(issuer, new.path, old.path, removed_names, added_names, args.model)],
            CARD_LISTS.rsplit(", extracted_at", 1)[0],
        ).withColumn("extracted_at", F.current_timestamp()).write.mode(
            "append"
        ).saveAsTable(f"{s}.card_lists")
        new_cards, gone_cards = list_changes(
            old.text, new.text, removed_names, added_names, known
        )
        rows = [("new_card", issuer, None, n, new.path, "open") for n in new_cards]
        rows += [("gone_card", issuer, None, n, new.path, "open") for n in gone_cards]
        if rows:
            spark.createDataFrame(rows, QUEUE.rsplit(", created_at", 1)[0]).withColumn(
                "created_at", F.current_timestamp()
            ).write.mode("append").saveAsTable(f"{s}.queue")
            queued += len(rows)
    print(
        f"바뀐 원문 {len(changes)}개, 목록을 뽑은 카드사 {extracted}곳, 검수 대기에 올린 카드 {queued}건"
    )


if __name__ == "__main__":
    main()
