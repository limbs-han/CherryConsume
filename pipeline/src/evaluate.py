"""cherry_extract가 남긴 정답 예시 추출을 정답과 비교해 MLflow에 남긴다. 작업 003 과제 19, 설계 1절 7단계.

모델을 다시 부르지 않아 모델 요금이 들지 않는다. 카드마다 그 모델과 프롬프트 판의 가장 최근 답을 쓴다.
원문이 짝지어지지 않은 정답 예시는 채점하지 않는다. 모델 호출이 실패한 행은 쓰지 않고 그 판의 앞선 답을 쓴다.
모델이 적지 않은 카드사 공통 칸은 카드사 기본값으로 채워 채점한다. 채운 뒤에도 형식에 맞지 않는 답은 모든 칸이 틀린 것이다.
그래서 찍히는 상태는 채우기 전 초안의 상태이고, needs_human인 카드에도 점수가 날 수 있다. 채우지 않은 점수는 nofill 지표다.
다듬기용은 tune, 채점 전용은 holdout 지표로 남긴다. 찍는 것은 정확도와 개수뿐이다.
"""

import argparse
import tempfile
from pathlib import Path

import mlflow
from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.draft import issuer_defaults
from cherry_core.pipeline.score import score_answer, summarize
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F


def main(argv: list[str] | None = None) -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--silver", required=True)
    ap.add_argument("--gold", required=True)
    ap.add_argument("--model", required=True, help="cherry_extract에 넘긴 모델 이름")
    ap.add_argument(
        "--prompt-version", default="", help="비면 이 모델의 가장 최근 프롬프트 판"
    )
    ap.add_argument(
        "--experiment", required=True, help="MLflow 실험 경로. 없으면 만든다"
    )
    args = ap.parse_args(argv)
    if not args.model:
        raise SystemExit("채점할 모델을 적는다")
    spark = SparkSession.builder.getOrCreate()
    s = f"cherry.{args.silver}"

    drafts = spark.table(f"{s}.drafts").where(
        (F.col("mode") == "golden") & (F.col("model") == args.model)
    )
    version = args.prompt_version
    if not version:
        last = (
            drafts.orderBy(F.col("created_at").desc()).select("prompt_version").first()
        )
        if last is None:
            raise SystemExit(
                "이 모델의 정답 예시 추출이 없다. cherry_extract를 mode golden으로 먼저 돌린다"
            )
        version = last.prompt_version
    # 판 번호까지만 맞춘다. 예시 카드 자신을 추출할 때는 다른 예시를 써서 꼬리표가 다르다. 2026-10-02 NH 히어로즈가 빠졌다
    base = version.split("+")[0]
    latest = Window.partitionBy("card_id").orderBy(F.col("created_at").desc())
    answers = {
        r.card_id: r
        for r in drafts.where(
            (
                (F.col("prompt_version") == base)
                | F.col("prompt_version").startswith(base + "+")
            )
            # 호출 실패는 모델 실력이 아니다. 2026-10-02 위험 검토
            & (F.col("status") != "model_error")
        )
        .withColumn("n", F.row_number().over(latest))
        .where("n = 1")
        .collect()
    }
    tags = sorted({r.prompt_version for r in answers.values()})
    # 판 7부터 형식 오류는 한 번 더 묻는다. 다시 묻기가 실패하면 점수가 조용히 낮아져 판끼리 비교가 틀어진다
    reasons = [r.asDict().get("retry_reason") for r in answers.values()]
    retried = sum(x is not None for x in reasons)
    retry_failed = sum(
        x is not None and x.startswith("다시 묻기 실패") for x in reasons
    )

    # 모델이 적지 않은 카드사 공통 칸을 카드사 기본값으로 채워 채점한다. score_answer
    files = {
        r.path: r.yaml
        for r in spark.table(f"cherry.{args.gold}.catalog_files")
        .select("path", "yaml")
        .collect()
    }
    with tempfile.TemporaryDirectory() as tmp:
        for rel, text in files.items():
            (Path(tmp) / rel).parent.mkdir(parents=True, exist_ok=True)
            (Path(tmp) / rel).write_text(text, encoding="utf-8", newline="\n")
        issuers = {iid: li.raw for iid, li in load_catalog(Path(tmp)).issuers.items()}

    cards, raw_cards, per_card, missing = [], [], {}, []
    for g in spark.table(f"{s}.golden").collect():
        if not g.sources:
            continue  # 자동 수집 원문이 없는 카드. 사람이 원문을 더하면 채점에 들어간다
        d = answers.get(g.card_id)
        if d is None:
            missing.append(g.card_id)
            continue
        issuer = issuers.get(g.issuer)
        result = score_answer(
            g.rules,
            d.answer,
            issuer_defaults(issuer, g.effective_from) if issuer else None,
        )
        cards.append((g.split, result))
        raw_cards.append((g.split, score_answer(g.rules, d.answer)))
        per_card[g.card_id] = {
            "split": g.split,
            "status": d.status,
            "groups": {k: list(v) for k, v in result.items()},
        }
    if not cards:
        raise SystemExit("채점할 카드가 없다")
    metrics = summarize(cards)
    nofill = summarize(raw_cards)
    tune = sum(split == "tune" for split, _ in cards)
    holdout = len(cards) - tune

    mlflow.set_tracking_uri("databricks")
    # 작업 공간 경로의 /Workspace 앞붙이는 MLflow 실험 이름에 쓰지 않는다
    mlflow.set_experiment(args.experiment.removeprefix("/Workspace"))
    with mlflow.start_run(run_name=f"{args.model} 판 {base}"):
        mlflow.log_params(
            {
                "model": args.model,
                "prompt_version": base,
                "prompt_tags": ", ".join(tags),
                "tune_cards": tune,
                "holdout_cards": holdout,
                "missing": len(missing),
            }
        )
        mlflow.log_metrics(
            metrics
            | {f"nofill.{k}": v for k, v in nofill.items()}
            | {"retried": retried, "retry_failed": retry_failed}
        )
        mlflow.log_dict({"cards": per_card, "missing": sorted(missing)}, "cards.json")
    print(
        f"모델 {args.model}, 프롬프트 판 {base}, 다듬기용 {tune}장 {metrics.get('tune.all', 0):.1%}, "
        f"채점 전용 {holdout}장 {metrics.get('holdout.all', 0):.1%}, 추출이 없는 카드 {len(missing)}장, "
        f"다시 물은 카드 {retried}장, 다시 묻기 실패 {retry_failed}장"
    )
    print(
        f"  카드사 기본값을 채우지 않으면 다듬기용 {nofill.get('tune.all', 0):.1%}, "
        f"채점 전용 {nofill.get('holdout.all', 0):.1%}"
    )
    # 프롬프트를 다듬는 데 쓰는 것은 다듬기용뿐이다. 채점 전용은 합친 숫자만 찍는다. 계획 과제 19 2단계
    for g, v in sorted(metrics.items()):
        if g.startswith("tune.") and g != "tune.all":
            print(f"  {g} {v:.1%}")
    for cid, c in sorted(per_card.items()):
        if c["split"] == "tune":
            ok = sum(v[0] for v in c["groups"].values())
            total = sum(v[1] for v in c["groups"].values())
            print(f"  {cid} {c['status']} {ok}/{total}")


if __name__ == "__main__":
    main()
