"""카탈로그 명령. check는 검증, format은 고정 저장 형식으로 다시 쓰기."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .canonical import catalog_files, format_file
from .check import check_catalog
from .load import load_catalog

DEFAULT_ROOT = Path(__file__).resolve().parents[3] / "catalog"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.catalog")
    ap.add_argument("command", choices=["check", "format"])
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
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
