"""카드사 상품공시실과 카드 목록 응답에서 색인 행 뽑기. 작업 008 설계 1절.

표본은 2026-10-03 받은 응답에서 몇 행만 자른 것이다. 농협 표본은 발급 종료 카드가 없어 둘째 카드의 sel_yn만 0으로 바꿨다.
"""

from datetime import date
from pathlib import Path

import pytest

from cherry_core.pipeline.disclosure import IndexRow, merge_rows, nuxt_data, read

FIXTURES = Path(__file__).parent / "fixtures" / "disclosure"


def rows(issuer: str, source_id: str, name: str) -> list[IndexRow]:
    return read(issuer, source_id, (FIXTURES / name).read_bytes())


def test_lotte_disclosure_list_has_pdf_and_issue_end():
    got = rows("lotte", "disclosure", "lotte_disclosure.json")
    pdf = "https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/"
    assert got == [
        IndexRow("lotte", "웅진씽크빅 롯데카드", pdf_urls=(pdf + "2017-A00031_20261002_10011.pdf",)),
        IndexRow("lotte", "LOCA CLASSIC 롯데마트", pdf_urls=(pdf + "2023-A00007_20260930_10002.pdf",)),
        IndexRow("lotte", "DC플러스 카드", status="discontinued", pdf_urls=(pdf + "2009-A00024_20261001_10011.pdf",)),
    ]


def test_lotte_card_list_has_code_page_and_image():
    got = rows("lotte", "cards-credit", "lotte_cards.json")
    assert got[0] == IndexRow(
        "lotte",
        "롯데마트&MAXX 카드",
        code="P14312-A14312",
        kind="credit",
        page_url="https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P14312-A14312",
        image_url="https://image.lottecard.co.kr/UploadFiles/ecenterPath/cdInfo/ecenterCdInfoP14312-A14312_nm1_v.png",
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
            image_url="https://www.shinhancard.com/pconts/static/images/card/plate/POKE1M_E5_v_f_s.webp",
        ),
        IndexRow(
            "shinhan",
            "SOL LINK 신한카드 Point Plan 체크",
            code="POBE2Z",
            kind="check",
            launched_on=date(2026, 8, 7),
            page_url="https://www.shinhancard.com/pconts/html/card/apply/check/2014281_2206.html",
            image_url="https://www.shinhancard.com/pconts/static/images/card/plate/POBE2Z_00_h_f_s.webp",
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
            image_url="https://card.nonghyup.com/content/imgs/shopmall/pro_img/card/F10802.png",
        ),
        IndexRow(
            "nh",
            "zgm 러닝",
            code="F10834",
            kind="credit",
            status="discontinued",
            page_url="https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010629",
            image_url="https://card.nonghyup.com/content/imgs/shopmall/pro_img/card/F10834.png",
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
            image_url="https://www.ibk.co.kr/fup/finemall/card/2020120114211440146444480710591.png",
        ),
        IndexRow(
            "ibk",
            "마일앤조이카드(대한항공)",
            code="12113130001",
            status="discontinued",
            page_url="https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=313&PDCD=0001&pageId=CA01010000",
            image_url="https://www.ibk.co.kr/fup/finemall/card/202504101515277657479331385623.png",
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
            image_url="https://img1.kbcard.com/ST/img/cxc/kbcard/upload/img/product/04587_img.png",
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
        image_url="https://img.hyundaicard.com/img/com/card/card_TBE4_h.png",
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
    assert rows("samsung", "recommend-credit", "samsung_recommend.html") == [
        IndexRow(
            "samsung",
            "모니모페이카드",
            code="AAP1918",
            kind="credit",
            image_url="https://static11.samsungcard.com/wcms/home/scard/image/personal/b_AAP1918.png",
        ),
        IndexRow(
            "samsung",
            "삼성카드 taptap O",
            code="AAP1483",
            kind="credit",
            image_url="https://static11.samsungcard.com/wcms/home/scard/image/personal/b_AAP1483.png",
        ),
    ]


def test_unknown_issuer_or_source_is_an_error():
    with pytest.raises(KeyError, match="nobody cards"):
        read("nobody", "cards", b"{}")


def test_merge_by_code_then_detail_ref_then_name():
    disclosure = [
        IndexRow("lotte", "LOCA 365 카드", status="discontinued", pdf_urls=("https://p/1.pdf",)),
        IndexRow("lotte", "디지로카 London", pdf_urls=("https://p/2.pdf",)),
    ]
    cards = [
        IndexRow("lotte", "디지로카 london", code="C1", kind="credit", image_url="https://i/1.png", enrich_only=True)
    ]
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
            image_url="https://i/1.png",
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
