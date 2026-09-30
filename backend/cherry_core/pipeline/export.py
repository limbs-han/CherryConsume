"""검수에서 승인된 카탈로그 파일을 저장소로 옮긴다. GitHub Actions가 돌린다. 설계 4절 7번.

내보내기 폴더 하나가 승인 하나다. 안에 catalog/ 아래 바뀐 파일과 commit.json이 있다.
commit.json은 {"subject": "feat: ...", "review_id": "..."}다.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# 카탈로그 개정 커밋은 feat나 fix 한 줄이다. "Revert "로 시작하면 커밋 훅이 검사를 건너뛰어 막는다
SUBJECT = re.compile(r"(feat|fix): [^\r\n]+")
REVIEW_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


def apply_export(export_dir: Path, repo: Path) -> tuple[list[str], str]:
    """내보낸 파일을 repo/catalog에 복사하고 (바뀐 경로, 커밋 메시지)를 돌려준다.

    폴더 이름은 검수 기록 번호와 같아야 하고, 안에는 catalog/와 commit.json만 있어야 한다.
    YAML이 하나도 없으면 승인한 개정이 저장소에 오르지 않은 채 끝나므로 실패한다.
    """
    meta = json.loads((export_dir / "commit.json").read_text(encoding="utf-8"))
    subject, review_id = meta.get("subject"), meta.get("review_id")
    if not isinstance(subject, str) or not SUBJECT.fullmatch(subject):
        raise ValueError("commit.json의 subject는 'feat: ' 또는 'fix: '로 시작하는 한 줄이어야 한다")
    if not isinstance(review_id, str) or not REVIEW_ID.fullmatch(review_id) or review_id != export_dir.name:
        raise ValueError("commit.json의 review_id가 폴더 이름과 같아야 한다")
    extra = sorted(p.name for p in export_dir.iterdir() if p.name not in ("catalog", "commit.json"))
    if extra:
        raise ValueError(f"내보내기 폴더에 모르는 것이 있다: {', '.join(extra)}")
    src_root = (export_dir / "catalog").resolve()
    dst_root = (repo / "catalog").resolve()
    files = sorted(p for p in src_root.rglob("*") if p.is_file()) if src_root.is_dir() else []
    if not files:
        raise ValueError("catalog/ 아래 YAML이 없다")
    changed = []
    for src in files:
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
