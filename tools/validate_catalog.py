# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml"]
# ///
"""카탈로그 초안 검증. 설계 문서 6.3절 필드와 6.6절 추가 규칙."""
import pathlib, sys, datetime, yaml
ROOT = pathlib.Path(__file__).resolve().parents[1] / "catalog"
sys.stdout.reconfigure(encoding="utf-8")
cats = {c["code"] for c in yaml.safe_load((ROOT / "categories.yaml").read_text(encoding="utf-8"))}
mpath = ROOT / "merchants.yaml"
merchants = {m["key"] for m in yaml.safe_load(mpath.read_text(encoding="utf-8"))} if mpath.exists() else None

CARD = {"id": str, "issuer": str, "name": str, "kind": str, "annual_fee_domestic": int, "annual_fee_global": int,
        "active": bool, "source_url": str, "updated_at": (datetime.date, str), "spend_basis": str,
        "spend_tiers": list, "spend_rule": dict, "benefits": list}
RULE = {"excluded_categories": list, "exclude_interest_free_installment": bool, "exclude_discounted": bool,
        "installment_basis": str, "cancellation_basis": str}
BEN = {"id": str, "title": str, "target_type": str, "target_values": list, "channel": str, "kind": str,
       "min_txn_amount": int, "min_tier_index": int, "counts_toward_integrated_cap": bool, "conditions_not_modeled": bool}
NULLABLE_INT = ["max_per_txn", "monthly_cap_amount", "monthly_cap_count", "daily_cap_count", "fixed_amount"]
ENUM = {"kind_card": {"credit", "check"}, "spend_basis": {"prev_calendar_month", "unsupported"},
        "installment_basis": {"full_at_purchase", "per_installment_month"}, "cancellation_basis": {"cancel_month", "original_month"},
        "target_type": {"category", "merchant", "all"}, "channel": {"online", "offline", "any"}, "kind_ben": {"discount", "points", "cashback"}}

errors, unknown_merchants, summary = [], {}, []
def err(f, path, msg): errors.append(f"{f}: {path}: {msg}")
def typed(f, obj, spec, where):
    for k, t in spec.items():
        if k not in obj: err(f, f"{where}.{k}", "없음"); continue
        if not isinstance(obj[k], t) or (t is int and isinstance(obj[k], bool)): err(f, f"{where}.{k}", f"타입 {type(obj[k]).__name__}")

files = sorted((ROOT / "cards").glob("*.yaml"))
for p in files:
    f = p.name
    try: c = yaml.safe_load(p.read_text(encoding="utf-8"))
    except Exception as e: err(f, "-", f"YAML 파싱 실패 {e}"); continue
    typed(f, c, CARD, "card")
    if c.get("id") != p.stem: err(f, "id", f"파일 이름과 다름 {c.get('id')}")
    if c.get("kind") not in ENUM["kind_card"]: err(f, "kind", c.get("kind"))
    if c.get("spend_basis") not in ENUM["spend_basis"]: err(f, "spend_basis", c.get("spend_basis"))
    tiers = c.get("spend_tiers") or []
    mins = [t.get("min_spend") for t in tiers]
    if not tiers or mins[0] != 0: err(f, "spend_tiers", "첫 구간이 0이 아님")
    if mins != sorted(mins) or len(set(mins)) != len(mins): err(f, "spend_tiers", f"오름차순 아님 {mins}")
    for i, t in enumerate(tiers):
        ic = t.get("integrated_cap")
        if ic is not None and (not isinstance(ic, int) or isinstance(ic, bool)): err(f, f"spend_tiers[{i}].integrated_cap", ic)
    rule = c.get("spend_rule") or {}
    typed(f, rule, RULE, "spend_rule")
    for x in rule.get("excluded_categories", []):
        if x not in cats: err(f, "spend_rule.excluded_categories", f"모르는 업종 {x}")
    for k in ("installment_basis", "cancellation_basis"):
        if rule.get(k) not in ENUM[k]: err(f, f"spend_rule.{k}", rule.get(k))
    ids = set()
    for j, b in enumerate(c.get("benefits") or []):
        w = f"benefits[{j}]"
        typed(f, b, BEN, w)
        if b.get("id") in ids: err(f, f"{w}.id", "중복")
        ids.add(b.get("id"))
        for k in ("target_type", "channel"):
            if b.get(k) not in ENUM[k]: err(f, f"{w}.{k}", b.get(k))
        if b.get("kind") not in ENUM["kind_ben"]: err(f, f"{w}.kind", b.get("kind"))
        rp, fa = b.get("rate_pct"), b.get("fixed_amount")
        if (rp is None) == (fa is None): err(f, w, "rate_pct와 fixed_amount 중 정확히 하나만")
        if rp is not None and not isinstance(rp, (int, float)): err(f, f"{w}.rate_pct", rp)
        for k in NULLABLE_INT:
            v = b.get(k, "없음")
            if v == "없음": err(f, f"{w}.{k}", "없음")
            elif v is not None and (not isinstance(v, int) or isinstance(v, bool)): err(f, f"{w}.{k}", v)
        mt = b.get("min_tier_index", 0)
        if isinstance(mt, int) and not (0 <= mt < len(tiers)): err(f, f"{w}.min_tier_index", f"{mt} 구간 수 {len(tiers)}")
        tv = b.get("target_values") or []
        if b.get("target_type") == "all" and tv: err(f, f"{w}.target_values", "all인데 값 있음")
        if b.get("target_type") != "all" and not tv: err(f, f"{w}.target_values", "비어 있음")
        if b.get("target_type") == "category":
            for x in tv:
                if x not in cats: err(f, f"{w}.target_values", f"모르는 업종 {x}")
        if b.get("target_type") == "merchant":
            for x in tv:
                if merchants is not None and x not in merchants: unknown_merchants.setdefault(x, []).append(f)
        if b.get("conditions_not_modeled") and not (b.get("notes") or "").strip(): err(f, f"{w}.notes", "조건 미반영인데 notes 없음")
    summary.append((c.get("id"), c.get("kind"), c.get("active"), len(tiers), len(c.get("benefits") or []),
                    sum(1 for b in c.get("benefits") or [] if b.get("conditions_not_modeled")),
                    ("미확인" in (c.get("notes") or "")) or any("미확인" in (b.get("notes") or "") for b in c.get("benefits") or [])))

print(f"카드 파일 {len(files)}개")
for s in summary: print("  ", s)
print("오류", len(errors)); [print("  ", e) for e in errors]
if merchants is None: print("merchants.yaml 없음. 가맹점 키 검사는 건너뜀")
else: print("별칭표에 없는 가맹점 키:", unknown_merchants or "없음")
sys.exit(1 if errors else 0)
