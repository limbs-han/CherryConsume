"""손계산 표 읽기. 설계 6.1. 표는 tests/engine/cases/<카드 id>.yaml이다.

card: shinhan-mrlife
holder: {facts: {}, options: []}          # 모든 경우에 쓰는 보유 카드 값. 없어도 된다
cases:
  - name: 주말 이마트 5만원, 30만 구간
    prev_month_spend: 350000             # 지난달 인정 실적. 첫 결제 달에 등록했고 이 값을 추정값으로 적은 것으로 본다
    holder: {}                            # 이 경우에만 덮어쓰는 값. 없어도 된다
    payments:
      - {at: 2026-09-05T11:00, amount: 50000, merchant: emart, channel: offline}
    expect:
      - {payment: 0, benefits: {weekend-mart: 3000}, counted: 50000, warnings: [check_conditions]}
    calc: 50,000 × 10% = 5,000. 주말 공유 한도 30만 구간 3,000원이라 3,000

- at은 한국 시간이다. 결제의 나머지 칸은 엔진의 Payment와 같다
- benefits는 그 결제가 받는 혜택 전부다. 값은 보상 단위라 포인트면 포인트 수다. 받는 혜택이 없으면 {}
- counted는 그 결제가 실적에 넣는 금액의 합이다. warnings는 반드시 있어야 하는 경고 코드다. 둘 다 없어도 된다
- difference는 엔진과 다른 까닭이다. 실제 명세서 대조에서만 쓴다. 적어 두면 그 결제는 대조하지 않는다. 설계 6.6
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import yaml

from cherry_core.engine import Engine
from cherry_core.engine.cond import KST, month_of
from cherry_core.engine.models import Payment, UserCard

CASES = Path(__file__).parent / "cases"


@dataclass
class Case:
    file: str
    card_id: str
    name: str
    holder: UserCard
    payments: list[Payment]
    expect: list[dict]
    calc: str


def _time(value) -> datetime:
    t = value if isinstance(value, datetime) else datetime.fromisoformat(str(value))
    return t if t.tzinfo else t.replace(tzinfo=KST)


def load_cases(root: Path = CASES) -> list[Case]:
    out: list[Case] = []
    for path in sorted(root.glob("*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        card_id = data["card"]
        for i, raw in enumerate(data["cases"]):
            payments = []
            for j, p in enumerate(raw["payments"]):
                fields = {k: v for k, v in p.items() if k not in ("at", "cancelled_at")}
                if "cancelled_at" in p:
                    fields["cancelled_at"] = _time(p["cancelled_at"])
                payments.append(Payment(id=f"{i:03d}-{j:03d}", user_card_id="u", paid_at=_time(p["at"]), **fields))
            holder = {"id": "u", "card_id": card_id, **(data.get("holder") or {}), **(raw.get("holder") or {})}
            if "prev_month_spend" in raw:
                holder["registered_on"] = month_of(min(p.paid_at for p in payments).astimezone(KST).date())
                holder["assumed_prev_month_spend"] = raw["prev_month_spend"]
            holder.setdefault("registered_on", date(2020, 1, 1))
            out.append(
                Case(
                    path.name,
                    card_id,
                    raw["name"],
                    UserCard(**holder),
                    payments,
                    raw.get("expect", []),
                    raw.get("calc", ""),
                )
            )
    return out


def mismatches(eng: Engine, case: Case) -> list[str]:
    """손계산과 엔진이 다른 곳. difference를 적은 결제는 보지 않는다"""
    results = {r.payment_id: r for r in eng.price_month(case.holder, case.payments)}
    out = []
    for e in case.expect:
        if "difference" in e:
            continue
        r = results[case.payments[e["payment"]].id]
        got = {b.key: b.amount for b in r.benefits}
        if got != e.get("benefits", {}):
            out.append(f"결제 {e['payment']}: 혜택 {got} 기대 {e.get('benefits', {})}. {case.calc}")
        if "counted" in e and sum(p.amount for p in r.spend) != e["counted"]:
            out.append(f"결제 {e['payment']}: 실적 {sum(p.amount for p in r.spend)} 기대 {e['counted']}")
        missing = set(e.get("warnings", [])) - {w.code for w in r.warnings}
        if missing:
            out.append(f"결제 {e['payment']}: 없는 경고 {sorted(missing)}")
    return out
