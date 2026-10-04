"""Play 스토어 그림과 폰 홈 화면 아이콘을 그린다. 작업 012 설계 3.2

돌리기: uv run --project backend --with pillow python backend/tools/store_art.py
- 스크린샷 원본은 에뮬레이터를 `adb shell wm size 1080x1920`으로 바꿔 screens.py로 찍은 app/build/screens/store/다
- 문구는 docs/store/listing.md의 스크린샷 문구 표에서 읽는다
- 그림 크기와 형식은 backend/tests/test_store_listing.py가 검사한다
"""

import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "docs" / "store"
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
SHOTS = ROOT / "app" / "build" / "screens" / "store"
FONTS = ROOT / "app" / "assets" / "fonts"
CREAM = (255, 246, 236)  # 아이콘 바탕. 2026-10-05 사용자가 골랐다
BLUE = (52, 87, 178)  # 앱 C.blue
WHITE = (255, 255, 255)
# 찍은 화면, 문구 표의 화면 이름, 내보낼 이름
SCREENS = [
    ("1-home", "홈", "1-home"),
    ("6-card-detail", "카드 상세", "2-card"),
    ("5-recommend", "추천", "3-recommend"),
    ("5b-result", "가게별 순위", "4-result"),
    ("4-payment-bottom", "결제 기록", "5-payment"),
    ("7-history", "기록", "6-history"),
]

ART = Image.open(ROOT / "design" / "icon.png").convert("RGBA")
ART = ART.crop(ART.getbbox())


def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"CherrySans-{weight}.otf"), size)


def centered(size: int, scale: float, bg: tuple[int, int, int, int]) -> Image.Image:
    """size 정사각형 가운데에 그림을 size × scale 안에 맞춰 둔다"""
    out = Image.new("RGBA", (size, size), bg)
    art = ART.copy()
    art.thumbnail((round(size * scale),) * 2, Image.LANCZOS)
    out.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return out


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius=radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def store_icon() -> None:
    # 모서리는 Play가 30%로 깎는다. 원본은 꽉 찬 정사각형이다
    centered(512, 0.78, CREAM + (255,)).save(STORE / "icon-512.png")


def launcher_icons() -> None:
    # Android 8 이상은 적응형 아이콘이다. 108dp 칸 가운데 지름 66dp 안전 영역에 들게 그림을 41%로 둔다.
    # 바탕색은 values/colors.xml의 ic_launcher_background다. 그 아래 판은 둥근 사각형 PNG를 쓴다
    for name, dp in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
        folder = RES / f"mipmap-{name}"
        centered(round(108 * dp), 0.41, (0, 0, 0, 0)).save(folder / "ic_launcher_foreground.png")
        size, pad = round(48 * dp), round(2 * dp)
        legacy = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inner = size - 2 * pad
        legacy.alpha_composite(rounded(centered(inner, 0.78, CREAM + (255,)), round(inner * 0.2)), (pad, pad))
        legacy.save(folder / "ic_launcher.png")


def feature_graphic() -> None:
    im = Image.new("RGB", (1024, 500), BLUE)
    tile = rounded(centered(260, 0.78, CREAM + (255,)), 60)
    im.paste(tile, (110, 120), tile)
    draw = ImageDraw.Draw(im)
    draw.text((420, 250), "체리컨슘", font=font("ExtraBold", 96), fill=WHITE, anchor="ls")
    draw.text((424, 330), "카드 실적·혜택 계산기", font=font("Bold", 40), fill=(232, 238, 251), anchor="ls")
    im.save(STORE / "feature-1024x500.png")


def captions() -> dict[str, str]:
    text = (STORE / "listing.md").read_text(encoding="utf-8")
    table = text.split("## 스크린샷 문구", 1)[1]
    return dict(re.findall(r"^\| (.+?) \| (.+?) \|$", table, re.MULTILINE))


def lines(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    """한 줄에 안 들면 가운데에 가까운 띄어쓰기에서 두 줄로 나눈다"""
    if draw.textlength(text, font=f) <= width:
        return [text]
    cut = min((i for i, c in enumerate(text) if c == " "), key=lambda i: abs(i - len(text) / 2))
    return [text[:cut], text[cut + 1 :]]


def screenshots() -> None:
    words = captions()
    out = STORE / "screens"
    out.mkdir(exist_ok=True)
    f = font("ExtraBold", 64)
    for src, name, dest in SCREENS:
        im = Image.new("RGB", (1080, 1920), BLUE)
        draw = ImageDraw.Draw(im)
        rows = lines(draw, words[name], f, 960)
        top = 232 if len(rows) == 1 else 188
        for j, row in enumerate(rows):
            draw.text((540, top + j * 88), row, font=f, fill=WHITE, anchor="ms")
        shot = Image.open(SHOTS / f"{src}.png").convert("RGB").resize((840, 1493), Image.LANCZOS)
        shot = rounded(shot, 44)
        im.paste(shot, (120, 380), shot)
        im.save(out / f"{dest}.png")


if __name__ == "__main__":
    store_icon()
    launcher_icons()
    feature_graphic()
    screenshots()
