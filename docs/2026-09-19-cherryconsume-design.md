# 체리컨슘 설계 문서

작성일 2026-09-19. 브레인스토밍에서 확정한 결정과 첫 하위 프로젝트의 상세 설계를 담는다.

## 1. 제품 개요

체리컨슘은 체리피커를 위한 카드 실적·혜택 관리 앱이다. 사용자는 자기 카드를 검색이나 카메라로 등록하고, 결제할 때마다 금액과 가게를 적는다. 앱은 카드별로 전월실적을 채우려면 얼마가 남았는지 보여 주고, 어느 가게에서 결제하려 할 때 보유 카드 중 혜택이 가장 큰 카드를 추천한다.

핵심 기능 4가지
1. 카드 등록. 카드사·상품명 검색, 또는 카드 앞면 사진으로 상품 식별
2. 결제 기록. 금액, 가게, 카드, 결제 시각을 직접 입력하거나, 카드사 웹에서 내려받은 이용 내역 엑셀을 올려 한 달치를 한 번에 넣음
3. 실적 현황. 카드별 이번 달 인정 실적과 다음 구간까지 남은 금액
4. 가게별 추천. 가게 이름이나 업종을 넣으면 보유 카드를 기대 혜택 금액 순으로 정렬한다. 가게를 고르면 내 카드마다 받을 수 있는 혜택 전부와 지금 못 받는 혜택의 이유까지 보여 준다

화면 구성과 흐름은 `design/wireframes.html`, 테이블 설계는 `docs/erd.md`에 있다.

## 2. 확정된 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 목표 | Android 먼저 실제 출시. 수익 모델은 아직 없음 | 사용자 확보 우선 |
| 팀 | 1인 개발 | 범위와 기술 스택을 최소로 |
| 스택 | Flutter 앱, Python 서버와 파이프라인 | 개발자가 가장 익숙한 조합 |
| 구조 | 표준 3계층. Flutter + FastAPI + Postgres. 계정과 결제 내역은 서버 저장, 추천은 서버 계산 | 기기 간 동기화와 분석 데이터 축적을 처음부터 |
| 앱 DB | Postgres. 처음엔 무료 구간이 있는 관리형 Postgres(Neon, Supabase 등)로 시작하고, 분석 데이터가 쌓이면 Databricks Lakebase로 옮기는 것을 검토. Postgres 표준 기능만 씀 | 수익 없는 단계에 첫날부터 나가는 비용을 만들지 않으면서, 나중에 Databricks 하나로 합칠 길을 열어 둠. 4.2절 |
| 결제 입력 | 직접 입력 + 이용 내역 엑셀 가져오기. 둘 다 MVP에 포함 | 마이데이터는 금융위 허가와 데이터 사용료가 필요하고 알림 읽기는 스토어 심사 부담. 엑셀 가져오기는 둘 다 없이 입력 부담을 줄임. 8절 |
| 카드 범위 | 신용카드와 체크카드, 주요 카드사 | |
| 카메라 | 카드 앞면 디자인을 이미지로 인식해 상품 식별. 기기 안에서만 처리 | 카드번호가 찍히므로 사진은 서버로 보내지 않음 |
| 데이터 플랫폼 | Databricks. 카드 상품 수집·정제 파이프라인에 쓰고 나중에 결제 데이터 분석까지 확장 | 학습 목적 겸 분석 기반 |
| 아이콘 | 스타크래프트1 디파일러 기술 "컨슘" 아이콘의 실루엣을 따른 일러스트. 살구색 벌레, 꼬리 고리 안에 체리 두 알. 투명 배경 PNG `design/icon.png`, 원본 `design/icon-source.webp` | 스타1 유저가 알아봐야 함 |

## 3. 조사로 확인된 제약

- 카드 상품 단위 공공 데이터는 없다. 여신금융협회 공시는 카드사 단위 수수료율만, 금감원 금융상품한눈에는 카드를 다루지 않는다. 1차 출처는 카드사별 상품공시실 페이지다.
- 삼성카드와 BC카드는 robots.txt로 크롤러를 전면 차단한다. 신한, KB국민, 하나, 우리는 상품 목록을 자바스크립트로 그려서 브라우저 자동화나 내부 JSON 호출이 필요하다. 롯데, 현대, NH농협은 봇 접근을 막아 구조를 확인하지 못했다.
- 카드고릴라의 비공개 JSON API는 남의 데이터라 서비스 기반으로 쓰지 않는다. 저작권과 부정경쟁방지법 위험이 있다.
- Databricks Free Edition은 약관에 상업적 이용 금지가 명시되어 있다. 개발 단계에만 쓰고 출시 뒤에는 종량제로 옮기거나 같은 코드를 다른 실행 환경에서 돌린다. Snowflake는 영구 무료 티어가 없다.
- 카드 플레이트 이미지는 카드사 저작물이다. 앱에는 이미지가 아니라 인식용 벡터만 넣고, 화면에 플레이트 이미지를 띄우는 것은 카드사 허락을 받기 전까지 하지 않는다.
- 카드 발급 제휴 링크를 넣으면 여신전문금융업법상 모집 규제와 금소법 중개 판단 문제가 생긴다. 수익 모델을 정할 때 다시 검토한다.
- 아이콘은 블리자드 저작물을 참고한 오마주다. 원본 픽셀을 복제하지 않았지만 문제 제기 가능성은 남아 있음을 알고 간다.

## 4. 전체 구조

```
[Flutter 앱]  ──HTTPS──▶  [FastAPI 서버]  ──▶  [Postgres]
   카드 등록·결제 입력         인증, 실적·추천 계산       사용자, 카드, 결제, 카탈로그
   카메라 인식(기기 내)        카탈로그 조회 API
        ▲                          │ 매일 밤 가명처리한 Parquet 내보내기
        │ 인식용 벡터 파일           ▼
        │                    [오브젝트 스토리지]
        │                     ▲            │ Auto Loader
        └─────────────────────┘            ▼
                            [Databricks: Python 파이프라인]
                              ① 카드사 수집 → 정제 → LLM 혜택 추출 → 사람 검수 → 카탈로그·벡터 발행
                              ② 사용자 로그 브론즈 → 실버 → 분석 테이블
```

책임 분리
- Flutter 앱: 화면, 입력, 카메라 인식. 계산 로직은 갖지 않는다.
- FastAPI 서버: 인증, 결제 저장, 실적·추천 계산, 카탈로그 조회. 계산은 `cherry_core` 패키지를 불러 쓴다.
- Postgres: 사용자, 보유 카드, 결제, 카탈로그 스냅샷.
- 파이프라인: 카드사 페이지에서 상품 정보를 모아 카탈로그 YAML을 만들고 서버 DB에 적재한다. 카드 플레이트 이미지의 임베딩 벡터도 여기서 만든다.
- 오브젝트 스토리지: 인식용 벡터 파일과 사용자 로그 내보내기 파일. 앱은 벡터 파일만 내려받는다.

인증 방식, 서버 호스팅, 카탈로그 갱신 주기는 하위 프로젝트 2와 3 스펙에서 정한다.

### 4.1 사용자 로그 적재

분석 대상은 세 가지다. 결제 기록, 추천 요청과 그때 사용자가 실제로 고른 카드, 보유 카드의 추가·삭제. 화면 이동 같은 일반 앱 이벤트는 1차에서 다루지 않는다. 서버는 추천 요청마다 입력 업종·가게·금액과 추천 순위, 그리고 사용자가 고른 카드를 기록한다.

흐름
1. 서버가 매일 밤 전날 분을 Parquet로 오브젝트 스토리지에 내보낸다. 내보내기 시점에 가명처리한다. 사용자 식별자는 솔트를 섞은 해시로 바꾸고 이메일 등 식별 정보는 내보내지 않는다.
2. Databricks Auto Loader가 새 파일을 읽어 브론즈 테이블에 그대로 쌓고, 실버 테이블에서 형식을 맞춘다.
3. 분석 테이블은 필요할 때 만든다. 첫 질문은 "추천 1순위를 실제로 얼마나 따르는가"와 "실적 부족 경고 뒤 결제가 늘어나는가"다.

Databricks가 운영 DB에 직접 붙지 않는 이유는 DB 자격 증명을 밖으로 내보내지 않고 가명처리를 한 지점에서만 하기 위해서다.

법적 조건. 가명정보는 개인정보보호법의 특례로 통계·연구 목적에 쓸 수 있지만 개인정보처리방침에 분석 목적과 가명처리 사실을 적어야 한다. 탈퇴 시 운영 DB 데이터는 삭제하고, 이미 가명처리된 분석 데이터는 개인을 알아볼 수 없으므로 보존한다.

코드는 하위 프로젝트 3에서 카탈로그 파이프라인과 함께 만든다. 실제 가동은 유료 Databricks로 옮긴 뒤에 한다. Free Edition은 실서비스 데이터에 쓸 수 없다.

앱 DB를 뒤에 Databricks Lakebase로 옮기면 이 내보내기 흐름은 Databricks가 제공하는 테이블 동기화로 대체할 수 있다. 그 경우 가명처리를 동기화 뒤 Delta 쪽에서 한 번 수행하는 것으로 위치만 바뀌고, 가명처리를 한다는 원칙은 같다.

### 4.2 앱 DB 운영 방식

앱 DB는 Postgres다. ERD와 서버 코드는 Postgres 표준 기능만 쓴다. 특정 서비스의 확장 기능이나 전용 문법은 쓰지 않는다. 이렇게 두면 어느 관리형 Postgres 사이에서도 덤프와 복원으로 옮길 수 있다.

**Databricks의 Delta 테이블과 SQL 웨어하우스는 앱 DB로 쓰지 않는다.** 분석용 저장소라 결제 한 건을 넣고 바로 읽는 요청에 느리고, 동시 쓰기에 약하며, 웨어하우스를 상시 켜 두는 비용이 앱 규모에 맞지 않는다. FastAPI가 요청마다 웨어하우스를 부르는 구조는 만들지 않는다.

운영은 두 단계로 간다.

| 단계 | 어디에 | 언제 | 이유 |
|---|---|---|---|
| 1 | 무료 구간이 있는 관리형 Postgres. Neon, Supabase 같은 곳 | 출시부터 | 수익이 없는 동안 고정 비용을 만들지 않는다. 사용자 수백 명까지 무료 구간 안에서 돈다 |
| 2 | Databricks Lakebase | 분석 데이터가 쌓여 4.1절 동기화가 실제로 필요해질 때 | Lakebase는 Databricks 안의 관리형 Postgres라 스키마를 그대로 옮길 수 있고, Delta와의 동기화가 붙어 있어 내보내기 코드가 사라진다. 계정과 청구가 하나로 합쳐진다 |

2단계로 넘어갈 때 확인할 것. Lakebase의 요금 구조, 서울 리전 제공 여부, 안 쓸 때 0으로 줄어드는 과금이 실제로 어느 수준인지. 이 셋은 옮기기로 정하는 시점에 확인하고 여기에 적는다.

옮기는 절차는 1단계 DB를 덤프해 Lakebase에 복원하고, 서버의 접속 문자열만 바꾸는 것이다. 표준 기능만 썼다면 코드 변경은 없다.

## 5. 하위 프로젝트 분해

의존 순서대로 진행한다. 각 하위 프로젝트는 별도 스펙과 구현 계획을 가진다.

| 순서 | 하위 프로젝트 | 완료 기준 |
|---|---|---|
| 1 | 카탈로그 스키마 + 카드 20장 수동 입력 + 실적·추천 계산 엔진 | 20장 예제 결제의 추천 금액과 실적 잔액이 손계산과 일치하는 테스트 통과 |
| 2 | FastAPI 서버 + Flutter 앱 MVP. 인증, 카드 검색·등록, 결제 직접 입력, 이용 내역 엑셀 가져오기, 실적 현황, 가게별 추천 | 실제 폰에서 카드 등록부터 추천까지 한 흐름이 동작하고, 카드사 웹에서 받은 엑셀 한 달치가 중복 없이 들어감 |
| 3 | Databricks 파이프라인. ① 카드사 수집 → 정제 → LLM 혜택 추출 → 검수 → 카탈로그 적재 ② 사용자 로그 내보내기 → Auto Loader → 브론즈·실버 | ① 카드사 3곳 이상의 발급 중 카드가 자동 적재되고 스키마 검증 통과 ② 하루치 로그가 다음 날 실버 테이블에서 조회됨 |
| 4 | 카메라 카드 인식. 기기 내 임베딩 + 최근접 이웃 | 카탈로그에 있는 카드 실물 사진 20장 중 18장 이상을 1순위로 맞춤 |
| 5 | 출시 준비. 개인정보처리방침, 스토어 등록, 아이콘 내보내기 | Play 스토어 심사 통과 |

파이프라인을 3번에 두는 이유: 스키마가 추천 계산에 맞는지 20장으로 먼저 증명하지 않으면 수천 장을 수집한 뒤 스키마를 고치게 된다.

## 6. 하위 프로젝트 1 상세 설계

### 6.1 범위와 성공 기준

DB도 웹도 없는 순수 Python 패키지 `cherry_core`. 입력은 카탈로그 파일과 결제 목록, 출력은 카드별 실적 현황과 가게별 추천 순위다.

성공 기준
- 카드 20장의 공식 안내 문구로 만든 예제 결제에서 추천 금액과 실적 잔액이 손계산과 일치하는 테스트가 전부 통과한다.
- 카탈로그 YAML 20개가 스키마 검증을 통과한다.

### 6.2 저장소 구조

```
cherryConsume/
  backend/
    pyproject.toml
    cherry_core/
      models.py        # Pydantic 모델
      categories.py    # 업종 목록과 카카오 업종 코드 대응
      catalog.py       # YAML 로더와 검증
      spend.py         # 실적 계산
      recommend.py     # 추천 계산
    tests/
  catalog/
    cards/<카드사>-<상품 슬러그>.yaml
    merchants.yaml     # 가게 이름 별칭표
    categories.yaml    # 업종 목록
  design/
  docs/
```

`backend/`는 뒤에 FastAPI 패키지 `cherry_api`가 추가될 자리다.

### 6.3 데이터 모델

모두 Pydantic 모델. 금액 단위는 원, 정수.

**Card 카드**

| 필드 | 타입 | 설명 |
|---|---|---|
| id | str | `<카드사>-<슬러그>`. 파일 이름과 같음 |
| issuer | str | 카드사 코드. shinhan, samsung, hyundai, kb, lotte, hana, woori, nh, bc, ibk 등 |
| name | str | 상품 이름 |
| kind | credit / check | 신용·체크 |
| annual_fee_domestic | int | 국내전용 연회비. 없으면 0 |
| annual_fee_global | int | 해외겸용 연회비. 없으면 0 |
| active | bool | 발급 중 여부 |
| source_url | str | 공식 안내 URL |
| updated_at | date | 카탈로그 갱신일 |
| spend_basis | prev_calendar_month / unsupported | 실적 기준. 전월 달력 월이 아닌 카드는 unsupported |
| spend_tiers | SpendTier[] | 실적 구간. 하한 오름차순. 최소 1개 |
| spend_rule | SpendRule | 실적 인정 규칙 |
| benefits | Benefit[] | 혜택 목록 |

**SpendTier 실적 구간**

| 필드 | 타입 | 설명 |
|---|---|---|
| min_spend | int | 전월 인정 실적 하한. 실적 무관 카드는 0 하나 |
| integrated_cap | int 또는 null | 이 구간의 월 통합 할인한도. 없으면 null |

**SpendRule 실적 인정 규칙**

| 필드 | 타입 | 설명 |
|---|---|---|
| excluded_categories | Category[] | 실적에서 빼는 업종. tax, utility, gift_card, insurance, apartment_fee, annual_fee 등 |
| exclude_interest_free_installment | bool | 무이자할부 결제를 실적에서 빼는지 |
| exclude_discounted | bool | 혜택을 받은 결제 건을 실적에서 빼는지 |
| installment_basis | full_at_purchase / per_installment_month | 할부 실적 인정 방식. 결제 당월 전액, 또는 매달 할부금만 |
| cancellation_basis | cancel_month / original_month | 취소 금액을 빼는 달. 취소한 달, 또는 원 결제 달 |

**Benefit 혜택**

| 필드 | 타입 | 설명 |
|---|---|---|
| id | str | 카드 안에서 고유 |
| title | str | 사람이 읽는 이름 |
| target_type | category / merchant / all | 대상 종류 |
| target_values | str[] | 업종 코드 또는 가게 별칭 키. all이면 빈 목록 |
| channel | online / offline / any | 결제 채널 |
| kind | discount / points / cashback | 종류 |
| rate_pct | float 또는 null | 정률. 정액과 둘 중 하나만 |
| fixed_amount | int 또는 null | 정액 |
| min_txn_amount | int | 건당 최소 결제액. 없으면 0 |
| max_per_txn | int 또는 null | 건당 최대 혜택 |
| monthly_cap_amount | int 또는 null | 월 한도 금액 |
| monthly_cap_count | int 또는 null | 월 한도 횟수 |
| daily_cap_count | int 또는 null | 일 한도 횟수 |
| min_tier_index | int | 필요한 실적 구간의 인덱스. 0이면 실적 무관 |
| counts_toward_integrated_cap | bool | 통합 한도에 포함되는지. 기본 true |
| conditions_not_modeled | bool | 주말·시간대 등 계산에 넣지 않은 조건이 있는지. 기본 false |
| notes | str | 원문 조건 메모. conditions_not_modeled가 참이면 필수 |

**Transaction 결제**

| 필드 | 타입 | 설명 |
|---|---|---|
| id | str | UUID |
| card_id | str | |
| amount | int | |
| merchant_name | str | 사용자가 적은 가게 이름 |
| category | Category | 업종. 별칭표나 카카오 코드로 정하고 없으면 other |
| paid_at | datetime | 시간대 포함 |
| installment_months | int | 할부 개월. 일시불은 1 |
| interest_free_installment | bool | 무이자할부 여부 |
| cancelled_amount | int | 취소·환불 금액. 기본 0 |
| cancelled_at | datetime 또는 null | 취소 시각 |
| channel | online / offline | |
| approval_no | str 또는 null | 카드사 승인번호. 엑셀 가져오기 중복 판정에 씀 |
| import_batch_id | str 또는 null | 엑셀 가져오기로 들어온 건이면 그 배치 |
| applied_benefit_id | str 또는 null | 입력 시점에 계산한 적용 혜택 |
| estimated_benefit | int | 입력 시점에 계산한 예상 혜택 금액 |

**UserCard 보유 카드**

| 필드 | 타입 | 설명 |
|---|---|---|
| card_id | str | |
| assumed_prev_month_spend | int 또는 null | 등록한 달에 쓰는 전월 실적 추정값 |

**출력 모델**

SpendStatus: card_id, month, counted_spend, current_tier_index, next_tier_min_spend 또는 null, remaining_to_next 또는 null, warnings[]

Recommendation: card_id, expected_benefit, applied_benefit_id 또는 null, remaining_monthly_cap 또는 null, counts_toward_spend, remaining_to_next 또는 null, warnings[]

### 6.4 업종과 가게 별칭

업종 `Category`는 고정 목록이다. 1차 목록과 카카오 로컬 API 업종 코드 대응은 다음과 같다.

| 코드 | 뜻 | 카카오 코드 |
|---|---|---|
| cafe | 카페 | CE7 |
| convenience | 편의점 | CS2 |
| restaurant | 음식점 | FD6 |
| delivery_app | 배달앱 | 없음. 별칭표로 |
| grocery_mart | 마트 | MT1 |
| department_store | 백화점 | 없음. 별칭표로 |
| online_shopping | 온라인 쇼핑 | 없음. 별칭표로 |
| fuel | 주유 | OL7 |
| public_transit | 대중교통 | SW8 |
| taxi | 택시 | 없음. 별칭표로 |
| telecom | 통신 | 없음. 별칭표로 |
| streaming | 구독·스트리밍 | 없음. 별칭표로 |
| movie | 영화 | CT1 |
| hospital | 병원 | HP8 |
| pharmacy | 약국 | PM9 |
| education | 교육 | AC5 |
| travel_airline | 항공 | 없음. 별칭표로 |
| hotel | 숙박 | AD5 |
| overseas | 해외 | 없음 |
| utility | 공과금 | 없음 |
| tax | 세금 | 없음 |
| insurance | 보험료 | 없음 |
| gift_card | 상품권 | 없음 |
| apartment_fee | 아파트관리비 | 없음 |
| annual_fee | 연회비 | 없음 |
| other | 기타 | 그 외 전부 |

카카오 코드 대응은 근사치이며, 별칭표에 걸리면 별칭표의 업종이 우선한다.

`merchants.yaml`은 가게 이름 별칭을 특정 가맹점 키와 업종에 연결한다. 예를 들어 "스타벅스", "스벅", "STARBUCKS"는 가맹점 키 starbucks와 업종 cafe로 연결한다. 결제의 가게 이름에 별칭 문자열이 포함되면 일치로 본다. 비교할 때 공백과 대소문자는 무시한다. 여러 별칭이 걸리면 가장 긴 별칭을 택한다.

### 6.5 계산 규칙

실적 월은 결제일 기준 달력 월이다.

실적 인정 여부 `countable(t, card)`
- 업종이 `excluded_categories`에 없고
- 무이자할부 제외 카드면 무이자할부 결제가 아니고
- 혜택 건 제외 카드면 `estimated_benefit`가 0인 결제

결제 한 건이 어느 달에 얼마를 실적에 넣는지 `contribution(t, month)`
- 일시불이거나 카드의 `installment_basis`가 `full_at_purchase`면 결제 달에 `amount` 전액, 다른 달은 0
- `per_installment_month`면 결제 달부터 `installment_months`개월 동안 매달 `amount / installment_months`를 원 단위로 내림해 넣고 나머지는 마지막 달에 넣음
- 취소가 있으면 카드의 `cancellation_basis`에 따라 뺀다. `cancel_month`면 `cancelled_at`이 속한 달에서 `cancelled_amount`를, `original_month`면 결제 달에서 `cancelled_amount`를 뺀다

이번 달 인정 실적 `counted_spend(card, month)` = `countable`인 결제들의 `contribution(t, month)` 합. 0보다 작으면 0

이번 달 적용 구간 `current_tier(card, month)` = `counted_spend(card, month - 1)` 이상인 `min_spend` 중 가장 큰 구간. 전월 결제가 하나도 없고 `assumed_prev_month_spend`가 있으면 그 값을 쓰고, 둘 다 없으면 0번 구간에 경고 `no_prev_month_data`를 붙인다.

다음 구간 잔액 `remaining_to_next` = 다음 구간 `min_spend` − `counted_spend(card, month)`. 마지막 구간이면 null.

혜택 후보 `eligible(b, t, card, month)`
- 대상 일치. all이면 항상, category면 업종 일치, merchant면 가게 별칭 키 일치
- 채널 일치. any면 항상
- `amount >= min_txn_amount`
- `current_tier_index >= min_tier_index`
- 일 한도가 있으면 같은 날 그 혜택 적용 건수가 한도 미만
- 월 횟수 한도가 있으면 그 달 적용 건수가 한도 미만
- 월 금액 한도가 있으면 남은 금액이 0보다 큼

혜택 금액 `value(b, t, card, month)`
1. 기본값 = `rate_pct` × `amount`를 원 단위로 내림, 또는 `fixed_amount`
2. `max_per_txn`이 있으면 그 값으로 자름
3. `monthly_cap_amount`가 있으면 남은 월 한도로 자름. 남은 한도 = 한도 − 그 달 이 혜택으로 받은 `estimated_benefit` 합
4. `counts_toward_integrated_cap`이고 구간에 `integrated_cap`이 있으면 남은 통합 한도로 자름. 남은 통합 한도 = 한도 − 그 달 이 카드에서 통합 한도에 포함되는 `estimated_benefit` 합

카드 기대 혜택 `expected(card, t, month)` = 후보 혜택의 `value` 중 최댓값. 한 카드 안에서 혜택은 중복 적용하지 않는다. 후보가 없으면 0.

추천 정렬
1. `expected` 내림차순
2. 같으면 이 결제가 실적에 잡히고 `remaining_to_next`가 0보다 큰 카드를 앞에, 그중 잔액이 작은 카드를 앞에
3. 그래도 같으면 카드 id 순

경고 코드
- `not_counted_toward_spend`: 이 결제는 실적 제외
- `monthly_cap_exhausted`: 이번 달 한도 소진으로 혜택 0
- `tier_not_met`: 전월실적 미충족으로 해당 혜택 불가
- `no_prev_month_data`: 전월 데이터 없어 최저 구간으로 계산
- `conditions_not_modeled`: 계산에 넣지 않은 조건이 있어 실제와 다를 수 있음
- `spend_basis_unsupported`: 이 카드의 실적 기준은 계산하지 않음
- `default_amount_used`: 금액이 없어 1만 원 기준으로 계산

포인트와 마일리지는 1차에서 1포인트 = 1원으로 보고 정렬한다. 결제를 저장할 때 계산한 `applied_benefit_id`와 `estimated_benefit`은 카탈로그가 바뀌어도 다시 계산하지 않는다.

시나리오 검토에서 추가한 규칙. 근거는 `docs/scenarios.md`.
- 카드를 등록한 달에는 입력된 전월 결제가 1건 이상이면 그 합계를 전월 실적으로 쓰고, 없을 때만 추정값을 쓴다. 다음 달부터는 입력된 결제만 본다. (E2)
- 할부는 카드의 `installment_basis`를 따른다. 카드사마다 다르므로 카탈로그에 카드별로 적는다. (E4)
- 취소는 카드의 `cancellation_basis`를 따른다. `original_month`로 전월 실적이 줄면 이번 달 적용 구간도 다시 정한다. `cancel_month`면 이번 달 구간은 그대로다. 전액 취소된 결제의 `estimated_benefit`은 0으로 되돌려 한도 사용량에서 뺀다. (E5)
- `spend_basis`가 `unsupported`인 카드는 실적 계산을 하지 않고 `min_tier_index`가 0인 혜택만 추천에 넣는다. (E6)
- 월 경계는 한국 시간 기준이다. (E7)
- 추천에 금액이 없으면 1만 원을 기준 금액으로 계산하고 결과에 표시한다. (E11)
- `conditions_not_modeled`가 참인 혜택은 조건이 없는 것처럼 계산하되 결과에 `conditions_not_modeled` 경고를 붙인다. (E12)

### 6.6 카탈로그 파일

카드 한 장이 YAML 파일 하나. 구조를 보이기 위한 예시이며 값은 실제 상품과 무관하다.

```yaml
id: ibk-narasarang
issuer: ibk
name: IBK 나라사랑카드
kind: check
annual_fee_domestic: 0
annual_fee_global: 0
active: true
source_url: https://example.invalid/narasarang
updated_at: 2026-09-19
spend_tiers:
  - { min_spend: 0, integrated_cap: null }
  - { min_spend: 200000, integrated_cap: 10000 }
spend_rule:
  excluded_categories: [tax, utility, gift_card, insurance, annual_fee]
  exclude_interest_free_installment: false
  exclude_discounted: false
  installment_basis: full_at_purchase
  cancellation_basis: cancel_month
benefits:
  - id: cafe-10
    title: 카페 10% 할인
    target_type: category
    target_values: [cafe]
    channel: any
    kind: discount
    rate_pct: 10
    fixed_amount: null
    min_txn_amount: 5000
    max_per_txn: 2000
    monthly_cap_amount: 5000
    monthly_cap_count: null
    daily_cap_count: 1
    min_tier_index: 1
    counts_toward_integrated_cap: true
    notes: 예시 값
```

로더는 파일마다 스키마 검증을 하고 실패하면 파일 이름과 필드 경로를 찍고 즉시 멈춘다. 추가 검증
- `spend_tiers`는 `min_spend` 오름차순이고 첫 구간은 0
- `rate_pct`와 `fixed_amount`는 둘 중 하나만
- `min_tier_index`는 구간 개수 미만
- `target_type`이 all이면 `target_values`는 비어 있고, 아니면 1개 이상
- category 대상 값은 업종 목록에, merchant 대상 값은 별칭표 키에 있어야 함

이 파일 형식은 하위 프로젝트 3 파이프라인의 출력 형식이 된다.

### 6.7 초기 카드 20장

사용자 보유 카드인 IBK 나라사랑카드를 반드시 넣는다. 나머지 19장은 카드사별 대표 카드에서 고른다. 아래는 시작 후보이며, 구현 시점에 카드사 공식 페이지에서 발급 중인지 확인하고 단종된 카드는 같은 카드사의 다른 카드로 바꾼다.

- IBK: 나라사랑카드 체크
- 신한: Mr.Life, 처음, Point Plan
- 삼성: taptap O, iD ON
- 현대: ZERO Edition3 할인형, M, the Green
- KB국민: My WE:SH, 청춘대로 톡톡, Easy all 티타늄
- 롯데: LOCA 365, LOCA LIKIT 1.2
- 하나: 원더카드 Daily+, 트래블로그 체크
- 우리: 카드의정석 EVERY DISCOUNT, 카드의정석 쿠키 체크
- NH농협: zgm.히어로
- 카카오뱅크: 프렌즈 체크

혜택 값은 각 카드사 공식 안내 문구에서 옮기고 `source_url`과 `notes`에 근거를 남긴다.

### 6.8 오류 처리

- 카탈로그 로딩은 실패 즉시 중단한다. 잘못된 카탈로그로 추천을 계산하지 않는다.
- 엔진 함수는 예외를 던지지 않는 순수 함수다. 알 수 없는 업종은 other로 본다. 카탈로그에 없는 `card_id`의 결제는 건너뛰고 경고 목록에 남긴다.
- 금액이 0 이하인 결제는 모델 검증에서 거부한다.

### 6.9 테스트

pytest.
- 카드별 표 테스트. 카드마다 예제 결제와 기대 `expected`, `applied_benefit_id`, `counted_spend`, `remaining_to_next`를 YAML 픽스처로 적고 한 테스트 함수가 전부 돈다
- 규칙 테스트. 혜택은 `max_per_txn`, 남은 월 한도, 남은 통합 한도를 넘지 않는다. 제외 업종은 실적에 잡히지 않는다. 같은 입력은 같은 출력을 낸다
- 로더 테스트. 잘못된 카탈로그 파일이 어떤 필드에서 실패하는지 확인

### 6.10 1차에서 미루는 것

주말·시간대 조건, 여러 카드 사이의 혜택 중복 계산, 해외 결제 수수료, 포인트의 원화 환산율, 카탈로그 변경 시 과거 결제 재계산. 스키마에 해당 필드를 두지 않고 필요할 때 추가한다.

## 7. 열어둔 위험

- 카드사 페이지 수집의 약관·기술 장벽. 삼성·BC는 다른 경로가 필요하다.
- Databricks 출시 뒤 비용. 카탈로그 주간 갱신 수준이면 종량제 서버리스 비용은 작다고 보지만 실측 전이다.
- 카드 플레이트 이미지와 아이콘의 저작권.
- 개인 결제 내역을 서버에 저장하므로 개인정보처리방침, 암호화, 탈퇴 시 삭제가 출시 요건이 된다.
- 관리형 Postgres 무료 구간의 조건이 바뀔 수 있다. 사용자 수가 무료 구간 상한에 가까워지면 유료 전환이나 Lakebase 이전 중 하나를 미리 정한다.

## 8. 이용 내역 엑셀 가져오기

### 왜 필요한가

수동 입력은 법적 부담과 운영비가 없지만 귀찮아서 이탈을 부른다. 자동 수집의 정석인 마이데이터는 금융위 본허가가 필요하고 2024년부터 정보 제공이 유료화되어 1인 개발 서비스가 감당할 수 없다. 이 둘 사이에 있는 길이 사용자가 직접 내려받은 이용 내역 파일을 올리는 것이다. 허가도 사용료도 필요 없고, 한 달치 결제를 한 번에 넣을 수 있다.

### 어디서 받은 파일인가

- 카드사 PC 웹의 이용 내역 조회. 대부분 기간을 정해 엑셀로 내려받을 수 있다
- 토스, 뱅크샐러드 같은 마이데이터 앱의 내보내기. 여러 카드사가 한 파일에 담기지만 형식은 앱마다 다르다

카드사와 앱마다 열 이름과 순서, 날짜 형식, 금액 표기가 다르다. 카드사별 매핑 표를 카탈로그처럼 관리하고, 표에 없는 형식은 사용자가 화면에서 열을 직접 짝지을 수 있게 한다.

### 어떻게 처리하나

1. 사용자가 파일을 고르고 어느 카드의 내역인지 지정한다. 여러 카드가 섞인 파일이면 카드 이름 열로 나눈다
2. 열 매핑. 결제일, 가맹점명, 금액, 할부 개월, 취소 여부, 승인번호를 찾는다. 매핑 표에 있으면 자동, 없으면 사용자가 짝짓는다
3. 행마다 결제 모델로 바꾼다. 가맹점명은 별칭표와 카카오 업종 코드로 업종을 정하고 못 정하면 other로 두고 나중에 고칠 수 있게 표시한다
4. 중복 제거. 승인번호가 있으면 그것으로, 없으면 카드·결제일시·금액·가맹점명이 같으면 같은 건으로 본다. 이미 수동으로 넣은 결제와도 겹치면 파일 쪽을 버리고 사용자에게 몇 건이 겹쳤는지 알린다
5. 취소 행은 원 결제를 찾아 `cancelled_amount`와 `cancelled_at`으로 붙인다. 원 결제를 못 찾으면 사용자에게 보여 주고 넘긴다
6. 미리보기 화면에서 건수, 합계, 업종 미분류 건수, 중복 건수를 보여 주고 확인을 받은 뒤 저장한다. 저장하면 실적과 한도가 다시 계산된다

### 어디서 처리하나

파싱은 서버에서 한다. 앱은 파일을 올리고 미리보기를 보여 주기만 한다. 이유는 매핑 표를 서버에서 갱신해야 카드사가 형식을 바꿔도 앱을 다시 배포하지 않기 때문이다. 올린 파일은 파싱이 끝나면 즉시 지우고 저장하지 않는다. 파일에는 카드번호 일부와 가맹점명이 들어 있어 개인정보처리방침에 "파싱 후 즉시 삭제"를 명시한다.

### 하지 않는 것

카드사 사이트에 로그인해 대신 내려받는 자동화는 하지 않는다. 금융 분야 스크래핑은 마이데이터 시행 뒤 금지되었고 카드사 약관에도 어긋난다. 파일은 항상 사용자가 직접 받아 올린다.

### 언제 하나

하위 프로젝트 2의 MVP에 처음부터 넣는다. 직접 입력만으로 출시하면 첫 달 이탈이 크다고 보기 때문이다. 범위는 서버 API 하나, 카드사별 매핑 표, 앱의 파일 선택·열 짝짓기·미리보기 화면이다. 매핑 표는 초기 카탈로그 20장의 카드사부터 채운다.

### 기록 남기기

가져오기 한 번이 `import_batches` 한 행이다. 출처, 파일 이름, 행 수, 저장 건수, 중복 건수를 남기고, 들어온 결제마다 `import_batch_id`를 달아 배치 단위로 되돌릴 수 있게 한다. 승인번호는 `transactions.approval_no`에 넣어 다음 가져오기의 중복 판정에 쓴다.
