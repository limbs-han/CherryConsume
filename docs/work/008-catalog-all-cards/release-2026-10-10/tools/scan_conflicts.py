"""승인 후보 전체의 상품 코드와 이름 겹침을 한 번에 찾는다. package.py는 첫 겹침에서 멈춘다."""

import json
from pathlib import Path

from cherry_core.pipeline.approve import new_card_conflicts

B = Path(__file__).resolve().parent
ROOT = B.parents[1]
CAT = B / "combined/catalog"
cands = json.loads((B / "combined/candidates.json").read_text(encoding="utf-8"))
staged = {
    p.relative_to(ROOT / "catalog").as_posix(): p.read_text(encoding="utf-8")
    for p in (ROOT / "catalog").rglob("*.yaml")
}
for c in cands:
    rel = c["path"]
    if (ROOT / "catalog" / rel).exists():
        continue
    text = (CAT / rel).read_text(encoding="utf-8")
    issuer = rel.split("/")[1]
    if bad := new_card_conflicts(text, staged, issuer, rel):
        print(c["card_id"], c["group"], bad)
    staged[rel] = text
print("끝")
