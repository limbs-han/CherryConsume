"""마이그레이션과 카탈로그 맞추기. 작업 005 계획 슬라이스 1의 2, 3단계"""

import psycopg
import pytest

from cherry_api.catalog_sync import sync_catalog
from cherry_api.db import migrate


def test_migrations_run_once(client, db):
    assert migrate(db) == []


def test_same_card_twice_is_refused(client, db):
    # E21. 가족카드도 같은 카드 한 장이다
    user = db.execute("INSERT INTO users DEFAULT VALUES RETURNING id").fetchone()["id"]
    db.execute("INSERT INTO user_cards (user_id, card_id) VALUES (%s, 'shinhan-mrlife')", (user,))
    with pytest.raises(psycopg.errors.UniqueViolation):
        db.execute("INSERT INTO user_cards (user_id, card_id) VALUES (%s, 'shinhan-mrlife')", (user,))


def test_removed_card_can_be_added_again(client, db):
    user = db.execute("INSERT INTO users DEFAULT VALUES RETURNING id").fetchone()["id"]
    db.execute("INSERT INTO user_cards (user_id, card_id, removed_at) VALUES (%s, 'shinhan-mrlife', now())", (user,))
    db.execute("INSERT INTO user_cards (user_id, card_id) VALUES (%s, 'shinhan-mrlife')", (user,))


def counts(db) -> tuple[int, int, int]:
    one = db.execute(
        "SELECT (SELECT count(*) FROM issuers) AS i, (SELECT count(*) FROM cards) AS c,"
        " (SELECT count(*) FROM card_revisions) AS r"
    ).fetchone()
    return one["i"], one["c"], one["r"]


def test_catalog_is_in_tables(client, db):
    # 카드사 10곳, 카드 20장, 개정 22개. 2026-10-01 카탈로그
    catalog = client.app.state.catalog
    assert counts(db) == (len(catalog.issuers), len(catalog.cards), 22)
    assert counts(db) == (10, 20, 22)


def test_catalog_sync_twice_changes_nothing(client, db):
    before = db.execute("SELECT id, rules_sha256 FROM card_revisions ORDER BY id").fetchall()
    sync_catalog(db, client.app.state.catalog)
    assert db.execute("SELECT id, rules_sha256 FROM card_revisions ORDER BY id").fetchall() == before


def test_changed_revision_adds_a_row(client, db):
    # E18. 결제가 가리키는 개정 행은 그때 계산에 쓴 규칙 그대로 남는다. 고친 내용은 새 행이다
    row = db.execute(
        "SELECT id, effective_from, rules_sha256 FROM card_revisions"
        " WHERE card_id = 'shinhan-mrlife' ORDER BY effective_from DESC"
    ).fetchone()
    db.execute("UPDATE card_revisions SET rules_sha256 = 'old', rules = '{}' WHERE id = %s", (row["id"],))
    sync_catalog(db, client.app.state.catalog)
    rows = db.execute(
        "SELECT id, rules_sha256, rules FROM card_revisions WHERE card_id = 'shinhan-mrlife' AND effective_from = %s"
        " ORDER BY id",
        (row["effective_from"],),
    ).fetchall()
    assert [(r["id"] == row["id"], r["rules_sha256"]) for r in rows] == [(True, "old"), (False, row["rules_sha256"])]
    assert rows[1]["rules"]["tiers"] == [0, 300000, 500000, 1000000]
    db.rollback()


def test_changed_migration_stops_the_server(client, db, tmp_path, monkeypatch):
    import cherry_api.db as dbmod

    for f in dbmod.MIGRATIONS.glob("*.sql"):
        (tmp_path / f.name).write_text(f.read_text(encoding="utf-8") + "\n-- 고침\n", encoding="utf-8")
    monkeypatch.setattr(dbmod, "MIGRATIONS", tmp_path)
    with pytest.raises(RuntimeError, match="이미 돌린 마이그레이션이 바뀌었다"):
        migrate(db)


def test_migration_number_rules(client, db, tmp_path, monkeypatch):
    import cherry_api.db as dbmod

    for f in dbmod.MIGRATIONS.glob("*.sql"):
        (tmp_path / f.name).write_text(f.read_text(encoding="utf-8"), encoding="utf-8")
    monkeypatch.setattr(dbmod, "MIGRATIONS", tmp_path)
    (tmp_path / "000_late.sql").write_text("SELECT 1;", encoding="utf-8")
    with pytest.raises(RuntimeError, match="앞 번호"):
        migrate(db)
    (tmp_path / "000_late.sql").unlink()
    (tmp_path / "001_twin.sql").write_text("SELECT 1;", encoding="utf-8")
    with pytest.raises(RuntimeError, match="번호가 겹친다"):
        migrate(db)


def test_payment_catalog_tables(client, db):
    cat = client.app.state.catalog
    n = db.execute(
        "SELECT (SELECT count(*) FROM categories) AS c, (SELECT count(*) FROM merchants) AS m,"
        " (SELECT count(*) FROM payment_methods) AS p"
    ).fetchone()
    assert (n["c"], n["m"], n["p"]) == (len(cat.categories), len(cat.merchants), len(cat.payment_methods))


def test_moved_alias_follows_the_catalog(client, db):
    db.execute("UPDATE merchant_aliases SET merchant_key = 'emart' WHERE alias = 'gs25'")
    sync_catalog(db, client.app.state.catalog)
    row = db.execute("SELECT merchant_key FROM merchant_aliases WHERE alias = 'gs25'").fetchone()
    assert row["merchant_key"] == "gs25"
    db.rollback()


def test_revision_changed_and_changed_back(client, db):
    # 내용을 A에서 B로 고쳤다가 A로 되돌리면 행은 A와 B 둘이고, 결제는 지금 내용 A의 행을 가리킨다
    from datetime import date

    from cherry_api.catalog_sync import revision_ids

    a = client.app.state.revision_ids[("shinhan-mrlife", date(2026, 7, 15))]
    row = db.execute("SELECT * FROM card_revisions WHERE id = %s", (a,)).fetchone()
    db.execute(
        "INSERT INTO card_revisions (card_id, effective_from, rules, rules_sha256, schema_version)"
        " VALUES ('shinhan-mrlife', '2026-07-15', '{}', 'b', 2)"
    )
    sync_catalog(db, client.app.state.catalog)
    assert revision_ids(db, client.app.state.catalog)[("shinhan-mrlife", date(2026, 7, 15))] == row["id"]
    db.rollback()


def test_every_table_has_row_security(client, db):
    # 설계 5h. Supabase의 Data API가 다시 켜져도 표의 행이 보이지 않는다. 새 표도 그 마이그레이션에서 켠다
    rows = db.execute(
        "SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace"
        " WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity ORDER BY 1"
    ).fetchall()
    assert [r["relname"] for r in rows] == []
