"""Play 스토어 등록 정보의 글자 수와 그림 크기. 작업 012 설계 3절, 의도 성공 기준 3

제한은 2026-10-05 Play 고객센터에서 확인했다. 그림은 PNG 머리만 읽어 새 의존성을 들이지 않는다
"""

import re
import struct
from pathlib import Path

import pytest

STORE = Path(__file__).resolve().parents[2] / "docs" / "store"
RGB, RGBA = 2, 6  # PNG 색 형식. 2는 투명 없는 24비트, 6은 투명 있는 32비트


def section(name: str) -> str:
    text = (STORE / "listing.md").read_text(encoding="utf-8")
    body = re.search(rf"^## {name}\n(.*?)(?=^## |\Z)", text, re.MULTILINE | re.DOTALL).group(1)
    fenced = re.search(r"```text\n(.*?)```", body, re.DOTALL)
    return (fenced.group(1) if fenced else body).strip()


def png(path: Path) -> tuple[int, int, int, int]:
    """너비, 높이, 비트 깊이, 색 형식"""
    head = path.read_bytes()[:26]
    assert head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR", f"{path.name}은 PNG가 아니다"
    w, h, depth, color = struct.unpack(">IIBB", head[16:26])
    return w, h, depth, color


def screenshot_ok(w: int, h: int) -> bool:
    short, long = sorted((w, h))
    return short >= 320 and long <= 3840 and long <= 2 * short


@pytest.mark.parametrize(("name", "limit"), [("앱 이름", 30), ("짧은 설명", 80), ("자세한 설명", 4000)])
def test_text_fits_limits(name, limit):
    text = section(name)
    assert 0 < len(text) <= limit, f"{name} {len(text)}자"


def test_screenshot_ratio_rule():
    # 지금 에뮬레이터 1080×2400은 긴 변이 짧은 변의 두 배를 넘어 Play가 받지 않는다. 설계 3.2
    assert not screenshot_ok(1080, 2400)
    assert screenshot_ok(1080, 1920)
    assert not screenshot_ok(300, 600)


def test_icon():
    path = STORE / "icon-512.png"
    assert png(path) == (512, 512, 8, RGBA)
    assert path.stat().st_size <= 1024 * 1024


def test_feature_graphic():
    assert png(STORE / "feature-1024x500.png") == (1024, 500, 8, RGB)


def test_screenshots():
    shots = sorted((STORE / "screens").glob("*.png"))
    assert len(shots) >= 2
    for path in shots:
        w, h, depth, color = png(path)
        assert (depth, color) == (8, RGB), path.name
        assert screenshot_ok(w, h), f"{path.name} {w}×{h}"
