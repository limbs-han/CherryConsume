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
# 앱 JSON에 닿는 곳. JSON을 만드는 코드가 바뀌어도 다시 본다
WATCH = ["catalog", "app/assets/catalog.json", "backend/cherry_core/catalog"]


def pushed(root: str, sha: str) -> list[str]:
    """올리는 커밋 가운데 앱 JSON에 닿는 것. 원격 가지에 아직 없는 커밋 모두다. 끝 커밋만 보면 앞 커밋의 어긋난
    JSON이 그대로 올라간다. 작업 013 13-21"""
    return subprocess.run(
        ["git", "rev-list", sha, "--not", "--remotes", "--", *WATCH],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    ).stdout.split()


if __name__ == "__main__":
    found = []
    # 한 줄이 "<로컬 ref> <로컬 sha> <원격 ref> <원격 sha>"다. 지우는 푸시는 로컬 sha가 0뿐이라 볼 것이 없다
    for line in sys.stdin:
        _, sha, *_ = line.split()
        if set(sha) != {"0"}:
            for rev in pushed(root, sha):
                found += errors(root, rev)
    if found:
        print("푸시를 막았다\n- " + "\n- ".join(dict.fromkeys(found)), file=sys.stderr)
        sys.exit(1)
