# 작업 기록

사용자가 시킨 요청, 그 결과, 수정 요청과 반영, 최종 결과를 작업마다 한 파일에 남긴다. 작업 하나는 요청 하나에서 시작해 수정 요청이 이어지다 결과가 확정될 때까지다.

설계와 계획은 `docs/work/`에 있고, 여기는 그 결정이 어떤 요청과 수정을 거쳐 나왔는지의 기록이다.

## 파일 형식

파일 이름은 `NN-<영문 소문자 슬러그>.md`이고 번호는 작업 순서다.

```markdown
# NN 제목

- 날짜: YYYY-MM-DD
- 결과물: 파일 링크
- 커밋: `해시` 메시지

## 요청

> 사용자 요청 원문 그대로

## 과정

### 첫 결과
무엇을 내놓았는지. 선택지를 냈으면 무엇 중에 무엇을 골랐는지

### 수정 요청 1
> 원문

반영: 무엇을 바꿨는지

## 최종 결과
확정된 결정과 결과물
```

- 요청은 한 글자도 바꾸지 않고 인용한다.
- 선택지 답은 "선택: 질문 요지 → 고른 답" 한 줄로 쓴다.
- 대화에 있었던 것만 쓴다.

## 목록

| 번호 | 날짜 | 작업 |
|---|---|---|
| [01](01-planning-kickoff.md) | 2026-09-19 | 기획 시작과 서비스 설계 |
| [02](02-erd-wireframe.md) | 2026-09-19 | ERD와 와이어프레임 |
| [03](03-scenarios.md) | 2026-09-19 | 사용자 시나리오와 예외 |
| [04](04-app-icon.md) | 2026-09-19 | 앱 아이콘 |
| [05](05-commit-convention.md) | 2026-09-19 | 커밋 규칙과 커밋 정리 |
| [06](06-github-readme.md) | 2026-09-19 | GitHub 저장소와 README |
| [07](07-icon-variation.md) | 2026-09-19 | 아이콘 변형 시안 |
| [08](08-competitor-research.md) | 2026-09-19 | 비슷한 서비스 조사와 마이데이터 |
| [09](09-excel-import.md) | 2026-09-19 | 이용 내역 엑셀 가져오기 |
| [10](10-app-db.md) | 2026-09-21 | 앱 DB 운영 방식 |
| [11](11-hifi-screens-colors.md) | 2026-09-21 | 고해상도 화면 시안과 색 |
| [12](12-screens-to-repo.md) | 2026-09-21 | 화면 시안 저장소 반영 |
| [13](13-screens-review.md) | 2026-09-23 | 화면 시안 평가와 개편 |
| [14](14-login-decision.md) | 2026-09-28 | 로그인 방식 확정 |
| [15](15-card-drafts.md) | 2026-09-28 | 카드 20장 초안 |
| [16](16-catalog-schema-v2.md) | 2026-09-28 | 카탈로그 틀 2판 방식과 1절 |
| [17](17-agent-setup.md) | 2026-09-28 | AI 작업 설정과 작업 단위 구조 |
| [18](18-catalog-commit-start-icon.md) | 2026-09-28 | 카드 초안 커밋과 시작 화면 아이콘 |
| [19](19-work-history.md) | 2026-09-28 | 작업 기록 폴더 |
| [20](20-catalog-schema-v2-sections.md) | 2026-09-28 | 카탈로그 틀 2판 2절부터 4절과 전체 검토 |
| [21](21-notification-reading.md) | 2026-09-28 | 결제 알림 읽기 |
| [22](22-catalog-schema-v2-plan.md) | 2026-09-29 | 카탈로그 틀 2판 구현 계획 |
| [23](23-databricks-reasons.md) | 2026-09-29 | Databricks를 고른 이유와 설정 방침 |
| [24](24-databricks-approach.md) | 2026-09-29 | Databricks 파이프라인 방식 |
| [25](25-catalog-schema-v2-build.md) | 2026-09-29 | 카탈로그 틀 2판 구현 |
| [26](26-calc-engine-design.md) | 2026-09-29 | 계산 엔진 의도, 설계, 계획 |
| [27](27-calc-engine-build.md) | 2026-09-29 | 계산 엔진 구현 |
| [28](28-mockup-review-fix.md) | 2026-09-30 | 화면 시안 검토와 고침 |
| [29](29-databricks-pipeline-prep.md) | 2026-09-30 | Databricks 파이프라인 가입 전 준비 |
| [30](30-korean-only-hook.md) | 2026-09-30 | 답에 영어가 섞이면 막는 훅 |
| [31](31-cost-guard-overnight-failures.md) | 2026-10-01 | 개발용 비용 차단 작업의 밤사이 실패 |
| [32](32-first-prod-deploy-and-collect.md) | 2026-10-01 | 첫 운영 배포와 첫 수집 |
| [33](33-change-detection-and-model-choice.md) | 2026-10-01 | 수집, 변경 감지 파일과 추출 모델 다시 고르기 |
| [34](34-databricks-handover-and-guard-retest.md) | 2026-10-01 | Databricks 일 이어 받기와 비용 차단 재시험 |
| [35](35-gold-seed.md) | 2026-10-01 | 골드 카탈로그 첫 적재 |
| [36](36-manual-approval-merchants.md) | 2026-10-01 | 손 승인 작업과 가맹점 두 개 추가 |
| [37](37-slice4-review-fixes.md) | 2026-10-02 | 슬라이스 4 위험 검토 지적 고치기 |
| [38](38-ranked-cancel-month-and-unknown-answers.md) | 2026-10-02 | 순위 영역 취소 달 칸과 슬라이스 5 모르는 값 묻기 |
| [39](39-excel-import.md) | 2026-10-02 | 슬라이스 6 이용 내역 엑셀 가져오기 |
| [40](40-social-login.md) | 2026-10-02 | 슬라이스 7 카카오와 Google 로그인 |
| [41](41-deploy-prep.md) | 2026-10-02 | E36 한계와 슬라이스 8 배포 준비 |
| [42](42-offline-and-outage.md) | 2026-10-02 | 슬라이스 9 오프라인 기록과 서버 장애 |
| [43](43-extraction-scoring-and-model.md) | 2026-10-02 | 추출 채점, 프롬프트 다듬기, 운영 모델 고르기 |
| [44](44-criteria-and-ci.md) | 2026-10-02 | 작업 005 성공 기준 확인과 서버 테스트 CI |
| [45](45-phone-check-and-on-device.md) | 2026-10-02 | 슬라이스 7 실제 폰 확인과 폰 안 구조로 바꾸기 |
| [46](46-ranked-cancel-gold.md) | 2026-10-02 | 순위 영역 취소 달을 골드에 넣기 |
| [47](47-on-device-design-and-plan.md) | 2026-10-02 | 작업 006 설계 2~8절과 계획 |
| [48](48-on-device-step1.md) | 2026-10-02 | 작업 006 단계 1 준비 |
| [49](49-on-device-step2.md) | 2026-10-02 | 작업 006 단계 2 엔진 옮기기 |
| [50](50-lineage-and-export-check.md) | 2026-10-02 | 운영 추출 첫 실행, 과제 21 마무리, 과제 22 계보 |
| [51](51-review-app.md) | 2026-10-02 | 과제 20 검수 앱 |
| [50](50-on-device-step3.md) | 2026-10-02 | 작업 006 단계 3 카탈로그 읽기와 받기 |
| [52](52-success-criteria-and-wrap-up.md) | 2026-10-02 | 작업 003 성공 기준 확인과 마무리 |
| [53](53-lineage-one-job.md) | 2026-10-02 | Unity Catalog 계보를 작업 하나로 살려 보기 |
| [51](51-on-device-step4-store.md) | 2026-10-02 | 작업 006 단계 4의 1~6 폰 안 저장소 |
| [54](54-on-device-step4-screens.md) | 2026-10-02 | 작업 006 단계 4의 7~9 화면을 폰 저장소로 바꿔 끼우기 |
| [55](55-on-device-step5-imports.md) | 2026-10-03 | 작업 006 단계 5 엑셀 가져오기를 폰으로 옮기기 |
| [56](56-on-device-step6-backup.md) | 2026-10-03 | 작업 006 단계 6 기록 내보내기와 가져오기, 자동 백업 끄기 |
| [57](57-dashboard-spark.md) | 2026-10-03 | 운영 대시보드와 Spark 계산으로 계보 잇기 |
| [58](58-on-device-step7-cleanup.md) | 2026-10-03 | 작업 006 단계 7 서버, Python 엔진, 로그인 지우기와 문서 맞추기 |
| [59](59-camera-recognition-dropped.md) | 2026-10-03 | 카메라 카드 인식을 시작했다가 빼기 |
| [60](60-on-device-step8-real-phone.md) | 2026-10-04 | 작업 006 단계 8 실제 폰 |
| [61](61-catalog-change-history.md) | 2026-10-04 | 작업 010 카탈로그 변경 이력 적재 |
| [62](62-catalog-index-step4.md) | 2026-10-04 | 작업 008 4단계 상품공시실 색인 |
| [63](63-handoff-for-other-pc-and-ai.md) | 2026-10-04 | 작업 011 단계 1~3 올리기와 다른 PC, 다른 AI 이어 받기 안내 |
