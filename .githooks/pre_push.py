"""푸시 전 검사: 올리는 커밋의 app/assets/catalog.json이 그 커밋의 catalog/로 다시 만든 것과 같은지 본다.

커밋 훅을 거치지 않는 merge, rebase, cherry-pick과 JSON을 만드는 코드만 바꾼 커밋도 여기서 잡는다. catalog_json.py
"""

import subprocess
import sys

from catalog_json import errors

sys.stderr.reconfigure(encoding="utf-8")
root = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False
).stdout.strip()
found = []
# 한 줄이 "<로컬 ref> <로컬 sha> <원격 ref> <원격 sha>"다. 지우는 푸시는 로컬 sha가 0뿐이라 볼 것이 없다
for line in sys.stdin:
    _, sha, *_ = line.split()
    if set(sha) != {"0"}:
        found += errors(root, sha)
if found:
    print("푸시를 막았다\n- " + "\n- ".join(dict.fromkeys(found)), file=sys.stderr)
    sys.exit(1)
