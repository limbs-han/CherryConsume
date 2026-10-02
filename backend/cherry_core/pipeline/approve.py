"""승인 하나를 골드와 내보내기 폴더로 옮길 값을 만든다. 작업 003 과제 20의 승인 부분, 설계 4절 7번.

Databricks의 approve.py가 부른다. 과제 20 검수 앱도 같은 함수를 부른다.
바뀐 파일은 저장 형식이어야 하고, 골드 카탈로그에 넣었을 때 검사 오류가 없어야 한다.
골드에 있던 카드, 개정, 혜택 key가 사라지는 파일은 거부한다. 결제 기록이 개정과 혜택 key를 가리키기 때문이다.
카드 개정은 다시 만들되, 바뀌지 않은 개정 행은 원래 검수 번호를 그대로 둔다.
"""

from __future__ import annotations

import json
import re
import tempfile
from collections.abc import Iterable
from datetime import datetime
from pathlib import Path

import yaml

from cherry_core.catalog.canonical import canonical_text
from cherry_core.catalog.load import Catalog, load_catalog
from cherry_core.pipeline.export import commit_message, secret_lines
from cherry_core.pipeline.seed import load_checked, revision_rows

# 카탈로그 2판 파일 자리. catalog_files와 같다. 공통 파일은 이미 있는 것만 바꿀 수 있다
PATH = re.compile(r"[a-z_]+\.yaml|issuers/[a-z0-9_-]+\.yaml|cards/[a-z0-9_-]+/[a-z0-9_-]+\.yaml")
LABEL = re.compile(r"[a-z0-9][a-z0-9-]*")


def _load(files: dict[str, str], checked: bool) -> Catalog:
    with tempfile.TemporaryDirectory() as tmp:
        for rel, text in files.items():
            (Path(tmp) / rel).parent.mkdir(parents=True, exist_ok=True)
            (Path(tmp) / rel).write_text(text, encoding="utf-8", newline="\n")
        return load_checked(Path(tmp)) if checked else load_catalog(Path(tmp))


def lost(old: Catalog, new: Catalog) -> list[str]:
    """old에 있고 new에 없는 카드, 개정, 개정 안의 혜택 key. 새 개정에서 혜택을 빼는 것은 사라진 것이 아니다."""
    out = []
    for cid, lc in sorted(old.cards.items()):
        nc = new.cards.get(cid)
        if nc is None:
            out.append(f"카드 {cid}")
            continue
        after = {rev.effective_from: rev for rev, _ in nc.revisions}
        for rev, _ in lc.revisions:
            now = after.get(rev.effective_from)
            if now is None:
                out.append(f"{cid} {rev.effective_from} 개정")
                continue
            keys = {b["key"] for b in rev.data.get("benefits", [])} - {b["key"] for b in now.data.get("benefits", [])}
            out += [f"{cid} {rev.effective_from} 혜택 {k}" for k in sorted(keys)]
    return out


def apply_changes(
    gold: dict[str, str], incoming: dict[str, str], already: Iterable[str] = ()
) -> tuple[dict[str, str], dict[str, str]]:
    """(바뀐 뒤 카탈로그 전체, 이 승인이 바꾸는 파일). 검사를 통과하지 못하면 ValueError로 멈춘다.

    already는 중간에 끊긴 이 승인이 골드에 이미 넣은 파일이다. 골드와 같아도 이 승인의 파일로 센다.
    """
    already = set(already)
    for path, text in incoming.items():
        if not PATH.fullmatch(path) or ("/" not in path and path not in gold):
            raise ValueError(f"카탈로그 파일 경로가 아니다: {path}")
        if text != canonical_text(yaml.safe_load(text)):
            raise ValueError(f"저장 형식이 아니다: {path}. format 명령으로 고친다")
    changed = {p: t for p, t in sorted(incoming.items()) if gold.get(p) != t or p in already}
    if not changed:
        raise ValueError("바뀐 파일이 없다")
    for path, text in changed.items():
        if found := secret_lines(text):
            raise ValueError(f"커밋 훅이 비밀값으로 볼 줄이 있다: {path} {found[0]}")
    files = {**gold, **changed}
    gone = lost(_load(gold, checked=False), _load(files, checked=True))  # 검사 오류가 있으면 ValueError
    if gone:
        raise ValueError(f"골드에 있던 것이 사라진다 {len(gone)}개. 첫 번째: {gone[0]}")
    return files, changed


def revision_rows_after(files: dict[str, str], old: list[tuple], review_id: str) -> list[tuple]:
    """바뀐 뒤 카탈로그의 카드 개정 행. 끝 칸은 검수 번호다.

    old는 지금 gold.card_revisions의 (카드, 카드사, 시행일, 추정 여부, 원문 id, 규칙 JSON, 검수 번호)다.
    앞의 여섯 칸이 같은 행은 old의 검수 번호를 그대로 쓰고, 다르거나 새 행은 이번 검수 번호를 쓴다.
    카드사 파일이 바뀌면 그 카드사 카드의 개정이 모두 여기서 함께 바뀐다.
    규칙 JSON은 글자로 비교한다. clean_rules를 바꾼 wheel로 돌리면 카탈로그가 같아도 모든 행이 새 번호를 받는다.
    """
    kept = {tuple(r[:6]): r[6] for r in old}
    return [(*r, kept.get(tuple(r), review_id)) for r in revision_rows(_load(files, checked=False))]


def unexpected_renewals(rows: list[tuple], changed: dict[str, str], review_id: str) -> list[str]:
    """이번 승인이 바꾸지 않은 카드인데 새 검수 번호를 받는 개정의 카드.

    카드 파일이나 그 카드사 파일을 바꾸지 않았는데 개정이 바뀌면, 규칙을 만드는 코드가 바뀐 것이다.
    그대로 쓰면 승인 하나가 모든 개정의 검수 번호와 시각을 덮어서 쓰기 전에 멈춘다.
    """

    def mine(card_id: str, issuer: str) -> bool:
        return f"cards/{issuer}/{card_id}.yaml" in changed or f"issuers/{issuer}.yaml" in changed

    return sorted({r[0] for r in rows if r[6] == review_id and not mine(r[0], r[1])})


def resume_or_start(mine: dict | None, unfinished: list[dict], gold_digest: str, expect_files: str) -> dict | None:
    """새 승인이면 None, 끊긴 승인을 이어서 하면 그 검수 기록을 돌려준다. 할 수 없으면 ValueError.

    mine은 같은 올린 폴더 이름의 검수 기록 {review_id, subject, base, result, paths, finished}이고,
    unfinished는 끝나지 않은 손 승인의 {review_id, source, subject}다.
    진행 상태는 사람이 고칠 수 없는 silver.reviews에 둔다. 올린 폴더는 지우거나 고치지 않아야 이어서 할 수 있다.
    """
    if mine and mine["finished"]:
        raise ValueError("이미 끝난 승인이다. 새 승인은 새 폴더 이름으로 올린다")
    others = [r for r in unfinished if not mine or r["review_id"] != mine["review_id"]]
    if others:
        r = others[0]
        if r.get("draft_id"):
            # 끊긴 앱 승인을 손 승인으로 이으면 저장 형식 맞추기와 대기 건 닫기가 빠진다. 2026-10-02 다시 검토
            raise ValueError(
                f"끊긴 앱 승인 {r['review_id']}이 있다. 검수 앱에서 초안 {r['draft_id']}을 다시 승인해 먼저 끝낸다"
            )
        raise ValueError(
            f"끊긴 승인 {r['review_id']}이 있다. 폴더 이름 {r['source']}, 제목 '{r['subject']}'로 다시 돌려 먼저 끝낸다"
        )
    if mine is None:
        if gold_digest != expect_files:
            raise ValueError("골드 카탈로그가 PC 값과 다르다. 저장소가 골드를 따라잡은 뒤 파일을 다시 만든다")
        return None
    if gold_digest not in (mine["base"], mine["result"]):
        raise ValueError("골드 카탈로그가 이 승인 밖에서 바뀌었다. 멈추고 사람이 맞춘다")
    return mine


def new_review_id(now: datetime, label: str) -> str:
    """r-<UTC 시각>-<이름>. 이름 순서가 승인 순서다. export 워크플로가 이 순서로 커밋한다."""
    if not LABEL.fullmatch(label):
        raise ValueError("검수 번호 이름은 영문 소문자나 숫자로 시작하고 영문 소문자, 숫자, 하이픈만 쓴다")
    return f"r-{now:%Y%m%dT%H%M%SZ}-{label}"


def commit_json(subject: str, review_id: str, base: str, result: str) -> str:
    """export가 읽을 commit.json. base와 result는 승인 전과 후의 골드 카탈로그 해시다. 커밋 훅이 막을 제목이면 ValueError."""
    commit_message(subject, review_id)
    return json.dumps({"subject": subject, "review_id": review_id, "base": base, "result": result}, ensure_ascii=False)


def draft_subject(text: str, old: str | None = None) -> str:
    """검수 앱이 승인한 카드 파일의 커밋 제목. 작업 003 과제 20. old는 승인 전 골드의 같은 파일이다.

    판매 중이던 카드가 멈췄으면 발급 중단으로 적는다. 아니면 바뀐 개정 가운데 마지막 것의 시행일을 쓴다.
    바뀐 개정이 없으면 마지막 개정의 시행일이다. 2026-10-02 위험 검토.
    """
    card = yaml.safe_load(text)
    before = yaml.safe_load(old) if old else {}
    if card.get("status") != "on_sale" and before.get("status", "on_sale") == "on_sale":
        return f"feat: {card['name']} 발급 중단 반영"
    olds = before.get("revisions", [])
    # 순번이 아니라 들어 있는지로 견준다. 과거 개정을 가운데 끼우면 뒤 순번이 밀리기 때문이다. 다시 검토
    changed = [r for r in card["revisions"] if r not in olds]
    return f"feat: {card['name']} {(changed or card['revisions'])[-1]['effective_from']} 개정 반영"


def draft_plan(decision: str, records: list[dict]) -> tuple[str, str | None]:
    """검수 앱이 초안 하나를 승인하거나 반려할 때 할 일과 이어 할 incoming 폴더 이름. 작업 003 과제 20.

    records는 그 초안의 검수 기록 {decision, source, finished}다. 할 일은 start, resume, close, reject다.
    앱은 버튼마다 새 폴더 이름을 만들어서, 끊긴 앱 승인은 기록의 폴더로 이어 한다. 끝났으면 대기 건만 닫는다.
    같은 초안에 승인과 반려가 함께 남지 않게 막는다. 2026-10-02 위험 검토.
    """
    approved = [r for r in records if r["decision"] == "approved"]
    if decision == "reject":
        if approved:
            raise ValueError("승인한 초안이다. 반려하지 않는다. 대기 건이 열려 있으면 승인을 다시 누르면 닫힌다")
        return ("close", None) if any(r["decision"] == "rejected" for r in records) else ("reject", None)
    if any(r["decision"] == "rejected" for r in records):
        raise ValueError(
            "반려한 초안이다. 대기 건이 열려 있으면 반려를 다시 누르면 닫힌다. 다시 넣으려면 지금 골드 판에 손 승인으로 넣는다"
        )
    if not approved:
        return "start", None
    return ("close", None) if approved[-1]["finished"] else ("resume", approved[-1]["source"])


def stale_exports(names: list[str], now: datetime, hours: int = 36) -> list[str]:
    """내보내기 pending/에 hours보다 오래 남은 폴더. export는 매일 돌아 이런 폴더가 있으면 커밋에 실패한 것이다.

    그 위에 앱 승인을 쌓으면 뒤 폴더가 모두 걸린다. 2026-10-02 사용자가 정했다. 검수 번호 모양이 아닌 이름도 남은 것으로 본다.
    예약 실행이 늦거나 한 번 건너뛸 수 있어 하루가 아니라 36시간을 넘은 것만 센다.
    """
    out = []
    for name in names:
        try:
            made = datetime.strptime(name[2:18], "%Y%m%dT%H%M%SZ").replace(tzinfo=now.tzinfo)
        except ValueError:
            out.append(name)
            continue
        if not name.startswith("r-") or (now - made).total_seconds() > hours * 3600:
            out.append(name)
    return out
