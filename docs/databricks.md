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
| 작업 공간 | Databricks에서 표, 파일, 작업, 앱을 두고 쓰는 곳. 주소가 하나씩 있다 |
| 계정 콘솔 | 작업 공간 위에서 계정 전체의 사용자, 청구, 예산을 관리하는 화면 |
| 번들 | 작업, 표, 앱을 파일로 적어 두고 명령 한 번에 작업 공간으로 올리는 방식. 개발용과 운영용을 나눠 올린다 |
| DBU | Databricks가 계산량을 세는 단위. 요금은 쓴 DBU에 단가를 곱한다 |

## 이 프로젝트에서 Databricks가 하는 일

1. **카드 상품 수집 파이프라인.** 하위 프로젝트 3이고 작업 003이다. 2026-10-02 끝났다. GitHub Actions가 매달 1일과 15일 카드사 원문을 받아 볼륨에 올리면 `cherry_refresh`가 적재, 글 뽑기, 바뀐 것 고르기를 하고 바뀐 카드만 `gpt-oss-120b`로 추출해 검사한다. 초안은 검수 대기에 오르고, 사람이 검수 앱 `cherry-review-prod`나 손 승인 `cherry_approve`로 승인해야 골드로 간다. 골드가 카탈로그의 원본이고 `export` 워크플로가 저장소에 봇 커밋한다. 정답 예시 채점 `cherry_tune`과 `cherry_evaluate`가 정확도를 MLflow에 남기고, 비용 차단 `cherry_cost_guard`가 6시간마다 쓴 금액을 본다. 방식은 `docs/work/003-databricks-pipeline/`.
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
| 브라우저가 필요한 사이트 | 안 된다 | 여전히 어렵다 | 하나, 우리, 현대, KB는 결제해도 바깥 수집기가 필요하다. 2026-09-30 수집 시험으로 고쳤다 |
| robots.txt로 막은 사이트 | 수동 | 수동 | 삼성, BC, IBK, 롯데는 결제와 상관없이 사람이 받아 올린다. 롯데는 robots.txt를 확인할 수 없어 더했다. 2026-10-04 작업 008부터 삼성, IBK, 롯데, 카카오뱅크는 robots.txt를 묻지 않고 집 PC 러너가 받는다 |
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

안내할 순서다. 2026-09-30 아래 출처의 공식 문서로 확인했다. 굵은 글씨는 화면에 보이는 영어 이름 그대로다. 가입은 작업 003 과제 12를 시작하는 날 한다. 체험 크레딧 14일이 가입한 날부터 흐르기 때문이다.

Claude는 계정과 비밀값을 다루는 명령을 돌리지 못하게 `.claude/settings.json`에서 막아 두었다. 로그인, 토큰, 서비스 주체 비밀값, 계정 관리, GitHub 비밀값 명령이다.

2026-10-03부터 설정이 끝난 뒤의 Databricks 명령은 Claude가 돌린다. 번들 배포와 실행, SQL, 파일 올리기, 조회다. 사용자에게는 웹 화면에서만 할 수 있는 일만 부탁한다. 운영에 쓰거나 운영 작업을 돌리는 명령은 돌리기 전에 묻는다. 그래서 아래 절의 명령들은 사람이 직접 돌릴 때의 기록이기도 하다.

### 1. 체험 계정 만들기

익스프레스 설정은 AWS 같은 클라우드 계정 없이 이메일만으로 Databricks를 쓰게 해 주는 가입 방식이다.
- 누를 곳: Databricks 가입 페이지에서 이메일을 넣고 **Start trial with express setup**을 누른다. 계정 이름을 넣는다. 같은 메일 주소를 쓰는 사람을 자동으로 들이는 설정이 나오면 끈다. 지역은 처음 골라진 그대로 두고 **Continue**를 누른다. 작업 003 설계 4절 11번.
- 넣을 값: 사용자 메일, 계정 이름 `cherryconsume`. 결제 정보는 넣지 않는다. 작업 003 설계 4절 9번.
- 성공하면 보이는 것: 첫 작업 공간이 열리고 위쪽 막대에 **Manage trial** 버튼이 있다.
- Claude에게 붙여 줄 것: 가입한 날짜. 작업 공간 주소는 붙여 주지 않는다. 주소와 인증값은 저장소에 넣지 않기로 했다.
- 알아 둘 것: 개인 메일로 가입하면 한 시간에 50 DBU까지 쓰고 바깥 사이트 접속이 제한된다. 원문 수집은 GitHub Actions에서 하므로 괜찮다.

### 2. PC에 Databricks CLI 설치와 로그인

CLI는 Databricks를 명령으로 다루는 프로그램이다. 번들 배포와 확인을 이 PC에서 한다.
- 누를 곳: 명령 프롬프트에서 `winget install Databricks.DatabricksCLI`를 돌린다. 창을 닫고 새로 연 뒤 `databricks -v`를 돌린다. 그다음 `databricks auth login --host <작업 공간 주소>`를 돌린다. 브라우저가 열리면 로그인한다.
- 넣을 값: 작업 공간 주소는 작업 공간을 연 브라우저 주소창의 `https://`부터 `.cloud.databricks.com`까지다. 프로필 이름을 물으면 `DEFAULT`를 넣는다. 그래야 명령마다 프로필을 적지 않는다.
- 성공하면 보이는 것: `databricks -v`가 0.205.0 이상이다. `databricks current-user me`가 자기 메일이 든 결과를 보여 준다. 로그인 토큰은 Windows 자격 증명 관리자에 들어가고, `.databrickscfg` 파일에는 주소와 프로필 이름만 남는다.
- Claude에게 붙여 줄 것: `databricks -v`와 `databricks current-user me`의 출력.

### 3. 서비스 주체 만들기와 OAuth 비밀값 발급

서비스 주체는 사람 대신 GitHub Actions가 쓰는 Databricks 계정이다. 사람 계정 토큰을 GitHub에 두면 그 토큰이 새었을 때 사람 계정 전체가 열리므로 권한이 좁은 계정을 따로 둔다. OAuth 비밀값은 이 계정의 비밀번호에 해당한다.
- 누를 곳: 작업 공간 위쪽 막대에서 자기 이름을 누르고 **Settings**를 누른다. **Identity and access** 탭에서 **Service principals** 옆 **Manage**를 누른다. **Add service principal**, **Add new**를 누르고 이름을 넣은 뒤 **Add**를 누른다. 만든 서비스 주체를 눌러 권한을 확인한다. **Secrets** 탭에서 **Generate secret**을 누른다. 기간을 넣고 **Scopes**에서 모든 API를 고른 뒤 **Generate**를 누른다.
- 넣을 값: 이름 `cherry-github-actions`, 기간 365일. 기간은 최대 730일이다.
- 권한: **Workspace access**와 **Databricks SQL access**만 켠다. 새 서비스 주체는 users 그룹을 통해 이 둘을 기본으로 받는다. **Consumer access**, **Allow unrestricted cluster creation**, **Allow pool creation**은 끈다. 서버리스만 쓰므로 서버를 만드는 권한이 필요 없고, 비밀값이 새면 비용이 커질 수 있다. 관리자 그룹에는 넣지 않는다.
- 범위: 모든 API. 2026-10-01 바꿨다. 처음에는 `workspace`, `jobs`, `sql` 같은 범위 9개만 연 비밀값을 만들었는데, 첫 운영 배포가 인증에서 실패했다. Databricks CLI는 토큰을 받을 때 늘 모든 API 범위 `all-apis`를 달라고 하고 환경변수로 바꿀 수 없다. 공식 문서는 범위를 좁힌 비밀값의 토큰이 그 범위를 넘을 수 없다고 쓴다. 그래서 CLI로 배포하려면 모든 API 비밀값이어야 한다. 이 비밀값이 새도 할 수 있는 일은 아래 권한과 GRANT로 준 것까지다. 처음 9개 범위에도 작업 실행과 배포가 들어 있어 줄어드는 보호는 크지 않다.
- 성공하면 보이는 것: 비밀값과 Client ID가 보인다. 비밀값은 창을 닫으면 다시 볼 수 없으니 창을 연 채로 바로 4단계로 간다.
- Claude에게 붙여 줄 것: 서비스 주체 이름과 비밀값이 끝나는 날짜. Client ID와 비밀값은 붙여 주지 않는다. 끝나는 날은 진행 상황에 적어 두고 그 전에 새로 발급한다.

**운영 배포 전에 서비스 주체에 권한 주기.** 과제 13에서 더했다. 운영 작업은 이 서비스 주체의 권한으로 돈다. 권한이 없으면 운영 스키마를 만들지 못하고, 비용 차단 작업이 청구 기록을 읽지 못해 아무것도 멈추지 않는다.
- 누를 곳: **Settings**의 **Identity and access**에서 `cherry-github-actions`를 열고 **Application ID**를 복사한다. **SQL Editor**에서 **Serverless Starter Warehouse**를 고르고 아래 SQL의 `<Application ID>`를 바꿔 한 줄씩 실행한다. 이어서 **SQL Warehouses**에서 **Serverless Starter Warehouse**를 열고 **Permissions**에서 `cherry-github-actions`를 **Can manage**로 더한다.
  ```sql
  GRANT USE CATALOG, CREATE SCHEMA ON CATALOG cherry TO `<Application ID>`;
  GRANT USE CATALOG ON CATALOG system TO `<Application ID>`;
  GRANT USE SCHEMA, SELECT ON SCHEMA system.billing TO `<Application ID>`;
  ```
- 먼저 할 것: 둘째와 셋째 줄은 메타스토어 관리자만 실행할 수 있다. 메타스토어는 Unity Catalog 전체를 담는 가장 위의 저장소다. 2026-09-30 가입한 계정은 이 역할이 없어 `PERMISSION_DENIED: User does not have MANAGE on Catalog 'system'`이 났다. 계정 콘솔의 **Catalog**에서 메타스토어 이름을 누르고 **Metastore Admin** 아래 **Edit**를 눌러, 로그인한 계정이 든 그룹을 고르고 **Save**를 누른다. 그런 그룹이 없으면 계정 콘솔의 사용자 관리에서 그룹을 만들고 자기 계정을 넣는다. 이 그룹에는 다른 사람이나 서비스 주체를 넣지 않는다.
- 무엇을 주는지: 첫 줄은 `cherry` 카탈로그 안에 운영 스키마를 만드는 권한이다. 둘째와 셋째 줄은 청구 기록을 읽는 권한이다. 웨어하우스 권한은 비용이 한도를 넘었을 때 끄는 권한이다. 새로 만드는 웨어하우스와 앱에도 같은 권한을 줘야 차단 작업이 끌 수 있다.
- 성공하면 보이는 것: SQL 세 줄이 모두 성공으로 끝난다. **Catalog**에서 `cherry`의 **Permissions** 탭에 서비스 주체가 보인다.
- Claude에게 붙여 줄 것: SQL 세 줄의 성공 여부. 실패하면 오류 글. **Application ID**는 붙여 주지 않는다.

### 4. GitHub 저장소 비밀값 등록

GitHub 저장소 비밀값은 Actions가 실행될 때만 꺼내 쓰는 값이다. 실행 기록에는 가려서 찍힌다.
- 누를 곳: GitHub 저장소 화면에서 **Settings**를 누른다. 왼쪽 **Security** 아래 **Secrets and variables**의 **Actions**를 누르고 **Secrets** 탭에서 **New repository secret**을 누른다. **Name**과 **Secret**을 넣고 **Add secret**을 누른다. 네 번 한다.
- 넣을 값: `DATABRICKS_HOST`에 2단계의 작업 공간 주소, `DATABRICKS_CLIENT_ID`에 Client ID, `DATABRICKS_CLIENT_SECRET`에 비밀값, `ALERT_EMAIL`에 작업이 실패하면 알림을 받을 메일. `ALERT_EMAIL`은 과제 13에서 더했다. 메일 주소를 공개 저장소에 적지 않으려고 비밀값으로 둔다. 작업 공간 주소는 끝에 `/`를 붙이지 않는다. 실행 기록은 등록한 글자와 똑같을 때만 가려지기 때문이다.
- 성공하면 보이는 것: 비밀값 목록에 네 이름이 보인다. 값은 다시 볼 수 없다.
- Claude에게 붙여 줄 것: 네 이름의 목록만. 값은 붙여 주지 않는다.
- 함께 할 것: GitHub 오른쪽 위 프로필 → **Settings** → **Notifications**에서 **Actions** 알림을 메일로 받게 하고, 실패한 워크플로만 알리게 고른다. 과제 21에서 더했다. 내보내기 워크플로가 커밋하지 못하면 승인한 개정이 저장소에 오르지 않고 `pending/`에 남는데, 그것을 알 길이 이 메일이다. 화면 이름은 조금 다를 수 있다.

### 5. 예산과 알림 설정

예산은 Databricks에 쓴 돈을 세다가 정한 금액을 넘으면 메일을 보내는 기능이다. 돈 쓰는 것을 멈추지는 않고, 메일은 최대 24시간 늦게 온다. 체험 크레딧도 빼지 않고 센다. 실제로 멈추는 것은 과제 13의 비용 차단 작업이다.
- 누를 곳: 계정 콘솔 왼쪽 **Usage**를 누르고 **Budgets** 탭에서 **Add budget**을 누른다. **Name**을 넣고 **Add threshold**를 세 번 눌러 **Monthly threshold**와 **Email addresses**를 넣은 뒤 **Create**를 누른다.
- 넣을 값: 이름 `cherry-monthly`. 알림 금액은 15달러, 30달러, 60달러다. 한 달 예산 30달러를 가운데에 두고 절반과 두 배에서도 알린다. 메일은 사용자 메일이다.
- 성공하면 보이는 것: **Budgets** 목록에 `cherry-monthly`가 있다.
- Claude에게 붙여 줄 것: 목록 화면에 보이는 예산 이름과 알림 금액 세 개.
- 알아 둘 것: 익스프레스 설정 계정에서 계정 콘솔로 가는 길은 공식 문서에 없다. 가입한 날 작업 공간 화면에서 같이 찾는다.
- SQL 웨어하우스: 2026-10-01 첫 청구 기록에서 하루 14달러 가운데 SQL 웨어하우스가 96%였다. **SQL Warehouses**에서 쓰는 웨어하우스의 **Cluster size**를 **2X-Small**, **Auto stop**을 화면 최솟값인 5분으로 둔다. 2X-Small은 한 시간 4 DBU, 약 2.8달러다. 조회가 끝나도 자동 중지 시간만큼 켜져 있고 그동안도 돈이 나간다.

### 6. 체험이 끝나는 날 결제 정보 등록

- 언제: 가입한 날부터 14일째다. 그날 Claude가 알린다.
- 누를 곳: 작업 공간 위쪽 막대의 **Manage trial**에서 신용카드를 넣는다.
- 알아 둘 것: 체험이 끝나거나 크레딧을 다 쓰면 쓴 만큼 내는 방식으로 바뀐다. 결제 정보를 넣지 않고 두면 작업 공간에 만든 것이 체험이 끝나고 60일 뒤 지워진다.
- 성공하면 보이는 것: 위쪽 막대의 체험 안내가 사라지거나 결제 방식이 바뀌었다고 나온다. 작업과 예약은 그대로 돈다.
- Claude에게 붙여 줄 것: 등록했다는 말만. 카드 정보는 붙여 주지 않는다.

### 차단을 사람이 풀 때

비용 차단 작업은 쓴 금액을 모르면 멈추는 쪽으로 만들었다. 그래서 한도를 넘지 않았는데도 멈출 수 있다. 가격 표가 늦게 들어오거나 서비스 주체 권한이 빠진 경우다. 과제 13 위험 검토에서 더했다. 화면 이름은 실제와 조금 다를 수 있다.
- 알게 되는 길: 차단 작업이 "비용 차단 알림"으로 실패하면 알림 메일이 온다. 배포 워크플로가 "차단된 달이라 배포하지 않는다" 경고를 남기고 건너뛴다.
- 원인 보기: **Jobs & Pipelines**에서 `cherry_cost_guard`를 열고 마지막 실행의 출력과 오류 글을 본다. 쓴 금액, 한도, 가격 없는 사용량, 조회 실패가 나온다.
- 가격 표가 비어서라면 먼저 기다린다. 공식 문서는 새 작업 공간의 청구 기록이 늦게 들어온다고 한다.
- 급하게 풀어야 하면 이 순서로 한다.
  1. `cherry_cost_guard`의 예약을 화면에서 멈춘다. 그래야 6시간 뒤 다시 멈추지 않는다.
  2. 멈춘 작업마다 태그 `cherry_guard_paused`를 지우고, 예약이나 트리거를 다시 켠다. `cherry_refresh` 안에도 마지막에 비용 차단 단계가 있다. 원인을 고치기 전에 트리거를 다시 켜면 새 파일이 올 때 그 단계가 돌아 다시 멈출 수 있다.
  3. 원인을 고친 뒤 GitHub **Actions**의 `deploy` 워크플로를 수동으로 돌린다. 배포는 `cherry_cost_guard`의 예약도 파일대로 다시 켠다. 배포가 끝나면 화면에서 그 예약이 Paused가 아닌지 본다. 화면에서만 바꾼 설정을 배포가 되돌리는지는 아직 시험하지 않았다.
- 성공하면 보이는 것: 다음 `cherry_cost_guard` 실행이 성공으로 끝나고 출력에 `멈춤 False`가 찍힌다. 멈췄던 작업에 태그 `cherry_guard_paused`가 없고 예약이나 트리거가 켜져 있다.
- 운영 작업을 손으로 돌릴 때는 PC의 `databricks bundle run -t prod`를 쓰지 않는다. 운영 배포 경로를 사람 계정으로는 찾지 못해 오류로 멈춘다. 화면의 작업 실행에서 매개변수를 바꿔 돌리고, `--limit`을 넣을 때는 `--signup`과 `--target`도 함께 넣는다.

### 내보내기 폴더가 계속 실패할 때

검수에서 승인한 개정은 매일 `export` 워크플로가 저장소에 커밋한다. 폴더 하나가 검사에 걸리면 그 폴더는 운영 볼륨 `cherry.gold.export`의 `pending/`에 남고, 실행은 실패로 끝나 GitHub 알림 메일이 온다. 치우지 않으면 매일 같은 실패 메일이 와서 새 실패가 묻힌다. 과제 21 위험 검토에서 더했다.
- 원인 보기: GitHub **Actions**에서 `export`의 실패한 실행을 열고 `prepare`의 "폴더마다 검사하고 커밋" 단계를 본다. 카탈로그 검사 오류, 커밋 메시지 규칙 위반, 모르는 파일, 빈 폴더 중 무엇인지 나온다.
- 고치기: 걸린 승인은 골드에 이미 들어가 있다. 그래서 새로 고쳐 승인해도 그 승인의 기준이 저장소와 달라 같은 까닭으로 걸린다. 원인이 워크플로나 커밋 훅 쪽이면 고친 뒤 `export`를 수동으로 다시 돌린다. 폴더 내용이 잘못이면 출력과 폴더 이름을 Claude에게 붙여 저장소와 골드를 맞추는 순서를 함께 정한다. 검수 앱은 이런 폴더가 36시간 넘게 남아 있으면 새 승인을 멈춘다.
- 치우기: **Catalog**에서 `cherry` → `gold` → `export` 볼륨을 열고 `pending/` 아래 그 폴더를 지운다. 지운 승인은 저장소에 오르지 않으니, 골드와 저장소가 어긋나지 않게 고친 승인이 먼저 들어간 것을 확인하고 지운다.
- 성공하면 보이는 것: 다음 `export` 실행이 초록 체크로 끝나고 `pending/`이 빈다.

### 작업이 패키지 설치에서 실패할 때

- 보이는 것: 실행이 시작하자마자 `Library installation failed`, `ERROR_NO_SUCH_FILE_OR_DIRECTORY`, `Unable to reinstall packages after restore`로 끝난다. 오류에 나온 `cherry_core-0.1.0+<숫자>` 파일의 숫자가 작업 화면 **Environment and Libraries**의 숫자보다 작다.
- 까닭: 서버리스가 지난 성공 실행의 환경을 되살리면서 그때의 예전 wheel 파일을 다시 깔려 했다. 그 파일은 다음 배포가 지웠다. 작업 정의는 최신이다. 2026-10-02 운영 `cherry_refresh`에서 한 번 일어났다.
- 할 일: 작업 화면에서 **Run now**를 한 번 누른다. 2026-10-02에는 다시 돌린 실행이 성공했다. 같은 오류가 되풀이되면 오류의 숫자와 작업 화면의 숫자를 Claude에게 붙여 준다.

### 개정의 근거 원문 따라가기

- 쓰는 것: `pipeline/src/lineage.sql`. 골드의 카드 개정 한 줄에서 검수 기록과 근거 원문 파일까지 따라간다. 작업 003 과제 22.
- 돌리기: 파일 안의 카드 id를 따라갈 카드로 바꿔 **SQL Editor**에 붙여 돌린다. 편집기 탭에 다른 SQL이 남아 있으면 지우고 붙인다.
- 성공하면 보이는 것: 개정마다 `첫 적재`, `손 승인`, `검수 앱 승인` 가운데 하나와 원문 파일 경로가 나온다. 삼성, 롯데, IBK 다섯 장은 자동 수집 원문이 없어 원문 칸이 비고 검수 기록에서 끝난다.

- 표 단위 계보: 화면 왼쪽 **Catalog**에서 표를 열고 **Lineage** 탭을 본다. 2026-10-03 작업 007로 `fetches` → `documents` → `changes`, `card_lists` → `queue`, `documents`와 `changes`와 `golden` → `drafts` → `queue`, `drafts` → `catalog_files`와 `card_revisions`가 이어졌다. 마지막 선은 검수 앱 승인일 때만 생긴다. 선은 작업이 끝나고 몇 분 뒤에 보인다.

### 운영 대시보드

- 보는 것: 화면 왼쪽 **Dashboards**의 "체리컨슘 운영". 수집 상태, 검수 대기, 쓴 금액을 한 화면에 보인다. 작업 007. 정의는 `pipeline/dashboards/ops.lvdash.json`이다.
- 비용: 열 때만 SQL 웨어하우스가 켜지고 5분 쓰지 않으면 멈춘다. 예약 새로고침은 없다. 웨어하우스는 켜질 때마다 돈이 나와, 쓴 금액에서 가장 큰 몫이 SQL이다. 2026-10-01과 10-02에 하루 7~13달러였다.
- 화면을 고치면: 개발용 화면에서 고친 뒤 `databricks bundle generate dashboard`로 정의 파일을 다시 받는다.
- 2026-10-04 작업 010으로 "카탈로그 변경" 묶음을 더했다. 최근 30일 바뀐 개정 목록과 날짜별 바뀐 개정 수다.

### 카탈로그 변경 이력 보기

골드 `card_revisions`가 바뀔 때마다 작업 `cherry_history_refresh`가 Lakeflow 파이프라인 `cherry_history`를 돌려 실버 `card_revision_history`에 쌓는다. 작업 010. 행이 바뀌면 옛 행을 지우지 않고 끝난 시각을 적어 닫는다. `__START_AT.at`부터 `__END_AT.at` 전까지가 그 행이 맞았던 때이고, 지금 맞는 행은 `__END_AT`이 비어 있다. 첫 판의 행은 이력을 켠 날의 첫 적재다.

- 어느 날 이 카드의 규칙이 무엇이었나:

```sql
SELECT effective_from, rules, review_id
FROM cherry.silver.card_revision_history
WHERE card_id = 'kb-toktok'
  AND __START_AT.at <= TIMESTAMP'2026-10-10 00:00:00'
  AND (__END_AT IS NULL OR __END_AT.at > TIMESTAMP'2026-10-10 00:00:00')
ORDER BY effective_from
```

- 이 카드의 개정이 언제 어떻게 바뀌어 왔나:

```sql
SELECT effective_from, __START_AT.at AS opened, __END_AT.at AS closed, review_id
FROM cherry.silver.card_revision_history
WHERE card_id = 'kb-toktok'
ORDER BY effective_from, __START_AT
```

- 최근 한 달 바뀐 카드. 이력을 켠 날의 첫 적재는 뺀다:

```sql
WITH first AS (SELECT min(__START_AT.version) AS v FROM cherry.silver.card_revision_history)
SELECT DISTINCT card_id
FROM cherry.silver.card_revision_history, first
WHERE (__START_AT.at >= current_date() - INTERVAL 30 DAYS AND __START_AT.version > first.v)
   OR __END_AT.at >= current_date() - INTERVAL 30 DAYS
```

- 승인은 규칙이 바뀐 개정을 같은 판 안에서 지우고 새로 넣는다. 이력에서는 옛 행이 그 판의 차례 0에 닫히고 새 행이 차례 1에 열린다. 시행일을 바로잡으면 옛 시행일 행이 닫히고 새 시행일 행이 열려 다른 개정처럼 보인다. 같은 `review_id`로 묶어 본다.
- 개발용에서 처음부터 다시 쌓으려면 `pipeline` 폴더에서 `databricks bundle run cherry_history --full-refresh-all`. 그때까지의 이력은 사라지고 지금 개정만 첫 적재로 다시 들어간다. 운영 이력 표는 `pipelines.reset.allowed=false`로 이 명령을 막아 두었다. 원천이 지우고 다시 넣는 표라 이력이 지워지면 되살릴 곳이 없다.
- 설정: 골드 `card_revisions`의 변경 데이터 피드와 변경 파일, 로그 보존 60일은 승인 작업과 골드 첫 적재 작업이 쓰기 전에 켠다. 사람 계정은 운영 골드 설정을 못 바꾼다. 피드가 켜지기 전에 이력 작업을 손으로 돌리지 않는다. 스트림이 피드 없는 판을 기억해 계속 실패할 수 있다. 트리거는 데이터 변경만 보고 설정 변경은 보지 않는다. 그래서 피드를 처음 켠 뒤에는 이력 작업을 손으로 한 번 돌린다. 운영은 2026-10-04 그렇게 켰다.
- 운영 이력 작업이 끊겼을 때: 실패 메일이 오면 먼저 작업 실행 화면의 오류를 본다. "change data was not recorded"나 파일을 못 찾는다는 오류면 밀린 변경이 지워진 것이다. 이때 순서는 이렇다. 첫째, **SQL Editor**에서 지금 이력을 `CREATE TABLE cherry.silver.card_revision_history_until_<날짜> AS SELECT * FROM cherry.silver.card_revision_history`로 따로 남긴다. 둘째, 번들 변수 `history_reset_allowed`를 운영도 true로 바꿔 푸시하고 전체 다시 쌓기를 한 번 돌린 뒤 false로 되돌린다. 셋째, 옛 이력은 남긴 표에서 본다. 남긴 표 만들기와 운영 실행은 Claude가 사용자에게 묻고 한다.

### 지금 파는 카드 색인 보기

카드사 상품공시실과 카드 목록에서 지금 파는 카드와 단종 카드를 모은 표가 실버 `card_index`다. 작업 008. `cherry_refresh`의 `index` 단계가 새 공시 묶음이 올 때마다 MERGE한다. 공시는 수집기 `--disclosure`가 받는다.

- 카드사별 수: `SELECT issuer, count_if(status = 'on_sale') AS on_sale, count(*) AS rows FROM cherry.silver.card_index GROUP BY issuer ORDER BY issuer`
- 카탈로그에 없는 판매 중 카드: `SELECT i.issuer, i.name, i.card_id FROM cherry.silver.card_index i LEFT JOIN cherry.gold.catalog_files f ON f.path = concat('cards/', i.issuer, '/', i.card_id, '.yaml') WHERE i.status = 'on_sale' AND f.path IS NULL ORDER BY i.recommended DESC, i.issuer`
- 단종일이 `discontinued_estimated`가 참이면 공시실에 단종일이 없어 처음 사라진 날을 적은 것이다.
- 카드 요청 표시: 설문으로 요청이 온 카드는 `requested`를 켜면 검수 앱에서 추천 카드 다음에 보인다. 운영 표에 쓰는 일이라 Claude가 사용자에게 묻고 `UPDATE cherry.silver.card_index SET requested = true WHERE issuer = '<카드사>' AND card_id = '<id>'`를 돌린다. 색인 작업은 이 칸을 바꾸지 않는다. 작업 008 13단계.
- 안전장치에 걸렸을 때: `index` 단계가 "지난번 판매 중 N장 가운데 M장이 판매 중에서 빠진다"로 실패하면 먼저 그 카드사 공시 원문이 점검 화면인지, 화면이 바뀌어 읽기가 깨졌는지 본다. 그렇다면 읽기 함수를 고친다. 카드사가 실제로 카드를 많이 단종한 것이 맞으면, Claude가 사용자에게 묻고 빠진 열쇠의 행을 SQL로 `status = 'discontinued'`, `discontinued_estimated = true`로 바꾼 뒤 `cherry_refresh`를 다시 돌린다. 그러면 지난번 판매 중 수가 줄어 안전장치를 지난다. 드문 일이다.

### 카드 요청 설문

앱 카탈로그에 없는 카드를 앱 사용자가 알려 주는 Google 설문이다. 작업 008 14단계, 설계 5절, 시나리오 E22. 설문과 답 스프레드시트는 사용자 Google 계정에 있고, 앱의 "요청하기" 링크는 주 개발 세션이 단다. 설문 만들기는 계정 일이라 사용자가 한다.

만들기
1. 브라우저에서 `forms.google.com`을 열고 앱 문의에 쓰는 Google 계정으로 로그인한다. **빈 양식**을 누른다.
2. 제목은 "체리컨슘 카드 요청"이다. 설명 칸에 "앱에 없는 카드를 알려 주세요. 카드사 공식 자료로 확인한 뒤 앱에 넣습니다. 연락처는 넣은 뒤 알림을 받고 싶을 때만 적어 주세요."를 넣는다.
3. 질문 넷을 만든다. 질문마다 오른쪽 위에서 형식을 고르고, 아래 **필수** 스위치를 정한다.
   - 카드사: **드롭다운**, 필수. 보기는 신한, 삼성, 현대, KB국민, 롯데, 하나, 우리, NH농협, IBK기업, 카카오뱅크, 기타다.
   - 카드 이름: **단답형**, 필수.
   - 신용카드인가요, 체크카드인가요: **객관식 질문**, 필수. 보기는 신용, 체크, 모름이다.
   - 연락처: **단답형**, 필수 끔. 질문 아래 설명에 "넣은 뒤 알림을 받을 메일 주소. 적지 않아도 됩니다."를 넣는다.
4. 위쪽 **설정** 탭에서 **응답**을 펼친다. **이메일 주소 수집**은 **수집 안함**, **응답 횟수 1회로 제한**은 끈다. 로그인 없이 낼 수 있어야 하고, 연락처를 묻지 않는 것이 기본이기 때문이다.
5. 위쪽 **응답** 탭에서 **Sheets에 연결**을 누르고 **새 스프레드시트 만들기**로 만든다.
6. 오른쪽 위에 **게시**가 보이면 먼저 누른다. 그다음 **보내기** → 링크 모양 아이콘 → **URL 단축** → **복사**를 누른다.
7. 성공하면 보이는 것: 시크릿 창에서 복사한 주소를 열면 로그인 없이 네 질문이 보인다. 시험으로 하나 내면 스프레드시트에 한 줄이 생긴다. 그 줄은 지운다.
8. 복사한 주소를 Claude에게 붙여 준다. Claude가 이 절에 적고 주 개발 세션에 넘긴다.

답 보기와 처리
- 스프레드시트는 저장소에 넣지 않는다. 연락처가 들어올 수 있다. 연락처를 얼마나 두는지는 개인정보처리방침에 적힌 대로 따른다. 방침에 설문을 더하는 것은 주 개발 세션의 작업 012 일이다.
- 요청이 오면 카드사와 카드 이름을 Claude에게 알린다. 연락처는 넘기지 않는다. Claude가 색인에서 찾는다. `SELECT issuer, card_id, name, status, recommended, requested FROM cherry.silver.card_index WHERE issuer = '<카드사>' AND name LIKE '%<이름 일부>%'`
- 색인에 있으면 위 "카드 요청 표시"로 `requested`를 켠다. 그 카드는 새 카드 초안을 고를 때 추천 카드 다음으로 먼저 뽑히고, 검수 앱에서도 추천 다음에 보인다. 아직 초안이 없으면 추출을 `mode new_card`, 그 카드사, `limit 1`로 돌린다. 운영 작업이라 Claude가 사용자에게 묻고 돌린다.
- 색인에 없으면 3년 넘게 전에 단종됐거나 공시실에 없는 카드다. 카드 조사 에이전트로 조사해 손 승인으로 넣는다.
- 넣었으면 연락처가 있는 사람에게 메일로 알린다.

### 집 PC 러너

GitHub 자체 호스팅 러너는 GitHub Actions 작업을 GitHub 서버 대신 사용자 집 PC가 받아 돌리는 프로그램이다. 2026-10-04 작업 008 6단계부터 `collect` 워크플로가 이 러너에서만 돈다. 신한처럼 GitHub 서버의 접속을 막는 카드사도 집 주소로는 받힌다. 러너 등록과 GitHub 설정은 계정에 걸린 일이라 사용자가 한다. 집 PC는 Windows다.

러너가 하는 일은 그 PC의 Windows 계정 권한으로 돈다. 공개 저장소라 누구나 풀 리퀘스트로 워크플로를 바꿀 수 있고, 그 풀 리퀘스트를 실행하도록 승인하면 바뀐 코드가 이 PC에서 돈다. 그러면 그 계정의 파일과 로그인 정보에 닿는다. 그래서 아래 두 가지를 지킨다.
- 외부인의 풀 리퀘스트에는 실행 승인 버튼을 누르지 않는다. 누를 일이 생기면 먼저 `.github/workflows` 아래 바뀐 것이 없는지 Claude에게 보여 준다.
- 할 수 있으면 러너는 개인 파일이 없는 별도 Windows 표준 계정에서 돌린다. 그 계정에는 Databricks CLI 로그인과 저장소의 `app/test/local` 같은 개인 파일을 두지 않는다.

처음 한 번:
1. Git for Windows를 설치한다. 워크플로가 그 안의 bash로 돈다. Git for Windows는 PATH에 bash 폴더를 넣지 않아 `bash`가 Windows의 WSL `bash.exe`로 잡힐 수 있다. 워크플로 첫 단계가 Git Bash 폴더를 PATH 앞에 두므로 PC 설정은 바꾸지 않는다. 2026-10-05 첫 실행에서 이것으로 모든 카드사가 멈췄다. PowerShell에서 `git --version`이 버전을 찍고 `Test-Path "C:\Program Files\Git\bin\bash.exe"`가 `True`면 된다.
2. PowerShell을 열고 먼저 `cd C:\`를 친다. GitHub의 받기 명령은 지금 있는 폴더 아래에 `actions-runner` 폴더를 만들기 때문이다.
3. GitHub 저장소 화면에서 **Settings** → **Actions** → **Runners** → **New self-hosted runner**를 누르고 **Windows**, **x64**를 고른다. 화면의 **Download** 칸 명령을 같은 PowerShell에서 차례로 돌린다. `C:\actions-runner` 폴더가 생긴다.
4. 같은 화면의 **Configure** 칸 첫 명령 `./config.cmd --url … --token …`을 돌린다. 물음에는 이렇게 답한다. 러너 그룹, 이름, 작업 폴더는 Enter로 기본값을 쓴다. 이름표를 묻는 `Enter any additional labels`에는 `cherry-home`을 친다. `Would you like to run the runner as service?`에는 `N`을 친다. 수집하는 날에만 켜 두려는 것이다. 마지막에 `Settings Saved.`가 보이면 된다.
5. **Settings** → **Actions** → **General**의 외부 기여자 풀 리퀘스트 실행 승인 칸에서 모든 외부 기여자에게 승인을 받는 항목을 고르고 **Save**를 누른다.
6. 성공하면 보이는 것: Git Bash에서 `cd /c/actions-runner && ./run.cmd`를 치면 `Listening for Jobs`가 찍히고, **Settings** → **Actions** → **Runners**에 러너가 `Idle`로 보인다. 확인했으면 Ctrl+C로 끈다.
7. 휴대폰 달력에 매달 1일과 15일 반복 알림을 둔다. 예약을 없애 잊어도 실패 메일이 오지 않는다.

매달 1일과 15일:
1. PC 절전을 잠시 끈다. Windows **설정** → **시스템** → **전원** → **화면 및 절전**에서 절전 모드로 전환을 **안 함**으로 바꾼다. 1일 실행은 두세 시간이라 그 사이 절전에 들면 러너가 끊기고 남은 카드사가 멈춘다. 끝나면 원래대로 돌린다.
2. Git Bash에서 `cd /c/actions-runner && ./run.cmd`로 러너를 켠다. 창을 닫으면 러너도 꺼진다. 2026-10-05 사용자가 러너는 Git Bash에서 켜기로 정했다. 러너가 Git Bash의 PATH를 물려받아 워크플로의 `bash`가 처음부터 Git Bash로 잡힌다. 러너 등록 1~5번은 GitHub 화면의 PowerShell 명령이라 PowerShell에서 한다.
3. GitHub **Actions** → **collect** → **Run workflow**를 누르고, 1일에는 `30`, 15일에는 `14`를 골라 **Run workflow**를 누른다. 카드사 칸은 `all` 그대로 둔다. 한 카드사의 "받은 원문 올리기"가 실패했으면 그 카드사만 골라 같은 주기로 다시 돌린다. 2026-10-04 사용자가 예약 대신 손으로 돌리기로 정했다.
4. 카드사 열한 곳의 작업이 차례로 돈다. 15일은 카드 원문만이라 몇 분이고, 1일은 상품공시실과 카탈로그 밖 카드 1,000장 안팎의 상품 페이지와 PDF까지 받아 두세 시간 걸린다.
5. 끝나면 러너를 켠 Git Bash 창에서 Ctrl+C로 러너를 끄고 절전 설정을 되돌린다.

성공과 실패를 가르는 법:
- 1일에는 받을 주소가 2,000개 안팎이라 상품 페이지 몇 개가 404로 실패하는 일이 흔하다. 그러면 그 카드사 작업이 빨갛게 끝나도 받은 것은 모두 올라간다.
- 빨간 작업을 열어 "원문 받기" 단계의 마지막 줄 `저장 N, robots.txt로 건너뜀 N, 실패 N, 뺌 N`을 본다. 실패가 몇 개뿐이면 넘어간다. 실패가 수십 개거나 `멈춤`이 찍혔거나 "받은 원문 올리기" 단계가 빨가면 그 단계의 마지막 몇 줄을 Claude에게 붙여 준다. 원문 내용은 찍히지 않는다.
- 그 뒤 운영 `cherry_refresh`가 저절로 돌아 색인과 글을 만든다. Claude가 결과를 본다. 글 뽑기 단계가 한 시간 제한에 걸리면 색인과 추출이 그 실행에서 건너뛰어지므로, Claude가 사용자에게 묻고 `cherry_refresh`를 다시 돌린다. 이미 해석한 PDF는 다시 해석하지 않는다.
- 2026-10-05부터 PDF는 집 PC가 Docling으로 해석해 원문 옆에 `.md`로 올린다. 작업 008 9단계. 첫 실행은 Docling과 torch 설치로 2GB쯤 받고, "Docling 준비" 단계가 모델을 처음 한 번 HuggingFace에서 받아 사용자 폴더에 둔다. 그 단계가 빨가면 그 카드사는 받지 않고 끝난 것이다. 마지막 몇 줄을 Claude에게 붙여 준다. 그 뒤 PDF는 쪽당 1초쯤이다. "원문 받기" 단계에 `Docling 실패`, `글자 깨짐`, `글자층 없음`, `빈 쪽`, `일부 쪽 실패`가 찍힌 PDF는 `.md` 없이 올라가 운영에서 `ai_parse_document`로 해석되고 요금이 나온다. 롯데 상품설명서는 글자 깨짐이라 워크플로가 롯데에는 Docling을 돌리지 않고 모두 이쪽이다. 다른 카드사에서 거의 모든 PDF가 이렇게 찍히면 그 줄을 Claude에게 붙여 준다.
- 첫 1일 실행은 처음 보는 PDF가 수백 개다. 글자층이 없는 PDF만 `ai_parse_document`로 해석해 요금이 나온다. 체험이 끝나는 10월 13일 전에 돌리면 체험 크레딧 안이다. 그 뒤라면 한 달 30달러 비용 차단에 걸려 남은 달 동안 `cherry_refresh`가 멈출 수 있다.
- 카드사가 수집 중단을 요청하면 워크플로 `matrix`의 카드사 목록에서 빼고 카드사 파일을 `blocked`로 둔다. 2026-10-04 사용자가 정했다.

### 러너를 쓸 수 없을 때 PC에서 받기

집 PC 러너를 쓸 수 없는 날에는 사용자가 PC에서 받아 운영 볼륨에 올린다. 아래 명령은 `--docling`을 붙이지 않아 PDF는 운영에서 `ai_parse_document`로 해석된다. 2026-10-01부터 10월 4일까지 GitHub 서버를 막는 신한을 이렇게 받았다. 아래는 신한 예다. 다른 카드사는 `--issuer`를 바꾼다. 삼성, IBK, 카카오뱅크, 롯데, 카드다모아는 `--ignore-robots <카드사 id>`를 함께 붙인다. 1일에는 같은 명령에 `--disclosure --index-cards 0`을 붙여 한 번 더 돌린다. 카드다모아는 이 두 번째 명령만 돌린다.
- 처음 한 번: 운영 스키마는 서비스 주체가 만들어 사람 계정에는 권한이 없다. 2026-10-01 첫 올리기가 `User does not have USE SCHEMA privilege on SCHEMA 'cherry.bronze'`로 멈췄다. **SQL Editor**에서 ``GRANT USE SCHEMA ON SCHEMA cherry.bronze TO `cherry-admins`;``와 ``GRANT READ VOLUME, WRITE VOLUME ON VOLUME cherry.bronze.raw TO `cherry-admins`;``를 돌린다. 원문 볼륨 하나만 연다.
- 어디서: PowerShell에서 저장소 맨 위 폴더 `cherryConsume`. 받은 원문은 저장소 밖 임시 폴더에 두어 커밋에 섞이지 않게 한다.
- 받기: 아래 두 줄을 차례로 돌린다. 첫 줄은 이번에 쓸 폴더 이름을 정한다. 둘째 줄은 신한 원문을 받는다. 1분쯤 걸리고 마지막 줄이 `저장 10, robots.txt로 건너뜀 0, 실패 0, 뺌 0`처럼 실패 0이면 성공이다. 개수는 카드가 늘면 달라진다.

```powershell
$raw = "$env:TEMP\cherry-raw-$(Get-Date -Format yyyyMMddHHmm)"
uv run --project backend --with playwright==1.63.0 python -m cherry_core.pipeline.collect --out $raw --interval 30 --issuer shinhan
```

- 올리기: 같은 창에서 아래를 한 덩어리씩 돌린다. 원문 파일을 먼저 올리고, 목록 파일을 마지막에 올린다. 목록이 먼저 올라가면 적재 작업이 아직 없는 원문을 찾는다. PowerShell은 명령 하나가 실패해도 다음 줄로 넘어가므로, 오류 글이 보이면 거기서 멈추고 Claude에게 붙여 준다.
- 폴더째 `cp -r`로 올리지 않는다. 볼륨에 같은 날짜 폴더가 이미 있으면 그 안에 한 단계 더 들어가 올라가고, 목록 파일이 그 원문을 찾지 못한다. 2026-10-02 계보 시험에서 겪었다. 그래서 파일 하나하나를 PC 폴더의 상대 경로 그대로 올린다.

원문 파일 올리기:

```powershell
Get-ChildItem $raw -Recurse -File | Where-Object { $_.FullName -notlike "*\manifests\*" } | ForEach-Object { $rel = $_.FullName.Substring("$raw\".Length).Replace('\', '/'); databricks fs cp $_.FullName "dbfs:/Volumes/cherry/bronze/raw/$rel" --overwrite }
```

제자리 확인. `list-`로 시작하는 파일이 보이면 성공이다.

```powershell
$day = (Get-ChildItem $raw -Directory | Where-Object Name -ne manifests).Name
databricks fs ls "dbfs:/Volumes/cherry/bronze/raw/$day/shinhan/_issuer"
```

목록 파일 올리기:

```powershell
databricks fs mkdir dbfs:/Volumes/cherry/bronze/raw/manifests
Get-ChildItem "$raw\manifests\*.jsonl" | ForEach-Object { databricks fs cp $_.FullName "dbfs:/Volumes/cherry/bronze/raw/manifests/$($_.Name)" --overwrite }
```

- 성공하면 보이는 것: `databricks fs ls dbfs:/Volumes/cherry/bronze/raw/manifests`에 방금 받은 `manifest-날짜T시각Z.jsonl`이 보인다. 화면의 **Catalog**에서 `cherry` → `bronze` → `raw` 볼륨을 열어도 된다.
- 실패가 있으면: 실패한 줄의 카드사와 오류 종류를 Claude에게 붙여 준다. 원문 내용은 찍히지 않는다.

### 골드 첫 적재

저장소의 `catalog/`를 골드 표에 처음 올린다. 작업 003 과제 17, 설계 4절 1번. 운영에서 이 작업이 끝나면 카탈로그의 원본은 골드이고, 그 뒤로 `catalog/`를 직접 고치지 않는다.
- 만드는 표: `gold.catalog_files`는 카탈로그 파일마다 한 행이다. `gold.card_revisions`는 카드 개정마다 카드사 기본값까지 합친 규칙이다. 두 표의 검수 기록 번호는 `initial`이다. `silver.golden`은 정답 예시로, 카드마다 마지막 개정의 시행일과 규칙, 처음 받은 원문 경로다.
- 지키는 것: 작업 `cherry_seed_gold`는 쓰기 전에 올린 카탈로그의 해시를 PC 값과 맞춘다. 올리기가 끊겨 카드 파일이 빠지면 검사는 통과하고 카드만 줄기 때문이다. 골드에 카탈로그가 이미 있으면 골드는 건드리지 않고 정답 예시만 다시 만든다. 다시 쓰면 그 뒤에 승인된 개정을 저장소 판으로 덮는다.
- 해시 받기: Claude가 PC에서 먼저 확인한다. `git status --porcelain catalog`가 비어 있고 `git rev-parse HEAD`가 `origin/master`와 같아야 한다. 그다음 `uv run --project backend python -m cherry_core.pipeline.seed catalog`가 찍는 해시 두 개를 사용자에게 준다. 작업 폴더가 저장소와 다르면 해시가 같아도 골드와 master가 다르다.
- 올리기: 저장소 맨 위 폴더에서 `catalog-seed` 폴더를 `databricks fs rm -r`로 지운 뒤 `databricks fs cp -r catalog <볼륨>/catalog-seed --overwrite`로 올린다. 지우지 않으면 저장소에서 지운 파일이 남는다. 처음이면 지우기 오류는 무시한다. 볼륨은 개발용이 `dbfs:/Volumes/cherry/dev_<개발자 이름>_bronze/raw`, 운영용이 `dbfs:/Volumes/cherry/bronze/raw`다.
- 돌리기: 개발용은 `pipeline` 폴더에서 `databricks bundle run cherry_seed_gold --params expect_files=<파일 해시>,expect_revisions=<개정 해시>`다. 운영용은 푸시해 배포된 뒤 화면에서 운영 `cherry_seed_gold`를 열고, 매개변수를 바꿔 실행하는 메뉴에서 두 칸에 해시를 넣어 돌린다. 사람 계정으로는 `bundle run -t prod`를 쓸 수 없다.
- 성공하면 보이는 것: 출력 세 줄. `골드 카탈로그 파일 35개 해시 …`, `골드 카드 개정 22개 해시 …`, `정답 예시 20장, 채점 전용 5장, 첫 수집 원문이 있는 카드 15장`. 앞의 두 해시가 넣은 해시와 같으면 골드와 저장소가 같다. 원문이 있는 카드는 GitHub이 받는 12장과 PC에서 받는 신한 3장이다. 삼성, 롯데, IBK는 사람이 원문을 더할 때까지 없다. 개수는 카드가 늘면 달라진다.
- 정답 예시 다시 만들기: 삼성처럼 사람이 원문을 `--add`로 더한 뒤 같은 해시로 다시 돌린다. 골드는 그대로이고 정답 예시만 바뀐다. 그래서 `catalog-seed`는 지우지 않고 첫 카탈로그 그대로 둔다.
- 운영 표를 SQL로 보려면: 운영 스키마는 서비스 주체가 만들어 사람 계정은 읽지 못한다. **SQL Editor**에서 ``GRANT USE SCHEMA, SELECT ON SCHEMA cherry.gold TO `cherry-admins`;``와 ``GRANT USE SCHEMA, SELECT ON SCHEMA cherry.silver TO `cherry-admins`;``를 한 번 돌린다. 읽기만 연다.
- 개발용에서 처음부터 다시 시험하려면: 골드 표 두 개를 SQL `DROP TABLE`로 지운 뒤 돌린다. 운영에서는 하지 않는다. 지우고 다시 만든 개정 표는 다른 표라 이력 스트림이 끊긴다. 개발용 이력도 `databricks bundle run cherry_history --full-refresh-all`로 다시 쌓는다.

### 손으로 승인하기

검수 앱이 생기기 전에 카탈로그를 바꾸는 길이다. 2026-10-01 서버 세션의 가맹점 요청으로 과제 20의 승인 부분만 먼저 만들었다. 작업 `cherry_approve`가 바뀐 파일을 골드 카탈로그에 넣어 검사하고, 통과하면 `silver.reviews`, `gold.catalog_files`, `gold.card_revisions`, `export` 볼륨 `pending/<검수 번호>/`의 파일과 `commit.json` 순서로 쓴다. 그 폴더는 `export` 워크플로가 다음 새벽에 저장소에 커밋한다. 저장소 카탈로그가 승인 전 골드와 같을 때만 커밋하고, 다르면 그 폴더를 거부한다.
- 한 번에 하나: 앞 승인이 저장소에 커밋된 뒤 다음 승인 파일을 만든다. 승인은 골드 해시가 PC에서 저장소로 잰 해시와 같아야 돌아서, 커밋 전에 만든 파일은 멈춘다. 옛 판을 고친 파일로 앞선 승인을 덮지 않으려는 것이다. 끝나지 않은 손 승인이 있어도 다음 승인은 멈춘다.
- 파일 만들기: Claude가 PC에서 저장소 카탈로그로 바뀐 파일을 저장 형식으로 만들고 검사한다. `git status --porcelain catalog`가 비고 `HEAD`가 `origin/master`와 같아야 한다. 해시는 `uv run --project backend python -m cherry_core.pipeline.seed catalog`의 카탈로그 파일 해시다. 저장소의 `catalog/`는 고치지 않는다.
- 처음 한 번, 운영만: **SQL Editor**에서 ``GRANT USE SCHEMA ON SCHEMA cherry.gold TO `cherry-admins`;``와 ``GRANT READ VOLUME, WRITE VOLUME ON VOLUME cherry.gold.incoming TO `cherry-admins`;``를 돌린다. 사람 계정은 업로드 볼륨 `incoming`에만 쓴다. `export` 볼륨에는 쓰기를 주지 않아 사람이 `pending/`에 직접 넣지 못한다.
- 올리기: `databricks fs cp -r <바뀐 파일 폴더>/catalog <incoming 볼륨>/<새 이름>/catalog --overwrite`. incoming 볼륨은 개발용이 `dbfs:/Volumes/cherry/dev_<개발자 이름>_gold/incoming`, 운영용이 `dbfs:/Volumes/cherry/gold/incoming`이다. 바꿀 파일만 넣는다. 이름은 승인마다 새로 쓴다. 끝난 이름을 다시 쓰면 멈춘다.
- 돌리기: 개발용은 `pipeline` 폴더에서 아래처럼 `--params` 값 전체를 큰따옴표로 감싸 돌린다. 값 안에는 쉼표를 쓰지 않는다. `--params`가 쉼표로 칸을 나누기 때문이다. 운영용은 화면에서 운영 `cherry_approve`를 열고 매개변수를 바꿔 실행하는 메뉴에서 같은 칸을 넣는다. 커밋 제목은 `feat: `나 `fix: `로 시작하고 끝에 마침표를 쓰지 않는다.

```powershell
databricks bundle run cherry_approve --params "incoming=<이름>,label=<영문 소문자 이름>,subject=feat: <무엇을 바꿨는지>,reviewer=<승인한 사람>,note=<근거>,expect_files=<해시>"
```

- 2026-10-04부터 운영 승인은 Claude가 사용자에게 물은 뒤 `databricks jobs run-now --json @<매개변수 파일>`로 돌린다. 사람 계정으로도 운영 작업을 이렇게 돌릴 수 있다. 매개변수 파일은 반드시 UTF-8로 쓴다. 2026-10-04 짧은 이름 승인에서 Windows 표준 출력으로 만든 파일이 cp949로 저장돼 봇 커밋 `90ff4b3`의 제목 한글이 깨졌다. 보내기 전에 파일을 UTF-8로 다시 읽어 제목이 같은지 본다.
- 성공하면 보이는 것: `1/5`부터 `5/5`까지 다섯 줄. 마지막 줄이 `5/5 commit.json. 검수 번호 r-…, 바뀐 파일 N개`다. 운영이면 다음 날 저장소에 봇의 커밋이 생긴다. 바로 보려면 GitHub **Actions**에서 `export`를 수동으로 돌린다.
- 멈추는 경우: 저장 형식이 아니거나, 카탈로그 검사 오류가 있거나, 골드에 있던 카드, 개정, 혜택 key가 사라지거나, 커밋 훅이 막을 제목이나 비밀값 같은 줄이 있으면 아무것도 쓰지 않고 멈춘다. 바꾸지 않은 카드의 개정이 바뀌어도 멈춘다. 규칙을 만드는 코드가 바뀐 경우라 Claude에게 붙여 준다. 추정 시행일을 실제 날짜로 바로잡는 것도 "개정이 사라진다"로 멈춘다. 이때도 Claude에게 붙여 준다.
- 중간에 끊기면: 같은 폴더 이름, 같은 제목으로 한 번 더 돌린다. 진행 상태는 사람이 고칠 수 없는 `silver.reviews`에 있어 남은 단계만 한다. 이미 쓴 곳은 다시 써도 결과가 같다. 올린 폴더는 지우거나 고치지 않는다. 그래도 멈추면 실패 메일의 마지막 단계 줄을 Claude에게 붙여 준다.

### 검수 앱

바뀐 원문에서 나온 초안을 보고 승인하거나 반려하는 Databricks 앱 `cherry-review-<대상>`이다. 작업 003 과제 20. 앱은 표를 읽기만 하고, 승인과 반려는 작업 `cherry_approve`가 한다. 켜져 있는 동안 요금이 나와 검수할 때만 켠다.
- 개발용 켜기: `pipeline` 폴더에서 `databricks bundle deploy` 뒤 `databricks bundle run cherry_review`. 끝나면 앱 주소가 찍힌다. 화면 왼쪽 **Compute**의 **Apps** 탭에서도 `cherry-review-dev`를 열 수 있다.
- 운영 켜기: 운영 앱은 푸시하면 배포 작업이 만들지만 켜지는 않는다. **Compute**의 **Apps** 탭에서 `cherry-review-prod`를 열고 **Start**를 누른다. 앱 코드를 바꾼 뒤에는 **Deploy**를 눌러 번들이 올린 `apps/review` 폴더를 고른다.
- 끄기: 검수가 끝나면 앱 화면에서 **Stop**을 누른다. 개발용은 `databricks apps stop cherry-review-dev`로도 끈다. 운영 비용 차단은 한도에서 운영 앱을 끄지만, 개발용 앱은 끄지 못하니 꼭 끈다.
- 목록 순서: 카탈로그 카드의 바뀐 원문 초안, 카드다모아 추천 카드, 요청 카드, 그 밖의 순서이고 같은 묶음 안에서는 오래된 것부터다. 추천과 요청은 앞에 `추천`, `요청`이 붙는다. 같은 카드의 더 새 새 카드 초안이 올라오면 옛 건은 추출이 `superseded`로 닫아 목록에서 빠진다. 바뀐 원문 초안과 승인이 끊긴 초안은 닫지 않는다. 작업 008 13단계. 운영 앱 코드를 이 판으로 Deploy하기 전에 운영 `cherry_refresh`가 한 번 돌아 색인에 `requested` 칸이 있어야 한다. 없으면 목록을 못 읽는다.
- 승인과 반려: 목록에서 건을 고르면 까닭, 검사 결과, 바뀐 원문 줄, 지금 골드 파일과 초안의 차이가 보인다. 아래 칸에서 카드 파일을 고쳐 승인할 수 있다. 저장 형식은 작업이 맞춘다. 누르면 작업이 끝날 때까지 기다렸다가 출력을 보인다. 성공한 승인은 손 승인처럼 다음 새벽 `export`가 저장소에 커밋한다.
- 멈추는 경우: 검사 오류, 사라지는 카드와 혜택 key, 초안을 만든 뒤 골드 카드 파일이 바뀐 경우, 운영 내보내기에 36시간 넘게 남은 폴더가 있는 경우다. 마지막 경우는 export가 커밋하지 못한 것이라 "내보내기 폴더가 계속 실패할 때"를 먼저 한다. 초안이 낡았다는 오류가 나면 반려하고, 초안의 변경은 지금 골드 판에 손 승인으로 넣는다. 반려한 변경은 다시 추출되지 않기 때문이다.
- 중간에 끊기면: 같은 건에서 처음 누른 버튼을 다시 누른다. 승인이 끊겼으면 승인을, 반려가 끊겼으면 반려를 누른다. 작업이 그 초안의 검수 기록을 보고 끊긴 승인을 이어 하거나 대기 건만 닫는다. 승인한 초안은 반려되지 않고 반려한 초안은 승인되지 않는다. 끊긴 앱 승인은 손 승인으로 잇지 않는다.
- 새 카드 초안: 2026-10-05 작업 008 11단계부터 추출 `new_card` 모드가 만든 새 카드 초안도 이 앱에서 승인한다. 목록에 `new_card`로 보인다. 골드에 파일이 없어 빈 글과의 차이가 보이고, 승인하면 `cards/<카드사>/<id>.yaml`로 들어간다. 카드 파일의 `id:` 줄을 바꾸면 그 이름으로 들어가고 색인도 따라 바뀐다. 확인 필요 항목을 원문과 맞춰 보고 연회비와 짧은 이름을 채운 뒤 승인한다. 초안이 없는 건은 카드 파일을 직접 쓰거나 반려한다. 커밋 제목은 "feat: <이름> 새 카드 추가"다. 새 카드 승인이 멈추는 경우: 올린 파일이 카드 파일 하나가 아니거나 그 카드사 폴더가 아니다, 골드에 이미 있는 경로다, 그 카드사 골드 카드와 상품 코드나 이름이 겹친다, 같은 카드의 다른 새 카드 초안이 이미 승인됐다, 바꾼 id를 색인의 다른 카드가 쓴다, 초안을 만든 뒤 카드사 파일이 바뀌었다, 앱 카탈로그를 만들 수 없는 수가 있다. 앞의 넷은 반려하고, 뒤의 셋은 id나 값을 고치거나 초안을 다시 만든다.
- 사라진 카드와 초안 없는 새 카드: 앱은 보여 주기만 한다. 다 본 건은 `silver.queue`에서 `status`를 `approved`나 `rejected`로 바꿔 닫는다. 행을 지우지 않는다. 바뀐 것 고르기는 검수 대기에 없는 사라진 카드를 다시 올려 메우므로, 지운 건은 다음 실행에 다시 열린다. 2026-10-03 작업 007. 2026-10-05 작업 008 10단계부터 목록 비교는 사라진 카드만 올리고, 새 카드는 추출 `new_card` 모드가 초안과 함께 올린다. 그 전에 올라온 초안 없는 새 카드 건은 카드 조사 에이전트로 조사해 손 승인으로 넣거나 같은 방법으로 닫는다.
- 성공하면 보이는 것: 앱 주소를 열면 "검수 대기" 제목과 열린 건 목록이 보인다. 승인하면 `cherry_approve SUCCESS`, `1/5`부터 `5/5`까지, `검수 대기 건을 닫았다`가 보이고 새로 고치면 그 건이 목록에서 사라진다. 끄면 **Apps** 탭의 상태가 멈춤이다.
- 권한: 앱 서비스 주체는 표 다섯 읽기, `incoming` 볼륨 쓰기, `cherry_approve` 실행만 받는다. 배포가 이 권한을 줄 때 앱 서비스 주체에게 `cherry` 카탈로그 사용 권한도 있어야 하는데, 배포하는 서비스 주체는 그것을 남에게 줄 수 없다. 그래서 처음 한 번, 운영만: **SQL Editor**에서 ``GRANT USE CATALOG ON CATALOG cherry TO `account users`;``를 돌린다. 2026-10-02 사용자가 정했다. 카탈로그로 들어가는 문만 열고, 스키마와 표는 따로 권한이 있어야 읽는다. 성공하면 다시 돌린 `deploy`가 초록 체크로 끝나고 **Apps** 탭에 `cherry-review-prod`가 멈춤 상태로 보인다.

## 출처

- [Databricks Free Edition limitations](https://docs.databricks.com/aws/en/getting-started/free-edition-limitations)
- [Lakebase release notes](https://docs.databricks.com/aws/en/release-notes/lakebase/)
- [Azure Databricks Lakebase is Generally Available](https://www.databricks.com/blog/azure-databricks-lakebase-generally-available)
- [Snowflake Postgres General availability, 2026-02-24](https://docs.snowflake.com/en/en/release-notes/2026/other/2026-02-24-snowflake-postgres-ga)
- [BigQuery sandbox](https://cloud.google.com/bigquery/docs/sandbox)
- [Databricks express setup](https://docs.databricks.com/aws/en/getting-started/express-setup)
- [Databricks free trial](https://docs.databricks.com/aws/en/getting-started/free-trial)
- [Databricks CLI install](https://docs.databricks.com/aws/en/dev-tools/cli/install)
- [Databricks CLI authentication](https://docs.databricks.com/aws/en/dev-tools/cli/authentication)
- [Manage service principals](https://docs.databricks.com/aws/en/admin/users-groups/manage-service-principals)
- [OAuth for service principals](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m)
- [OAuth API scopes](https://docs.databricks.com/api/workspace/scopes)
- [Workspace entitlements](https://docs.databricks.com/aws/en/security/auth/entitlements)
- [Budgets](https://docs.databricks.com/aws/en/admin/account-settings/budgets)
- [Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [Databricks pricing guide 2026, Flexera](https://www.flexera.com/blog/finops/databricks-pricing-guide/)
