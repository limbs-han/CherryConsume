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

1. **카드 상품 수집 파이프라인.** 하위 프로젝트 3이고 작업 003이다. 원문 적재부터 카탈로그까지 모든 층을 Databricks 안에 둔다. 원문을 브론즈에 쌓고, 해석하고, 바뀐 문서만 LLM으로 추출하고, 카탈로그 검증기로 검사한다. 처음에는 모든 초안을 사람이 승인해야 골드로 간다. 작업 001에서 확인한 카드 20장을 정답 예시로 삼아 추출 정확도를 잰다. 카드사마다 14일이나 30일 주기로 돈다. 방식은 `docs/work/003-databricks-pipeline/`.
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
| MLflow | 실험과 모델 결과를 기록하고, 정답 예시로 채점하고, 사람의 검수 의견을 모은다 | LLM 추출 결과의 필드별 정확도를 프롬프트와 모델을 바꿀 때마다 비교하고, 검수 기록을 남긴다 |
| 문서 AI 함수 | `ai_parse_document`는 PDF와 이미지를 구조가 살아 있는 글로 바꾸고, `ai_extract`는 정한 형식대로 값을 뽑는다 | 상품설명서 PDF의 혜택 표를 읽고 카탈로그 2판 형식의 초안을 만든다. 쓴 만큼 요금이 나온다 |
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

## 결제는 언제 하나

2026-09-29 사용자가 필요하면 바로 결제하겠다고 했다. 확인해 보니 개발 단계에는 결제가 필요 없다. 결제해도 풀리지 않는 제약이 있기 때문이다.

같은 날 작업 003은 처음부터 유료 계정으로 시작하기로 정했다. 무료판은 유료로 바꿀 수 없어 LLM 추출 단계에서 계정을 새로 만들고 옮겨야 하기 때문이다. 비용 상한과 체험 기간 처리는 `docs/work/003-databricks-pipeline/design.md` 4절 8번과 9번이다.

| 항목 | 무료판 | 유료 서버리스 | 이 프로젝트에 주는 영향 |
|---|---|---|---|
| 상업 이용 | 금지 | 가능 | 출시하려면 유료가 필요하다. 개발 중에는 무료판으로 된다 |
| Databricks 안에서 바깥 사이트 접속 | 신뢰 도메인 몇 곳만 | 기본으로 열려 있다 | 봇 접근을 막지 않는 카드사는 Databricks 안에서 바로 받을 수 있다 |
| 브라우저가 필요한 사이트 | 안 된다 | 여전히 어렵다 | 롯데, 하나, 우리, NH는 결제해도 바깥 수집기가 필요하다 |
| robots.txt로 막은 사이트 | 수동 | 수동 | 삼성, BC, IBK는 결제와 상관없이 사람이 받아 올린다 |
| LLM 호출 | 일부 모델만, 한도가 있다 | 제한이 풀린다 | LLM 추출을 Databricks 안에서 돌릴 때만 중요하다 |
| 사용량 한도 | 넘으면 그날 계산이 멈춘다 | 쓴 만큼 낸다 | 이 규모에서는 무료판 한도를 넘을 일이 드물다 |

다음 중 하나가 오면 결제한다.
1. 출시 준비. 실제 사용자 데이터가 들어오기 전, 하위 프로젝트 5 전이다.
2. LLM 추출을 Databricks 안에서 돌리기로 할 때.
3. 무료판 한도에 걸릴 때.
4. 봇 접근을 막지 않는 카드사의 원문을 Databricks 안에서 직접 받고 싶을 때.

결제할 때는 익스프레스 설정으로 시작한다. 클라우드 계정 없이 이메일로 서버리스 작업 공간을 만들고 14일짜리 $400 체험 크레딧을 받는다. 크레딧이 14일 뒤 끝나므로 실제로 쓸 준비가 됐을 때 시작한다. 결제 수단 등록과 예산 알림은 사용자가 직접 설정한다.

비용은 서버리스 작업 기준 미국 지역 약 $0.70/DBU다. DBU는 Databricks가 계산량을 세는 단위다. 카드 20장을 2주마다 확인하고 로그를 매일 적재하는 정도면 한 달 몇 달러에서 몇십 달러로 보지만 실측 전이고, 서울 지역 요금은 확인하지 못했다.

## 설정은 사용자가 직접 한다

Databricks가 필요해지는 때는 하위 프로젝트 3이다. 그때 Claude는 설정을 대신하지 않고 단계마다 안내한다.
- 계정 만들기, 로그인, 결제 수단, 토큰 발급처럼 계정과 비밀값이 걸린 일은 사용자가 한다.
- 단계마다 무엇을 누르고, 무엇이 보이면 성공인지 알려 준다. 끝나면 사용자가 붙여 준 결과로 Claude가 확인한다.
- 토큰과 비밀번호는 사용자 PC의 Databricks CLI 설정이나 환경변수에만 두고 저장소에 넣지 않는다.

안내할 순서의 미리 보기다. 실제로 할 때는 그때의 공식 문서로 다시 확인하고 고친다.
1. 익스프레스 설정으로 체험 계정을 만든다. 체험 중에는 결제 정보를 넣지 않는다. 작업 003 설계 4절 9번.
2. 작업 공간에서 Unity Catalog의 카탈로그와 스키마 이름을 정한다. 예: `cherry.catalog`, `cherry.logs`.
3. 로그 파일은 작업 공간의 볼륨에 둔다.
4. 자기 PC에 Databricks CLI를 설치하고 로그인한다. 성공하면 `databricks current-user me`가 자기 계정을 보여 준다.
5. 이 저장소를 작업 공간의 Git 폴더로 연결한다.
6. 수집 작업과 로그 적재 작업을 예약한다.

## 출처

- [Databricks Free Edition limitations](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)
- [Lakebase release notes](https://docs.databricks.com/aws/en/release-notes/lakebase/)
- [Azure Databricks Lakebase is Generally Available](https://www.databricks.com/blog/azure-databricks-lakebase-generally-available)
- [Snowflake Postgres General availability, 2026-02-24](https://docs.snowflake.com/en/en/release-notes/2026/other/2026-02-24-snowflake-postgres-ga)
- [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox)
- [Databricks express setup](https://docs.databricks.com/aws/en/getting-started/express-setup)
- [Databricks free trial](https://docs.databricks.com/aws/en/getting-started/free-trial)
- [Databricks pricing guide 2026, Flexera](https://www.flexera.com/blog/finops/databricks-pricing-guide/)
