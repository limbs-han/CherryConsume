"""모델 밖의 교차 검사와 경고. 설계 4.2 검증 규칙."""

from __future__ import annotations

import re
import subprocess
from itertools import pairwise
from pathlib import Path
from typing import Any

import yaml

from .canonical import catalog_files, is_canonical
from .load import Catalog, LoadedCard, Problem
from .models import Benefit, Condition, Rules

FUEL_PRICE_KEY = "fuel_price_gasoline"
_PATH_TOKEN = re.compile(r"([^.\[\]]+)|\[([^\]]+)\]")


def check_catalog(cat: Catalog) -> list[Problem]:
    problems = list(cat.problems)
    for path in catalog_files(cat.root):
        try:
            canonical = is_canonical(path)
        except yaml.YAMLError:
            continue  # 읽기 오류는 load_catalog가 이미 남겼다
        if not canonical:
            rel = path.relative_to(cat.root).as_posix()
            problems.append(Problem("error", rel, "", "저장 형식이 아니다. format 명령으로 고친다"))
    problems += _check_common(cat)
    for issuer in cat.issuers.values():
        for q in issuer.issuer.open_questions:
            if not path_exists(issuer.raw, q.path):
                problems.append(Problem("error", issuer.file, "open_questions", f"path {q.path}가 가리키는 칸이 없다"))
    for card in cat.cards.values():
        problems += _check_card(card, cat)
    return problems


def _check_common(cat: Catalog) -> list[Problem]:
    out = []
    seen: dict[str, str] = {}
    for m in cat.merchants.values():
        if m.category not in cat.categories:
            out.append(Problem("error", "merchants.yaml", f"[{m.key}].category", f"업종 {m.category}가 없다"))
        for alias in m.aliases:
            norm = alias.replace(" ", "").lower()
            if norm in seen and seen[norm] != m.key:
                out.append(
                    Problem("error", "merchants.yaml", f"[{m.key}].aliases", f"별칭 {alias}가 {seen[norm]}와 겹친다")
                )
            seen[norm] = m.key
    return out


def _check_card(card: LoadedCard, cat: Catalog) -> list[Problem]:
    out = []
    c, f = card.card, card.file
    stem, parent = Path(f).stem, Path(f).parent.name
    if c.id != stem:
        out.append(Problem("error", f, "id", f"파일 이름 {stem}과 다르다"))
    if c.issuer != parent or not c.id.startswith(c.issuer + "-"):
        out.append(Problem("error", f, "issuer", f"카드사 폴더 {parent}와 id 앞부분이 issuer와 같아야 한다"))
    if c.issuer not in cat.issuers:
        out.append(Problem("error", f, "issuer", f"issuers/{c.issuer}.yaml이 없다"))
    if not c.product_codes:
        out.append(Problem("warning", f, "product_codes", "비어 있다. 갱신 때 같은 카드를 찾지 못한다"))
    source_ids = {s.id for s in c.sources}
    for q in c.open_questions:
        if not path_exists(card.raw, q.path):
            out.append(Problem("error", f, "open_questions", f"path {q.path}가 가리키는 칸이 없다"))
    for r, rules in card.revisions:
        prefix = f"revisions@{r.effective_from}."
        if r.source not in source_ids:
            out.append(Problem("error", f, prefix + "source", f"sources에 {r.source}가 없다"))
        out += [Problem(level, f, prefix + path, msg) for level, path, msg in check_rules(rules, cat, source_ids)]
    out += [
        Problem("warning", f, "revisions", f"직전 커밋에 있던 혜택 key가 사라졌다: {sorted(gone)}")
        for gone in [removed_benefit_keys(cat.root / f, card.raw)]
        if gone
    ]
    return out


def check_rules(rules: Rules, cat: Catalog, source_ids: set[str]) -> list[tuple[str, str, str]]:
    """개정 하나를 검사해 (level, path, message) 목록을 돌려준다."""
    out: list[tuple[str, str, str]] = []

    def err(path: str, msg: str) -> None:
        out.append(("error", path, msg))

    def warn(path: str, msg: str) -> None:
        out.append(("warning", path, msg))

    tiers = rules.tiers
    tierset = set(tiers)
    if tiers[0] != 0 or any(a >= b for a, b in pairwise(tiers)):
        err("tiers", "0부터 시작하는 오름차순이어야 한다")

    def table(value: Any, path: str, first: int | None) -> None:
        """first는 이 값이 적용되는 첫 구간. 쓰는 혜택이 없어 모르면 None."""
        if not isinstance(value, dict) or not value:
            return
        bad = sorted(k for k in value if k not in tierset)
        if bad:
            err(path, f"구간표 키 {bad}가 tiers에 없다")
        if first is not None and min(value) > first:
            err(path, f"구간표의 가장 작은 키 {min(value)}가 적용 첫 구간 {first}보다 크다")
        vals = [value[k] for k in sorted(value)]
        if any(b < a for a, b in pairwise(vals)):
            warn(path, "구간이 높아지는데 값이 줄어든다")

    def cats(values: list[str], path: str) -> None:
        bad = [v for v in values if v not in cat.categories]
        if bad:
            err(path, f"업종 {bad}가 categories.yaml에 없다")

    for name in ("benefits", "limits", "stacks", "options", "facts", "ranked"):
        keys = [x.key for x in getattr(rules, name)]
        dup = sorted({k for k in keys if keys.count(k) > 1})
        if dup:
            err(name, f"key가 겹친다: {dup}")

    options = {o.key: {ch.key for ch in o.choices} for o in rules.options}
    facts = {x.key: x for x in rules.facts}
    ranked_keys = {x.key for x in rules.ranked}
    shared_keys = {x.key for x in rules.limits}
    stack_keys = {x.key for x in rules.stacks} | {"main"}
    benefit_keys = {b.key for b in rules.benefits}

    def cond(c: Condition, path: str, benefit: Benefit | None) -> None:
        for name in ("payment", "payment_not"):
            bad = [x for x in getattr(c, name) or [] if x not in cat.payment_methods]
            if bad:
                err(f"{path}.{name}", f"결제수단 {bad}가 payment_methods.yaml에 없다")
        for key, choices in (c.option or {}).items():
            if key not in options:
                err(f"{path}.option", f"옵션 {key}가 없다")
            elif set(choices) - options[key]:
                err(f"{path}.option", f"옵션 {key}에 선택지 {sorted(set(choices) - options[key])}가 없다")
        if c.fact is not None:
            derived = c.fact == "birth_month_now" and "birth_month" in facts
            if c.fact not in facts and not derived:
                err(f"{path}.fact", f"사실 {c.fact}가 facts에 없다")
            elif c.fact in facts and facts[c.fact].type != "bool":
                err(f"{path}.fact", f"사실 {c.fact}는 bool이어야 조건으로 쓴다")
        if c.ranked is not None and c.ranked not in ranked_keys:
            err(f"{path}.ranked", f"ranked 그룹 {c.ranked}가 없다")
        if c.month_total is not None and (benefit is None or benefit.reward.basis != "month_total"):
            err(f"{path}.month_total", "reward.basis가 month_total인 혜택에만 쓴다")
        for i, sub in enumerate(c.any_of or []):
            cond(sub, f"{path}.any_of[{i}]", benefit)

    s = rules.spend
    if s.basis == "billing_cycle":
        err("spend.basis", "결제일 기준 실적은 이용기간 표가 모델에 들어간 뒤에 쓴다")
    cats(s.exclude_categories, "spend.exclude_categories")
    cats(list(s.month_offset), "spend.month_offset")
    for i, o in enumerate(s.cancellation_overrides):
        cond(o.when, f"spend.cancellation_overrides[{i}].when", None)
    be = rules.benefit_exclusions
    cats(be.categories, "benefit_exclusions.categories")
    for i, w in enumerate(be.when_any):
        cond(w, f"benefit_exclusions.when_any[{i}]", None)
    if rules.new_card:
        if rules.new_card.tier not in tierset:
            err("new_card.tier", f"구간 {rules.new_card.tier}가 tiers에 없다")
        for k, v in rules.new_card.tier_by_benefit.items():
            if k not in benefit_keys:
                err("new_card.tier_by_benefit", f"혜택 {k}가 없다")
            if v not in tierset:
                err("new_card.tier_by_benefit", f"구간 {v}가 tiers에 없다")

    shared_first: dict[str, int] = {}
    ranked_first: dict[str, int] = {}
    ranked_areas: dict[str, set[str]] = {}
    for b in rules.benefits:
        bp = f"benefits[{b.key}]"
        start, end = tiers[0], tiers[-1]
        if b.tiers:
            if b.tiers.start is not None:
                if b.tiers.start not in tierset:
                    err(f"{bp}.tiers.from", f"구간 {b.tiers.start}가 tiers에 없다")
                start = b.tiers.start
            if b.tiers.end is not None:
                if b.tiers.end not in tierset:
                    err(f"{bp}.tiers.to", f"구간 {b.tiers.end}가 tiers에 없다")
                end = b.tiers.end
            if start > end:
                err(f"{bp}.tiers", "from은 to 이하여야 한다")
            if b.tiers.waived_when:
                cond(b.tiers.waived_when, f"{bp}.tiers.waived_when", b)
        first = tiers[0] if b.tiers and b.tiers.waived_when else start  # 하한을 풀면 0 구간에서도 받는다
        cats(b.target.categories + b.target.exclude_categories, f"{bp}.target")
        bad = [m for m in b.target.merchants + b.target.exclude_merchants if m not in cat.merchants]
        if bad:
            err(f"{bp}.target", f"가맹점 {bad}가 merchants.yaml에 없다")
        for i, c in enumerate(b.when):
            cond(c, f"{bp}.when[{i}]", b)
            if c.ranked in ranked_keys:
                ranked_areas.setdefault(c.ranked, set()).add(b.area or b.key)
                ranked_first[c.ranked] = min(ranked_first.get(c.ranked, first), first)
        rw = b.reward
        if rw.program is not None and rw.program not in cat.point_programs:
            err(f"{bp}.reward.program", f"포인트 {rw.program}가 point_programs.yaml에 없다")
        if rw.per_liter is not None and FUEL_PRICE_KEY not in cat.reference:
            err(f"{bp}.reward.per_liter", f"reference.yaml에 {FUEL_PRICE_KEY}가 없다")
        table(rw.rate, f"{bp}.reward.rate", first)
        table(rw.fixed, f"{bp}.reward.fixed", first)
        for i, lim in enumerate(b.limits):
            lp = f"{bp}.limits[{i}]"
            if lim.shared is not None:
                if lim.shared not in shared_keys:
                    err(f"{lp}.shared", f"공유 한도 {lim.shared}가 limits에 없다")
                shared_first[lim.shared] = min(shared_first.get(lim.shared, first), first)
            for name in ("amount", "count", "base"):
                table(getattr(lim, name), f"{lp}.{name}", first)
            for j, a in enumerate(lim.adjust):
                cond(a.when, f"{lp}.adjust[{j}].when", b)
        if b.stack not in stack_keys:
            err(f"{bp}.stack", f"묶음 {b.stack}가 stacks에 없다")
        if b.source is not None and b.source not in source_ids:
            err(f"{bp}.source", f"sources에 {b.source}가 없다")
        rates = list(rw.rate.values()) if isinstance(rw.rate, dict) else [rw.rate] if rw.rate else []
        if rates and max(rates) >= 5 and not b.limits:
            warn(bp, "비율이 5% 이상인데 한도가 없다")
        if rw.type == "onsite_discount" and rates and max(rates) >= 100:
            err(f"{bp}.reward.rate", "현장할인 비율은 100 미만이어야 한다. 할인 전 금액을 되짚을 수 없다")

    for lim in rules.limits:
        lp = f"limits[{lim.key}]"
        if lim.key not in shared_first:
            warn(lp, "쓰는 혜택이 없다")
        for name in ("amount", "count", "base"):
            table(getattr(lim, name), f"{lp}.{name}", shared_first.get(lim.key))
        for j, a in enumerate(lim.adjust):
            cond(a.when, f"{lp}.adjust[{j}].when", None)
    for st in rules.stacks:
        members = sorted(b.key for b in rules.benefits if b.stack == st.key)
        if st.pick == "priority" and sorted(st.order) != members:
            err(f"stacks[{st.key}].order", f"묶음의 혜택 {members}이 빠짐없이 한 번씩 있어야 한다")
    for rk in rules.ranked:
        if len(ranked_areas.get(rk.key, ())) < 2:
            err(f"ranked[{rk.key}]", "영역이 둘 이상이어야 한다. area가 같은 혜택은 한 영역이다")
        table(rk.top, f"ranked[{rk.key}].top", ranked_first.get(rk.key))
    return out


def path_exists(data: Any, path: str) -> bool:
    """open_questions의 path가 파일 안의 칸을 가리키는지. [숫자]는 순서, [이름]은 key로 찾는다."""
    node = data
    for name, sel in _PATH_TOKEN.findall(path):
        if name:
            if not isinstance(node, dict) or name not in node:
                return False
            node = node[name]
        elif isinstance(node, list) and sel.isdigit():
            if int(sel) >= len(node):
                return False
            node = node[int(sel)]
        elif isinstance(node, list):
            found = [x for x in node if isinstance(x, dict) and x.get("key") == sel]
            if not found:
                return False
            node = found[0]
        else:
            return False
    return True


def benefit_keys(raw: Any) -> set[str]:
    """파일에 적힌 모든 개정의 혜택 key."""
    keys: set[str] = set()
    revisions = raw.get("revisions") if isinstance(raw, dict) else None
    for entry in revisions or []:
        if not isinstance(entry, dict):
            continue
        for b in entry.get("benefits") or []:
            if isinstance(b, dict) and "key" in b:
                keys.add(b["key"])
        patched = (entry.get("patch") or {}).get("benefits")
        if isinstance(patched, dict):
            keys |= {k for k, v in patched.items() if v is not None}
    return keys


def removed_benefit_keys(path: Path, raw_now: Any) -> set[str]:
    """직전 커밋의 같은 파일에 있던 혜택 key 중 지금 없는 것. git이 없거나 새 파일이면 빈 집합."""
    try:
        r = subprocess.run(
            ["git", "show", f"HEAD:./{path.name}"],
            cwd=path.parent,
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
    except OSError:
        return set()
    if r.returncode != 0:
        return set()
    try:
        old = yaml.safe_load(r.stdout)
    except yaml.YAMLError:
        return set()
    return benefit_keys(old) - benefit_keys(raw_now)
