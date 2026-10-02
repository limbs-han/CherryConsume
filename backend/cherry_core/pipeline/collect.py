"""카드사 원문 수집기. GitHub Actions와 개발자 PC에서 돈다. 설계 4절 2번.

카드사 파일의 collect와 카드 파일의 sources에 적힌 주소를 받아 날짜별 폴더에 원본 그대로 저장한다.
실행 기록은 공개 저장소에서 누구나 보므로 원문 내용은 찍지 않고 개수와 id만 찍는다.
브라우저가 필요한 카드사는 Playwright로 연다. 실행할 때 `uv run --with playwright`로 더한다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
import urllib.robotparser
from contextlib import ExitStack
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from typing import TextIO
from urllib.parse import urlsplit

from cherry_core.catalog.load import load_catalog

DEFAULT_ROOT = Path(__file__).resolve().parents[3] / "catalog"
AGENT = "cherryconsume-collector"
USER_AGENT = f"{AGENT} (+https://github.com/limbs-han/CherryConsume)"
DELAY_SECONDS = 2
TRIES = 3  # 연결이 끊겼을 때 묻는 횟수
PLAIN_KINDS = {"manual_pdf", "terms_pdf", "api"}


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


def _get(url: str) -> tuple[bytes, str]:
    """연결이 잠깐 끊긴 것은 모두 세 번까지 묻는다. 서버가 HTTP로 답한 것은 다시 물어도 같아 그대로 던진다.

    60초 시간 초과는 다시 묻지 않는다. 응답 없는 곳을 세 번 기다리면 원문 받기 20분 제한에 걸릴 수 있다.

    2026-10-02 GitHub 수집에서 실행마다 다른 카드사 하나가 연결 실패였다. 호스트의 robots.txt가 한 번 끊기면 그 호스트 주소가 모두 실패로 남는다.
    """
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
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


def save(out: Path, manifest: TextIO, t: Target, body: bytes, content_type: str, now: datetime) -> str:
    """원문을 날짜별 폴더에 쓰고 목록 파일에 한 줄 더한다. 브론즈는 이 목록 파일을 읽는다."""
    rel = raw_path(t, now.date(), body, content_type)
    (out / rel).parent.mkdir(parents=True, exist_ok=True)
    (out / rel).write_bytes(body)
    line = {**asdict(t), "path": rel, "fetched_at": now.isoformat(), "content_type": content_type}
    line["sha256"] = hashlib.sha256(body).hexdigest()
    manifest.write(json.dumps(line, ensure_ascii=False) + "\n")
    return rel


def _manual(root: Path, card_id: str, source_id: str) -> Target:
    """robots.txt로 막은 카드사는 사람이 받아 온 파일을 쓴다. 카드와 원문 id로 대상을 찾는다."""
    card = load_catalog(root).cards[card_id].card
    source = {s.id: s for s in card.sources}[source_id]
    return Target(card.issuer, card.id, source.id, source.kind, source.url, False)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.pipeline.collect")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--interval", type=int, choices=[14, 30], default=30)
    ap.add_argument("--issuer", action="append", help="이 카드사만 받는다. 여러 번 쓸 수 있다")
    ap.add_argument(
        "--exclude", action="append", default=[], help="이 카드사는 받지 않는다. GitHub 서버를 막는 카드사에 쓴다"
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
    with ExitStack() as stack, manifest.open("w", encoding="utf-8") as out:
        page = None
        for t in targets(args.root, args.interval, set(args.issuer or []) or None):
            if t.issuer in args.exclude:
                excluded += 1
                continue
            host = urlsplit(t.url).netloc
            try:
                if host not in robots:
                    try:
                        robots[host] = _robots(t.url)
                    except Exception as e:  # noqa: BLE001 받지 못한 까닭을 기억해 같은 호스트에 다시 묻지 않는다
                        robots[host] = e
                if isinstance(robots[host], Exception):
                    # robots.txt를 모르는 호스트는 허용 여부를 모르는 것이라 받지 않는다. 롯데처럼 연결을 끊는 곳
                    raise robots[host]
                if not allowed(t.url, robots[host]):
                    skipped += 1
                    print(f"건너뜀 {t.issuer} {t.card_id or '-'} {t.source_id}")
                    continue
                if t.browser:
                    if page is None:
                        from playwright.sync_api import TimeoutError as PlaywrightTimeout
                        from playwright.sync_api import sync_playwright

                        browser = stack.enter_context(sync_playwright()).chromium.launch()
                        stack.callback(browser.close)
                        page = browser.new_page(user_agent=USER_AGENT)
                    page.goto(t.url, wait_until="load", timeout=60_000)
                    try:
                        page.wait_for_load_state("networkidle", timeout=15_000)
                    except PlaywrightTimeout:
                        pass  # 동영상을 넣은 페이지는 요청이 끊이지 않아 조용해지지 않는다. 현대카드 상품 목록
                    # 브라우저가 돌려준 글은 UTF-8이다. meta의 charset은 원래 페이지 것이라 머리에 적어 이긴다
                    body, ctype = page.content().encode("utf-8"), "text/html; charset=utf-8"
                else:
                    body, ctype = _get(t.url)
            except Exception as e:  # noqa: BLE001 한 곳이 실패해도 나머지는 받는다
                failed += 1
                code = f" {e.code}" if isinstance(e, urllib.error.HTTPError) else ""
                print(f"실패 {t.issuer} {t.card_id or '-'} {t.source_id}: {type(e).__name__}{code}")
                continue
            finally:
                time.sleep(DELAY_SECONDS)
            save(args.out, out, t, body, ctype, now)
            saved += 1
    print(f"저장 {saved}, robots.txt로 건너뜀 {skipped}, 실패 {failed}, 뺌 {excluded}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
