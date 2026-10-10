"""출시 검토 사본을 합친다. 저장소 카탈로그와 운영 데이터는 고치지 않는다."""

import copy
import json
import shutil
from pathlib import Path

import yaml
from cherry_core.catalog.canonical import canonical_text

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
OUT = BASE / "combined"
# 2026-10-10 이어받은 뒤의 추가 조사 묶음. expand1, expand2처럼 이름 붙인 폴더를 차례로 합친다
EXPANDS = sorted(p.name for p in BASE.glob("expand[0-9]*") if p.is_dir())
CAT = OUT / "catalog"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def expand_school_exclusions(node):
    if isinstance(node, dict):
        for value in node.values():
            expand_school_exclusions(value)
    elif isinstance(node, list):
        if "education.school_fee" in node:
            for category in (
                "education.primary_secondary_fee",
                "education.kindergarten",
            ):
                if category not in node:
                    node.append(category)
        for value in node:
            expand_school_exclusions(value)


def strings(node):
    if isinstance(node, str):
        return {node}
    if isinstance(node, dict):
        return set().union(*(strings(v) for v in node.values())) if node else set()
    if isinstance(node, list):
        return set().union(*(strings(v) for v in node)) if node else set()
    return set()


def main():
    shutil.copytree(
        ROOT / "tmp/card-ready-review/combined/catalog", CAT, dirs_exist_ok=True
    )
    shutil.copytree(
        ROOT / "tmp/card-ready-review/combined/cases", OUT / "cases", dirs_exist_ok=True
    )
    candidates = read(ROOT / "tmp/card-ready-review/combined/candidates.json")
    candidates = [{**c, "group": "previous-ready"} for c in candidates]
    common_requests, group_results = [], []
    # expand1은 2026-10-10 이어받은 뒤의 추가 조사 묶음이다
    for group in ("hana8", "recommended-mixed", "recommended-others", *EXPANDS):
        folder = BASE / group
        if not (folder / "result.json").exists():
            continue
        results = read(folder / "result.json")
        group_results.extend({**r, "group": group} for r in results)
        ready_ids = {r["card_id"] for r in results if r["status"] == "ready"}
        for source in (folder / "catalog/cards").glob("*/*.yaml"):
            if source.stem not in ready_ids:
                continue
            rel = source.relative_to(folder / "catalog")
            target = CAT / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            data = yaml.safe_load(source.read_text(encoding="utf-8"))
            target.write_text(canonical_text(data), encoding="utf-8", newline="\n")
            candidates.append(
                {"card_id": source.stem, "path": rel.as_posix(), "group": group}
            )
            shutil.copy2(folder / "cases" / source.name, OUT / "cases" / source.name)
        if (folder / "needed_common.json").exists():
            requests = read(folder / "needed_common.json")
            common_requests.extend(
                requests.get("definitions", [])
                if isinstance(requests, dict)
                else requests
            )
    assert len(candidates) == len({c["card_id"] for c in candidates})
    candidate_ids = {c["card_id"] for c in candidates}
    original_ids = {p.stem for p in (ROOT / "catalog/cards").glob("*/*.yaml")}
    for path in (CAT / "cards").glob("*/*.yaml"):
        if path.stem not in candidate_ids | original_ids:
            assert path.resolve().is_relative_to(CAT.resolve())
            path.unlink()
    for path in (OUT / "cases").glob("*.yaml"):
        if path.stem not in candidate_ids:
            assert path.resolve().is_relative_to(OUT.resolve())
            path.unlink()
    referenced = set().union(
        *(
            strings(yaml.safe_load((CAT / c["path"]).read_text(encoding="utf-8")))
            for c in candidates
        )
    )
    common_requests = [
        r
        for r in common_requests
        if (
            f"{r['definition']['parent']}.{r['definition']['code']}"
            if r["definition"].get("parent")
            else r["definition"].get("key", r["definition"].get("code"))
        )
        in referenced
    ]
    for filename in {r["file"] for r in common_requests}:
        path = CAT / filename
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        for request in [r for r in common_requests if r["file"] == filename]:
            definition = copy.deepcopy(request["definition"])
            if filename == "categories.yaml":
                parent = definition.pop("parent", None)
                if "." in definition["code"]:
                    parent, definition["code"] = definition["code"].split(".", 1)
                items = (
                    next(r for r in data if r["code"] == parent).setdefault(
                        "children", []
                    )
                    if parent
                    else data
                )
                key = "code"
            else:
                items = data
                key = "key"
            existing = next((r for r in items if r[key] == definition[key]), None)
            if existing is None:
                items.append(definition)
            elif existing != definition and existing.get("category") != definition.get(
                "category"
            ):
                raise ValueError(
                    f"공통 업종 정의 충돌: {filename}/{definition[key]}: {existing} != {definition}"
                )
        path.write_text(canonical_text(data), encoding="utf-8", newline="\n")
    # 새 초중고 업종은 기존 학교납입금의 일부다. 기존 카드가 이 업종을 적립 대상으로
    # 잘못 계산하지 않게 기존 제외 목록을 연결한다. 카드사 정책 변경일을 만들지 않는다.
    adapted = []
    if any(
        r["file"] == "categories.yaml"
        and r["definition"]["code"] == "primary_secondary_fee"
        for r in common_requests
    ):
        old_files = list((ROOT / "catalog/cards").glob("*/*.yaml")) + list(
            (ROOT / "catalog/issuers").glob("*.yaml")
        )
        school_cases = []
        for old in old_files:
            path = CAT / old.relative_to(ROOT / "catalog")
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
            before = copy.deepcopy(data)
            expand_school_exclusions(data)
            if data == before:
                continue
            path.write_text(canonical_text(data), encoding="utf-8", newline="\n")
            adapted.append(old.relative_to(ROOT / "catalog").as_posix())
            if "cards" in old.parts:
                cid = data["id"]
                case = {
                    "card": cid,
                    "cases": [
                        {
                            "name": "추가 초중고 업종도 기존 학교납입금처럼 혜택 제외",
                            "prev_month_spend": 3000000,
                            "payments": [
                                {
                                    "at": "2026-11-06T12:00",
                                    "amount": 10000,
                                    "category": "education.primary_secondary_fee",
                                }
                            ],
                            "expect": [{"payment": 0, "benefits": {}}],
                            "calc": "초중고 학교납입금은 기존 학교납입금 제외 범위 안에 들어간다. 새 업종을 골라도 적립이나 할인은 0원이다.",
                        }
                    ],
                }
                school_cases.append(case)
        # 현대 기본값을 쓰는 기존 카드도 확인한다.
        if "issuers/hyundai.yaml" in adapted:
            for old in (ROOT / "catalog/cards/hyundai").glob("*.yaml"):
                data = yaml.safe_load(old.read_text(encoding="utf-8"))
                if any(c["card"] == data["id"] for c in school_cases):
                    continue
                school_cases.append(
                    {
                        "card": data["id"],
                        "cases": [
                            {
                                "name": "현대 공통 학교납입금 제외에 새 초중고 업종 연결",
                                "prev_month_spend": 3000000,
                                "payments": [
                                    {
                                        "at": "2026-11-06T12:00",
                                        "amount": 10000,
                                        "category": "education.primary_secondary_fee",
                                    }
                                ],
                                "expect": [{"payment": 0, "benefits": {}}],
                                "calc": "현대 공통 적립 제외의 학교납입금 범위는 초중고 납입금을 포함하므로 0원이다.",
                            }
                        ],
                    }
                )
        dest = OUT / "school-cases"
        dest.mkdir(exist_ok=True)
        for case in school_cases:
            kindergarten_case = copy.deepcopy(case["cases"][0])
            kindergarten_case["name"] = (
                "추가 유치원 업종도 기존 학교납입금처럼 혜택 제외"
            )
            kindergarten_case["payments"][0]["category"] = "education.kindergarten"
            kindergarten_case["calc"] = (
                "기존 학교납입금 제외는 유치원을 포함한다. 새 유치원 업종을 골라도 혜택은 0원이다."
            )
            case["cases"].append(kindergarten_case)
            (dest / f"{case['card']}.yaml").write_text(
                yaml.safe_dump(case, allow_unicode=True, sort_keys=False),
                encoding="utf-8",
            )
        for candidate in candidates:
            path = CAT / candidate["path"]
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
            expand_school_exclusions(data)
            path.write_text(canonical_text(data), encoding="utf-8", newline="\n")
    for filename, data in [
        ("candidates.json", candidates),
        ("research-results.json", group_results),
        ("common-evidence.json", common_requests),
        ("school-adapted-files.json", adapted),
    ]:
        (OUT / filename).write_text(
            json.dumps(data, ensure_ascii=False, indent=2, default=str),
            encoding="utf-8",
        )
    print(
        json.dumps(
            {
                "new_cards": len(candidates),
                "school_adapted_files": len(adapted),
                "groups_finished": len({r["group"] for r in group_results}),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
