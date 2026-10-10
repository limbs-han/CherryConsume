"""검증한 출시 후보를 운영 승인용으로 저장한다. 운영 데이터에는 쓰지 않는다."""

import hashlib
import json
import shutil
from collections import Counter
from pathlib import Path

import yaml
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.approve import apply_changes, new_card_conflicts
from cherry_core.pipeline.seed import digest

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
CAT = BASE / "combined/catalog"
import sys

# 두 번째 승인 묶음부터는 폴더 이름과 올리기 이름 꼬리를 받는다. 예: package.py release-2026-10-10b 20261010b
OUT = ROOT / "docs/work/008-catalog-all-cards" / (sys.argv[1] if len(sys.argv) > 1 else "release-2026-10-10")
TAG = sys.argv[2] if len(sys.argv) > 2 else "20261010"
EXPANDS = sorted(p.name for p in BASE.glob("expand[0-9]*") if p.is_dir())


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, default=str) + "\n",
        encoding="utf-8",
    )


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main():
    candidates = read(BASE / "combined/candidates.json")
    ids = {r["card_id"] for r in candidates}
    gold = {
        p.relative_to(ROOT / "catalog").as_posix(): p.read_text(encoding="utf-8")
        for p in (ROOT / "catalog").rglob("*.yaml")
    }
    files = {
        p.relative_to(CAT).as_posix(): p.read_text(encoding="utf-8")
        for p in CAT.rglob("*.yaml")
    }
    incoming = {p: t for p, t in files.items() if gold.get(p) != t}
    _, changed = apply_changes(gold, incoming)
    new_paths = {c["path"] for c in candidates}
    shared = {p: t for p, t in changed.items() if p not in new_paths}
    # 공통 항목과 기존 카드 분류 연결만 먼저 승인해도 완전한 카탈로그여야 한다.
    staged, shared_changed = apply_changes(gold, shared)
    packets = {}
    for folder in [
        ROOT / "tmp/card-ready-review" / g for g in ("mixed", "nh", "others")
    ] + [BASE / g for g in ("recommended-mixed", "recommended-others", *EXPANDS)]:
        packets.update({r["draft"]["card_id"]: r for r in read(folder / "packet.json")})
    cards = []
    for candidate in candidates:
        cid, rel = candidate["card_id"], candidate["path"]
        # 이미 운영에 들어가 저장소 catalog/에 있는 카드는 이번 묶음에서 뺀다
        if (ROOT / "catalog" / rel).exists():
            continue
        text = files[rel]
        if conflicts := new_card_conflicts(
            text, staged, packets[cid]["draft"]["issuer"], rel
        ):
            raise ValueError(f"{cid}: {conflicts}")
        staged[rel] = text
        data = yaml.safe_load(text)
        target = OUT / "incoming" / cid / "catalog" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")
        cards.append(
            {
                "card_id": cid,
                "name": data["name"],
                "path": rel,
                "draft_id": packets[cid]["draft"]["draft_id"],
                "sha256": sha(text),
                "sources": data["sources"],
                "annual_fees": data["annual_fees"],
                "open_questions": data.get("open_questions", []),
                "group": candidate["group"],
                "incoming": f"release-{TAG}-{cid}",
            }
        )
    for rel, text in shared_changed.items():
        target = OUT / "incoming/shared/catalog" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")
    shutil.copytree(BASE / "combined/cases", OUT / "cases", dirs_exist_ok=True)
    shutil.copytree(
        BASE / "combined/school-cases", OUT / "school-cases", dirs_exist_ok=True
    )
    shutil.copytree(BASE / "verification", OUT / "verification", dirs_exist_ok=True)
    previous = ROOT / "docs/work/008-catalog-all-cards/ready-2026-10-09"
    shutil.copytree(
        previous / "verification", OUT / "verification/previous", dirs_exist_ok=True
    )
    for group in ("hana8", "recommended-mixed", "recommended-others", *EXPANDS):
        dest = OUT / "research" / group
        dest.mkdir(parents=True, exist_ok=True)
        for filename in (
            "result.json",
            "report.md",
            "needed_common.json",
            "kb-handoff.md",
        ):
            source = BASE / group / filename
            if source.exists():
                shutil.copy2(source, dest / filename)
    results = {
        r["card_id"]: {**r, "status": "source_review_pending"}
        for r in read(BASE / "triage-results.json")
    }
    results.update({r["card_id"]: r for r in read(previous / "all-results.json")})
    research = read(BASE / "combined/research-results.json")
    # 승인 전에 id를 상품 코드로 바꾼 카드는 초안의 옛 id 줄을 새 id로 옮긴다. expand1의 토스 LIKIT ALL
    for r in research:
        if r.get("draft_card_id"):
            results[r["card_id"]] = {
                **results.pop(r["draft_card_id"]),
                "draft_card_id": r["draft_card_id"],
            }
    results.update({r["card_id"]: r for r in research})
    for cid in ids:
        results[cid].update(status="ready", approved=False, final_engine_checked=True)
    assert len(results) == 2421
    write(OUT / "all-results.json", list(results.values()))
    write(OUT / "inventory-summary.json", read(BASE / "triage-counts.json"))
    cases = sum(
        len(yaml.safe_load(p.read_text(encoding="utf-8"))["cases"])
        for p in (OUT / "cases").glob("*.yaml")
    )
    checks = {
        name: read(BASE / "combined" / f"{name}.json")
        for name in ("new-tests", "existing-tests", "school-tests")
    }
    assert (
        checks["new-tests"]["cards"] == len(candidates)
        and checks["new-tests"]["cases"] == cases
    )
    assert all(not r["failures"] for r in checks.values())
    problems = check_catalog(load_catalog(CAT))
    assert not [p for p in problems if p.level == "error"]
    checks.update(
        new_cards=len(cards),
        total_catalog_cards=len(cards)
        + len(list((ROOT / "catalog/cards").glob("*/*.yaml"))),
        catalog_errors=0,
        catalog_warnings=sum(p.level == "warning" for p in problems),
        local_approval_errors=0,
        changed_files=len(changed),
        shared_files=len(shared),
        duplicate_products=0,
        all_status_counts=dict(Counter(r["status"] for r in results.values())),
        operational_writes=0,
    )
    write(OUT / "checks.json", checks)
    write(
        OUT / "approval-manifest.json",
        {
            "approved": False,
            "approval_required": True,
            "job_id": 665396523935248,
            "base_files_digest": digest(list(gold.items())),
            "cards": cards,
            "shared_files": [{"path": p, "sha256": sha(t)} for p, t in shared.items()],
            "operation_order": [
                "운영 현재 값과 끊긴 승인 확인",
                "공통 항목과 기존 카드 분류 연결 승인 후 봇 내보내기 확인",
                "새 카드별 초안 번호로 승인하고 검수 대기 닫기",
                "앱 배포용 카탈로그 내보내기 확인",
            ],
        },
    )
    lines = [
        f"# 출시용 카드 승인 목록\n\n새 카드 {len(cards)}장을 준비했다. 운영 반영 뒤 기존 카드와 합쳐 {checks['total_catalog_cards']}장이다. 운영 반영은 아직 하지 않았다.",
        f"새 카드 손계산 {cases}개, 기존 손계산 {checks['existing-tests']['cases']}개, 교육비 분류 연결 {checks['school-tests']['cases']}개가 앱 계산과 일치했다. 카탈로그 오류 {checks['catalog_errors']}개와 경고 {checks['catalog_warnings']}개. 실제 승인 함수 검사와 상품 중복 검사를 통과했다.",
        "## 이번 목록에서 확인할 내용\n\n- JADE Classic는 거래별 하나머니 적립을 계산한다. 바우처와 라운지는 자동 계산하지 않는다.\n- 현대 X는 전월실적에 따른 거래별 1% 할인을 계산한다. 연간 500만원당 2만원 캐시백과 라운지·발레파킹은 자동 계산하지 않는다.\n- 미미의 09:00 정각 포함 여부는 공식 문구가 명확하지 않아 09:00 미만으로 계산한다.\n- zgm 구독의 일부 페이 제외 이름은 공식 문구에 없어 확인 안내로 남겼다.\n- 매출표 접수 순서, 입점 매장, 과거 최초 결제 이력처럼 현재 결제 입력으로 알 수 없는 조건은 카드 상세 안내로 남겼다.\n- 2026-10-10 expand1로 8장을 더했다. 올리 POINT는 해외 결제가 커피·편의점 등 ①~⑤ 영역 순위에 함께 쌓이지 않게 국내 결제만 세었다. 해피포인트 하나 체크의 취소분 차감 방식은 자동 계산하지 않는다.\n- 새 공통 가맹점 뚜레쥬르, LFmall, 농협몰, 미니스톱을 더했다. 미니스톱은 기존 카드의 편의점 혜택에, 뚜레쥬르는 제과 혜택에 새로 걸린다. 두 업종 모두 원문 범위 안이다.",
        "## 카드 목록\n\n| 카드 | 연회비 | 계산 범위 |\n|---|---:|---|",
    ]
    table_rows = []
    for row in cards:
        raw = yaml.safe_load(files[row["path"]])
        fees = sorted({f["amount"] for f in raw["annual_fees"]})
        fee = (
            "없음" if fees == [0] else "/".join(f"{amount:,}" for amount in fees) + "원"
        )
        benefits = raw["revisions"][-1].get("benefits", [])
        scope = " · ".join(b["title"] for b in benefits[:3]) + (
            f" 외 {len(benefits) - 3}개" if len(benefits) > 3 else ""
        )
        table_rows.append(
            f"| [{row['name']}]({raw['sources'][0]['url']}) | {fee} | {scope} |"
        )
    lines[-1] += "\n" + "\n".join(table_rows)
    lines += [
        "\n## 승인 뒤 처리\n\n승인하면 파일 업로드, 공통 항목과 기존 카드 분류 연결 승인, 새 카드별 승인과 검수 대기 닫기, 봇 내보내기와 앱 카탈로그 확인을 AI가 처리한다. 새 초중고와 유치원 업종이 기존 카드에서 적립 대상으로 바뀌지 않도록 기존 카드 12개와 현대 공통 규칙 1개의 제외 목록을 연결했다. 기존 제외 범위와 혜택을 삭제하지 않았다.",
        "전체 일반 초안 2,162장 중 구조 검사 오류 없이 계산 혜택이 있는 것은 1,034장이다. 이는 원문 대조 완료 수가 아니다. 추가 원문 조사와 계산 기능 보완을 이어 할 대상은 [전체 결과](all-results.json)에 기록했다. KB 노리2·ALL·NEED Edu의 후불교통 실적 제외와 달달의 교통 월합산 조건 등은 실제 거래 금액을 바꾸므로 이번 승인에서 뺐다.",
        "올릴 파일과 지문은 [승인 파일 묶음](approval-manifest.json), 시험 결과는 [검증 기록](checks.json)에 있다. 운영 승인 전 현재 골드 값과 초안 번호를 다시 확인한다.",
    ]
    (OUT / "approval.md").write_text("\n\n".join(lines) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "new_cards": len(cards),
                "total_cards": checks["total_catalog_cards"],
                "cases": cases,
                "changed_files": len(changed),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
