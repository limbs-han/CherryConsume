"""앱 화면과 시안 화면을 찍어 나란히 본다. 작업 011 설계 2절

돌리기
- 앱: uv run --project backend python backend/tools/screens.py app <기기 일련번호> <이름표>
  에뮬레이터나 폰에서 app/integration_test/screens_test.dart를 돌리고, 시험이 "SHOT 이름"을 출력할 때마다 adb로
  시스템 막대까지 화면 전체를 찍어 app/build/screens/<이름표>/<이름>.png에 둔다
- 시안: uv run --project backend --with playwright python backend/tools/screens.py mockup
  design/체리컨슘-화면-시안.html의 화면마다 설치된 Chrome으로 찍어 app/build/screens/mockup/<화면 id>.png에 둔다
app/build/는 저장소에 올라가지 않는다
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
OUT = APP / "build" / "screens"
ADB = shutil.which("adb") or str(Path.home() / "dev/android-sdk/platform-tools/adb.exe")
BOARDS = [
    "HomeEmpty", "Home", "AddCard", "CardDetail", "AddTxn",
    "Recommend", "RecommendResult", "History", "Import", "ImportPreview", "Settings", "States",
]  # fmt: skip


def app(device: str, label: str) -> int:
    out = OUT / label
    out.mkdir(parents=True, exist_ok=True)
    flutter = shutil.which("flutter")
    cmd = [flutter, "test", "integration_test/screens_test.dart", "-d", device]
    proc = subprocess.Popen(
        cmd, cwd=APP, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace"
    )
    for line in proc.stdout:
        print(line, end="")
        if line.startswith("SHOT "):
            name = line.split(maxsplit=1)[1].strip()
            png = subprocess.run([ADB, "-s", device, "exec-out", "screencap", "-p"], capture_output=True, check=True)
            (out / f"{name}.png").write_bytes(png.stdout)
    return proc.wait()


def mockup() -> None:
    from playwright.sync_api import sync_playwright

    out = OUT / "mockup"
    out.mkdir(parents=True, exist_ok=True)
    page_url = (ROOT / "design" / "체리컨슘-화면-시안.html").as_uri()
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome")
        page = browser.new_page(device_scale_factor=2, viewport={"width": 1400, "height": 1000})
        page.goto(page_url)
        for board in BOARDS:
            page.locator(f"#{board}").screenshot(path=str(out / f"{board}.png"))
            print(board)
        browser.close()


if __name__ == "__main__":
    os.environ.setdefault("PYTHONUTF8", "1")
    if sys.argv[1:2] == ["app"] and len(sys.argv) == 4:
        sys.exit(app(sys.argv[2], sys.argv[3]))
    elif sys.argv[1:] == ["mockup"]:
        mockup()
    else:
        sys.exit("app <기기> <이름표> 또는 mockup")
