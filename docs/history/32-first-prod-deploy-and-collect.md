# 32 첫 운영 배포와 첫 수집

- 날짜: 2026-10-01
- 결과물: [수집기](../../backend/cherry_core/pipeline/collect.py), [수집 워크플로](../../.github/workflows/collect.yml), [PC에서 받는 카드사](../databricks.md), [설계 4절 2번](../work/003-databricks-pipeline/design.md), [과제 14](../work/003-databricks-pipeline/plan.md)
- 커밋: `e67431c` docs: CLI 배포에 맞게 서비스 주체 비밀값 범위를 모든 API로 안내
- 커밋: `772e909` fix: 첫 수집에서 목록 파일 폴더가 없어 올리기가 실패하던 문제 수정
- 커밋: `7547114` feat: 수집기에 카드사 빼기 옵션과 robots.txt 확인 실패 처리 추가
- 커밋: `1b7c4f7` deploy: 수집 워크플로에서 GitHub 서버를 막는 신한을 빼고 빈 목록은 올리지 않음
- 커밋: `9c30aeb` docs: GitHub 서버를 막는 카드사를 PC에서 받는 순서와 첫 수집 결과 기록
- 커밋: `cd8ada6` docs: 첫 운영 수집과 신한 PC 올리기 결과, 원문 볼륨 권한 기록

## 요청

> 푸시해줘

## 과정

### 첫 결과
비용 차단 수정 커밋을 푸시해 `deploy` 워크플로가 첫 운영 배포를 돌게 했다.

### 수정 요청 1
> 커밋 제목은 맞는데 빨간 X 야

실행 기록도 붙였다. 서비스 주체 인증이 실패했다.

반영: Databricks CLI는 토큰을 받을 때 늘 모든 API 범위를 달라고 하고 환경변수로 바꿀 수 없다. 범위 9개만 연 비밀값으로는 토큰을 받지 못한다. 사용자가 모든 API 비밀값을 새로 받아 GitHub 비밀값을 바꾸게 하고, 안내서의 범위 설명을 고쳤다. 실패 기록에 계정 번호가 찍혀 그 실행을 지우게 했다.

### 수정 요청 2
> 배포 성공했어 초록 체크 떴어

반영: 운영 차단 작업 예약 확인과 `collect` 수동 실행을 안내했다.

### 수정 요청 3
> 30으로 run workflow 눌렀어
> 4분 39초 끝에 실패했네

실행 기록도 붙였다. 목록 폴더가 없어 올리기가 멈췄다.

반영: 목록 파일을 올리기 전에 폴더를 만들게 고쳤다. 원문 받기 단계의 기록을 받아 보니 저장 22, 건너뜀 14, 실패 10이었다. 신한 열 주소가 모두 연결 끊김이었고 PC에서는 모두 받았다. 건너뜀은 PC보다 5곳 많았다. GitHub 수집에서 신한을 빼는 표시를 두고, robots.txt를 확인하지 못하면 실패로 세는 방법을 추천했다.

### 수정 요청 4
> 추천대로 진행해줘

반영: 수집기에 `--exclude`를 더하고 robots.txt 401, 403, 429를 실패로 세게 했다. 건너뛴 주소와 뺀 개수를 기록에 찍는다. 위험 검토에서 나온 6건을 반영했다. 받은 것이 없는 목록 파일은 올리지 않고, PC 올리기에 제자리 확인을 넣었다.

### 수정 요청 5
> 푸시해줘

반영: 푸시했다. 운영 배포가 새 wheel로 다시 돌았다.

### 수정 요청 6
> deploy 초록 체크 떴어
>
> collect 원문받기

실행 기록도 붙였다. 저장 27, 건너뜀 9, 실패 0, 뺌 10이었다.

반영: 건너뛴 9곳이 PC와 같아 현대와 KB는 GitHub 수집에 두었다. 늘었던 5곳은 일시적이었던 것으로 적었다.

### 수정 요청 7
> 초록 체크 떴고 올린 파일 개수 붙여 줄게
> 올린 파일 28개

반영: 원문 27개와 목록 파일 하나다. 신한 PC 받기를 안내했다.

### 수정 요청 8
> 설명해줘 신한을 PC에서 받아올리는 일

반영: 왜 하는지와 일곱 단계를 명령마다 성공 기준과 함께 풀어 썼다.

### 수정 요청 9
> 저장 10, robots.txt로 건너뜀 0, 실패 0, 뺌 0 나왔어
>
> 근데 4번에서 PS C:\Users\SSAFY\Desktop\pjt\cherryConsume> Get-ChildItem $raw -Directory | Where-Object Name -ne manifests | ForEach-Object { databricks fs cp -r $_.FullName "dbfs:/Volumes/cherry/bronze/raw/$($_.Name)" --overwrite }
> Error: databricks-api error: User does not have USE SCHEMA privilege on SCHEMA 'cherry.bronze'.

반영: 운영 스키마는 서비스 주체가 만들어 사람 계정에 권한이 없다. `cherry-admins`에 `cherry.bronze` USE SCHEMA와 원문 볼륨 READ VOLUME, WRITE VOLUME을 주는 SQL을 안내하고 안내서에 처음 한 번 할 일로 적었다.

### 수정 요청 10
> 권한주고 4번 했는데 또 에러야

실행 기록도 붙였다. PC가 Databricks 주소를 찾지 못한 오류였다.

반영: 일시적인 네트워크 오류라 같은 명령을 다시 돌리게 했다.

### 수정 요청 11
> 다시 했더니 됐어 7단계까지 정상적으로 마무리했어

## 최종 결과
첫 운영 배포와 첫 운영 수집이 끝났다. GitHub은 신한을 뺀 카드사를 받고, 신한은 사용자가 매달 2일과 16일에 PC에서 받아 올린다. 과제 14가 끝났다. 남은 것은 운영 차단 작업 예약 화면 확인, 예전 비밀값 지우기, 새 비밀값이 끝나는 날짜 기록이다.
