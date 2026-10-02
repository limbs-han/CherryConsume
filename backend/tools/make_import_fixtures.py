"""엑셀 가져오기 시험 파일을 만든다. Dart 시험이 Python과 같은 파일을 읽게 한다. 작업 006 계획 단계 1의 3

돌리기: uv run --project backend python backend/tools/make_import_fixtures.py
xlsx는 만들 때마다 안의 시각이 달라 다시 만든 파일과 바이트로 비교하지 않는다. 내용은 backend/tests/api/test_import_parse.py와 같다.
"""

from __future__ import annotations

import io
import zipfile
from datetime import datetime, time
from pathlib import Path

import openpyxl

OUT = Path(__file__).resolve().parents[2] / "app" / "test" / "fixtures" / "imports"
HEAD = ["이용일자", "이용시간", "가맹점명", "이용금액(원)", "할부", "승인번호", "취소여부"]
BODY = [
    ["2026.09.10", "12:30", "스타벅스 강남점", "4,500", "일시불", "11112222", ""],
    ["2026-09-11", "", "이마트 성수점", "120,000", "3개월", "33334444", ""],
    ["2026/09/12", "08:05:09", "스타벅스 강남점", "-4,500", "일시불", "11112222", "취소"],
    ["합계", "", "", "120,000", "", "", ""],
]


def csv_text() -> str:
    lines = ["카드 이용 내역", "조회 기간 2026.09.01 ~ 2026.09.30", ",".join(HEAD)]
    lines += [",".join(f'"{v}"' for v in row) for row in BODY]
    return "\n".join(lines)


def xlsx(fill) -> bytes:
    wb = openpyxl.Workbook()
    fill(wb.active)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def dates_and_numbers(ws) -> None:
    ws.append(["카드 이용 내역"])
    ws.append(HEAD)
    ws.append([datetime(2026, 9, 10), time(12, 30), "스타벅스 강남점", 4500, "일시불", "11112222", None])  # noqa: DTZ001
    ws.append([datetime(2026, 9, 11), None, "이마트 성수점", 120000.0, "03", "33334444", None])  # noqa: DTZ001
    ws.append([datetime(2026, 9, 12, 8, 5, 9), None, "스타벅스 강남점", -4500, "일시불", "11112222", "취소"])  # noqa: DTZ001


def far_cell(ws) -> None:
    # 시트 머리의 크기를 믿지 않는다. 100만 번째 행에 칸 하나가 있어도 정해 둔 만큼만 읽는다
    ws.append(HEAD)
    ws.append(["2026.09.10", "", "스타벅스", "4500", "", "", ""])
    ws.cell(row=1_000_000, column=16_000, value="x")


def zipped(method: int, size: int) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", method) as z:
        z.writestr("xl/sharedStrings.xml", "a" * size)
    return buf.getvalue()


FILES = {
    "utf8.csv": csv_text().encode("utf-8-sig"),
    "cp949.csv": csv_text().encode("cp949"),
    "dates_and_numbers.xlsx": xlsx(dates_and_numbers),
    "far_cell.xlsx": xlsx(far_cell),
    # 풀면 30MB가 넘는 압축 파일
    "unzip_bomb.xlsx": zipped(zipfile.ZIP_DEFLATED, 31_000_000),
    # 보통 쓰는 두 방식이 아닌 압축
    "bzip2.xlsx": zipped(zipfile.ZIP_BZIP2, 1),
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in FILES.items():
        (OUT / name).write_bytes(data)
        print(f"{name} {len(data):,}바이트")


if __name__ == "__main__":
    main()
