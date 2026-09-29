# 001 카탈로그 틀 2판 설계

1절부터 4절까지 절마다 사용자 확인을 받아 확정했다. 2026-09-28 전체 검토에서 절 사이의 이름과 규칙을 맞췄다.

## 방식

개정 이력이 있는 규칙 문서로 한다. 2026-09-28 확정.

카드 한 장에 개정 목록을 둔다. 개정 하나는 적용 시작일부터의 규칙 전체다. 조건, 한도, 중복 규칙은 종류가 정해진 블록으로 적는다. 카드사가 혜택을 바꾸면 새 개정을 추가하고 적용 시작일을 적는다. 지난달 실적은 지난달 규칙으로 계산해야 하므로 옛 개정은 지우지 않는다.

검토한 다른 방식
- 1판 틀에 칸을 더하는 방식은 바로 쓸 수 있지만 구간별 복제가 남고, 새 조건이 나올 때마다 DB 테이블을 고쳐야 한다.
- 규칙 전용 식 언어는 표현력이 가장 크지만 해석기를 따로 만들어야 하고 AI 추출과 사람 검수가 어렵다.

## 1절 파일 구조와 갱신 흐름

2026-09-28 확정.

### 파일

```
catalog/
  categories.yaml        업종. 2단 트리
  merchants.yaml         가맹점과 별칭
  payment_methods.yaml   결제수단과 이용 내역에 찍히는 이름. 3.1
  point_programs.yaml    포인트 종류와 1포인트 가치
  reference.yaml         리터당 기름값처럼 계산에 쓰는 기준값
  issuers/<카드사>.yaml   카드사 공통 규칙과 수집 설정
  cards/<카드사>/<카드 id>.yaml
```

카드사 파일
- 공통 규칙을 적는다. 실적 제외 목록, 할부와 취소를 어느 달에 반영하는지, 교통카드 이용액을 전전월 실적에 넣는 규칙, 신규 발급 특례, 간편결제 가맹점명 제외 같은 것이다. 20장에서 신한, KB, 현대는 이런 규칙이 카드마다 거의 같았다.
- 카드 파일에 없는 항목은 카드사 값을 쓴다. 카드 파일에 적은 항목은 그 항목만 덮어쓴다.
- 공통 규칙은 `defaults` 목록에 적용 시작일과 함께 둔다. 카드사가 공통 규칙을 바꾸면 새 항목을 더한다. 해석기는 카드 개정 날짜와 카드사 기본값 날짜를 합친 날짜마다 개정 하나를 만든다.
- 결제일 기준 실적 카드가 있는 카드사는 결제일별 이용기간 표 `billing_cycles`를 둔다. 2.10
- 수집 설정을 적는다. 상품 목록 주소, 수집 방법, 갱신 주기, 부가서비스 변경 공지 주소다. 수집 방법은 api, browser, manual, blocked 중 하나다.

카드 파일 윗부분

```yaml
schema_version: 2
id: shinhan-mrlife
issuer: shinhan
name: 신한카드 Mr.Life
search_names: [미스터라이프]
kind: credit
product_codes: ["201509030001"]  # 카드사 내부 상품 코드. 갱신 때 같은 카드를 찾는 열쇠
status: on_sale                  # on_sale 발급 중 / discontinued 신규 발급 중단 / closed 서비스 종료
annual_fees:
  - { brand: amex, scope: domestic, form: physical, amount: 15000 }
sources:
  - id: page
    kind: product_page           # product_page, manual_pdf, terms_pdf, promo_page, notice, api
    url: https://...
    fetched_at: 2026-09-28
    text_sha256: 3f1a...         # 본문 지문
    review_no: 제2026-C1a-09920호  # 심의필 번호
checked_at: 2026-09-28           # 원문과 마지막으로 대조한 날
revisions:
  - effective_from: 2026-07-01
    # 실적 규칙, 구간, 한도, 혜택. 2절
open_questions:
  - { path: revisions[0].spend.cancellation, question: 취소를 어느 달 실적에서 빼는지, assumed: cancel_month }
```

- 본문 지문은 광고와 날짜를 걷어 낸 본문의 해시다. 내용이 바뀌었는지 판단하는 데 쓴다.
- 심의필 번호는 카드사 광고가 여신금융협회 심의를 받았다는 번호다. 유효기간이 끝날 때 페이지도 바뀌는 경우가 많다.
- 1판 notes에 흩어져 있던 "공식 문구 미확인"은 `open_questions`로 모은다.

### 갱신 흐름

1. 카드사 단위로 상품 목록을 받아 `product_codes`로 기존 카드와 짝을 맞춘다. 처음 보는 카드는 초안으로 만든다. 목록에서 사라진 카드는 지우지 않고 발급 중단 후보로 검수를 기다린다. 이미 가진 사람은 계속 혜택을 받기 때문이다.
2. 카드 단위로 원문마다 본문 지문을 비교한다. 같으면 `checked_at`만 고치고 끝낸다. 다르면 혜택을 다시 뽑아 검증하고 현재 개정과 비교한 뒤 사람이 검수해 새 개정으로 발행한다.
3. 여신전문금융업법상 부가서비스를 줄이려면 6개월 전부터 알려야 한다. 이 공지에서 시행일을 읽어 미래 개정을 미리 넣는다.
4. 혜택 key는 갱신해도 유지한다. 결제 기록이 개정과 혜택 key를 가리킨다.
5. 같은 갱신을 두 번 돌려도 파일이 바뀌지 않게 저장 형식을 고정한다. git 차이에는 실제 변경만 보인다.
6. 주기는 카드사마다 14일이나 30일이다. 행사 종료 2주 전, 심의필 유효기간 만료, 미해결 질문이 남은 카드는 주기와 상관없이 다시 본다.

## 2절 혜택 규칙

2026-09-28 확정. 20장 초안에서 1판이 담지 못한 규칙을 전부 담는 것이 기준이다.

### 2.1 개정 하나에 들어가는 것

```yaml
revisions:
  - effective_from: 2026-07-27      # 이날 한국 시간 0시부터
    effective_from_estimated: false # 시행일을 몰라 발견한 날을 넣었으면 true
    source: page                    # 이 개정의 근거 원문. sources의 id
    # patch: {...}                  # 두 번째 개정부터는 바뀌는 곳만 적을 수 있다. 2.12
    tiers: [0, 80000, 200000, 250000, 500000, 1000000]   # 구간 하한
    spend: {...}              # 2.10 실적 규칙
    new_card: {...}           # 2.10 신규 발급 특례
    benefit_exclusions: {...} # 2.11 모든 혜택에서 빠지는 결제
    facts: [...]              # 2.9 사용자에게 묻는 사실
    options: [...]            # 2.8 사용자가 고르는 것
    ranked: [...]             # 2.8 이번 달 이용액 순 자동 선택
    limits: [...]             # 2.6 여러 혜택이 같이 쓰는 한도
    stacks: [...]             # 2.7 중복 묶음
    benefits: [...]
    unmodeled: [...]          # 2.13 계산하지 못하는 카드 전체 조건
```

카드사 파일의 `defaults`는 이 중 `spend`, `new_card`, `benefit_exclusions`를 채울 수 있다. 카드 개정에 적은 항목은 그 항목만 덮어쓴다.

### 2.2 구간과 구간표 값

`tiers`는 구간 하한 목록이다. 화면에서는 "30만 구간"처럼 하한으로 부른다.

구간마다 달라지는 숫자는 구간 하한을 키로 한 표로 적는다. 어떤 구간의 값은 그 구간 하한 이하인 키 중 가장 큰 키의 값이다. 숫자가 들어가는 칸은 전부 숫자 하나나 구간표 둘 중 하나로 쓸 수 있다.

```yaml
rate: { 0: 0.5, 1500000: 1.0 }        # 150만 미만 0.5%, 150만 이상 1.0%
limits:
  - { per: month, amount: { 300000: 3000, 500000: 7000, 1000000: 10000 } }
```

혜택이 적용되는 구간은 `tiers: { from: 300000, to: 1000000 }`으로 적는다. 둘 다 구간 하한이고 양 끝을 포함한다. 적지 않으면 가장 낮은 구간부터 가장 높은 구간까지다. 1판처럼 구간마다 혜택을 복제하지 않는다.

구간표의 가장 작은 키는 그 혜택이 적용되는 첫 구간 이하여야 한다. 그래야 적용되는 모든 구간에 값이 있다.

- IBK 나라사랑의 나라 편의점 할인은 `to: 200000`이다. 25만 구간부터는 All in One 할인만 받기 때문이다.
- 사용자 사실로 구간 조건이 면제되면 `tiers: { from: 80000, waived_when: { fact: salary_transfer } }`로 적는다. 나라사랑의 병 급여이체 면제가 이 경우다.
- `waived_when`은 `from`만 푼다. `to`는 그대로다. 나라사랑 급여이체자도 전월 25만원 이상이면 나라 편의점 할인을 받지 못한다. 엔진 테스트에 이 경우를 넣는다.

### 2.3 대상과 업종 트리

```yaml
target:
  categories: [cafe]            # 이 업종이거나
  merchants: [starbucks]        # 이 가맹점이면 대상
  exclude_categories: []
  exclude_merchants: []
# 전가맹점은 target: { all: true }
```

업종은 두 단계 트리로 바꾼다. 자식 코드는 `transit.subway`처럼 `부모.자식`으로 쓴다. 부모 코드를 대상으로 적으면 자식 업종이 전부 대상이다. 20장에서 빠졌던 업종을 더한다.

| 부모 | 자식 | 필요했던 카드 |
|---|---|---|
| restaurant | general, fastfood, bakery | KB 톡톡 버거, Easy all 제과 |
| transit | bus_city, subway, bus_intercity, bus_express, rail | 시외·고속버스 제외가 거의 모든 카드. 고속버스만 빼거나 고속버스만 주는 카드가 있어 시외버스와 나눈다 |
| telecom | mobile, internet_tv | 결합상품 제외 |
| education | academy, study_material, tuition, school_fee | LOCA 365 학습지, 등록금 실적 제외 |
| utility | electricity, gas, water | 수도만 빠지는 카드 |
| insurance | private, social | 4대보험만 실적 제외 |
| beauty | salon, cosmetics | My WE:SH 미용실, Easy all 뷰티 |
| travel | airline, agency, hotel, duty_free | the Green 여행 |
| 새 부모 없음 | laundry, pc_room, sports, pet, prepaid_charge, rent | Mr.Life 세탁소, zgm 반려동물, 선불 충전 제외 |

`overseas` 업종은 없앤다. 해외 결제는 업종이 아니라 결제의 지역이다. 해외 카페 결제는 카페이면서 해외다. 2.4의 `region`으로 가린다.

### 2.4 조건

`when`은 조건 목록이고 전부 맞아야 한다. 목록의 항목 하나에 조건을 여럿 적어도 전부 맞아야 한다. 한도의 `adjust`, 실적의 `cancellation_overrides`, 공통 제외의 `when_any`에 쓰는 `when`도 같은 조건 문법이다.

```yaml
when:
  - amount: { min: 30000, below: 100000 }       # 3만원 이상 10만원 미만
  - day: { in: [sat, sun], holidays: exclude }  # holidays: ignore 기본, include 공휴일도 포함, exclude 공휴일 빼기, only 공휴일만
  - time: { from: "21:00", to: "09:00" }        # 승인 시각. 자정을 넘길 수 있다
  - months: [5, 12]
  - region: overseas                            # domestic 또는 overseas
  - channel: online                             # online 또는 offline
  - interest_free: false                        # 무이자할부 건이 아니어야 한다
  - lump_sum: true                              # 일시불이어야 한다. 할부 개월 수가 없거나 1이면 일시불이고, 할부는 무이자여도 빠진다. true만 쓴다
  - payment: [naver_pay, kakao_pay]             # 결제수단이 이 중 하나
  - payment_not: [naver_pay, kakao_pay, toss_pay]
  - billing: [autopay]                          # normal 일반, autopay 자동납부, subscription 정기결제, postpaid_transit 후불교통, app_prepay 앱 선결제, in_app 인앱결제
  - billing_not: [in_app]
  - option: { package: [p1, p2, p3] }           # 2.8
  - fact: soldier                               # 2.9
  - ranked: easy-all-a                          # 2.8
  - card_month: { min: 1 }                      # 카드를 쓰기 시작한 달을 0으로 센 몇 번째 달인지
  - month_total: { min: 50000 }                 # basis가 month_total인 보상에서만. 2.5
  - any_of: [ { fact: soldier }, { fact: salary_transfer } ]
```

- 금액, 날짜, 시각, 지역, 채널, 할부는 결제에서 바로 알 수 있다.
- 결제수단, 청구 방식, 사실, 옵션은 사용자가 넣지 않았을 수 있다. 값이 없을 때 어떻게 계산하고 보여 줄지는 3절에서 정한다.
- 공휴일은 한국 공휴일 달력을 쓴다. 대체공휴일과 임시공휴일도 포함한다.

### 2.5 보상

```yaml
reward:
  type: billing_discount     # billing_discount 청구할인, onsite_discount 현장할인, points 포인트, cashback 캐시백
  program: mysinhan_point    # points일 때 point_programs.yaml의 키
  rate: 10                   # 정률 %. 아래 넷 중 정확히 하나를 쓴다
  # fixed: 1500              # 정액
  # per_unit: { unit: 20000, amount: 1000 }   # 2만원당 1천P, 남는 금액은 버린다
  # per_liter: 60            # 리터당 원. reference.yaml의 기름값으로 리터를 환산한다
  round: floor               # floor 원 단위 내림 기본, round 반올림, floor10, floor100
  basis: txn                 # txn 결제마다, month_total 한 달 대상 이용액 합이 조건을 채우면 한 번
```

- 현장할인은 결제할 때 이미 빠진 할인이다. 기록된 결제 금액은 할인 뒤 금액이므로 엔진이 할인 전 금액을 되짚어 혜택을 계산한다. 실적에는 할인 뒤 금액이 잡힌다.
- `basis: month_total`은 카카오뱅크 후불교통처럼 한 달 합산 5만원 이상이면 4천원을 주는 혜택이다. 조건은 `when: [ { month_total: { min: 50000 } } ]`로 쓰고 화면에는 진행률로 보여 준다.
- `point_programs.yaml`은 포인트 종류마다 이름과 1포인트의 원화 가치를 둔다. 1차는 전부 1원이다.
- `reference.yaml`은 기름값처럼 계산에 쓰는 기준값과 그 날짜와 출처를 둔다. 기름값은 한국석유공사 오피넷 평균가를 갱신 때 함께 받는다.

### 2.6 한도

혜택마다 `limits` 목록을 둔다. 결제 하나의 혜택은 목록의 한도를 전부 넘지 않는 가장 큰 값이다.

```yaml
limits:
  - { per: txn, base: 10000 }       # 1회 승인 1만원까지만 혜택 계산에 넣는다
  - { per: txn, amount: 2000 }      # 건당 최대 혜택 2천원
  - { per: day, count: 1 }
  - { per: day, amount: 10000 }     # 하루 혜택 1만원까지
  - { per: month, count: 10 }
  - { per: month, base: 300000 }    # 월 승인 30만원까지
  - { per: year, count: 12 }        # 1월 1일부터 12월 31일
  - { per: period, count: 1 }       # 혜택의 행사 기간 전체에 1회
  - { shared: integrated }          # 카드 수준 공유 한도를 쓴다
```

- `per`는 txn, day, month, quarter, year, period, lifetime 중 하나다. 달, 분기, 연은 한국 시간 달력 기준이다.
- 한도 종류는 셋이다. `amount`는 받은 혜택 금액 합, `count`는 적용 횟수, `base`는 혜택 계산에 넣은 결제액 합이다.

여러 혜택이 같이 쓰는 한도는 개정의 `limits`에 key를 붙여 두고 혜택에서 `shared`로 가리킨다. 1판의 `integrated_cap`도 이 중 하나가 된다.

```yaml
limits:
  - key: weekend              # Mr.Life 주말 마트와 주말 주유가 같이 쓴다
    per: month
    amount: { 300000: 3000, 500000: 7000, 1000000: 10000 }
  - key: px-basic             # 나라사랑 PX 3만원 이상 세 구간이 같이 쓴다
    per: month
    amount: 50000
    count: 2
    adjust:
      - { when: { fact: salary_transfer }, count: null }   # 병 급여이체자는 횟수 제한 없음
```

`adjust`는 조건에 따라 한도를 바꾼다. `amount`, `count`, `base`에 새 값을 주거나, `multiply`, `add`로 바꾼다. 값 `null`은 제한 없음이다.
- My WE:SH 생일 달 한도 두 배: `{ when: { fact: birth_month_now }, multiply: 2 }`
- Point Plan 5월과 12월 추가 한도: `{ when: { months: [5, 12] }, add: 10000 }`

### 2.7 중복 묶음

혜택마다 `stack`을 적는다. 적지 않으면 `main`이다.
- 같은 묶음의 혜택은 결제 하나에 하나만 받는다.
- 다른 묶음의 혜택은 더해서 받는다.

```yaml
stacks:
  - key: main
    pick: priority            # best 가장 큰 혜택 하나, priority 적은 순서대로 먼저 맞는 하나
    order: [area-5, base-1-5]
    spill: split              # none 넘친 금액은 버림, split 한도를 넘은 금액은 다음 혜택으로
  - key: pay                  # KB 톡톡 간편결제 10%는 다른 할인과 겹쳐 받는다
```

- 현대카드M은 5% 영역 혜택이 기본 1.5%를 대신하고, 5% 한도를 넘은 금액은 1.5%로 받는다. `pick: priority`와 `spill: split`이다.
- 삼성 iD ON은 3% 한도를 넘긴 다음 결제부터 1%다. 같은 결제 안에서는 나누지 않으므로 `spill: none`이다.
- NH zgm처럼 "둘 중 큰 쪽만"이면 `pick: best`다. 묶음을 적지 않았을 때의 기본값도 `best`와 `none`이다.
- `spill: split`은 넘친 금액을 priority면 order의 다음 혜택으로, best면 다음으로 큰 혜택으로 넘긴다.
- 우리 EVERY POINT의 간편결제 2% 추가 적립은 기본 0.8%와 다른 묶음에 둔다. 그러면 둘을 더해 2.8%가 된다.

### 2.8 옵션과 자동 선택

사용자가 고르는 패키지나 모드는 `options`로 둔다.

```yaml
options:
  - key: package
    title: 라이프스타일 옵션 패키지
    choices:
      - { key: p1, title: 패키지1 }
      - { key: p2, title: 패키지2 }
    default: null             # 카드사 기본값이 있으면 그 값. 없으면 등록할 때 묻는다
    change: immediate         # immediate 바로, next_month 다음 달 1일부터
    unsupported: []           # 계산하지 않는 선택지. Easy all의 diy 모드
```

혜택은 `when: [ { option: { package: [p1, p4] } } ]`로 그 선택지에서만 적용된다. 고른 값과 바꾼 날은 보유 카드에 이력으로 남긴다. 3절에서 다룬다.

이번 달 이용액이 큰 영역만 받는 규칙은 `ranked`로 둔다.

```yaml
ranked:
  - key: easy-all-a
    top: { 500000: 1, 1000000: 2, 1500000: 3 }   # 구간마다 상위 몇 개
    by: month_amount
```

그룹에 드는 혜택은 각자 `when`에 `ranked: easy-all-a`를 단다. 그룹은 몇 개를 고를지만 정한다. KB Easy all A그룹이면 음식, 교육, 병원·약국, 해외, 관리비 다섯 혜택이 이 조건을 단다.

혜택 하나가 영역 하나다. 조건이나 보상이 달라 한 영역을 혜택 여럿으로 나눴으면 그 혜택들에 같은 `area`를 적는다. 순위는 영역마다 이용액을 합쳐 매긴다.
- KB Easy all의 해외/면세점은 해외 혜택과 국내 면세점 혜택으로 나뉘지만 `area: overseas-dutyfree`로 한 영역이다.
- 삼성 iD ON 커피전문점 영역의 스타벅스는 사이렌오더도 받아 오프라인 조건이 없는 혜택으로 따로 둔다. 두 혜택 모두 `area: coffee`다.

순위는 그 달 1일부터 계산한 순간까지의 대상 이용액으로 매긴다. 달 중간의 추천은 잠정값이다. 순위가 바뀌면 화면에 알린다. 삼성 iD ON의 많이 쓰는 영역 30%는 `top: 1`이다.

### 2.9 사용자에게 묻는 사실

```yaml
facts:
  - { key: soldier, type: bool, scope: user, ask: 현역 병사인가요 }
  - { key: salary_transfer, type: bool, scope: card, ask: 이 카드 결제계좌로 병 급여를 받나요 }
  - { key: mytag, type: bool, scope: card, ask: BC카드 마이태그에 이 카드를 등록했나요 }
  - { key: birth_month, type: month, scope: user, ask: 생일이 몇 월인가요 }
```

- `type`은 bool, month, choice 중 하나다.
- `scope`는 user와 card 중 하나다. user는 사람에 대한 사실이라 카드를 여러 장 등록해도 한 번만 묻는다. 3.2
- `birth_month_now`처럼 결제 달과 비교하는 파생 사실은 엔진이 만든다.
- 사실은 그 카드에 필요한 것만 묻는다. 생일 달은 개인정보라 달만 받고, 답하지 않아도 된다.

### 2.10 실적 규칙과 신규 발급 특례

```yaml
spend:
  basis: prev_calendar_month    # prev_calendar_month, billing_cycle, none
  regions: [domestic, overseas] # K-LIFE는 [domestic]
  exclude_categories: [tax, utility, gift_card, insurance.social, education.tuition, prepaid_charge, rent]
  interest_free: count          # count 실적에 넣음, exclude 뺌
  installment: full_at_purchase # 또는 per_installment_month
  cancellation: cancel_month    # 또는 original_month
  cancellation_overrides:
    - { when: { region: overseas }, use: cancel_month }   # the Green은 해외 취소만 취소 달
  month_offset: { transit.bus_city: 1, transit.subway: 1 }  # 신한은 교통카드 이용액을 다음 달 실적으로 넣는다
  exclude_applied: 0            # 혜택 받은 결제를 실적에서 빼는 비율. 0, 0.5, 1
```

- 혜택에 `exclude_applied`를 적으면 그 혜택만 카드 값을 덮어쓴다. 삼성 iD ON은 카드 값이 0이고 세 혜택만 1이다. 우리 K-LIFE는 카드 값이 0.5다.
- `billing_cycle`은 결제일 기준 이용기간으로 실적을 세는 카드다. 사용자의 결제일과 카드사 파일의 결제일별 이용기간 표가 필요하다. 20장에는 없지만 갱신 중에 나오면 받을 수 있게 둔다.

```yaml
new_card:
  from: registration            # registration 사용 등록일, first_use 첫 사용일, issue 발급일, receipt 수령일
  until: next_month_end         # 기준일이 속한 달의 다음 달 말일까지
  tier: 300000                  # 이 기간에 적용할 구간
  tier_by_benefit: { weekend-dining: 0, autopay-telecom: 400000 }   # 혜택마다 다르면
```

이 기간에 쌓은 실적이 더 높은 구간을 채우면 다음 달은 그 구간이다. 이는 평소 규칙과 같다.

사용자에게는 날짜 하나만 받는다. 그 날짜가 `started_on`이다. 등록할 때 묻는 문구는 그 카드의 `from`에 맞춘다. registration이면 "카드 사용 등록을 한 날", first_use면 "처음 결제한 날"을 묻는다. `card_month`도 이 날짜의 달을 0으로 센다. "생활할인은 카드 등록 달에는 없음" 같은 예외는 혜택에 `card_month: { min: 1 }`을 건다.

### 2.11 모든 혜택에서 빠지는 결제

```yaml
benefit_exclusions:
  categories: [apartment_fee, education.school_fee, education.tuition, insurance.social]
  when_any:
    - { interest_free: true }
    - { payment: [naver_pay, kakao_pay, toss_pay], channel: online }   # 간편결제 가맹점명으로 찍히는 건
  unmodeled: [다른 현대카드 할인이 적용된 건]
```

실적 제외와는 목록이 다르다. 20장 대부분이 둘을 따로 적는다. 혜택이 대상으로 직접 적은 업종이나 가맹점은 이 목록보다 우선한다. KB Easy all의 관리비 3%처럼 실적에서는 빠지지만 혜택은 주는 경우가 있기 때문이다.

### 2.12 날짜가 있는 변화

- **행사성 혜택**은 혜택에 `valid_from`과 `valid_until`을 적는다. 둘 다 그날을 포함한다. 기간이 지나면 그 혜택만 없어진다. 나라사랑 프로모션들과 카카오뱅크 프로모션이 해당한다.
- **기존 규칙의 값이 바뀌는 날**이 있으면 새 개정을 추가한다. 나라사랑 Npay 적립 횟수는 12월 31일까지 5회, 7회, 10회이고 1월 1일부터는 5회다. 이런 변화가 해당한다.

새 개정은 앞 개정에서 바뀌는 곳만 적는다.

```yaml
  - effective_from: 2027-01-01
    source: page                  # 근거 원문
    patch:
      benefits:
        npay-points:
          limits: [ { per: month, count: 5 }, { per: day, count: 1 } ]
```

합치는 규칙은 세 가지다.
- key가 있는 목록은 key로 짝을 맞춰 합친다. 대상은 `benefits`, `limits`, `stacks`, `options`, `facts`다.
- key가 없는 목록은 통째로 바꾼다.
- 값 `null`은 그 항목을 지운다.

검증기는 합친 결과로 개정마다 전체 규칙을 만들어 검사한다. DB와 엔진은 합친 결과만 본다.

### 2.13 문장으로 남기는 것

결제 입력으로는 판단할 수 없는 조건만 혜택이나 개정의 `unmodeled`에 문장으로 남긴다. 엔진은 이 혜택을 조건이 없는 것처럼 계산하고 "확인 필요"를 붙인다. 1판의 `conditions_not_modeled` 참거짓은 없앤다.

20장에서 남는 것은 다음과 같다.
- 백화점·마트 입점 매장과 임대 매장 제외
- GS25 주요품목, 하나Pay 맛집처럼 품목이나 지정 가맹점이 정해진 경우
- 카드사의 다른 행사 할인과 겹칠 때의 처리
- 가족카드 실적과 한도 합산
- 나라사랑 NOL 적립처럼 여러 카드사 카드가 같이 쓰는 한도
- 매출표 접수일 기준으로 달이 갈리는 경우. 교통처럼 규칙이 정해진 것은 `month_offset`으로 담는다

### 2.14 예: 신한 Mr.Life 주말 할인

1판의 혜택 6개가 2판에서는 2개와 공유 한도 하나가 된다.

```yaml
limits:
  - key: weekend
    per: month
    amount: { 300000: 3000, 500000: 7000, 1000000: 10000 }
benefits:
  - key: weekend-mart
    title: 주말 할인마트 10% 할인
    target: { merchants: [emart, lotte_mart, homeplus] }
    when: [ { day: { in: [sat, sun], holidays: ignore } } ]
    reward: { type: billing_discount, rate: 10 }
    limits: [ { per: day, count: 1 }, { per: txn, base: 50000 }, { shared: weekend } ]
    tiers: { from: 300000 }
    unmodeled: [상품권 결제 제외]
  - key: weekend-fuel
    title: 주말 주유 리터당 60원 할인
    target: { merchants: [sk_energy, gs_caltex, hd_oilbank, s_oil] }
    when: [ { day: { in: [sat, sun], holidays: ignore } }, { channel: offline } ]
    reward: { type: billing_discount, per_liter: 60 }
    limits: [ { per: day, count: 1 }, { per: txn, base: 100000 }, { per: month, base: 300000 }, { shared: weekend } ]
    tiers: { from: 300000 }
    unmodeled: [LPG 제외]
```

### 2.15 예: 현대카드M 기본 적립과 영역 적립

```yaml
limits:
  - { key: area-5, per: month, amount: 10000 }
stacks:
  - { key: main, pick: priority, order: [area-5-domestic, area-5-overseas, base-1-5], spill: split }
benefits:
  - key: base-1-5
    target: { all: true }
    reward: { type: points, program: hyundai_m_point, rate: 1.5, round: round }
    tiers: { from: 500000 }
  - key: area-5-domestic
    target:
      categories: [restaurant]
      merchants: [naver_plus_store, coupang, gmarket, auction, eleven_st, ssg_com, kurly]
    when: [ { region: domestic } ]
    reward: { type: points, program: hyundai_m_point, rate: 5, round: round }
    limits: [ { shared: area-5 } ]
    tiers: { from: 1000000 }
  - key: area-5-overseas
    target: { all: true }
    when: [ { region: overseas } ]
    reward: { type: points, program: hyundai_m_point, rate: 5, round: round }
    limits: [ { shared: area-5 } ]
    tiers: { from: 1000000 }
```

- 1판은 해외를 업종으로 적었다. 그래서 해외 음식점 결제 한 건이 음식점과 해외 양쪽에 걸렸다. 2판에서는 국내 영역과 해외 영역을 지역 조건으로 나누고, 두 혜택이 월 1만 포인트 한도 하나를 같이 쓴다.
- 100만 구간에서 음식점 30만원을 쓰면 먼저 5%가 1만 포인트까지 적용된다. 그 1만 포인트는 20만원어치다. 남은 10만원은 1.5%로 넘어가 1,500포인트가 된다. 합계는 11,500포인트다.

## 3절 입력과 DB

2026-09-28 확정. 2절 조건을 계산하려면 결제와 보유 카드에 값이 더 필요하다. 원칙은 세 가지다.
- 화면에 입력 칸을 늘리지 않는다. 자동으로 채우고, 사용자는 틀릴 때만 바꾼다.
- 모르는 값을 아는 척 계산하지 않는다.
- 사용자가 넣은 값이 자동으로 채운 값보다 우선한다.

### 3.1 결제에 더하는 값

| 필드 | 값 | 자동으로 채우는 방법 | 쓰는 곳 |
|---|---|---|---|
| region | domestic, overseas | 기본 domestic. 엑셀의 해외 열이나 외화 금액 | 해외 적립, 해외 실적 제외 |
| payment_method | `payment_methods.yaml`의 키. 모르면 null | 그 카드로 마지막에 쓴 결제수단. 처음은 physical_card. 엑셀은 가맹점명의 페이 이름. 페이 이름이 없는 엑셀 행은 physical_card | 간편결제 할인과 제외 |
| billing | normal, autopay, subscription, postpaid_transit, app_prepay, in_app | 가맹점의 기본 청구 방식. 통신사는 autopay, 넷플릭스는 subscription, 나머지는 normal | 자동납부, 정기결제 혜택 |
| card_revision_id | 계산에 쓴 개정 | 결제일에 적용되는 개정 | 기록 고정 |

- 결제 시각 `paid_at`, 채널, 할부는 1판에 이미 있다.
- 결제 기록 화면의 "자동으로 채웠어요" 줄에 결제수단과 해외를 더한다. 예: "카페 · 오늘 14:20 · 오프라인 · 일시불 · 실물카드". 사용자는 틀릴 때만 "바꾸기"를 누른다.
- 해외 결제 금액은 카드사가 청구한 원화 금액이다. 해외 수수료 포함 여부는 카드마다 다를 수 있어 1차는 청구 금액 그대로 쓴다.
- 삼성페이 결제는 카드사 이용 내역에 보통 일반 카드 승인으로 찍혀 엑셀로는 실물카드와 구분하지 못한다. 그래서 페이 이름이 없는 엑셀 행은 실물카드로 본다. 삼성페이를 가려야 하는 혜택은 20장 중 iD ON의 오프라인 NFC 제외뿐이라 사용자가 바꾸기로 고칠 수 있게 둔다.
- 결제수단이 null인 경우는 추천 요청처럼 아직 결제하지 않았거나, 사용자가 "모름"을 고른 경우다.

`payment_methods.yaml`은 결제수단 목록이다. 새 페이가 나와도 코드를 고치지 않고 추가하려고 카탈로그에 둔다.

```yaml
- { key: physical_card, name: 실물카드 }
- { key: samsung_pay, name: 삼성페이 }
- { key: naver_pay, name: 네이버페이, statement_names: [네이버페이, NAVERPAY, 엔페이] }
- { key: kb_pay, name: KB Pay }
```

`statement_names`는 엑셀 이용 내역에 찍히는 이름이다. 가맹점명에 이 이름이 있으면 결제수단을 그 페이로 채운다. 이런 결제는 카드사가 가맹점을 페이로 보므로, 가게 이름은 페이 이름을 뺀 나머지로 별칭표에서 찾는다.

`merchants.yaml`의 가맹점에는 `billing: autopay`처럼 기본 청구 방식을 적을 수 있다.

### 3.2 보유 카드에 더하는 값

| 필드 | 뜻 | 언제 묻나 |
|---|---|---|
| started_on | 카드를 쓰기 시작한 날. 신규 발급 특례 계산 | 카드 등록 때 "최근 두 달 안에 새로 받은 카드인가요". 예면 날짜를 받는다 |
| 옵션 선택 이력 | 옵션마다 고른 선택지와 적용 시작일 | 옵션이 있는 카드를 등록할 때. 나중에 카드 상세에서 바꾼다 |
| 사실 답 | 2.9의 사실. bool, month, choice | 그 카드에 필요한 사실만 등록 때 묻는다. 건너뛸 수 있다 |
| last_payment_method | 마지막에 쓴 결제수단 | 결제를 저장할 때 자동 |

- 옵션을 바꾸면 `change` 규칙에 따라 적용 시작일을 정한다. `next_month`면 다음 달 1일이다. 지난 결제는 그 결제일에 선택돼 있던 옵션으로 계산한다.
- 사실에는 범위를 둔다. `scope: user`는 사람에 대한 사실이라 카드를 여러 장 등록해도 한 번만 묻는다. 현역병 여부와 생일 달이 해당한다. `scope: card`는 카드마다 다른 사실이다. 이 카드 결제계좌로 병 급여를 받는지, 마이태그에 등록했는지가 해당한다.
- 결제일 기준 실적 카드가 오면 결제일을 `scope: card` 사실로 묻는다.

### 3.3 모르는 값이 있을 때

조건에 쓰인 값을 모르는 경우는 셋이다. 결제수단이 null이거나, 사실에 답하지 않았거나, 옵션을 고르지 않은 경우다.

**저장한 결제의 혜택**은 그 조건을 채우지 않은 것으로 계산한다. 아낀 돈을 부풀리지 않기 위해서다. 결제에는 `needs_input` 경고를 붙여 기록 화면에서 "네이버페이로 결제했나요"처럼 한 번 묻는다. 답하면 다시 계산한다.

**추천**은 두 부분으로 돌려준다.
- 기본 순위: 지금 아는 값으로 계산한 혜택으로 매긴다.
- 조건부 혜택: 값이 바뀌면 더 받는 혜택을 카드마다 따로 돌려준다. 예: "네이버페이로 결제하면 +1,000원", "현역병이면 PX 15% 할인". 결제수단처럼 사용자가 결제 직전에 고를 수 있는 것은 순위 옆에 보여 준다. 사실은 한 번 답하면 되니 "답하고 다시 보기"로 보여 준다.

**옵션을 고르지 않은 카드**는 옵션에 걸린 혜택을 전부 빼고, 카드 줄에 "패키지를 골라 주세요"를 띄운다. taptap O처럼 혜택 대부분이 옵션에 달린 카드는 등록할 때 고르게 한다.

출력 모델에 두 가지를 더한다. 이름은 엔진 작업 002에서 확정한다.
- `ConditionalBenefit`: card_id, benefit_key, 필요한 값, 더 받는 금액
- 경고 코드 `needs_input`: 무엇을 모르는지

### 3.4 DB 변경

카탈로그 영역은 개정 단위로 바꾼다. 혜택 규칙은 개정 하나에 JSON 문서 하나로 넣는다. `jsonb`는 Postgres 표준 기능이라 설계 문서 4.2절의 "표준 기능만" 원칙에 맞는다. 엔진은 개정 문서를 통째로 읽어 계산하므로 혜택을 행으로 쪼갤 이유가 없다. 쪼개면 조건 종류가 늘 때마다 테이블을 고쳐야 한다.

| 테이블 | 바뀌는 점 |
|---|---|
| cards | 신원 정보만 남긴다. search_names, product_codes, status, status_since, annual_fees, sources, checked_at을 더한다 |
| card_revisions | 새 테이블. card_id, effective_from, effective_from_estimated, rules jsonb, rules_sha256, schema_version, published_at. `(card_id, effective_from)` 유니크 |
| spend_tiers, spend_rules, spend_rule_excluded_categories, benefits, benefit_targets | 없앤다. 내용은 card_revisions.rules로 간다 |
| categories | parent_code를 더한다 |
| merchants | billing을 더한다 |
| payment_methods | 새 테이블. key, name, statement_names |
| point_programs | 새 테이블. key, name, won_per_point |
| reference_values | 새 테이블. key, value, as_of, source |

사용자 영역에 더하는 것.

| 테이블 | 바뀌는 점 |
|---|---|
| user_cards | started_on, last_payment_method를 더한다 |
| user_card_options | 새 테이블. user_card_id, option_key, choice_key, effective_from |
| user_facts | 새 테이블. user_id, key, value. `scope: user` 사실 |
| user_card_facts | 새 테이블. user_card_id, key, value. `scope: card` 사실 |
| transactions | region, payment_method, billing, card_revision_id를 더한다. applied_benefit_id와 estimated_benefit은 없애고 아래 테이블로 옮긴다 |
| transaction_benefits | 새 테이블. transaction_id, benefit_key, amount, base_amount. 중복 묶음이 여럿이면 결제 한 건에 여러 행이다 |
| recommendation_requests | region, payment_method를 더한다 |
| recommendation_results | applied_benefit_id를 없애고 applied jsonb와 conditional jsonb를 더한다 |

- 테이블은 19개에서 22개가 된다. 5개가 없어지고 8개가 생긴다.
- 한도 사용량은 따로 저장하지 않는다. 기간 안의 `transaction_benefits`를 모아 엔진이 계산한다. 횟수는 행 수, 금액은 amount 합, 결제액 한도는 base_amount 합이다.
- 저장한 결제의 혜택은 1판처럼 고정한다. 카탈로그가 바뀌어도 다시 계산하지 않는다. 사용자가 결제를 고치거나 모르던 값을 답하면 그 결제만 다시 계산한다.
- 파이프라인은 카드사 파일을 합치고 패치를 적용한 뒤의 개정 전체를 `card_revisions`에 넣는다. 카드사 공통 규칙이 바뀌면 그 카드사 카드마다 새 개정 행이 생긴다.

### 3.5 화면에 생기는 변화

하위 프로젝트 2에서 반영한다. 여기서는 목록만 정한다.
- 카드 등록: 옵션 선택, 사실 질문, 신규 발급 여부. 모두 그 카드에 필요할 때만 나오고, 옵션 말고는 건너뛸 수 있다.
- 결제 기록: 자동으로 채운 줄에 결제수단과 해외를 더한다.
- 추천 결과: 카드마다 조건부 혜택 한 줄. 예: "네이버페이로 결제하면 +1,000원".
- 카드 상세: 옵션 바꾸기. 자동 선택 카드는 이번 달 영역 순위.
- 기록: 모르는 값이 있는 결제에 "확인 필요" 표시.

## 4절 검증과 20장 옮기기

2026-09-28 확정.

### 4.1 코드 위치

1판 검증 스크립트 `tools/validate_catalog.py`는 옮기기가 끝나면 지운다. 2판은 계산 엔진과 같은 패키지에 둔다. 엔진이 같은 모델로 카탈로그를 읽어야 검증과 계산이 어긋나지 않기 때문이다.

```
backend/
  pyproject.toml
  cherry_core/catalog/
    models.py      # 2절과 3절의 Pydantic 모델
    resolve.py     # 카드사 기본값 합치기, 패치 적용, 날짜로 개정 고르기
    check.py       # 모델 밖의 교차 검사
    canonical.py   # 고정된 저장 형식으로 다시 쓰기
    __main__.py    # check, format 명령
  tests/catalog/
```

- 명령은 `uv run --project backend python -m cherry_core.catalog check`와 `format` 둘이다.
- 파일 수정 뒤 훅은 1판 스크립트 대신 `check`를 부른다.

### 4.2 검증 규칙

**모델 검증.** 모르는 필드가 있으면 실패한다. AI가 뽑은 파일에서 오타 난 필드가 조용히 무시되는 것을 막는다. 금액은 정수, 비율은 0보다 크고 100 이하다.

**교차 검사.** 파일 사이, 필드 사이의 관계를 본다. 합치기와 패치를 적용한 뒤의 개정 전체에 대해 검사한다.

| 대상 | 검사 |
|---|---|
| 구간 | 0부터 시작하고 오름차순. 구간표의 키와 혜택의 `tiers.from`, `to`는 전부 이 목록 안에 있다. `from`은 `to` 이하다. 구간표의 가장 작은 키는 `from` 이하다 |
| 대상 | 업종은 트리에, 가맹점은 별칭표에 있다. `all: true`와 목록을 함께 쓰지 않는다 |
| 조건 | 아는 종류만 쓴다. `amount`는 min이 below보다 작다. 요일 이름, 시각 형식, 결제수단 키, 청구 방식이 목록에 있다 |
| 보상 | rate, fixed, per_unit, per_liter 중 정확히 하나다. points면 program이 있고 목록에 있다 |
| 한도 | `shared`가 가리키는 한도가 있다. 한도마다 amount, count, base 중 하나 이상이 있다. 쓰이지 않는 공유 한도는 경고다 |
| 중복 묶음 | 혜택의 stack이 정의돼 있다. `main`은 적지 않아도 있다. priority 묶음의 order에는 그 묶음의 혜택이 빠짐없이 한 번씩 있다 |
| 옵션, 사실, 자동 선택 | 조건이 가리키는 옵션, 선택지, 사실, ranked 그룹이 있다. 옵션의 default는 선택지 중 하나이거나 null이다. ranked 그룹마다 영역이 둘 이상이다. `area`가 같은 혜택은 한 영역으로 센다. `month_total` 조건은 `basis: month_total` 보상에만 쓴다 |
| 날짜 | 개정은 날짜 오름차순이고 날짜가 겹치지 않는다. 첫 개정은 패치가 아니다. valid_from은 valid_until 이하다 |
| 근거 | 혜택의 source는 sources에 있다. open_questions의 path는 실제 필드를 가리킨다 |
| key | 개정 안에서 혜택, 한도, 묶음, 옵션, 사실의 key가 겹치지 않는다 |

**경고.** 틀렸다고 단정할 수는 없지만 사람이 볼 것이다. 검사는 통과시키고 목록으로 보여 준다.
- 비율이 5% 이상인데 한도가 하나도 없는 혜택
- 구간이 높아지는데 값이 줄어드는 구간표
- `unmodeled`와 `open_questions` 개수. 카드마다 센다
- 직전 커밋의 파일에는 있던 혜택 key가 사라진 경우. 갱신 때 key가 바뀌어 결제 기록 연결이 끊기는 것을 잡는다

**저장 형식.** `format`은 필드 순서, 들여쓰기, 목록 정렬을 고정해 다시 쓴다. `check`는 파일이 이미 그 형식이 아니면 실패한다. 형식이 고정돼 있어야 같은 원문으로 두 번 갱신했을 때 차이가 0이 된다.

### 4.3 검증기 테스트

- 잘못된 파일 테스트. 위 표의 검사마다 틀린 파일 하나를 두고, 어느 파일의 어느 필드에서 실패하는지 확인한다.
- 합치기 테스트
  - 카드사 기본값을 카드가 덮어쓴다.
  - 카드사 기본값 하나를 바꾸면 그 카드사 카드의 해석 결과가 전부 바뀐다.
  - 패치는 key로 합치고, 목록은 통째로 바꾸고, null은 지운다.
- 날짜 테스트. 나라사랑 Npay 패치로 2026-12-31과 2027-01-01 결제가 서로 다른 개정으로 해석된다.
- 저장 형식 테스트. `format`을 두 번 돌려도 결과가 같고, 20장 전부가 `format` 뒤에도 바뀌지 않는다.

### 4.4 20장 옮기는 순서

1. **기계 변환.** 1판에서 2판으로 그대로 옮길 수 있는 것은 스크립트로 옮긴다. 대상은 다음과 같다.
   - 신원 필드와 구간
   - 실적 규칙
   - 대상과 채널
   - 비율과 정액
   - 건당 최소 금액과 최대 혜택
   - 월, 일 한도
   - 최소 구간
   - 통합 한도 참조

   이름 끝이 `-t1`, `-t2`인 혜택은 나머지 필드가 같은지 확인한 뒤 구간표 하나로 합친다. 필드가 다르면 합치지 않고 목록에 올린다. 스크립트는 한 번 쓰고 지우는 작업용이라 저장소에 넣지 않는다.
2. **공통 파일.**
   - 업종을 트리로 바꾼다. `public_transit`은 `transit`으로 옮기고, `overseas`는 지역 조건으로 옮긴다.
   - 가맹점에 기본 청구 방식을 더한다.
   - `payment_methods.yaml`, `point_programs.yaml`, `reference.yaml`을 새로 만든다.
3. **카드사 파일.** 같은 카드사 카드끼리 겹치는 실적 규칙, 공통 제외, 신규 발급 특례를 카드사 파일로 올린다. 신한, KB, 현대, 삼성, 롯데, 하나, 우리가 두 장 이상이다. 한 장뿐인 IBK, NH, 카카오뱅크도 카드사 파일을 두지만 기본값은 최소로 한다.
4. **카드별 판단.** 1판 notes에 문장으로만 있던 규칙을 구조로 옮긴다. 대상은 다음과 같다.
   - 중복 묶음, 옵션, 자동 선택, 사실
   - 요일, 시각, 결제수단, 청구 방식 조건
   - 공유 한도와 모든 혜택 공통 제외
   - "공식 문구 미확인"을 `open_questions`로
   - 계산할 수 없는 것을 `unmodeled`로

   카드사 묶음마다 `card-researcher` 에이전트가 맡는다. notes로 판단이 안 되는 곳만 공식 원문을 다시 본다.
5. **대조.** 카드마다 `card-verifier` 에이전트가 2판 파일을 공식 원문과 따로 대조한다. 불일치를 고친 뒤 `check`를 통과시킨다.
6. **사용자 확인.** IBK 나라사랑카드의 확인 필요 항목 네 가지를 묻는다. 답이 없으면 `open_questions`에 남긴다.
7. **보고.** 카드마다 아래를 한 줄로 보고한다. 이 보고로 intent.md의 성공 기준을 하나씩 확인한다.
   - 1판 대비 혜택 수
   - `unmodeled` 목록
   - `open_questions` 목록
   - 합치지 못한 `-t` 혜택

파일은 `catalog/cards/<카드사>/<카드 id>.yaml`로 옮긴다. git이 이동으로 알아보게 하려고, 이동과 내용 변경은 커밋을 나눈다.

### 4.5 걸리는 시간

| 단계 | 시간 |
|---|---|
| 모델, 합치기, 검사, 저장 형식과 테스트 | 5~6시간 |
| 기계 변환과 공통 파일 | 1시간 30분 |
| 카드사 파일과 카드별 판단, 에이전트 병렬 | 2~3시간 |
| 대조와 수정 | 1~2시간 |
| 설계 문서 6.2절, 6.3절, 6.6절과 ERD에 합치기 | 1시간 |

합치면 하루 반쯤이다.

### 4.6 구현 계획에서 정한 것

2026-09-29 구현 계획을 쓰며 코드를 임시 폴더에서 먼저 돌려 보고 정했다. 같은 날 사용자가 확인했다.

1. **첫 개정의 시행일.** 카드사가 부가서비스를 줄이려면 바뀌는 날의 6개월 전까지 홈페이지를 포함한 두 가지 이상의 방법으로 알려야 한다. 여신전문금융업법 시행령과 표준약관의 의무다. 그래서 첫 개정의 시행일은 출시일과, 출시 뒤 마지막 부가서비스 변경 시행일 중 늦은 날로 정한다. 근거가 된 공지나 출시 안내는 `sources`에 남기고 추정 표시를 하지 않는다. 여신금융협회 공시에는 부가서비스 변경 내역이 따로 없어 카드사마다 홈페이지 공지를 본다.
   - 공지 목록을 끝까지 확인하지 못한 카드만 추정일로 두고 `open_questions`에 올린다.
   - 예비 규칙: 첫 개정의 시행일이 추정이면 그날보다 앞선 결제에도 첫 개정을 쓴다. 추정이 아니면 그 결제에 쓸 개정이 없다고 본다.
   - 혜택이 늘어나는 변경과 새 행사는 미리 알릴 의무가 없어, 우리가 다음에 확인하는 날에 알게 된다. 시행일이 최대 갱신 주기만큼 늦게 잡힐 수 있다. 그 기간은 옛 규칙으로 계산되니 아낀 돈이 적게 나올 뿐 부풀려지지 않는다.
2. **사람용 메모.** 카탈로그 파일에는 주석을 쓰지 않는다. `format`이 주석을 지우기 때문이다. 대신 카드, 카드사, 혜택에 `notes` 칸을 둔다. 계산에는 쓰지 않는다.
3. **결제일 기준 실적.** 20장에 없어 이용기간 표 `billing_cycles`는 이번에 모델에 넣지 않는다. `spend.basis: billing_cycle`을 쓰면 오류로 알린다. 처음 나오는 카드가 생길 때 표를 설계한다.
4. **확인 필요 항목의 자리.** `open_questions`는 카드 파일과 카드사 파일에 둔다. `path`는 그 파일 안의 칸을 가리키고, `[숫자]`는 순서, `[이름]`은 key로 찾는다. 예: `revisions[0].benefits[npay-points].limits`.
5. **더한 칸.** 원문에 `review_valid_until` 심의필 유효기간, 카드에 `status_since`, 선택형 사실에 `choices`, 카드사 파일에 수집 설정 `collect`. 연회비의 `brand`는 모르면 비워 둔다.
6. **조건의 사실.** `when`의 `fact`는 bool 사실만 쓴다. 생일 달처럼 month 사실은 엔진이 만드는 파생 사실 `birth_month_now`로 쓴다.
7. **읽기 파일.** 파일을 읽고 오류 위치를 사람이 읽는 경로로 바꾸는 일을 `load.py`에 따로 둔다. 오류 위치는 `revisions@2026-07-01.benefits[cafe-10].reward.rate`처럼 날짜와 혜택 key로 쓴다.
8. **저장 형식의 순서.** 혜택 안의 칸은 key, 제목, 대상, 조건, 보상, 한도, 구간 순으로 쓴다. 나머지는 파일 머리, 개정, 규칙 순의 고정 목록을 따른다.
9. **카드사 기본값의 시작일.** 카드사 파일 `defaults`의 첫 시작일은 그 카드사 카드 중 가장 이른 첫 개정 날짜 이하여야 한다. 그렇지 않으면 그 사이 개정에 공통 규칙이 빠져 검증 오류가 난다. 카드사 공통 약관의 시행일을 찾으면 그 날을 쓰고, 못 찾으면 추정 표시를 둔다.

## 남은 일

plan.md의 구현 계획을 2026-09-29 승인받아 과제 1부터 실행한다.
