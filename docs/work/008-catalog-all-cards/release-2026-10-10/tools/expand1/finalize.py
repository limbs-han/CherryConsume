"""expand1 결과를 assemble.py와 package.py가 읽는 모양으로 모은다. result.json, needed_common.json, packet.json."""

import json
from pathlib import Path

B = Path(__file__).resolve().parent


def read(p):
    return json.loads(p.read_text(encoding="utf-8"))


results = [read(p) for p in sorted((B / "results").glob("*.json"))]
(B / "result.json").write_text(
    json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
)

needed, seen = [], set()
for p in sorted((B / "needed").glob("*.json")):
    for item in read(p):
        d = item["definition"]
        key = (item["file"], d.get("key") or f"{d.get('parent')}.{d.get('code')}")
        if key not in seen:
            seen.add(key)
            needed.append(item)
(B / "needed_common.json").write_text(
    json.dumps(needed, ensure_ascii=False, indent=2), encoding="utf-8"
)

# package.py는 packet.json의 draft.card_id로 초안 번호를 찾는다. id를 바꾼 카드는 새 id로 찾게 한다
renamed = {r["draft_card_id"]: r["card_id"] for r in results if r.get("draft_card_id")}
packet = read(B / "packet.json")
if packet and "draft" not in packet[0]:
    packet = [
        {"draft": {**p, "card_id": renamed.get(p["card_id"], p["card_id"])}}
        for p in packet
    ]
    (B / "packet.json").write_text(
        json.dumps(packet, ensure_ascii=False, indent=2), encoding="utf-8"
    )
print({r["card_id"]: r["status"] for r in results}, len(needed), "공통 제안")
