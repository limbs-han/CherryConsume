# 체리컨슘 AI 작업 안내

이 저장소를 연 AI는 Claude Code가 아니어도 아래 순서로 읽고 그대로 따른다. 사람이 다른 PC에서 이어 받을 때도 같은 순서다.

1. `.claude/CLAUDE.md`. 프로젝트 소개, 사용자, 반드시 지킬 규칙, 작업 순서, 커밋, 명령, 새 PC 준비, 말투. 파일 이름에 Claude가 들어 있지만 모든 AI에 똑같이 적용한다. 지침의 "Claude"는 지금 일하는 AI로 읽는다
2. `.claude/progress.md`. 맨 위 "한눈에"가 전체 상황, 진행 중인 작업, 다음 할 일이다. 그 아래가 작업마다 자세한 진행과 사용자 확인이 필요한 것이다
3. 진행 중인 작업 폴더 `docs/work/<번호>-<이름>/`의 `intent.md`, `design.md`, `plan.md`. 다음 할 일은 `plan.md`에서 체크되지 않은 첫 칸이다
4. 필요할 때 설계 문서 `docs/2026-09-19-cherryconsume-design.md`, 시나리오 `docs/scenarios.md`, ERD `docs/erd.md`, 작업 기록 `docs/history/`

## Claude Code 전용 장치를 손으로 대신하기

Claude Code는 `.claude/settings.json`의 훅, 스킬, 에이전트를 저절로 쓴다. 다른 AI는 아래를 직접 한다.

| 장치 | Claude Code에서 하는 일 | 다른 AI가 할 일 |
|---|---|---|
| 세션 시작 훅 `.claude/hooks/session_start.py` | git 훅 경로를 `.githooks`로 맞추고 진행 상황을 보인다 | `git config core.hooksPath .githooks`를 한 번 돌리고 `.claude/progress.md`를 읽는다 |
| 파일 고친 뒤 훅 `.claude/hooks/after_edit.py` | `catalog/`의 YAML을 고치면 카탈로그 검사, `.py`를 고치면 ruff 형식 맞추기와 검사 | 같은 파일을 고쳤으면 `.claude/CLAUDE.md` "명령"의 카탈로그 검증, `uvx ruff format <파일>`, `uvx ruff check --fix <파일>`을 돌린다 |
| 끝내기 전 훅 `.claude/hooks/on_stop.py` | `backend/`가 바뀌면 pytest, `app/lib/engine`이나 `app/lib/store`가 바뀌면 그 Dart 시험을 돌리고 실패하면 계속 고친다 | 일을 마치기 전에 같은 시험을 돌려 통과시킨다 |
| 한국어 훅 `.claude/hooks/korean_only.py` | 답에 영어 문장이 섞이면 다시 쓰게 한다 | 보내기 전에 스스로 확인한다. `.claude/output-styles/korean.md` |
| 경로 규칙 `.claude/rules/` | `backend/`, `catalog/`, `app/lib/engine/`을 고칠 때 붙는 규칙 | 그 경로를 고치기 전에 해당 파일을 읽는다 |
| 스킬 `.claude/skills/<이름>/SKILL.md` | `work`는 작업 단위, `commit`은 커밋 절차, `rule-change`는 계산 규칙 바꾸기 | 그 상황이 되면 SKILL.md를 읽고 순서대로 한다 |
| 에이전트 `.claude/agents/` | `risk-reviewer`는 돈, 개인정보, 기록 옮기기, DB 마이그레이션 검토. `card-researcher`는 카드 조사, `card-verifier`는 카드 원문 대조 | 그 파일의 지시를 점검 목록으로 삼아 따로 한 번 검토하고 결과를 사용자에게 보인다 |

`.githooks/`의 git 훅은 AI와 상관없이 커밋과 푸시 때 메시지 형식, 민감 정보, 카탈로그 JSON을 검사한다. 막히면 `--no-verify`로 넘기지 말고 원인을 고친다. 커밋 메시지와 작성자 정보에는 Claude뿐 아니라 쓰고 있는 AI의 이름도 넣지 않는다.
