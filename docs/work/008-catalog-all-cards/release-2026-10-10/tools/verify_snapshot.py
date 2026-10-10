"""승인 사본 지문과 로컬 승인 검사를 확인하고 앱 시험용 사본을 만든다."""

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import yaml
from cherry_core.pipeline.approve import apply_changes, new_card_conflicts


def main():
    root = Path.cwd().resolve()
    source = Path(__file__).resolve().parents[1]
    manifest = json.loads(
        (source / "approval-manifest.json").read_text(encoding="utf-8")
    )
    gold = {
        p.relative_to(root / "catalog").as_posix(): p.read_text(encoding="utf-8")
        for p in (root / "catalog").rglob("*.yaml")
    }
    assert gold, "저장소 루트에서 실행해야 한다"
    incoming = {}
    for row in manifest["shared_files"] + manifest["cards"]:
        group = row.get("card_id", "shared")
        text = (source / "incoming" / group / "catalog" / row["path"]).read_text(
            encoding="utf-8"
        )
        assert hashlib.sha256(text.encode("utf-8")).hexdigest() == row["sha256"], row[
            "path"
        ]
        incoming[row["path"]] = text
    staged, _ = apply_changes(
        gold, {r["path"]: incoming[r["path"]] for r in manifest["shared_files"]}
    )
    for row in manifest["cards"]:
        text = incoming[row["path"]]
        issuer = yaml.safe_load(text)["issuer"]
        assert not new_card_conflicts(text, staged, issuer, row["path"]), row["card_id"]
        staged[row["path"]] = text
    merged, _ = apply_changes(gold, incoming)
    target = root / "tmp/release-card-expansion/handoff/catalog"
    for rel, text in merged.items():
        file = target / rel
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text, encoding="utf-8", newline="\n")
    subprocess.run(
        [sys.executable, "-m", "cherry_core.catalog", "check", "--root", str(target)],
        check=True,
    )
    subprocess.run(
        [
            sys.executable,
            "-m",
            "cherry_core.catalog",
            "json",
            "--root",
            str(target),
            "--out",
            str(target.parent / "catalog.json"),
        ],
        check=True,
    )
    print(
        json.dumps(
            {
                "new_cards": len(manifest["cards"]),
                "verified_files": len(incoming),
                "operational_writes": 0,
            }
        )
    )


if __name__ == "__main__":
    main()
