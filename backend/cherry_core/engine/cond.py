"""참, 거짓, 모름 판정. 설계 2.1, 3.1, 3.2.

판정 결과는 (값, 모르는 것들)이다. 값이 None이면 모름이고, 모르는 것들은 ("payment_method",),
("fact", key), ("option", key), ("category", 부모 코드), ("started_on",) 같은 짝의 집합이다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from functools import cache

import holidays

from cherry_core.catalog.models import Condition

from .models import UserCard

KST = timezone(timedelta(hours=9))  # 한국은 1988년 뒤로 서머타임이 없다
TRUE: tuple[bool | None, frozenset] = (True, frozenset())
FALSE: tuple[bool | None, frozenset] = (False, frozenset())
Tri = tuple[bool | None, frozenset]


def unknown(*need: str) -> Tri:
    return (None, frozenset([tuple(need)]))


def all_of(results) -> Tri:
    needs: set = set()
    value: bool | None = True
    for v, n in results:
        if v is False:
            return FALSE
        if v is None:
            value = None
            needs |= n
    return (value, frozenset(needs)) if value is None else TRUE


def any_of(results) -> Tri:
    needs: set = set()
    value: bool | None = False
    for v, n in results:
        if v is True:
            return TRUE
        if v is None:
            value = None
            needs |= n
    return (value, frozenset(needs)) if value is None else FALSE


def local(at: datetime) -> datetime:
    return at.astimezone(KST)


def month_of(d: date) -> date:
    return date(d.year, d.month, 1)


def add_months(m: date, n: int) -> date:
    y, mm = divmod(m.month - 1 + n, 12)
    return date(m.year + y, mm + 1, 1)


@cache
def _kr_holidays(year: int) -> frozenset[date]:
    return frozenset(holidays.country_holidays("KR", years=[year]))


def is_holiday(d: date) -> bool:
    return d in _kr_holidays(d.year)


def category_match(paid: str | None, wanted: str) -> Tri:
    """결제 업종이 조건 업종에 맞는지. 결제가 부모 업종까지만 알면 모름이다. 설계 2.1"""
    if paid is None:
        return FALSE
    if paid == wanted or paid.startswith(wanted + "."):
        return TRUE
    if wanted.startswith(paid + "."):
        return unknown("category", paid)
    return FALSE


def categories_match(paid: str | None, wanted: list[str]) -> Tri:
    return any_of(category_match(paid, w) for w in wanted)


@dataclass
class Situation:
    """조건을 판정하는 데 필요한 결제 쪽 값. amount는 혜택마다 다를 수 있어 바꿔 가며 쓴다."""

    at: datetime
    amount: int
    merchant: str | None
    category: str | None
    channel: str
    region: str
    installment_months: int
    interest_free: bool
    payment_method: str | None
    billing: str
    card: UserCard
    defaults: dict[str, str | None] = field(default_factory=dict)
    top_areas: dict[str, set[str]] = field(default_factory=dict)
    area: str | None = None
    month_total: int | None = None
    skip: frozenset[str] = frozenset()
    time_known: bool = True

    @property
    def day(self) -> date:
        return local(self.at).date()

    def choice(self, option: str) -> str | None:
        """결제일에 골라 둔 선택지. 고른 적이 없으면 카드사 기본값. 설계 3.8"""
        picks = [p for p in self.card.options if p.option == option and p.effective_from <= self.day]
        if picks:
            return max(picks, key=lambda p: p.effective_from).choice
        return self.defaults.get(option)


def check(c: Condition, s: Situation) -> Tri:
    """조건 항목 하나. 적힌 칸이 모두 맞아야 참이다."""
    parts: list[Tri] = []
    add = parts.append
    if c.amount is not None:
        ok = (c.amount.min is None or s.amount >= c.amount.min) and (
            c.amount.below is None or s.amount < c.amount.below
        )
        add(TRUE if ok else FALSE)
    if c.day is not None:
        weekday = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"][s.day.weekday()]
        in_days = weekday in (c.day.days or [])
        holiday = is_holiday(s.day)
        ok = {
            "ignore": in_days,
            "include": in_days or holiday,
            "exclude": in_days and not holiday,
            "only": holiday,
        }[c.day.holidays]
        add(TRUE if ok else FALSE)
    if c.time is not None and not s.time_known:
        add(unknown("time"))
    elif c.time is not None:
        t = local(s.at).strftime("%H:%M")
        start, end = c.time.start, c.time.end
        ok = start <= t < end if start <= end else (t >= start or t < end)
        add(TRUE if ok else FALSE)
    if c.months is not None:
        add(TRUE if s.day.month in c.months else FALSE)
    if c.region is not None:
        add(TRUE if s.region == c.region else FALSE)
    if c.channel is not None:
        add(TRUE if s.channel == c.channel else FALSE)
    if c.interest_free is not None:
        add(TRUE if s.interest_free == c.interest_free else FALSE)
    if c.lump_sum is not None:
        add(TRUE if s.installment_months <= 1 else FALSE)
    if c.payment is not None:
        add(unknown("payment_method") if s.payment_method is None else TRUE if s.payment_method in c.payment else FALSE)
    if c.payment_not is not None:
        pm = s.payment_method
        add(unknown("payment_method") if pm is None else FALSE if pm in c.payment_not else TRUE)
    if c.billing is not None:
        add(TRUE if s.billing in c.billing else FALSE)
    if c.billing_not is not None:
        add(FALSE if s.billing in c.billing_not else TRUE)
    for option, choices in (c.option or {}).items():
        chosen = s.choice(option)
        add(unknown("option", option) if chosen is None else TRUE if chosen in choices else FALSE)
    if c.fact is not None:
        add(fact(c.fact, s))
    if c.ranked is not None and "ranked" not in s.skip:
        add(TRUE if s.area in s.top_areas.get(c.ranked, set()) else FALSE)
    if c.card_month is not None:
        if s.card.started_on is None:
            add(unknown("started_on"))
        else:
            start = s.card.started_on
            n = (s.day.year - start.year) * 12 + s.day.month - start.month
            ok = (c.card_month.min is None or n >= c.card_month.min) and (
                c.card_month.max is None or n <= c.card_month.max
            )
            add(TRUE if ok else FALSE)
    if c.month_total is not None and "month_total" not in s.skip:
        add(TRUE if (s.month_total or 0) >= c.month_total.min else FALSE)
    if c.any_of is not None:
        add(any_of(check(sub, s) for sub in c.any_of))
    return all_of(parts)


def fact(key: str, s: Situation) -> Tri:
    facts = dict(s.card.facts)
    # 결제일에 맞는 가장 늦은 답이 facts를 덮는다. 작업 005 설계 5e
    for p in sorted((p for p in s.card.fact_picks if p.effective_from <= s.day), key=lambda p: p.effective_from):
        facts[p.key] = p.value
    if key == "birth_month_now":
        if "birth_month" not in facts:
            return unknown("fact", "birth_month")
        return TRUE if facts["birth_month"] == s.day.month else FALSE
    if key not in facts:
        return unknown("fact", key)
    return TRUE if facts[key] is True else FALSE


def check_all(conditions: list[Condition], s: Situation) -> Tri:
    return all_of(check(c, s) for c in conditions)
