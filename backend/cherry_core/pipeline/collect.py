"""카드사 원문 수집기. GitHub Actions와 개발자 PC에서 돈다. 설계 4절 2번.

카드사 파일의 collect와 카드 파일의 sources에 적힌 주소를 받아 날짜별 폴더에 원본 그대로 저장한다.
실행 기록은 공개 저장소에서 누구나 보므로 원문 내용은 찍지 않고 개수와 id만 찍는다.
브라우저가 필요한 카드사는 Playwright로 연다. 실행할 때 `uv run --with playwright`로 더한다.
`--disclosure`는 카드사 상품공시실만 받는다. 작업 008 설계 1절. 받는 순서는 `cherry_core.pipeline.disclosure.PLANS`다.
`--index-cards`를 함께 주면 받은 공시로 색인 행을 다시 만들어 카탈로그 밖 카드의 상품 페이지와 최신 PDF도 받는다.
카드사가 403이나 429로 거절하거나 연결이 세 번 잇달아 끊기면 그 카드사의 남은 주소는 이번 실행에서 받지 않는다. 설계 2절.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from collections.abc import Callable
from contextlib import ExitStack
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime, timedelta, timezone
from pathlib import Path
from typing import TextIO
from urllib.parse import urlsplit

from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.card_index import key_id
from cherry_core.pipeline.disclosure import (
    PLANS,
    KnownCard,
    Request,
    card_ids,
    collectable,
    merge_rows,
    read,
    row_key,
)
from cherry_core.pipeline.text import image_heavy

DEFAULT_ROOT = Path(__file__).resolve().parents[3] / "catalog"
AGENT = "cherryconsume-collector"
USER_AGENT = f"{AGENT} (+https://github.com/limbs-han/CherryConsume)"
DELAY_SECONDS = 2
TRIES = 3  # 연결이 끊겼을 때 묻는 횟수
PLAIN_KINDS = {"manual_pdf", "terms_pdf", "api"}
BLOCK_CODES = (403, 429)  # 거절과 요청이 너무 많다는 답. 사이트에 부담을 주지 않으려고 그 카드사를 멈춘다
DROPS = 3  # 한 카드사에서 연결이 이만큼 잇달아 끊기면 멈춘다
# robots.txt를 묻지 않는 곳. 삼성, IBK, 카카오뱅크, 롯데는 사용자가 정했고 카드다모아는 robots.txt가 없다(404).
# 워크플로에 다른 이름을 잘못 넣지 않게 이 목록 밖은 받지 않는다
ROBOTS_IGNORED = ("samsung", "ibk", "kakaobank", "lotte", "carddamoa")
KST = timezone(timedelta(hours=9))
# 색인 카드를 고르는 곳. 카드다모아는 카드사가 아니라 추천 표시다
READ_ISSUERS = set(PLANS) - {"carddamoa"}


@dataclass(frozen=True)
class Target:
    issuer: str
    card_id: str | None  # None이면 카드사 상품 목록이나 공지
    source_id: str
    kind: str
    url: str
    browser: bool


def targets(root: Path, interval: int = 30, issuers: set[str] | None = None) -> list[Target]:
    """자동으로 받을 주소. method가 api나 browser이고 interval_days가 interval 이하인 카드사만 고른다."""
    cat = load_catalog(root)
    out = []
    for iid, loaded in sorted(cat.issuers.items()):
        c = loaded.issuer.collect
        if c is None or c.method not in ("api", "browser") or c.interval_days > interval:
            continue
        if issuers and iid not in issuers:
            continue
        browser = c.method == "browser"
        out.append(Target(iid, None, "list", "list", c.list_url, browser))
        if c.notice_url:
            out.append(Target(iid, None, "notice", "notice", c.notice_url, browser))
        for card in sorted((lc.card for lc in cat.cards.values() if lc.card.issuer == iid), key=lambda c: c.id):
            for s in card.sources:
                out.append(Target(iid, card.id, s.id, s.kind, s.url, browser and s.kind not in PLAIN_KINDS))
    return out


def raw_path(t: Target, day: date, body: bytes, content_type: str) -> str:
    """저장할 경로. 같은 날 같은 원문을 다시 받아도 이름이 같아 덮어쓰기만 된다."""
    sha = hashlib.sha256(body).hexdigest()
    ext = "pdf" if body.startswith(b"%PDF-") else "json" if "json" in content_type else "html"
    return f"{day:%Y-%m-%d}/{t.issuer}/{t.card_id or '_issuer'}/{t.source_id}-{sha[:12]}.{ext}"


def allowed(url: str, robots_txt: str | None) -> bool:
    """robots.txt가 막은 주소는 받지 않는다. robots.txt가 없으면 허용이다."""
    if robots_txt is None:
        return True
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(robots_txt.splitlines())
    return rp.can_fetch(AGENT, url)


def _get(url: str, form: dict[str, str] | None = None, json_body: dict | None = None) -> tuple[bytes, str]:
    """연결이 잠깐 끊긴 것은 모두 세 번까지 묻는다. 서버가 HTTP로 답한 것은 다시 물어도 같아 그대로 던진다.

    60초 시간 초과는 다시 묻지 않는다. 응답 없는 곳을 세 번 기다리면 원문 받기 20분 제한에 걸릴 수 있다.

    2026-10-02 GitHub 수집에서 실행마다 다른 카드사 하나가 연결 실패였다. 호스트의 robots.txt가 한 번 끊기면 그 호스트 주소가 모두 실패로 남는다.
    """
    headers = {"User-Agent": USER_AGENT}
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    if json_body is not None:
        data, headers["Content-Type"] = json.dumps(json_body).encode(), "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    for attempt in range(TRIES):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read(), r.headers.get("Content-Type", "")
        except urllib.error.HTTPError:
            raise
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            timed_out = isinstance(e, TimeoutError) or isinstance(getattr(e, "reason", None), TimeoutError)
            if timed_out or attempt == TRIES - 1:
                raise
            time.sleep(10 * (attempt + 1))


def _robots(url: str) -> str | None:
    """401, 403, 429가 아닌 4xx면 robots.txt가 없는 것으로 본다. 그 밖의 오류는 그대로 던져 허용을 모르는 것으로 센다."""
    parts = urlsplit(url)
    try:
        body, _ = _get(f"{parts.scheme}://{parts.netloc}/robots.txt")
    except urllib.error.HTTPError as e:
        # robotparser는 401, 403을 전부 막힌 것으로 읽지만 건너뜀으로 세면 실패 메일 없이 빠진다
        # 2026-10-01 GitHub 서버에만 403을 준 카드사가 있었다. 연결이 끊긴 롯데처럼 실패로 센다
        # 429는 요청이 많다며 거절한 것이라 robots.txt가 없는 것이 아니다
        if e.code not in (401, 403, 429) and 400 <= e.code < 500:
            return None
        raise
    return body.decode("utf-8", "replace")


def _robots_allow(url: str, robots: dict[str, str | None | Exception]) -> bool:
    """robots.txt가 허용하면 True, 막으면 False. robots.txt를 모르는 호스트는 그 까닭을 던진다. 롯데처럼 연결을 끊는 곳"""
    host = urlsplit(url).netloc
    if host not in robots:
        try:
            robots[host] = _robots(url)
        except Exception as e:  # noqa: BLE001 받지 못한 까닭을 기억해 같은 호스트에 다시 묻지 않는다
            robots[host] = e
    if isinstance(robots[host], Exception):
        raise robots[host]
    return allowed(url, robots[host])


class Disallowed(Exception):
    """robots.txt가 막은 공시 주소. 공시는 카드사 하나를 통째로 받아야 해서 그 카드사를 건너뛴다."""


def _open_browser(stack: ExitStack):
    from playwright.sync_api import sync_playwright

    browser = stack.enter_context(sync_playwright()).chromium.launch()
    stack.callback(browser.close)
    # 우리카드 화면 스크립트는 브라우저 이름을 읽어 암호화 모듈을 고른다. 수집기 이름만 주면 목록 요청을 보내지 못한다.
    # 실제 브라우저 이름을 그대로 두고 뒤에 수집기 이름을 붙여 누가 받는지 밝힌다. 2026-10-04
    probe = browser.new_page()
    ua = probe.evaluate("navigator.userAgent")
    probe.close()
    return browser.new_page(user_agent=f"{ua} {USER_AGENT}")


def _captured(page, req: Request) -> tuple[bytes, str]:
    """브라우저로 화면을 열고 주소에 req.capture가 든 응답을 돌려준다. script가 있으면 돌린 뒤의 응답이다."""

    def wanted(r) -> bool:
        return req.capture in r.url

    with page.expect_response(wanted, timeout=60_000) as first:
        page.goto(req.url, wait_until="load", timeout=60_000)
    resp = first.value
    if req.script:
        # 우리카드 화면은 처음에 목록을 두 번 부른다. 화면이 조용해진 뒤에 돌려야 스크립트가 부른 응답을 잡는다
        from playwright.sync_api import TimeoutError as PlaywrightTimeout

        try:
            page.wait_for_load_state("networkidle", timeout=15_000)
        except PlaywrightTimeout:
            pass  # 요청이 끊이지 않는 화면은 15초 뒤 그대로 간다
        with page.expect_response(wanted, timeout=60_000) as again:
            page.evaluate(req.script)
        resp = again.value
    if resp.status >= 400:
        raise urllib.error.HTTPError(req.url, resp.status, "", {}, None)
    return resp.body(), resp.headers.get("content-type", "")


def fetch_disclosure(issuer: str, today: date, allow: Callable[[str], bool]) -> list[tuple[Target, bytes, str]]:
    """한 카드사의 공시 응답을 모두 받는다. 하나라도 실패하면 오류를 던져 아무것도 저장하지 않게 한다.

    쪽 하나가 빠진 색인은 그 쪽의 카드가 사라진 것으로 보여 단종으로 잘못 잡힌다. 그래서 다 받은 뒤에만 저장한다.
    """
    got = []
    with ExitStack() as stack:
        page = None

        def fetch(req: Request) -> bytes:
            nonlocal page
            if not allow(req.url):
                raise Disallowed(req.url)
            try:
                if req.capture:
                    page = page or _open_browser(stack)
                    body, ctype = _captured(page, req)
                else:
                    body, ctype = _get(req.url, req.form, req.json)
            finally:
                time.sleep(DELAY_SECONDS)
            got.append((Target(issuer, None, req.source_id, "disclosure", req.url, bool(req.capture)), body, ctype))
            return body

        PLANS[issuer](fetch, today)
    return got


def index_targets(
    issuer: str, got: list[tuple[Target, bytes, str]], known: list[KnownCard], today: date, limit: int, browser: bool
) -> list[Target]:
    """받은 공시 응답으로 색인 행을 다시 만들어, 카탈로그 밖 카드의 상품 페이지와 최신 PDF 주소를 고른다. 작업 008 5단계.

    수집기는 Databricks 색인 표를 읽지 않는다. 같은 읽기 함수와 저장소 catalog/로 같은 판단을 한다.
    card_id는 비운다. 카탈로그 id가 아직 없고 색인의 card_id는 Databricks가 정한다. limit은 카드 수이고 0이면 모두다.
    """
    merged, _ = merge_rows([r for t, body, _ in got for r in read(issuer, t.source_id, body)])
    out: list[Target] = []
    cards = 0
    for r, (_, in_catalog) in zip(merged, card_ids(merged, known)):
        if in_catalog or not collectable(r, today) or not (r.page_url or r.pdf_urls):
            continue
        tag = "ix-" + key_id(issuer, row_key(r)).split("-", 1)[1]
        if r.page_url:
            out.append(Target(issuer, None, f"{tag}-page", "product_page", r.page_url, browser))
        if r.pdf_urls:
            # PDF 목록은 최신이 앞이다. 옛 판 PDF는 새 카드 초안에 쓰지 않는다
            out.append(Target(issuer, None, f"{tag}-pdf", "manual_pdf", r.pdf_urls[0], False))
        cards += 1
        if cards == limit:
            break
    return out


def save(
    out: Path,
    manifest: TextIO,
    t: Target,
    body: bytes,
    content_type: str,
    now: datetime,
    screenshot: bytes | None = None,
) -> str:
    """원문을 날짜별 폴더에 쓰고 목록 파일에 한 줄 더한다. 브론즈는 이 목록 파일을 읽는다.

    스크린샷은 원문과 같은 이름의 .png로 둔다. 목록 파일에는 칸을 더하지 않고 글 뽑기가 같은 이름을 찾는다. 작업 008 8단계.
    """
    rel = raw_path(t, now.date(), body, content_type)
    (out / rel).parent.mkdir(parents=True, exist_ok=True)
    (out / rel).write_bytes(body)
    if screenshot is not None:
        (out / rel).with_suffix(".png").write_bytes(screenshot)
    line = {**asdict(t), "path": rel, "fetched_at": now.isoformat(), "content_type": content_type}
    line["sha256"] = hashlib.sha256(body).hexdigest()
    manifest.write(json.dumps(line, ensure_ascii=False) + "\n")
    return rel


def _manual(root: Path, card_id: str, source_id: str) -> Target:
    """robots.txt로 막은 카드사는 사람이 받아 온 파일을 쓴다. 카드와 원문 id로 대상을 찾는다."""
    card = load_catalog(root).cards[card_id].card
    source = {s.id: s for s in card.sources}[source_id]
    return Target(card.issuer, card.id, source.id, source.kind, source.url, False)


class Fetcher:
    """원문 주소를 차례로 받아 저장한다. robots.txt 확인, 브라우저, 403과 429와 세 번 끊김에 멈추기를 여기서 한다."""

    def __init__(
        self,
        out_dir: Path,
        manifest: TextIO,
        now: datetime,
        ignore: list[str],
        robots: dict[str, str | None | Exception],
        stack: ExitStack,
    ) -> None:
        self.out_dir, self.manifest, self.now, self.ignore, self.stack = out_dir, manifest, now, ignore, stack
        self.robots = robots  # 호스트마다 robots.txt. 공시 받기와 함께 쓴다
        self.blocked: set[str] = set()
        self.drops: dict[str, int] = {}
        self.page = None
        self.saved = self.skipped = self.failed = 0

    def fetch(self, t: Target) -> None:
        if t.issuer in self.blocked:
            self.failed += 1
            print(f"멈춤 {t.issuer} {t.card_id or '-'} {t.source_id}")
            return
        try:
            if t.issuer not in self.ignore and not _robots_allow(t.url, self.robots):
                self.skipped += 1
                print(f"건너뜀 {t.issuer} {t.card_id or '-'} {t.source_id}")
                return
            if t.browser:
                body, ctype, shot = self._browser(t)
            else:
                (body, ctype), shot = _get(t.url), None
        except Exception as e:  # noqa: BLE001 한 곳이 실패해도 나머지는 받는다
            self.failed += 1
            code = f" {e.code}" if isinstance(e, urllib.error.HTTPError) else ""
            print(f"실패 {t.issuer} {t.card_id or '-'} {t.source_id}: {type(e).__name__}{code}")
            # 브라우저로 연 주소가 끊기면 Playwright 오류로 온다. 이것도 끊김으로 센다
            network = isinstance(e, (urllib.error.URLError, TimeoutError, ConnectionError)) or type(
                e
            ).__module__.startswith("playwright")
            if e is not self.robots.get(urlsplit(t.url).netloc):
                # 기억해 둔 robots.txt 실패는 새 연결이 아니라 끊김 수를 늘리지도 되돌리지도 않는다
                self.drops[t.issuer] = self.drops.get(t.issuer, 0) + 1 if network and not code else 0
            if (isinstance(e, urllib.error.HTTPError) and e.code in BLOCK_CODES) or self.drops.get(
                t.issuer, 0
            ) >= DROPS:
                self.blocked.add(t.issuer)
            return
        finally:
            time.sleep(DELAY_SECONDS)
        self.drops[t.issuer] = 0
        save(self.out_dir, self.manifest, t, body, ctype, self.now, shot)
        self.saved += 1

    def _browser(self, t: Target) -> tuple[bytes, str, bytes | None]:
        from playwright.sync_api import Error as PlaywrightError
        from playwright.sync_api import TimeoutError as PlaywrightTimeout

        if self.page is None:
            from playwright.sync_api import sync_playwright

            browser = self.stack.enter_context(sync_playwright()).chromium.launch()
            self.stack.callback(browser.close)
            self.page = browser.new_page(user_agent=USER_AGENT)
        resp = self.page.goto(t.url, wait_until="load", timeout=60_000)
        # 거절 화면을 원문으로 저장하면 바뀐 원문으로 잡혀 추출 요금이 난다. 다른 받기와 같이 오류로 센다
        if resp is not None and resp.status >= 400:
            raise urllib.error.HTTPError(t.url, resp.status, "", {}, None)
        try:
            self.page.wait_for_load_state("networkidle", timeout=15_000)
        except PlaywrightTimeout:
            pass  # 동영상을 넣은 페이지는 요청이 끊이지 않아 조용해지지 않는다. 현대카드 상품 목록
        html, shot = self.page.content(), None
        # 혜택을 이미지로 넣은 상품 페이지는 화면을 찍어 글 뽑기가 해석하게 한다. 작업 008 설계 4절
        if t.kind == "product_page" and image_heavy(html):
            try:
                self._scroll(PlaywrightTimeout)
                # 저장하는 HTML로 기준을 다시 잰다. 스크롤로 글이 나타나 기준을 벗어나면 HTML 글을 쓰게 찍지 않는다
                html = self.page.content()
                if image_heavy(html):
                    shot = self.page.screenshot(full_page=True)
            except PlaywrightError as e:
                # 찍기가 실패해도 받은 HTML은 남긴다. 끊김으로 세지 않는다
                print(f"찍기 실패 {t.issuer} {t.card_id or '-'} {t.source_id}: {type(e).__name__}")
        # 브라우저가 돌려준 글은 UTF-8이다. meta의 charset은 원래 페이지 것이라 머리에 적어 이긴다
        return html.encode("utf-8"), "text/html; charset=utf-8", shot

    def _scroll(self, timeout: type[Exception]) -> None:
        """페이지 끝까지 천천히 내렸다 올린다. 스크롤해야 나타나는 내용을 띄워야 전체 화면을 찍어도 비지 않는다.

        2026-10-04 현대와 카카오뱅크 상품 페이지는 내리지 않고 찍으면 가운데가 비었다.
        ponytail: 한 번에 800픽셀씩 60번까지다. 더 긴 페이지는 아래가 빌 수 있다.
        """
        height = self.page.evaluate("document.body.scrollHeight")
        for y in range(0, min(height, 800 * 60), 800):
            self.page.evaluate(f"window.scrollTo(0, {y})")
            self.page.wait_for_timeout(300)
        try:
            self.page.wait_for_load_state("networkidle", timeout=15_000)
        except timeout:
            pass  # 스크롤로 불러온 이미지를 기다린다. 조용해지지 않는 페이지는 그대로 찍는다
        self.page.evaluate("window.scrollTo(0, 0)")
        self.page.wait_for_timeout(500)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.pipeline.collect")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--interval", type=int, choices=[14, 30], default=30)
    ap.add_argument("--issuer", action="append", help="이 카드사만 받는다. 여러 번 쓸 수 있다")
    ap.add_argument(
        "--exclude", action="append", default=[], help="이 카드사는 받지 않는다. GitHub 서버를 막는 카드사에 쓴다"
    )
    ap.add_argument(
        "--ignore-robots",
        action="append",
        default=[],
        choices=ROBOTS_IGNORED,
        help="이 카드사는 robots.txt를 묻지 않는다. 사용자가 정한 삼성, IBK, 카카오뱅크, 롯데와 robots.txt가 없는 카드다모아만 된다",
    )
    ap.add_argument("--disclosure", action="store_true", help="카드사 상품공시실만 받는다. 작업 008")
    ap.add_argument(
        "--index-cards",
        type=int,
        help="--disclosure와 함께 카드사마다 카탈로그 밖 카드를 이만큼 받는다. 0은 모두다. 주지 않으면 받지 않는다",
    )
    ap.add_argument("--add", type=Path, help="사람이 받아 온 파일을 더한다. --card와 --source를 함께 쓴다")
    ap.add_argument("--card")
    ap.add_argument("--source")
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    now = datetime.now(UTC)
    manifest = args.out / "manifests" / f"manifest-{now:%Y%m%dT%H%M%SZ}.jsonl"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    if args.add:
        body = args.add.read_bytes()
        ctype = "application/pdf" if body.startswith(b"%PDF-") else "text/html"
        with manifest.open("a", encoding="utf-8") as out:
            print(save(args.out, out, _manual(args.root, args.card, args.source), body, ctype, now))
        return 0

    robots: dict[str, str | None | Exception] = {}
    saved = skipped = failed = excluded = 0
    if args.disclosure:
        today = now.astimezone(KST).date()  # 3년 기준은 한국 날짜로 센다. 새벽 수집이면 UTC 날짜가 하루 앞이다
        pending: list[Target] = []
        if args.index_cards is not None:
            cat = load_catalog(args.root)
            known = [
                KnownCard(c.card.id, c.card.issuer, (c.card.name, *c.card.search_names), tuple(c.card.product_codes))
                for c in cat.cards.values()
            ]
            browsers = {
                i for i, li in cat.issuers.items() if li.issuer.collect and li.issuer.collect.method == "browser"
            }
        with ExitStack() as stack, manifest.open("w", encoding="utf-8") as out:
            for issuer in sorted(PLANS):
                if args.issuer and issuer not in args.issuer:
                    continue
                if issuer in args.exclude:
                    excluded += 1
                    continue
                ignore = issuer in args.ignore_robots
                try:
                    got = fetch_disclosure(
                        issuer, today, lambda url, ignore=ignore: ignore or _robots_allow(url, robots)
                    )
                except Disallowed:
                    skipped += 1
                    print(f"건너뜀 {issuer} 공시")
                    continue
                except Exception as e:  # noqa: BLE001 한 카드사가 실패해도 나머지 카드사는 받는다
                    failed += 1
                    code = f" {e.code}" if isinstance(e, urllib.error.HTTPError) else ""
                    print(f"실패 {issuer} 공시: {type(e).__name__}{code}")
                    continue
                for t, body, ctype in got:
                    save(args.out, out, t, body, ctype, now)
                # 강제로 끊겨도 목록 파일에 한 카드사의 줄이 반만 남지 않게 카드사마다 내보낸다
                out.flush()
                print(f"공시 {issuer} 응답 {len(got)}개")
                saved += len(got)
                if args.index_cards is not None and issuer in READ_ISSUERS:
                    found = index_targets(issuer, got, known, today, args.index_cards, issuer in browsers)
                    print(f"색인 카드 {issuer} {len(found)}개")
                    pending += found
            fetcher = Fetcher(args.out, out, now, args.ignore_robots, robots, stack)
            for t in pending:
                fetcher.fetch(t)
        saved += fetcher.saved
        skipped += fetcher.skipped
        failed += fetcher.failed
        print(f"저장 {saved}, robots.txt로 건너뜀 {skipped}, 실패 {failed}, 뺌 {excluded}")
        return 1 if failed else 0

    with ExitStack() as stack, manifest.open("w", encoding="utf-8") as out:
        fetcher = Fetcher(args.out, out, now, args.ignore_robots, robots, stack)
        for t in targets(args.root, args.interval, set(args.issuer or []) or None):
            if t.issuer in args.exclude:
                excluded += 1
                continue
            fetcher.fetch(t)
    saved, skipped, failed = fetcher.saved, fetcher.skipped, fetcher.failed
    print(f"저장 {saved}, robots.txt로 건너뜀 {skipped}, 실패 {failed}, 뺌 {excluded}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
