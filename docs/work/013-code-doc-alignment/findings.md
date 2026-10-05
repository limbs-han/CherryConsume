# 013 찾은 어긋남 53건

2026-10-05 `취준/체리컨슘_코드_해설서.md` 13장을 옮겨 왔다. 해설서는 저장소 밖에 있어 이 작업의 출발점을 여기에 둔다.

3장부터 12장을 쓰며 찾은 것을 모았다. 코드는 2026-10-05 master `0768a96`, 파이프라인은 `4987d33` 기준이다. 세 묶음으로 나눴다. 가는 지금 동작이 문서나 정한 원칙과 달라 고칠지 정해야 하는 것, 나는 코드가 나중에 바뀌었는데 문서나 주석이 따라오지 않은 것, 다는 지금은 맞지만 곧 어긋날 것이다. "판단" 칸은 해설하며 본 의견이고 정해진 것이 아니다. 이 장은 고칠 목록이 아니라 회고 자료다. 고치려면 작업 단위를 따로 만든다.

### 가. 동작이 문서나 원칙과 다른 것

| 번호 | 코드 | 문서 | 다른 점 | 판단 |
|---|---|---|---|---|
| 13-1 | `app/lib/engine/price.dart` `price` | 설계 문서 6.3, 작업 002 설계 1.4 | 결제 결과의 조건부 혜택 `PaymentResult.conditional`을 채우지 않는다. 추천에만 담긴다 | 화면이 결제 결과의 조건부 혜택을 쓰지 않으면 문서를 고친다 |
| 13-2 | `app/lib/engine/price.dart` 788~806줄 | 설계 문서 6.5, 작업 002 설계 3.5, 5.1 | 달 중간이면 순위 혜택마다 `ranked_provisional`을 늘 붙인다. 문서는 순위가 바뀌면 붙인다 | 확인 필요 |
| 13-3 | `app/lib/engine/price.dart` 609~616줄 | 작업 002 설계 5.1 | 실적 경고 `no_prev_month_data`, `spend_basis_unsupported`가 결제 결과와 추천에도 붙는다 | 문서를 고친다 |
| 13-4 | `app/lib/engine/recommend.dart` `queryPayment` | 설계 문서 6.5, 작업 002 설계 4.1 | 가맹점 기본 채널과 지역 단계가 없다. 카탈로그 가맹점에 그 칸도 없다 | 문서를 고친다 |
| 13-5 | `app/lib/engine/spend.dart` `newCardTier` | 작업 001 설계, 카드 파일 `new_card.from` | 발급일, 수령일, 사용 등록일, 첫 사용일을 구분하지 않고 쓰기 시작한 날 하나만 쓴다 | 카드 파일의 확인 필요 항목에 이미 남아 있다 |
| 13-6 | `app/lib/engine/` 여러 곳 | `.claude/rules/engine.md`, 작업 002 설계 1.1 | "엔진 함수는 예외를 던지지 않는다"인데 `StateError`, `ArgumentError`, `!`, `firstWhere`가 있다. 검사를 통과한 카탈로그라면 닿지 않는다 | 규칙에 전제를 적는다 |
| 13-7 | `backend/cherry_core/catalog/app_json.py` `rule_errors` | 설계 문서 6.8 | 앱 JSON은 `check_rules` 오류만 막는다. 개정 출처 누락, 별칭 겹침은 막지 않는다. 실제로는 `export.yml`과 승인이 `check`를 먼저 돌려 막는다 | 문서를 고친다 |
| 13-8 | `backend/cherry_core/catalog/models.py` 131행 `Reward.round` | `.claude/CLAUDE.md` 반드시 지킬 규칙 | 반올림 기본값이 `floor`다. 작업 001 설계 2.5가 정했지만 "하나의 기본값으로 단순화하지 않는다"와 긴장한다 | 확인 필요 |
| 13-9 | `app/lib/store/db.dart` 28줄 `user_cards.nickname` | 작업 012 설계 1.1, 개인정보처리방침 2절 | 칸은 있지만 값을 쓰는 코드가 없다. 방침은 "카드 별명"을 폰에 둔다고 적었다 | 방침은 틀린 말이 아니지만 쓰지 않는 칸이다 |
| 13-10 | `app/lib/store/routes/imports.dart` 662~665줄 | 설계 문서 8절 기록 남기기 | `import_batches.source`를 적지 않아 늘 비어 있다 | 확인 필요 |
| 13-11 | `app/lib/store/imports.dart` 26~49줄 | 설계 문서 8절 | 카드사별 매핑 표 대신 흔한 열 이름 사전만 있다. ponytail 주석으로 알고 한 단순화라고 밝혔다 | 알고 한 단순화 |
| 13-12 | `app/lib/store/routes/imports.dart` `required` | `docs/scenarios.md` E30 | 꼭 고를 열이 결제일, 가맹점명, 금액 셋이다. E30은 취소 여부까지 넷 | 문서를 고친다 |
| 13-13 | `app/lib/screens/recommend.dart` 655줄 | 작업 004 설계 2.1, 시안 | "조건 확인" 배지가 호박색이다. 정한 색은 알림 회색 | 코드를 고친다 |
| 13-14 | `app/lib/screens/recommend.dart` 228~231, 512~515, 526~529줄 | 작업 004 설계 2.1 | 흐린 글자가 회색 바탕 위에 있다. 대비 4.19:1이라 흰 상자 안에서만 쓰기로 했다 | 코드를 고친다 |
| 13-15 | `app/lib/screens/import.dart` 365줄 | 작업 004 설계 2.1 | 오류 문장이 호박색이다. 호박색은 기회에만 쓴다 | 코드를 고친다 |
| 13-16 | `app/lib/ui.dart` | 작업 011 설계 1절 원칙 4, 설계 문서 10절 | 진동은 칩과 바닥 시트 줄 두 곳뿐이다. 결제 기록 저장과 카드 등록은 떨지 않는다 | 확인 필요 |
| 13-17 | `app/lib/screens/payment.dart` 469~483줄 | 작업 004 설계 3절 | 카드가 많아도 모두 늘어놓는다. 1순위 두 장과 다른 카드로 줄이기는 아직이다 | 카드가 많은 사용자가 생기면 |
| 13-18 | `app/lib/screens/import.dart` 412, 439줄 | 설계 문서 10절 원칙 5 | 열 짝짓기가 드롭다운이다. 고를 것이 넷 이상이면 바닥 시트가 원칙이다 | 확인 필요 |
| 13-19 | `app/lib/screens/records.dart` 306줄 | 작업 011 설계 1절 원칙 4 | 기록의 결제 줄은 누를 때 작아지지 않는다. 원칙의 "기록의 카드 줄"이 이 줄인지 모른다 | 확인 필요 |
| 13-20 | `.github/workflows/export.yml` 125, 145줄 | 머리 주석 4줄, 작업 003 설계 4절 7번 | 푸시하는 작업은 GitHub이 만든 액션만 쓴다고 했는데 `astral-sh/setup-uv`가 있고, 쓰기 열쇠가 남은 채로 PyPI 패키지를 받는다 | 보안 검토 거리 |
| 13-21 | `.githooks/pre_push.py` 17~20줄 | 작업 006 설계 2절, 커밋 `7c8aa04` | 올리는 가지의 끝 커밋 하나만 본다. 문서는 올리는 커밋마다 본다 | 코드를 고친다 |
| 13-22 | `.githooks/commit_msg.py` 24~27줄 | 같은 파일 제목 검사 | 이름 검사는 `#` 안내 줄까지 본다. 편집기로 커밋하면 안내 줄의 `.claude/` 경로에 걸릴 수 있다 | 추정. 실행해 보지 않았다 |
| 13-23 | `app/android/app/build.gradle.kts` 13~18줄 | 작업 005 설계 5h | 서명 값 검사가 `key.properties`가 있으면 디버그 빌드에서도 돈다. 문서는 출시 빌드만 | 일찍 알리려는 것으로 보인다. 추정 |

### 나. 코드가 바뀌고 문서나 주석이 남은 것

| 번호 | 낡은 쪽 | 지금 코드 | 다른 점 |
|---|---|---|---|
| 13-24 | `backend/cherry_core/catalog/app_json.py` 28, 95행, `load.py` 56행, `models.py` 247행 주석 | 서버는 작업 006에서 지웠다 | "서버의 card_revisions", "서버의 업종 표", "서버는 다시 매기지 않는다"가 남았다 |
| 13-25 | 작업 001 설계 2.12 | `resolve.py` 12행 `KEYED_LISTS` | key로 합치는 목록에 `ranked`가 더해져 여섯이다 |
| 13-26 | 작업 001 설계 1절, 4.1 | `IssuerFile`, `__main__.py` | `billing_cycles` 칸은 없다. 4.6 3번이 뺐다. 코드 위치 표에 `json` 명령, `load.py`, `app_json.py`가 없다 |
| 13-27 | 설계 문서 6.5 | `app/lib/engine/cond.dart` `isHoliday` | 공휴일은 `holidays` 패키지가 아니라 카탈로그 JSON의 2020~2036년 목록이다 |
| 13-28 | `app/lib/store/db.dart` 4줄 | 같은 파일 | "나머지 표는 계획 단계 4의 1에서 더한다"는 지난 말이다 |
| 13-29 | 작업 006 설계 6절 | `app/lib/store/backup.dart` 81~84, 131~151줄 | 카탈로그에 없는 것이 든 파일의 안내 문구가 바뀌었고, 결제수단 두 칸도 검사한다 |
| 13-30 | 작업 006 설계 6절 235줄 | `data_extraction_rules.xml` | 백업에서 빼는 곳이 다섯 구역 `./`에서 아홉 구역 `.`이 됐다 |
| 13-31 | 작업 005 설계 5d, 5e | `records.dart` 396~414줄, `backup.dart` 30~39줄 | 취소로 지난 달 순위를 다시 매기고, 사람 사실도 내보낸다. E55와 작업 006 설계 6절에서 바뀌었다 |
| 13-32 | `docs/scenarios.md` E21 | `db.dart` 36줄 | 유니크가 `(user_id, card_id)`에서 `(card_id) where removed_at is null`이 됐다. 사용자 칸이 없어졌다 |
| 13-33 | `docs/scenarios.md` E31, 작업 005 설계 5f | `routes/imports.dart` 299~305, 941줄 | 승인번호가 같으면 다른 행이 차지한 결제라도 겹침으로 본다. 되돌릴 때 취소 시각은 지금 시각이 아니라 적혀 있던 시각이다 |
| 13-34 | `routes/imports.dart` 482줄, `app/test/store/imports_test.dart` 647줄 주석 | 작업 006 설계 6절 | 열 짝 표는 기록 가져오기로 들어오지 않는다 |
| 13-35 | 작업 006 설계 5절 | `app/lib/store/imports.dart` 109, 147, 181~292줄 | 행 상한이 문구 3,000, 실제 3,020, 문서 3,030으로 셋이다. csv 코드는 40줄 안팎이 아니라 약 110줄이다 |
| 13-36 | `app/lib/catalog/download.dart` 3~4줄, 작업 006 설계 2절 34, 69줄 | `cache.dart` 30, 59줄 | 받은 카탈로그 검사에 결제수단이 더해졌고, 소수 기준은 넷째 자리가 아니라 약분한 분모 1만 이하다 |
| 13-37 | `docs/scenarios.md` S9, `home.dart` 303줄, `card_detail.dart` 689줄, `shell.dart` 1줄 | 화면 코드 | 메뉴 이름이 "카드 삭제"가 아니라 "카드 해지"다. 주석의 갈래 수, 주석 위치, 근거 절 번호가 어긋났다 |
| 13-38 | `docs/databricks.md` 76줄, 설계 문서 3절 38~39줄, 작업 003 설계 4절 2번 | `collect.py` `ROBOTS_IGNORED`, `--ignore-robots`, `collect.yml` | robots.txt로 막은 카드사도 이제 자동으로 받고, 이 옵션을 색인뿐 아니라 카드 원문에도 쓴다 |
| 13-39 | 작업 008 의도 정한 것 | `disclosure.py` `collectable`, 작업 008 계획 5단계 | 단종일 모르는 단종 카드도 받는다. 의도와 계획끼리도 다르다 |
| 13-40 | `catalog/issuers/lotte.yaml` notes | `disclosure._lotte_plan` | 롯데 공시 목록을 500이 아니라 2000개씩 받는다 |
| 13-41 | `pipeline/src/approve.py` 229줄, 작업 003 계획 과제 20 | `stale_exports` 기본값 | "하루 넘게"가 아니라 36시간이다 |
| 13-42 | `pipeline/src/extract.py` 293줄, `docs/databricks.md` 370줄, 작업 003 설계 1절 | `changes.py` 236~237줄, 작업 008 계획 10.4 | 목록 비교는 사라진 카드만 올린다. 새 카드는 `new_card` 모드가 초안과 함께 올린다 |
| 13-43 | `pipeline/resources/review.yml` 4줄 | `docs/databricks.md` 365줄 | 운영 비용 차단은 개발용 앱을 끄지 못한다 |
| 13-44 | 작업 003 계획 과제 18 | `pipeline/src/extract.py` 300줄 | 지금 규칙은 `card_revisions`가 아니라 `catalog_files`를 `resolve_card`로 풀어 계산한다 |
| 13-45 | 작업 003 설계 4절 7번 | `export.yml` 132줄 | 봇 커밋이 `catalog/`뿐 아니라 `app/assets/catalog.json`도 바꾼다 |
| 13-46 | `docs/databricks.md` 집 PC 러너 절 | 같은 절 | 러너를 켜는 곳은 Git Bash, 끄는 곳은 PowerShell 창으로 적혀 있다 |
| 13-47 | `backend/cherry_core/pipeline/history.py` 머리 주석, 작업 010 계획 5단계 | `pipeline/src/seed_gold.py` 109줄, 작업 010 계획 1단계 | 변경 데이터 피드를 켜는 때가 "쓰기 전"과 "쓰고 난 뒤"로 갈린다. 코드는 쓰고 난 뒤다 |
| 13-48 | 작업 006 계획 단계 1의 5, `.claude/progress.md` 57줄 | 봇 커밋 `90ff4b3` | 봇 커밋에 `app/assets/catalog.json`이 함께 들어가는지 "그때 본다"고 남았지만 2026-10-04 이미 들어갔다 |
| 13-49 | `.claude/progress.md` 59줄, `.claude/CLAUDE.md` 40줄 | `collect.yml`, 작업 008 11단계 | 삼성, 롯데, IBK 자동 수집이 없다는 문장과 새 카드를 넣는 길을 "과제 20에서 정한다"는 문장이 낡았다 |
| 13-50 | `docs/history/README.md` 목록 | 같은 목록의 번호 규칙 | 50과 51이 두 개씩 있다. 세션 둘이 같은 번호를 쓴 것이다. 74와 75도 겹쳤는데 2026-10-05 이 해설서를 쓰며 주 개발 세션 쪽을 76, 77로 옮겼다 |

### 다. 곧 어긋날 것

| 번호 | 어디 | 무엇 |
|---|---|---|
| 13-51 | `catalog/issuers/`의 삼성, IBK, 롯데 `method: blocked` | 기준 커밋 `0768a96`에서는 골드만 `api`였다. 바로 뒤 커밋 `de17f14`가 저장소의 세 파일을 바꿔 `collect.targets`가 세 카드사를 받기 시작한다. 이 해설서 기준 뒤에 맞춰졌다 |
| 13-52 | `pipeline/src/lineage.sql` 10줄, `pipeline/dashboards/ops.lvdash.json` 74줄 | "삼성, 롯데, IBK 다섯 장은 자동 수집 원문이 없다"는 집 PC 러너가 처음 돌면 틀린 말이 된다 |
| 13-53 | `backend/tests/engine/` | git에는 없고 디스크에만 남은 빈 폴더다 |

### 무엇을 배웠나

- 어긋남의 절반 넘게가 "나" 묶음이다. 작업 006에서 서버를 지우며 코드는 한 번에 옮겼지만, 작업 001, 002, 005의 설계 문서와 주석은 그날의 기록으로 남았다. 작업 폴더는 이력이고 기준은 설계 문서라는 규칙이 있어도 주석은 그 규칙 밖에 있었다.
- "가" 묶음의 화면 색과 대비는 작업 004에서 정한 것이 작업 011 다듬기 중에 새로 생긴 화면에서 빠졌다. 원칙을 시험으로 지키지 않으면 새 화면이 원칙을 모른다.
- 위험 검토가 바꾼 코드는 계획 결과에만 적히고 설계 본문은 고치지 않은 경우가 많다. 13-29, 13-30, 13-33, 13-36이 그렇다.
