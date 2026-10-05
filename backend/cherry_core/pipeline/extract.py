"""추출 답 하나를 초안과 검수 대기로 바꾼다. 설계 1절 4단계와 5단계. Databricks의 extract.py가 부른다.

답은 parse_answer, make_draft, check_draft 순서로 처리한다. 쓸 수 없는 답은 버리지 않고 사람이 정할 것으로 남긴다.
카드가 바뀌었다는 신호를 아무도 모르게 되기 때문이다. 검사에 걸린 초안도 걸린 이유와 함께 남긴다.
모델 호출이 실패한 것은 답이 아니라서 사람에게 넘기지 않고 다음 실행에서 다시 추출한다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

from pydantic import ValidationError

from cherry_core.catalog.canonical import canonical_text
from cherry_core.pipeline.draft import check_draft, clean_rules, fill_defaults, int_keys, make_draft
from cherry_core.pipeline.prompt import parse_answer

QUEUED = ("draft", "needs_human")  # 검수 대기에 오르는 결과


@dataclass(frozen=True)
class Outcome:
    status: str  # no_change, draft, needs_human, model_error
    reason: str | None = None
    draft_yaml: str | None = None
    problems: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)  # 규칙 형식 오류의 칸마다 문구. 있으면 한 번 더 묻는다


def process_answer(
    files: dict[str, str],
    path: str,
    card: dict,
    issuer: dict | None,
    response: str | None,
    error: str | None,
    fetched: date,
    keep_current: bool = False,
) -> Outcome:
    """files는 카탈로그 파일 전체, path는 이 카드 파일 경로, response와 error는 ai_query의 failOnError false 결과다.

    keep_current는 바뀐 원문 추출에서 켠다. draft.make_draft와 같다.
    """
    if error or response is None:
        return Outcome("model_error", f"모델 호출 실패: {error}")
    try:
        draft = make_draft(card, issuer, parse_answer(response), fetched, keep_current)
        if draft is None:
            return Outcome("no_change")
        return Outcome("draft", draft_yaml=canonical_text(draft), problems=check_draft(files, path, draft))
    except ValidationError as e:
        return invalid(e)
    except Exception as e:  # noqa: BLE001 모델의 답은 어떤 모양이든 올 수 있다. 무엇이든 사람이 본다
        return Outcome("needs_human", f"답을 초안으로 바꾸지 못했다: {type(e).__name__}: {e}"[:500])


def invalid(e: ValidationError) -> Outcome:
    """규칙 형식 오류. 칸마다의 오류를 붙여 한 번 더 묻는다. 새 카드 초안도 쓴다."""
    where = ", ".join(".".join(map(str, x["loc"])) for x in e.errors()[:3])
    return Outcome("needs_human", f"규칙 형식 오류 {e.error_count()}곳: {where}", errors=_errors(e))


def _errors(e: ValidationError) -> list[str]:
    """칸마다 오류 문구. 입력값은 넣지 않는다. 다시 묻는 프롬프트에 붙인다."""
    return [f"{'.'.join(map(str, x['loc']))}: {x['msg']}" for x in e.errors()[:20]]


def retry_errors(out: Outcome, response: str | None, defaults: dict | None) -> list[str]:
    """한 번 더 물을 때 알려 줄 규칙 형식 오류. 비면 다시 묻지 않는다. 설계 1절 4단계 판 7.

    defaults는 정답 예시 모드에서 넘기는 카드사 기본값이다. 채점처럼 채워 보고 남는 오류만 돌려준다.
    채울 수 있는 칸의 오류까지 알려 주면 모델이 값을 지어 기본값을 덮는다. 2026-10-02 다시 검토.
    바뀐 원문 모드는 빠진 실적 규칙을 이미 지금 값으로 채웠으므로 None이다. 두 모드가 같은 누락에 같이 움직이게 한다.
    """
    if not out.errors or not defaults:
        return out.errors
    try:
        clean_rules(fill_defaults(int_keys(parse_answer(response)["rules"]), defaults))
    except ValidationError as e:
        return _errors(e)
    except Exception:  # noqa: BLE001 채워 보지도 못하면 처음 오류를 그대로 알려 준다
        return out.errors
    return []


def pending_changes(changes: list[tuple[str, str]], drafts: list[tuple[list[str], str]]) -> dict[str, list[str]]:
    """카드마다 아직 추출하지 않은 변경 행의 새 경로.

    changes는 silver.changes의 (카드, 새 경로), drafts는 changes 모드 silver.drafts의 (쓴 변경 경로, 결과)다.
    모델 호출이 실패한 초안이 쓴 변경은 끝나지 않은 것으로 본다.
    """
    done = {p for paths, status in drafts if status != "model_error" for p in paths or []}
    out: dict[str, list[str]] = {}
    for card_id, path in changes:
        if path not in done and path not in out.get(card_id, []):
            out.setdefault(card_id, []).append(path)
    return out


def unqueued(drafts: list[tuple[str, str]], queued: set[str]) -> list[str]:
    """검수 대기에 올라야 하는데 빠진 초안. drafts는 changes 모드의 (초안 번호, 결과)다.

    초안을 쓴 뒤 검수 대기를 쓰기 전에 실행이 끊기면 그 변경은 끝난 것으로 남아 다시 추출되지 않는다.
    다음 실행이 시작할 때 이 목록을 검수 대기에 다시 올린다. 모델 요금은 들지 않는다.
    """
    return [d for d, status in drafts if status in QUEUED and d not in queued]


def superseded(rows: list[tuple[object, str, object, str]]) -> list[str]:
    """열린 검수 대기 가운데 같은 카드의 더 새 초안이 있는 초안. rows는 (카드, 초안 번호, 초안 시각, 결과)다.

    쌓인 초안은 원문이 바뀌면 낡는다. 같은 카드의 새 초안이 생기면 옛 건을 superseded로 닫고 새 초안만 보인다.
    작업 008 설계 5절. 다시 올린 옛 초안이 새 초안을 닫지 않게 올린 순서가 아니라 초안 시각으로 본다.
    쓸 글이 없는 needs_human은 그보다 옛 draft를 닫지 않는다. 2026-10-05 위험 검토
    """
    out = set()
    for card, d, at, status in rows:
        if any(c == card and (a, n) > (at, d) and (s == "draft" or status != "draft") for c, n, a, s in rows):
            out.add(d)
    return sorted(out)  # ponytail: 카드마다 열린 건이 몇 개라 이중 반복으로 둔다
