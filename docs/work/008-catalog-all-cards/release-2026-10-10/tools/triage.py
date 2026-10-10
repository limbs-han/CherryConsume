"""새 카드 초안 전수 구조 검사. 원문 대조 완료나 운영 승인을 뜻하지 않는다."""

import json
from collections import Counter
from pathlib import Path

import yaml
from cherry_core.catalog.check import check_rules, path_exists
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.models import CardFile, Rules
from cherry_core.catalog.resolve import resolve_card
from pydantic import ValidationError

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]


def read(name):
    return json.loads((BASE / name).read_text(encoding="utf-8-sig"))


def main():
    drafts = [
        json.loads(r[0]) for r in read("drafts-response.json")["result"]["data_array"]
    ]
    drafts += [json.loads(r[0]) for r in read("drafts-chunk1.json")["data_array"]]
    inventory = {r["card_id"]: r for r in read("inventory.json")}
    assert len(drafts) == len(inventory) == 2162
    catalog = load_catalog(ROOT / "tmp/card-ready-review/combined/catalog")
    results = []
    for draft in drafts:
        item = inventory[draft["card_id"]]
        raw = yaml.safe_load(draft["draft_yaml"])
        errors, warnings = [], []
        benefit_count = 0
        model_valid = False
        try:
            card = CardFile.model_validate(raw)
            issuer = catalog.issuers.get(card.issuer)
            revisions = resolve_card(
                card.model_dump(by_alias=True, exclude_unset=True),
                issuer.raw if issuer else None,
            )
            for revision in revisions:
                rules = Rules.model_validate(revision.data)
                benefit_count = len(rules.benefits)
                for level, path, message in check_rules(
                    rules, catalog, {s.id for s in card.sources}
                ):
                    (errors if level == "error" else warnings).append(
                        f"{revision.effective_from}/{path}: {message}"
                    )
            for question in card.open_questions:
                if not path_exists(raw, question.path):
                    errors.append(
                        f"open_questions: {question.path}가 가리키는 칸이 없다"
                    )
            model_valid = True
        except (ValidationError, ValueError, TypeError, KeyError) as error:
            errors.append(str(error))
        results.append(
            {
                **item,
                "current_errors": errors,
                "current_warnings": warnings,
                "resolved_benefit_count": benefit_count,
                "model_valid": model_valid,
                "source_review_complete": False,
                "approved": False,
            }
        )
    counts = {
        "draft_cards": len(results),
        "previous_no_problems": sum(not r.get("problems") for r in results),
        "current_no_errors": sum(not r["current_errors"] for r in results),
        "current_no_errors_with_benefits": sum(
            not r["current_errors"] and r["resolved_benefit_count"] > 0 for r in results
        ),
        "current_no_errors_or_warnings_with_benefits": sum(
            not r["current_errors"]
            and not r["current_warnings"]
            and r["resolved_benefit_count"] > 0
            for r in results
        ),
        "raw_zero_benefits": sum(r["benefit_count"] == 0 for r in results),
        "model_valid_zero_benefits": sum(
            r["model_valid"] and r["resolved_benefit_count"] == 0 for r in results
        ),
        "model_invalid": sum(not r["model_valid"] for r in results),
        "recommended": sum(r.get("recommended", False) for r in results),
        "approved": 0,
    }
    by_issuer = {}
    for issuer in sorted({r["issuer"] for r in results}):
        group = [r for r in results if r["issuer"] == issuer]
        by_issuer[issuer] = {
            "drafts": len(group),
            "no_errors_with_benefits": sum(
                not r["current_errors"] and r["resolved_benefit_count"] > 0
                for r in group
            ),
        }
    (BASE / "triage-results.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (BASE / "triage-counts.json").write_text(
        json.dumps({**counts, "by_issuer": by_issuer}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    simple = [
        r
        for r in results
        if not r["current_errors"]
        and r["resolved_benefit_count"] == 1
        and not r.get("recommended")
        and r.get("sale_status") == "on_sale"
    ]
    (BASE / "simple-candidates.json").write_text(
        json.dumps(simple, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(counts, ensure_ascii=False))
    print(
        "one-benefit candidates",
        len(simple),
        dict(Counter(r["issuer"] for r in simple)),
    )


if __name__ == "__main__":
    main()
