"""expand1 원문 재대조 지적 반영. 2026-10-10 card-verifier 두 번의 결과."""

import json
from pathlib import Path

B = Path(__file__).resolve().parent
C = B / "catalog/cards"


def edit(rel, pairs):
    p = C / rel
    s = p.read_text(encoding="utf-8")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:60])
        s = s.replace(a, b)
    p.write_text(s, encoding="utf-8", newline="\n")


utility_q = (
    "  - {path: 'revisions[0].spend.exclude_categories', question: '원문 실적 제외는 \"공과금, 도시가스 이용금액\"이다. "
    "전기와 수도가 공과금에 드는지 원문만으로 단정할 수 없어 utility 전체를 뺐다.', assumed: utility 전체}\n"
)
refund = "발급수수료 2,000원은 수령 다음달 말일까지 1만원 이상 쓰면 돌려준다. "

# 하나 1Q, 길한통: 공과금 범위는 확인 필요로, 원문에 없는 발급수수료 환급 문장은 지운다
edit(
    "hana/hana-282.yaml",
    [
        ("open_questions:\n", "open_questions:\n" + utility_q),
        ("연회비 없음, " + refund, "연회비 없음. "),
    ],
)
edit(
    "hana/hana-10222.yaml",
    [
        ("open_questions:\n", "open_questions:\n" + utility_q),
        ("연회비 없음, " + refund, "연회비 없음. "),
    ],
)
# 해피포인트: 취소분을 다음 캐쉬백에서 깎는 방식은 계산하지 않는 조건으로 적는다
edit(
    "hana/hana-151.yaml",
    [
        (
            "unmodeled: [아이사랑카드로 전환 등록하면 어린이집 정부지원금은 실적과 모든 혜택에서 빠진다]",
            "unmodeled: [아이사랑카드로 전환 등록하면 어린이집 정부지원금은 실적과 모든 혜택에서 빠진다, 매출 취소 시 이미 캐쉬백된 금액은 다음 매출의 캐쉬백에서 뺀다]",
        )
    ],
)
# LFmall: 연회비 15,000원. 모바일 공식 페이지와 데스크톱 머리가 같다
edit(
    "kb/kb-09314.yaml",
    [
        (
            "status: on_sale\nsources:",
            "status: on_sale\nannual_fees:\n  - {scope: domestic, amount: 15000}\n  - {scope: global, brand: mastercard, amount: 15000}\nsources:",
        ),
        (
            "  - {path: 'sources[0]', question: '상품 페이지 머리는 연회비 15,000원인데 연회비 탭 표는 국내전용과 국내외겸용 모두 기본 7천원, 제휴 1만8천원, 합계 2만5천원이다. 표의 요약 문구가 GS SHOP 카드라 다른 상품 표를 옮긴 것으로 보이지만 상품설명서 PDF로 확인해야 한다. 연회비를 비워 둔다.'}\n",
            "",
        ),
        (
            "LFmall 할인은 lfmall",
            "연회비는 모바일 공식 페이지 m.kbcard.com/c/09314의 합계 1만5천원과 데스크톱 머리의 국내전용, MASTER 15,000원을 따른다. 데스크톱 연회비 탭 표는 이 카드에 없는 K-World와 VISA 행이 있어 다른 상품 표로 본다. LFmall 할인은 lfmall",
        ),
    ],
)
# taptap: 원문 실적 제외 목록에 연회비가 없다
edit(
    "samsung/samsung-aap1544.yaml",
    [
        (
            "exclude_categories: [annual_fee, apartment_fee, education.tuition,",
            "exclude_categories: [apartment_fee, education.tuition,",
        )
    ],
)
# 올리 POINT: 1위와 2위 추가 적립의 한도가 합산인지 원문에 없다
edit(
    "nh/nh-f20016.yaml",
    [
        (
            "open_questions:\n",
            "open_questions:\n  - {path: 'revisions[0].limits', question: 원문은 추가적립 한도 5천 하나만 적었다. 1위와 2위 추가적립이 한도를 함께 쓰는지 따로 쓰는지 문구가 없다, assumed: 함께 쓴다}\n",
        )
    ],
)

# 토스 LIKIT ALL: id를 다른 롯데 카드처럼 상품 코드로. 1795는 색인 번호이고 The CJ 롯데카드 코드 P01795와 겹친다
old, new = "lotte-1795", "lotte-p14129-a14129"
src = C / "lotte" / f"{old}.yaml"
if src.exists():
    text = src.read_text(encoding="utf-8").replace(f"id: {old}\n", f"id: {new}\n", 1)
    (C / "lotte" / f"{new}.yaml").write_text(text, encoding="utf-8", newline="\n")
    src.unlink()
    case = B / "cases" / f"{old}.yaml"
    (B / "cases" / f"{new}.yaml").write_text(
        case.read_text(encoding="utf-8").replace(f"card: {old}", f"card: {new}", 1),
        encoding="utf-8",
        newline="\n",
    )
    case.unlink()
    res = B / "results" / f"{old}.json"
    r = json.loads(res.read_text(encoding="utf-8"))
    r["card_id"], r["draft_card_id"] = new, old
    (B / "results" / f"{new}.json").write_text(
        json.dumps(r, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    res.unlink()
print("반영 끝")
