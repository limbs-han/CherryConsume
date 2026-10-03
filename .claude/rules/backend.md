---
paths:
  - "backend/**"
---

# 카탈로그와 파이프라인 Python 규칙

- `cherry_core`는 카탈로그 읽기와 검사, 앱 JSON 만들기, 파이프라인 코드다. 계산 엔진은 `app/lib/engine`의 Dart다. 2026-10-03 작업 006에서 Python 엔진과 서버를 지웠다.
- 모델은 Pydantic으로 쓴다. 금액 필드는 int다.
- 패키지와 실행은 uv로 관리한다. 형식과 문법 검사는 ruff로 한다.
