"""검수에서 승인된 카탈로그 파일을 저장소로 옮긴다. GitHub Actions가 돌린다. 설계 4절 7번.

내보내기 폴더 하나가 승인 하나다. 안에 catalog/ 아래 바뀐 파일과 commit.json이 있다.
commit.json은 {"subject": "feat: ...", "review_id": "..."}다.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def apply_export(export_dir: Path, repo: Path) -> tuple[list[str], str]:
    """내보낸 파일을 repo/catalog에 복사하고 (바뀐 경로, 커밋 메시지)를 돌려준다."""
    meta = json.loads((export_dir / "commit.json").read_text(encoding="utf-8"))
    src_root = (export_dir / "catalog").resolve()
    dst_root = (repo / "catalog").resolve()
    changed = []
    for src in sorted(p for p in src_root.rglob("*") if p.is_file()):
        rel = src.relative_to(src_root)
        dst = (dst_root / rel).resolve()
        if src.suffix != ".yaml" or not dst.is_relative_to(dst_root):
            raise ValueError(f"카탈로그 YAML이 아니다: {rel.as_posix()}")
        text = src.read_text(encoding="utf-8")
        if dst.exists() and dst.read_text(encoding="utf-8") == text:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(text, encoding="utf-8", newline="\n")
        changed.append(f"catalog/{rel.as_posix()}")
    return changed, f"{meta['subject']}\n\n검수 기록 {meta['review_id']}\n작업 003\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.pipeline.export")
    ap.add_argument("export_dir", type=Path)
    ap.add_argument("--repo", type=Path, default=Path.cwd())
    ap.add_argument("--message-file", type=Path, required=True)
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    changed, message = apply_export(args.export_dir, args.repo)
    args.message_file.write_text(message, encoding="utf-8")
    print(f"바뀐 파일 {len(changed)}개")
    for path in changed:
        print(f"  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
