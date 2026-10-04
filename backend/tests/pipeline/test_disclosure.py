"""카드사 상품공시실과 카드 목록 응답에서 색인 행 뽑기. 작업 008 설계 1절.

표본은 2026-10-03 받은 응답에서 몇 행만 자른 것이다. 농협 표본은 발급 종료 카드가 없어 둘째 카드의 sel_yn만 0으로 바꿨다.
"""

import json
from datetime import date
from pathlib import Path

import pytest

from cherry_core.pipeline.disclosure import (
    PLANS,
    IndexRow,
    KnownCard,
    Request,
    card_ids,
    collectable,
    merge_rows,
    must_have_rows,
    nuxt_data,
    read,
    recommended_keys,
    row_key,
)

FIXTURES = Path(__file__).parent / "fixtures" / "disclosure"


def rows(issuer: str, source_id: str, name: str) -> list[IndexRow]:
    return read(issuer, source_id, (FIXTURES / name).read_bytes())


def test_lotte_disclosure_list_has_pdf_and_issue_end():
    got = rows("lotte", "disclosure", "lotte_disclosure.json")
    pdf = "https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/"
    assert got == [
        IndexRow("lotte", "웅진씽크빅 롯데카드", pdf_urls=(pdf + "2017-A00031_20261002_10011.pdf",), detail_ref="1489"),
        IndexRow(
            "lotte", "LOCA CLASSIC 롯데마트", pdf_urls=(pdf + "2023-A00007_20260930_10002.pdf",), detail_ref="1828"
        ),
        IndexRow(
            "lotte",
            "DC플러스 카드",
            status="discontinued",
            pdf_urls=(pdf + "2009-A00024_20261001_10011.pdf",),
            detail_ref="1118",
        ),
    ]


def test_lotte_card_list_has_code_and_page():
    got = rows("lotte", "cards-credit", "lotte_cards.json")
    assert got[0] == IndexRow(
        "lotte",
        "롯데마트&MAXX 카드",
        code="P14312-A14312",
        kind="credit",
        page_url="https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P14312-A14312",
        enrich_only=True,
    )
    assert [r.name for r in got] == ["롯데마트&MAXX 카드", "디지로카 Las Vegas"]


def test_shinhan_kind_comes_from_card_type():
    got = rows("shinhan", "cards", "shinhan_cards.json")
    assert got == [
        IndexRow(
            "shinhan",
            "신한카드 Hi-Point Plan",
            code="POKE1M",
            kind="credit",
            launched_on=date(2026, 4, 27),
            page_url="https://www.shinhancard.com/pconts/html/card/apply/credit/2013774_2207.html",
        ),
        IndexRow(
            "shinhan",
            "SOL LINK 신한카드 Point Plan 체크",
            code="POBE2Z",
            kind="check",
            launched_on=date(2026, 8, 7),
            page_url="https://www.shinhancard.com/pconts/html/card/apply/check/2014281_2206.html",
        ),
    ]


def test_nh_sale_flag_zero_is_discontinued():
    got = rows("nh", "cards-credit", "nh_cards.json")
    assert got == [
        IndexRow(
            "nh",
            "the Origins카드",
            code="F10802",
            kind="credit",
            page_url="https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010626",
        ),
        IndexRow(
            "nh",
            "zgm 러닝",
            code="F10834",
            kind="credit",
            status="discontinued",
            page_url="https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010629",
        ),
    ]


def test_kakaobank_groups_keep_only_cards_and_docs_keep_only_product_sheet():
    assert rows("kakaobank", "groups", "kakaobank_groups.json") == [
        IndexRow("kakaobank", "카카오뱅크 프렌즈 체크카드", code="30", kind="check"),
        IndexRow("kakaobank", "카카오뱅크 mini카드", code="77"),
    ]
    assert rows("kakaobank", "docs", "kakaobank_docs.json") == [
        IndexRow(
            "kakaobank",
            "카카오뱅크 프렌즈 체크카드",
            code="30",
            kind="check",
            pdf_urls=("https://og.kakaobank.io/view/4e347d49-30a1-436d-99f2-03480c19b36a",),
            enrich_only=True,
        )
    ]


def test_ibk_list_has_code_kind_from_name_and_sale_stop_icon():
    got = rows("ibk", "cards", "ibk_cards.html")
    assert got == [
        IndexRow(
            "ibk",
            "일상의 기쁨카드(신용)",
            code="12113090001",
            kind="credit",
            page_url="https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=309&PDCD=0001&pageId=CA01010000",
        ),
        IndexRow(
            "ibk",
            "마일앤조이카드(대한항공)",
            code="12113130001",
            status="discontinued",
            page_url="https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=313&PDCD=0001&pageId=CA01010000",
        ),
    ]


def test_kb_disclosure_table_has_launch_and_issue_end_dates():
    got = rows("kb", "disclosure-credit", "kb_disclosure.html")
    assert got == [
        IndexRow(
            "kb",
            "KB국민 Fnsave카드",
            code="09026",
            kind="credit",
            status="discontinued",
            launched_on=date(2008, 4, 4),
            discontinued_on=date(2009, 4, 10),
            pdf_urls=("https://img2.kbcard.com/obj/card/download/09026__prdctOpmn_20180508.pdf",),
        ),
        IndexRow(
            "kb",
            "KB국민 알파원카드",
            code="04587",
            kind="credit",
            launched_on=date(2016, 2, 25),
            pdf_urls=("https://img2.kbcard.com/obj/card/download/04587__prdctOpmn_20210923.pdf",),
            page_url="https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=04587",
        ),
    ]


def test_hyundai_manuals_files_and_cards():
    # 설명서 목록이 색인이다. 사업자와 제휴 카드까지 판매 중 카드가 다 있다. 카드 목록과 설명서 파일은 코드, 그림, PDF만 채운다
    assert rows("hyundai", "manuals", "hyundai_manuals.html") == [
        IndexRow(
            "hyundai",
            "네이버 현대카드 Edition2",
            kind="credit",
            status="discontinued",
            launched_on=date(2024, 11, 22),
            discontinued_on=date(2026, 8, 25),
            detail_ref="161602",
        ),
        IndexRow(
            "hyundai",
            "the Green Edition4",
            kind="credit",
            launched_on=date(2026, 8, 24),
            detail_ref="181608",
        ),
    ]
    assert rows("hyundai", "files", "hyundai_files.json") == [
        IndexRow(
            "hyundai",
            "",
            detail_ref="181608",
            pdf_urls=(
                "https://www.hyundaicard.com/upload/card/20260824_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_the%20Green%20Edition4.pdf",
            ),
            enrich_only=True,
        )
    ]
    cards = rows("hyundai", "cards", "hyundai_cards.html")
    assert cards[0] == IndexRow(
        "hyundai",
        "the Black",
        code="TBE4",
        kind="credit",
        page_url="https://www.hyundaicard.com/cpc/cr/CPCCR0201_01.hc?cardWcd=TBE4",
        enrich_only=True,
    )
    assert [r.code for r in cards] == ["TBE4", "TPE4"]


def test_nuxt_function_call_is_unpacked():
    # 삼성 추천 페이지의 window.__NUXT__는 (function(a,b,…){return {…}}(값들)) 모양이다. 표본은 2026-10-03 받은 모양을 줄였다
    data = nuxt_data((FIXTURES / "samsung_recommend.html").read_text(encoding="utf-8"))
    card = data["data"][0]["hub"]["props"]["code3"]["bgdPcdList"][0]
    assert card["cardTitle"] == "삼성카드 taptap O"
    assert card["imgInfo"]["pcImg1"] == "/wcms/home/scard/image/personal/b_AAP1483.png"
    assert (card["isNew"], card["price"], card["empty"], card["none"]) == (False, -150.0, None, None)
    assert data["data"][0]["wcms"][1] == {"code": "AAP0001", "detailUrl": "/wcms/home/scard/personal/1_1.json"}
    assert data["serverRendered"] is True
    assert data["data"][0]["hub"]["props"]["code3"]["selectDataMap"] == {"k": 1}


def test_samsung_recommend_lists_each_card_once():
    page = "https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code="
    assert rows("samsung", "recommend-credit", "samsung_recommend.html") == [
        IndexRow("samsung", "모니모페이카드", code="AAP1918", kind="credit", page_url=page + "AAP1918"),
        IndexRow("samsung", "삼성카드 taptap O", code="AAP1483", kind="credit", page_url=page + "AAP1483"),
    ]


def test_unknown_issuer_or_source_is_an_error():
    with pytest.raises(KeyError, match="nobody cards"):
        read("nobody", "cards", b"{}")


def test_merge_by_code_then_detail_ref_then_name():
    disclosure = [
        IndexRow("lotte", "LOCA 365 카드", status="discontinued", pdf_urls=("https://p/1.pdf",)),
        IndexRow("lotte", "디지로카 London", pdf_urls=("https://p/2.pdf",)),
    ]
    cards = [IndexRow("lotte", "디지로카 london", code="C1", kind="credit", page_url="https://c/1", enrich_only=True)]
    manuals = [IndexRow("hyundai", "현대카드 X Cut", launched_on=date(2026, 8, 24), detail_ref="181608")]
    files = [IndexRow("hyundai", "", detail_ref="181608", pdf_urls=("https://p/3.pdf",), enrich_only=True)]
    hd_cards = [IndexRow("hyundai", "X Cut", code="XC", kind="credit", enrich_only=True)]
    merged, unmatched = merge_rows(disclosure + cards + manuals + files + hd_cards)
    assert merged == [
        IndexRow("lotte", "LOCA 365 카드", status="discontinued", pdf_urls=("https://p/1.pdf",)),
        IndexRow(
            "lotte",
            "디지로카 London",
            code="C1",
            kind="credit",
            pdf_urls=("https://p/2.pdf",),
            page_url="https://c/1",
        ),
        IndexRow(
            "hyundai",
            "현대카드 X Cut",
            code="XC",
            kind="credit",
            launched_on=date(2026, 8, 24),
            pdf_urls=("https://p/3.pdf",),
            detail_ref="181608",
        ),
    ]
    assert unmatched == []


def test_name_match_ignores_brand_words_spaces_and_marks():
    # 현대 카드 목록은 짧은 이름, 설명서 목록은 카드사 이름을 붙인 긴 이름을 쓴다. 2026-10-03 84장 가운데 81장이 이것으로 짝지어진다
    cards = [
        IndexRow("hyundai", "D", code="D", enrich_only=True),
        IndexRow("hyundai", "ZERO Up (할인형)", code="ZU", enrich_only=True),
    ]
    manuals = [
        IndexRow("hyundai", "알파벳카드D", detail_ref="1"),
        IndexRow("hyundai", "현대카드 ZERO Up(할인형)", detail_ref="2"),
    ]
    merged, unmatched = merge_rows(cards + manuals)
    assert [(r.code, r.detail_ref) for r in merged] == [("D", "1"), ("ZU", "2")]
    assert unmatched == []


def test_two_index_rows_do_not_merge_by_name_and_enrich_prefers_on_sale():
    # 같은 이름의 옛 판이 발급 중단으로 남아 있다. 보충용 카드 목록 행은 판매 중인 쪽을 채운다
    old = IndexRow("hyundai", "현대카드M", status="discontinued", discontinued_on=date(2024, 1, 1), detail_ref="1")
    new = IndexRow("hyundai", "현대카드M", detail_ref="2")
    card = IndexRow("hyundai", "M", code="M", enrich_only=True)
    merged, unmatched = merge_rows([old, new, card])
    assert merged == [old, IndexRow("hyundai", "현대카드M", code="M", detail_ref="2")]
    assert unmatched == []


def test_name_match_needs_same_sale_status():
    # 2026-10-03 현대 카드 목록의 "네이버"는 지금 파는 Edition3인데 이름이 같은 옛 "네이버 현대카드"가 발급 중단으로 남아 있었다
    old = IndexRow("hyundai", "네이버 현대카드", status="discontinued", detail_ref="1")
    card = IndexRow("hyundai", "네이버", code="NVE3", enrich_only=True)
    merged, unmatched = merge_rows([old, card])
    assert merged == [old]
    assert unmatched == [card]


def test_enrich_only_rows_without_partner_are_returned_apart():
    # 보충용 행이 짝을 못 찾으면 색인에 넣지 않고 따로 돌려준다. 같은 카드가 두 번 색인되지 않게 하고 사람이 이름을 본다
    lone = IndexRow("lotte", "지마켓 꼭 롯데카드", code="X1", enrich_only=True)
    merged, unmatched = merge_rows([IndexRow("lotte", "LOCA 365 카드"), lone])
    assert merged == [IndexRow("lotte", "LOCA 365 카드")]
    assert unmatched == [lone]


def test_merge_keeps_discontinued_and_unions_pdfs():
    a = IndexRow("kb", "카드", code="1", pdf_urls=("https://p/a.pdf",))
    b = IndexRow(
        "kb", "카드", code="1", status="discontinued", discontinued_on=date(2026, 9, 1), pdf_urls=("https://p/b.pdf",)
    )
    merged, _ = merge_rows([a, b])
    assert merged == [
        IndexRow(
            "kb",
            "카드",
            code="1",
            status="discontinued",
            discontinued_on=date(2026, 9, 1),
            pdf_urls=("https://p/a.pdf", "https://p/b.pdf"),
        )
    ]


def test_read_takes_kind_and_ignores_page_number():
    got = rows("kb", "disclosure-check-p3", "kb_disclosure.html")
    assert got and {r.kind for r in got} == {"check"}
    assert {r.kind for r in rows("lotte", "cards-credit-A101-p2", "lotte_cards.json")} == {"credit"}


def asked(issuer: str, answer) -> list[Request]:
    """가짜 받기로 받기 함수를 돌려 요청을 차례로 모은다. answer는 요청마다 돌려줄 응답이다."""
    out: list[Request] = []

    def fetch(req: Request) -> bytes:
        out.append(req)
        return answer(req)

    PLANS[issuer](fetch, date(2026, 10, 4))
    return out


def test_kb_reads_page_count_from_first_page_of_each_tab():
    totals = {"credit": 25, "check": 10}
    got = asked(
        "kb", lambda r: f'<div class="totalNum">총<strong>{totals[r.source_id.split("-")[1]]}</strong>건</div>'.encode()
    )
    assert [r.source_id for r in got] == [
        "disclosure-credit-p1",
        "disclosure-credit-p2",
        "disclosure-credit-p3",
        "disclosure-check-p1",
    ]
    assert got[1].form == {"카드분류코드": "0", "카드검색그룹코드": "", "pageCount": "2", "카드명": ""}
    assert got[3].form["카드분류코드"] == "1"


def test_page_count_missing_stops_the_issuer():
    with pytest.raises(ValueError, match="totalNum"):
        asked("kb", lambda r: b"<html>maintenance</html>")


@pytest.mark.parametrize(
    ("issuer", "body", "ids"),
    [
        (
            "ibk",
            b'<strong class="f_count">11</strong>',
            ["cards-p1", "cards-p2", "cards-credit-p1", "cards-credit-p2", "cards-check-p1", "cards-check-p2"],
        ),
        (
            "nh",
            b'{"totalPage": "2"}',
            ["cards-p1", "cards-p2", "cards-credit-p1", "cards-credit-p2", "cards-check-p1", "cards-check-p2"],
        ),
        (
            "shinhan",
            b'{"payload": {"totalPage": 1}}',
            ["cards-credit-p1", "cards-check-p1", "cards-all-p1"],
        ),
    ],
)
def test_paged_issuers(issuer, body, ids):
    assert [r.source_id for r in asked(issuer, lambda r: body)] == ids


def test_lotte_asks_whole_disclosure_list_at_once_then_card_tabs():
    def answer(r: Request) -> bytes:
        if r.source_id.startswith("disclosure"):
            inner = {"result": {"collection": [{"totalcount": "2", "docs": [{}, {}]}]}}
            return json.dumps({"Content": json.dumps(inner)}).encode()
        return json.dumps({"Param": {"totalRowCnt": 2 if "A100" in r.url else 1}}).encode()

    got = asked("lotte", answer)
    assert [r.source_id for r in got] == [
        "disclosure",
        "cards-credit-A100-p1",
        "cards-credit-A100-p2",
        "cards-credit-A101-p1",
        "cards-credit-A102-p1",
        "cards-check-A100-p1",
        "cards-check-A100-p2",
        "cards-check-A101-p1",
    ]
    assert got[0].form["listcount"] == "2000"


def test_lotte_short_disclosure_list_stops():
    inner = {"result": {"collection": [{"totalcount": "531", "docs": [{}] * 500}]}}
    body = json.dumps({"Content": json.dumps(inner)}).encode()
    with pytest.raises(ValueError, match="500건만"):
        asked("lotte", lambda r: body)


def test_empty_list_total_stops_instead_of_reading_no_cards():
    with pytest.raises(ValueError, match="총수가 0"):
        asked("kb", lambda r: '<div class="totalNum">총<strong>0</strong>건</div>'.encode())


def test_kakaobank_asks_docs_for_each_card_group():
    groups = (FIXTURES / "kakaobank_groups.json").read_bytes()
    got = asked("kakaobank", lambda r: groups)
    codes = [r.code for r in rows("kakaobank", "groups", "kakaobank_groups.json")]
    assert [r.source_id for r in got] == ["groups"] + [f"docs-{c}" for c in codes]
    assert got[1].url.endswith(f"/{codes[0]}?hmpg_yn=Y")


def test_hyundai_asks_files_only_for_cards_still_collected():
    manuals = (
        '<p class="h4_m_lt">판매 중</p><span>상품출시일 : 2024.01.02</span> sqno="1"'
        '<p class="h4_m_lt">작년 단종</p><span>발급중단일 : 2025.03.01</span> sqno="2"'
        '<p class="h4_m_lt">오래된 단종</p><span>발급중단일 : 2023.10.04</span> sqno="3"'
    ).encode()
    got = asked("hyundai", lambda r: manuals)
    assert [r.source_id for r in got] == ["manuals", "cards", "files-1", "files-2"]
    assert got[2].form == {"sqno": "1"}


def test_collectable_is_on_sale_or_discontinued_within_three_years():
    today = date(2026, 10, 4)
    assert collectable(IndexRow("kb", "a"), today)
    assert collectable(IndexRow("kb", "b", status="discontinued"), today)
    assert collectable(IndexRow("kb", "c", status="discontinued", discontinued_on=date(2023, 10, 5)), today)
    assert not collectable(IndexRow("kb", "d", status="discontinued", discontinued_on=date(2023, 10, 4)), today)


def test_row_key_prefers_disclosure_number_then_code_then_name():
    assert row_key(IndexRow("hyundai", "네이버", code="NV3", detail_ref="181608")) == "ref:181608"
    assert row_key(IndexRow("kb", "톡톡", code="09174")) == "code:09174"
    assert row_key(IndexRow("hana", "원더카드 2.0 Daily")) == "name:원더20daily"


def test_card_ids_use_catalog_code_or_name_and_make_ids_for_the_rest():
    known = [
        KnownCard("ibk-nara", "ibk", ("나라사랑카드",), ("12-11-296-0001",)),
        KnownCard("hyundai-naver", "hyundai", ("네이버 현대카드",), ()),
        KnownCard("kb-toktok", "kb", ("청춘대로 톡톡카드",), ()),
    ]
    rows = [
        IndexRow("ibk", "나라사랑카드(신용)", code="12112960001"),
        IndexRow("hyundai", "네이버 현대카드", status="discontinued", detail_ref="100"),
        IndexRow("hyundai", "네이버 Edition3", detail_ref="181608"),
        IndexRow("kb", "청춘대로 톡톡카드", code="09174"),
        IndexRow("kb", "새 카드", code="09999"),
        IndexRow("hana", "원더카드 2.0 Daily"),
    ]
    got = card_ids(rows, known)
    assert got[0] == ("ibk-nara", True)
    # 이름이 같은 판이 판매 중에 없으면 단종 판이 카탈로그 id를 받는다
    assert got[1] == ("hyundai-naver", True)
    assert got[2] == ("hyundai-181608", False)
    assert got[3] == ("kb-toktok", True)
    assert got[4] == ("kb-09999", False)
    assert got[5][0].startswith("hana-n") and not got[5][1]


def test_only_on_sale_row_gets_catalog_id_when_names_repeat():
    known = [KnownCard("lotte-loca365", "lotte", ("LOCA 365 카드",), ())]
    rows = [
        IndexRow("lotte", "LOCA 365 카드", status="discontinued", detail_ref="1"),
        IndexRow("lotte", "LOCA 365 카드", detail_ref="2"),
    ]
    assert card_ids(rows, known) == [("lotte-1", False), ("lotte-loca365", True)]


def test_index_row_takes_every_enrich_row_that_came_before_it():
    # 2026-10-04 받은 현대 원문은 경로 순서로 설명서 파일, 카드 목록, 설명서 목록이 온다. 설명서 행이 파일 행과 카드 행 둘에
    # 짝지어지는데 하나에만 합쳐져 판매 중 77장의 PDF가 빠졌다
    files = IndexRow("hyundai", "", detail_ref="12459", pdf_urls=("https://p/cj.pdf",), enrich_only=True)
    card = IndexRow("hyundai", "The CJ M Edition2", code="CJM2", page_url="https://c/cj", enrich_only=True)
    manual = IndexRow("hyundai", "The CJ-현대카드M Edition2", detail_ref="12459")
    merged, unmatched = merge_rows([files, card, manual])
    assert unmatched == []
    assert merged == [
        IndexRow(
            "hyundai",
            "The CJ-현대카드M Edition2",
            code="CJM2",
            pdf_urls=("https://p/cj.pdf",),
            page_url="https://c/cj",
            detail_ref="12459",
        )
    ]


def test_samsung_asks_recommend_check_and_terms_pages():
    got = asked("samsung", lambda r: b'{"totInqrCt": "150"}' if r.source_id.startswith("terms") else b"")
    assert [r.source_id for r in got] == ["recommend-credit", "check", "terms-p1", "terms-p2"]
    assert got[3].json["cndt"]["pgeNo"] == "2" and got[3].form is None


def test_samsung_check_page_lists_cards_with_product_page():
    page = (
        'window.__NUXT__=(function(a){return {data:[{pdList:[{bgdPcd:"ABP1871",cardTitle:"스타벅스 삼성체크카드"},'
        '{bgdPcd:a,cardTitle:"국민행복 삼성체크카드 V2"},{bgdPcd:"",cardTitle:"배너"}]}]}}("ABP1689"));'
    ).encode()
    page_url = "https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code="
    assert read("samsung", "check", page) == [
        IndexRow("samsung", "스타벅스 삼성체크카드", code="ABP1871", kind="check", page_url=page_url + "ABP1871"),
        IndexRow("samsung", "국민행복 삼성체크카드 V2", code="ABP1689", kind="check", page_url=page_url + "ABP1689"),
    ]


def test_samsung_terms_board_gives_pdf_per_card_code():
    board = {
        "totInqrCt": "2",
        "blbdInqrRsList": [
            {
                "bgdAlncPdC": "AAP1920",
                "bltnbmTitNm": "이마트신세계 PLUS 삼성카드",
                "uploadFileList": [
                    {"apnFileNm": "이용안내장.pdf", "apnFileGrpNoE": "1zPV%2Fkwz", "apnFileSn": "1"},
                    {"apnFileNm": "안내.hwp", "apnFileGrpNoE": "x", "apnFileSn": "2"},
                ],
            },
            {"bgdAlncPdC": "AAP0001", "bltnbmTitNm": "옛 카드", "uploadFileList": []},
        ],
    }
    assert read("samsung", "terms-p1", json.dumps(board).encode()) == [
        IndexRow(
            "samsung",
            "이마트신세계 PLUS 삼성카드",
            code="AAP1920",
            pdf_urls=("https://www.samsungcard.com/filedownload.do?grpNo=1zPV%2Fkwz&sn=1",),
            enrich_only=True,
        ),
        IndexRow("samsung", "옛 카드", code="AAP0001", enrich_only=True),
    ]


def test_woori_issue_stop_is_discontinued_and_codeless_rows_are_skipped():
    page = "https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd="
    assert rows("woori", "disclosure", "woori_disclosure.json") == [
        IndexRow("woori", "ALL 우리카드 Infinite", code="103187", page_url=page + "103187"),
        IndexRow("woori", "CJ ONE 우리체크", code="103759", kind="check", page_url=page + "103759"),
        IndexRow(
            "woori",
            "#오하쳌(오늘하루체크)",
            code="101201",
            kind="check",
            status="discontinued",
            discontinued_on=date(2022, 9, 7),
            page_url=page + "101201",
        ),
    ]


def test_hana_card_list_is_euc_kr_and_kind_comes_from_category():
    page = "https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ="
    assert rows("hana", "cards-check-241704050328506", "hana_cards.json") == [
        IndexRow("hana", "HERO 체크카드", code="94316", kind="check", page_url=page + "94316"),
        IndexRow("hana", "삼성월렛 하나 트래블로그 체크카드", code="19227", kind="check", page_url=page + "19227"),
    ]


def test_woori_opens_page_in_browser_and_asks_all_rows():
    full = json.dumps({"mainDataList": {"totCnt": "1", "cct11PrdntcAgrmMainVo": [{}]}}).encode()
    (got,) = asked("woori", lambda r: full)
    assert got.capture == "getMainDataList.pwkjson"
    assert "PAGE_SIZE = '2000'" in got.script and got.form is None


def test_hana_asks_each_category():
    categories = {
        "dataMap": {
            "CATEGORY_LIST": {
                "data": [
                    {"CT_NM": "신용카드", "CT_ID": "1"},
                    {"CT_NM": "제휴카드", "CT_ID": "2"},
                    {"CT_NM": "체크카드", "CT_ID": "3"},
                ]
            }
        }
    }
    body = b"\r\r" + json.dumps(categories, ensure_ascii=False).encode("cp949")
    got = asked("hana", lambda r: body)
    assert [r.source_id for r in got] == ["categories", "cards-credit-1", "cards-2", "cards-check-3"]
    assert got[1].form["targetMethod"] == "cardMainList" and got[1].form["CT_ID"] == "1"
    assert read("hana", "categories", body) == []


def test_kb_end_date_9999_means_still_on_sale():
    # 2026-10-04 KB 개인체크 목록이 발급중단일 칸에 9999.12.31을 적은 판매 중 카드를 단종으로 읽혔다
    page = (
        "<table><tr><td>KB국민 노리2 체크카드(Play)</td><td></td><td></td><td>2020.01.02</td><td>9999.12.31</td>"
        "<td><a href=\"javascript:goDetail('07986', 'x', 'y')\">보기</a></td></tr></table>"
    ).encode()
    (row,) = read("kb", "disclosure-check-p16", page)
    assert (row.status, row.discontinued_on, row.launched_on) == ("on_sale", None, date(2020, 1, 2))


def test_hyundai_manual_kind_comes_from_name():
    manuals = (
        '<p class="h4_m_lt">현대카드M CHECK</p> sqno="1"<p class="h4_m_lt">현대카드M HYBRID</p> sqno="2"'
        '<p class="h4_m_lt">MY COMPANY 체크카드</p> sqno="3"<p class="h4_m_lt">현대카드 ZERO Edition3</p> sqno="4"'
    ).encode()
    assert [r.kind for r in read("hyundai", "manuals", manuals)] == ["check", None, "check", "credit"]


def test_carddamoa_recommendations_match_by_page_or_name():
    damoa = {
        "resultList": [
            {"companyNm": "롯데카드", "itemName": "디지로카 London", "itemLink": "https://m.lottecard.co.kr/london"},
            {
                "companyNm": "KB국민카드",
                "itemName": "트래블러스 체크카드",
                "itemLink": "https://card.kbcard.com/x?c=09562",
            },
            {"companyNm": "비씨카드", "itemName": "BC 바로카드", "itemLink": "https://bc"},
        ]
    }
    recs = read("carddamoa", "recommend-credit", json.dumps(damoa).encode())
    assert [(r.issuer, r.recommended, r.enrich_only) for r in recs] == [("lotte", True, True), ("kb", True, True)]
    index = [
        ("lotte", "ref:1", "디지로카 London", None),
        ("kb", "code:09562", "KB국민 트래블러스 체크카드", "https://card.kbcard.com/x?c=09562"),
    ]
    found, missing = recommended_keys(recs, index)
    assert set(found) == {("lotte", "ref:1"), ("kb", "code:09562")}
    assert missing == []


def test_woori_short_answer_stops():
    ten = json.dumps({"mainDataList": {"totCnt": "937", "cct11PrdntcAgrmMainVo": [{}] * 10}}).encode()
    with pytest.raises(ValueError, match="10건만"):
        asked("woori", lambda r: ten)


def test_collectable_on_leap_day():
    assert collectable(IndexRow("kb", "e", status="discontinued", discontinued_on=date(2025, 3, 1)), date(2028, 2, 29))


def test_carddamoa_unknown_company_name_is_kept_for_the_report():
    damoa = {"resultList": [{"companyNm": "국민카드", "itemName": "새 카드", "itemLink": ""}]}
    assert [r.issuer for r in read("carddamoa", "recommend-credit", json.dumps(damoa).encode())] == ["?국민카드"]


def test_only_list_and_enrich_responses_may_be_empty():
    assert must_have_rows("kb", "disclosure-check-p3")
    assert must_have_rows("samsung", "check")
    assert not must_have_rows("lotte", "cards-credit-A102-p1")
    assert not must_have_rows("hana", "categories")


def test_nh_asks_credit_and_check_lists():
    # 2026-10-05 체크 목록만 받아 신용 카드 137장의 종류가 비었다. 화면의 분류는 신용 IPCC0105와 체크 IPCC0106이다
    body = json.dumps({"totalPage": "1", "CARDLIST": []}).encode()
    got = asked("nh", lambda r: body)
    assert [(r.source_id, r.form["cardGubun"]) for r in got] == [
        ("cards-p1", ""),
        ("cards-credit-p1", "IPCC0105"),
        ("cards-check-p1", "IPCC0106"),
    ]


def test_kind_comes_from_official_name_when_lists_have_none():
    merged, _ = merge_rows(
        [
            IndexRow("nh", "제주교통복지카드(신용)", code="1"),
            IndexRow("nh", "서울교육사랑카드(개인체크)", code="2"),
            IndexRow("nh", "LIKIT all CHECK", code="3"),
            IndexRow("nh", "다둥이 카드(신용/체크)", code="4"),
            IndexRow("nh", "the Origins카드", code="5"),
            # 공식 목록의 종류가 이름보다 앞선다
            IndexRow("nh", "NH FIT 신용할인형", code="6", kind="check"),
        ]
    )
    assert [r.kind for r in merged] == ["credit", "check", "check", None, None, "check"]


def test_corporate_cards_are_not_collected():
    today = date(2026, 10, 5)
    for name in (
        "롯데 비즈니스 법인카드",
        "LOCA Biz",
        "CEO카드(기업)",
        "Business Sky 기업카드",
        "LOCA Corporate Zeus",
        "IBK컴퍼니카드(기관)",
    ):
        assert not collectable(IndexRow("lotte", name), today), name
    # 이름에 개인이 있으면 개인 카드다. 낱말 가운데 든 biz는 걸지 않는다
    for name in ("한국사회적기업진흥원 지원금 체크카드(개인)", "LOCA 365", "Bizzy 카드"):
        assert collectable(IndexRow("lotte", name), today), name


WOORI_PAGE = "https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd="


def _woori_list(*cards: tuple[str, str]) -> bytes:
    rows = [{"code": code, "codeName": name, "issuAt": "Y"} for code, name in cards]
    return json.dumps(
        {"mainDataList": {"totCnt": str(len(rows)), "cct11PrdntcAgrmMainVo": rows}}, ensure_ascii=False
    ).encode()


def _woori_detail(code: str, name: str, cfcd: str) -> bytes:
    return json.dumps(
        {"resultVo": {"crd01DtlVo": {"cdPrdCd": code, "cdPrdNm": name, "cdPrdCfcd": cfcd}}}, ensure_ascii=False
    ).encode()


def test_woori_reads_kind_from_card_detail_for_untyped_cards():
    listing = _woori_list(("1", "ALL 우리카드"), ("2", "CJ ONE 우리체크"), ("3", "카드의정석 Biz Platinum"))
    detail = _woori_detail("1", "ALL 우리카드", "1")
    got = asked("woori", lambda r: listing if r.source_id == "disclosure" else detail)
    # 이름으로 종류를 아는 카드와 법인 카드는 상세를 열지 않는다
    assert [(r.source_id, r.url, r.capture) for r in got[1:]] == [
        ("detail-1", WOORI_PAGE + "1", "searchCrdDtl.pwkjson")
    ]
    merged, _ = merge_rows(read("woori", "disclosure", listing) + read("woori", "detail-1", detail))
    assert [(r.code, r.kind) for r in merged] == [("1", "credit"), ("2", "check"), ("3", None)]
    # cdPrdCfcd는 1이 신용, 2가 체크다. 그 밖의 값은 비운다
    assert [read("woori", "detail-9", _woori_detail("9", "x", c))[0].kind for c in ("2", "7")] == ["check", None]


def test_woori_detail_failures_skip_the_card_and_three_in_a_row_stop_details():
    listing = _woori_list(*((str(n), f"카드{n} 우리카드") for n in range(1, 8)))
    ok = {"detail-2"}

    def answer(r):
        if r.source_id == "disclosure":
            return listing
        if r.source_id in ok:
            return _woori_detail("2", "카드2 우리카드", "1")
        raise TimeoutError("detail")

    # 상세는 종류를 채우는 것뿐이라 실패해도 공시 묶음은 쓴다. 실패한 카드는 건너뛰고, 세 번 잇달아 실패하면
    # 사이트에 부담을 주지 않게 남은 상세는 열지 않는다. 2026-10-05 117장째에서 한 장의 응답이 오지 않았다
    got = [r.source_id for r in asked("woori", answer)]
    assert got == ["disclosure", "detail-1", "detail-2", "detail-3", "detail-4", "detail-5"]


def test_woori_detail_without_card_data_is_no_row():
    # 2026-10-05 상세 117장 가운데 2장은 카드 정보 없이 비어 있었다. 읽기가 멈추면 우리 색인 전체가 빠진다
    empty = json.dumps({"resultVo": {"fixedLengthVo": False, "totalPageCount": 1}}).encode()
    assert read("woori", "detail-220136", empty) == []


@pytest.mark.parametrize(
    "body", [b"<html>error</html>", b'{"resultVo": []}', b'{"resultVo": {"crd01DtlVo": {"cdPrdCd": null}}}']
)
def test_broken_woori_detail_is_no_row(body):
    # 상세 하나를 못 읽어 우리 색인 전체가 멈추면 안 된다. 2026-10-05 위험 검토
    assert read("woori", "detail-1", body) == []


def test_woori_detail_block_answer_fails_the_issuer():
    import urllib.error

    listing = _woori_list(("1", "A 우리카드"), ("2", "B 우리카드"))

    def answer(r):
        if r.source_id == "disclosure":
            return listing
        raise urllib.error.HTTPError(r.url, 429, "", {}, None)

    # 거절 답은 차단 신호라 그 카드사를 실패로 센다. 수집기는 이어서 같은 사이트의 상품 페이지를 열지 않는다
    with pytest.raises(urllib.error.HTTPError):
        asked("woori", answer)


def test_woori_details_stop_after_their_time_budget(monkeypatch):
    from cherry_core.pipeline import disclosure

    clock = iter([0.0, 10.0, 4000.0, 4000.0])
    monkeypatch.setattr(disclosure.time, "monotonic", lambda: next(clock))
    listing = _woori_list(("1", "A 우리카드"), ("2", "B 우리카드"), ("3", "C 우리카드"))
    got = asked("woori", lambda r: listing if r.source_id == "disclosure" else _woori_detail("1", "A", "1"))
    # 상세는 60분까지만 연다. 원문 받기 240분 제한에 걸리면 공시 묶음까지 버려진다
    assert [r.source_id for r in got] == ["disclosure", "detail-1"]


def test_woori_name_with_both_kinds_is_not_check():
    listing = _woori_list(("1", "한화생명 Family카드(신용/체크)"))
    assert [r.kind for r in read("woori", "disclosure", listing)] == [None]


@pytest.mark.parametrize(
    ("name", "personal"),
    [
        ("W_SCHOOL체크_안산국제비즈니스고등학교", True),
        ("카드의정석 Welfare+ 한영회계법인", True),
        ("공공기관 임직원 ESG 나눔카드", True),
        ("LOCA Biz카드", False),
        ("Biz 카드", False),
    ],
)
def test_corporate_words_spare_school_and_employee_cards(name, personal):
    assert collectable(IndexRow("woori", name), date(2026, 10, 5)) is personal
