# 48 작업 006 단계 1 준비

- 날짜: 2026-10-02
- 결과물: [앱의 SQLite 시험](../../app/test/sqlite_check.dart), [카탈로그 JSON 만들기](../../backend/cherry_core/catalog/app_json.py), [앱이 담는 카탈로그](../../app/assets/catalog.json), [시험 파일 만들기](../../backend/tools/make_import_fixtures.py), [테스트 워크플로](../../.github/workflows/test.yml), [작업 006 계획](../work/006-on-device/plan.md)
- 커밋: `1856514` build: 앱에 SQLite를 묶는 sqlite3와 판 확인 시험
- 커밋: `ac9add1` feat: 앱이 담을 카탈로그 JSON 만들기 명령
- 커밋: `ab5cd3a` test: 엑셀 가져오기 시험 파일을 만들어 커밋
- 커밋: `f58eef5` build: CI에 앱 시험 잡과 검수 승인 커밋의 JSON 단계
- 커밋: `a9e2c2f` docs: 작업 006 단계 1 진행
- 커밋: `2628ae6` docs: 작업 006 단계 1 CI 확인

## 요청

> 시작해

## 과정

### 첫 결과
`sqlite3`를 앱에 넣었다. 계획은 3.7이었지만 3.6부터는 Flutter 3.44가 묶은 `meta` 1.18과 맞지 않아 3.5.2로 했다. PC 시험과 에뮬레이터 Android 16 모두 SQLite 3.53.4이고 서버가 쓰던 세 문법이 된다.

카탈로그 JSON 만들기 명령을 더했다. 카드사 기본값과 패치를 합친 개정, 2020~2036년 공휴일, 형식 번호를 `app/assets/catalog.json` 한 파일로 쓴다. 엔진이 거절하던 오류가 있으면 만들지 않는다. 공휴일 범위를 만든 해로 정하면 해가 바뀔 때 커밋된 파일과 달라져 끝 해를 코드에 두었다. 개정 지문 함수는 서버와 함께 쓴다.

Python 시험이 그 자리에서 만들던 csv, cp949 csv, xlsx, 압축 폭탄을 스크립트로 만들어 커밋했다. 지금 읽기 코드가 그 파일로도 같은 결과를 낸다. CI에 Flutter 분석기와 앱 시험 잡을 더하고 `export.yml`에 JSON 다시 만들기를 넣었다. 카탈로그 사본을 고쳐 보는 명령은 권한에서 막혀 다시 시도하지 않았다.

### 수정 요청 1
> 커밋하고 푸시해

반영: 커밋 다섯 개로 푸시했다. GitHub에서 서버 시험 잡과 앱 시험 잡이 모두 통과했다. Databricks 세션이 `export.yml` 변경을 검토했다.

### 수정 요청 2
> 여기까지 커밋하고 푸시해줘

반영: CI 결과를 계획에 적어 푸시했다.

## 최종 결과
단계 1의 1~4번을 마쳤다. 5번은 다음 검수 승인의 봇 커밋에 `catalog.json`이 함께 들어가는지 Databricks 세션이 확인해 준다. 다음은 단계 2 엔진 옮기기다.
