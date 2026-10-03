"""카드사 상품공시실과 카드 목록 응답에서 색인 행을 뽑는다. 작업 008 설계 1절.

응답 하나를 받아 색인 행 목록을 돌려준다. 읽기 함수는 카드사와 응답 종류마다 하나다. 응답 종류 뒤에 `-credit`이나
`-check`를 붙이면 그 응답의 카드 종류로 쓴다. 신용과 체크를 따로 받는 카드사가 그렇다.
한 카드가 여러 응답에 나오면 `merge_rows`가 카드사 코드, 공시 문서 번호, 이름 순서로 짝지어 합친다.
보충용 응답의 행은 다른 행을 채우기만 하고, 짝이 없으면 색인에 넣지 않고 따로 돌려준다. 같은 카드가 두 번 색인되지 않게 한다.
조사 결과는 `docs/work/008-catalog-all-cards/survey.md`. 우리와 하나는 브라우저로 받은 표본이 생기면 더한다.
"""

from __future__ import annotations

import html
import json
import re
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import date
from urllib.parse import quote


@dataclass(frozen=True)
class IndexRow:
    issuer: str
    name: str
    code: str | None = None
    kind: str | None = None  # credit, check
    status: str = "on_sale"  # on_sale, discontinued
    launched_on: date | None = None
    discontinued_on: date | None = None
    pdf_urls: tuple[str, ...] = ()
    page_url: str | None = None
    image_url: str | None = None
    recommended: bool = False
    # 설명서 파일 목록을 따로 받아야 하는 카드사의 공시 문서 번호. 현대의 sqno
    detail_ref: str | None = None
    # 다른 응답의 행을 채우기만 하는 행. 롯데와 현대의 카드 목록, 현대 설명서 파일, 카카오뱅크 문서
    enrich_only: bool = False


_DATE = re.compile(r"(\d{4})\D+(\d{1,2})\D+(\d{1,2})")


def _date(text: str | None) -> date | None:
    m = _DATE.search(text or "")
    return date(*map(int, m.groups())) if m else None


def _json(content: bytes):
    return json.loads(content.decode("utf-8-sig").strip())


def _text(content: bytes) -> str:
    return re.sub(r"<!--.*?-->", "", content.decode("utf-8-sig", "replace"), flags=re.DOTALL)


def _clean(text: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", text)).strip()


def _abs(base: str, url: str) -> str:
    return "https:" + url if url.startswith("//") else base + url if url.startswith("/") else url


def _lotte_disclosure(content: bytes) -> list[IndexRow]:
    inner = json.loads(_json(content)["Content"])
    base = "https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/"
    return [
        IndexRow(
            "lotte",
            d["VT_CD_KND_NM"].strip(),
            status="discontinued" if d["ISU_E_YN"] == "Y" else "on_sale",
            pdf_urls=(base + d["OCY_FILE_NM"],) if d.get("OCY_FILE_NM") else (),
        )
        for d in inner["result"]["collection"][0]["docs"]
    ]


def _lotte_cards(content: bytes) -> list[IndexRow]:
    found = re.finditer(
        r"GoDet\('([^']+)'\).*?<img src=\"([^\"]+)\".*?<b class=\"tit\">(.*?)</b>", _json(content)["Content"], re.DOTALL
    )
    return [
        IndexRow(
            "lotte",
            _clean(name),
            code=code,
            page_url=f"https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC={code}",
            image_url=_abs("https://www.lottecard.co.kr", img),
            enrich_only=True,
        )
        for code, img, name in (m.groups() for m in found)
    ]


def _shinhan(content: bytes) -> list[IndexRow]:
    base = "https://www.shinhancard.com"
    return [
        IndexRow(
            "shinhan",
            c["cardProductEntryName"].strip(),
            code=c["cardProductCode"],
            kind={"0": "credit", "1": "check"}.get(c.get("cardType")),
            launched_on=_date(c.get("cardPdStartDate")),
            page_url=_abs(base, c["cardProductUrl"]) if c.get("cardProductUrl") else None,
            image_url=_abs(base, c["thumbnailImgUrl"]) if c.get("thumbnailImgUrl") else None,
        )
        for c in _json(content)["payload"]["cardInformationList"]
    ]


def _nh(content: bytes) -> list[IndexRow]:
    base = "https://card.nonghyup.com"
    return [
        IndexRow(
            "nh",
            _clean(c["cd_wrsnm"]),
            code=c["wrs_tup_c"],
            status="discontinued" if c.get("sel_yn") == "0" else "on_sale",
            page_url=f"{base}/servlet/IpCc2021R.act?CD_WRS_SQNO={c['cd_wrs_sqno']}",
            image_url=_abs(base, c["cd_img_urlnm"]) if c.get("cd_img_urlnm") else None,
        )
        for c in _json(content)["CARDLIST"]
    ]


def _kakaobank_card(group: dict, pdf_urls: tuple[str, ...] = (), enrich_only: bool = False) -> IndexRow:
    name = group["stpl_group_nm"].strip()
    return IndexRow(
        "kakaobank",
        name,
        code=str(group["stpl_group_no"]),
        kind="check" if "체크카드" in name else None,
        status="discontinued" if "판매종료" in name else "on_sale",
        pdf_urls=pdf_urls,
        enrich_only=enrich_only,
    )


def _kakaobank_groups(content: bytes) -> list[IndexRow]:
    # 상품공시 그룹 가운데 chnl_prgr_cd 03이 카드다. 나머지는 예금, 대출, 서비스다
    return [_kakaobank_card(g) for g in _json(content)["result"] if g.get("chnl_prgr_cd") == "03"]


def _kakaobank_docs(content: bytes) -> list[IndexRow]:
    group = _json(content)["result"]
    pdfs = tuple(
        f"https://og.kakaobank.io/view/{a['pdf_doc_file_id']}"
        for a in group["agreements"]
        if a.get("intg_doc_typ_lccd") == "04" and a.get("pdf_doc_file_id")
    )
    return [_kakaobank_card(group, pdfs, enrich_only=True)]


def _ibk(content: bytes) -> list[IndexRow]:
    out = []
    for chunk in _text(content).split("<tr")[1:]:
        m = re.search(
            r"detail\('(\d+)',\s*'(\d+)',\s*'(\d+)',\s*'(\d+)',\s*'[^']*',\s*'(\d+)'\);\">(.*?)</a>", chunk, re.DOTALL
        )
        if not m:
            continue
        line, group, team, product, code, name = m.groups()
        img = re.search(r"<dd class=\"thumb\"><img src=\"([^\"]+)\"", chunk)
        name = _clean(name)
        out.append(
            IndexRow(
                "ibk",
                name,
                code=code,
                kind="credit" if name.endswith("(신용)") else "check" if name.endswith("(체크)") else None,
                status="discontinued" if "ic_sell_stop2" in chunk else "on_sale",
                page_url="https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?"
                f"PDLN_CD={line}&PDGR_CD={group}&PDTM_CD={team}&PDCD={product}&pageId=CA01010000",
                image_url=_abs("https://www.ibk.co.kr", img.group(1)) if img else None,
            )
        )
    return out


def _kb(content: bytes) -> list[IndexRow]:
    out = []
    for chunk in _text(content).split("<tr")[1:]:
        code = re.search(r"goDetail\('(\w+)'", chunk)
        cells = re.findall(r"<td[^>]*>(.*?)</td>", chunk, re.DOTALL)
        if not code or len(cells) < 5:
            continue
        code = code.group(1)
        pdf = re.search(r"href=\"(https://[^\"]+\.pdf)\"", cells[1])
        ended = _date(cells[4])
        on_sale = ended is None
        out.append(
            IndexRow(
                "kb",
                _clean(cells[0]),
                code=code,
                status="on_sale" if on_sale else "discontinued",
                launched_on=_date(cells[3]),
                discontinued_on=ended,
                pdf_urls=(pdf.group(1),) if pdf else (),
                # 상품 페이지와 그림 주소 규칙은 판매 중 카드로만 확인했다
                page_url=f"https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode={code}"
                if on_sale
                else None,
                image_url=f"https://img1.kbcard.com/ST/img/cxc/kbcard/upload/img/product/{code}_img.png"
                if on_sale
                else None,
            )
        )
    return out


def _hyundai_manuals(content: bytes) -> list[IndexRow]:
    out = []
    for m in re.finditer(r"<p class=\"h4_m_lt\">(.*?)</p>(.*?)sqno=\"(\d+)\"", _text(content), re.DOTALL):
        name, body, sqno = m.groups()
        launched = re.search(r"상품출시일\s*:\s*([^<]+)", body)
        ended = _date((re.search(r"발급중단일\s*:\s*([^<]+)", body) or [None, None])[1])
        out.append(
            IndexRow(
                "hyundai",
                _clean(name),
                kind="credit",
                status="discontinued" if ended else "on_sale",
                launched_on=_date(launched.group(1)) if launched else None,
                discontinued_on=ended,
                detail_ref=sqno,
            )
        )
    return out


def _hyundai_files(content: bytes) -> list[IndexRow]:
    pdfs: dict[str, list[str]] = {}
    for f in _json(content)["bdy"]["result"]["cpuug2001DAO"]:
        if f.get("apndFileNm"):
            url = "https://www.hyundaicard.com/upload/card/" + quote(f["apndFileNm"])
            pdfs.setdefault(f["webPsnlBlbdSqno"], []).append(url)
    return [
        IndexRow("hyundai", "", detail_ref=sqno, pdf_urls=tuple(urls), enrich_only=True) for sqno, urls in pdfs.items()
    ]


def _hyundai_cards(content: bytes) -> list[IndexRow]:
    out = []
    for m in re.finditer(
        r"goCardDetail\('(\w+)'\).*?<img src=\"([^\"]+)\" alt=\"([^\"]*)\"", _text(content), re.DOTALL
    ):
        code, img, name = m.groups()
        # 두 카드만 다른 상세 주소를 쓴다. 카드 목록 페이지의 goCardDetail 함수에 적혀 있다
        page = "/cpc/cr/CPCCR0621_11.hc?cardflag=" if code in ("SPM", "TO") else "/cpc/cr/CPCCR0201_01.hc?cardWcd="
        out.append(
            IndexRow(
                "hyundai",
                _clean(name),
                code=code,
                kind="credit",
                page_url=f"https://www.hyundaicard.com{page}{code}",
                image_url=_abs("https://www.hyundaicard.com", img),
                # 설명서 목록이 색인이다. 사업자와 제휴 카드까지 다 있고 카드 목록에는 일부만 있다
                enrich_only=True,
            )
        )
    return out


class _Ref(str):
    """함수 인자 이름. 값을 다 읽은 뒤 인자 값으로 바꾼다."""


_NUMBER = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_NAME = re.compile(r"[A-Za-z_$][\w$]*")
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}


class _Js:
    """Nuxt가 페이지에 심는 자바스크립트 값 하나를 읽는다. 객체, 배열, 글자, 숫자, true, false, null, void 0, 인자 이름만 안다."""

    def __init__(self, text: str, at: int) -> None:
        self.s, self.i = text, at

    def skip(self) -> None:
        while self.s[self.i].isspace():
            self.i += 1

    def take(self, ch: str) -> None:
        self.skip()
        if self.s[self.i] != ch:
            raise ValueError(f"{self.i}번째 글자에 {ch!r}가 와야 한다: {self.s[self.i : self.i + 30]!r}")
        self.i += 1

    def value(self):
        self.skip()
        c = self.s[self.i]
        if c == "{":
            return self.items("}", keyed=True)
        if c == "[":
            return self.items("]", keyed=False)
        if c in "\"'":
            return self.string()
        if m := _NUMBER.match(self.s, self.i):
            self.i = m.end()
            text = m.group()
            return float(text) if any(x in text for x in ".eE") else int(text)
        m = _NAME.match(self.s, self.i)
        if not m:
            raise ValueError(f"{self.i}번째 글자를 읽지 못했다: {self.s[self.i : self.i + 30]!r}")
        self.i = m.end()
        word = m.group()
        if word == "void":
            self.value()
            return None
        if word == "new":
            # new Map([…]), new Set([…]), new Date(…). 2026-10-03 삼성 페이지에 new Map([])이 있었다
            self.skip()
            kind = _NAME.match(self.s, self.i)
            self.i = kind.end()
            self.skip()
            args = self.items(")", keyed=False)
            first = args[0] if args else None
            if kind.group() == "Map":
                return {k: v for k, v in (first or [])}
            if kind.group() == "Set":
                return list(first or [])
            return first
        if word == "Array" and self.s[self.i] == "(":
            self.i += 1
            size = self.value()
            self.take(")")
            return [None] * size
        return {"true": True, "false": False, "null": None, "undefined": None}.get(word, _Ref(word))

    def items(self, close: str, keyed: bool):
        self.i += 1
        out = {} if keyed else []
        self.skip()
        if self.s[self.i] == close:
            self.i += 1
            return out
        while True:
            if keyed:
                self.skip()
                if self.s[self.i] in "\"'":
                    key = self.string()
                else:
                    m = _NAME.match(self.s, self.i) or _NUMBER.match(self.s, self.i)
                    key, self.i = m.group(), m.end()
                self.take(":")
                out[key] = self.value()
            else:
                out.append(self.value())
            self.skip()
            self.i += 1
            if self.s[self.i - 1] == close:
                return out
            if self.s[self.i - 1] != ",":
                raise ValueError(f"{self.i - 1}번째 글자에 쉼표나 {close!r}가 와야 한다")

    def string(self) -> str:
        quote_ch, self.i, out = self.s[self.i], self.i + 1, []
        while (c := self.s[self.i]) != quote_ch:
            if c == "\\":
                e = self.s[self.i + 1]
                if e == "u":
                    out.append(chr(int(self.s[self.i + 2 : self.i + 6], 16)))
                    self.i += 6
                    continue
                if e == "x":
                    out.append(chr(int(self.s[self.i + 2 : self.i + 4], 16)))
                    self.i += 4
                    continue
                out.append(_ESCAPES.get(e, e))
                self.i += 2
                continue
            out.append(c)
            self.i += 1
        self.i += 1
        return "".join(out)


def _resolve(value, names: dict):
    if isinstance(value, _Ref):
        return names.get(value)
    if isinstance(value, dict):
        return {k: _resolve(v, names) for k, v in value.items()}
    if isinstance(value, list):
        return [_resolve(v, names) for v in value]
    return value


def nuxt_data(page: str) -> dict:
    """window.__NUXT__=(function(a,b,…){대입문;return {…}}(값들)) 를 풀어 Python 값으로 돌려준다. 삼성 추천 페이지가 쓴다.

    대입문은 여러 곳이 같은 값을 가리키게 하려고 Nuxt가 쓴다. i[0]={…}, f.bgdPcdList=e 모양이다.
    """
    m = re.search(r"window\.__NUXT__=\(function\(([^)]*)\)\{", page)
    if not m:
        raise ValueError("window.__NUXT__ 함수 호출을 찾지 못했다")
    params = [p.strip() for p in m.group(1).split(",") if p.strip()]
    js = _Js(page, m.end())
    assigns = []
    while True:
        js.skip()
        if page.startswith("return", js.i):
            js.i += len("return")
            body = js.value()
            break
        target = _NAME.match(page, js.i)
        js.i = target.end()
        path: list = []
        while page[js.i] in "[.":
            if page[js.i] == "[":
                js.i += 1
                path.append(js.value())
                js.take("]")
            else:
                key = _NAME.match(page, js.i + 1)
                path.append(key.group())
                js.i = key.end()
        js.take("=")
        assigns.append((target.group(), path, js.value()))
        js.skip()
        if page[js.i] == ";":
            js.i += 1
    js.take("}")
    js.skip()
    if page[js.i] != "(":
        raise ValueError("함수 호출의 인자 목록을 찾지 못했다")
    names = dict(zip(params, js.items(")", keyed=False)))
    for name, path, value in assigns:
        container = names[name]
        for key in path[:-1]:
            container = container[key]
        container[path[-1]] = _resolve(value, names)
    return _resolve(body, names)


def _samsung_recommend(content: bytes) -> list[IndexRow]:
    # 추천 탭마다 카드 목록이 있고 한 카드가 여러 탭에 나온다. 2026-10-03 탭 16개를 합쳐 판매 중 신용 개인카드 134장이었다
    props = nuxt_data(content.decode("utf-8-sig", "replace"))["data"][0]["hub"]["props"]
    seen: dict[str, IndexRow] = {}

    def walk(o) -> None:
        if isinstance(o, dict):
            code, name = o.get("bgdPcd"), o.get("cardTitle")
            if code and name and code not in seen:
                img = (o.get("imgInfo") or {}).get("pcImg1")
                seen[code] = IndexRow(
                    "samsung",
                    _clean(name),
                    code=code,
                    image_url=_abs("https://static11.samsungcard.com", img) if img else None,
                )
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(props)
    return list(seen.values())


READERS: dict[tuple[str, str], Callable[[bytes], list[IndexRow]]] = {
    ("lotte", "disclosure"): _lotte_disclosure,
    ("lotte", "cards"): _lotte_cards,
    ("shinhan", "cards"): _shinhan,
    ("nh", "cards"): _nh,
    ("kakaobank", "groups"): _kakaobank_groups,
    ("kakaobank", "docs"): _kakaobank_docs,
    ("ibk", "cards"): _ibk,
    ("kb", "disclosure"): _kb,
    ("hyundai", "manuals"): _hyundai_manuals,
    ("hyundai", "files"): _hyundai_files,
    ("hyundai", "cards"): _hyundai_cards,
    ("samsung", "recommend"): _samsung_recommend,
}


def read(issuer: str, source_id: str, content: bytes) -> list[IndexRow]:
    """응답 하나의 색인 행. source_id 뒤의 -credit, -check는 행에 카드 종류가 없을 때 채운다."""
    base, _, kind = source_id.partition("-")
    reader = READERS.get((issuer, base))
    if reader is None:
        raise KeyError(f"{issuer} {base}")
    rows = reader(content)
    return [replace(r, kind=r.kind or kind) for r in rows] if kind else rows


# 카드 목록은 짧은 이름, 공시 목록은 카드사 이름을 붙인 긴 이름을 쓴다. 긴 낱말부터 뺀다
_BRAND_WORDS = ("알파벳카드", "현대카드", "롯데카드", "카드")


def _name_key(name: str) -> str:
    """띄어쓰기, 대소문자, 문장 부호, 카드사 이름만 다른 이름은 같은 카드로 본다."""
    key = name.casefold()
    for word in _BRAND_WORDS:
        key = key.replace(word, "")
    return re.sub(r"[\W_]+", "", key)


def _same(a: IndexRow, b: IndexRow) -> bool:
    if a.issuer != b.issuer:
        return False
    if a.code and b.code:
        return a.code == b.code
    if a.detail_ref and b.detail_ref:
        return a.detail_ref == b.detail_ref
    # 색인 행끼리는 이름으로 합치지 않고, 판매 상태가 다른 행도 이름으로 짝짓지 않는다. 같은 이름의 옛 판이 발급 중단으로
    # 따로 남아 있다. 2026-10-03 현대의 "네이버"는 지금 파는 Edition3인데 옛 "네이버 현대카드"와 이름이 같았다
    if not (a.enrich_only or b.enrich_only) or a.status != b.status:
        return False
    return bool(a.name and b.name) and _name_key(a.name) == _name_key(b.name)


def _join(a: IndexRow, b: IndexRow) -> IndexRow:
    # 보충용 행이 먼저 와도 색인 행의 이름을 쓴다
    first, second = (b, a) if a.enrich_only and not b.enrich_only else (a, b)
    return IndexRow(
        a.issuer,
        first.name or second.name,
        code=first.code or second.code,
        kind=first.kind or second.kind,
        status="discontinued" if "discontinued" in (a.status, b.status) else "on_sale",
        launched_on=first.launched_on or second.launched_on,
        discontinued_on=first.discontinued_on or second.discontinued_on,
        pdf_urls=a.pdf_urls + tuple(u for u in b.pdf_urls if u not in a.pdf_urls),
        page_url=first.page_url or second.page_url,
        image_url=first.image_url or second.image_url,
        recommended=a.recommended or b.recommended,
        detail_ref=first.detail_ref or second.detail_ref,
        enrich_only=a.enrich_only and b.enrich_only,
    )


def merge_rows(rows: list[IndexRow]) -> tuple[list[IndexRow], list[IndexRow]]:
    """(색인 행, 짝을 못 찾은 보충용 행). 같은 카드의 행을 합치고 처음 나온 순서를 지킨다.

    ponytail: 모든 행끼리 비교한다. 카드사 하나에 행 수백 개라 충분하다. 수만 개가 되면 열쇠별 사전으로 바꾼다.
    """
    out: list[IndexRow] = []
    for r in rows:
        found = [n for n, o in enumerate(out) if _same(o, r)]
        # 여럿과 짝지어지면 같은 판매 상태의 행을 고른다. 판매 중 카드 목록이 같은 이름의 옛 판을 채우지 않게 한다
        i = next((n for n in found if out[n].status == r.status), found[0] if found else None)
        if i is None:
            out.append(r)
        else:
            out[i] = _join(out[i], r)
    return [r for r in out if not r.enrich_only], [r for r in out if r.enrich_only]
