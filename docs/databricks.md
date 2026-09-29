# Databricks를 고른 이유와 설정 안내

작성일 2026-09-29. 설계 문서 2절의 "데이터 플랫폼" 결정을 자세히 적는다.

## 먼저 솔직하게

이 프로젝트 규모에서는 Databricks가 꼭 있어야 하는 것은 아니다. 카드는 수천 장, 사용자는 처음에 수백 명이다. 카드 수집은 Python 스크립트와 예약 실행만으로, 로그 분석은 DuckDB와 Parquet 파일만으로도 된다.

Databricks를 고른 가장 큰 이유는 개발자가 Databricks를 배워 보고 싶었기 때문이다. 2026-09-19 첫 기획 요청에서 "카드 정보 수집과 보관은 Databricks나 Snowflake를 써 보고 싶다"고 정했다. 그 위에서, 이 프로젝트의 흐름과 잘 맞는 점이 있어 비교한 대안 중 Databricks를 골랐다. 아래는 그 근거다.

## 용어

| 용어 | 한 줄 설명 |
|---|---|
| 데이터 레이크 | 파일을 원래 모양 그대로 쌓아 두는 저장소. 싸고 자유롭지만 정리와 관리를 직접 해야 한다 |
| 데이터 웨어하우스 | 정리된 표로 넣어 두고 SQL로 분석하는 곳. 편하지만 파일을 그대로 두기 어렵다 |
| 레이크하우스 | 파일 저장소 위에서 웨어하우스처럼 표로 다루는 방식. Databricks가 대표적이다 |

## 이 프로젝트에서 Databricks가 하는 일

1. **카드 상품 수집 파이프라인.** 하위 프로젝트 3이다. 카드사 페이지를 모으고, 정제하고, LLM으로 혜택을 뽑고, 카탈로그 검증기로 검사한 뒤 카탈로그를 발행한다. 카드사마다 14일이나 30일 주기로 돈다.
2. **사용자 로그 분석.** 설계 4.1절이다. 서버가 매일 밤 가명처리한 로그 파일을 내보내면 Databricks가 새 파일만 읽어 쌓는다.
3. **나중에 앱 DB 합치기.** 설계 4.2절이다. 분석 데이터가 쌓이면 앱 DB를 Databricks 안의 Postgres인 Lakebase로 옮겨, 밤마다 파일을 내보내는 코드를 없앤다.

## 이 프로젝트에 맞는 점

| 기능 | 한 줄 설명 | 이 프로젝트에서 쓰는 곳 |
|---|---|---|
| Lakebase | Databricks 안의 관리형 Postgres. 안 쓸 때는 0으로 줄고, Delta 테이블과 양쪽으로 동기화된다 | 앱 DB를 옮기면 로그 내보내기 코드와 가명처리 위치를 한 곳으로 줄인다. 2026년에 정식 출시됐다 |
| Auto Loader | 저장소에 새로 들어온 파일만 골라 읽는 적재 기능 | 하루치 로그 파일을 중복 없이 쌓는다 |
| 작업 예약 | Python 노트북과 스크립트를 주기적으로 돌리고 실패를 알린다 | 카드사별 수집 주기, 밤마다의 로그 적재 |
| Python 중심 | 노트북과 작업을 Python으로 그대로 쓴다 | 개발자가 가장 익숙한 언어다. 카탈로그 검증기 `cherry_core`를 파이프라인에서 그대로 불러 쓴다 |
| Unity Catalog | 테이블마다 접근 권한을 두고, 데이터가 어디서 왔는지 계보를 남긴다 | 가명처리한 사용자 로그에 누가 접근했는지 남긴다. 개인정보처리방침에 적을 근거가 된다 |
| Delta Lake | 열린 표준 파일 형식 | Databricks를 떠나도 DuckDB나 Spark로 그대로 읽는다. 한 회사에 묶이는 위험을 줄인다 |
| MLflow | 실험과 모델 결과를 기록한다 | LLM 추출 결과의 정확도를 버전마다 비교한다 |
| Free Edition | 무료 학습용 작업 공간 | 개발 단계에서 비용 없이 배운다. 상업 이용은 금지다 |

## 대안과 비교

| 대안 | 한 줄 설명 | 이 프로젝트 기준 장점 | 이 프로젝트 기준 단점 |
|---|---|---|---|
| Snowflake | SQL 중심 클라우드 데이터 웨어하우스 | SQL이 강하고 운영이 쉽다. 2026-02-24 Snowflake Postgres가 정식 출시돼 앱 DB와 분석을 한 곳에 둘 길도 생겼다 | 영구 무료 구간이 없고 체험 계정뿐이다. Python 수집과 LLM 추출은 Snowpark로 할 수 있지만 Python 노트북 중심인 Databricks보다 손이 더 간다 |
| Google BigQuery | 서버를 관리하지 않는 SQL 분석 서비스 | 무료 구간이 넉넉하다. 매달 저장 10GB, 조회 1TB까지 무료라 이 규모에서는 가장 쌀 수 있다 | 신용카드 없이 쓰는 샌드박스는 테이블이 60일 뒤 사라지고 일부 기능이 없다. Postgres 동기화와 수집 예약은 다른 Google 서비스를 따로 붙여야 한다 |
| AWS S3와 Glue, Athena, Iceberg | 파일 저장소와 조회 도구를 직접 조합하는 레이크하우스 | 가장 싸고 자유롭다 | 조합과 권한 설정을 직접 해야 해서 1인 개발에 손이 많이 간다 |
| DuckDB와 Parquet, MotherDuck | 내 컴퓨터나 작은 서버에서 도는 분석 DB | 이 규모에서는 가장 단순하고 거의 공짜다 | 예약 실행, 권한, 계보, 새 파일 적재를 직접 만들어야 한다. 배우려던 Databricks 경험도 남지 않는다 |

**정리.** 규모와 비용만 보면 DuckDB나 BigQuery가 더 단순하고 싸다. 그런데도 Databricks를 고른 이유는 세 가지다.
1. 배우려는 목적이 처음부터 있었다.
2. 카드 수집, LLM 추출, 검증, 로그 적재를 Python 하나로 이어 예약 실행할 수 있다.
3. 나중에 Lakebase로 앱 DB와 분석을 한 곳에 합칠 길이 있다.

Snowflake도 Postgres가 생겨 3번은 비슷해졌다. 하지만 무료로 배울 수 있는 구간과 Python 중심의 흐름에서 Databricks가 더 맞았다.

## 비용과 제약

- **Free Edition.** 상업 이용이 금지다. 서버리스 계산만 쓸 수 있고, SQL 웨어하우스는 1개, 동시에 도는 작업은 5개까지다. 그래서 개발 단계에서만 쓴다.
- **출시 뒤.** 종량제 계정으로 옮기거나, 같은 Python 코드를 다른 실행 환경에서 돌린다. 설계 3절. 카탈로그를 2주나 한 달마다 갱신하는 정도면 비용이 작다고 보지만 아직 실측 전이다.
- **Lakebase로 옮기기 전 확인할 것.** 요금 구조, 서울 리전 제공 여부, 0으로 줄었을 때의 실제 과금이다. 설계 4.2절.

## 설정은 사용자가 직접 한다

Databricks가 필요해지는 때는 하위 프로젝트 3이다. 그때 Claude는 설정을 대신하지 않고 단계마다 안내한다.
- 계정 만들기, 로그인, 결제 수단, 토큰 발급처럼 계정과 비밀값이 걸린 일은 사용자가 한다.
- 단계마다 무엇을 누르고, 무엇이 보이면 성공인지 알려 준다. 끝나면 사용자가 붙여 준 결과로 Claude가 확인한다.
- 토큰과 비밀번호는 사용자 PC의 Databricks CLI 설정이나 환경변수에만 두고 저장소에 넣지 않는다.

안내할 순서의 미리 보기다. 실제로 할 때는 그때의 공식 문서로 다시 확인하고 고친다.
1. Free Edition에 가입한다. 출시 전에 종량제 계정으로 옮길지는 그때 정한다.
2. 작업 공간에서 Unity Catalog의 카탈로그와 스키마 이름을 정한다. 예: `cherry.catalog`, `cherry.logs`.
3. 로그 파일을 둘 곳을 정한다. Free Edition이면 작업 공간의 볼륨, 종량제면 오브젝트 스토리지를 외부 위치로 연결한다.
4. 자기 PC에 Databricks CLI를 설치하고 로그인한다. 성공하면 `databricks current-user me`가 자기 계정을 보여 준다.
5. 이 저장소를 작업 공간의 Git 폴더로 연결한다.
6. 수집 작업과 로그 적재 작업을 예약한다.

## 출처

- [Databricks Free Edition limitations](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)
- [Lakebase release notes](https://docs.databricks.com/aws/en/release-notes/lakebase/)
- [Azure Databricks Lakebase is Generally Available](https://www.databricks.com/blog/azure-databricks-lakebase-generally-available)
- [Snowflake Postgres General availability, 2026-02-24](https://docs.snowflake.com/en/en/release-notes/2026/other/2026-02-24-snowflake-postgres-ga)
- [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox)
