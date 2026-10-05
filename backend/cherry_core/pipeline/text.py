"""원문에서 글 뽑기, 본문 지문, 바뀐 줄. 설계 1절 2단계와 3단계."""

from __future__ import annotations

import codecs
import hashlib
import json
import re
from html import unescape
from html.parser import HTMLParser

_SPACE = re.compile(r"\s+")
_CHARSET = re.compile(r"charset=[\"']?([\w-]+)", re.IGNORECASE)
_BLOCK = {"p", "div", "br", "li", "tr", "table", "section", "article", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6"}
_SKIP = {"script", "style", "noscript", "template"}
# 받을 때마다 바뀌는 JSON 응답 칸. 남기면 원문이 그대로여도 지문이 매번 바뀐다. 신한카드 상품 API
_VOLATILE = {"responseTime"}


def lines(text: str) -> list[str]:
    """줄마다 공백을 하나로 줄이고 빈 줄은 뺀다. 줄바꿈과 공백만 다른 글은 같은 결과가 나온다."""
    return [s for s in (_SPACE.sub(" ", line).strip() for line in text.splitlines()) if s]


# 받을 때마다 바뀌는 조회수. 과제 9에서 하나 공지 본문의 "조회33118"을 봤다
_VIEWS = re.compile(r"조회\s*수?\s*:?\s*[\d,]+")
_DIGITS = re.compile(r"\d+")
# 새 글이나 새 카드가 올라왔는지만 보는 원문. KB 공지 목록은 행 끝 칸이 조회수라 숫자를 모두 가린다
_NUMBERLESS_KINDS = {"notice", "list"}


def _compared(text: str, kind: str | None) -> list[tuple[str, str]]:
    """(비교에 쓸 줄, 원래 줄). 공지와 목록은 숫자를 #으로 바꿔 비교하고, 상품 원문은 숫자까지 비교한다.

    이미 올라온 공지의 숫자만 나중에 바뀌면 놓친다. 공지는 올린 뒤 거의 고치지 않아 받아들인다.
    """
    out = []
    for line in lines(text):
        key = _VIEWS.sub("조회", line)
        if kind in _NUMBERLESS_KINDS:
            key = _DIGITS.sub("#", key)
        out.append((key, line))
    return out


def fingerprint(text: str, kind: str | None = None) -> str:
    """바뀐 원문을 가리는 지문. kind는 카드 파일 sources의 kind이고, 카드사 목록은 list다."""
    return hashlib.sha256("\n".join(k for k, _ in _compared(text, kind)).encode("utf-8")).hexdigest()


def changed_lines(old: str, new: str, kind: str | None = None) -> tuple[list[str], list[str]]:
    """(없어진 줄, 새로 생긴 줄). 자리만 옮긴 줄과 조회수만 바뀐 줄은 바뀐 것으로 보지 않는다."""
    old_lines, new_lines = _compared(old, kind), _compared(new, kind)
    old_keys, new_keys = {k for k, _ in old_lines}, {k for k, _ in new_lines}
    return [s for k, s in old_lines if k not in new_keys], [s for k, s in new_lines if k not in old_keys]


class _Text(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
        self.skip = 0
        self.cell = 0  # 표 칸 안인지. 칸 안에서는 블록 태그도 줄을 나누지 않아 한 행이 한 줄로 남는다

    def _block(self, tag: str) -> None:
        if tag in ("tr", "table"):
            # 닫는 td를 빼먹은 HTML도 행마다 새로 센다
            # ponytail: 칸 안에 표를 또 넣으면 바깥 행의 나머지가 줄로 나뉜다. 그런 페이지가 나오면 깊이를 쌓는다
            self.cell = 0
        self.parts.append(" " if self.cell else "\n")

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag in _SKIP:
            self.skip += 1
        elif tag in ("td", "th"):
            self.cell += 1
            self.parts.append(" | ")
        elif tag in _BLOCK:
            self._block(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag in _SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag in ("td", "th"):
            self.cell = max(0, self.cell - 1)
        elif tag in _BLOCK:
            self._block(tag)

    def handle_data(self, data: str) -> None:
        # HTML 원본의 줄바꿈은 공백과 같다. 줄은 블록 태그만 나눈다
        if not self.skip:
            self.parts.append(_SPACE.sub(" ", data))


def html_text(html: str) -> str:
    """HTML에서 글만 뽑는다. ai_parse_document는 HTML을 받지 않아 코드로 한다.

    블록 태그는 줄을 나누고, 표의 칸은 ' | '로 이어 한 줄이 표의 한 행이 되게 한다.
    """
    parser = _Text()
    parser.feed(html)
    parser.close()
    return "\n".join(s.removeprefix("| ") for s in lines("".join(parser.parts)))


# 본문이 아닌 영역. id나 class의 이름 하나가 이 낱말로 시작하고 바로 끝나거나 붙임표, 밑줄, 숫자, 대문자가 이어지면
# 그 안은 세지 않는다. header_wrap, gnbArea는 걸리고 card-header, unavailable처럼 낱말이 이름 가운데 든 것은 본문이다
_CHROME = re.compile(r"(?:^|\s)(?i:header|footer|gnb|lnb|nav|skip|quick|sitemap|familysite)(?=$|[\s\-_0-9A-Z])")
# 이름이 걸려도 영역으로 보지 않는 태그. 빈 태그와 끝 태그를 생략할 수 있는 태그는 끝 태그가 오지 않아 나머지 본문을 모두 건너뛰고,
# 페이지 전체를 감싸는 태그는 본문을 통째로 뺀다
_NOT_REGION = {
    *("img", "br", "hr", "input", "meta", "link", "source", "area", "wbr", "html", "body", "main"),
    *("li", "p", "dt", "dd", "tr", "td", "th", "option", "thead", "tbody", "tfoot"),
}
# 이미지 혜택 페이지의 기준. 본문 이미지가 이만큼 이상이고 본문 글자가 이만큼 미만이다. 작업 008 설계 4절
HEAVY_IMAGES, HEAVY_CHARS = 3, 2000


class _Body(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.outside: str | None = None  # 지금 건너뛰는 본문 밖 영역의 태그
        self.depth = 0
        self.skip = 0
        self.images = 0
        self.chars = 0

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if self.outside:
            self.depth += tag == self.outside
            return
        a = dict(attrs)
        names = f"{a.get('id') or ''} {a.get('class') or ''}"
        if tag in ("header", "footer", "nav") or (tag not in _NOT_REGION and _CHROME.search(names)):
            self.outside, self.depth = tag, 1
        elif tag in _SKIP:
            self.skip += 1
        elif tag == "img" and not self.skip:
            self.images += 1

    def handle_endtag(self, tag: str) -> None:
        if self.outside:
            if tag == self.outside:
                self.depth -= 1
                if self.depth == 0:
                    self.outside = None
            return
        if tag in _SKIP:
            self.skip = max(0, self.skip - 1)

    def handle_data(self, data: str) -> None:
        if not self.outside and not self.skip:
            self.chars += len(_SPACE.sub("", data))


def body_stats(html: str) -> tuple[int, int]:
    """(본문 이미지 수, 공백을 뺀 본문 글자 수). 머리말, 바닥글, 메뉴 영역은 세지 않는다. 작업 008 8단계.

    페이지 전체로 재면 메뉴와 바닥글만으로 수천 자라 이미지 혜택 페이지가 하나도 걸리지 않았다.
    """
    parser = _Body()
    parser.feed(html)
    parser.close()
    return parser.images, parser.chars


def image_heavy(html: str) -> bool:
    """혜택을 이미지로 넣은 페이지로 보이는지. 그런 페이지는 수집기가 화면을 찍고 글 뽑기가 그 사진을 해석한다."""
    images, chars = body_stats(html)
    return images >= HEAVY_IMAGES and chars < HEAVY_CHARS


def same_page_text(old: bytes, new: bytes) -> bool:
    """찍은 화면이 있는 두 HTML의 페이지 글이 같은지. 같으면 앞 사진의 해석 글을 다시 쓴다. 작업 008 설계 4절.

    사진 해석은 같은 화면도 할 때마다 글이 조금씩 달라 바뀌지 않은 페이지가 바뀐 원문으로 잡힌다.
    브라우저가 준 HTML은 받을 때마다 바이트가 달라 sha로는 막지 못한다. 글이 같고 이미지만 바뀌면 놓친다.
    """
    return fingerprint(document_text(old, "text/html")) == fingerprint(document_text(new, "text/html"))


# Docling 마크다운의 표 구분 줄. 칸마다 붙임표가 셋 이상이다. 칸이 모두 "-"인 행은 "해당 없음"이라 남긴다
_MD_RULE = re.compile(r"\|(?:\s*:?-{3,}:?\s*\|)+")
# Docling의 글을 믿지 않고 ai_parse_document에 맡기는 기준. 작업 008 설계 4절
MIN_CHARS_PER_PAGE = 200  # 공백을 뺀 글이 쪽당 평균 이보다 적으면 글자층이 없는 PDF다
# 앞표지일 수 있는 첫 두 쪽과 뒤표지일 수 있는 마지막 쪽 밖에서 이보다 적은 쪽은 그림으로 된 쪽이다
# 2026-10-05 첫 수집에서 현대 상품설명서는 뒤표지가 비고 목차와 간지가 서른 자쯤이라 50자로는 넷에 하나가 걸렸다
MIN_PAGE_CHARS = 20
COVER_PAGES = 2


def markdown_text(md: str) -> str:
    """Docling이 PDF에서 만든 마크다운의 글. 표 행은 html_text처럼 칸을 ' | '로 잇고 구분 줄, 그림 자리, 제목 표시는 뺀다.

    Docling이 바꿔 쓴 &gt; 같은 문자 참조와 \\_는 되돌린다.
    """
    out = []
    for line in md.splitlines():
        s = unescape(line.strip()).replace("\\_", "_")
        if s == "<!-- image -->" or _MD_RULE.fullmatch(s):
            continue
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if not any(cells):
                continue
            s = " | ".join(cells)
        out.append(s.lstrip("#"))
    return "\n".join(lines("\n".join(out)))


def docling_problem(pages: list[str]) -> str | None:
    """Docling이 쪽마다 낸 마크다운을 믿을 수 없는 까닭. 믿을 수 있으면 None이고, 까닭이 있으면 ai_parse_document에 맡긴다.

    글자층에 글자 정보가 빠진 PDF는 깨진 글자 U+FFFD가 나온다. 2026-10-05 롯데 상품설명서 두 장이 그랬다.
    OCR을 꺼서 그림으로 된 쪽은 글이 빈다. 표지 밖에 그런 쪽이 있으면 그 쪽의 혜택이 빠진다.
    """
    texts = [markdown_text(p) for p in pages]
    if any("\ufffd" in t for t in texts):
        return "글자 깨짐"
    chars = [len(_SPACE.sub("", t)) for t in texts]
    if sum(chars) < MIN_CHARS_PER_PAGE * max(len(pages), 1):
        return "글자층 없음"
    if any(c < MIN_PAGE_CHARS for c in chars[COVER_PAGES:-1]):
        return "빈 쪽"
    return None


def parsed_text(parsed: dict) -> str:
    """ai_parse_document 결과의 글. 표는 HTML로 오므로 html_text로 행을 살린다."""
    parts = []
    for element in parsed["document"]["elements"]:
        content = element.get("content") or ""
        parts.append(html_text(content) if element.get("type") == "table" else content)
    return "\n".join(lines("\n".join(parts)))


def _charset(content_type: str, head: bytes) -> str:
    """응답 머리의 charset, 없으면 HTML meta의 charset, 둘 다 없거나 모르는 이름이면 utf-8."""
    m = _CHARSET.search(content_type) or _CHARSET.search(head.decode("ascii", "ignore"))
    if m:
        try:
            return codecs.lookup(m.group(1)).name
        except LookupError:
            pass
    return "utf-8"


def document_text(content: bytes, content_type: str, parsed: dict | None = None) -> str:
    """받은 파일 하나의 글. PDF는 ai_parse_document 결과로, JSON은 들여쓰기로, 일반 글은 줄 그대로, HTML은 html_text로 뽑는다."""
    if content.startswith(b"%PDF-"):
        if parsed is None:
            raise ValueError("PDF는 ai_parse_document 결과가 있어야 글을 뽑는다")
        return parsed_text(parsed)
    text = content.decode(_charset(content_type, content[:2048]), "replace")
    if "json" in content_type:
        data = json.loads(text)
        if isinstance(data, dict):
            data = {k: v for k, v in data.items() if k not in _VOLATILE}
        return json.dumps(data, ensure_ascii=False, indent=1)
    if "text/plain" in content_type:
        return "\n".join(lines(text))
    return html_text(text)


def method_and_text(
    content: bytes, content_type: str, parsed: str | None, markdown: str | None = None
) -> tuple[str, str]:
    """(글을 뽑은 방법, 글). parsed는 ai_parse_document 결과의 JSON 글이다. 방법은 나중에 방법별로 글 품질을 보려고 남긴다.

    Spark 작업이 파일마다 부른다. 작업 007 설계 2절. PDF가 아닌데 parsed가 있으면 그 원문의 스크린샷을 해석한 것이라
    스크린샷의 글을 쓴다. 혜택을 이미지로 넣은 페이지다. 작업 008 설계 4절.
    """
    # 집 PC 수집기가 Docling으로 해석해 둔 PDF는 그 글을 쓴다. 작업 008 9단계
    if markdown and content.startswith(b"%PDF-"):
        return "docling", markdown_text(markdown)
    if parsed and not content.startswith(b"%PDF-"):
        try:
            shot = parsed_text(json.loads(parsed))
        except (ValueError, TypeError, KeyError, AttributeError):
            shot = ""
        if shot:
            return "screenshot", shot
        # 해석이 실패했거나 글이 비면 HTML 글을 쓴다. 빈 글을 쓰면 바뀐 원문으로 잡혀 카드가 비워진다
        parsed = None
    if content.startswith(b"%PDF-"):
        how = "ai_parse_document"
    elif "json" in content_type:
        how = "json"
    elif "text/plain" in content_type:
        how = "text"
    else:
        how = "html"
    return how, document_text(content, content_type, json.loads(parsed) if parsed else None)
