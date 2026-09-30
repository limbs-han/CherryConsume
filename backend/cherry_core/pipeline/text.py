"""원문에서 글 뽑기, 본문 지문, 바뀐 줄. 설계 1절 2단계와 3단계."""

from __future__ import annotations

import codecs
import hashlib
import json
import re
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
