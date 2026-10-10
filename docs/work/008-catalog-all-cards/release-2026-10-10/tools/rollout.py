"""release-2026-10-10 승인 목록을 운영에 반영한다. 2026-10-10 사용자가 "지금 38장 먼저 운영에 반영해"라고 했다.

순서: 공통 파일 손 승인, 그다음 새 카드를 초안 번호로 하나씩 승인. 운영 cherry_approve는 한 번에 하나만 돈다.
`uv run --project backend python tmp/release-card-expansion/rollout.py [shared|cards]`. 끝난 것은 rollout-log.json에 남겨 다시 돌리면 건너뛴다.
"""

import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
# 두 번째 묶음부터: rollout.py <shared|cards> <폴더 이름> <올리기 이름 꼬리>
REL = ROOT / "docs/work/008-catalog-all-cards" / (sys.argv[2] if len(sys.argv) > 2 else "release-2026-10-10")
TAG = sys.argv[3] if len(sys.argv) > 3 else "20261010"
LOG = BASE / ("rollout-log.json" if len(sys.argv) <= 3 else f"rollout-log-{sys.argv[3]}.json")
VOL = "dbfs:/Volumes/cherry/gold/incoming"
DB = shutil.which("databricks") or "databricks"
manifest = json.loads((REL / "approval-manifest.json").read_text(encoding="utf-8"))
log = json.loads(LOG.read_text(encoding="utf-8")) if LOG.exists() else {}


def cli(*args, tries=4):
    for i in range(tries):
        r = subprocess.run(
            [DB, *args], check=False, capture_output=True, text=True, encoding="utf-8"
        )
        if r.returncode == 0:
            return r.stdout
        # 이 PC에서 TLS 연결이 가끔 끊긴다. 네트워크 오류만 다시 한다
        if "timeout" not in r.stderr and "connection" not in r.stderr.lower():
            raise SystemExit(f"{' '.join(args[:3])} 실패: {r.stderr[-800:]}")
        time.sleep(10 * (i + 1))
    raise SystemExit(f"{' '.join(args[:3])} 네트워크 실패: {r.stderr[-400:]}")


def upload(local, name):
    cli("fs", "cp", "-r", str(local), f"{VOL}/{name}/catalog", "--overwrite")


def approve(key, params):
    if log.get(key) == "SUCCESS":
        print("건너뜀", key)
        return
    f = BASE / "rollout-params.json"
    f.write_text(
        json.dumps(
            {"job_id": manifest["job_id"], "job_parameters": params}, ensure_ascii=False
        ),
        encoding="utf-8",
    )
    out = cli(
        "jobs", "run-now", "--json", f"@{f}", "--timeout", "60m", "-o", "json", tries=1
    )
    run = json.loads(out)
    state = run.get("state", {}).get("result_state")
    log[key] = state
    LOG.write_text(json.dumps(log, ensure_ascii=False, indent=1), encoding="utf-8")
    print(key, state, run.get("run_page_url", ""))
    if state != "SUCCESS":
        raise SystemExit(f"{key} 승인이 {state}로 끝났다. 실행 화면을 본다")


note = "작업 008 release-2026-10-10 승인 목록. 공식 원문 대조와 손계산 검사 통과. 2026-10-10 사용자 승인"
if sys.argv[1] == "shared":
    upload(REL / "incoming/shared/catalog", f"release-{TAG}-shared")
    approve(
        "shared",
        {
            "incoming": f"release-{TAG}-shared",
            "label": "release-shared",
            "subject": "feat: 카드 확대용 공통 가맹점과 학교 업종 연결 더하기",
            "reviewer": "jihan",
            "note": note,
            "expect_files": manifest["base_files_digest"],
        },
    )
elif sys.argv[1] == "hyundai":
    # 공통 승인이 issuers/hyundai.yaml을 바꿔 현대카드 초안은 초안 승인이 막힌다. 카드 파일을 손 승인으로 넣고 초안은 반려로 닫는다
    from cherry_core.pipeline.seed import digest

    gold = {
        p.relative_to(ROOT / "catalog").as_posix(): p.read_text(encoding="utf-8")
        for p in (ROOT / "catalog").rglob("*.yaml")
    }
    for p in (REL / "incoming/shared/catalog").rglob("*.yaml"):
        gold[p.relative_to(REL / "incoming/shared/catalog").as_posix()] = p.read_text(encoding="utf-8")
    for c in manifest["cards"]:
        if log.get(c["card_id"]) == "SUCCESS" or log.get(c["card_id"] + "-manual") == "SUCCESS":
            gold[c["path"]] = (REL / "incoming" / c["card_id"] / "catalog" / c["path"]).read_text(encoding="utf-8")
    for c in manifest["cards"]:
        if not c["path"].startswith("cards/hyundai/"):
            continue
        key = c["card_id"] + "-manual"
        text = (REL / "incoming" / c["card_id"] / "catalog" / c["path"]).read_text(encoding="utf-8")
        if log.get(key) != "SUCCESS":
            name = c["incoming"] + "-manual"
            upload(REL / "incoming" / c["card_id"] / "catalog", name)
            approve(
                key,
                {
                    "incoming": name,
                    "label": "new-" + c["card_id"],
                    "subject": f"feat: {c['name']} 새 카드 추가",
                    "reviewer": "jihan",
                    "note": note + ". 공통 승인이 현대카드 공통 파일을 바꿔 초안 승인 대신 손 승인",
                    "expect_files": digest(list(gold.items())),
                },
            )
        gold[c["path"]] = text
        approve(
            c["card_id"] + "-close",
            {"draft_id": c["draft_id"], "decision": "reject", "reviewer": "jihan", "note": "같은 카드 파일을 손 승인으로 넣어 초안을 닫는다"},
        )
else:
    for c in manifest["cards"]:
        if log.get(c["card_id"]) == "SUCCESS":
            continue
        # 공통 승인이 issuers/hyundai.yaml을 바꿔 그 전에 만든 현대카드 초안은 승인 작업이 막는다. 손 승인으로 따로 넣는다
        if c["path"].startswith("cards/hyundai/"):
            print("현대카드는 손 승인으로 미룸", c["card_id"])
            continue
        upload(REL / "incoming" / c["card_id"] / "catalog", c["incoming"])
        approve(
            c["card_id"],
            {
                "incoming": c["incoming"],
                "draft_id": c["draft_id"],
                "reviewer": "jihan",
                "note": note,
            },
        )
print("끝", sum(v == "SUCCESS" for v in log.values()), "건 성공")
