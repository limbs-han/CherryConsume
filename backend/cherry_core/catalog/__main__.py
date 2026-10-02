"""카탈로그 명령. check는 검증, format은 고정 저장 형식으로 다시 쓰기, json은 앱이 담는 파일 만들기."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .app_json import app_catalog_text, rule_errors
from .canonical import catalog_files, format_file
from .check import check_catalog
from .load import load_catalog

DEFAULT_ROOT = Path(__file__).resolve().parents[3] / "catalog"
# 앱이 담고 켤 때 이 경로로 새 판을 받는다. 작업 006 설계 2절
DEFAULT_JSON = Path(__file__).resolve().parents[3] / "app" / "assets" / "catalog.json"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.catalog")
    ap.add_argument("command", choices=["check", "format", "json"])
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--out", type=Path, default=DEFAULT_JSON)
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    if args.command == "format":
        changed = [p for p in catalog_files(args.root) if format_file(p)]
        print(f"형식을 고친 파일 {len(changed)}개")
        for p in changed:
            print(f"  {p.relative_to(args.root).as_posix()}")
        return 0

    cat = load_catalog(args.root)
    if args.command == "json":
        # 엔진이 계산을 거절하던 카탈로그로는 만들지 않는다. 앱은 규칙 검사를 다시 하지 않는다
        errors = rule_errors(cat)
        if errors:
            print(f"오류 {len(errors)}. JSON을 만들지 않았다")
            for e in errors:
                print(f"  {e}")
            return 1
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(app_catalog_text(cat), encoding="utf-8", newline="\n")
        print(f"카드 {len(cat.cards)}장을 {args.out}에 썼다")
        return 0

    problems = check_catalog(cat)
    errors = [p for p in problems if p.level == "error"]
    warnings = [p for p in problems if p.level == "warning"]
    print(f"카드 {len(cat.cards)}장")
    for card in cat.cards.values():
        if not card.revisions:
            continue
        rules = card.revisions[-1][1]
        unmodeled = len(rules.unmodeled) + len(rules.benefit_exclusions.unmodeled)
        unmodeled += sum(len(b.unmodeled) for b in rules.benefits)
        print(
            f"  {card.card.id}: 개정 {len(card.revisions)}, 혜택 {len(rules.benefits)}, "
            f"문장으로 남긴 조건 {unmodeled}, 확인 필요 {len(card.card.open_questions)}"
        )
    print(f"오류 {len(errors)}")
    for p in errors:
        print(f"  {p}")
    print(f"경고 {len(warnings)}")
    for p in warnings:
        print(f"  {p}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
