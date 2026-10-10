"""조사 묶음 폴더 꾸리기. <그룹>/pick.json의 카드 초안을 drafts에 꺼내고, 합친 카탈로그 사본과 검사 도구를 둔다.

`uv run --project backend python tmp/release-card-expansion/expand_prepare.py <그룹>`. 운영과 catalog/는 건드리지 않는다.
"""

import json
import shutil
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
OUT = BASE / sys.argv[1]
cards = json.loads((OUT / "pick.json").read_text(encoding="utf-8"))


def rows():
    first = json.loads((BASE / "drafts-response.json").read_text(encoding="utf-8-sig"))
    second = json.loads((BASE / "drafts-chunk1.json").read_text(encoding="utf-8-sig"))
    for data in (first["result"]["data_array"], second["data_array"]):
        for (text,) in data:
            yield json.loads(text)


found = {r["card_id"]: r for r in rows() if r["card_id"] in cards}
for d in ("drafts", "cases", "needed", "results"):
    (OUT / d).mkdir(parents=True, exist_ok=True)
packet = []
for card in cards:
    row = found[card]
    (OUT / "drafts" / f"{card}.yaml").write_text(
        row["draft_yaml"], encoding="utf-8", newline="\n"
    )
    packet.append({"draft": {k: v for k, v in row.items() if k != "draft_yaml"}})
(OUT / "packet.json").write_text(
    json.dumps(packet, ensure_ascii=False, indent=2), encoding="utf-8"
)
if not (OUT / "catalog").exists():
    shutil.copytree(BASE / "combined/catalog", OUT / "catalog")
shutil.copy2(BASE / "expand1/validate.py", OUT / "validate.py")
print(len(packet), "장 준비", OUT)
