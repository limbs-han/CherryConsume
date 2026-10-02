"""이용 내역 엑셀 가져오기의 파일 읽기. csv, xlsx, html 표로 된 xls. 작업 005 설계 5f, 설계 문서 8절

파일은 메모리에서 읽고 저장하지 않는다. E35
"""

from __future__ import annotations

import csv
import hashlib
import io
import re
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, time
from html.parser import HTMLParser

MAX_ROWS = 3000
MAX_COLS = 60
# xlsx를 풀었을 때의 크기. 몇 KB짜리 파일이 수 GB로 풀리는 압축 폭탄을 막는다
MAX_UNZIPPED = 30_000_000

# 열 이름 사전. 띄어쓰기와 괄호 안을 뺀 이름으로 맞춘다. 앞에 있는 이름이 먼저다
# ponytail: 흔한 이름만 넣었다. 카드사 실제 파일을 받으면 카드사별 매핑 표로 채운다
NAMES = {
    "date": [
        "이용일자",
        "이용일",
        "승인일자",
        "승인일",
        "거래일자",
        "거래일",
        "사용일자",
        "사용일",
        "이용일시",
        "승인일시",
        "거래일시",
    ],
    "time": ["이용시간", "승인시간", "거래시간", "사용시간", "이용시각", "승인시각", "시간"],
    "merchant": ["가맹점명", "이용가맹점", "이용하신가맹점", "가맹점", "이용처", "사용처", "거래처"],
    "amount": ["이용금액", "승인금액", "거래금액", "사용금액", "결제금액", "금액"],
    "installment": ["할부개월", "할부기간", "할부개월수", "할부", "이용구분"],
    "cancel": ["취소여부", "승인구분", "취소구분", "상태", "거래구분", "구분"],
    "approval": ["승인번호"],
    "card": ["카드명", "이용카드", "카드이름", "카드"],
    "interest_free": ["무이자여부", "무이자구분", "무이자"],
    "region": ["해외여부", "국내외구분", "국내외", "해외구분", "이용국가"],
}
REQUIRED = ("date", "merchant", "amount")


class Unreadable(ValueError):
    """읽을 수 없는 파일. 문구는 앱이 그대로 보인다"""


@dataclass
class Row:
    line: int
    day: date | None = None
    at: time | None = None
    merchant: str = ""
    amount: int = 0
    cancel: bool = False
    installment_months: int = 1
    approval_no: str | None = None
    card: str | None = None
    # 할부인데 무이자인지 모르면 None이다. 유이자로 넣고 미리보기에 알린다. 2026-10-02 사용자가 정했다
    interest_free: bool | None = False
    overseas: bool = False
    error: str | None = None


def norm(name: object) -> str:
    return re.sub(r"\(.*?\)|\[.*?\]|\s", "", str(name or ""))


def signature(headers: list, salt: str = "") -> str:
    """머리 줄 모양의 해시. 사용자가 짝지은 열을 같은 모양의 다음 파일에 다시 쓴다. E30

    머리 줄이 이름이나 카드번호가 적힌 줄일 수 있어 글자를 남기지 않는다. 사용자마다 다른 salt를 섞어 흔한 값을 대입해
    되짚기 어렵게 한다. 빈 칸도 자리로 넣어 열이 밀리면 다른 모양이다
    """
    return hashlib.sha256((salt + "|" + "|".join(norm(h) for h in headers)).encode()).hexdigest()


def _unzipped(data: bytes) -> None:
    """xlsx를 실제로 풀며 크기를 센다. 목차에 적힌 크기는 꾸밀 수 있다. 보통 쓰는 두 방식만 받는다. 압축 폭탄을 막는다"""
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
        total = 0
        for info in z.infolist():
            if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
                raise Unreadable("엑셀 파일을 읽지 못했어요")
            with z.open(info) as f:
                while chunk := f.read(1 << 16):
                    total += len(chunk)
                    if total > MAX_UNZIPPED:
                        raise Unreadable("엑셀 파일이 너무 커요. 기간을 나눠 올려 주세요")
    except (zipfile.BadZipFile, OSError, ValueError, EOFError) as e:
        raise Unreadable("엑셀 파일을 읽지 못했어요") from e


class _Table(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.rows: list[list[str]] = []
        self.cell: list[str] | None = None

    def handle_starttag(self, tag, attrs) -> None:
        if tag == "tr":
            self.rows.append([])
        elif tag in ("td", "th") and self.rows:
            self.cell = []

    def handle_endtag(self, tag) -> None:
        if tag in ("td", "th") and self.cell is not None:
            self.rows[-1].append(" ".join("".join(self.cell).split()))
            self.cell = None

    def handle_data(self, data) -> None:
        if self.cell is not None:
            self.cell.append(data)


def _text(data: bytes) -> str:
    for encoding in ("utf-8-sig", "cp949"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise Unreadable("글자를 읽지 못했어요. UTF-8이나 CP949로 저장한 파일을 올려 주세요")


def read_table(data: bytes, name: str) -> list[list]:
    """파일을 행 목록으로. 칸은 글자나 숫자, 날짜다"""
    if data.startswith(b"PK"):
        import openpyxl

        _unzipped(data)
        try:
            wb = openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)
            # 시트 머리에 적힌 크기를 믿지 않는다. 행과 열을 정해 둔 만큼만 읽는다
            sheet = wb.worksheets[0]
            limit = MAX_ROWS + 30
            rows = [list(r) for r in sheet.iter_rows(max_row=limit, max_col=MAX_COLS, values_only=True)]
            # 끝까지 읽었는데 마지막 줄들에 값이 있으면 뒤에 행이 더 있다. 말없이 자르지 않는다
            if len(rows) >= limit and any(any(str(c or "").strip() for c in r) for r in rows[-10:]):
                raise Unreadable(f"행이 {MAX_ROWS:,}개보다 많아요. 기간을 나눠 올려 주세요")
        except Unreadable:
            raise
        except Exception as e:
            raise Unreadable("엑셀 파일을 읽지 못했어요") from e
    elif data.startswith(b"\xd0\xcf\x11\xe0"):
        raise Unreadable("옛 엑셀 형식이라 읽지 못했어요. 엑셀에서 xlsx나 csv로 저장해 올려 주세요")
    else:
        text = _text(data)
        lower = text.lower()
        # 행을 만들기 전에 센다. 줄바꿈만 수백만 개인 파일이 메모리를 다 쓰지 않게 한다
        too_many = Unreadable(f"행이 {MAX_ROWS:,}개보다 많아요. 기간을 나눠 올려 주세요")
        if text.lstrip().startswith("<") and "<table" in lower:
            if lower.count("<tr") > MAX_ROWS + 20:
                raise too_many
            parser = _Table()
            parser.feed(text)
            rows = parser.rows
        else:
            if text.count("\n") > (MAX_ROWS + 20) * 4:
                raise too_many
            try:
                rows = list(csv.reader(io.StringIO(text)))
            except csv.Error as e:
                raise Unreadable("csv 파일을 읽지 못했어요") from e
    rows = [r[:MAX_COLS] for r in rows]
    rows = [r for r in rows if any(str(c or "").strip() for c in r)]
    if len(rows) > MAX_ROWS + 20:
        raise Unreadable(f"행이 {MAX_ROWS:,}개보다 많아요. 기간을 나눠 올려 주세요")
    return rows


def top_rows(table: list[list]) -> list[list[str]]:
    """짝짓기 화면에서 머리 줄을 고를 위 10줄. 앱이 올린 파일의 줄이라 앱에만 돌려준다"""
    return [[str(c or "").strip() for c in r] for r in table[:10]]


def top_row(table: list[list]) -> int:
    """열 이름을 못 찾을 때 짝짓기 화면에 보일 줄. 위 20줄에서 칸이 셋 이상인 첫 줄이다"""
    return next((i for i, r in enumerate(table[:20]) if sum(1 for c in r if str(c or "").strip()) >= 3), 0)


def find_header(table: list[list], mapping: dict | None = None) -> tuple[int | None, dict | None]:
    """머리 줄과 열 짝 {칸: 열 번호}. mapping은 사용자가 짝지은 {"row": 줄, "columns": {칸: 열 번호}}다.
    사전으로 못 찾으면 (None, None)이다. E30"""
    if mapping is not None:
        row, cols = mapping.get("row"), mapping.get("columns")
        ok = (
            type(row) is int
            and 0 <= row < min(len(table), 20)
            and isinstance(cols, dict)
            and set(cols) <= set(NAMES)
            and all(f in cols for f in REQUIRED)
            and all(type(j) is int and 0 <= j < len(table[row]) for j in cols.values())
            and len(set(cols.values())) == len(cols)
        )
        if not ok:
            raise Unreadable("열 짝이 맞지 않아요. 한 열은 한 칸에만 고르고 결제일, 가맹점명, 금액은 꼭 골라 주세요")
        return row, dict(cols)
    best: tuple[int, int, dict] | None = None
    for i, row in enumerate(table[:20]):
        names = [norm(c) for c in row]
        found: dict[str, int] = {}
        for field, words in NAMES.items():
            for w in words:
                cols = [j for j, n in enumerate(names) if n == w and j not in found.values()]
                if cols:
                    found[field] = cols[0]
                    break
        if all(f in found for f in REQUIRED) and (best is None or len(found) > best[0]):
            best = (len(found), i, found)
    return (best[1], best[2]) if best else (None, None)


DATE = re.compile(r"(\d{2,4})\s*[.\-/년]?\s*(\d{1,2})\s*[.\-/월]?\s*(\d{1,2})")
TIME = re.compile(r"(\d{1,2}):(\d{2})(?::(\d{2}))?")


def _day(v) -> tuple[date | None, time | None]:
    if isinstance(v, datetime):
        return v.date(), v.time() if v.time() != time(0) else None
    if isinstance(v, date):
        return v, None
    s = str(v or "").strip()
    m = DATE.search(s)
    if not m:
        return None, None
    y, mo, d = (int(x) for x in m.groups())
    try:
        day = date(y + 2000 if y < 100 else y, mo, d)
    except ValueError:
        return None, None
    return day, _time(s[m.end() :])


def _time(v) -> time | None:
    if isinstance(v, time):
        return v
    if isinstance(v, datetime):
        return v.time()
    s = str(v or "").strip()
    m = TIME.search(s) or (re.fullmatch(r"(\d{2})(\d{2})(\d{2})?", s) if s.isdigit() else None)
    if not m:
        return None
    h, mi, sec = int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)
    return time(h, mi, sec) if h < 24 and mi < 60 and sec < 60 else None


def _amount(v) -> int | None:
    if isinstance(v, bool):
        return None
    if isinstance(v, int | float):
        return round(v)
    s = re.sub(r"[,\s원₩]", "", str(v or ""))
    # "-4,500", "4,500-", "(4,500)"은 모두 취소다
    negative = s.startswith("-") or s.endswith("-") or (s.startswith("(") and s.endswith(")"))
    s = s.strip("-()")
    if not s.isdigit():
        return None
    return -int(s) if negative else int(s)


def _approval(v) -> str | None:
    """자리만 채운 "-", "0", "00000000" 같은 값은 승인번호가 아니다. xlsx 숫자 칸은 앞의 0이 빠져 비교할 때 뗀다"""
    s = str(v or "").strip()
    if s.endswith(".0") and s[:-2].isdigit():
        s = s[:-2]
    return s if len(s) >= 4 and any(c.isdigit() and c != "0" for c in s) else None


def approval_key(v: str | None) -> str | None:
    return v.lstrip("0") if v else None


def _yes(v) -> bool | None:
    s = norm(v).lower()
    if not s:
        return None
    if s in ("y", "예", "o", "yes") or "무이자" in s or "해외" in s:
        return True
    if s in ("n", "아니오", "x", "no") or "유이자" in s or "국내" in s:
        return False
    return None


def _installment(v) -> int:
    s = str(v or "").strip()
    m = re.search(r"\d+", s)
    return max(int(m.group()), 1) if m else 1


def parse_rows(table: list[list], start: int, mapping: dict[str, int]) -> list[Row]:
    """머리 줄 아래 행을 결제 행으로. 날짜도 가맹점도 없는 합계 줄은 건너뛴다"""
    out = []
    for i, raw in enumerate(table[start + 1 :], start + 2):

        def get(field: str, raw=raw):
            j = mapping.get(field)
            return raw[j] if j is not None and j < len(raw) else None

        day, at = _day(get("date"))
        merchant = " ".join(str(get("merchant") or "").split())
        if day is None and not merchant:
            continue
        row = Row(line=i, day=day, merchant=merchant)
        amount = _amount(get("amount"))
        if day is None:
            row.error = "날짜를 읽지 못했어요"
        elif amount is None or amount == 0:
            row.error = "금액을 읽지 못했어요"
        else:
            # 시각 열이 비면 날짜 칸에 든 시각을 쓴다
            row.at = (_time(get("time")) if "time" in mapping else None) or at
            row.amount = abs(amount)
            row.cancel = amount < 0 or "취소" in str(get("cancel") or "")
            row.installment_months = _installment(get("installment"))
            row.approval_no = _approval(get("approval"))
            row.card = str(get("card") or "").strip() or None
            free = _yes(get("interest_free")) if "interest_free" in mapping else None
            if free is None and "무이자" in str(get("installment") or ""):
                free = True
            # 일시불은 무이자가 아니다. 할부인데 무이자인지 모르면 None이다
            row.interest_free = False if row.installment_months == 1 else free
            # 해외 여부 Y나 국내외 구분 "해외"면 해외다. 열이 없거나 모르면 국내다
            # ponytail: 이용 국가 열의 나라 이름은 읽지 않는다. 실제 파일을 받으면 더한다
            row.overseas = _yes(get("region")) is True
        out.append(row)
    return out
