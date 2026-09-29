"""check와 format 명령."""

from cherry_core.catalog.__main__ import main

from .conftest import benefit


def test_check_passes_and_prints_summary(make_catalog, capsys):
    root = make_catalog()
    assert main(["check", "--root", str(root)]) == 0
    out = capsys.readouterr().out
    assert "카드 1장" in out
    assert "shinhan-test: 개정 1, 혜택 1, 문장으로 남긴 조건 0, 확인 필요 0" in out
    assert "오류 0" in out


def test_check_fails_on_error(make_catalog, capsys):
    root = make_catalog(lambda f: benefit(f).update(stack="pay"))
    assert main(["check", "--root", str(root)]) == 1
    assert "benefits[cafe-10].stack" in capsys.readouterr().out


def test_format_rewrites_non_canonical_files(make_catalog, capsys):
    root = make_catalog()
    path = root / "merchants.yaml"
    path.write_text("- {name: 스타벅스, key: starbucks, category: cafe, aliases: [스타벅스, 스벅]}\n", encoding="utf-8")
    assert main(["format", "--root", str(root)]) == 0
    assert "merchants.yaml" in capsys.readouterr().out
    assert main(["check", "--root", str(root)]) == 0
