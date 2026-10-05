"""커밋 전 검사: git 사용자 정보, 민감 파일, 추가된 줄의 비밀값 패턴."""

import re
import subprocess
import sys

sys.stderr.reconfigure(encoding="utf-8")


def git(*args):
    r = subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return r.stdout


errors = []
name, email = (
    git("config", "--get", "user.name").strip(),
    git("config", "--get", "user.email").strip(),
)
if not name or not email:
    errors.append(
        "git user.name 또는 user.email이 비어 있다. 값은 사용자가 직접 정한다"
    )
elif re.search(r"claude|anthropic", name + email, re.IGNORECASE):
    errors.append(f"git 작성자 정보가 의심스럽다: {name} <{email}>")

SECRET_FILE = re.compile(
    r"(^|/)(\.env(\.[^/]*)?|id_rsa[^/]*|key\.properties)$|\.(pem|key|p12|pfx|jks|keystore)$"
)
for f in git("diff", "--cached", "--name-only", "--diff-filter=AM").splitlines():
    if SECRET_FILE.search(f) and not f.endswith((".example", ".sample")):
        errors.append(f"민감 파일로 보인다: {f}")

SECRET_LINE = [
    ("개인 키", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("AWS 키", r"AKIA[0-9A-Z]{16}"),
    ("Google API 키", r"AIza[0-9A-Za-z_\-]{35}"),
    ("GitHub 토큰", r"gh[pousr]_[A-Za-z0-9]{36,}"),
    ("Slack 토큰", r"xox[abprs]-[A-Za-z0-9-]{10,}"),
    ("API 키", r"\bsk-[A-Za-z0-9_\-]{20,}"),
    (
        "비밀값 대입",
        r"(?i)(api[_-]?key|secret|token|password|passwd)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]",
    ),
]
current = None
for line in git("diff", "--cached", "-U0", "--no-color").splitlines():
    if line.startswith("+++ "):
        current = line[6:] if line.startswith("+++ b/") else None
    elif line.startswith("+") and current:
        for label, pat in SECRET_LINE:
            if re.search(pat, line):
                errors.append(f"{current}: {label}로 보이는 값이 있다")

# 새로 올리는 작업 기록의 번호가 다른 기록 파일과 같으면 막는다. 세션 둘이 같은 번호를 쓴 일이 두 번 있었다. 옛
# 겹침은 다른 문서가 가리켜 두었다. 작업 013 13-50
history = git("ls-files", "docs/history").splitlines()
for f in git("diff", "--cached", "--name-only", "--diff-filter=A").splitlines():
    m = re.match(r"docs/history/(\d+)-", f)
    if m and any(
        h != f and h.startswith(f"docs/history/{m.group(1)}-") for h in history
    ):
        errors.append(
            f"{f}: 작업 기록 {m.group(1)}번이 이미 있다. 목록의 마지막 번호 다음을 쓴다"
        )

# 폰이 받는 app/assets/catalog.json이 stage한 catalog/로 다시 만든 것과 같은지 본다. catalog_json.py
staged = git("diff", "--cached", "--name-only").splitlines()
if any(f == "app/assets/catalog.json" or f.startswith("catalog/") for f in staged):
    from catalog_json import errors as catalog_json_errors

    errors += catalog_json_errors(git("rev-parse", "--show-toplevel").strip())

if errors:
    print("커밋을 막았다\n- " + "\n- ".join(dict.fromkeys(errors)), file=sys.stderr)
    sys.exit(1)
