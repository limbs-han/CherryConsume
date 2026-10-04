"""사람이 승인한 카탈로그 파일을 골드에 넣고 내보내기 폴더에 쓴다. 작업 003 과제 20의 승인 부분, 설계 4절 7번.

사람이 바뀐 파일을 incoming 볼륨의 <이름>/catalog/ 아래에 올리고 이 작업을 돌린다. 손 승인이다.
검수 앱도 고친 초안을 같은 곳에 올리고 draft_id와 함께 이 작업을 돌린다. 앱은 표를 읽기만 하고 쓰기는 이 작업만 한다.
초안 승인은 PC 해시 대신 초안을 만들 때의 골드 카드 파일 해시로 맞추고, 올린 파일이 그 카드 파일 하나여야 한다.
decision reject는 검수 기록에 반려를 적고 대기 건을 닫는다. 골드는 그대로다. 작업 003 과제 20
값은 cherry_core.pipeline.approve가 만든다. 검사를 통과해야 쓴다.
쓰기 전에 골드 카탈로그 해시를 PC 값과 맞춘다. 옛 판을 고친 파일로 앞선 승인을 덮지 않으려는 것이다.
진행 상태는 silver.reviews에 둔다. 끝나지 않은 손 승인이 있으면 그것부터 끝내야 다음 승인이 돈다.
중간에 끊기면 같은 폴더 이름과 제목으로 다시 돌려 남은 단계를 한다. 쓰는 곳마다 다시 써도 결과가 같다.
순서: 검수 기록, gold.catalog_files, gold.card_revisions, 내보내기 폴더 파일, commit.json, 끝난 시각.
내보내기 파일을 골드 뒤에 써서, 골드에 쓰기 전에 끊긴 승인은 pending/에 아무것도 남기지 않는다.
찍는 것은 검수 번호, 단계, 개수뿐이다.
"""

import argparse
import hashlib
from datetime import UTC, datetime
from pathlib import Path

import yaml
from cherry_core.catalog.canonical import canonical_text
from cherry_core.pipeline.approve import (
    apply_changes,
    commit_json,
    draft_plan,
    draft_subject,
    new_review_id,
    resume_or_start,
    revision_rows_after,
    stale_exports,
    unexpected_renewals,
)
from cherry_core.pipeline.export import REVIEW_ID
from cherry_core.pipeline.history import change_feed_sql
from cherry_core.pipeline.seed import digest
from pyspark.sql import SparkSession
from pyspark.sql.functions import col

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
    ap.add_argument("--incoming", default="", help="incoming 볼륨 안 폴더 이름")
    ap.add_argument("--label", default="", help="검수 번호 끝에 붙일 영문 소문자 이름")
    ap.add_argument(
        "--subject",
        default="",
        help="커밋 제목. feat: 또는 fix:로 시작한다. 초안 승인은 비우면 카드 파일로 만든다",
    )
    ap.add_argument(
        "--draft-id", default="", help="검수 앱이 승인하거나 반려하는 초안 번호"
    )
    ap.add_argument("--decision", choices=["approve", "reject"], default="approve")
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
    if args.draft_id and not REVIEW_ID.fullmatch(args.draft_id):
        raise SystemExit("초안 번호에 쓸 수 없는 글자가 있다")
    if args.decision == "reject" and not args.draft_id:
        raise SystemExit("반려할 초안 번호를 적는다")
    if not args.draft_id and not (args.label and args.subject):
        raise SystemExit("손 승인은 label과 subject를 적는다")
    label = args.label or ("reject" if args.decision == "reject" else "draft")
    spark = SparkSession.builder.getOrCreate()
    files_t, revisions_t = (
        f"cherry.{args.gold}.catalog_files",
        f"cherry.{args.gold}.card_revisions",
    )
    reviews_t, queue_t = f"cherry.{args.silver}.reviews", f"cherry.{args.silver}.queue"

    spark.sql(f"CREATE TABLE IF NOT EXISTS {reviews_t} ({REVIEWS})")
    if "finished_at" not in spark.table(reviews_t).columns:
        spark.sql(f"ALTER TABLE {reviews_t} ADD COLUMNS (finished_at TIMESTAMP)")
        # 이 칸이 생기기 전의 손 승인은 진행 상태를 볼륨 파일에 두던 2026-10-01 개발용 시험의 끝난 승인이다
        # 운영 표는 처음부터 이 칸이 있어 타지 않는다. ALTER 뒤에 끊기면 이 UPDATE를 SQL로 한 번 돌린다
        spark.sql(
            f"UPDATE {reviews_t} SET finished_at = reviewed_at WHERE finished_at IS NULL AND kind = 'manual'"
        )
    draft, open_now, incoming = None, False, args.incoming
    if args.draft_id:
        found_draft = (
            spark.table(f"cherry.{args.silver}.drafts")
            .where(col("draft_id") == args.draft_id)
            .collect()
        )
        # 아래에서 골드에 쓸 행을 이 초안 행과 맞붙인다. 행이 없거나 여럿이면 쓰는 행 수가 바뀌므로 여기서 멈춘다
        if len(found_draft) != 1:
            raise SystemExit(
                f"초안을 찾지 못했거나 같은 id의 초안이 {len(found_draft)}개다"
            )
        draft = found_draft[0]
        open_now = (
            spark.table(queue_t)
            .where((col("draft_id") == args.draft_id) & (col("status") == "open"))
            .count()
            > 0
        )
        records = [
            {
                "decision": r.decision,
                "source": r.source,
                "finished": r.finished_at is not None,
            }
            for r in spark.table(reviews_t)
            .where(col("draft_id") == args.draft_id)
            .orderBy("reviewed_at")
            .collect()
        ]
        try:
            plan, resume_from = draft_plan(args.decision, records)
        except ValueError as e:
            raise SystemExit(str(e)) from None
        if plan == "close":
            # 기록은 끝났는데 대기 건을 닫기 전에 끊겼다. 대기 건만 닫는다
            status = "rejected" if args.decision == "reject" else "approved"
            spark.sql(
                f"UPDATE {queue_t} SET status = :status WHERE draft_id = :draft",
                args={"status": status, "draft": args.draft_id},
            )
            print(
                f"이미 끝난 검수다. 대기 건만 {status}로 닫았다. 초안 {args.draft_id}"
            )
            return
        if plan in ("start", "reject") and not open_now:
            raise SystemExit("열린 검수 대기 건이 아니다")
        if plan == "resume":
            # 앱은 버튼마다 새 폴더 이름을 만든다. 끊긴 앱 승인은 그때 올린 폴더로 이어 한다
            incoming = resume_from
            print(f"끊긴 앱 승인을 폴더 {incoming}로 이어 한다")
    if args.decision == "reject":
        review_id = new_review_id(datetime.now(UTC), label)
        spark.sql(
            f"""INSERT INTO {reviews_t} (review_id, decision, kind, subject, paths, reviewer, note, source, run_id,
              base_digest, result_digest, draft_id, reviewed_at, finished_at)
            VALUES (:rid, 'rejected', 'app', '', CAST(array() AS ARRAY<STRING>), :reviewer, :note, NULL, :run,
              NULL, NULL, :draft, current_timestamp(), current_timestamp())""",
            args={
                "rid": review_id,
                "reviewer": args.reviewer.strip(),
                "note": args.note,
                "run": args.run_id,
                "draft": args.draft_id,
            },
        )
        spark.sql(
            f"UPDATE {queue_t} SET status = 'rejected' WHERE draft_id = :draft",
            args={"draft": args.draft_id},
        )
        print(f"반려했다. 검수 번호 {review_id}, 초안 {args.draft_id}")
        return
    if draft is not None and plan == "start" and args.gold == "gold":
        # 하루 넘게 남은 내보내기 폴더는 export가 커밋하지 못한 것이다. 그 위에 쌓으면 뒤 폴더가 모두 걸린다
        # export는 운영 골드만 읽어 개발용 pending은 아무도 비우지 않는다. 그래서 운영에서만 본다. 다시 검토
        pending = Path(f"/Volumes/cherry/{args.gold}/export/pending")
        names = (
            [p.name for p in pending.iterdir() if p.is_dir()]
            if pending.is_dir()
            else []
        )
        if stale := stale_exports(names, datetime.now(UTC)):
            raise SystemExit(
                f"내보내기에 오래 남은 폴더가 있다: {stale[0]}. export를 먼저 고친다"
            )

    if not REVIEW_ID.fullmatch(incoming):
        raise SystemExit("올린 폴더 이름이 비었거나 쓸 수 없는 글자가 있다")
    folder_in = Path(f"/Volumes/cherry/{args.gold}/incoming") / incoming / "catalog"
    if not folder_in.is_dir():
        raise SystemExit("올린 폴더에 catalog/가 없다")
    # 손 승인과 검수 앱 승인은 같은 진행 상태를 쓴다. 끝나지 않은 승인이 있으면 어느 쪽이든 그것부터 끝낸다
    approvals = spark.table(reviews_t).where("kind IN ('manual', 'app')")
    unfinished = [
        {
            "review_id": r.review_id,
            "source": r.source,
            "subject": r.subject,
            "draft_id": r.draft_id,
        }
        for r in approvals.where("finished_at IS NULL").collect()
    ]
    found = approvals.where(approvals.source == incoming).collect()
    if found and draft is None and found[0].kind == "app":
        # 앱 승인을 손 승인으로 이으면 저장 형식 맞추기와 대기 건 닫기가 빠진다. 다시 검토
        raise SystemExit(
            f"앱 승인이다. 검수 앱에서 초안 {found[0].draft_id}을 다시 승인한다"
        )
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
    subject_in, expect, card_path = args.subject, args.expect_files, None
    if draft is not None:
        card_path = next(
            (
                p
                for p in gold
                if p.startswith("cards/") and p.endswith(f"/{draft.card_id}.yaml")
            ),
            None,
        )
        if card_path is None or card_path not in upload:
            raise SystemExit("올린 폴더에 초안의 카드 파일이 없다")
        # 앱에서 고친 글은 저장 형식이 아닐 수 있다. 앱 사용자는 format 명령을 돌릴 수 없어 여기서 맞춘다
        try:
            loaded = yaml.safe_load(upload[card_path])
        except yaml.YAMLError as e:
            raise SystemExit(f"올린 카드 파일을 YAML로 읽지 못했다: {e}") from None
        if not isinstance(loaded, dict):
            raise SystemExit("올린 카드 파일이 카드 파일 모양이 아니다")
        upload[card_path] = canonical_text(loaded)
        # 이어 할 때는 골드가 이미 바뀌어 처음 제목을 그대로 쓴다. 새 승인의 제목은 검사를 통과한 뒤 만든다
        subject_in = subject_in or (mine["subject"] if mine else "")
        if mine is None:
            now_sha = hashlib.sha256(gold[card_path].encode("utf-8")).hexdigest()
            if now_sha != draft.base_sha256:
                raise SystemExit(
                    "초안을 만든 뒤 골드의 카드 파일이 바뀌었다. 반려하고, 초안의 변경은 지금 골드 판에 손 승인으로 넣는다"
                )
            # 카드 파일 해시를 맞췄으니 PC 해시 대신 지금 골드를 기준으로 삼는다
            expect = digest(list(gold.items()))
    resumed = resume_or_start(mine, unfinished, digest(list(gold.items())), expect)
    if resumed is None:
        files, changed = apply_changes(
            gold, upload
        )  # 검사에 걸리면 ValueError로 멈춘다
        review_id = new_review_id(datetime.now(UTC), label)
        if card_path is not None and not subject_in:
            subject_in = draft_subject(upload[card_path], gold.get(card_path))
        base, result, subject = (
            digest(list(gold.items())),
            digest(list(files.items())),
            subject_in,
        )
    else:
        review_id, base, result, subject = (
            resumed["review_id"],
            resumed["base"],
            resumed["result"],
            resumed["subject"],
        )
        if subject_in != subject:
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
    if card_path is not None and set(changed) != {card_path}:
        raise SystemExit("올린 파일이 초안의 카드 파일 하나가 아니거나 바뀐 것이 없다")
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

    def from_draft(rows, expected: int):
        # 검수 앱 승인은 골드에 쓸 행을 그 초안의 drafts 행 하나와 맞붙인다. 계보에 drafts에서 catalog_files와
        # card_revisions로 가는 선이 남는다. 작업 007 설계 2절
        # 개정 표는 원본에 없는 행을 지워서, 맞붙인 행이 줄면 개정이 지워진다. 검수 기록을 쓰기 전에 행 수를 센다
        if draft is None:
            return rows
        joined = rows.crossJoin(
            spark.table(f"cherry.{args.silver}.drafts")
            .where(col("draft_id") == args.draft_id)
            .select("draft_id")
        )
        if joined.count() != expected:
            raise SystemExit("초안 행과 맞붙인 골드 행 수가 다르다. 쓰기 전에 멈춘다")
        return joined

    from_draft(
        spark.createDataFrame(list(changed.items()), "path STRING, yaml STRING"),
        len(changed),
    ).createOrReplaceTempView("approved")
    from_draft(
        spark.createDataFrame(rows, REVISIONS), len(rows)
    ).createOrReplaceTempView("revisions")

    spark.createDataFrame(
        [
            (
                "approved",
                "app" if draft is not None else "manual",
                subject,
                list(changed),
                args.reviewer.strip(),
                args.note,
                incoming,
                args.run_id,
                base,
                result,
                args.draft_id or None,
            )
        ],
        "decision STRING, kind STRING, subject STRING, paths ARRAY<STRING>, reviewer STRING, note STRING, "
        "source STRING, run_id STRING, base_digest STRING, result_digest STRING, draft_id STRING",
    ).createOrReplaceTempView("review")
    spark.sql(
        f"""MERGE INTO {reviews_t} t USING review r ON t.review_id = :rid
        WHEN NOT MATCHED THEN INSERT (review_id, decision, kind, subject, paths, reviewer, note, source, run_id,
          base_digest, result_digest, draft_id, reviewed_at, finished_at)
        VALUES (:rid, r.decision, r.kind, r.subject, r.paths, r.reviewer, r.note, r.source, r.run_id,
          r.base_digest, r.result_digest, r.draft_id, current_timestamp(), NULL)""",
        args={"rid": review_id},
    )
    print(f"1/5 검수 기록 {review_id}")

    spark.sql(
        f"""MERGE INTO {files_t} t USING approved a ON t.path = a.path
        WHEN MATCHED AND (t.yaml <> a.yaml OR t.review_id <> :rid) THEN
          UPDATE SET yaml = a.yaml, review_id = :rid, updated_at = current_timestamp()
        WHEN NOT MATCHED THEN INSERT (path, yaml, review_id, updated_at) VALUES (a.path, a.yaml, :rid, current_timestamp())""",
        args={"rid": review_id},
    )
    print("2/5 gold.catalog_files")

    # 개정 이력 파이프라인이 이 표의 변경 데이터 피드를 읽는다. 쓰기 전에 모자란 설정만 켠다. 서비스 주체라 운영 표도 된다
    # 작업 010 설계 1절
    current = {r.key: r.value for r in spark.sql(f"SHOW TBLPROPERTIES {revisions_t}").collect()}
    if alter := change_feed_sql(revisions_t, current):
        spark.sql(alter)
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
    if draft is not None:
        spark.sql(
            f"UPDATE {queue_t} SET status = 'approved' WHERE draft_id = :draft",
            args={"draft": args.draft_id},
        )
        print(f"검수 대기 건을 닫았다. 초안 {args.draft_id}")


if __name__ == "__main__":
    main()
