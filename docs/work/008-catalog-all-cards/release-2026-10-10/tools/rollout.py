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
REL = ROOT / "docs/work/008-catalog-all-cards/release-2026-10-10"
LOG = BASE / "rollout-log.json"
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
    upload(REL / "incoming/shared/catalog", "release-20261010-shared")
    approve(
        "shared",
        {
            "incoming": "release-20261010-shared",
            "label": "release-shared",
            "subject": "feat: 카드 확대용 공통 가맹점과 학교 업종 연결 더하기",
            "reviewer": "jihan",
            "note": note,
            "expect_files": manifest["base_files_digest"],
        },
    )
else:
    for c in manifest["cards"]:
        if log.get(c["card_id"]) == "SUCCESS":
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
