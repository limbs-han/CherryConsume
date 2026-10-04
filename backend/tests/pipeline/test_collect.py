"""수집 대상과 저장 경로. 설계 4절 2번. 네트워크는 쓰지 않는다."""

import json
from datetime import date

import pytest

from cherry_core.pipeline.collect import Target, allowed, main, raw_path, targets


def collect(method, interval_days=14):
    def edit(files):
        files["issuers/shinhan.yaml"]["collect"] = {
            "list_url": "https://www.shinhancard.com/list",
            "method": method,
            "interval_days": interval_days,
            "notice_url": "https://www.shinhancard.com/notice",
        }

    return edit


def test_api_issuer_lists_list_notice_and_card_sources(make_catalog):
    assert targets(make_catalog(collect("api"))) == [
        Target("shinhan", None, "list", "list", "https://www.shinhancard.com/list", False),
        Target("shinhan", None, "notice", "notice", "https://www.shinhancard.com/notice", False),
        Target("shinhan", "shinhan-test", "page", "product_page", "https://www.shinhancard.com/t", False),
    ]


def test_browser_issuer_opens_pages_in_browser(make_catalog):
    assert [t.browser for t in targets(make_catalog(collect("browser")))] == [True, True, True]


def test_blocked_and_manual_issuers_are_skipped(make_catalog):
    assert targets(make_catalog(collect("blocked"))) == []
    assert targets(make_catalog(collect("manual"))) == []


def test_interval_filter(make_catalog):
    root = make_catalog(collect("api", interval_days=30))
    assert targets(root, interval=14) == []
    assert len(targets(root, interval=30)) == 3


def test_issuer_filter(make_catalog):
    assert targets(make_catalog(collect("api")), issuers={"kb"}) == []


def test_raw_path():
    t = Target("shinhan", "shinhan-test", "page", "product_page", "https://x", False)
    # sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    assert (
        raw_path(t, date(2026, 10, 1), b"abc", "text/html") == "2026-10-01/shinhan/shinhan-test/page-ba7816bf8f01.html"
    )
    assert raw_path(t, date(2026, 10, 1), b"%PDF-1.7", "application/octet-stream").endswith(".pdf")
    issuer_list = Target("shinhan", None, "list", "list", "https://x", False)
    assert raw_path(issuer_list, date(2026, 10, 1), b"{}", "application/json").startswith(
        "2026-10-01/shinhan/_issuer/list-"
    )


def test_robots():
    robots = "User-agent: *\nDisallow: /card/\n"
    assert not allowed("https://x.com/card/1", robots)
    assert allowed("https://x.com/notice", robots)
    assert allowed("https://x.com/card/1", None)
    assert not allowed("https://x.com/a", "User-agent: cherryconsume-collector\nDisallow: /\n")


def test_add_manual_file_goes_to_same_layout_and_manifest(make_catalog, tmp_path, capsys):
    root, out = make_catalog(), tmp_path / "raw"
    page = tmp_path / "saved.html"
    page.write_bytes(b"<p>abc</p>")
    args = ["--root", str(root), "--out", str(out), "--add", str(page), "--card", "shinhan-test", "--source", "page"]
    assert main(args) == 0
    rel = capsys.readouterr().out.strip()
    assert (out / rel).read_bytes() == b"<p>abc</p>"
    [manifest] = (out / "manifests").glob("manifest-*.jsonl")
    line = json.loads(manifest.read_text(encoding="utf-8"))
    assert (line["issuer"], line["card_id"], line["source_id"], line["kind"], line["path"]) == (
        "shinhan",
        "shinhan-test",
        "page",
        "product_page",
        rel,
    )


def test_host_whose_robots_failed_is_not_asked_again(make_catalog, tmp_path, monkeypatch, capsys):
    # 롯데처럼 robots.txt 요청이 끊기면 60초씩 기다린다. 같은 호스트의 남은 주소는 다시 묻지 않고 실패로 센다
    import cherry_core.pipeline.collect as collect_module

    asked = []

    def broken_robots(url):
        asked.append(url)
        raise TimeoutError

    monkeypatch.setattr(collect_module, "_robots", broken_robots)
    monkeypatch.setattr(collect_module, "_get", lambda url: pytest.fail("robots.txt를 모르는 호스트에서 받았다"))
    monkeypatch.setattr(collect_module.time, "sleep", lambda s: None)
    root = make_catalog(collect("api"))
    assert main(["--root", str(root), "--out", str(tmp_path / "raw")]) == 1
    assert len(asked) == 1  # 신한 주소 세 곳이 모두 같은 호스트다
    assert "실패 0" not in capsys.readouterr().out


def _offline(monkeypatch, get):
    import cherry_core.pipeline.collect as collect_module

    monkeypatch.setattr(collect_module, "_get", get)
    monkeypatch.setattr(collect_module.time, "sleep", lambda s: None)


@pytest.mark.parametrize("code", [401, 403, 429])
def test_unconfirmed_robots_counts_as_failure(make_catalog, tmp_path, monkeypatch, capsys, code):
    # 2026-10-01 GitHub 서버에만 robots.txt를 403으로 준 카드사가 건너뜀으로 세어져 실패 메일 없이 빠졌다
    # 429는 요청이 많다며 거절한 것이라 robots.txt가 없는 것과 다르다
    import urllib.error

    def get(url):
        if url.endswith("/robots.txt"):
            raise urllib.error.HTTPError(url, code, "", {}, None)
        pytest.fail("허용을 확인하지 못한 호스트에서 받았다")

    _offline(monkeypatch, get)
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(tmp_path / "raw")]) == 1
    out = capsys.readouterr().out
    assert f"실패 shinhan - list: HTTPError {code}" in out
    assert "저장 0, robots.txt로 건너뜀 0, 실패 3" in out


def test_missing_robots_allows(make_catalog, tmp_path, monkeypatch, capsys):
    import urllib.error

    def get(url):
        if url.endswith("/robots.txt"):
            raise urllib.error.HTTPError(url, 404, "Not Found", {}, None)
        return b"<p>abc</p>", "text/html"

    _offline(monkeypatch, get)
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(tmp_path / "raw")]) == 0
    assert "저장 3, robots.txt로 건너뜀 0, 실패 0" in capsys.readouterr().out


def test_skipped_address_is_printed(make_catalog, tmp_path, monkeypatch, capsys):
    _offline(monkeypatch, lambda url: (b"User-agent: *\nDisallow: /\n", "text/plain"))
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(tmp_path / "raw")]) == 0
    out = capsys.readouterr().out
    assert "건너뜀 shinhan - list" in out
    assert "건너뜀 shinhan shinhan-test page" in out


def test_excluded_issuer_is_not_fetched(make_catalog, tmp_path, monkeypatch, capsys):
    root = make_catalog(collect("api"))
    _offline(monkeypatch, lambda url: pytest.fail("뺀 카드사에서 받았다"))
    assert main(["--root", str(root), "--out", str(tmp_path / "raw"), "--exclude", "shinhan"]) == 0
    # 뺀 개수를 요약에 찍어 기록에서 보이게 한다
    assert "저장 0, robots.txt로 건너뜀 0, 실패 0, 뺌 3" in capsys.readouterr().out

    # 다른 카드사를 빼면 신한은 그대로 받는다
    _offline(monkeypatch, lambda url: (b"<p>abc</p>", "text/html"))
    assert main(["--root", str(root), "--out", str(tmp_path / "raw2"), "--exclude", "kb"]) == 0
    assert "저장 3, robots.txt로 건너뜀 0, 실패 0, 뺌 0" in capsys.readouterr().out


class _Answer:
    def __init__(self):
        self.headers = {"Content-Type": "text/html"}

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self):
        return b"ok"


def _flaky(monkeypatch, failures):
    """앞의 failures번은 failures의 오류를 내고 그 뒤로는 답한다."""
    import cherry_core.pipeline.collect as collect_module

    calls = []

    def urlopen(req, timeout):
        calls.append(req.full_url)
        if len(calls) <= len(failures):
            raise failures[len(calls) - 1]
        return _Answer()

    monkeypatch.setattr(collect_module.urllib.request, "urlopen", urlopen)
    monkeypatch.setattr(collect_module.time, "sleep", lambda s: None)
    return collect_module, calls


def test_connection_error_is_retried(monkeypatch):
    # 2026-10-02 예약 실행에서 하나 7곳, 수동 실행에서 현대 5곳이 연결 실패였다. 호스트의 robots.txt 한 번 실패가 그 호스트 전체 실패가 된다
    import urllib.error

    collect_module, calls = _flaky(monkeypatch, [urllib.error.URLError("reset"), ConnectionResetError()])
    assert collect_module._get("https://x.com/robots.txt") == (b"ok", "text/html")
    assert len(calls) == 3


def test_gives_up_after_three_tries(monkeypatch):
    import urllib.error

    collect_module, calls = _flaky(monkeypatch, [urllib.error.URLError("reset")] * 5)
    with pytest.raises(urllib.error.URLError):
        collect_module._get("https://x.com/a")
    assert len(calls) == 3


def test_http_answer_is_not_retried(monkeypatch):
    # 서버가 403이나 404로 답한 것은 다시 물어도 같다
    import urllib.error

    forbidden = urllib.error.HTTPError("https://x.com/a", 403, "", {}, None)
    collect_module, calls = _flaky(monkeypatch, [forbidden])
    with pytest.raises(urllib.error.HTTPError):
        collect_module._get("https://x.com/a")
    assert len(calls) == 1


def test_timeout_is_not_retried(monkeypatch):
    # 응답 없는 곳을 60초씩 세 번 기다리면 원문 받기 20분 제한에 걸릴 수 있다
    import urllib.error

    for timeout in (TimeoutError(), urllib.error.URLError(TimeoutError())):
        collect_module, calls = _flaky(monkeypatch, [timeout])
        with pytest.raises((TimeoutError, urllib.error.URLError)):
            collect_module._get("https://x.com/a")
        assert len(calls) == 1


def _fake_plan(monkeypatch, plan):
    import cherry_core.pipeline.collect as collect_module

    monkeypatch.setattr(collect_module, "PLANS", {"kb": plan})


def _two_pages(fetch, today):
    from cherry_core.pipeline.disclosure import Request

    fetch(Request("disclosure-credit-p1", "https://card.kbcard.com/d", form={"pageCount": "1"}))
    fetch(Request("disclosure-credit-p2", "https://card.kbcard.com/d", form={"pageCount": "2"}))


def _manifest(out):
    (path,) = (out / "manifests").iterdir()
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def test_disclosure_saves_every_response_of_the_issuer(make_catalog, tmp_path, monkeypatch, capsys):
    _fake_plan(monkeypatch, _two_pages)
    forms = []

    def get(url, form=None, json_body=None):
        if url.endswith("/robots.txt"):
            return b"User-agent: *\nAllow: /\n", "text/plain"
        forms.append(form)
        return f"<p>{form['pageCount']}</p>".encode(), "text/html"

    _offline(monkeypatch, get)
    out = tmp_path / "raw"
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(out), "--disclosure"]) == 0
    assert forms == [{"pageCount": "1"}, {"pageCount": "2"}]
    lines = _manifest(out)
    assert [(x["issuer"], x["card_id"], x["source_id"], x["kind"]) for x in lines] == [
        ("kb", None, "disclosure-credit-p1", "disclosure"),
        ("kb", None, "disclosure-credit-p2", "disclosure"),
    ]
    assert len({x["fetched_at"] for x in lines}) == 1  # 색인 단계가 한 번에 받은 묶음으로 읽는다
    assert "저장 2, robots.txt로 건너뜀 0, 실패 0" in capsys.readouterr().out


def test_disclosure_failing_midway_saves_nothing(make_catalog, tmp_path, monkeypatch, capsys):
    import urllib.error

    _fake_plan(monkeypatch, _two_pages)

    def get(url, form=None, json_body=None):
        if url.endswith("/robots.txt"):
            return b"", "text/plain"
        if form["pageCount"] == "2":
            raise urllib.error.HTTPError(url, 429, "", {}, None)
        return b"<p>1</p>", "text/html"

    _offline(monkeypatch, get)
    out = tmp_path / "raw"
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(out), "--disclosure"]) == 1
    assert _manifest(out) == []
    assert "실패 kb 공시: HTTPError 429" in capsys.readouterr().out


def test_disclosure_blocked_by_robots_is_skipped(make_catalog, tmp_path, monkeypatch, capsys):
    _fake_plan(monkeypatch, _two_pages)
    _offline(monkeypatch, lambda url, form=None, json_body=None: (b"User-agent: *\nDisallow: /\n", "text/plain"))
    out = tmp_path / "raw"
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(out), "--disclosure"]) == 0
    assert _manifest(out) == []
    assert "건너뜀 kb 공시" in capsys.readouterr().out


def test_ignore_robots_does_not_ask_robots(make_catalog, tmp_path, monkeypatch, capsys):
    import cherry_core.pipeline.collect as collect_module

    _fake_plan(monkeypatch, _two_pages)
    monkeypatch.setattr(collect_module, "ROBOTS_IGNORED", ("kb", "shinhan"))

    def get(url, form=None, json_body=None):
        assert not url.endswith("/robots.txt"), "robots.txt를 물었다"
        return b"<p>x</p>", "text/html"

    _offline(monkeypatch, get)
    root, out = make_catalog(collect("api")), tmp_path / "raw"
    assert main(["--root", str(root), "--out", str(out), "--disclosure", "--ignore-robots", "kb"]) == 0
    assert len(_manifest(out)) == 2
    # 공시가 아닌 원문에도 같다
    assert main(["--root", str(root), "--out", str(tmp_path / "raw2"), "--ignore-robots", "shinhan"]) == 0
    assert "저장 3, robots.txt로 건너뜀 0, 실패 0" in capsys.readouterr().out


@pytest.mark.parametrize("code", [403, 429])
def test_refusal_stops_the_issuer_for_this_run(make_catalog, tmp_path, monkeypatch, capsys, code):
    import urllib.error

    asked = []

    def get(url):
        if url.endswith("/robots.txt"):
            return b"", "text/plain"
        asked.append(url)
        raise urllib.error.HTTPError(url, code, "", {}, None)

    _offline(monkeypatch, get)
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(tmp_path / "raw")]) == 1
    assert asked == ["https://www.shinhancard.com/list"]
    out = capsys.readouterr().out
    assert "멈춤 shinhan - notice" in out
    assert "저장 0, robots.txt로 건너뜀 0, 실패 3" in out


def test_three_dropped_connections_in_a_row_stop_the_issuer(make_catalog, tmp_path, monkeypatch, capsys):
    import urllib.error

    def edit(files):
        collect("api")(files)
        files["cards/shinhan/shinhan-test.yaml"]["sources"] += [
            {
                "id": f"extra{n}",
                "kind": "product_page",
                "url": f"https://www.shinhancard.com/x{n}",
                "fetched_at": date(2026, 9, 28),
            }
            for n in range(2)
        ]

    asked = []

    def get(url):
        if url.endswith("/robots.txt"):
            return b"", "text/plain"
        asked.append(url)
        raise urllib.error.URLError("reset")

    _offline(monkeypatch, get)
    assert main(["--root", str(make_catalog(edit)), "--out", str(tmp_path / "raw")]) == 1
    assert len(asked) == 3
    assert "멈춤 shinhan shinhan-test extra1" in capsys.readouterr().out


def test_capture_request_opens_one_browser_and_saves_as_browser(make_catalog, tmp_path, monkeypatch):
    import cherry_core.pipeline.collect as collect_module
    from cherry_core.pipeline.disclosure import Request

    def plan(fetch, today):
        fetch(Request("disclosure", "https://pc.wooricard.com/d", capture="list.json", script="go()"))
        fetch(Request("more", "https://pc.wooricard.com/e", capture="list.json"))

    monkeypatch.setattr(collect_module, "PLANS", {"woori": plan})
    opened = []
    monkeypatch.setattr(collect_module, "_open_browser", lambda stack: opened.append(1) or "page")
    monkeypatch.setattr(
        collect_module, "_captured", lambda page, req: (f"{page}:{req.source_id}".encode(), "application/json")
    )
    _offline(monkeypatch, lambda url, form=None, json_body=None: (b"", "text/plain"))
    out = tmp_path / "raw"
    assert main(["--root", str(make_catalog(collect("api"))), "--out", str(out), "--disclosure"]) == 0
    assert opened == [1]
    lines = _manifest(out)
    assert [(x["source_id"], x["browser"]) for x in lines] == [("disclosure", True), ("more", True)]
    assert (out / lines[0]["path"]).read_bytes() == b"page:disclosure"


def test_ignore_robots_takes_only_the_agreed_names(make_catalog, tmp_path):
    with pytest.raises(SystemExit):
        main(["--root", str(make_catalog(collect("api"))), "--out", str(tmp_path / "raw"), "--ignore-robots", "kb"])


def test_remembered_robots_failure_is_not_counted_as_three_drops(make_catalog, tmp_path, monkeypatch, capsys):
    # robots.txt 한 번의 끊김을 주소마다 끊김으로 세면 세 주소 만에 카드사 전체가 멈춘다
    import cherry_core.pipeline.collect as collect_module

    def edit(files):
        collect("api")(files)
        files["cards/shinhan/shinhan-test.yaml"]["sources"] += [
            {
                "id": f"extra{n}",
                "kind": "product_page",
                "url": f"https://www.shinhancard.com/x{n}",
                "fetched_at": date(2026, 9, 28),
            }
            for n in range(2)
        ]

    monkeypatch.setattr(collect_module, "_robots", lambda url: (_ for _ in ()).throw(TimeoutError()))
    _offline(monkeypatch, lambda url: pytest.fail("robots.txt를 모르는 호스트에서 받았다"))
    assert main(["--root", str(make_catalog(edit)), "--out", str(tmp_path / "raw")]) == 1
    out = capsys.readouterr().out
    assert "멈춤" not in out
    assert "실패 5" in out


FIXTURES = __import__("pathlib").Path(__file__).parent / "fixtures" / "disclosure"


def _got(issuer, source_id, name):
    body = (FIXTURES / name).read_bytes()
    return [(Target(issuer, None, source_id, "disclosure", "https://x", False), body, "text/html")]


def test_index_targets_take_page_and_latest_pdf_of_cards_outside_catalog():
    from cherry_core.pipeline.collect import index_targets

    got = index_targets("kb", _got("kb", "disclosure-credit-p1", "kb_disclosure.html"), [], date(2026, 10, 4), 0, False)
    # Fnsave는 2009년에 단종돼 받지 않는다. 알파원은 상품 페이지와 PDF를 받는다
    assert got == [
        Target(
            "kb",
            None,
            "ix-04587-page",
            "product_page",
            "https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=04587",
            False,
        ),
        Target(
            "kb",
            None,
            "ix-04587-pdf",
            "manual_pdf",
            "https://img2.kbcard.com/obj/card/download/04587__prdctOpmn_20210923.pdf",
            False,
        ),
    ]


def test_index_targets_skip_catalog_cards_and_stop_at_the_limit():
    from cherry_core.pipeline.collect import index_targets
    from cherry_core.pipeline.disclosure import KnownCard

    known = [KnownCard("kb-alpha", "kb", ("KB국민 알파원카드",), ())]
    kb = _got("kb", "disclosure-credit-p1", "kb_disclosure.html")
    assert index_targets("kb", kb, known, date(2026, 10, 4), 0, False) == []
    hana = _got("hana", "cards-check-241704050328506", "hana_cards.json")
    got = index_targets("hana", hana, [], date(2026, 10, 4), 1, True)
    # 하나는 수집 방법이 브라우저라 상품 페이지를 브라우저로 연다. 표본 두 장 가운데 한 장만 받는다
    assert [(t.source_id, t.browser) for t in got] == [("ix-94316-page", True)]


def test_disclosure_run_also_fetches_index_cards(make_catalog, tmp_path, monkeypatch, capsys):
    from cherry_core.pipeline.disclosure import Request

    kb = (FIXTURES / "kb_disclosure.html").read_bytes()

    def plan(fetch, today):
        fetch(Request("disclosure-credit-p1", "https://card.kbcard.com/d"))

    _fake_plan(monkeypatch, plan)
    asked = []

    def get(url, form=None, json_body=None):
        if url.endswith("/robots.txt"):
            return b"User-agent: *\nAllow: /\n", "text/plain"
        asked.append(url)
        return (
            (kb, "text/html")
            if url.endswith("/d")
            else (b"%PDF-1.4 x" if url.endswith(".pdf") else b"<p>card</p>", "text/html")
        )

    _offline(monkeypatch, get)
    out = tmp_path / "raw"
    root = make_catalog(collect("api"))
    assert main(["--root", str(root), "--out", str(out), "--disclosure", "--index-cards", "5"]) == 0
    lines = _manifest(out)
    assert [(x["source_id"], x["kind"], x["card_id"]) for x in lines] == [
        ("disclosure-credit-p1", "disclosure", None),
        ("ix-04587-page", "product_page", None),
        ("ix-04587-pdf", "manual_pdf", None),
    ]
    # 색인 카드는 묶음과 다른 받은 시각이 아니라 같은 실행의 시각으로 저장된다. 색인 단계는 kind로 공시만 고른다
    assert "색인 카드 kb 2개" in capsys.readouterr().out
    # 옵션을 주지 않으면 색인 카드는 받지 않는다
    assert main(["--root", str(root), "--out", str(tmp_path / "raw2"), "--disclosure"]) == 0
    assert [x["source_id"] for x in _manifest(tmp_path / "raw2")] == ["disclosure-credit-p1"]


def test_screenshot_is_saved_next_to_the_page_with_png_suffix(make_catalog, tmp_path, monkeypatch, capsys):
    import cherry_core.pipeline.collect as collect_module

    def fake_browser(self, t):
        return b"<p>page</p>", "text/html; charset=utf-8", b"\x89PNG fake"

    monkeypatch.setattr(collect_module.Fetcher, "_browser", fake_browser)
    _offline(monkeypatch, lambda url: (b"User-agent: *\nAllow: /\n", "text/plain"))
    out = tmp_path / "raw"
    assert main(["--root", str(make_catalog(collect("browser"))), "--out", str(out)]) == 0
    lines = _manifest(out)
    page = next(x for x in lines if x["source_id"] == "page")
    assert page["path"].endswith(".html")
    assert (out / page["path"][: -len(".html")]).with_suffix(".png").read_bytes() == b"\x89PNG fake"
    # 목록 파일에는 칸을 더하지 않는다. 글 뽑기가 같은 이름의 png를 찾는다
    assert "screenshot" not in page


class _PlaywrightError(Exception):
    pass


class _PlaywrightTimeout(_PlaywrightError):
    pass


@pytest.fixture(autouse=False)
def fake_playwright(monkeypatch):
    """테스트 환경에는 Playwright가 없다. 수집기가 가져다 쓰는 오류 두 가지만 흉내 낸다."""
    import sys
    from types import ModuleType

    api = ModuleType("playwright.sync_api")
    api.Error, api.TimeoutError = _PlaywrightError, _PlaywrightTimeout
    monkeypatch.setitem(sys.modules, "playwright", ModuleType("playwright"))
    monkeypatch.setitem(sys.modules, "playwright.sync_api", api)


class _Page:
    """스크롤 전과 뒤에 다른 HTML을 돌려주는 가짜 브라우저 쪽."""

    def __init__(self, before: str, after: str, fail: bool = False) -> None:
        self.htmls, self.fail, self.shots = [before, after], fail, 0

    def goto(self, url, **kw):
        return None

    def wait_for_load_state(self, *a, **kw):
        pass

    def content(self):
        return self.htmls.pop(0) if len(self.htmls) > 1 else self.htmls[0]

    def evaluate(self, js):
        if self.fail:
            raise _PlaywrightError("scroll failed")
        return 1600

    def wait_for_timeout(self, ms):
        pass

    def screenshot(self, **kw):
        self.shots += 1
        return b"png"


def _shoot(page):
    from types import SimpleNamespace

    from cherry_core.pipeline.collect import Fetcher

    f = Fetcher(None, None, None, [], {}, None)
    f.page = page
    return f._browser(SimpleNamespace(kind="product_page", url="https://x.test/card", issuer="kb", card_id="kb-a", source_id="page"))


HEAVY = '<img src="/a.png"><img src="/b.png"><img src="/c.png"><p>혜택</p>'


def test_screenshot_only_when_page_is_still_image_heavy_after_scrolling(fake_playwright):
    page = _Page(HEAVY, HEAVY + "<p>" + "가" * 2500 + "</p>")
    body, _, shot = _shoot(page)
    # 스크롤로 글이 나타나 기준에서 벗어나면 찍지 않고, 저장하는 HTML은 스크롤 뒤 것이다
    assert shot is None and page.shots == 0
    assert "가" * 2500 in body.decode()

    page = _Page(HEAVY, HEAVY + "<p>더</p>")
    body, _, shot = _shoot(page)
    assert shot == b"png" and "더" in body.decode()


def test_scroll_failure_keeps_the_html_without_screenshot(fake_playwright, capsys):
    body, _, shot = _shoot(_Page(HEAVY, HEAVY, fail=True))
    assert shot is None and body.decode() == HEAVY
    assert "찍기 실패" in capsys.readouterr().out
