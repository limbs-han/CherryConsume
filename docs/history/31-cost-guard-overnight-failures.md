# 31 개발용 비용 차단 작업의 밤사이 실패

- 날짜: 2026-10-01
- 결과물: [비용 차단 작업 정의](../../pipeline/resources/cost_guard.yml), [번들 설정](../../pipeline/databricks.yml), [비용 차단 코드](../../pipeline/src/cost_guard.py), [설계 4절 8번](../work/003-databricks-pipeline/design.md), [차단을 사람이 풀 때](../databricks.md)
- 커밋: `3b6125b` fix: 개발용 비용 차단 작업의 예약이 켜진 채 배포되던 문제 수정
- 커밋: `ddc287c` docs: 차단을 푼 뒤 비용 차단 예약이 켜졌는지 보는 순서 추가
- 커밋: `6a6462b` fix: 비용 차단이 Genie 무료 사용량을 가격 없는 사용량으로 세던 문제 수정

## 요청

> 어제 밤 동안 cherry_cost_guard 가 실패했다는 메일이 한 4번 왔어 Error in run 753063293880295 of '[dev jihan0469] cherry_cost_guard'
> [limbs-han/CherryConsume] Run failed: export - master (e199640) 이것도 왔고

## 과정

### 첫 결과
개발 모드는 예약을 멈춘 채 배포하지만, 작업 정의에 `pause_status: UNPAUSED`를 직접 적으면 그 작업은 켜 둔다. 그래서 개발용 차단 작업이 6시간마다 돌았다. 기본 정의에서 그 줄을 빼고 운영 대상에서만 켰다. export 실패는 운영 볼륨이 아직 없어서라 예상한 것이라고 설명했다.

### 수정 요청 1
> 배포했고 Paused 확인했어
> 가격표 SQL 887 나왔어
>
> export 메일은 안 글게

반영: 위험 검토를 통과해 커밋했다. 검토에서 나온 대로 차단을 푼 뒤 예약이 켜졌는지 보는 순서를 안내서에 더했다. 개발용 차단 작업을 다시 돌리게 했는데 가격 없는 사용량 11건으로 또 실패했다. 짝 없는 사용량을 상품별로 보는 조회를 드렸다.

### 수정 요청 2
> sku_name	cloud	usage_unit	rows	first_use	price_rows	price_from	price_units	currencies	no_effective
> GENIE_FREE_USAGE	AWS	DBU	11	2026-09-30T06:00:00.000+00:00	null	-	null	null	null

반영: 공식 문서 "Monitor and understand your Genie cost"가 이 상품은 무료이고 가격 표에 행이 없다고 쓴 것을 확인했다. 가격 없는 사용량을 셀 때만 이 상품을 빼도록 고쳤다. 위험 검토 지적대로 합계에서는 빼지 않고, 상품 이름이 빈 기록은 계속 센다.

## 최종 결과
개발용 차단 작업의 예약은 멈춰 있고, 수동 실행은 가격 없는 사용량 0건, 멈춤 False로 성공했다. 쓴 금액은 13.94달러, 체험 한도는 400달러다. 푸시는 첫 운영 배포가 함께 돌기 때문에 사용자가 따로 정한다. 다른 세션의 `refresh.yml`에도 같은 `pause_status: UNPAUSED`가 있어 주 개발 세션에 전하기로 했다.
