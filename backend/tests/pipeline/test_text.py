"""원문에서 글 뽑기, 지문, 바뀐 줄. 설계 1절 2단계와 3단계."""

import pytest

from cherry_core.pipeline.text import changed_lines, document_text, fingerprint, html_text, lines, method_and_text


def test_lines_ignore_spacing_and_blank_lines():
    assert lines("  카페 10%   할인\n\n\t월 최대 1만원 \n") == ["카페 10% 할인", "월 최대 1만원"]


def test_same_text_with_different_spacing_has_same_fingerprint():
    assert fingerprint("카페 10%  할인\n\n월 최대 1만원") == fingerprint("카페 10% 할인\n월 최대 1만원 ")


def test_one_digit_changes_fingerprint():
    assert fingerprint("카페 10% 할인") != fingerprint("카페 5% 할인")


def test_changed_lines():
    assert changed_lines("a\nb\nc", "a\nc\nd") == (["b"], ["d"])


def test_moved_line_is_not_a_change():
    assert changed_lines("a\nb", "b\na") == ([], [])


def test_html_text_keeps_table_rows_and_drops_scripts():
    html = (
        "<html><head><style>p{}</style><script>var a = 1</script></head><body>"
        "<h1>혜택</h1><p>카페 10%  할인<br>월 최대 1만원</p>"
        "<table><tr><th>구분</th><th>할인</th></tr><tr><td>카페</td><td>10%</td></tr></table>"
        "</body></html>"
    )
    assert html_text(html) == "혜택\n카페 10% 할인\n월 최대 1만원\n구분 | 할인\n카페 | 10%"


def test_table_row_stays_one_line_in_real_html():
    # 카드사 페이지는 칸 사이에 줄바꿈이 있고 칸 안에 p와 br을 쓴다. 롯데, 하나, 우리. 과제 10에서 찾았다
    html = "<table>\n<tr>\n  <td>카페</td>\n  <td>\n    10%\n  </td>\n</tr>\n<tr><td><p>배달</p><p>커피</p></td><td>5%<br>월 1만원</td></tr>\n</table>"
    assert html_text(html) == "카페 | 10%\n배달 커피 | 5% 월 1만원"


def test_table_row_without_closing_cells():
    assert html_text("<table><tr><td>카페<td>10%<tr><td>배달<td>5%</table><p>끝</p>") == "카페 | 10%\n배달 | 5%\n끝"


def test_euc_kr_page_from_meta_or_header():
    body = "<html><head><meta charset='euc-kr'></head><body><p>카페 할인</p></body></html>".encode("euc-kr")
    assert document_text(body, "text/html") == "카페 할인"
    assert document_text("<p>카페 할인</p>".encode("euc-kr"), "text/html; charset=EUC-KR") == "카페 할인"


def test_header_charset_wins_over_meta():
    # 브라우저가 돌려준 글은 UTF-8인데 meta에는 원래 페이지의 euc-kr이 남아 있다. 하나카드
    body = "<html><head><meta charset='euc-kr'></head><body><p>카페 할인</p></body></html>".encode()
    assert document_text(body, "text/html; charset=utf-8") == "카페 할인"


def test_plain_text_keeps_its_lines():
    # 카카오뱅크 상품안내장은 text/plain으로 온다. HTML처럼 읽으면 줄바꿈이 공백이 된다
    body = "상품 개요   • 연회비 : 없음\n\n  • 브랜드 : 국내전용".encode()
    assert document_text(body, "text/plain; charset=utf-8") == "상품 개요 • 연회비 : 없음\n• 브랜드 : 국내전용"


def test_json_is_indented_text():
    assert document_text('{"a": "카드"}'.encode(), "application/json") == '{\n "a": "카드"\n}'


def test_json_response_time_is_not_text():
    # 신한카드 상품 API는 받을 때마다 responseTime이 바뀐다. 지문이 매번 달라지지 않게 뺀다
    a = document_text(b'{"responseTime": "2026-09-30 12:47:07", "payload": {"a": 1}}', "application/json")
    b = document_text(b'{"responseTime": "2026-09-30 12:55:49", "payload": {"a": 1}}', "application/json")
    assert a == b == '{\n "payload": {\n  "a": 1\n }\n}'


def test_pdf_uses_parse_result_and_keeps_table_rows():
    parsed = {
        "document": {
            "elements": [
                {"type": "title", "content": "혜택 안내"},
                {"type": "table", "content": "<table><tr><td>카페</td><td>10%</td></tr></table>"},
            ]
        }
    }
    assert document_text(b"%PDF-1.7 ...", "application/pdf", parsed) == "혜택 안내\n카페 | 10%"
    with pytest.raises(ValueError, match="ai_parse_document"):
        document_text(b"%PDF-1.7 ...", "application/pdf")


def test_method_and_text_for_each_kind_of_file():
    # Spark 작업이 파일마다 부른다. PDF의 해석 결과는 표에서 JSON 글로 온다. 작업 007 설계 2절
    parsed = '{"document": {"elements": [{"type": "title", "content": "혜택 안내"}]}}'
    assert method_and_text(b"%PDF-1.7 ...", "application/pdf", parsed) == ("ai_parse_document", "혜택 안내")
    assert method_and_text('{"a": "카드"}'.encode(), "application/json", None) == ("json", '{\n "a": "카드"\n}')
    assert method_and_text("카페\n 할인".encode(), "text/plain", None) == ("text", "카페\n할인")
    assert method_and_text("<p>카페</p><p>할인</p>".encode(), "text/html", None) == ("html", "카페\n할인")


def test_view_count_is_not_a_change():
    # 과제 9에서 하나 공지 본문의 조회수가 받을 때마다 바뀌었다
    old, new = "혜택 변경 안내\n등록일2025.07.01 조회33118", "혜택 변경 안내\n등록일2025.07.01 조회33119"
    assert fingerprint(old, "notice") == fingerprint(new, "notice")
    assert fingerprint(old, "product_page") == fingerprint(new, "product_page")
    assert changed_lines(old, new, "product_page") == ([], [])


def test_notice_and_list_compare_without_numbers():
    # KB 공지 목록은 표 행 끝 칸이 조회수다. 공지와 목록은 새 글이 올라왔는지만 본다
    old = "공지 | 홈페이지 오류 시 조치방법 안내 | 2021.12.20 | 18309"
    new = "공지 | 홈페이지 오류 시 조치방법 안내 | 2021.12.20 | 18310"
    assert fingerprint(old, "notice") == fingerprint(new, "notice")
    added = new + "\n공지 | 부가서비스 변경 안내 | 2026.10.01 | 3"
    assert changed_lines(old, added, "notice") == ([], ["공지 | 부가서비스 변경 안내 | 2026.10.01 | 3"])


def test_product_page_numbers_still_count():
    assert fingerprint("카페 10% 할인", "product_page") != fingerprint("카페 5% 할인", "product_page")
    assert changed_lines("카페 10% 할인", "카페 5% 할인", "product_page") == (["카페 10% 할인"], ["카페 5% 할인"])
