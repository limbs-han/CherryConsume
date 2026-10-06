"""카탈로그에 없는 카드의 새 초안. 작업 008 설계 3절. Databricks의 extract.py가 new_card 모드에서 부른다.

머리는 색인 행에서 코드가 채우고 규칙만 모델에 묻는다. 머리까지 모델에 맡기면 이름과 주소를 지어낸다.
모델이 적지 않은 실적 규칙, 신규 회원, 혜택 제외는 카드사 기본값을 따르고 확인 필요 항목을 단다.
"""

from __future__ import annotations

import re
from collections import Counter
from datetime import date

from pydantic import ValidationError

from cherry_core.catalog.canonical import canonical_text, normalize
from cherry_core.pipeline.disclosure import IndexRow, collectable
from cherry_core.pipeline.draft import (
    SECTIONS,
    card_content,
    check_draft,
    clean_rules,
    fill_defaults,
    int_keys,
    issuer_defaults,
    model_questions,
)
from cherry_core.pipeline.extract import Outcome, invalid
from cherry_core.pipeline.prompt import parse_answer

# 색인 원문의 종류와 카드 파일의 원문 id. 카탈로그 카드도 상품 페이지는 page, 상품설명서는 manual을 많이 쓴다
SOURCE_IDS = {"product_page": "page", "manual_pdf": "manual"}
NOTES = "새 카드 초안. 머리는 색인에서, 규칙은 모델이 원문에서 옮겼다. 연회비와 짧은 이름은 사람이 채운다."
KIND_REASON = "카드 종류를 색인과 원문에서 확인하지 못했다. 신용인지 체크인지 사람이 정한다"
FORMAT_REASON = "규칙 형식 오류"  # extract.invalid가 까닭 앞에 붙인다
_SPACE = re.compile(r"\s+")
# 카드 종류의 근거 문장. 메뉴의 "신용카드" 한 낱말이 근거로 통과하지 않게 길이를 본다. 2026-10-05 위험 검토
MIN_EVIDENCE = 10


# 이름으로 카드 종류를 추정하는 카드사. 롯데는 공시실에 종류가 없고 신용, 체크 목록이 판매 중 카드의 절반쯤만 담는다.
# 2026-10-06 목록 130장 모두 이름에 "체크"가 있으면 체크카드, 없으면 신용카드였다. 추정이라 확인 필요 항목을 단다
NAME_KIND_ISSUERS = {"lotte"}


def name_kind(issuer: str, name: str) -> str | None:
    """이름으로 추정한 카드 종류. 추정하지 않는 카드사면 None이다."""
    if issuer not in NAME_KIND_ISSUERS:
        return None
    return "check" if "체크" in name else "credit"


class KindUnknown(ValueError):
    """색인에도 원문에도 카드 종류의 근거가 없다. 다시 물어도 나아지지 않아 사람이 정한다."""


def card_head(row: dict, docs: list[tuple[str, str, date, str]], fetched: date) -> dict:
    """색인 행으로 만든 카드 파일 머리. docs는 (원문 종류, 주소, 받은 날, 글)이다. 모델에 묻지 않는다."""
    head = {
        "schema_version": 2,
        "id": row["card_id"],
        "issuer": row["issuer"],
        "name": row["name"],
        "kind": row["kind"],
        "product_codes": [row["code"]] if row.get("code") else [],
        "status": row["status"],
    }
    if row["status"] == "discontinued" and row.get("discontinued_on"):
        head["status_since"] = row["discontinued_on"]
    head["sources"] = [
        {"id": SOURCE_IDS[kind], "kind": kind, "url": url, "fetched_at": day} for kind, url, day, _ in docs
    ]
    head["checked_at"] = fetched
    return head


def _kind(head: dict, extracted: dict, texts: list[str]) -> tuple[str, dict | None]:
    """(카드 종류, 확인 필요 항목). 색인에 없으면 모델이 고른 종류를 근거 문장이 원문에 그대로 있을 때만 쓴다."""
    if head["kind"]:
        return head["kind"], None
    kind, evidence = extracted.get("kind"), _SPACE.sub(" ", str(extracted.get("kind_evidence") or "")).strip()
    said = {"credit": "신용" in evidence, "check": "체크" in evidence or "CHECK" in evidence.upper()}
    # 근거는 원문에 그대로 있고, 충분히 길고, 고른 종류의 낱말만 든 문장이어야 한다
    if (
        kind not in said
        or len(_SPACE.sub("", evidence)) < MIN_EVIDENCE
        or [k for k, yes in said.items() if yes] != [kind]
        or evidence not in _SPACE.sub(" ", "\n".join(texts))
    ):
        guess = name_kind(head["issuer"], head["name"])
        if guess is None:
            raise KindUnknown(KIND_REASON)
        word = "체크카드" if guess == "check" else "신용카드"
        return guess, {
            "path": "kind",
            "question": f"원문에서 카드 종류를 찾지 못해 이름으로 {word}로 추정했다. 카드사 공식 목록에서 이름에 체크가 든 카드만 "
            "체크카드였다. 확인한다",
        }
    return kind, {"path": "kind", "question": f'카드 종류를 원문 문장 "{evidence}"로 정했다. 확인한다'}


def make_new_card(head: dict, issuer: dict | None, extracted: dict, fetched: date, texts: list[str]) -> dict:
    """머리와 모델 답으로 카드 파일을 만든다. 규칙은 카드사 기본값으로 채워 검사하고 기본값과 같은 칸은 적지 않는다."""
    kind, kind_question = _kind(head, extracted, texts)
    raw = int_keys(extracted["rules"])
    here = "revisions[0]"
    questions = [kind_question] if kind_question else []
    day = extracted.get("effective_from")
    estimated = day is None or day > fetched
    if day is None:
        questions.append(
            {"path": f"{here}.effective_from", "question": "원문에서 시행일을 찾지 못해 수집한 날로 두었다"}
        )
    elif day > fetched:
        # 첫 개정이 미래에서 시작하면 그 전의 결제는 계산할 개정이 없다. 2026-10-05 위험 검토
        questions.append(
            {
                "path": f"{here}.effective_from",
                "question": f"원문 시행일 {day}가 받은 날보다 뒤라 받은 날로 두었다. 그 전부터 쓰던 혜택인지 확인한다",
            }
        )
    if estimated:
        day = fetched
    # 카드에는 그날 카드사 파일이 채우는 값과 다른 칸만 적는다. 그날 기본값이 아직 없으면 받은 날의 기본값으로 채우고
    # 카드에 그대로 적는다. 프롬프트와 다시 묻기는 받은 날의 기본값을 보여 준다. 2026-10-05 위험 검토
    then = issuer_defaults(issuer, day)
    defaults = then or issuer_defaults(issuer, fetched)
    if defaults and not then:
        questions.append(
            {
                "path": here,
                "question": "카드사 기본값이 시행일 뒤에 시작해 받은 날의 기본값을 카드에 그대로 적었다. 확인한다",
            }
        )
    rules = clean_rules(fill_defaults(raw, defaults))
    entry = {"effective_from": day, "source": extracted["source"], **card_content(rules, then)}
    if estimated:
        entry["effective_from_estimated"] = True
    card = {**head, "kind": kind, "revisions": [entry]}
    for k in SECTIONS:
        base, mine = defaults.get(k) or {}, raw.get(k)
        missing = sorted(set(base) - set(mine or {})) if isinstance(mine, dict) or mine is None else []
        if missing:
            where = k if mine is None else f"{k}의 {', '.join(map(str, missing))}"
            questions.append({"path": here, "question": f"{where}: 원문에서 찾지 못해 카드사 기본값을 따른다"})
        if not isinstance(mine, dict) or not mine:
            continue
        # 실적 규칙에는 근거 문장 칸이 없다. 모델이 적은 값이 기본값과 다르면 형식 예시를 베꼈을 수 있다. 위험 검토
        if not base:
            fields = ", ".join(sorted(map(str, mine)))
            questions.append(
                {
                    "path": here,
                    "question": f"{k}의 {fields}: 카드사 기본값이 없어 원문에서 옮긴 값이다. 원문과 맞는지 확인한다",
                }
            )
            continue
        moved = sorted(str(f) for f, v in mine.items() if f not in base or normalize(v, f) != normalize(base[f], f))
        if moved:
            questions.append(
                {
                    "path": here,
                    "question": f"{k}의 {', '.join(moved)}: 원문에서 읽은 값이 카드사 기본값과 다르다. 원문과 맞는지 확인한다",
                }
            )
    # 프롬프트는 금액을 못 찾은 한도를 빼라고 한다. 새 카드는 견줄 지금 값이 없어 한도 없는 혜택마다 묻는다
    for b in rules.get("benefits", []):
        if not b.get("limits"):
            questions.append(
                {"path": here, "question": f"benefits[{b['key']}]: 한도를 적지 않았다. 원문에 한도가 없는지 확인한다"}
            )
    questions += [q for q in model_questions(card, here, extracted) if q not in questions]
    if questions:
        card["open_questions"] = questions
    card["notes"] = NOTES
    return card


def process_new_card(
    files: dict[str, str],
    head: dict,
    issuer: dict | None,
    response: str | None,
    error: str | None,
    fetched: date,
    texts: list[str],
) -> Outcome:
    """모델 답 하나를 새 카드 초안으로 바꾼다. 결과의 뜻은 extract.process_answer와 같다."""
    if error or response is None:
        return Outcome("model_error", f"모델 호출 실패: {error}")
    try:
        card = make_new_card(head, issuer, parse_answer(response), fetched, texts)
    except KindUnknown as e:
        return Outcome("needs_human", str(e))
    except ValidationError as e:
        return invalid(e)
    except Exception as e:  # noqa: BLE001 모델의 답은 어떤 모양이든 올 수 있다. 무엇이든 사람이 본다
        return Outcome("needs_human", f"답을 초안으로 바꾸지 못했다: {type(e).__name__}: {e}"[:500])
    path = f"cards/{head['issuer']}/{head['id']}.yaml"
    return Outcome("draft", draft_yaml=canonical_text(card), problems=check_draft(files, path, card))


def drafted_cards(drafts: list[tuple[str, str, str | None]], typed: set[str]) -> set[str]:
    """새 초안을 다시 만들지 않을 카드. drafts는 new_card 모드 초안의 (카드, 결과, 까닭), typed는 색인에 종류가 있는 카드다.

    모델 호출이 실패한 카드와, 종류를 몰라 사람에게 넘겼는데 그 뒤 색인이 종류를 알게 된 카드는 다시 고른다.
    종류 때문에 넘긴 카드는 초안이 없어 사람이 처음부터 써야 하기 때문이다.
    모델 호출이 두 번 실패한 카드는 다시 고르지 않는다. 늘 실패하는 카드가 앞자리를 차지해 다른 카드가 멈추지 않게 한다.
    규칙 형식 오류로 넘긴 카드는 한 번만 다시 고른다. 2026-10-06 첫 전체 추출의 형식 오류 대부분이 카탈로그 포인트 목록에
    없는 포인트라, 목록을 채운 뒤 다시 물으면 초안이 생긴다. 두 번째도 형식 오류면 사람에게 둔다.
    """
    errors = Counter(cid for cid, status, _ in drafts if status == "model_error")
    formats = Counter(cid for cid, status, reason in drafts if (reason or "").startswith(FORMAT_REASON))
    return {
        cid
        for cid, status, reason in drafts
        if status != "model_error"
        and not (reason == KIND_REASON and cid in typed)
        and not ((reason or "").startswith(FORMAT_REASON) and formats[cid] == 1)
    } | {cid for cid, n in errors.items() if n >= 2}


def pick_new_cards(
    rows: list[dict],
    catalog_ids: set[str],
    drafted: set[str],
    docs: dict[str, dict],
    today: date,
    issuers: set[str] | None = None,
    limit: int | None = None,
) -> list[tuple[dict, list[tuple[str, str, dict]]]]:
    """새 초안을 만들 색인 행과 그 원문 (원문 종류, 주소, 문서). docs는 주소마다 가장 최근 문서다.

    카탈로그에 있거나 이미 초안이 있는 카드, 법인 카드와 3년 넘게 전에 단종된 카드, 원문이 없는 카드는 뺀다.
    원문은 상품 페이지와 가장 최근 PDF 하나다. 수집기가 받는 것과 같다. 카드다모아 추천 카드, 설문으로 요청이 온 카드를 먼저 고른다.
    """
    out = []
    for r in rows:
        if r["card_id"] in catalog_ids or r["card_id"] in drafted or (issuers and r["issuer"] not in issuers):
            continue
        row = IndexRow(r["issuer"], r["name"], status=r["status"], discontinued_on=r["discontinued_on"])
        if not collectable(row, today):
            continue
        urls = (("product_page", r["page_url"]), ("manual_pdf", next(iter(r["pdf_urls"] or []), None)))
        found = [(kind, url, docs[url]) for kind, url in urls if url and url in docs]
        if found:
            out.append((r, found))
    out.sort(key=lambda x: (not x[0]["recommended"], not x[0].get("requested"), x[0]["issuer"], x[0]["name"]))
    return out[:limit] if limit else out
