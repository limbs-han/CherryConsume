"""커밋 메시지 검사. 규칙 원문은 .claude/skills/commit/SKILL.md"""

import re
import sys

sys.stderr.reconfigure(encoding="utf-8")
TYPES = "feat|fix|build|chore|deploy|docs|style|refactor|test|release"
VAGUE = {
    "수정",
    "변경",
    "버그 수정",
    "코드 수정",
    "코드 변경",
    "기능 개발",
    "기능 추가",
}

with open(sys.argv[1], encoding="utf-8") as f:
    text = f.read()
lines = [l for l in text.splitlines() if not l.startswith("#")]
subject = next((l for l in lines if l.strip()), "")
if subject.startswith(("Merge ", "Revert ")):
    sys.exit(0)

errors = []
m = re.fullmatch(rf"({TYPES}): (\S.*)", subject)
if not m:
    errors.append(
        f"제목은 '<type>: 작업 내용' 형식이어야 한다. type은 {TYPES.replace('|', ', ')}"
    )
else:
    desc = m.group(2).strip()
    if desc.endswith((".", "。")):
        errors.append("제목 끝에 마침표를 쓰지 않는다")
    if desc in VAGUE:
        errors.append(
            f"'{desc}'만으로는 무엇을 바꿨는지 알 수 없다. 대상과 목적을 적는다"
        )
# git이 편집기에 붙이는 # 안내 줄은 메시지가 아니다. 바뀐 파일의 .claude/ 경로에 걸리지 않게 뺀 글만 본다. 작업 013 13-22
body = "\n".join(lines)
if re.search(r"claude|anthropic", body, re.IGNORECASE):
    errors.append("커밋 메시지에 claude나 anthropic을 넣지 않는다")
if re.search(r"^co-authored-by:", body, re.IGNORECASE | re.MULTILINE):
    errors.append("Co-authored-by를 붙이지 않는다")

if errors:
    print("커밋 메시지 규칙 위반\n- " + "\n- ".join(errors), file=sys.stderr)
    sys.exit(1)
if len(subject) > 50:
    print(
        f"알림: 제목이 {len(subject)}자다. 가능하면 50자 이내로 줄인다", file=sys.stderr
    )
