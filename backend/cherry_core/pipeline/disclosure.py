"""카드사 상품공시실과 카드 목록 응답에서 색인 행을 뽑는다. 작업 008 설계 1절.

응답 하나를 받아 색인 행 목록을 돌려준다. 읽기 함수는 카드사와 응답 종류마다 하나다. 응답 종류 뒤에 `-credit`이나
`-check`를 붙이면 그 응답의 카드 종류로 쓴다. 신용과 체크를 따로 받는 카드사가 그렇다. `-p2`는 쪽 번호다.
받기 함수 `PLANS`는 카드사마다 하나이고 받을 응답을 차례로 요청한다. 첫 쪽에서 쪽 수를 읽어 나머지 쪽을 받는다.
한 카드가 여러 응답에 나오면 `merge_rows`가 카드사 코드, 공시 문서 번호, 이름 순서로 짝지어 합친다.
보충용 응답의 행은 다른 행을 채우기만 하고, 짝이 없으면 색인에 넣지 않고 따로 돌려준다. 같은 카드가 두 번 색인되지 않게 한다.
조사 결과는 `docs/work/008-catalog-all-cards/survey.md`. 우리는 화면 스크립트가 요청을 암호화해 브라우저로 받는다.
"""

from __future__ import annotations

import hashlib
import html
import json
import re
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from datetime import date, timedelta
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
    recommended: bool = False
    # 설명서 파일 목록을 따로 받아야 하는 카드사의 공시 문서 번호. 현대의 sqno
    detail_ref: str | None = None
    # 다른 응답의 행을 채우기만 하는 행. 롯데와 현대의 카드 목록, 현대 설명서 파일, 카카오뱅크 문서
    enrich_only: bool = False
    # 이 행이 나온 원문 경로. 색인 단계가 채운다. 같은 카드인지 가릴 때는 보지 않는다
    source_path: str | None = field(default=None, compare=False)


_DATE = re.compile(r"(\d{4})\D+(\d{1,2})\D+(\d{1,2})")


def _date(text: str | None) -> date | None:
    """글에서 날짜를 읽는다. 9999년은 날짜 없음이다. KB가 발급중단일 칸에 9999.12.31을 중단 없음으로 적는다."""
    m = _DATE.search(text or "")
    if not m or m.group(1) == "9999":
        return None
    return date(*map(int, m.groups()))


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
            # 공시 문서 번호. 카드 코드가 없어 색인 열쇠로 쓴다
            detail_ref=d["DOCID"],
        )
        for d in inner["result"]["collection"][0]["docs"]
    ]


def _lotte_cards(content: bytes) -> list[IndexRow]:
    found = re.finditer(r"GoDet\('([^']+)'\).*?<b class=\"tit\">(.*?)</b>", _json(content)["Content"], re.DOTALL)
    return [
        IndexRow(
            "lotte",
            _clean(name),
            code=code,
            page_url=f"https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC={code}",
            enrich_only=True,
        )
        for code, name in (m.groups() for m in found)
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
                # 상품 페이지 주소 규칙은 판매 중 카드로만 확인했다
                page_url=f"https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode={code}"
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
        name = _clean(name)
        # 신용카드 설명서 목록이지만 체크카드와 하이브리드도 있다. 하이브리드는 체크에 소액 신용이 붙어 정하지 않는다
        upper = name.upper()
        kind = "check" if "CHECK" in upper or "체크" in name else None if "HYBRID" in upper else "credit"
        out.append(
            IndexRow(
                "hyundai",
                name,
                kind=kind,
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
    for m in re.finditer(r"goCardDetail\('(\w+)'\).*?<img src=\"[^\"]+\" alt=\"([^\"]*)\"", _text(content), re.DOTALL):
        code, name = m.groups()
        # 두 카드만 다른 상세 주소를 쓴다. 카드 목록 페이지의 goCardDetail 함수에 적혀 있다
        page = "/cpc/cr/CPCCR0621_11.hc?cardflag=" if code in ("SPM", "TO") else "/cpc/cr/CPCCR0201_01.hc?cardWcd="
        out.append(
            IndexRow(
                "hyundai",
                _clean(name),
                code=code,
                kind="credit",
                page_url=f"https://www.hyundaicard.com{page}{code}",
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


_SAMSUNG_PAGE = "https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code="


def _samsung_recommend(content: bytes) -> list[IndexRow]:
    # 추천 탭마다 카드 목록이 있고 한 카드가 여러 탭에 나온다. 2026-10-03 탭 16개를 합쳐 판매 중 신용 개인카드 134장이었다
    props = nuxt_data(content.decode("utf-8-sig", "replace"))["data"][0]["hub"]["props"]
    seen: dict[str, IndexRow] = {}

    def walk(o) -> None:
        if isinstance(o, dict):
            code, name = o.get("bgdPcd"), o.get("cardTitle")
            if code and name and code not in seen:
                seen[code] = IndexRow("samsung", _clean(name), code=code, page_url=_SAMSUNG_PAGE + code)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(props)
    return list(seen.values())


def _samsung_check(content: bytes) -> list[IndexRow]:
    # 체크카드 화면은 추천 탭 없이 data[0].pdList 하나에 판매 중 카드가 모두 있다. 2026-10-04 16장
    return [
        IndexRow(
            "samsung", _clean(c["cardTitle"]), code=c["bgdPcd"], kind="check", page_url=_SAMSUNG_PAGE + c["bgdPcd"]
        )
        for c in nuxt_data(content.decode("utf-8-sig", "replace"))["data"][0]["pdList"]
        if c.get("bgdPcd") and c.get("cardTitle")
    ]


def _samsung_terms(content: bytes) -> list[IndexRow]:
    """신용카드 상품약관 공시 게시판. 글마다 카드 코드와 이용안내장 PDF가 있다. 판매 상태는 없어 보충용이다."""
    out = []
    for post in _json(content)["blbdInqrRsList"]:
        pdfs = tuple(
            f"https://www.samsungcard.com/filedownload.do?grpNo={f['apnFileGrpNoE']}&sn={f['apnFileSn']}"
            for f in post.get("uploadFileList") or []
            if f.get("apnFileNm", "").lower().endswith(".pdf")
        )
        out.append(
            IndexRow("samsung", _clean(post["bltnbmTitNm"]), code=post["bgdAlncPdC"], pdf_urls=pdfs, enrich_only=True)
        )
    return out


def _woori(content: bytes) -> list[IndexRow]:
    # 상품공시실 약관 탭의 개인 카드. issuAt이 N이면 화면에 발급중지로 그리고 issuDt가 발급중단일이다
    # 신용과 체크 구분 칸이 없어 이름에 체크가 있을 때만 체크로 둔다
    out = []
    for c in _json(content)["mainDataList"]["cct11PrdntcAgrmMainVo"]:
        if not c.get("code"):
            continue  # 선불카드, ID/RF카드처럼 코드 없는 묶음 행이다
        name, stopped = _clean(c["codeName"]), c.get("issuAt") == "N"
        out.append(
            IndexRow(
                "woori",
                name,
                code=c["code"],
                kind="check" if "체크" in name or "CHECK" in name.upper() else None,
                status="discontinued" if stopped else "on_sale",
                discontinued_on=_date(c.get("issuDt")) if stopped else None,
                page_url=f"https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd={c['code']}",
            )
        )
    return out


def _hana_json(content: bytes):
    # 하나카드 응답은 EUC-KR이고 앞에 줄바꿈이 붙는다
    return json.loads(content.decode("cp949").strip())


def _hana_cards(content: bytes) -> list[IndexRow]:
    # 카드 한눈에 보기의 분류 하나. 지금 파는 카드만 나오고 판매 상태 칸은 없다
    out = []
    for cards in _hana_json(content)["dataMap"]["CARD_LIST"].values():
        for c in cards:
            out.append(
                IndexRow(
                    "hana",
                    _clean(c["CD_NM"]),
                    code=c["CD_PD_SEQ"],
                    page_url=f"https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ={c['CD_PD_SEQ']}",
                )
            )
    return out


# 카드다모아의 카드사 이름. 비씨카드는 카탈로그에 없어 뺀다
_DAMOA_ISSUERS = {
    "KB국민카드": "kb",
    "롯데카드": "lotte",
    "삼성카드": "samsung",
    "신한카드": "shinhan",
    "우리카드": "woori",
    "하나카드": "hana",
    "현대카드": "hyundai",
    "NH농협카드": "nh",
}


def _carddamoa(content: bytes) -> list[IndexRow]:
    """여신금융협회 카드다모아의 카드사 추천 카드. 다른 응답의 행에 추천 표시만 더하는 보충용이다."""
    return [
        IndexRow(
            # 모르는 카드사 이름은 짝이 없어 색인 단계의 "추천 짝 없음"에 찍힌다. 이름 표기가 바뀐 것을 알 수 있다
            _DAMOA_ISSUERS.get(c["companyNm"], f"?{c['companyNm']}"),
            _clean(c["itemName"]),
            page_url=c.get("itemLink") or None,
            recommended=True,
            enrich_only=True,
        )
        for c in _json(content)["resultList"]
        if c.get("companyNm") != "비씨카드"
    ]


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
    ("samsung", "check"): _samsung_check,
    ("samsung", "terms"): _samsung_terms,
    ("woori", "disclosure"): _woori,
    ("hana", "categories"): lambda content: [],
    ("hana", "cards"): _hana_cards,
    ("carddamoa", "recommend"): _carddamoa,
}


# 카드가 없어도 되는 응답. 분류 목록과 보충용 목록이다. 롯데 프리미엄 목록은 2026-10-04 비어 있었다
MAY_BE_EMPTY = {
    ("hana", "categories"),
    ("hyundai", "files"),
    ("hyundai", "cards"),
    ("lotte", "cards"),
    ("samsung", "terms"),
}


def must_have_rows(issuer: str, source_id: str) -> bool:
    """이 응답에서 카드가 0장이면 점검 화면이나 바뀐 응답이다. 그대로 쓰면 그 목록의 카드가 단종으로 보인다."""
    return (issuer, source_id.split("-")[0]) not in MAY_BE_EMPTY


def read(issuer: str, source_id: str, content: bytes) -> list[IndexRow]:
    """응답 하나의 색인 행. source_id의 -credit, -check는 행에 카드 종류가 없을 때 채우고, 쪽 번호와 문서 번호는 버린다."""
    base, *rest = source_id.split("-")
    kind = next((p for p in rest if p in ("credit", "check")), None)
    reader = READERS.get((issuer, base))
    if reader is None:
        raise KeyError(f"{issuer} {base}")
    rows = reader(content)
    return [replace(r, kind=r.kind or kind) for r in rows] if kind else rows


@dataclass(frozen=True)
class Request:
    """공시 응답 하나를 받는 요청. form이 있으면 폼 POST, json이 있으면 JSON 본문 POST다.

    capture가 있으면 브라우저로 url을 열고, 주소에 capture가 든 화면 요청의 응답을 돌려준다. script가 있으면 첫 응답 뒤에
    그 스크립트를 화면에서 돌리고 다음 응답을 돌려준다. 화면 스크립트가 요청을 암호화하는 우리카드가 쓴다.
    """

    source_id: str
    url: str
    form: dict[str, str] | None = None
    json: dict | None = None
    capture: str | None = None
    script: str | None = None


Fetch = Callable[[Request], bytes]
# 단종된 지 이만큼 지난 카드는 색인에만 두고 원문을 받지 않는다. 설계 1절
COLLECT_YEARS = 3


def collectable(row: IndexRow, today: date) -> bool:
    """판매 중이거나 단종된 지 3년이 안 된 카드. 단종일을 모르는 단종 카드는 받는다."""
    if row.status == "on_sale" or row.discontinued_on is None:
        return True
    return row.discontinued_on > today - timedelta(days=round(365.25 * COLLECT_YEARS))


def _pages(total: str | int, size: int) -> int:
    # 총 0건은 점검 화면이나 바뀐 응답이다. 빈 목록으로 받으면 그 카드사 카드가 모두 단종으로 보인다
    if int(total) <= 0:
        raise ValueError("목록 총수가 0이다")
    return -(-int(total) // size)


def _paged(fetch: Fetch, request_for: Callable[[int], Request], last_page: Callable[[bytes], int]) -> None:
    """첫 쪽에서 마지막 쪽 번호를 읽고 나머지 쪽을 받는다. 쪽 수를 못 읽으면 오류로 멈춰 반쪽 색인을 막는다."""
    last = last_page(fetch(request_for(1)))
    for n in range(2, last + 1):
        fetch(request_for(n))


def _found(pattern: str, content: bytes) -> str:
    m = re.search(pattern, _text(content))
    if not m:
        raise ValueError(f"응답에서 {pattern!r}를 찾지 못했다")
    return m.group(1)


def _kb_plan(fetch: Fetch, today: date) -> None:
    url = "https://card.kbcard.com/SVC/DVIEW/HSHMCXCRSZZC0002"
    # 금융약관의 개인신용 0, 개인체크 1. 기업 탭은 개인이 쓰는 앱이라 받지 않는다. 한 쪽 10건
    for code, kind in (("0", "credit"), ("1", "check")):
        _paged(
            fetch,
            lambda n, code=code, kind=kind: Request(
                f"disclosure-{kind}-p{n}",
                url,
                form={"카드분류코드": code, "카드검색그룹코드": "", "pageCount": str(n), "카드명": ""},
            ),
            lambda body: _pages(_found(r'class="totalNum">총<strong>(\d+)', body), 10),
        )


def _ibk_plan(fetch: Fetch, today: date) -> None:
    url = "https://www.ibk.co.kr/cardbiz/listBizNew.ibk"
    # 전체 CA01010000에는 판매 중지와 기업 카드까지 다 있다. 이름에 신용, 체크가 없는 카드가 많아 신용 CA01020000과
    # 체크 CA01030000 탭도 받아 카드 코드로 합친다. CardSaleYn A는 판매 중지까지다. 한 쪽 10장
    for page_id, suffix in (("CA01010000", ""), ("CA01020000", "-credit"), ("CA01030000", "-check")):
        _paged(
            fetch,
            lambda n, page_id=page_id, suffix=suffix: Request(
                f"cards{suffix}-p{n}", url, form={"pageId": page_id, "pageNum": str(n), "CardSaleYn": "A"}
            ),
            lambda body: _pages(_found(r'class="f_count">(\d+)<', body), 10),
        )


def _nh_plan(fetch: Fetch, today: date) -> None:
    url = "https://card.nonghyup.com/servlet/IpCc1210I.jct"
    # 전체 목록에는 신용과 체크 구분이 없어 체크 목록을 따로 받아 카드 코드로 합친다
    for gubun, suffix in (("", ""), ("IPCC0106", "-check")):
        _paged(
            fetch,
            lambda n, gubun=gubun, suffix=suffix: Request(
                f"cards{suffix}-p{n}", url, form={"pageNum": str(n), "cardGubun": gubun}
            ),
            lambda body: int(_json(body)["totalPage"]),
        )


def _shinhan_plan(fetch: Fetch, today: date) -> None:
    api = "https://shapi.shinhancard.com/card-apply/search/v1.0"
    # 고정 목록은 신용과 체크가 따로다. 2026-10-04 고정 목록에 없는 "신한카드 처음"이 전체 목록에만 있었다.
    # 전체 목록은 listID와 상관없이 신용과 체크가 섞인 74장이다. 셋을 받아 카드 코드로 합친다. pageSize를 키워도 8장씩 온다
    lists = (
        ("searchPagingFixedCardProductList", "202001020012", "-credit"),
        ("searchPagingFixedCardProductList", "202001020001", "-check"),
        ("searchPagingCardProductList", "202001020012", "-all"),
    )
    for path, list_id, suffix in lists:
        _paged(
            fetch,
            lambda n, path=path, list_id=list_id, suffix=suffix: Request(
                f"cards{suffix}-p{n}", f"{api}/{path}?listID={list_id}&pageSize=8&index={n}"
            ),
            lambda body: int(_json(body)["payload"]["totalPage"]),
        )


def _kakaobank_plan(fetch: Fetch, today: date) -> None:
    api = "https://www.kakaobank.com/api/v1/docs/app"
    groups = fetch(Request("groups", f"{api}/productGroupList"))
    for row in _kakaobank_groups(groups):
        fetch(Request(f"docs-{row.code}", f"{api}/{row.code}?hmpg_yn=Y"))


def _hyundai_plan(fetch: Fetch, today: date) -> None:
    base = "https://www.hyundaicard.com"
    manuals = fetch(Request("manuals", f"{base}/cpu/ug/CPUUG2001_08.hc"))
    fetch(Request("cards", f"{base}/cpc/ma/CPCMA0101_01.hc"))
    # 설명서 PDF 주소는 공시 문서마다 한 번 더 물어야 한다. 원문을 받을 카드만 묻는다
    for row in _hyundai_manuals(manuals):
        if collectable(row, today):
            fetch(
                Request(f"files-{row.detail_ref}", f"{base}/cpu/ug/apiCPUUG2001_0404.hc", form={"sqno": row.detail_ref})
            )


def _lotte_plan(fetch: Fetch, today: date) -> None:
    base = "https://www.lottecard.co.kr/app"
    # 공시 목록은 500건씩 나눠 받으면 쪽 사이 순서가 흔들려 겹치고 빠진다. 2026-10-04 531건 가운데 21건이 겹치고 21건이 빠졌다.
    # 한 번에 모두 묻고 총수만큼 왔는지 본다
    body = fetch(
        Request(
            "disclosure",
            f"{base}/LPSCHAA_V100.lc",
            form={"collection": "disclosure", "listcount": "2000", "startcount": "0", "query": ""},
        )
    )
    result = json.loads(_json(body)["Content"])["result"]["collection"][0]
    if len(result["docs"]) < int(result["totalcount"]):
        raise ValueError(f"롯데 공시 {result['totalcount']}건 가운데 {len(result['docs'])}건만 왔다")
    # 판매 중 카드의 코드와 상품 페이지. 신용은 일반 A100, 제휴 A101, 프리미엄 A102, 체크는 일반 A100, 제휴 A101이다.
    # 한 쪽 9장이고 totalRowCnt가 쪽 수다
    lists = (
        ("LPCDADA_A100", "credit"),
        ("LPCDADA_A101", "credit"),
        ("LPCDADA_A102", "credit"),
        ("LPCDAEA_A100", "check"),
        ("LPCDAEA_A101", "check"),
    )
    for path, kind in lists:
        _paged(
            fetch,
            lambda n, path=path, kind=kind: Request(
                f"cards-{kind}-{path[-4:]}-p{n}", f"{base}/{path}.lc", form={"cond": "1", "pageNo": str(n)}
            ),
            lambda body: int(_json(body)["Param"]["totalRowCnt"]),
        )


def _samsung_plan(fetch: Fetch, today: date) -> None:
    base = "https://www.samsungcard.com"
    # 추천 탭들이 판매 중 신용 개인카드이고 체크카드는 따로다. 사업자와 기업 카드는 개인이 쓰는 앱이라 받지 않는다
    fetch(Request("recommend-credit", f"{base}/home/card/cardinfo/PGHPPDCCardCardinfoRecommendPC001"))
    fetch(Request("check", f"{base}/home/card/cardinfo/PGHPPCCCardCardinfoCheckcard001"))
    # 이용안내장 PDF는 상품약관 공시 게시판에 있다. 한 번에 100건까지 준다. 600건을 물으면 일시 장애라고 답한다
    _paged(
        fetch,
        lambda n: Request(
            f"terms-p{n}",
            f"{base}/frontservice/SHPPCC0247S01",
            json={
                "cndt": {
                    "no1PgeSize": "100",
                    "pgeNo": str(n),
                    "itgBlbdChnlDvC": "01",
                    "itgBlbdTpDvC": "19",
                    "aryCriCn": "sysFstRgTs",
                    "aryDvCn": "DESC",
                }
            },
        ),
        lambda body: _pages(_json(body)["totInqrCt"], 100),
    )


def _woori_plan(fetch: Fetch, today: date) -> None:
    # 화면이 처음 10건을 부른 뒤 쪽 크기를 키워 다시 부르면 개인 카드 전부가 한 응답에 온다. 2026-10-04 937건.
    # 화면이 스스로 부른 10건 응답을 잡았거나 2000건을 넘으면 총수와 달라 멈춘다
    body = fetch(
        Request(
            "disclosure",
            "https://pc.wooricard.com/dcpc/yh1/cct/cct11/prdntc/H1CCT211S09.do",
            capture="getMainDataList.pwkjson",
            script="H1CCT211S09.variable.PAGE_SIZE = '2000'; H1CCT211S09.variable.PAGE_NO = '1';"
            " H1CCT211S09.svrAction.getMainData();",
        )
    )
    data = _json(body)["mainDataList"]
    if len(data["cct11PrdntcAgrmMainVo"]) < int(data["totCnt"]):
        raise ValueError(f"우리 공시 {data['totCnt']}건 가운데 {len(data['cct11PrdntcAgrmMainVo'])}건만 왔다")


def _hana_plan(fetch: Fetch, today: date) -> None:
    # 공시실에는 카드 목록이 없어 카드 한눈에 보기를 쓴다. 분류마다 그 분류의 카드가 한 응답에 온다
    url = "https://www.hanacard.co.kr/OPI22000000D.ajax"
    form = {"schID": "pcd", "mID": "OPM05000000C"}
    categories = fetch(
        Request("categories", url, form={**form, "PAGE": "1", "SLC_CT_NM": "", "targetMethod": "categoryList"})
    )
    for c in _hana_json(categories)["dataMap"]["CATEGORY_LIST"]["data"]:
        kind = "-check" if "체크" in c["CT_NM"] else "-credit" if "신용" in c["CT_NM"] else ""
        fetch(
            Request(
                f"cards{kind}-{c['CT_ID']}",
                url,
                form={**form, "CT_ID": c["CT_ID"], "LIST_TYPE": "S", "targetMethod": "cardMainList"},
            )
        )


def _carddamoa_plan(fetch: Fetch, today: date) -> None:
    # 여신금융협회 서버는 Python이 받아들이지 않는 옛 TLS 서명을 써서 브라우저로 연다. 2026-10-04 robots.txt는 없다(404).
    # 화면이 열리면 신용 01을 부르고, fn_showTab('02')가 체크를 부른다
    url = "https://gongsi.crefia.or.kr/portal/carddamoa/carddamoaList"
    fetch(Request("recommend-credit", url, capture="carddamoaList/schList"))
    fetch(Request("recommend-check", url, capture="carddamoaList/schList", script="fn_showTab('02')"))


PLANS: dict[str, Callable[[Fetch, date], None]] = {
    "kb": _kb_plan,
    "ibk": _ibk_plan,
    "nh": _nh_plan,
    "shinhan": _shinhan_plan,
    "kakaobank": _kakaobank_plan,
    "hyundai": _hyundai_plan,
    "lotte": _lotte_plan,
    "samsung": _samsung_plan,
    "woori": _woori_plan,
    "hana": _hana_plan,
    # 카드사가 아니라 여러 카드사의 추천 표시다. 색인 단계가 카드사 묶음 뒤에 따로 다룬다
    "carddamoa": _carddamoa_plan,
}

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
        recommended=a.recommended or b.recommended,
        detail_ref=first.detail_ref or second.detail_ref,
        enrich_only=a.enrich_only and b.enrich_only,
        source_path=first.source_path or second.source_path,
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
            continue
        out[i] = _join(out[i], r)
        # 보충 행 여럿이 색인 행보다 먼저 와 있으면 그것들도 모두 합친다. 현대 설명서 파일과 카드 목록
        extra = [n for n in found if n != i and out[n].enrich_only and _same(out[n], out[i])]
        for n in extra:
            out[i] = _join(out[i], out[n])
        out = [o for n, o in enumerate(out) if n not in extra]
    return [r for r in out if not r.enrich_only], [r for r in out if r.enrich_only]


def row_key(row: IndexRow) -> str:
    """색인 MERGE 열쇠. 받을 때마다 같은 값이 나오는 칸을 쓴다. 공시 문서 번호, 카드 코드, 정리한 이름 순서다.

    현대는 같은 이름의 옛 판이 따로 있고 카드 코드는 카드 목록에 있을 때만 붙는다. 그래서 설명서 번호를 먼저 쓴다.
    """
    if row.detail_ref:
        return f"ref:{row.detail_ref}"
    if row.code:
        return f"code:{row.code}"
    return f"name:{_name_key(row.name)}"


@dataclass(frozen=True)
class KnownCard:
    """카탈로그에 있는 카드. 색인 행과 짝지을 이름과 코드다."""

    card_id: str
    issuer: str
    names: tuple[str, ...]
    codes: tuple[str, ...]


def _code_key(code: str) -> str:
    # IBK는 카탈로그에 12-11-296-0001, 목록에 12112960001로 적혀 있다
    return re.sub(r"[\W_]+", "", code).casefold()


def card_ids(rows: list[IndexRow], known: list[KnownCard]) -> list[tuple[str, bool]]:
    """행마다 (card_id, 카탈로그에 있는 카드인지). 같은 카드사에서 코드나 이름이 같으면 카탈로그 id를 쓴다.

    한 카탈로그 카드에 이름이 같은 행이 여럿이면 판매 중인 행 하나에만 준다. 옛 판은 따로 id를 받는다.
    없는 카드는 카드사 id와 카드 코드, 공시 번호, 이름 지문 순서로 만든다. 사람이 승인할 때 바꿀 수 있다.
    """
    by_code = {(k.issuer, _code_key(c)): k.card_id for k in known for c in k.codes}
    by_name = {(k.issuer, _name_key(n)): k.card_id for k in known for n in k.names}
    found: list[str | None] = []
    for r in rows:
        cid = by_code.get((r.issuer, _code_key(r.code))) if r.code else None
        found.append(cid or by_name.get((r.issuer, _name_key(r.name))))
    taken: set[str] = set()
    out = []
    for status in ("on_sale", "discontinued"):
        for i, r in enumerate(rows):
            if r.status == status and found[i] and found[i] not in taken:
                taken.add(found[i])
            elif r.status == status:
                found[i] = None
    for r, cid in zip(rows, found):
        if cid:
            out.append((cid, True))
            continue
        own = r.code or r.detail_ref
        slug = re.sub(r"[^a-z0-9]+", "-", own.casefold()).strip("-") if own else ""
        slug = slug or "n" + hashlib.sha1(_name_key(r.name).encode()).hexdigest()[:10]
        out.append((f"{r.issuer}-{slug}", False))
    return out


def recommended_keys(
    recs: list[IndexRow], index: list[tuple[str, str, str, str | None]]
) -> tuple[dict[tuple[str, str], IndexRow], list[IndexRow]]:
    """카드다모아 추천 행과 짝인 색인 열쇠 {(카드사, 열쇠): 추천 행}과 짝을 못 찾은 추천 행.

    index는 판매 중 색인 행의 (카드사, 열쇠, 이름, 상품 페이지)다. 같은 카드사에서 상품 페이지 주소나 정리한 이름이 같으면 짝이다.
    """
    by_page = {(i, page): (i, k) for i, k, _, page in index if page}
    by_name = {(i, _name_key(name)): (i, k) for i, k, name, _ in index}
    found: dict[tuple[str, str], IndexRow] = {}
    missing = []
    for r in recs:
        hit = by_page.get((r.issuer, r.page_url)) or by_name.get((r.issuer, _name_key(r.name)))
        if hit:
            found[hit] = r
        else:
            missing.append(r)
    return found, missing
