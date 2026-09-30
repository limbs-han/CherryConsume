"""수집 대상과 저장 경로. 설계 4절 2번. 네트워크는 쓰지 않는다."""

import json
from datetime import date

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
