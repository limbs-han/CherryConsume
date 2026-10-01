"""사람이 승인한 카탈로그 파일을 골드에 넣고 내보내기 폴더에 쓴다. 작업 003 과제 20의 승인 부분, 설계 4절 7번.

검수 앱이 생기기 전에는 사람이 바뀐 파일을 incoming 볼륨의 <이름>/catalog/ 아래에 올리고 이 작업을 돌린다.
값은 cherry_core.pipeline.approve가 만든다. 검사를 통과해야 쓴다.
쓰기 전에 골드 카탈로그 해시를 PC 값과 맞춘다. 옛 판을 고친 파일로 앞선 승인을 덮지 않으려는 것이다.
진행 상태는 silver.reviews에 둔다. 끝나지 않은 손 승인이 있으면 그것부터 끝내야 다음 승인이 돈다.
중간에 끊기면 같은 폴더 이름과 제목으로 다시 돌려 남은 단계를 한다. 쓰는 곳마다 다시 써도 결과가 같다.
순서: 검수 기록, gold.catalog_files, gold.card_revisions, 내보내기 폴더 파일, commit.json, 끝난 시각.
내보내기 파일을 골드 뒤에 써서, 골드에 쓰기 전에 끊긴 승인은 pending/에 아무것도 남기지 않는다.
찍는 것은 검수 번호, 단계, 개수뿐이다.
"""

import argparse
from datetime import UTC, datetime
from pathlib import Path

from cherry_core.pipeline.approve import (
    apply_changes,
    commit_json,
    new_review_id,
    resume_or_start,
    revision_rows_after,
    unexpected_renewals,
)
from cherry_core.pipeline.export import REVIEW_ID
from cherry_core.pipeline.seed import digest
from pyspark.sql import SparkSession

REVIEWS = (
    "review_id STRING, decision STRING, kind STRING, subject STRING, paths ARRAY<STRING>, reviewer STRING, note STRING, "
    "source STRING, run_id STRING, base_digest STRING, result_digest STRING, draft_id STRING, reviewed_at TIMESTAMP, "
    "finished_at TIMESTAMP"
)
REVISIONS = (
    "card_id STRING, issuer STRING, effective_from DATE, effective_from_estimated BOOLEAN, source STRING, "
    "rules STRING, review_id STRING"
)
KEY = (
    "card_id",
    "issuer",
    "effective_from",
    "effective_from_estimated",
    "source",
    "rules",
)


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument("--incoming", required=True, help="incoming 볼륨 안 폴더 이름")
    ap.add_argument(
        "--label", required=True, help="검수 번호 끝에 붙일 영문 소문자 이름"
    )
    ap.add_argument(
        "--subject", required=True, help="커밋 제목. feat: 또는 fix:로 시작한다"
    )
    ap.add_argument("--reviewer", required=True, help="승인한 사람")
    ap.add_argument("--note", default="", help="근거와 까닭")
    ap.add_argument(
        "--expect-files",
        default="",
        help="PC의 seed 명령이 찍은 카탈로그 파일 해시. 지금 골드와 같아야 한다",
    )
    ap.add_argument(
        "--run-id",
        default="",
        help="이 실행의 번호. 누가 돌렸는지는 작업 실행 기록에 남는다",
    )
    args = ap.parse_args(argv)
    if not args.reviewer.strip():
        raise SystemExit("승인한 사람을 적는다")
    if not REVIEW_ID.fullmatch(args.incoming):
        raise SystemExit("올린 폴더 이름에 쓸 수 없는 글자가 있다")
    spark = SparkSession.builder.getOrCreate()
    files_t, revisions_t = (
        f"cherry.{args.gold}.catalog_files",
        f"cherry.{args.gold}.card_revisions",
    )
    reviews_t = f"cherry.{args.silver}.reviews"
    folder_in = (
        Path(f"/Volumes/cherry/{args.gold}/incoming") / args.incoming / "catalog"
    )
    if not folder_in.is_dir():
        raise SystemExit("올린 폴더에 catalog/가 없다")

    spark.sql(f"CREATE TABLE IF NOT EXISTS {reviews_t} ({REVIEWS})")
    if "finished_at" not in spark.table(reviews_t).columns:
        spark.sql(f"ALTER TABLE {reviews_t} ADD COLUMNS (finished_at TIMESTAMP)")
        # 이 칸이 생기기 전의 손 승인은 진행 상태를 볼륨 파일에 두던 2026-10-01 개발용 시험의 끝난 승인이다
        # 운영 표는 처음부터 이 칸이 있어 타지 않는다. ALTER 뒤에 끊기면 이 UPDATE를 SQL로 한 번 돌린다
        spark.sql(
            f"UPDATE {reviews_t} SET finished_at = reviewed_at WHERE finished_at IS NULL AND kind = 'manual'"
        )
    manual = spark.table(reviews_t).where("kind = 'manual'")
    unfinished = [
        {"review_id": r.review_id, "source": r.source, "subject": r.subject}
        for r in manual.where("finished_at IS NULL").collect()
    ]
    found = manual.where(manual.source == args.incoming).collect()
    mine = (
        {
            "review_id": found[0].review_id,
            "subject": found[0].subject,
            "base": found[0].base_digest,
            "result": found[0].result_digest,
            "paths": list(found[0].paths or []),
            "finished": found[0].finished_at is not None,
        }
        if found
        else None
    )

    gold_rows = spark.table(files_t).select("path", "yaml", "review_id").collect()
    gold = {r.path: r.yaml for r in gold_rows}
    upload = {
        p.relative_to(folder_in).as_posix(): p.read_text(encoding="utf-8")
        for p in folder_in.rglob("*")
        if p.is_file()
    }
    resumed = resume_or_start(
        mine, unfinished, digest(list(gold.items())), args.expect_files
    )
    if resumed is None:
        files, changed = apply_changes(
            gold, upload
        )  # 검사에 걸리면 ValueError로 멈춘다
        review_id = new_review_id(datetime.now(UTC), args.label)
        base, result, subject = (
            digest(list(gold.items())),
            digest(list(files.items())),
            args.subject,
        )
    else:
        review_id, base, result, subject = (
            resumed["review_id"],
            resumed["base"],
            resumed["result"],
            resumed["subject"],
        )
        if args.subject != subject:
            raise SystemExit("제목이 처음 승인과 다르다. 처음 제목으로 다시 돌린다")
        already = {r.path for r in gold_rows if r.review_id == review_id}
        files, changed = apply_changes(gold, upload, already=already)
        # 골드에 이미 넣은 뒤라면 해시만으로는 올린 폴더에서 빠진 파일을 알 수 없어 파일 목록도 맞춘다
        if digest(list(files.items())) != result or set(changed) != set(
            resumed["paths"]
        ):
            raise SystemExit(
                "올린 파일이 끊긴 승인 때와 다르다. 올린 폴더를 고치지 않고 다시 돌린다"
            )
        print(f"끊긴 승인 {review_id}을 이어서 한다")
    commit = commit_json(
        subject, review_id, base, result
    )  # 제목이 틀리면 쓰기 전에 멈춘다
    old = [
        tuple(r) for r in spark.table(revisions_t).select(*KEY, "review_id").collect()
    ]
    rows = revision_rows_after(files, old, review_id)
    if strange := unexpected_renewals(rows, changed, review_id):
        raise SystemExit(
            f"바꾸지 않은 카드 {len(strange)}장의 개정이 바뀐다. 첫 번째: {strange[0]}. 규칙을 만드는 코드가 바뀌었는지 본다"
        )

    spark.createDataFrame(
        [
            (
                "approved",
                "manual",
                subject,
                list(changed),
                args.reviewer.strip(),
                args.note,
                args.incoming,
                args.run_id,
                base,
                result,
            )
        ],
        "decision STRING, kind STRING, subject STRING, paths ARRAY<STRING>, reviewer STRING, note STRING, "
        "source STRING, run_id STRING, base_digest STRING, result_digest STRING",
    ).createOrReplaceTempView("review")
    spark.sql(
        f"""MERGE INTO {reviews_t} t USING review r ON t.review_id = :rid
        WHEN NOT MATCHED THEN INSERT (review_id, decision, kind, subject, paths, reviewer, note, source, run_id,
          base_digest, result_digest, draft_id, reviewed_at, finished_at)
        VALUES (:rid, r.decision, r.kind, r.subject, r.paths, r.reviewer, r.note, r.source, r.run_id,
          r.base_digest, r.result_digest, NULL, current_timestamp(), NULL)""",
        args={"rid": review_id},
    )
    print(f"1/5 검수 기록 {review_id}")

    spark.createDataFrame(
        list(changed.items()), "path STRING, yaml STRING"
    ).createOrReplaceTempView("approved")
    spark.sql(
        f"""MERGE INTO {files_t} t USING approved a ON t.path = a.path
        WHEN MATCHED AND (t.yaml <> a.yaml OR t.review_id <> :rid) THEN
          UPDATE SET yaml = a.yaml, review_id = :rid, updated_at = current_timestamp()
        WHEN NOT MATCHED THEN INSERT (path, yaml, review_id, updated_at) VALUES (a.path, a.yaml, :rid, current_timestamp())""",
        args={"rid": review_id},
    )
    print("2/5 gold.catalog_files")

    spark.createDataFrame(rows, REVISIONS).createOrReplaceTempView("revisions")
    same = " AND ".join(f"t.{k} <=> s.{k}" for k in KEY)
    # 여섯 칸이 같은 행은 건드리지 않아 검수 번호와 시각이 그대로 남는다. 없어진 행은 지운다
    spark.sql(
        f"""MERGE INTO {revisions_t} t USING revisions s ON {same}
        WHEN NOT MATCHED THEN INSERT ({", ".join(KEY)}, review_id, updated_at)
          VALUES ({", ".join(f"s.{k}" for k in KEY)}, s.review_id, current_timestamp())
        WHEN NOT MATCHED BY SOURCE THEN DELETE"""
    )
    renewed = sum(r[6] == review_id for r in rows)
    print(f"3/5 gold.card_revisions, 새 검수 번호를 받은 개정 {renewed}개")

    export = Path(f"/Volumes/cherry/{args.gold}/export")
    folder_out = export / "pending" / review_id
    if (export / "done" / review_id / "commit.json").exists():
        # commit.json을 쓴 뒤 끝난 시각을 적기 전에 끊겼고, 그 사이 export가 저장소에 커밋해 옮겼다
        print("4/5, 5/5 이미 저장소에 커밋되어 내보내기를 건너뛴다")
    else:
        for rel, text in changed.items():
            (folder_out / "catalog" / rel).parent.mkdir(parents=True, exist_ok=True)
            (folder_out / "catalog" / rel).write_text(
                text, encoding="utf-8", newline="\n"
            )
        print(f"4/5 내보내기 폴더 파일 {len(changed)}개")
        (folder_out / "commit.json").write_text(commit, encoding="utf-8")
    spark.sql(
        f"UPDATE {reviews_t} SET finished_at = current_timestamp() WHERE review_id = :rid",
        args={"rid": review_id},
    )
    print(f"5/5 commit.json. 검수 번호 {review_id}, 바뀐 파일 {len(changed)}개")


if __name__ == "__main__":
    main()
