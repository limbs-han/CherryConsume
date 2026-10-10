# expand2 빠른 조사 지침

체리컨슘 작업 008 카드 확대. 저장소 C:\Users\SSAFY\Desktop\pjt\cherryConsume. 한국어로 일하고 보고한다.

사용자가 출시를 서두르며 카드를 최대한 많이 담으라고 했다. 꼼꼼한 재대조는 생략하고 빠르게 판정한다. 그래도 금액이 틀린 카드를 넣으면 안 된다.

## 자료

- 초안 `tmp/release-card-expansion/expand2/drafts/<카드>.yaml`. 모델이 뽑아 틀릴 수 있다. kind가 빈 초안은 원문에서 신용·체크를 확인한다. 메타는 `expand2/packet.json`
- 카드 파일 형식 예: `expand2/catalog/cards/<카드사>/` 의 이미 준비된 카드. 사례 예: `tmp/release-card-expansion/expand1/cases/hana-10222.yaml`, `kb-09314.yaml`, `samsung-aap1544.yaml`
- 지켜야 할 계산 결정: `docs/work/008-catalog-all-cards/handoff-2026-10-10.md`의 해당 절. KB 후불교통 문제는 `docs/work/008-catalog-all-cards/release-2026-10-10/research/recommended-mixed/kb-handoff.md`
- 앞서 멈춘 조사에서 `expand2/catalog/cards`나 `expand2/cases`에 쓰다 만 내 카드 파일이 있을 수 있다. 있으면 이어서 고친다

## 카드마다 (한 장에 오래 쓰지 않는다)

1. 공식 상품 페이지(필요하면 상품설명서)를 열어 핵심 숫자만 확인한다. 연회비, 판매 상태, 종류, 실적 구간, 혜택별 비율·대상·최소금액·한도, 실적 제외 대략. 초안과 다르면 고친다. 카드 비교 사이트는 근거로 쓰지 않는다
   - 하나카드 수집 주소는 카드 목록 페이지일 수 있다. 카드 검색으로 상세 페이지를 찾는다
   - KB 상품설명서 PDF는 막힐 수 있다. 모바일 페이지 `m.kbcard.com/c/<코드>`가 도움이 된다
   - 우리카드 페이지는 브라우저로 열어야 숨은 내용이 나올 수 있다
   - 롯데 id는 상품 코드 모양 `lotte-pXXXXX-aXXXXX`를 쓴다. 숫자만 있는 id는 색인 번호일 수 있어 바꾸고 결과에 `draft_card_id`를 남긴다
2. 카드 파일을 `tmp/release-card-expansion/expand2/catalog/cards/<카드사>/<카드>.yaml`에 쓴다. 저장소 `catalog/`, `app/`, 사본의 공통 파일은 고치지 않는다. 새 가맹점이 필요하면 `expand2/needed/<카드>.json`. 모양은 `tmp/release-card-expansion/expand1/needed_common.json`
3. 사례 `expand2/cases/<카드>.yaml`. 혜택마다 양수 1개, 실적 구간이 있으면 경계 직전 1개 정도. 많이 쓰지 않는다
4. 저장소 루트에서 `uv run --project backend python tmp/release-card-expansion/expand2/validate.py <카드>`로 내 카드의 오류 0, 사례 실패 0. 형식 정리는 내 파일만 임시 폴더에 복사해 `uv run --project backend python -m cherry_core.catalog format --root <임시 폴더>`로 하고 되돌려 놓는다. 사본 폴더 전체 format은 금지다. 다른 에이전트가 동시에 쓴다. 남의 카드 오류는 무시한다
5. 결과 `expand2/results/<카드>.json`: `{"card_id","status":"ready"|"blocked"|"exclude","reason","source_urls":[],"case_count","unmodeled":[],"open_questions":[]}`. id를 바꿨으면 `"draft_card_id"`에 옛 id

## 판정

- ready: 핵심 숫자가 공식 원문과 맞고 금액을 바꾸는 필수 조건을 담았다. 담지 못하는 부가 조건(입점 매장, 매출 접수 순서, 가족카드 합산 등)은 unmodeled 문장으로 두고 ready로 해도 된다. 확인 못 한 값은 open_questions에 두고 추측하지 않는다. 혜택 하나를 통째로 담을 수 없으면 그 혜택만 빼고 unmodeled에 적어 나머지로 ready해도 된다. 혜택을 덜 주는 쪽은 괜찮고 더 주는 쪽은 안 된다
- blocked: 실적 계산 자체를 지금 모델로 맞게 못 하거나(후불교통만 실적 제외, 실물·모바일 후불교통 반영월 구분, 연간 누적, 3개월 평균, 앱 로그인 일수, 기간 누적 달성 뒤 적용 등), 공식 원문을 못 열었다
- exclude: 직원·단체·지역민·학교 전용, 법인, 이미 있는 상품과 중복

마지막 보고는 카드마다 한 줄.
