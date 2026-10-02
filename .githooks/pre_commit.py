"""커밋 전 검사: git 사용자 정보, 민감 파일, 추가된 줄의 비밀값 패턴."""
import re, subprocess, sys

sys.stderr.reconfigure(encoding="utf-8")


def git(*args):
    r = subprocess.run(["git", "-c", "core.quotepath=false", *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.stdout


errors = []
name, email = git("config", "--get", "user.name").strip(), git("config", "--get", "user.email").strip()
if not name or not email:
    errors.append("git user.name 또는 user.email이 비어 있다. 값은 사용자가 직접 정한다")
elif re.search(r"claude|anthropic", name + email, re.I):
    errors.append(f"git 작성자 정보가 의심스럽다: {name} <{email}>")

SECRET_FILE = re.compile(r"(^|/)(\.env(\.[^/]*)?|id_rsa[^/]*|key\.properties)$|\.(pem|key|p12|pfx|jks|keystore)$")
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
    ("비밀값 대입", r"(?i)(api[_-]?key|secret|token|password|passwd)\s*[:=]\s*['\"][^'\"\s]{8,}['\"]"),
]
current = None
for line in git("diff", "--cached", "-U0", "--no-color").splitlines():
    if line.startswith("+++ "):
        current = line[6:] if line.startswith("+++ b/") else None
    elif line.startswith("+") and current:
        for label, pat in SECRET_LINE:
            if re.search(pat, line):
                errors.append(f"{current}: {label}로 보이는 값이 있다")

# 폰이 받는 app/assets/catalog.json이 stage한 catalog/로 다시 만든 것과 같은지 본다. catalog_json.py
staged = git("diff", "--cached", "--name-only").splitlines()
if any(f == "app/assets/catalog.json" or f.startswith("catalog/") for f in staged):
    from catalog_json import errors as catalog_json_errors
    errors += catalog_json_errors(git("rev-parse", "--show-toplevel").strip())

if errors:
    print("커밋을 막았다\n- " + "\n- ".join(dict.fromkeys(errors)), file=sys.stderr)
    sys.exit(1)
