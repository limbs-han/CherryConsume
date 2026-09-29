---
paths:
  - "catalog/**"
  - "backend/cherry_core/catalog/**"
---

# 카드 카탈로그 규칙

카탈로그는 2판이다. 칸의 뜻과 예시는 `docs/work/001-catalog-schema-v2/design.md` 2절과 3절, 코드는 `backend/cherry_core/catalog/models.py`가 기준이다.

## 파일

- 카드는 `catalog/cards/<카드사>/<카드 id>.yaml`, 카드사 공통 규칙은 `catalog/issuers/<카드사>.yaml`이다.
- 공통 파일은 `categories.yaml`, `merchants.yaml`, `payment_methods.yaml`, `point_programs.yaml`, `reference.yaml`이다. 여러 에이전트가 동시에 일할 때는 공통 파일을 한 곳에서만 고친다.
- 파일에 주석을 쓰지 않는다. `format`이 지운다. 사람용 메모는 `notes`에 쓴다.

## 값

- 값은 카드사 공식 상품 페이지나 카드사가 올린 상품설명서와 약관 PDF에서만 옮긴다.
- 확인하지 못한 값은 추측하지 않고 `open_questions`에 남긴다.
- 금액은 원 단위 정수, 비율은 퍼센트 숫자다.
- 결제 입력으로 판단할 수 없는 조건만 `unmodeled`에 문장으로 남긴다.
- 신규 발급이 끝난 카드도 지우지 않는다. `status`를 바꾼다.
- 한 번 정한 카드 id와 혜택 key는 바꾸지 않는다. 결제 기록이 그 key를 가리킨다.
- 카드사가 혜택을 바꾸면 옛 개정을 지우지 않고 새 개정을 더한다.

## 명령

- 검증: `uv run --project backend python -m cherry_core.catalog check`
- 형식: `uv run --project backend python -m cherry_core.catalog format`
- 파일을 고치면 훅이 검증을 돌린다. 오류가 나오면 그 자리에서 고친다.
