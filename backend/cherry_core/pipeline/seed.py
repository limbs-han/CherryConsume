"""골드 첫 적재에 넣을 행. 작업 003 과제 17, 설계 4절 1번.

Databricks의 seed_gold.py가 이 행을 표에 쓰고, 다시 읽은 표의 해시를 찍는다.
PC에서 `python -m cherry_core.pipeline.seed catalog`로 같은 해시를 찍어 두 값이 같으면 골드와 저장소가 같다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import date
from pathlib import Path

from cherry_core.catalog.canonical import catalog_files
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import Catalog, load_catalog
from cherry_core.pipeline.draft import clean_rules

INITIAL = "initial"  # 첫 적재 행의 검수 기록 번호
# 채점에만 쓰는 정답 예시. 카드사가 겹치지 않게 골랐다. 나머지 15장은 프롬프트 다듬기에 쓴다
TEST_CARDS = frozenset(
    {"hana-travelog-check", "hyundai-the-green-ed4", "kb-my-wesh", "samsung-taptap-o", "shinhan-cheoeum"}
)


def load_checked(root: Path) -> Catalog:
    """검사 오류가 하나라도 있으면 골드에 올리지 않는다. 골드는 이 뒤로 카탈로그의 원본이다."""
    cat = load_catalog(root)
    errors = [p for p in check_catalog(cat) if p.level == "error"]
    if errors:
        raise ValueError(f"카탈로그 검사 오류 {len(errors)}개. 첫 번째: {errors[0].file} {errors[0].message}")
    return cat


def rules_json(rules: dict) -> str:
    """규칙을 JSON 글로. 읽을 때는 draft.int_keys로 구간 키를 정수로 되돌려 Rules로 비교한다.

    글끼리 비교하지 않는다. 정수 키는 숫자 순서로, 다시 읽은 글자 키는 글자 순서로 정렬돼 같은 규칙도 글이 달라진다.
    """
    return json.dumps(clean_rules(rules), ensure_ascii=False, sort_keys=True, default=str)


def file_rows(root: Path) -> list[tuple[str, str]]:
    """(경로, YAML 글) 파일마다 한 행. 저장 형식 그대로라 내보낼 때 바이트까지 같다."""
    return [(p.relative_to(root).as_posix(), p.read_text(encoding="utf-8")) for p in catalog_files(root)]


def revision_rows(cat: Catalog) -> list[tuple[str, str, date, bool, str, str]]:
    """(카드, 카드사, 시행일, 시행일 추정 여부, 원문 id, 규칙 JSON) 카드 개정마다 한 행. 규칙은 카드사 기본값까지 합친 것이다."""
    return [
        (cid, lc.card.issuer, rev.effective_from, rev.effective_from_estimated, rev.source, rules_json(rev.data))
        for cid, lc in sorted(cat.cards.items())
        for rev, _ in lc.revisions
    ]


def golden_rows(
    cat: Catalog, first: dict[tuple[str, str], str]
) -> list[tuple[str, str, str, date, str, dict[str, str]]]:
    """(카드, 카드사, test나 tune, 정답 개정 시행일, 그 개정 규칙 JSON, 원문 id별 첫 수집 경로) 카드마다 한 행.

    정답은 마지막 개정이다. IBK처럼 앞날 개정이 마지막이면 첫 수집 원문과 시기가 다를 수 있어 시행일을 함께 둔다.
    first는 (카드, 원문 id)마다 처음 받은 원문의 raw 볼륨 안 경로다. 자동 수집하지 않는 카드는 사람이 원문을 더할 때까지 비어 있다.
    """
    return [
        (
            cid,
            lc.card.issuer,
            "test" if cid in TEST_CARDS else "tune",
            lc.revisions[-1][0].effective_from,
            rules_json(lc.revisions[-1][0].data),
            {s: p for (c, s), p in sorted(first.items()) if c == cid},
        )
        for cid, lc in sorted(cat.cards.items())
    ]


def digest(rows) -> str:
    """행 순서와 상관없는 해시. Spark에서 다시 읽은 행과 PC에서 만든 행을 비교한다."""
    lines = sorted(
        json.dumps([v.isoformat() if isinstance(v, date) else v for v in r], ensure_ascii=False) for r in rows
    )
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.pipeline.seed")
    ap.add_argument("root", type=Path, help="카탈로그 폴더")
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    cat = load_checked(args.root)
    files, revisions = file_rows(args.root), revision_rows(cat)
    print(f"카탈로그 파일 {len(files)}개 해시 {digest(files)}")
    print(f"카드 개정 {len(revisions)}개 해시 {digest(revisions)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
