"""앱 글꼴을 만든다. Pretendard에서 자주 쓰는 글자만 남기고 이름을 Cherry Sans로 바꾼다. 작업 011 설계 1절, 4절

돌리기: uv run --no-project --with fonttools python backend/tools/subset_font.py <Pretendard 압축을 푼 폴더>
- 원본은 https://github.com/orioncactus/pretendard/releases 의 Pretendard-1.3.9.zip이다
  sha256 04be351a74d6bf7d60c480a3087e51d185485d35a52023142af1df19eb8c428a
- 남기는 글자는 영문, 숫자, 기호, 한글 자모, KS X 1001 한글 2,350자다. 없는 글자는 폰 기본 글꼴로 그려진다
- Pretendard는 SIL 오픈 글꼴 라이선스 1.1이고 이름 "Pretendard"를 지은이가 남겨 두었다. 글자를 줄이면 고친 판이라
  그 이름을 쓸 수 없어 안의 이름을 Cherry Sans로 바꾸고 라이선스를 함께 둔다
"""

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

OUT = Path(__file__).resolve().parents[2] / "app" / "assets" / "fonts"
WEIGHTS = ["Regular", "Bold", "ExtraBold"]
SYMBOLS = "·…‘’“”–—•※○●◎◇◆□■△▲▽▼→←↑↓↔₩×÷±≤≥≠°%‰€£¥©®™"


def unicodes() -> list[int]:
    keep = set(range(0x20, 0x7F)) | set(range(0xA0, 0x100)) | set(range(0x3131, 0x318F))
    keep |= {ord(c) for c in SYMBOLS}
    # EUC-KR 2바이트로 쓰이는 한글 음절이 KS X 1001의 2,350자다. 나머지는 Python이 자모 8바이트로 풀어 쓴다
    keep |= {cp for cp in range(0xAC00, 0xD7A4) if len(chr(cp).encode("euc-kr")) == 2}
    return sorted(keep)


def rename(font: TTFont) -> None:
    for rec in font["name"].names:
        text = rec.toUnicode()
        if "Pretendard" in text:
            rec.string = text.replace("Pretendard", "CherrySans" if rec.nameID == 6 else "Cherry Sans")


def main(src: Path) -> None:
    static = next(src.rglob("public/static"))
    OUT.mkdir(parents=True, exist_ok=True)
    options = subset.Options()
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    keep = unicodes()
    for weight in WEIGHTS:
        font = TTFont(static / f"Pretendard-{weight}.otf")
        sub = subset.Subsetter(options)
        sub.populate(unicodes=keep)
        sub.subset(font)
        rename(font)
        out = OUT / f"CherrySans-{weight}.otf"
        font.save(out)
        print(out.name, out.stat().st_size)
    license_text = (src / "LICENSE.txt").read_text(encoding="utf-8")
    note = (
        "Cherry Sans는 Pretendard 1.3.9에서 자주 쓰는 글자만 남기고 이름을 바꾼 글꼴이다.\n"
        "Cherry Sans is a subset of Pretendard 1.3.9 renamed under the Reserved Font Name clause.\n\n"
    )
    (OUT / "OFL.txt").write_text(note + license_text, encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Pretendard 압축을 푼 폴더를 넘긴다")
    main(Path(sys.argv[1]))
