"""검수에서 승인된 카탈로그 파일을 저장소로 옮긴다. GitHub Actions가 돌린다. 설계 4절 7번.

내보내기 폴더 하나가 승인 하나다. 안에 catalog/ 아래 바뀐 파일과 commit.json이 있다.
commit.json은 {"subject": "feat: ...", "review_id": "...", "base": "...", "result": "..."}다.
base와 result는 승인 전과 후의 골드 카탈로그 해시다. 저장소 카탈로그가 base와 같을 때만 옮기고, 옮긴 뒤 result와 같아야 한다.
앞선 승인이 빠졌거나 저장소를 직접 고쳤으면 옛 판으로 새 판을 덮지 않고 그 폴더를 거부한다.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from cherry_core.pipeline.seed import digest, file_rows

# 카탈로그 개정 커밋은 feat나 fix 한 줄이다. "Revert "로 시작하면 커밋 훅이 검사를 건너뛰어 막는다
SUBJECT = re.compile(r"(feat|fix): \S[^\r\n]*")
REVIEW_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
# .githooks/commit_msg.py와 같다. 훅에 막히면 골드만 바뀌고 저장소는 따라오지 못해 승인할 때 미리 막는다
VAGUE = {"수정", "변경", "버그 수정", "코드 수정", "코드 변경", "기능 개발", "기능 추가"}
# .githooks/pre_commit.py의 SECRET_LINE과 같다. 카탈로그 글에 이런 줄이 있으면 export 커밋이 막힌다
SECRET_LINE = [
    ("개인 키", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("AWS 키", r"AKIA[0-9A-Z]{16}"),
    ("Google API 키", r"AIza[0-9A-Za-z_\-]{35}"),
    ("GitHub 토큰", r"gh[pousr]_[A-Za-z0-9]{36,}"),
    ("Slack 토큰", r"xox[abprs]-[A-Za-z0-9-]{10,}"),
    ("API 키", r"\bsk-[A-Za-z0-9_\-]{20,}"),
    ("비밀값 대입", r"(?i)(api[_-]?key|secret|token|password|passwd)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]"),
]


def secret_lines(text: str) -> list[str]:
    """커밋 훅이 비밀값으로 볼 줄의 종류."""
    return [label for label, pattern in SECRET_LINE if re.search(pattern, text)]


def commit_message(subject: object, review_id: str) -> str:
    """export가 쓸 커밋 메시지. 커밋 훅이 막을 제목이면 ValueError."""
    if not isinstance(subject, str) or not SUBJECT.fullmatch(subject):
        raise ValueError("commit.json의 subject는 'feat: ' 또는 'fix: '로 시작하는 한 줄이어야 한다")
    desc = subject.split(": ", 1)[1].strip()
    if desc.endswith((".", "。")):
        raise ValueError("commit.json의 subject 끝에 마침표를 쓰지 않는다")
    if desc in VAGUE:
        raise ValueError("commit.json의 subject가 무엇을 바꿨는지 알 수 없다")
    message = f"{subject}\n\n검수 기록 {review_id}\n작업 003\n"
    if re.search(r"claude|anthropic", message, re.IGNORECASE):
        raise ValueError("commit.json의 subject와 review_id에 claude나 anthropic을 넣지 않는다")
    return message


def apply_export(export_dir: Path, repo: Path) -> tuple[list[str], str]:
    """내보낸 파일을 repo/catalog에 복사하고 (바뀐 경로, 커밋 메시지)를 돌려준다.

    폴더 이름은 검수 기록 번호와 같아야 하고, 안에는 catalog/와 commit.json만 있어야 한다.
    YAML이 하나도 없으면 승인한 개정이 저장소에 오르지 않은 채 끝나므로 실패한다.
    """
    meta = json.loads((export_dir / "commit.json").read_text(encoding="utf-8"))
    review_id = meta.get("review_id")
    if not isinstance(review_id, str) or not REVIEW_ID.fullmatch(review_id) or review_id != export_dir.name:
        raise ValueError("commit.json의 review_id가 폴더 이름과 같아야 한다")
    message = commit_message(meta.get("subject"), review_id)
    extra = sorted(p.name for p in export_dir.iterdir() if p.name not in ("catalog", "commit.json"))
    if extra:
        raise ValueError(f"내보내기 폴더에 모르는 것이 있다: {', '.join(extra)}")
    src_root = (export_dir / "catalog").resolve()
    dst_root = (repo / "catalog").resolve()
    files = sorted(p for p in src_root.rglob("*") if p.is_file()) if src_root.is_dir() else []
    if not files:
        raise ValueError("catalog/ 아래 YAML이 없다")
    for src in files:
        rel = src.relative_to(src_root)
        if src.suffix != ".yaml" or not (dst_root / rel).resolve().is_relative_to(dst_root):
            raise ValueError(f"카탈로그 YAML이 아니다: {rel.as_posix()}")
    now = digest(file_rows(dst_root))
    if now == meta.get("result"):
        # 이미 저장소에 들어간 승인이다. 올린 뒤 done/으로 옮기다 끊긴 폴더가 남은 경우라 바뀐 것 없이 끝내 옮기게 한다
        return [], message
    if now != meta.get("base"):
        raise ValueError("저장소 카탈로그가 승인할 때의 골드와 다르다. 앞선 승인이 빠졌거나 저장소를 직접 고쳤다")
    changed = []
    for src in files:
        rel = src.relative_to(src_root)
        dst = dst_root / rel
        text = src.read_text(encoding="utf-8")
        if dst.exists() and dst.read_text(encoding="utf-8") == text:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(text, encoding="utf-8", newline="\n")
        changed.append(f"catalog/{rel.as_posix()}")
    if digest(file_rows(dst_root)) != meta.get("result"):
        raise ValueError("옮긴 뒤 저장소 카탈로그가 승인한 골드와 다르다")
    return changed, message


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
