"""2026-10-10 이어받기 다음 묶음. 일반 초안에서 고른 카드의 초안 글을 expand1/drafts에 꺼낸다. 운영과 catalog/는 건드리지 않는다."""

import json
from pathlib import Path

BASE = Path(__file__).resolve().parent
OUT = BASE / "expand1"
CARDS = [
    "hana-282", "hana-94264", "hana-10222", "hana-151",
    "samsung-aap1544", "samsung-aap1817", "samsung-abp0291",
    "lotte-1795", "nh-f20016", "woori-834632",
    "kb-09314", "kb-09218", "kb-04368",
]


def rows():
    first = json.loads((BASE / "drafts-response.json").read_text(encoding="utf-8-sig"))
    second = json.loads((BASE / "drafts-chunk1.json").read_text(encoding="utf-8-sig"))
    for data in (first["result"]["data_array"], second["data_array"]):
        for (text,) in data:
            yield json.loads(text)


def main():
    (OUT / "drafts").mkdir(parents=True, exist_ok=True)
    found = {}
    for row in rows():
        if row["card_id"] in CARDS:
            found[row["card_id"]] = row
    packet = []
    for card in CARDS:
        row = found[card]
        (OUT / "drafts" / f"{card}.yaml").write_text(row["draft_yaml"], encoding="utf-8", newline="\n")
        packet.append({k: v for k, v in row.items() if k != "draft_yaml"})
    (OUT / "packet.json").write_text(json.dumps(packet, ensure_ascii=False, indent=2), encoding="utf-8")
    print(len(packet), "장", sorted(packet[0].keys()))


if __name__ == "__main__":
    main()
