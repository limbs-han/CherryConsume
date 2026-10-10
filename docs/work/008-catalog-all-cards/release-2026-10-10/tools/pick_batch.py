"""다음 조사 묶음 고르기. 구조 검사 오류 없이 계산 혜택이 있는 일반 초안 가운데 아직 결과가 없는 개인 카드.

`uv run --project backend python tmp/release-card-expansion/pick_batch.py <그룹> <장 수>`. 고른 목록을 <그룹>/pick.json에 쓴다.
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
group, count = sys.argv[1], int(sys.argv[2])

triage = json.loads((BASE / "triage-results.json").read_text(encoding="utf-8"))
done = {
    r["card_id"]: r["status"]
    for r in json.loads(
        (
            ROOT / "docs/work/008-catalog-all-cards/release-2026-10-10/all-results.json"
        ).read_text(encoding="utf-8")
    )
}
taken = set()
for g in BASE.glob("expand*/pick.json"):
    taken |= set(json.loads(g.read_text(encoding="utf-8")))
for g in BASE.glob("expand*/results/*.json"):
    taken.add(json.loads(g.read_text(encoding="utf-8"))["card_id"])
    taken.add(json.loads(g.read_text(encoding="utf-8")).get("draft_card_id"))

# 직원, 단체, 학교, 법인, 사업자 전용으로 보이는 이름은 뺀다. 개인 카드 대상이 아니다
narrow = re.compile(
    r"W_UNI|안내|사원|임직원|직원|복지|공무원|군인|학교|대학교|고등학교|W_SCHOOL|법인|기업|사업자|소상공인|BIZ|Biz|biz|COMPANY|Company|"
    r"화물|트럭|택시|조합|협회|노인회|교직원|상근|공단|MY COMPANY|joyful|Joyful|패밀리포인트|구매전용|우편|정부"
)
picked = []
for r in triage:
    cid = r["card_id"]
    if (
        done.get(cid, "source_review_pending") != "source_review_pending"
        or cid in taken
    ):
        continue
    if (
        r.get("has_errors")
        or not r.get("resolved_benefit_count")
        or r.get("sale_status") != "on_sale"
    ):
        continue
    if narrow.search(r.get("name", "")):
        continue
    picked.append(r)
# 추천과 요청이 먼저, 그다음 혜택이 많은 카드. 카드사를 고르게 섞는다
picked.sort(
    key=lambda r: (
        not r.get("recommended"),
        not r.get("requested"),
        -r.get("resolved_benefit_count", 0),
    )
)
by_issuer = {}
for r in picked:
    by_issuer.setdefault(r["issuer"], []).append(r)
out = []
while len(out) < count and any(by_issuer.values()):
    for issuer in sorted(by_issuer):
        if by_issuer[issuer] and len(out) < count:
            out.append(by_issuer[issuer].pop(0))
(BASE / group).mkdir(exist_ok=True)
(BASE / group / "pick.json").write_text(
    json.dumps([r["card_id"] for r in out], ensure_ascii=False, indent=1),
    encoding="utf-8",
)
print("남은 대상", len(picked), "고른 것", len(out), Counter(r["issuer"] for r in out))
for r in out:
    print(r["card_id"], r.get("kind"), r.get("resolved_benefit_count"), r["name"][:30])
