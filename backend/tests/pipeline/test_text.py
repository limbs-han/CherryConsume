"""원문에서 글 뽑기, 지문, 바뀐 줄. 설계 1절 2단계와 3단계."""

import pytest

from cherry_core.pipeline.text import changed_lines, document_text, fingerprint, html_text, lines


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


def test_euc_kr_page_from_meta_or_header():
    body = "<html><head><meta charset='euc-kr'></head><body><p>카페 할인</p></body></html>".encode("euc-kr")
    assert document_text(body, "text/html") == "카페 할인"
    assert document_text("<p>카페 할인</p>".encode("euc-kr"), "text/html; charset=EUC-KR") == "카페 할인"


def test_header_charset_wins_over_meta():
    # 브라우저가 돌려준 글은 UTF-8인데 meta에는 원래 페이지의 euc-kr이 남아 있다. 하나카드
    body = "<html><head><meta charset='euc-kr'></head><body><p>카페 할인</p></body></html>".encode()
    assert document_text(body, "text/html; charset=utf-8") == "카페 할인"


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
