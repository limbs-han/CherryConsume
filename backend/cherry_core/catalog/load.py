"""카탈로그 파일을 읽어 파일 단위 모델과 합친 개정 모델로 검사한다."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml
from pydantic import TypeAdapter, ValidationError

from .models import (
    CardFile,
    Category,
    IssuerFile,
    Merchant,
    PaymentMethod,
    PointProgram,
    ReferenceValue,
    Rules,
)
from .resolve import ResolvedRevision, resolve_card


@dataclass
class Problem:
    level: str  # error 또는 warning
    file: str
    path: str
    message: str

    def __str__(self) -> str:
        where = f"{self.file}: {self.path}" if self.path else self.file
        return f"{where}: {self.message}"


@dataclass
class LoadedCard:
    file: str
    raw: dict
    card: CardFile
    revisions: list[tuple[ResolvedRevision, Rules]]


@dataclass
class LoadedIssuer:
    file: str
    raw: dict
    issuer: IssuerFile


@dataclass
class Catalog:
    root: Path
    categories: set[str] = field(default_factory=set)
    merchants: dict[str, Merchant] = field(default_factory=dict)
    payment_methods: dict[str, PaymentMethod] = field(default_factory=dict)
    point_programs: dict[str, PointProgram] = field(default_factory=dict)
    reference: dict[str, ReferenceValue] = field(default_factory=dict)
    issuers: dict[str, LoadedIssuer] = field(default_factory=dict)
    cards: dict[str, LoadedCard] = field(default_factory=dict)
    problems: list[Problem] = field(default_factory=list)


def format_loc(loc: tuple, data: Any) -> str:
    """pydantic 오류 위치를 사람이 읽는 경로로 바꾼다. key가 있는 목록 항목은 [key]로 쓴다."""
    out, node = "", data
    for part in loc:
        if isinstance(part, int):
            item = node[part] if isinstance(node, list) and part < len(node) else None
            label = item.get("key") if isinstance(item, dict) else None
            out += f"[{label}]" if label else f"[{part}]"
            node = item
        else:
            out += f".{part}" if out else str(part)
            node = node.get(part) if isinstance(node, dict) else None
    return out


def _read(path: Path, rel: str, problems: list[Problem]) -> Any:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        problems.append(Problem("error", rel, "", f"YAML을 읽지 못했다: {e}"))
        return None


def _validate(tp: Any, data: Any, rel: str, problems: list[Problem], prefix: str = "") -> Any:
    try:
        return TypeAdapter(tp).validate_python(data)
    except ValidationError as e:
        for err in e.errors():
            problems.append(Problem("error", rel, prefix + format_loc(err["loc"], data), err["msg"]))
        return None


def load_catalog(root: Path) -> Catalog:
    cat = Catalog(root=root)
    p = cat.problems

    def read_list(name: str, model: type) -> list:
        path = root / name
        if not path.exists():
            p.append(Problem("error", name, "", "파일이 없다"))
            return []
        return _validate(list[model], _read(path, name, p), name, p) or []

    categories = read_list("categories.yaml", Category)
    cat.categories = {c.code for c in categories} | {f"{c.code}.{ch.code}" for c in categories for ch in c.children}
    cat.merchants = {m.key: m for m in read_list("merchants.yaml", Merchant)}
    cat.payment_methods = {m.key: m for m in read_list("payment_methods.yaml", PaymentMethod)}
    cat.point_programs = {m.key: m for m in read_list("point_programs.yaml", PointProgram)}
    cat.reference = {m.key: m for m in read_list("reference.yaml", ReferenceValue)}

    for path in sorted((root / "issuers").glob("*.yaml")):
        rel = path.relative_to(root).as_posix()
        raw = _read(path, rel, p)
        issuer = _validate(IssuerFile, raw, rel, p)
        if issuer is None:
            continue
        if issuer.id != path.stem:
            p.append(Problem("error", rel, "id", f"파일 이름 {path.stem}과 다르다"))
        cat.issuers[issuer.id] = LoadedIssuer(rel, raw, issuer)

    for path in sorted((root / "cards").glob("*/*.yaml")):
        rel = path.relative_to(root).as_posix()
        raw = _read(path, rel, p)
        card = _validate(CardFile, raw, rel, p)
        if card is None:
            continue
        if card.id in cat.cards:
            p.append(Problem("error", rel, "id", f"{cat.cards[card.id].file}와 id가 겹친다"))
            continue
        issuer = cat.issuers.get(card.issuer)
        try:
            resolved = resolve_card(
                card.model_dump(by_alias=True, exclude_unset=True),
                issuer.issuer.model_dump(by_alias=True, exclude_unset=True) if issuer else None,
            )
        except ValueError as e:
            p.append(Problem("error", rel, "revisions", str(e)))
            continue
        revisions = []
        for r in resolved:
            rules = _validate(Rules, r.data, rel, p, prefix=f"revisions@{r.effective_from}.")
            if rules is not None:
                revisions.append((r, rules))
        cat.cards[card.id] = LoadedCard(rel, raw, card, revisions)
    return cat
