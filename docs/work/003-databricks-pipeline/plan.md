# 003 계획

> **에이전트가 실행할 때:** superpowers:subagent-driven-development로 과제마다 새 에이전트를 띄우고 과제 사이에 검토한다. 한 세션에서 직접 하면 superpowers:executing-plans를 쓴다. 단계는 `- [ ]` 체크박스로 표시하고 끝나면 `- [x]`로 바꾼다.

**목표:** 카드사 원문을 Databricks에 쌓고 LLM이 카탈로그 2판 초안을 만들게 한다. 사람이 승인한 개정만 골드와 git에 들어가게 해서 intent.md의 성공 기준을 채운다.

**구조:** 세 곳에 나눠 둔다.
- `backend/cherry_core/pipeline/`: 어디서나 도는 순수 Python이다. 수집기, 글 뽑기와 지문, 초안, 프롬프트, 채점, 비용 한도, 내보내기가 여기 있다. PC에서 테스트한다.
- `pipeline/`: Databricks 번들이다. 파이프라인, 작업, 앱 정의와 Databricks에서만 도는 코드를 둔다. `cherry_core`를 wheel로 올려 쓴다.
- `.github/workflows/`: 수집, 배포, 내보내기다.

**기술:** Python 3.12, uv, Pydantic 2, pytest, ruff, Playwright, Databricks CLI와 번들, Lakeflow 파이프라인, Auto Loader, `ai_parse_document`, `ai_query`, MLflow, Databricks 앱, GitHub Actions. 셸은 Git Bash다.

**코드의 근거:** 2026-09-29 임시 폴더에서 먼저 돌려 봤다.
- 과제 1부터 8까지의 코드와 테스트: 기존 81개에 49개를 더해 130개가 통과했고 ruff 검사도 통과했다.
- 실제 카드 20장: 원문이 같으면 초안이 0건이었다. 카드마다 혜택 값 하나를 바꾼 초안 20건은 모두 검증을 통과했다. 이 시험에서 문제 두 가지를 찾아 코드에 반영했다. 하나는 IBK 한도 조정의 "제한 없음" null이 기본값을 빼는 단계에서 사라지던 것이다. 다른 하나는 카드사 기본값에 없는 필수 칸이나, 모델 기본값과 같은 카드 값이 카드 개정에서 빠지던 것이다.
- 수집기: 신한카드만 받아 10건을 저장했고 실패는 0건이었다. 상품 페이지에서는 혜택 글이 나왔지만 상품 목록과 공지 페이지는 자바스크립트로 그려서 빈 틀만 받았다. 과제 9와 16에서 다룬다.
- 과제 12부터 22까지의 Databricks 코드는 미리 쓰지 않았다. 가입 전에는 돌려 볼 수 없고, 가입하면 체험 14일이 흐른다. 그 과제들에는 확인할 공식 문서, 만들 파일과 모양, 검증 기준을 적었다. 코드는 과제를 시작할 때 공식 문서를 열고 작은 시험부터 돌려 쓴다.

**시작 조건:** 작업 001이 끝난 뒤 시작한다. 과제 1이 작업 001의 모델을 고치고, 정답 예시가 작업 001에서 사람이 확인한 카드들이기 때문이다.

**걸리는 시간**

| 과제 | 시간 |
|---|---|
| 1~8 순수 코드 | 2시간. 코드가 아래에 모두 있어 옮겨 쓰며 테스트를 돌린다 |
| 9 수집기 PC 시험 | 카드사 8곳에 1~2시간 |
| 10 근거 문장 채우기 | 에이전트 6개를 동시에 돌려 3~4시간, 대조에 1~2시간 |
| 11 사용자 안내서와 권한 | 1시간 |
| 12~13 가입, 번들, 비용 차단, 첫 운영 배포 | 사용자 1시간, Claude 반나절 |
| 14~16 수집 올리기, 브론즈와 실버, 변경 감지 | 하루 |
| 17~19 골드 첫 적재, 추출, 채점과 모델 고르기 | 하루에서 이틀. 프롬프트를 몇 번 다듬느냐에 따른다 |
| 20 검수 앱 | 반나절 |
| 21~22 내보내기, 계보 | 반나절 |
| 23~24 성공 기준, 문서 합치기 | 반나절 |

과제 12부터 24까지가 5일쯤이라 체험 14일 안에 끝난다. 과제 1부터 11은 가입 전에 한다.

## 설계 단계

- [x] 의도와 방식 선택. 검증: 사용자 확정 2026-09-29. 현업식 A
- [x] 4절 "정할 것" 1~11. 검증: 사용자 확정 2026-09-29
- [x] design.md 전체 검토와 빈틈 반영. 검증: 사용자 확정 2026-09-29
- [x] 구현 계획 검토. 이 문서. 검증: 사용자 승인 2026-09-29. 과제 19의 모델 고르는 기준도 제안대로 승인받았다

## 지켜야 할 것

모든 과제에 적용한다.

- 카탈로그 금액은 원 단위 정수다. Databricks 비용은 달러이고 `Decimal`로 다룬다. 부동소수점으로 돈을 계산하지 않는다.
- 카탈로그 값은 카드사 공식 원문에서만 온다. LLM 초안도 사람이 승인하기 전에는 골드와 git에 들어가지 않는다.
- 원문은 GitHub에 올리지 않고 Databricks 볼륨에만 둔다. 공개 저장소의 실행 기록은 누구나 보므로 원문 내용과 비밀값을 찍지 않는다. 개수와 id만 찍는다.
- Databricks 주소와 인증값은 GitHub 저장소 비밀값과 사용자 PC의 CLI 설정에만 둔다. 저장소에 넣지 않는다.
- Databricks 계정, 결제 정보, 토큰과 비밀값 발급, 예산 알림, GitHub 비밀값 등록은 사용자가 한다. Claude는 `docs/databricks.md`의 순서대로 무엇을 누르고 무엇이 보이면 성공인지 안내하고, 사용자가 붙여 준 결과로 확인한다.
- 비용 차단 작업이 서기 전에는 LLM 추출과 채점을 돌리지 않는다. 체험 중에는 결제 정보를 넣지 않는다.
- 커밋은 사용자가 커밋을 요청했거나 계획 실행을 맡기며 커밋까지 허락했을 때만 한다. 절차는 `/commit` 스킬이고 `--no-verify`는 쓰지 않는다. 푸시는 요청받을 때만 한다. 과제 13부터는 master 푸시가 운영 배포를 일으키므로 푸시 전에 무엇이 배포되는지 사용자에게 말한다.
- 비밀값을 쓰는 워크플로, 비용 차단 작업, 내보내기 워크플로는 커밋 전에 `risk-reviewer` 에이전트로 검토한다.
- Databricks 과제는 시작할 때 과제에 적힌 공식 문서를 다시 읽는다. 문서가 이 계획과 다르면 design.md를 먼저 고치고 사용자에게 알린다.
- 명령은 저장소 루트에서 실행한다.
  - 테스트: `uv run --project backend pytest -q`
  - 카탈로그 검증: `uv run --project backend python -m cherry_core.catalog check`
  - 번들: `cd pipeline && databricks bundle validate`, `databricks bundle deploy -t dev`

## 파일

```text
backend/cherry_core/catalog/models.py      고침. 혜택 근거 문장 칸, 제한 없음 null 보존
backend/cherry_core/catalog/canonical.py   고침. 근거 문장 칸 순서
backend/cherry_core/pipeline/__init__.py
backend/cherry_core/pipeline/text.py       글 뽑기, 지문, 바뀐 줄
backend/cherry_core/pipeline/collect.py    수집기
backend/cherry_core/pipeline/draft.py      초안 만들기와 검사
backend/cherry_core/pipeline/prompt.py     추출 프롬프트와 답 형식
backend/cherry_core/pipeline/score.py      칸마다 정확도
backend/cherry_core/pipeline/cost.py       비용 차단 금액
backend/cherry_core/pipeline/export.py     승인된 파일을 저장소로 옮기기
backend/tests/pipeline/                    위 모듈마다 test_*.py와 conftest.py
pipeline/databricks.yml                    번들. dev와 prod
pipeline/resources/                        스키마, 볼륨, 파이프라인, 작업, 앱, 실험 정의
pipeline/src/                              Databricks에서만 도는 코드
pipeline/apps/review/                      검수 앱
.github/workflows/collect.yml              수집
.github/workflows/deploy.yml               운영 배포
.github/workflows/export.yml               승인된 파일 커밋
docs/databricks.md                         사용자 안내
.claude/settings.json                      계정과 비밀값 명령 막기
.claude/CLAUDE.md                          자동 커밋 예외
```

Databricks 안의 이름이다. 카탈로그는 `cherry`다. 개발용으로 배포하면 번들이 스키마 이름 앞에 개발자 이름을 붙인다.

| 이름 | 종류 | 담는 것 |
|---|---|---|
| `cherry.bronze.raw` | 볼륨 | 수집기가 올린 원문 파일과 `manifests/` 목록 파일 |
| `cherry.bronze.fetches` | 테이블 | 목록 파일 한 줄이 한 행. 카드사, 카드, 원문 id, 주소, 경로, 받은 시각, sha256 |
| `cherry.silver.documents` | 테이블 | 원문 파일마다 뽑은 글, 지문, 글을 뽑은 방법 |
| `cherry.silver.changes` | 테이블 | 원문마다 지난번과 달라진 경우의 없어진 줄과 새 줄 |
| `cherry.silver.card_lists` | 테이블 | 카드사 목록 글에서 뽑은 카드 이름 |
| `cherry.silver.drafts` | 테이블 | 추출 답, 초안 YAML, 검사 결과, 모델, 프롬프트 판 |
| `cherry.silver.queue` | 테이블 | 검수 대기. 초안, 새 카드, 사라진 카드, 사람이 정할 것 |
| `cherry.silver.reviews` | 테이블 | 승인과 반려, 사람이 고친 YAML, 검수한 사람과 시각 |
| `cherry.silver.golden` | 테이블 | 정답 예시. 카드, 다듬기용과 채점 전용 구분, 원문 경로, 정답 규칙 |
| `cherry.gold.catalog_files` | 테이블 | 카탈로그 파일마다 경로와 고정 형식 YAML, 검수 기록 번호 |
| `cherry.gold.card_revisions` | 테이블 | 카드 개정마다 합친 규칙. 앱 DB가 읽는다 |
| `cherry.gold.export` | 볼륨 | 승인마다 내보낸 파일. `pending/`과 `done/` |

---

## 과제 1: 혜택 근거 문장 칸과 제한 없음 null 보존

혜택마다 값이 나온 원문 문장을 담는 칸을 더한다. 설계 4절 6번. 또 한도 조정의 `amount: null`은 "제한 없음"인데, 기본값을 빼고 저장하면 사라진다. 초안을 만들 때 기본값을 빼고 비교하므로 이 null이 남게 한다.

**Files:**
- Modify: `backend/cherry_core/catalog/models.py`
- Modify: `backend/cherry_core/catalog/canonical.py`
- Test: `backend/tests/catalog/test_models.py`, `backend/tests/catalog/test_canonical.py`

**Interfaces:**
- Produces: `Benefit.evidence: list[str]`, 기본값 `[]`. 빈 글자는 받지 않는다. 고정 형식에서 `source` 바로 뒤에 온다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/catalog/test_models.py` 맨 위 가져오기에 `Benefit`을 더한다.

```python
from cherry_core.catalog.models import Adjust, Benefit, Condition, Fact, Limit, Option, Reward, SharedLimit, Target
```

파일 끝에 더한다.

```python
def test_evidence_sentences_are_not_empty():
    base = {"key": "k", "title": "t", "target": {"all": True}, "reward": {"type": "cashback", "rate": 1}}
    assert Benefit.model_validate(base).evidence == []
    assert Benefit.model_validate({**base, "evidence": ["전 가맹점 1% 캐시백"]}).evidence == ["전 가맹점 1% 캐시백"]
    with pytest.raises(ValidationError):
        Benefit.model_validate({**base, "evidence": [""]})


def test_null_limit_survives_dump_without_defaults():
    limit = Limit(per="month", amount=10000, adjust=[{"when": {"region": "overseas"}, "amount": None}])
    assert limit.model_dump(exclude_defaults=True)["adjust"] == [{"when": {"region": "overseas"}, "amount": None}]
```

`backend/tests/catalog/test_canonical.py` 끝에 더한다.

```python
def test_evidence_comes_after_source():
    b = {"reward": {"type": "cashback", "fixed": 1000}, "evidence": ["월 1천원 캐시백"], "source": "page", "key": "k"}
    assert list(yaml.safe_load(canonical_text(b))) == ["key", "source", "evidence", "reward"]
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/catalog
```

기대: 새 테스트 3개가 실패한다. 근거 문장은 extra 칸이라 거부되고, null은 사라지고, 순서가 다르다.

- [x] **3단계: 모델을 고친다**

`models.py`의 pydantic 가져오기에 `model_serializer`를 더한다.

```python
from pydantic import BaseModel, ConfigDict, Field, model_serializer, model_validator
```

`Adjust.check_adjust` 바로 뒤에 더한다.

```python
    @model_serializer(mode="wrap")
    def keep_null_limit(self, handler: Any) -> dict:
        """null은 제한 없음이라 기본값을 빼고 저장할 때도 적어 둔 null은 남긴다."""
        data = handler(self)
        for name in ("amount", "count", "base"):
            if name in self.model_fields_set and getattr(self, name) is None:
                data[name] = None
        return data
```

`Benefit`의 `source` 다음 줄에 더한다.

```python
    evidence: list[Annotated[str, Field(min_length=1)]] = []
```

`canonical.py`의 `BENEFIT_ORDER`에서 `"source",` 다음 줄에 `"evidence",`를 더한다.

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q
uv run --project backend python -m cherry_core.catalog check | tail -2
uvx ruff check backend && uvx ruff format --check backend
```

기대: 모두 통과. 카탈로그 오류 0, 경고 0.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/catalog backend/tests/catalog
git commit -m "feat: 혜택 근거 문장 칸과 제한 없음 null 보존 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 3개가 먼저 실패하고 고친 뒤 통과했다. 전체 460개 통과, 카탈로그 오류 0, ruff 통과. 작업 004에서 더한 `test_mockup.py`가 ruff 형식에 맞지 않아 형식만 맞췄다.

---

## 과제 2: 원문 글 뽑기와 지문

받은 파일에서 글을 뽑고, 줄바꿈과 공백만 다른 글은 같은 지문이 나오게 한다. 설계 1절 2단계와 3단계. `ai_parse_document`는 HTML을 받지 않으므로 HTML은 코드로 뽑는다. PDF는 그 함수의 결과를 받아 글로 바꾼다. 한국 카드사 페이지에는 EUC-KR로 된 곳이 있어 charset을 따른다.

**Files:**
- Create: `backend/cherry_core/pipeline/__init__.py`, `backend/cherry_core/pipeline/text.py`
- Test: `backend/tests/pipeline/__init__.py`, `backend/tests/pipeline/conftest.py`, `backend/tests/pipeline/test_text.py`

**Interfaces:**
- Produces: `lines(text) -> list[str]`, `fingerprint(text) -> str`, `changed_lines(old, new) -> tuple[list[str], list[str]]`, `html_text(html) -> str`, `parsed_text(parsed: dict) -> str`, `document_text(content: bytes, content_type: str, parsed: dict | None = None) -> str`

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/__init__.py`는 빈 파일이다. `backend/tests/pipeline/conftest.py`:

```python
"""카탈로그 테스트의 임시 카탈로그를 파이프라인 테스트에서도 쓴다."""

from tests.catalog.conftest import make_catalog  # noqa: F401
```

`backend/tests/pipeline/test_text.py`:

```python
"""원문에서 글 뽑기, 지문, 바뀐 줄. 설계 1절 2단계와 3단계."""

import pytest

from cherry_core.pipeline.text import changed_lines, document_text, fingerprint, html_text, lines


def test_lines_ignore_spacing_and_blank_lines():
    assert lines("  카페 10%   할인\n\n\t월 최대 1만원 \n") == ["카페 10% 할인", "월 최대 1만원"]


def test_same_text_with_different_spacing_has_same_fingerprint():
    assert fingerprint("카페 10%  할인\n\n월 최대 1만원") == fingerprint("카페 10% 할인\n월 최대 1만원 ")


def test_one_digit_changes_fingerprint():
    assert fingerprint("카페 10% 할인") != fingerprint("카페 5% 할인")


def test_changed_lines():
    assert changed_lines("a\nb\nc", "a\nc\nd") == (["b"], ["d"])


def test_moved_line_is_not_a_change():
    assert changed_lines("a\nb", "b\na") == ([], [])


def test_html_text_keeps_table_rows_and_drops_scripts():
    html = (
        "<html><head><style>p{}</style><script>var a = 1</script></head><body>"
        "<h1>혜택</h1><p>카페 10%  할인<br>월 최대 1만원</p>"
        "<table><tr><th>구분</th><th>할인</th></tr><tr><td>카페</td><td>10%</td></tr></table>"
        "</body></html>"
    )
    assert html_text(html) == "혜택\n카페 10% 할인\n월 최대 1만원\n구분 | 할인\n카페 | 10%"


def test_euc_kr_page_from_meta_or_header():
    body = "<html><head><meta charset='euc-kr'></head><body><p>카페 할인</p></body></html>".encode("euc-kr")
    assert document_text(body, "text/html") == "카페 할인"
    assert document_text("<p>카페 할인</p>".encode("euc-kr"), "text/html; charset=EUC-KR") == "카페 할인"


def test_json_is_indented_text():
    assert document_text('{"a": "카드"}'.encode(), "application/json") == '{\n "a": "카드"\n}'


def test_pdf_uses_parse_result_and_keeps_table_rows():
    parsed = {
        "document": {
            "elements": [
                {"type": "title", "content": "혜택 안내"},
                {"type": "table", "content": "<table><tr><td>카페</td><td>10%</td></tr></table>"},
            ]
        }
    }
    assert document_text(b"%PDF-1.7 ...", "application/pdf", parsed) == "혜택 안내\n카페 | 10%"
    with pytest.raises(ValueError, match="ai_parse_document"):
        document_text(b"%PDF-1.7 ...", "application/pdf")
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_text.py
```

기대: `cherry_core.pipeline`이 없어 실패한다.

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/__init__.py`:

```python
"""카탈로그 파이프라인. 설계는 docs/work/003-databricks-pipeline/design.md."""
```

`backend/cherry_core/pipeline/text.py`:

```python
"""원문에서 글 뽑기, 본문 지문, 바뀐 줄. 설계 1절 2단계와 3단계."""

from __future__ import annotations

import codecs
import hashlib
import json
import re
from html.parser import HTMLParser

_SPACE = re.compile(r"\s+")
_CHARSET = re.compile(r"charset=[\"']?([\w-]+)", re.IGNORECASE)
_BLOCK = {"p", "div", "br", "li", "tr", "table", "section", "article", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6"}
_SKIP = {"script", "style", "noscript", "template"}


def lines(text: str) -> list[str]:
    """줄마다 공백을 하나로 줄이고 빈 줄은 뺀다. 줄바꿈과 공백만 다른 글은 같은 결과가 나온다."""
    return [s for s in (_SPACE.sub(" ", line).strip() for line in text.splitlines()) if s]


def fingerprint(text: str) -> str:
    return hashlib.sha256("\n".join(lines(text)).encode("utf-8")).hexdigest()


def changed_lines(old: str, new: str) -> tuple[list[str], list[str]]:
    """(없어진 줄, 새로 생긴 줄). 자리만 옮긴 줄은 바뀐 것으로 보지 않는다."""
    old_lines, new_lines = lines(old), lines(new)
    old_set, new_set = set(old_lines), set(new_lines)
    return [s for s in old_lines if s not in new_set], [s for s in new_lines if s not in old_set]


class _Text(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
        self.skip = 0

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag in _SKIP:
            self.skip += 1
        elif tag in ("td", "th"):
            self.parts.append(" | ")
        elif tag in _BLOCK:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in _SKIP:
            self.skip = max(0, self.skip - 1)
        elif tag in _BLOCK:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.skip:
            self.parts.append(data)


def html_text(html: str) -> str:
    """HTML에서 글만 뽑는다. ai_parse_document는 HTML을 받지 않아 코드로 한다.

    블록 태그는 줄을 나누고, 표의 칸은 ' | '로 이어 한 줄이 표의 한 행이 되게 한다.
    """
    parser = _Text()
    parser.feed(html)
    parser.close()
    return "\n".join(s.removeprefix("| ") for s in lines("".join(parser.parts)))


def parsed_text(parsed: dict) -> str:
    """ai_parse_document 결과의 글. 표는 HTML로 오므로 html_text로 행을 살린다."""
    parts = []
    for element in parsed["document"]["elements"]:
        content = element.get("content") or ""
        parts.append(html_text(content) if element.get("type") == "table" else content)
    return "\n".join(lines("\n".join(parts)))


def _charset(content_type: str, head: bytes) -> str:
    """응답 머리의 charset, 없으면 HTML meta의 charset, 둘 다 없거나 모르는 이름이면 utf-8."""
    m = _CHARSET.search(content_type) or _CHARSET.search(head.decode("ascii", "ignore"))
    if m:
        try:
            return codecs.lookup(m.group(1)).name
        except LookupError:
            pass
    return "utf-8"


def document_text(content: bytes, content_type: str, parsed: dict | None = None) -> str:
    """받은 파일 하나의 글. PDF는 ai_parse_document 결과로, JSON은 들여쓰기로, HTML은 html_text로 뽑는다."""
    if content.startswith(b"%PDF-"):
        if parsed is None:
            raise ValueError("PDF는 ai_parse_document 결과가 있어야 글을 뽑는다")
        return parsed_text(parsed)
    text = content.decode(_charset(content_type, content[:2048]), "replace")
    if "json" in content_type:
        return json.dumps(json.loads(text), ensure_ascii=False, indent=1)
    return html_text(text)
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_text.py
```

기대: 9개 통과.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline backend/tests/pipeline
git commit -m "feat: 원문 글 뽑기와 본문 지문 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 9개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 전체 469개 통과, ruff 통과.

---

## 과제 3: 수집기

카드사 파일의 `collect`와 카드 파일의 `sources`에 적힌 주소를 받아 날짜별 폴더에 원본 그대로 저장한다. 설계 4절 2번. robots.txt가 막은 주소는 받지 않고, `blocked`와 `manual` 카드사는 사람이 받아 온 파일을 `--add`로 더한다.

**Files:**
- Create: `backend/cherry_core/pipeline/collect.py`
- Test: `backend/tests/pipeline/test_collect.py`

**Interfaces:**
- Consumes: `cherry_core.catalog.load.load_catalog`
- Produces: `Target(issuer, card_id, source_id, kind, url, browser)`, `targets(root, interval=30, issuers=None) -> list[Target]`, `raw_path(t, day, body, content_type) -> str`, `allowed(url, robots_txt) -> bool`, 명령 `python -m cherry_core.pipeline.collect --out DIR [--interval 14|30] [--issuer ID] [--add FILE --card ID --source ID]`
- 저장 모양: `<out>/<YYYY-MM-DD>/<issuer>/<card_id 또는 _issuer>/<source_id>-<sha256 앞 12자>.<html|pdf|json>`과 `<out>/manifests/manifest-<UTC 시각>.jsonl`. 목록 한 줄은 `Target`의 칸에 `path`, `fetched_at`, `content_type`, `sha256`을 더한 JSON이다. 과제 15의 Auto Loader가 이 목록을 읽는다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/test_collect.py`:

```python
"""수집 대상과 저장 경로. 설계 4절 2번. 네트워크는 쓰지 않는다."""

import json
from datetime import date

from cherry_core.pipeline.collect import Target, allowed, main, raw_path, targets


def collect(method, interval_days=14):
    def edit(files):
        files["issuers/shinhan.yaml"]["collect"] = {
            "list_url": "https://www.shinhancard.com/list",
            "method": method,
            "interval_days": interval_days,
            "notice_url": "https://www.shinhancard.com/notice",
        }

    return edit


def test_api_issuer_lists_list_notice_and_card_sources(make_catalog):
    assert targets(make_catalog(collect("api"))) == [
        Target("shinhan", None, "list", "list", "https://www.shinhancard.com/list", False),
        Target("shinhan", None, "notice", "notice", "https://www.shinhancard.com/notice", False),
        Target("shinhan", "shinhan-test", "page", "product_page", "https://www.shinhancard.com/t", False),
    ]


def test_browser_issuer_opens_pages_in_browser(make_catalog):
    assert [t.browser for t in targets(make_catalog(collect("browser")))] == [True, True, True]


def test_blocked_and_manual_issuers_are_skipped(make_catalog):
    assert targets(make_catalog(collect("blocked"))) == []
    assert targets(make_catalog(collect("manual"))) == []


def test_interval_filter(make_catalog):
    root = make_catalog(collect("api", interval_days=30))
    assert targets(root, interval=14) == []
    assert len(targets(root, interval=30)) == 3


def test_issuer_filter(make_catalog):
    assert targets(make_catalog(collect("api")), issuers={"kb"}) == []


def test_raw_path():
    t = Target("shinhan", "shinhan-test", "page", "product_page", "https://x", False)
    # sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    assert (
        raw_path(t, date(2026, 10, 1), b"abc", "text/html") == "2026-10-01/shinhan/shinhan-test/page-ba7816bf8f01.html"
    )
    assert raw_path(t, date(2026, 10, 1), b"%PDF-1.7", "application/octet-stream").endswith(".pdf")
    issuer_list = Target("shinhan", None, "list", "list", "https://x", False)
    assert raw_path(issuer_list, date(2026, 10, 1), b"{}", "application/json").startswith(
        "2026-10-01/shinhan/_issuer/list-"
    )


def test_robots():
    robots = "User-agent: *\nDisallow: /card/\n"
    assert not allowed("https://x.com/card/1", robots)
    assert allowed("https://x.com/notice", robots)
    assert allowed("https://x.com/card/1", None)
    assert not allowed("https://x.com/a", "User-agent: cherryconsume-collector\nDisallow: /\n")


def test_add_manual_file_goes_to_same_layout_and_manifest(make_catalog, tmp_path, capsys):
    root, out = make_catalog(), tmp_path / "raw"
    page = tmp_path / "saved.html"
    page.write_bytes(b"<p>abc</p>")
    args = ["--root", str(root), "--out", str(out), "--add", str(page), "--card", "shinhan-test", "--source", "page"]
    assert main(args) == 0
    rel = capsys.readouterr().out.strip()
    assert (out / rel).read_bytes() == b"<p>abc</p>"
    [manifest] = (out / "manifests").glob("manifest-*.jsonl")
    line = json.loads(manifest.read_text(encoding="utf-8"))
    assert (line["issuer"], line["card_id"], line["source_id"], line["kind"], line["path"]) == (
        "shinhan",
        "shinhan-test",
        "page",
        "product_page",
        rel,
    )
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_collect.py
```

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/collect.py`:

```python
"""카드사 원문 수집기. GitHub Actions와 개발자 PC에서 돈다. 설계 4절 2번.

카드사 파일의 collect와 카드 파일의 sources에 적힌 주소를 받아 날짜별 폴더에 원본 그대로 저장한다.
실행 기록은 공개 저장소에서 누구나 보므로 원문 내용은 찍지 않고 개수와 id만 찍는다.
브라우저가 필요한 카드사는 Playwright로 연다. 실행할 때 `uv run --with playwright`로 더한다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.request
import urllib.robotparser
from contextlib import ExitStack
from dataclasses import asdict, dataclass
from datetime import UTC, date, datetime
from pathlib import Path
from typing import TextIO
from urllib.parse import urlsplit

from cherry_core.catalog.load import load_catalog

DEFAULT_ROOT = Path(__file__).resolve().parents[3] / "catalog"
AGENT = "cherryconsume-collector"
USER_AGENT = f"{AGENT} (+https://github.com/limbs-han/CherryConsume)"
DELAY_SECONDS = 2
PLAIN_KINDS = {"manual_pdf", "terms_pdf", "api"}


@dataclass(frozen=True)
class Target:
    issuer: str
    card_id: str | None  # None이면 카드사 상품 목록이나 공지
    source_id: str
    kind: str
    url: str
    browser: bool


def targets(root: Path, interval: int = 30, issuers: set[str] | None = None) -> list[Target]:
    """자동으로 받을 주소. method가 api나 browser이고 interval_days가 interval 이하인 카드사만 고른다."""
    cat = load_catalog(root)
    out = []
    for iid, loaded in sorted(cat.issuers.items()):
        c = loaded.issuer.collect
        if c is None or c.method not in ("api", "browser") or c.interval_days > interval:
            continue
        if issuers and iid not in issuers:
            continue
        browser = c.method == "browser"
        out.append(Target(iid, None, "list", "list", c.list_url, browser))
        if c.notice_url:
            out.append(Target(iid, None, "notice", "notice", c.notice_url, browser))
        for card in sorted((lc.card for lc in cat.cards.values() if lc.card.issuer == iid), key=lambda c: c.id):
            for s in card.sources:
                out.append(Target(iid, card.id, s.id, s.kind, s.url, browser and s.kind not in PLAIN_KINDS))
    return out


def raw_path(t: Target, day: date, body: bytes, content_type: str) -> str:
    """저장할 경로. 같은 날 같은 원문을 다시 받아도 이름이 같아 덮어쓰기만 된다."""
    sha = hashlib.sha256(body).hexdigest()
    ext = "pdf" if body.startswith(b"%PDF-") else "json" if "json" in content_type else "html"
    return f"{day:%Y-%m-%d}/{t.issuer}/{t.card_id or '_issuer'}/{t.source_id}-{sha[:12]}.{ext}"


def allowed(url: str, robots_txt: str | None) -> bool:
    """robots.txt가 막은 주소는 받지 않는다. robots.txt가 없으면 허용이다."""
    if robots_txt is None:
        return True
    rp = urllib.robotparser.RobotFileParser()
    rp.parse(robots_txt.splitlines())
    return rp.can_fetch(AGENT, url)


def _get(url: str) -> tuple[bytes, str]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read(), r.headers.get("Content-Type", "")


def _robots(url: str) -> str | None:
    """robotparser.read()와 같게 401, 403이면 전부 막힌 것으로, 그 밖의 4xx면 없는 것으로 본다."""
    parts = urlsplit(url)
    try:
        body, _ = _get(f"{parts.scheme}://{parts.netloc}/robots.txt")
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return "User-agent: *\nDisallow: /"
        if 400 <= e.code < 500:
            return None
        raise
    return body.decode("utf-8", "replace")


def save(out: Path, manifest: TextIO, t: Target, body: bytes, content_type: str, now: datetime) -> str:
    """원문을 날짜별 폴더에 쓰고 목록 파일에 한 줄 더한다. 브론즈는 이 목록 파일을 읽는다."""
    rel = raw_path(t, now.date(), body, content_type)
    (out / rel).parent.mkdir(parents=True, exist_ok=True)
    (out / rel).write_bytes(body)
    line = {**asdict(t), "path": rel, "fetched_at": now.isoformat(), "content_type": content_type}
    line["sha256"] = hashlib.sha256(body).hexdigest()
    manifest.write(json.dumps(line, ensure_ascii=False) + "\n")
    return rel


def _manual(root: Path, card_id: str, source_id: str) -> Target:
    """robots.txt로 막은 카드사는 사람이 받아 온 파일을 쓴다. 카드와 원문 id로 대상을 찾는다."""
    card = load_catalog(root).cards[card_id].card
    source = {s.id: s for s in card.sources}[source_id]
    return Target(card.issuer, card.id, source.id, source.kind, source.url, False)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.pipeline.collect")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--interval", type=int, choices=[14, 30], default=30)
    ap.add_argument("--issuer", action="append", help="이 카드사만 받는다. 여러 번 쓸 수 있다")
    ap.add_argument("--add", type=Path, help="사람이 받아 온 파일을 더한다. --card와 --source를 함께 쓴다")
    ap.add_argument("--card")
    ap.add_argument("--source")
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    now = datetime.now(UTC)
    manifest = args.out / "manifests" / f"manifest-{now:%Y%m%dT%H%M%SZ}.jsonl"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    if args.add:
        body = args.add.read_bytes()
        ctype = "application/pdf" if body.startswith(b"%PDF-") else "text/html"
        with manifest.open("a", encoding="utf-8") as out:
            print(save(args.out, out, _manual(args.root, args.card, args.source), body, ctype, now))
        return 0

    robots: dict[str, str | None] = {}
    saved = skipped = failed = 0
    with ExitStack() as stack, manifest.open("w", encoding="utf-8") as out:
        page = None
        for t in targets(args.root, args.interval, set(args.issuer or []) or None):
            host = urlsplit(t.url).netloc
            try:
                if host not in robots:
                    robots[host] = _robots(t.url)
                if not allowed(t.url, robots[host]):
                    skipped += 1
                    continue
                if t.browser:
                    if page is None:
                        from playwright.sync_api import sync_playwright

                        browser = stack.enter_context(sync_playwright()).chromium.launch()
                        stack.callback(browser.close)
                        page = browser.new_page(user_agent=USER_AGENT)
                    page.goto(t.url, wait_until="networkidle", timeout=60_000)
                    body, ctype = page.content().encode("utf-8"), "text/html"
                else:
                    body, ctype = _get(t.url)
            except Exception as e:  # noqa: BLE001 한 곳이 실패해도 나머지는 받는다
                failed += 1
                print(f"실패 {t.issuer} {t.card_id or '-'} {t.source_id}: {type(e).__name__}")
                continue
            finally:
                time.sleep(DELAY_SECONDS)
            save(args.out, out, t, body, ctype, now)
            saved += 1
    print(f"저장 {saved}, robots.txt로 건너뜀 {skipped}, 실패 {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_collect.py
```

기대: 8개 통과. 네트워크는 쓰지 않는다.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline/collect.py backend/tests/pipeline/test_collect.py
git commit -m "feat: 카드사 원문 수집기 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 8개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 전체 477개 통과, ruff 통과. 네트워크 없이 실제 카탈로그로 대상만 뽑아 보니 30일 주기 50곳, 그중 브라우저로 여는 곳 32곳, 14일 주기는 신한 10곳이다.

---

## 과제 4: 초안 만들기와 검사

LLM이 추출한 합친 규칙을 카드 파일의 개정으로 넣고, 카탈로그 전체와 함께 검증한다. 설계 1절의 "초안은 이렇게 만든다".

**Files:**
- Create: `backend/cherry_core/pipeline/draft.py`
- Test: `backend/tests/pipeline/test_draft.py`

**Interfaces:**
- Consumes: `resolve_card`, `DEFAULT_KEYS`, `check_catalog`, `load_catalog`, `canonical_text`, `normalize`
- Produces:
  - `int_keys(node)`: JSON 글자 키 `"300000"`을 정수로 되돌린다
  - `clean_rules(rules: dict) -> dict`: `Rules`로 검사하고 기본값을 뺀 모양. 비교와 채점이 이 모양을 쓴다
  - `issuer_defaults(issuer: dict | None, day: date) -> dict`
  - `make_draft(card: dict, issuer: dict | None, extracted: dict, fetched: date) -> dict | None`. `extracted`는 `{"rules", "effective_from", "source", "open_questions"}`다. 시행일이 마지막 개정보다 앞이면 `ValueError`
  - `check_draft(files: dict[str, str], path: str, card: dict) -> list[str]`. 결과는 `"error: <위치>: <내용>"` 모양이다

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/test_draft.py`:

```python
"""추출 결과로 만든 카드 초안. 설계 1절 4단계와 5단계.

테스트 카탈로그는 tests/catalog/conftest.py의 FILES다. CURRENT는 그 카드의 지금 규칙을 손으로 합친 것이고,
구간 키는 LLM이 JSON으로 돌려주는 모양대로 글자로 적었다.
"""

import copy
from datetime import date

import pytest

from cherry_core.pipeline.draft import check_draft, int_keys, make_draft
from tests.catalog.conftest import FILES, write_catalog

CARD = FILES["cards/shinhan/shinhan-test.yaml"]
ISSUER = FILES["issuers/shinhan.yaml"]
PATH = "cards/shinhan/shinhan-test.yaml"
FETCHED = date(2026, 10, 1)
CURRENT = {
    "tiers": [0, 300000, 500000],
    "spend": {
        "basis": "prev_calendar_month",
        "exclude_categories": ["tax"],
        "installment": "full_at_purchase",
        "cancellation": "cancel_month",
    },
    "limits": [{"key": "integrated", "per": "month", "amount": {"300000": 10000, "500000": 20000}}],
    "benefits": [
        {
            "key": "cafe-10",
            "title": "카페 10% 할인",
            "target": {"categories": ["cafe"]},
            "reward": {"type": "billing_discount", "rate": 10},
            "limits": [{"per": "txn", "amount": 1000}, {"shared": "integrated"}],
            "tiers": {"from": 300000},
        }
    ],
}


def extracted(effective_from=None, rate=10, **spend):
    rules = copy.deepcopy(CURRENT)
    rules["benefits"][0]["reward"]["rate"] = rate
    rules["spend"].update(spend)
    return {"rules": rules, "effective_from": effective_from, "source": "page"}


def test_int_keys():
    assert int_keys({"amount": {"300000": 10000}, "key": "a"}) == {"amount": {300000: 10000}, "key": "a"}


def test_same_rules_make_no_draft():
    assert make_draft(CARD, ISSUER, extracted(), FETCHED) is None


def test_changed_rate_adds_revision_without_issuer_defaults():
    draft = make_draft(CARD, ISSUER, extracted(date(2026, 11, 1), rate=5), FETCHED)
    assert draft["revisions"][0] == CARD["revisions"][0]
    assert draft["revisions"][1] == {
        "effective_from": date(2026, 11, 1),
        "source": "page",
        "tiers": [0, 300000, 500000],
        "limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 20000}}],
        "benefits": [
            {
                "key": "cafe-10",
                "title": "카페 10% 할인",
                "target": {"categories": ["cafe"]},
                "reward": {"type": "billing_discount", "rate": 5},
                "limits": [{"per": "txn", "amount": 1000}, {"shared": "integrated"}],
                "tiers": {"from": 300000},
            }
        ],
    }
    assert draft["checked_at"] == FETCHED
    assert draft["sources"][0]["fetched_at"] == FETCHED
    assert CARD["checked_at"] == date(2026, 9, 28)  # 원본은 그대로다


def test_card_specific_spend_is_kept():
    draft = make_draft(CARD, ISSUER, extracted(date(2026, 11, 1), installment="per_installment_month"), FETCHED)
    assert draft["revisions"][1]["spend"] == {"installment": "per_installment_month"}


def test_card_value_equal_to_model_default_is_kept_when_issuer_differs():
    issuer = copy.deepcopy(ISSUER)
    issuer["defaults"][0]["spend"]["interest_free"] = "exclude"
    rules = extracted(date(2026, 11, 1))  # 카드 규칙은 interest_free를 적지 않았다. 모델 기본값 count다
    draft = make_draft(CARD, issuer, rules, FETCHED)
    assert draft["revisions"][1]["spend"] == {"interest_free": "count"}


def test_required_field_missing_from_issuer_is_kept():
    issuer, card = copy.deepcopy(ISSUER), copy.deepcopy(CARD)
    del issuer["defaults"][0]["spend"]["cancellation"]
    card["revisions"][0]["spend"] = {"cancellation": "cancel_month"}  # 카드사가 안 정한 칸은 카드가 정한다
    draft = make_draft(card, issuer, extracted(date(2026, 11, 1), rate=5), FETCHED)
    assert draft["revisions"][1]["spend"] == {"cancellation": "cancel_month"}


def test_missing_date_uses_fetch_day_and_asks():
    draft = make_draft(CARD, ISSUER, extracted(rate=5), FETCHED)
    rev = draft["revisions"][1]
    assert (rev["effective_from"], rev["effective_from_estimated"]) == (FETCHED, True)
    assert draft["open_questions"] == [
        {"path": "revisions[1].effective_from", "question": "원문에서 시행일을 찾지 못해 수집한 날로 두었다"}
    ]


def test_same_date_corrects_last_revision():
    draft = make_draft(CARD, ISSUER, extracted(date(2026, 7, 1), rate=5), FETCHED)
    assert len(draft["revisions"]) == 1
    assert draft["revisions"][0]["benefits"][0]["reward"]["rate"] == 5


def test_earlier_date_needs_a_person():
    with pytest.raises(ValueError, match="앞이다"):
        make_draft(CARD, ISSUER, extracted(date(2026, 6, 1), rate=5), FETCHED)


@pytest.fixture
def files(tmp_path):
    root = write_catalog(tmp_path / "catalog", copy.deepcopy(FILES))
    return {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in root.rglob("*.yaml")}


def test_good_draft_passes_check(files):
    assert check_draft(files, PATH, make_draft(CARD, ISSUER, extracted(rate=5), FETCHED)) == []


def test_bad_draft_reports_its_problems(files):
    bad = extracted(date(2026, 11, 1))
    bad["rules"]["benefits"][0]["target"]["categories"] = ["nope"]
    problems = check_draft(files, PATH, make_draft(CARD, ISSUER, bad, FETCHED))
    assert problems and all(p.startswith("error: revisions@2026-11-01.benefits[cafe-10]") for p in problems)
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_draft.py
```

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/draft.py`:

```python
"""추출 결과로 카드 파일 초안을 만들고 검사한다. 설계 1절 4단계와 5단계."""

from __future__ import annotations

import copy
import tempfile
from datetime import date
from pathlib import Path
from typing import Any

from pydantic import BaseModel

from cherry_core.catalog.canonical import canonical_text, normalize
from cherry_core.catalog.check import check_catalog
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.models import BenefitExclusions, NewCard, Rules, Spend
from cherry_core.catalog.resolve import DEFAULT_KEYS, resolve_card

SECTIONS: dict[str, type[BaseModel]] = {"spend": Spend, "new_card": NewCard, "benefit_exclusions": BenefitExclusions}


def int_keys(node: Any) -> Any:
    """JSON은 맵 키가 글자뿐이라 '300000' 같은 구간 키를 정수로 되돌린다."""
    if isinstance(node, dict):
        return {(int(k) if isinstance(k, str) and k.isdigit() else k): int_keys(v) for k, v in node.items()}
    if isinstance(node, list):
        return [int_keys(v) for v in node]
    return node


def _whole(node: Any) -> Any:
    """10.0처럼 소수점 아래가 없는 비율을 10으로 되돌린다. 카탈로그 파일은 정수로 적는다."""
    if isinstance(node, dict):
        return {k: _whole(v) for k, v in node.items()}
    if isinstance(node, list):
        return [_whole(v) for v in node]
    return int(node) if isinstance(node, float) and node.is_integer() else node


def clean_rules(rules: dict) -> dict:
    """모델로 검사하고 기본값인 칸을 뺀다. 같은 뜻이면 같은 모양이 되어 비교할 수 있다."""
    return _whole(Rules.model_validate(rules).model_dump(by_alias=True, exclude_defaults=True))


def issuer_defaults(issuer: dict | None, day: date) -> dict:
    """day에 적용되는 카드사 기본값. resolve_card와 같이 마지막 항목 하나만 쓴다."""
    current = [d for d in (issuer or {}).get("defaults", []) if d["effective_from"] <= day]
    return {k: current[-1][k] for k in DEFAULT_KEYS if current and current[-1].get(k) is not None}


def _top_level(model: type[BaseModel], data: dict) -> dict:
    """맨 위 칸마다 값. 안 적은 칸은 모델 기본값으로 채우고, 기본값이 없는 칸은 비워 둔다."""
    out = {}
    for name, info in model.model_fields.items():
        key = info.alias or name
        if key in data:
            out[key] = data[key]
        elif not info.is_required():
            out[key] = info.get_default(call_default_factory=True)
    return normalize(out)


def card_content(rules: dict, defaults: dict) -> dict:
    """합친 규칙에서 카드사 기본값과 같은 칸을 뺀다.

    남긴 칸만 카드 개정에 적어야 카드사 기본값이 나중에 바뀔 때 이 카드도 따라간다.
    비교 전에 양쪽 모두 모델 기본값을 채운다. 카드사는 exclude인데 카드는 기본값 count인 칸도 남기고,
    카드사 기본값에 없는 필수 칸도 남기기 위해서다.
    """
    out = copy.deepcopy(rules)
    for k, model in SECTIONS.items():
        if k not in out or k not in defaults:
            continue
        mine, base = _top_level(model, out[k]), _top_level(model, defaults[k])
        rest = {key: v for key, v in mine.items() if key not in base or base[key] != v}
        if rest:
            out[k] = rest
        else:
            del out[k]
    return out


def make_draft(card: dict, issuer: dict | None, extracted: dict, fetched: date) -> dict | None:
    """추출 결과를 카드 파일의 개정으로 넣는다. 지금 규칙과 같으면 None.

    extracted는 {"rules": 합친 규칙, "effective_from": 날짜나 None, "source": 원문 id, "open_questions": [...]}다.
    시행일이 마지막 개정과 같으면 그 개정을 고치고, 뒤면 새 개정을 더한다. 앞이면 사람이 정하도록 ValueError를 낸다.
    """
    rules = clean_rules(int_keys(extracted["rules"]))
    if rules == clean_rules(resolve_card(card, issuer)[-1].data):
        return None
    out = copy.deepcopy(card)
    revisions = out["revisions"]
    last = revisions[-1]["effective_from"]
    day = extracted.get("effective_from")
    estimated = day is None
    if estimated:
        day = fetched
    if day < last:
        raise ValueError(f"추출한 시행일 {day}가 마지막 개정 {last}보다 앞이다")
    entry = {"effective_from": day, "source": extracted["source"], **card_content(rules, issuer_defaults(issuer, day))}
    if day == last:
        revisions[-1] = entry
    else:
        revisions.append(entry)
    questions = list(out.get("open_questions", []))
    if estimated:
        entry["effective_from_estimated"] = True
        path = f"revisions[{len(revisions) - 1}].effective_from"
        questions.append({"path": path, "question": "원문에서 시행일을 찾지 못해 수집한 날로 두었다"})
    questions += [q for q in extracted.get("open_questions", []) if q not in questions]
    if questions:
        out["open_questions"] = questions
    for s in out["sources"]:
        if s["id"] == extracted["source"]:
            s["fetched_at"] = fetched
    out["checked_at"] = fetched
    return out


def check_draft(files: dict[str, str], path: str, card: dict) -> list[str]:
    """카탈로그 파일 전체에 초안 하나를 넣고 검사한다. 초안 파일의 오류와 경고만 돌려준다.

    files는 카탈로그 폴더 기준 경로와 고정 형식 YAML 본문이다. path도 같은 기준이다.
    """
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, text in {**files, path: canonical_text(card)}.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8", newline="\n")
        return [f"{p.level}: {p.path}: {p.message}" for p in check_catalog(load_catalog(root)) if p.file == path]
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_draft.py
```

기대: 11개 통과.

- [x] **5단계: 실제 카탈로그로 확인한다**

`$SCRATCH/real_drafts.py`로 저장하고 돌린다. `$SCRATCH`는 그 세션의 scratchpad 폴더다.

```python
"""실제 카탈로그로 초안 만들기를 확인한다. 과제 4."""

import copy
import sys
from datetime import date
from pathlib import Path

from cherry_core.catalog.canonical import catalog_files
from cherry_core.catalog.load import load_catalog
from cherry_core.catalog.resolve import resolve_card
from cherry_core.pipeline.draft import check_draft, make_draft

sys.stdout.reconfigure(encoding="utf-8")
root = Path(sys.argv[1])
cat = load_catalog(root)
files = {p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in catalog_files(root)}
bad = 0
for cid, lc in sorted(cat.cards.items()):
    issuer = cat.issuers[lc.card.issuer].raw if lc.card.issuer in cat.issuers else None
    rules = resolve_card(lc.raw, issuer)[-1].data
    source = lc.card.sources[0].id
    same = make_draft(lc.raw, issuer, {"rules": rules, "effective_from": None, "source": source}, date(2026, 10, 1))
    changed = copy.deepcopy(rules)
    reward = changed["benefits"][0]["reward"]
    key = next((k for k in ("rate", "fixed", "per_liter") if isinstance(reward.get(k), (int, float))), None)
    if key:
        reward[key] += 1
    else:
        changed["tiers"] = [*changed["tiers"], changed["tiers"][-1] + 1_000_000]
    extracted = {"rules": changed, "effective_from": date(2028, 1, 1), "source": source}
    problems = check_draft(files, lc.file, make_draft(lc.raw, issuer, extracted, date(2026, 10, 1)))
    bad += bool(problems) or same is not None
    print(f"{cid}: 같은 규칙 초안 없음 {same is None}, 바꾼 초안 문제 {len(problems)}", *problems[:2])
print(f"문제 있는 카드 {bad}")
```

```bash
uv run --project backend python "$SCRATCH/real_drafts.py" catalog
```

기대: 카드마다 `같은 규칙 초안 없음 True, 바꾼 초안 문제 0`이고 마지막 줄이 `문제 있는 카드 0`이다.

- [x] **6단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline/draft.py backend/tests/pipeline/test_draft.py
git commit -m "feat: 추출 결과로 카드 초안을 만들고 검사하는 기능 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 11개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 실제 카탈로그 20장 모두 같은 규칙이면 초안이 없고 바꾼 초안은 문제 0이다. 전체 488개 통과, ruff 통과.

---

## 과제 5: 추출 프롬프트와 답 형식

`ai_query`에 넘길 프롬프트와 JSON 답 형식을 만든다. 설계 1절 4단계. 답 형식은 `Rules` 모델에서 만들어 모델이 바뀌면 따라 바뀐다. `$defs`를 쓰는 형식을 `ai_query`가 받는지는 공식 문서에 없어 과제 18에서 확인한다.

**Files:**
- Create: `backend/cherry_core/pipeline/prompt.py`
- Test: `backend/tests/pipeline/test_prompt.py`

**Interfaces:**
- Produces: `VERSION`, `response_schema() -> dict`, `catalog_codes(cat) -> dict[str, list[str]]`, `build_prompt(card, current, docs, codes) -> str`, `parse_answer(text) -> dict`. `parse_answer`의 결과는 `make_draft`의 `extracted`로 그대로 들어간다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/test_prompt.py`:

```python
"""추출 프롬프트와 답 형식. 설계 1절 4단계."""

import json
from datetime import date

from cherry_core.catalog.load import load_catalog
from cherry_core.pipeline.prompt import build_prompt, catalog_codes, parse_answer, response_schema
from tests.catalog.conftest import FILES


def test_schema_is_json_with_rules_and_shared_defs():
    fmt = response_schema()
    schema = fmt["json_schema"]["schema"]
    json.dumps(fmt)
    assert {"tiers", "spend", "benefits"} <= set(schema["properties"]["rules"]["properties"])
    assert "$defs" not in schema["properties"]["rules"]
    assert {"Benefit", "Condition", "OpenQuestion"} <= set(schema["$defs"])


def test_prompt_has_current_keys_codes_and_documents(make_catalog):
    card = FILES["cards/shinhan/shinhan-test.yaml"]
    current = {"benefits": [{"key": "cafe-10", "title": "카페 10% 할인"}]}
    codes = catalog_codes(load_catalog(make_catalog()))
    prompt = build_prompt(card, current, [("page", "카페 10% 할인\n월 최대 1만원")], codes)
    assert '"key": "cafe-10"' in prompt
    assert "가맹점: starbucks(스타벅스)" in prompt
    assert '<원문 id="page">\n카페 10% 할인\n월 최대 1만원\n</원문>' in prompt


def test_parse_answer_turns_date_text_into_date():
    answer = {"rules": {}, "effective_from": "2026-11-01", "source": "page", "open_questions": []}
    assert parse_answer(json.dumps(answer))["effective_from"] == date(2026, 11, 1)
    assert parse_answer(json.dumps({**answer, "effective_from": None}))["effective_from"] is None


def test_parse_answer_treats_null_as_not_written():
    rules = {"tiers": [0], "new_card": None, "benefits": [{"key": "a", "valid_until": None}]}
    answer = {"rules": rules, "effective_from": None, "source": "page", "open_questions": []}
    assert parse_answer(json.dumps(answer))["rules"] == {"tiers": [0], "benefits": [{"key": "a"}]}
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_prompt.py
```

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/prompt.py`:

```python
"""추출 프롬프트와 답 형식. 설계 1절 4단계. ai_query에 그대로 넘긴다."""

from __future__ import annotations

import json
from datetime import date
from typing import Any

from cherry_core.catalog.load import Catalog
from cherry_core.catalog.models import OpenQuestion, Rules

VERSION = "1"
INSTRUCTIONS = """\
너는 한국 카드사의 공식 원문에서 카드 혜택 규칙을 옮긴다. 답은 주어진 JSON 형식으로만 쓴다.
- 원문에 적힌 것만 옮긴다. 원문으로 확인하지 못한 값은 만들지 않고 open_questions에 무엇을 확인해야 하는지 적는다.
- 금액은 원 단위 정수다. 1만원은 10000이다. 비율은 퍼센트 숫자다. 10%는 10이다.
- 전월실적 구간은 tiers에 구간 하한을 적는다. 구간마다 다른 값은 {"구간 하한": 값} 맵으로 쓴다.
- 지금 혜택에 같은 혜택이 있으면 그 key를 그대로 쓴다. 새 혜택이면 영어 소문자, 숫자, -로 새 key를 만든다.
- 업종, 가맹점, 결제수단, 포인트는 아래 목록의 key만 쓴다. 맞는 key가 없으면 그 조건을 unmodeled에 문장으로 남긴다.
- 혜택마다 값을 옮긴 원문 문장을 evidence에 원문 그대로 적는다.
- 시행일은 원문에 적힌 날짜만 effective_from에 YYYY-MM-DD로 쓴다. 없으면 null이다.
- source는 가장 많이 근거로 삼은 원문의 id다.
"""


def response_schema() -> dict:
    """ai_query의 responseFormat. 모델이 바뀌면 답 형식도 따라 바뀐다."""
    rules = Rules.model_json_schema(by_alias=True)
    defs = {**rules.pop("$defs", {}), "OpenQuestion": OpenQuestion.model_json_schema()}
    schema = {
        "type": "object",
        "properties": {
            "rules": rules,
            "effective_from": {"anyOf": [{"type": "string", "format": "date"}, {"type": "null"}]},
            "source": {"type": "string"},
            "open_questions": {"type": "array", "items": {"$ref": "#/$defs/OpenQuestion"}},
        },
        "required": ["rules", "effective_from", "source", "open_questions"],
        "$defs": defs,
    }
    return {"type": "json_schema", "json_schema": {"name": "card_rules", "schema": schema, "strict": True}}


def catalog_codes(cat: Catalog) -> dict[str, list[str]]:
    return {
        "업종": sorted(cat.categories),
        "가맹점": sorted(f"{k}({m.name})" for k, m in cat.merchants.items()),
        "결제수단": sorted(f"{k}({m.name})" for k, m in cat.payment_methods.items()),
        "포인트": sorted(f"{k}({m.name})" for k, m in cat.point_programs.items()),
    }


def build_prompt(card: dict, current: dict, docs: list[tuple[str, str]], codes: dict[str, list[str]]) -> str:
    """card는 카드 파일, current는 지금 합친 규칙, docs는 (원문 id, 글) 목록이다."""
    benefits = [{"key": b["key"], "title": b["title"]} for b in current.get("benefits", [])]
    parts = [
        INSTRUCTIONS,
        f"카드: {card['name']} ({card['id']})",
        "지금 혜택: " + json.dumps(benefits, ensure_ascii=False),
        *(f"{name}: {', '.join(keys)}" for name, keys in codes.items()),
        *(f'<원문 id="{sid}">\n{text}\n</원문>' for sid, text in docs),
    ]
    return "\n\n".join(parts)


def _drop_nulls(node: Any) -> Any:
    if isinstance(node, dict):
        return {k: _drop_nulls(v) for k, v in node.items() if v is not None}
    if isinstance(node, list):
        return [_drop_nulls(v) for v in node]
    return node


def parse_answer(text: str) -> dict:
    """ai_query의 답을 make_draft가 받는 모양으로 바꾼다.

    답 형식을 엄격하게 두면 모델이 모르는 칸에도 null을 적는다. 그래서 규칙 안의 null은 안 적은 것으로 본다.
    한도 조정의 '제한 없음' null은 이 때문에 LLM이 적을 수 없고, 검수에서 사람이 적는다.
    """
    data = json.loads(text)
    day = data.get("effective_from")
    return {**data, "rules": _drop_nulls(data["rules"]), "effective_from": date.fromisoformat(day) if day else None}
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_prompt.py
```

기대: 4개 통과.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline/prompt.py backend/tests/pipeline/test_prompt.py
git commit -m "feat: 카드 규칙 추출 프롬프트와 답 형식 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 4개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 전체 492개 통과, ruff 통과. 실제 카탈로그로 만들면 원문을 뺀 프롬프트가 약 4,900자, 답 형식이 약 18,400자다. 목록은 업종 58, 가맹점 143, 결제수단 18, 포인트 7개다.

---

## 과제 6: 칸마다 정확도

추출 결과를 정답 예시와 칸마다 비교한다. 설계 1절 7단계와 4절 4번. 제목, 메모, 근거 문장, 원문 id, 문장으로 남긴 조건은 채점하지 않는다. 정답에만 있거나 추출에만 있는 칸은 틀린 것으로 센다. 없는 혜택을 지어내도 점수가 깎이게 하려는 것이다.

**Files:**
- Create: `backend/cherry_core/pipeline/score.py`
- Test: `backend/tests/pipeline/test_score.py`

**Interfaces:**
- Consumes: 두 값 모두 `clean_rules`를 거친 합친 규칙
- Produces: `field_accuracy(expected, actual) -> dict[str, tuple[int, int]]`. 묶음 이름은 `tiers`, `spend`, `limits`, `benefits.reward`처럼 맨 위 칸이고, 혜택은 그 아래 칸까지 나눈다. `total_accuracy(per_card) -> dict[str, float]`. `all`은 모든 칸이다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/test_score.py`:

```python
"""칸마다 정확도. 설계 1절 7단계. 기대값은 칸을 손으로 센 것이다."""

import pytest

from cherry_core.pipeline.score import field_accuracy, total_accuracy

EXPECTED = {
    "tiers": [0, 300000],
    "benefits": [
        {
            "key": "cafe",
            "title": "카페",
            "target": {"categories": ["cafe", "bakery"]},
            "reward": {"type": "billing_discount", "rate": 10},
        }
    ],
}


def test_same_rules_score_full():
    assert field_accuracy(EXPECTED, EXPECTED) == {"benefits.reward": (2, 2), "benefits.target": (1, 1), "tiers": (1, 1)}


def test_wrong_value_and_invented_benefit_count_as_wrong():
    actual = {
        "tiers": [0, 300000],
        "benefits": [
            {
                "key": "cafe",
                "title": "다른 제목",  # 제목은 채점하지 않는다
                "target": {"categories": ["bakery", "cafe"]},  # 순서만 다르다
                "reward": {"type": "billing_discount", "rate": 5},
            },
            {"key": "extra", "target": {"all": True}, "reward": {"type": "cashback", "rate": 1}},
        ],
    }
    # target: cafe.categories 맞음, extra.all 틀림. reward: cafe.type 맞음, cafe.rate 틀림, extra 두 칸 틀림
    assert field_accuracy(EXPECTED, actual) == {"benefits.reward": (1, 4), "benefits.target": (1, 2), "tiers": (1, 1)}


def test_missing_benefit_counts_as_wrong():
    assert field_accuracy(EXPECTED, {"tiers": [0, 300000]}) == {
        "benefits.reward": (0, 2),
        "benefits.target": (0, 1),
        "tiers": (1, 1),
    }


def test_tier_table_keys_are_separate_fields():
    e = {"limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 20000}}]}
    a = {"limits": [{"key": "integrated", "per": "month", "amount": {300000: 10000, 500000: 25000}}]}
    assert field_accuracy(e, a) == {"limits": (2, 3)}


def test_total_accuracy():
    got = total_accuracy([{"tiers": (1, 1), "benefits.reward": (1, 4)}, {"tiers": (0, 1)}])
    assert got == {"all": pytest.approx(2 / 6), "benefits.reward": 0.25, "tiers": 0.5}
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_score.py
```

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/score.py`:

```python
"""추출 결과를 정답 예시와 칸마다 비교한다. 설계 1절 7단계와 4절 4번.

두 값 모두 draft.clean_rules를 거친 합친 규칙이어야 한다. 기본값을 빼야 같은 뜻을 같은 칸으로 비교한다.
"""

from __future__ import annotations

import json
import re
from typing import Any

from cherry_core.catalog.canonical import normalize

# 돈과 무관한 글. 4절 4번
IGNORED = {"title", "notes", "evidence", "source", "unmodeled"}
_BENEFIT = re.compile(r"^benefits\[[^\]]*\]\.([^.\[]+)")


def _leaves(node: Any, path: str, out: dict[str, str]) -> None:
    if isinstance(node, dict):
        for k, v in node.items():
            if k not in IGNORED:
                _leaves(v, f"{path}.{k}" if path else str(k), out)
    elif isinstance(node, list) and node and all(isinstance(v, dict) and "key" in v for v in node):
        for v in node:
            _leaves({k: x for k, x in v.items() if k != "key"}, f"{path}[{v['key']}]", out)
    else:
        parent = path.rsplit(".", 1)[-1]
        out[path] = json.dumps(normalize(node, parent), ensure_ascii=False, sort_keys=True, default=str)


def _group(path: str) -> str:
    m = _BENEFIT.match(path)
    return f"benefits.{m.group(1)}" if m else re.split(r"[.\[]", path, maxsplit=1)[0]


def field_accuracy(expected: dict, actual: dict) -> dict[str, tuple[int, int]]:
    """칸 묶음마다 (맞은 칸, 전체 칸). 정답에만 있거나 추출에만 있는 칸은 틀린 것으로 센다."""
    e: dict[str, str] = {}
    a: dict[str, str] = {}
    _leaves(expected, "", e)
    _leaves(actual, "", a)
    out: dict[str, list[int]] = {}
    for path in e.keys() | a.keys():
        ok_total = out.setdefault(_group(path), [0, 0])
        ok_total[1] += 1
        if path in e and path in a and e[path] == a[path]:
            ok_total[0] += 1
    return {g: (ok, total) for g, (ok, total) in sorted(out.items())}


def total_accuracy(per_card: list[dict[str, tuple[int, int]]]) -> dict[str, float]:
    """카드 여러 장의 결과를 칸 묶음마다 합쳐 비율로 바꾼다. all은 모든 칸이다."""
    sums: dict[str, list[int]] = {}
    for result in per_card:
        for g, (ok, total) in result.items():
            for key in (g, "all"):
                s = sums.setdefault(key, [0, 0])
                s[0] += ok
                s[1] += total
    return {g: ok / total for g, (ok, total) in sorted(sums.items())}
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_score.py
```

기대: 5개 통과.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline/score.py backend/tests/pipeline/test_score.py
git commit -m "feat: 추출 결과의 칸별 정확도 채점 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 5개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 실제 카드 20장을 자기 자신과 채점하면 칸 1,616개, 묶음 19개가 모두 1.0이다. 전체 497개 통과, ruff 통과.

---

## 과제 7: 비용 차단 금액

오늘 기준으로 언제부터 합산해 얼마에서 멈출지 정한다. 설계 4절 8번과 9번. 체험 14일은 가입한 날부터 합산해 400달러, 그 뒤는 달마다 30달러다. 체험 크레딧으로 쓴 금액은 체험이 끝난 달의 30달러에 넣지 않는다.

**Files:**
- Create: `backend/cherry_core/pipeline/cost.py`
- Test: `backend/tests/pipeline/test_cost.py`

**Interfaces:**
- Produces: `spend_window(today: date, signup: date) -> tuple[date, Decimal]`. 과제 13의 차단 작업이 쓴다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/test_cost.py`:

```python
"""비용 차단 금액. 설계 4절 8번과 9번. 가입일 2026-10-05로 손으로 센 날짜다."""

from datetime import date
from decimal import Decimal

import pytest

from cherry_core.pipeline.cost import spend_window

SIGNUP = date(2026, 10, 5)


@pytest.mark.parametrize(
    ("today", "start", "limit"),
    [
        (date(2026, 10, 5), date(2026, 10, 5), 400),  # 체험 1일째
        (date(2026, 10, 18), date(2026, 10, 5), 400),  # 체험 14일째
        (date(2026, 10, 19), date(2026, 10, 19), 30),  # 15일째. 체험 중 쓴 금액은 넣지 않는다
        (date(2026, 10, 31), date(2026, 10, 19), 30),
        (date(2026, 11, 1), date(2026, 11, 1), 30),  # 새 달
    ],
)
def test_spend_window(today, start, limit):
    assert spend_window(today, SIGNUP) == (start, Decimal(limit))


def test_trial_across_months():
    signup = date(2026, 9, 25)
    assert spend_window(date(2026, 10, 2), signup) == (signup, Decimal(400))
    assert spend_window(date(2026, 10, 9), signup) == (date(2026, 10, 9), Decimal(30))
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_cost.py
```

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/cost.py`:

```python
"""한 달 비용 차단 금액. 설계 4절 8번과 9번. 달러 금액은 Decimal로 다룬다."""

from __future__ import annotations

from datetime import date, timedelta
from decimal import Decimal

TRIAL_DAYS = 14
TRIAL_LIMIT = Decimal(400)
MONTH_LIMIT = Decimal(30)


def spend_window(today: date, signup: date) -> tuple[date, Decimal]:
    """(합산을 시작하는 날, 차단 금액).

    체험 14일은 가입한 날부터 합산해 400달러에서 멈춘다. 그 뒤로는 달마다 30달러다.
    체험 크레딧으로 쓴 금액은 체험이 끝난 달의 30달러에 넣지 않는다.
    """
    trial_end = signup + timedelta(days=TRIAL_DAYS)
    if today < trial_end:
        return signup, TRIAL_LIMIT
    return max(today.replace(day=1), trial_end), MONTH_LIMIT
```

- [x] **4단계: 통과를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_cost.py
```

기대: 6개 통과.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline/cost.py backend/tests/pipeline/test_cost.py
git commit -m "feat: Databricks 비용 차단 금액 계산 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 6개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 전체 503개 통과, ruff 통과. 차단 작업과 함께 과제 13에서 `risk-reviewer`로 검토한다.

---

## 과제 8: 승인된 파일을 저장소로 옮기기

GitHub Actions가 내보내기 폴더 하나를 저장소의 `catalog/`에 복사하고 커밋 메시지를 만든다. 설계 4절 7번. `catalog/` 밖이나 YAML이 아닌 파일은 거부한다.

**Files:**
- Create: `backend/cherry_core/pipeline/export.py`
- Test: `backend/tests/pipeline/test_export.py`

**Interfaces:**
- Produces: `apply_export(export_dir, repo) -> tuple[list[str], str]`, 명령 `python -m cherry_core.pipeline.export DIR --message-file FILE`. 내보내기 폴더는 `catalog/` 아래 파일과 `commit.json`이다. `commit.json`은 `{"subject", "review_id"}`이고 과제 20의 검수 앱이 쓴다.

- [x] **1단계: 실패하는 테스트를 쓴다**

`backend/tests/pipeline/test_export.py`:

```python
"""승인된 파일을 저장소로 옮기기. 설계 4절 7번."""

import json

import pytest

from cherry_core.pipeline.export import apply_export, main

CARD = "cards/shinhan/shinhan-test.yaml"


@pytest.fixture
def dirs(tmp_path):
    export, repo = tmp_path / "export", tmp_path / "repo"
    (export / "catalog/cards/shinhan").mkdir(parents=True)
    (repo / "catalog/cards/shinhan").mkdir(parents=True)
    (export / "commit.json").write_text(
        json.dumps({"subject": "feat: 신한카드 테스트 2026-11-01 개정 반영", "review_id": "r-0001"}), encoding="utf-8"
    )
    return export, repo


def test_copies_changed_files_and_writes_message(dirs):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new\n", encoding="utf-8")
    (export / "catalog/issuers").mkdir()
    (export / "catalog/issuers/shinhan.yaml").write_text("same\n", encoding="utf-8")
    (repo / "catalog/issuers").mkdir()
    (repo / "catalog/issuers/shinhan.yaml").write_text("same\n", encoding="utf-8")

    changed, message = apply_export(export, repo)

    assert changed == [f"catalog/{CARD}"]
    assert (repo / "catalog" / CARD).read_text(encoding="utf-8") == "new\n"
    assert message == "feat: 신한카드 테스트 2026-11-01 개정 반영\n\n검수 기록 r-0001\n작업 003\n"


def test_rejects_non_yaml(dirs):
    export, repo = dirs
    (export / "catalog/run.sh").write_text("echo\n", encoding="utf-8")
    with pytest.raises(ValueError, match="YAML이 아니다"):
        apply_export(export, repo)


def test_cli_writes_message_file(dirs, tmp_path, capsys):
    export, repo = dirs
    (export / "catalog" / CARD).write_text("new\n", encoding="utf-8")
    msg = tmp_path / "msg.txt"
    assert main([str(export), "--repo", str(repo), "--message-file", str(msg)]) == 0
    assert msg.read_text(encoding="utf-8").startswith("feat: 신한카드 테스트")
    assert "바뀐 파일 1개" in capsys.readouterr().out
```

- [x] **2단계: 실패를 확인한다**

```bash
uv run --project backend pytest -q backend/tests/pipeline/test_export.py
```

- [x] **3단계: 코드를 쓴다**

`backend/cherry_core/pipeline/export.py`:

```python
"""검수에서 승인된 카탈로그 파일을 저장소로 옮긴다. GitHub Actions가 돌린다. 설계 4절 7번.

내보내기 폴더 하나가 승인 하나다. 안에 catalog/ 아래 바뀐 파일과 commit.json이 있다.
commit.json은 {"subject": "feat: ...", "review_id": "..."}다.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def apply_export(export_dir: Path, repo: Path) -> tuple[list[str], str]:
    """내보낸 파일을 repo/catalog에 복사하고 (바뀐 경로, 커밋 메시지)를 돌려준다."""
    meta = json.loads((export_dir / "commit.json").read_text(encoding="utf-8"))
    src_root = (export_dir / "catalog").resolve()
    dst_root = (repo / "catalog").resolve()
    changed = []
    for src in sorted(p for p in src_root.rglob("*") if p.is_file()):
        rel = src.relative_to(src_root)
        dst = (dst_root / rel).resolve()
        if src.suffix != ".yaml" or not dst.is_relative_to(dst_root):
            raise ValueError(f"카탈로그 YAML이 아니다: {rel.as_posix()}")
        text = src.read_text(encoding="utf-8")
        if dst.exists() and dst.read_text(encoding="utf-8") == text:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(text, encoding="utf-8", newline="\n")
        changed.append(f"catalog/{rel.as_posix()}")
    return changed, f"{meta['subject']}\n\n검수 기록 {meta['review_id']}\n작업 003\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m cherry_core.pipeline.export")
    ap.add_argument("export_dir", type=Path)
    ap.add_argument("--repo", type=Path, default=Path.cwd())
    ap.add_argument("--message-file", type=Path, required=True)
    args = ap.parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    changed, message = apply_export(args.export_dir, args.repo)
    args.message_file.write_text(message, encoding="utf-8")
    print(f"바뀐 파일 {len(changed)}개")
    for path in changed:
        print(f"  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [x] **4단계: 전체를 확인한다**

```bash
uv run --project backend pytest -q
uvx ruff check backend && uvx ruff format --check backend
```

기대: 130개 통과. 시작할 때 테스트가 81개가 아니었으면 그 수에 49를 더한 값이다.

- [x] **5단계: 커밋 지점**

```bash
git add backend/cherry_core/pipeline/export.py backend/tests/pipeline/test_export.py
git commit -m "feat: 승인된 카탈로그 파일을 저장소로 옮기는 명령 추가" -m "작업 003"
```

2026-09-30 실행 결과: 새 테스트 3개가 모듈이 없어 먼저 실패하고 코드를 넣은 뒤 통과했다. 전체 506개 통과로 시작할 때 457개에 49를 더한 값이다. ruff 통과, 카탈로그 오류 0. 내보내기 워크플로와 함께 과제 21에서 `risk-reviewer`로 검토한다.

---

## 과제 9: 수집기 PC 시험

자동 수집 카드사 8곳을 PC에서 받아 보고, 글이 제대로 나오는지 본다. GitHub 서버에서 막히는 곳은 과제 14에서 따로 본다.

- [x] **1단계: Playwright 브라우저를 설치하고 받는다**

```bash
uv run --project backend --with playwright python -m playwright install chromium
uv run --project backend --with playwright python -m cherry_core.pipeline.collect --out "$SCRATCH/raw"
```

기대: 마지막 줄 `저장 N, robots.txt로 건너뜀 M, 실패 K`. 실패가 있으면 id와 오류 종류를 표로 남긴다.

- [x] **2단계: 파일마다 글이 나오는지 본다**

`$SCRATCH/peek.py`로 저장하고 돌린다.

```python
"""받은 원문에서 글이 나오는지 본다. 과제 9. PDF는 Databricks에서 읽으므로 크기만 찍는다."""

import json
import sys
from pathlib import Path

from cherry_core.pipeline.text import document_text

sys.stdout.reconfigure(encoding="utf-8")
root = Path(sys.argv[1])
types = {}
for manifest in root.glob("manifests/*.jsonl"):
    for line in manifest.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        types[row["path"]] = row["content_type"]
for rel, content_type in sorted(types.items()):
    body = (root / rel).read_bytes()
    if body.startswith(b"%PDF-"):
        print(f"{rel}: PDF {len(body)}바이트")
        continue
    text = document_text(body, content_type)
    print(f"{rel}: {len(text)}자, 할인 {text.count('할인')}, 적립 {text.count('적립')}")
```

```bash
uv run --project backend python "$SCRATCH/peek.py" "$SCRATCH/raw"
```

기대: 카드 원문은 글자가 수천 자이고 `할인`이나 `적립`이 나온다. 글자가 수백 자뿐인 파일은 빈 틀이다.

- [x] **3단계: 결과를 카드사 파일에 적는다**

빈 틀만 받은 곳과 실패한 곳은 원인을 적는다. 예: 목록을 자바스크립트로 그림, 보안 프로그램 화면으로 넘어감, PDF 내려받기에 쿠키가 필요함. 고칠 수 있으면 고친다. 브라우저가 필요한데 `api`로 적힌 목록은 목록 주소를 브라우저로 여는 대신 카드사의 JSON 주소로 바꿀 수 있는지 먼저 본다. 카카오뱅크 notes에 그런 주소가 있다. 고친 내용과 남은 문제는 카드사 파일의 `notes`에 날짜와 함께 적는다.

2026-09-29 신한카드 시험: 상품 페이지 3장은 혜택 글이 4천~9천 자 나왔다. 상품 목록과 공지는 131자와 200자로 빈 틀이었다.

- [x] **4단계: 커밋 지점**

```bash
uv run --project backend python -m cherry_core.catalog check | tail -2
git add catalog/issuers
git commit -m "docs: 카드사별 원문 수집 시험 결과 기록" -m "작업 003"
```

2026-09-30 실행 결과

첫 수집은 저장 36, robots.txt로 건너뜀 9, 실패 5였다. 고친 뒤 다시 받아 저장 37, 건너뜀 9, 실패 0이다.

| 카드사 | 첫 수집에서 본 것 | 원인 | 한 것 |
|---|---|---|---|
| 하나 | 글은 1만 자가 넘는데 할인과 적립이 0 | 브라우저가 돌려준 UTF-8 글을 meta의 euc-kr로 읽음 | 수집기가 브라우저 글에 `charset=utf-8`을 적는다. 테스트를 더했다 |
| 현대 | 상품 목록 TimeoutError | 유튜브 동영상 때문에 요청이 끊이지 않아 networkidle이 오지 않음 | load 뒤 15초만 기다린다 |
| 롯데 | 네 주소 모두 TimeoutError | robots.txt 요청이 수집기와 브라우저 모두에서 연결 끊김 | 허용을 확인하지 못해 `blocked`로 바꿨다 |
| 농협 | 네 파일 모두 2,356자 | 브라우저가 보안프로그램 설치 화면으로 넘어감 | `api`로 바꿨다. 새소식 주소에 쪽 번호를 붙였다 |
| 신한 | 상세 API의 지문이 받을 때마다 다름 | 응답의 `responseTime` | JSON 글 뽑기에서 뺀다. 테스트를 더했다 |

남은 것
- robots.txt로 건너뛴 9곳은 카카오뱅크 상품 목록, 공지, 상품 페이지와 KB 상품설명서 PDF 6개다. 사람이 받아 `--add`로 더한다
- 빈 틀: 신한 상품 목록과 공지, 농협 카드 목록. 신한 목록 API는 한 쪽에 8장까지라 주소 하나로 다 받지 못한다
- 받을 때마다 바뀌는 줄: 하나 공지 본문의 조회수, KB 공지 목록의 조회수. 과제 16에 적었다
- 수집기와 글 뽑기를 고친 커밋과 카드사 파일 기록 커밋을 나눴다

---

## 과제 10: 기존 20장 근거 문장 채우기

혜택마다 값을 옮긴 원문 문장을 `evidence`에 넣는다. 설계 4절 6번. 카탈로그 값은 바꾸지 않는다. 원문 문장이 카탈로그 값과 맞지 않으면 고치지 말고 보고한다.

**나누는 방법.** 작업 001 과제 12와 같이 에이전트 6개를 동시에 띄운다. 묶음은 작업 001이 끝났을 때의 카드 목록으로 다시 확인한다.

| 묶음 | 카드 |
|---|---|
| A | shinhan-cheoeum, shinhan-mrlife, shinhan-pointplan |
| B | samsung-id-on, samsung-taptap-o, hyundai-m, hyundai-the-green-ed4, hyundai-zero-edition3-discount |
| C | kb-easy-all-titanium, kb-my-wesh, kb-toktok |
| D | lotte-loca-classic, lotte-loca365, hana-travelog-check, hana-wonder2-daily, woori-every-point, woori-k-life-check |
| E | ibk-narasarang |
| F | nh-heroes-check, kakaobank-friends-check |

- [x] **1단계: 묶음마다 `card-researcher` 에이전트를 띄운다**

````text
카탈로그 2판 혜택에 근거 문장을 채운다. 맡은 카드: <묶음의 카드 id 목록>

해야 할 것
1. 카드 파일의 sources에 있는 공식 원문을 다시 읽는다.
2. 모든 개정의 모든 혜택에 evidence를 채운다. 그 혜택의 대상, 조건, 보상, 한도를 옮긴 원문 문장을 원문 그대로 적는다. 표의 한 행은 칸을 " | "로 이어 한 문장으로 적는다.
3. 한 문장이 여러 혜택의 근거면 혜택마다 적는다. 문장은 짧게 끊지 말고 값이 들어 있는 문장 전체를 적는다.
4. 카탈로그 값은 바꾸지 않는다. 원문 문장과 값이 맞지 않거나 근거 문장을 찾지 못한 혜택은 보고서에 적는다.
5. patch 개정의 혜택은 patch에 들어 있는 혜택만 채운다.

지켜야 할 것: .claude/agents/card-researcher.md 전부.
judgment.md는 고치지 않는다. format 명령은 다른 에이전트의 파일까지 다시 쓰므로 쓰지 않는다. 자기 파일만 cherry_core.catalog.canonical.format_file로 고친다.
끝나면 check를 돌리고 맡은 파일의 오류가 0인지 확인한 뒤 보고한다.
````

- [x] **2단계: 다른 에이전트가 대조한다**

묶음마다 `card-verifier` 에이전트에게 "evidence 문장이 원문에 그대로 있는지, 그 문장이 혜택 값과 맞는지"만 대조하게 한다. 불일치는 1단계 에이전트의 보고와 합쳐 사용자에게 보인다.

- [x] **3단계: 전체를 확인한다**

`$SCRATCH/evidence_count.py`로 저장하고 돌린다.

```python
"""근거 문장이 없는 혜택을 센다. 과제 10."""

import sys
from pathlib import Path

from cherry_core.catalog.load import load_catalog

sys.stdout.reconfigure(encoding="utf-8")
missing = set()
for cid, lc in sorted(load_catalog(Path(sys.argv[1])).cards.items()):
    for _, rules in lc.revisions:
        missing |= {(cid, b.key) for b in rules.benefits if not b.evidence}
for cid, key in sorted(missing):
    print(f"{cid} {key}")
print(f"근거 없는 혜택 {len(missing)}")
```

```bash
uv run --project backend python "$SCRATCH/evidence_count.py" catalog
uv run --project backend python -m cherry_core.catalog check | tail -2
```

기대: 마지막 줄이 `근거 없는 혜택 0`. 카탈로그 오류 0, 경고 0.

- [x] **4단계: 커밋 지점**

카드사마다 나눠 커밋한다.

```bash
git add catalog/cards/shinhan
git commit -m "feat: 신한카드 3장 혜택에 원문 근거 문장 추가" -m "작업 003"
```

나머지 카드사도 같은 방식이다. 메시지는 `feat: <카드사> 카드 혜택에 원문 근거 문장 추가`다.

2026-09-30 실행 결과

20장의 혜택 190개에 근거 문장을 채웠다. 문장은 모두 1,730개다. 근거 없는 혜택 0, 카탈로그 오류 0, 경고 0, 전체 511개 통과. 카드사마다 커밋 10개다. 대조 에이전트 6개가 원문과 맞춰 봤고, 문장이 틀린 네 곳은 고쳤다. KB의 "SK주유쇼", KB 구간 경계 행 빠짐, KB My WE:SH 관리에 진심 행을 둘로 나눈 것, 하나 트래블로그 "면제서비스"다.

실행 중에 바꾼 것
- 혜택의 `source`를 page로 적은 카드가 셋이다. 하나 원더, 삼성 taptap O, IBK. 개정의 source가 시행일 근거 문서라 근거 문장을 옮긴 상품 페이지와 달랐다. card-researcher.md의 "그 원문에서 옮긴 혜택의 source에 id를 적는다"를 따랐다
- 조사 에이전트가 `html_text`에서 표의 한 행이 여러 줄로 쪼개지는 버그를 찾았다. 칸 사이 줄바꿈과 칸 안의 p, br 때문이다. 고치면서 text/plain 원문을 HTML로 읽던 것도 고쳤다. 커밋 `ad4e512`
- 적는 방식: 표의 한 행은 칸을 " | "로 잇고, 여러 행에 걸친 칸은 행마다 채웠다. 칸 안의 줄바꿈은 공백 하나다. PDF 줄바꿈으로 단어 중간에 생긴 공백은 붙였고 문장 앞의 ·, •, ※ 표시는 뺐다
- 한계: 여러 행이 한도 칸 하나를 같이 쓰는 표는 행마다 한도를 채워 적어, 문장만 보면 한도를 같이 쓴다는 것이 보이지 않는다. KB My WE:SH, IBK PX

값이 원문과 다를 수 있는 곳. 카탈로그 값은 바꾸지 않았고 사용자 확인을 기다린다

| 카드 | 혜택 | 원문 | 카탈로그 | 영향 |
|---|---|---|---|---|
| 삼성 iD ON | easypay-overseas-3, easypay-overseas-1 | 할인 제외에 "고속버스(차내 단말기 및 고속버스 앱 결제)" | 제외 업종에 고속버스가 없다 | 고속버스 앱에서 간편결제로 내면 3%, 1%가 계산된다 |
| 롯데 LOCA 365 | transit-10 | "건당 2만원 이상 결제 건" | 한 달 합산 2만원 이상 | 우리 K-LIFE transit-5는 같은 문구를 건마다로 보고 확인 필요로 남겨 두 카드가 반대다 |
| 하나 원더 | transit-10 | 상세표 10%, 주요혜택 요약 "버스, 지하철 3%" | 10% | 이미 확인 필요 항목에 있다 |
| IBK | aio-transit | "대중교통은 할인 횟수, 할인 금액 제한 없음" | 통합할인한도 안 | 이미 확인 필요 항목에 있다 |
| KB 이지올 티타늄 | b-online-5 | 설명서 PDF "롯데닷컴", 상품 페이지 "롯데ON" | lotte_on | 상품 페이지와 맞다 |
| 하나 원더 | DAILY 8개 | 2026-07-06 심의 페이지의 값 | 개정 시행일 2025-07-01 | 2025년 7월 값과 같은지 원문으로 확인되지 않는다 |

작은 것: 삼성 iD ON과 taptap O의 "장애인 고용부담금" 제외는 맞는 업종 코드가 없다. taptap O 패키지 적립의 다이어트할부와 법인공용카드 제외는 unmodeled에 없다. 농협 외국어학원, 스포츠, 철도는 대상 범위가 원문보다 넓고 unmodeled에 적혀 있다.

조사 에이전트가 규칙에서 벗어난 것: IBK 상품 페이지와 KB 설명서 PDF를 한 번씩 직접 받아 읽었다. 둘 다 robots.txt가 수집기를 막은 곳이고, 사람이 공식 페이지를 보는 것과 같은 한 번의 조사였다. 우리 에이전트는 수집기를 우리카드로 한 번 돌렸다.

---

## 과제 11: 사용자 안내서와 권한 막기

가입 전에 사용자가 할 일을 단계마다 적고, Claude가 계정과 비밀값 명령을 실수로 돌리지 못하게 막는다.

**확인할 공식 문서:**
- 익스프레스 설정: https://docs.databricks.com/aws/en/getting-started/express-setup
- 체험 조건: https://docs.databricks.com/aws/en/getting-started/free-trial
- CLI 설치와 로그인: https://docs.databricks.com/aws/en/dev-tools/cli/install , https://docs.databricks.com/aws/en/dev-tools/cli/authentication
- 서비스 주체와 OAuth 비밀값: https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m
- 예산: https://docs.databricks.com/aws/en/admin/account-settings/budgets
- GitHub 저장소 비밀값: https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions

**Files:**
- Modify: `docs/databricks.md`의 "설정은 사용자가 직접 한다"
- Modify: `.claude/settings.json`

- [ ] **1단계: 안내서를 쓴다**

`docs/databricks.md`의 "안내할 순서의 미리 보기"를 아래 단계로 바꾼다. 단계마다 "누를 곳", "넣을 값", "성공하면 보이는 것", "Claude에게 붙여 줄 것"을 쓴다. 공식 문서의 화면 이름을 그대로 쓴다.

1. 익스프레스 설정으로 체험 계정 만들기. 결제 정보는 넣지 않는다. 지역은 따로 고르지 않는다. 가입한 날을 Claude에게 알려 준다.
2. PC에 Databricks CLI 설치와 로그인. 성공하면 `databricks current-user me`가 자기 계정을 보여 준다. 이 출력을 붙여 준다.
3. 서비스 주체 만들기와 OAuth 비밀값 발급. 서비스 주체는 사람 대신 GitHub Actions가 쓰는 Databricks 계정이다. 사람 계정 토큰을 GitHub에 두면 그 토큰이 새었을 때 사람 계정 전체가 열리므로 권한이 좁은 계정을 따로 둔다. 비밀값은 화면에 한 번만 보이므로 바로 4단계로 간다.
4. GitHub 저장소 비밀값 등록. 이름은 `DATABRICKS_HOST`, `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`이다. 성공하면 Settings의 Actions secrets 목록에 세 이름이 보인다. 값은 붙여 주지 않고 이름 목록만 붙여 준다.
5. 예산과 알림 설정. 한 달 예산 30달러, 알림 15달러, 30달러, 60달러. 알림 메일 주소는 사용자 메일이다.
6. 체험이 끝나는 날 결제 정보 등록. 가입 14일째에 Claude가 알린다.

- [ ] **2단계: Claude가 돌리면 안 되는 명령을 막는다**

`.claude/settings.json`의 `deny`에 더한다.

```json
      "Bash(databricks auth login *)",
      "Bash(databricks auth token *)",
      "Bash(databricks tokens *)",
      "Bash(databricks service-principal-secrets *)",
      "Bash(databricks account *)",
      "Bash(gh secret *)"
```

- [ ] **3단계: 확인한다**

`python -c "import json; json.load(open('.claude/settings.json', encoding='utf-8'))"`로 JSON이 맞는지 본다. 안내서는 사용자가 읽어 보고 모르는 말이 없는지 확인받는다.

- [ ] **4단계: 커밋 지점**

```bash
git add docs/databricks.md .claude/settings.json
git commit -m "docs: Databricks 가입과 비밀값 등록 안내 추가" -m "작업 003"
```

---

## 과제 12: 가입과 번들 첫 배포

이 과제를 시작하는 날 사용자가 가입한다. 그날부터 체험 14일이 흐른다. 과제 12부터 19까지를 14일 안에 끝내는 것을 목표로 한다.

**확인할 공식 문서:**
- 번들 설정: https://docs.databricks.com/aws/en/dev-tools/bundles/settings
- 번들 자원 종류: https://docs.databricks.com/aws/en/dev-tools/bundles/resources
- 번들 wheel 빌드: https://docs.databricks.com/aws/en/dev-tools/bundles/python-wheel
- 개발 모드와 운영 모드: https://docs.databricks.com/aws/en/dev-tools/bundles/deployment-modes

**Files:**
- Create: `pipeline/databricks.yml`, `pipeline/resources/storage.yml`

- [ ] **1단계: 사용자가 안내서 1, 2단계를 한다**

사용자가 붙여 준 `databricks current-user me` 출력에 자기 메일이 보이면 성공이다. 가입일을 progress.md에 적는다.

- [ ] **2단계: 번들을 쓴다**

`pipeline/databricks.yml`에 둘 것:
- 번들 이름 `cherry`
- 변수 `signup_date`. 기본값은 가입일이다. 비밀값이 아니다
- 산출물 `cherry_core`: `../backend`에서 `uv build --wheel`로 만든 wheel
- 대상 `dev`는 `mode: development`이고 기본이다. 대상 `prod`는 `mode: production`이다

`pipeline/resources/storage.yml`에 둘 것: 카탈로그 `cherry`, 스키마 `bronze`, `silver`, `gold`, 볼륨 `cherry.bronze.raw`와 `cherry.gold.export`.

확인할 것 두 가지가 있다.
- 번들 밖 경로 `../backend`를 wheel 빌드 경로로 쓸 수 있는가. 안 되면 `databricks.yml`을 저장소 루트로 옮기고 `sync.include`로 필요한 폴더만 올린다.
- 번들로 카탈로그를 만들 수 있는가. 안 되면 SQL `CREATE CATALOG IF NOT EXISTS cherry`로 만든다. 익스프레스 계정에서 카탈로그를 새로 못 만들면 작업 공간 기본 카탈로그 아래에 같은 스키마를 두고 design.md 2절의 이름을 고친다.

- [ ] **3단계: 개발용으로 배포한다**

```bash
cd pipeline && databricks bundle validate && databricks bundle deploy -t dev
databricks schemas list cherry
```

기대: validate에 오류가 없고, 스키마 목록에 개발자 이름이 붙은 bronze, silver, gold가 보인다.

- [ ] **4단계: `ai_parse_document`가 되는지 본다**

작은 PDF 하나를 개발용 볼륨에 올리고 SQL 편집기나 `databricks` CLI로 돌린다.

```sql
SELECT ai_parse_document(content, map('version', '2.0')) FROM read_files('<볼륨 안 PDF 경로>', format => 'binaryFile');
```

지역 때문에 안 되면 PDF는 `pypdf`로 글을 뽑는다. 그 경우 과제 15의 문서 코드가 PDF에 `pypdf`를 쓰고, design.md 1절 2단계에 결과를 적는다.

- [ ] **5단계: 커밋 지점**

```bash
git add pipeline
git commit -m "build: Databricks 번들과 저장 공간 정의 추가" -m "작업 003"
```

---

## 과제 13: 비용 차단 작업과 첫 운영 배포

LLM을 부르기 전에 비용 차단이 서 있어야 한다. 설계 4절 8번과 10번.

**확인할 공식 문서:**
- 청구 기록 테이블: https://docs.databricks.com/aws/en/admin/system-tables/billing
- 가격 테이블: https://docs.databricks.com/aws/en/admin/system-tables/pricing
- 작업 예약과 멈춤: https://docs.databricks.com/aws/en/jobs/scheduled
- Python SDK의 jobs, warehouses, apps: https://databricks-sdk-py.readthedocs.io/
- GitHub Actions에서 번들 배포: https://docs.databricks.com/aws/en/dev-tools/bundles/ci-cd

**Files:**
- Create: `pipeline/src/cost_guard.py`, `pipeline/resources/cost_guard.yml`, `.github/workflows/deploy.yml`

**만들 것:**
- `cost_guard.py`: `spend_window(오늘, signup_date)`로 합산 시작일과 한도를 정한다. 아래 SQL로 쓴 금액을 구한다. 한도 이상이면 태그 `cherry_guard`가 붙은 작업의 예약과 트리거를 멈추고, SQL 웨어하우스와 앱을 끈다. 한도 밑이면 멈춘 예약과 트리거를 다시 켠다. 시험용으로 `--limit` 인자를 받는다. 찍는 것은 합산 시작일, 쓴 금액, 한도, 멈춤 여부뿐이다.

```sql
SELECT coalesce(sum(u.usage_quantity * p.pricing.effective_list.default), 0) AS spent
FROM system.billing.usage u
JOIN system.billing.list_prices p
  ON u.sku_name = p.sku_name AND u.cloud = p.cloud AND u.usage_unit = p.usage_unit
 AND u.usage_end_time >= p.price_start_time
 AND (p.price_end_time IS NULL OR u.usage_end_time < p.price_end_time)
WHERE u.usage_date >= :start AND p.currency_code = 'USD'
```

- `cost_guard.yml`: 작업 `cherry_cost_guard`. 6시간마다 돈다. 이 작업에는 `cherry_guard` 태그를 붙이지 않는다. 자기 자신은 멈추지 않아야 새 달에 다시 켤 수 있다. 실행 시간 제한은 10분이다.
- `deploy.yml`: master에 `pipeline/**`, `backend/cherry_core/**`, `backend/pyproject.toml`이 바뀐 푸시와 수동 실행에서 돈다. 비밀값 세 개를 환경변수로 받는다. 먼저 `cherry_guard` 태그가 붙은 운영 작업 중 멈춘 것이 있는지 보고, 있으면 "차단된 달이라 배포하지 않는다"를 찍고 성공으로 끝낸다. 없으면 `databricks bundle deploy -t prod`를 돌린다. 권한은 `contents: read`다.

- [ ] **1단계: 사용자가 안내서 3, 4, 5단계를 한다**

사용자가 붙여 준 GitHub 비밀값 이름 목록에 세 이름이 모두 있으면 성공이다.

- [ ] **2단계: 차단 작업을 쓰고 개발용으로 돌린다**

```bash
cd pipeline && databricks bundle deploy -t dev && databricks bundle run -t dev cherry_cost_guard
```

기대: 출력에 합산 시작일이 가입일이고 한도 400이다.

- [ ] **3단계: `risk-reviewer`로 검토한다**

`cost_guard.py`와 `deploy.yml`을 넘긴다. 비밀값이 실행 기록에 찍히는지, 차단이 풀리는 조건이 맞는지, 배포가 차단을 되살리는 길이 남았는지 본다.

- [ ] **4단계: 커밋하고, 사용자에게 푸시를 요청받아 첫 운영 배포를 한다**

```bash
git add pipeline .github/workflows/deploy.yml
git commit -m "deploy: 비용 차단 작업과 운영 배포 워크플로 추가" -m "작업 003"
```

푸시하면 운영 배포가 돈다고 사용자에게 먼저 말한다.

- [ ] **5단계: 운영에서 멈춤과 다시 켜기를 시험한다**

운영 작업 공간에서 `cherry_cost_guard`를 `--limit 0`으로 한 번 돌리면 태그가 붙은 운영 작업이 멈춰야 한다. 인자 없이 다시 돌리면 다시 켜져야 한다. 멈춘 동안 `deploy.yml`을 수동 실행하면 "차단된 달이라 배포하지 않는다"가 찍혀야 한다.

---

## 과제 14: 수집 워크플로

**확인할 공식 문서:**
- CLI로 볼륨에 올리기: https://docs.databricks.com/aws/en/dev-tools/cli/reference/fs-commands
- Actions에서 CLI 쓰기: https://github.com/databricks/setup-cli
- GitHub Actions 예약 실행: https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#schedule

**Files:**
- Create: `.github/workflows/collect.yml`

**만들 것:** 매달 1일과 15일 UTC 18시에 돈다. 한국 시각으로 다음 날 새벽 3시다. 1일에는 `--interval 30`으로 모든 카드사를, 15일에는 `--interval 14`로 14일 주기 카드사만 받는다. 수동 실행도 받는다. Playwright 브라우저를 설치하고 수집기를 돌린 뒤, 수집이 일부 실패해도 받은 파일은 `databricks fs cp -r`로 `cherry.bronze.raw`에 올린다. 권한은 `contents: read`다.

- [ ] **1단계: 워크플로를 쓰고 `risk-reviewer`로 검토한다**

- [ ] **2단계: 커밋하고 사용자에게 푸시를 요청받은 뒤 수동 실행한다**

```bash
git add .github/workflows/collect.yml
git commit -m "deploy: 카드사 원문 수집 워크플로 추가" -m "작업 003"
```

기대: 실행 기록에 카드사 id, 개수, 실패 id만 보이고 원문 내용은 없다. `databricks fs ls dbfs:/Volumes/cherry/bronze/raw/manifests`에 목록 파일이 보인다.

- [ ] **3단계: GitHub 서버에서 막힌 카드사를 가린다**

과제 9의 PC 결과와 비교해 GitHub에서만 실패한 카드사를 찾는다. 그 카드사는 PC에서 같은 명령에 `--issuer`를 붙여 받고, Claude가 사용자 CLI 로그인으로 올린다. 삼성과 IBK는 사용자가 브라우저로 저장한 파일을 `--add`로 더해 올린다. 결과는 카드사 파일 `notes`와 design.md 4절 2번에 적는다.

---

## 과제 15: 브론즈와 실버 문서

**확인할 공식 문서:**
- Lakeflow 선언형 파이프라인과 Auto Loader: https://docs.databricks.com/aws/en/ldp/ , https://docs.databricks.com/aws/en/ingestion/cloud-object-storage/auto-loader/
- `ai_parse_document`: https://docs.databricks.com/aws/en/sql/language-manual/functions/ai_parse_document
- 볼륨 파일 도착 트리거: https://docs.databricks.com/aws/en/jobs/file-arrival-triggers
- 서버리스 작업의 라이브러리: https://docs.databricks.com/aws/en/compute/serverless/dependencies

**Files:**
- Create: `pipeline/resources/ingest.yml`, `pipeline/src/ingest.py`, `pipeline/resources/refresh.yml`, `pipeline/src/documents.py`

**만들 것:**
- 파이프라인 `cherry_ingest`: Auto Loader로 `raw/manifests/`의 JSON 줄을 읽어 `cherry.bronze.fetches`에 쌓는다. 목록 파일 경로와 적재 시각을 더한다. `path`와 `sha256`이 빈 행은 품질 규칙으로 뺀다.
- 작업 `cherry_refresh`: `raw/manifests/`에 새 파일이 오면 돈다. 태그 `cherry_guard`를 붙인다. 순서는 `cherry_ingest` 갱신, `documents.py`, 과제 16의 `changes.py`, 과제 18의 `extract.py`, 마지막에 `cost_guard.py`다. 과제마다 그때 만든 단계만 더한다. 설계 4절 8번대로 단계마다 실행 시간 제한을 건다. 문서 30분, 변경 감지 10분, 추출 60분, 차단 10분에서 시작하고 과제 15와 18에서 잰 시간의 두 배로 고친다.
- `documents.py`: `bronze.fetches`에 있고 `silver.documents`에 없는 경로만 처리한다. 파일을 볼륨에서 읽어 PDF는 `ai_parse_document` 결과를, 나머지는 바로 `document_text`에 넣는다. `text`, `fingerprint`, 글을 뽑은 방법을 쓴다. 이미 처리한 파일은 다시 읽지 않으므로 `ai_parse_document` 요금은 새 PDF에만 나온다.

- [ ] **1단계: 개발용으로 배포하고 과제 14에서 올린 파일로 돌린다**

기대: `bronze.fetches` 행 수가 목록 파일 줄 수와 같다. `silver.documents` 행 수가 같다. 카드 원문의 글자 수가 과제 9의 PC 결과와 비슷하다.

- [ ] **2단계: 같은 파일로 한 번 더 돌린다**

기대: 두 테이블 모두 행이 늘지 않는다.

- [ ] **3단계: 비용을 본다**

`cherry_cost_guard`를 돌려 쓴 금액이 얼마 늘었는지 적는다. PDF 쪽수와 함께 plan.md에 남긴다.

- [ ] **4단계: 커밋 지점**

```bash
git add pipeline
git commit -m "feat: 원문 적재 파이프라인과 문서 글 뽑기 작업 추가" -m "작업 003"
```

---

## 과제 16: 바뀐 문서와 카드 목록

**Files:**
- Create: `pipeline/src/changes.py`

**만들 것:**
- 원문마다, 즉 카드와 원문 id 한 쌍마다 가장 최근 문서와 그 직전 문서의 지문을 비교한다. 다르면 `changed_lines`로 없어진 줄과 새 줄을 `silver.changes`에 쓴다. 처음 받은 원문은 바뀐 것으로 보지 않는다. 정답 예시가 첫 수집 원문과 짝이기 때문이다.
- 카드사 목록 문서의 지문이 바뀐 때만 `ai_query`로 카드 이름 목록을 뽑아 `silver.card_lists`에 쓴다. 답 형식은 `{"names": [string]}`다. 직전 목록과 비교해 새 이름은 "새 카드", 없어진 이름은 "사라진 카드"로 `silver.queue`에 올린다. 카탈로그의 `name`, `search_names`와 같은 이름은 "새 카드"에서 뺀다.
- 목록을 받을 카드사 3곳을 정한다. 과제 9와 14에서 목록 글이 제대로 나온 곳 중에서 고르고 design.md 1절 3단계에 적는다. 과제 9에서 목록 글이 나온 곳은 하나, 현대, KB, 우리다.
- 과제 9에서 본 것. 하나 공지 본문의 "조회33118" 같은 줄과 KB 공지 목록의 조회수 숫자 줄은 받을 때마다 바뀐다. 이런 줄만 바뀐 원문은 바뀐 것으로 보지 않게 한다. 방법은 이 과제에서 정한다. 그러지 않으면 1단계의 0행 기대가 깨지고 추출 비용이 매번 든다.

- [ ] **1단계: 두 번 수집한 것처럼 시험한다**

개발용 볼륨에 같은 원문을 날짜만 다르게 한 번 더 올린다. 기대: `silver.changes` 0행. intent.md의 "원문이 같은 주기에는 카탈로그 차이가 0"이다.

- [ ] **2단계: 바뀐 원문을 흉내 낸다**

카드 원문 하나에서 숫자 하나를 바꾼 파일을 `--add`로 올린다. 기대: `silver.changes`에 그 원문 한 행, 없어진 줄과 새 줄이 각각 한 줄이다.

- [ ] **3단계: 카드 목록을 흉내 낸다**

목록을 받는 카드사 3곳마다 직전 목록에서 이름 하나를 뺀 목록과 하나를 더한 목록을 만든다. 기대: 카드사마다 "새 카드" 한 건과 "사라진 카드" 한 건이 `silver.queue`에 뜬다. intent.md의 "카드사 3곳 이상" 기준이다.

- [ ] **4단계: 커밋 지점**

```bash
git add pipeline docs/work/003-databricks-pipeline/design.md
git commit -m "feat: 바뀐 원문과 카드 목록 변화 감지 추가" -m "작업 003"
```

---

## 과제 17: 골드 첫 적재와 정답 예시

설계 4절 1번. 이 과제가 끝나면 카탈로그의 원본은 골드다. 그 뒤로 `catalog/`를 사람이나 에이전트가 직접 고치지 않는다.

**Files:**
- Create: `pipeline/src/seed_gold.py`, `pipeline/resources/seed.yml`

**만들 것:**
- 저장소의 `catalog/` 전체를 개발용 볼륨에 올리고, `seed_gold.py`가 파일마다 `gold.catalog_files`에 한 행을 쓴다. 검수 기록 번호는 `initial`이다.
- 같은 파일로 `load_catalog`를 돌려 카드 개정마다 `gold.card_revisions`에 쓴다. 규칙은 `clean_rules`를 거친 JSON이다.
- `silver.golden`: 카드마다 가장 최근 개정의 규칙, 첫 수집 문서 경로를 쓴다. 채점 전용 5장은 `hana-travelog-check`, `hyundai-the-green-ed4`, `kb-my-wesh`, `samsung-taptap-o`, `shinhan-cheoeum`이다. 카드사가 겹치지 않게 골랐다. 나머지 15장은 다듬기용이다.

- [ ] **1단계: 개발용으로 돌리고 PC 결과와 맞춘다**

`gold.card_revisions`의 규칙을 받아 PC에서 `load_catalog`로 만든 결과와 비교한다. 기대: 차이 0.

- [ ] **2단계: 정답 예시와 첫 수집 원문을 대조한다**

첫 수집 원문의 글에 정답 규칙의 금액과 비율이 있는지 사람이 카드마다 훑는다. 수집과 작업 001 대조 사이에 카드사가 원문을 바꾼 카드는 여기서 찾는다. 바뀐 카드는 정답을 원문에 맞추는 개정을 `card-researcher`로 만들어 검수 과정을 거친다.

- [ ] **3단계: 운영에서 돌린다**

사용자에게 푸시를 요청받아 배포한 뒤 운영에서 `seed.yml` 작업을 한 번 돌린다. progress.md에 "카탈로그 원본은 골드"를 적는다.

- [ ] **4단계: 커밋 지점**

```bash
git add pipeline .claude/progress.md
git commit -m "feat: 골드 카탈로그 첫 적재와 정답 예시 추가" -m "작업 003"
```

---

## 과제 18: 추출과 검사

**확인할 공식 문서:**
- `ai_query`와 답 형식: https://docs.databricks.com/aws/en/sql/language-manual/functions/ai_query
- 구조화 출력: https://docs.databricks.com/aws/en/machine-learning/model-serving/structured-outputs
- 쓴 만큼 내는 모델 목록: https://docs.databricks.com/aws/en/machine-learning/foundation-model-apis/supported-models

**Files:**
- Create: `pipeline/src/extract.py`

**만들 것:**
- `silver.changes`에 새 행이 있는 카드만 추출한다. 평가 모드에서는 `silver.golden`의 카드를 지정한 모델로 추출한다.
- 카드마다 원문 id별 가장 최근 문서의 글을 모아 `build_prompt`에 넣는다. 지금 규칙은 `gold.card_revisions`의 마지막 개정이다. 코드 목록은 `gold.catalog_files`로 만든 카탈로그의 `catalog_codes`다.
- `ai_query(모델, 프롬프트, responseFormat => response_schema())`를 `failOnError => false`로 부른다. 답은 `parse_answer`, `make_draft`, `check_draft` 순서로 처리한다.
- `silver.drafts`에 쓴다: 카드, 쓴 변경 행, 모델, 프롬프트 판 `VERSION`, 답 원문, 초안 YAML, 검사 결과, 만든 시각.
- `silver.queue`에 올린다. 초안이 None이면 올리지 않는다. 검사에 걸린 초안도 걸린 이유와 함께 올린다. `make_draft`가 `ValueError`를 내거나 답이 오류면 "사람이 정할 것"으로 까닭과 함께 올린다.

- [ ] **1단계: 모델 이름을 확인한다**

```bash
databricks serving-endpoints list
```

Claude Sonnet급 하나와 Claude Haiku급 하나의 이름을 design.md 4절 3번에 적는다.

- [ ] **2단계: 카드 한 장으로 답 형식을 시험한다**

`response_schema()`를 그대로 넘겨 본다. `$defs`나 재귀 참조를 거부하면 `prompt.py`에 참조를 펼치는 함수를 더하고 테스트를 쓴다. `Condition.any_of`처럼 자기 자신을 품는 칸은 두 단계까지만 펼친다. 결과를 design.md 1절 4단계에 적는다.

- [ ] **3단계: 다듬기용 15장을 두 모델로 추출한다**

기대: 30건 모두 `silver.drafts`에 행이 있다. 정답과 같은 규칙이면 초안이 없고, 다르면 검사 결과가 붙은 초안이 있다. 쓴 금액을 적는다.

- [ ] **4단계: 커밋 지점**

```bash
git add pipeline backend docs/work/003-databricks-pipeline/design.md
git commit -m "feat: LLM 규칙 추출과 초안 검사 작업 추가" -m "작업 003"
```

---

## 과제 19: 정확도 측정과 모델 고르기

**확인할 공식 문서:**
- MLflow 실행 기록: https://mlflow.org/docs/latest/ml/tracking/
- 번들의 실험 자원: https://docs.databricks.com/aws/en/dev-tools/bundles/resources

**Files:**
- Create: `pipeline/src/evaluate.py`, `pipeline/resources/evaluate.yml`

**만들 것:** 작업 `cherry_evaluate`. 인자는 모델과 프롬프트 판이다. `silver.golden`의 20장을 추출하고, 카드마다 `field_accuracy(clean_rules(정답), clean_rules(추출))`를 구한다. 다듬기용 15장과 채점 전용 5장을 따로 `total_accuracy`로 합친다. MLflow 실행 하나에 모델, 프롬프트 판을 인자로, `tune.<묶음>`과 `holdout.<묶음>`을 지표로, 카드별 결과표를 파일로 남긴다. 검수에서 사람이 고친 값이 있으면 그 카드의 정답을 고친 값으로 바꿔 채점한다. 설계 4절 5번.

- [ ] **1단계: 두 모델을 채점한다**

기대: MLflow에 실행 두 개, 지표에 `tune.all`, `holdout.all`과 묶음별 값이 있다.

- [ ] **2단계: 프롬프트를 다듬는다**

다듬기용 15장의 틀린 칸만 보고 `INSTRUCTIONS`를 고치고 `VERSION`을 올린다. 채점 전용 5장은 결과 숫자만 보고 내용은 보지 않는다. 한 번 채점에 드는 금액을 보고 체험 한도 안에서 몇 번 할지 정한다.

- [ ] **3단계: 모델을 고른다**

기준은 2026-09-29 사용자가 승인했다. Haiku급의 채점 전용 정확도가 모든 묶음에서 Sonnet급보다 5%p 넘게 낮지 않으면 Haiku급을 쓰고, 아니면 Sonnet급을 쓴다. 고른 모델과 숫자를 design.md 4절 3번에 적는다.

- [ ] **4단계: 커밋 지점**

```bash
git add pipeline backend/cherry_core/pipeline/prompt.py docs/work/003-databricks-pipeline/design.md
git commit -m "feat: 추출 정확도 채점 작업과 모델 선택 결과 추가" -m "작업 003"
```

---

## 과제 20: 검수 앱

설계 4절 5번.

**확인할 공식 문서:**
- Databricks 앱: https://docs.databricks.com/aws/en/dev-tools/databricks-apps/
- 앱에서 SQL 웨어하우스 쓰기와 자원 권한: https://docs.databricks.com/aws/en/dev-tools/databricks-apps/resources
- 번들의 앱 자원: https://docs.databricks.com/aws/en/dev-tools/bundles/resources

**Files:**
- Create: `pipeline/apps/review/app.py`, `pipeline/apps/review/app.yaml`, `pipeline/apps/review/requirements.txt`, `pipeline/resources/review.yml`

**만들 것:** Streamlit 앱 `cherry_review`. 앱이 쓰는 SQL 웨어하우스는 가장 작은 크기로 두고, 쓰지 않으면 가장 짧은 시간 안에 멈추게 한다. 설계 4절 8번.
- 목록: `silver.queue`의 대기 건. 종류, 카드, 만든 시각.
- 초안 한 건: 바뀐 원문 줄, 바뀐 칸의 전과 후, 검사 결과, 고칠 수 있는 YAML 칸, 승인과 반려 버튼.
- 승인: 고친 YAML을 `check_draft`로 다시 검사한다. 오류가 있으면 승인 버튼이 듣지 않는다. 통과하면 한 번에 다음을 한다. `silver.reviews`에 기록, `gold.catalog_files`에 MERGE, 그 카드의 `gold.card_revisions`를 다시 만듦, `cherry.gold.export/pending/<검수 번호>/`에 바뀐 파일과 `commit.json`을 씀, 대기 건을 끝남으로 바꿈.
- 반려: `silver.reviews`에만 기록한다.
- 새 카드와 사라진 카드: 확인만 표시한다. 새 카드 조사는 `card-researcher`로 따로 한다.
- 커밋 제목은 `feat: <카드 이름> <시행일> 개정 반영`이다. 발급 중단이면 `feat: <카드 이름> 발급 중단 반영`이다.

- [ ] **1단계: 개발용으로 시험한다**

과제 18의 초안 하나를 승인하고 하나를 반려한다. 기대:
- 승인한 건은 골드 두 테이블과 `pending/` 폴더가 바뀐다.
- 반려한 건은 골드가 그대로다.
- 검사 오류가 있는 YAML은 승인되지 않는다.

- [ ] **2단계: 앱을 끄는 것까지 확인한다**

검수가 끝나면 앱을 끈다. `cherry_cost_guard`가 한도에서 앱을 끄는지도 과제 13의 방법으로 한 번 본다.

- [ ] **3단계: 커밋 지점**

```bash
git add pipeline
git commit -m "feat: 카드 개정 초안 검수 앱 추가" -m "작업 003"
```

---

## 과제 21: 내보내기 워크플로와 커밋 규칙 예외

설계 4절 7번.

**확인할 공식 문서:**
- Actions에서 저장소에 쓰기: https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token

**Files:**
- Create: `.github/workflows/export.yml`
- Modify: `.claude/CLAUDE.md`의 커밋 절

**만들 것:** 매일 UTC 19시와 수동 실행에서 돈다. 권한은 `contents: write`다.
1. 저장소를 받고 uv와 CLI를 설치한다. `git config core.hooksPath .githooks`로 커밋 훅을 켠다. 작성자는 `github-actions[bot]`이다.
2. `pending/` 아래 폴더마다 내려받아 `python -m cherry_core.pipeline.export`를 돌린다.
3. `python -m cherry_core.catalog check`가 통과하면 `git add catalog`, `git commit -F <메시지 파일>`, 푸시한다. 훅이 형식과 민감 정보를 검사한다.
4. 푸시가 되면 그 폴더를 `done/`으로 옮긴다. 검사나 훅이 막으면 폴더는 `pending/`에 두고 실패로 끝낸다. 다음 날 다시 시도하지 않도록 실패하면 메일이 가게 GitHub 알림을 켜 둔다.

`.claude/CLAUDE.md` 커밋 절에 한 줄 더한다: "검수에서 승인된 카탈로그 개정은 GitHub Actions가 봇 이름으로 master에 바로 커밋한다. 사용자가 2026-09-29 정한 예외다. 작업 003 설계 4절 7번."

- [ ] **1단계: `risk-reviewer`로 검토한다**

쓰기 권한이 필요한 단계에만 있는지, 내보내기 폴더의 파일이 `catalog/` 밖을 건드릴 길이 없는지, 실행 기록에 비밀값이 찍히지 않는지 본다.

- [ ] **2단계: 커밋하고 사용자에게 푸시를 요청받는다**

```bash
git add .github/workflows/export.yml .claude/CLAUDE.md
git commit -m "deploy: 승인된 카탈로그 개정 자동 커밋 워크플로 추가" -m "작업 003"
```

- [ ] **3단계: 운영에서 시험한다**

운영 검수 앱에서 실제로 맞는 개정 하나를 승인한다. 원문을 다시 확인한 카드의 `checked_at`만 바뀌는 개정이면 충분하다. 워크플로를 수동 실행한다. 기대:
- master에 `github-actions[bot]` 이름의 커밋이 생긴다.
- 커밋 본문에 `검수 기록 <번호>`와 `작업 003`이 있다.
- `pending/`이 비고 `done/`에 그 폴더가 있다.

---

## 과제 22: 계보 확인

설계 1절 8단계.

**확인할 공식 문서:**
- Unity Catalog 계보: https://docs.databricks.com/aws/en/data-governance/unity-catalog/data-lineage

**Files:**
- Create: `pipeline/src/lineage.sql`

- [ ] **1단계: 행 단위로 따라가는 SQL을 쓴다**

`gold.catalog_files`의 한 행에서 검수 번호로 `silver.reviews`, 대기 건으로 `silver.drafts`, 쓴 변경 행으로 `silver.changes`와 `silver.documents`, 경로로 `bronze.fetches`까지 이어 원문 파일 경로를 돌려준다.

기대: 과제 21에서 승인한 개정의 행이 원문 파일 경로 하나 이상을 돌려준다.

- [ ] **2단계: 테이블 단위 계보를 본다**

`system.access.table_lineage`나 카탈로그 탐색기의 계보 화면에서 `bronze.fetches`부터 `gold.catalog_files`까지 이어지는지 본다. 끊긴 곳이 있으면 그 단계의 코드가 테이블을 읽는 방식을 고친다.

- [ ] **3단계: 커밋 지점**

```bash
git add pipeline/src/lineage.sql
git commit -m "feat: 골드 카탈로그에서 원문까지 계보 조회 추가" -m "작업 003"
```

---

## 과제 23: 성공 기준 확인

intent.md의 성공 기준을 하나씩 확인하고 이 문서 끝 "성공 기준 확인"에 결과를 적는다.

- [ ] 카드 20장의 원문이 주기마다 브론즈에 쌓이고 바뀐 문서만 추출로 넘어간다. 확인: 과제 14 수동 실행의 `bronze.fetches` 행 수와 과제 16의 `silver.changes`
- [ ] 원문이 같은 주기에는 카탈로그 차이가 0이다. 확인: 과제 16 1단계
- [ ] 카드사 3곳 이상에서 새 카드와 사라진 카드가 검수 대기에 뜬다. 확인: 과제 16 3단계
- [ ] 필드별 정확도가 MLflow에 남고 프롬프트나 모델을 바꿀 때마다 다시 잰다. 확인: 과제 19의 실행 목록
- [ ] 검사에 걸린 초안도 이유와 함께 검수 대기에 오르고, 검증을 통과해야 승인된다. 사람 승인 없이 골드로 간 초안이 없다. 확인: `gold.catalog_files`의 모든 행이 `initial`이거나 `silver.reviews`의 승인 행과 이어지는지 SQL로 센다
- [ ] 골드의 카드 개정 한 줄에서 원문 파일까지 계보로 따라간다. 확인: 과제 22
- [ ] 하루치 사용자 로그가 다음 날 실버 테이블에서 조회된다. 하위 프로젝트 2 뒤로 미룬다. 이 작업에서는 확인하지 않는다고 적는다
- [ ] 사용자가 직접 하는 설정 단계마다 무엇이 보이면 성공인지 안내 문서에 있다. 확인: `docs/databricks.md`를 단계마다 읽는다

---

## 과제 24: 문서 합치기와 마무리

- [ ] 설계 문서 3절에 카드사별 수집 결과를, 5절 하위 프로젝트 3에 끝난 것과 미룬 것을 적는다. 미룬 것은 로그 적재와 숫자 초안이다.
- [ ] `docs/databricks.md`의 "이 프로젝트에서 Databricks가 하는 일"을 실제 만든 것에 맞춘다.
- [ ] README의 폴더 나무에 `pipeline/`과 `.github/`를 더한다.
- [ ] `.claude/progress.md`에서 작업 003을 끝난 것으로 옮긴다. 카탈로그 원본이 골드라는 것과, 새 카드를 넣는 길이 검수 앱이라는 것을 적는다.
- [ ] `docs/history/`에 기록을 쓴다.
- [ ] 커밋 지점: `docs: 작업 003 결과를 설계 문서와 안내서에 반영`

## 성공 기준 확인

과제 23에서 채운다.
