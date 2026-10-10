hana-12782.yaml: ready. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/hana/hana-12782.yaml.
원문: https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=12782
손계산 5개. 공식 원문 대조와 실제 앱 엔진 손계산 통과. 독립 검토와 운영 승인 대기.
문장 조건: 입점 매장 등 결제에서 알 수 없는 제외 조건
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다.
새 혜택 key: domestic-03, domestic-pay-04, overseas-04. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

hana-94257.yaml: blocked. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/hana/hana-94257.yaml.
원문: https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=94257 https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=18058
손계산 8개. 교통 영역의 월 합산 3만원과 대상별 결제조건을 함께 적용하는 계산 미지원. 지원 가능한 8개 혜택 작성. 잘못된 목록 주소를 실제 상품 코드 18058로 보완했다.
문장 조건: 교통은 버스 지하철, 카카오T 선결제, 지정 주유소 오프라인, 지정 전기차 충전의 월 합산 3만원 이상이면 5% 적립한다. 월 영역별 합산액을 여러 결제조건을 가진 혜택 사이에서 공유하는 기능이 필요하다. / 입점 임대매장, 배달앱과 예약앱 커피 주문은 제외한다. 카카오T 현장 결제와 나중결제는 제외한다. / 외화 하나머니 해외 결제는 적립 대신 해외 수수료 면제를 제공한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다. / 94257은 카드 목록 주소였다. 동일한 달달 하나 체크 상품의 실제 코드 18058과 기존 색인 연결을 합쳐야 한다. ID는 유지한다. / 교통 영역 합산 3만원 조건과 다른 결제조건별 적립 계산을 추가해야 한다. 핵심 교통 적립을 누락한 상태로 승인하지 않는다.
새 혜택 key: delivery-5, life-telecom-5, life-utility-5, subscription-streaming-10, subscription-membership-10. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

kb-07964.yaml: blocked. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/kb/kb-07964.yaml.
원문: https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=07964
손계산 19개. Spend.exclude_billing 기능이 없어 후불교통 무승인 전표만 실적에서 제외할 수 없다. 실적 경계에서 혜택 과지급 가능. 지원 가능한 거래 규칙과 손계산은 보존했다.
문장 조건: 입점 매장 등 결제에서 알 수 없는 제외 조건
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다. / 무승인 후불교통 결제만 실적에서 빼는 billing 조건을 실적 규칙에 더해야 한다. 일반 승인 철도 승차권을 제외하지 않도록 광범위한 transit 제외를 제거했다.
새 혜택 key: 없음. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

hana-17504.yaml: ready. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/hana/hana-17504.yaml.
원문: https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=17504
손계산 17개. 공식 원문 대조와 실제 앱 엔진 손계산 통과. 독립 검토와 운영 승인 대기.
문장 조건: 바우처는 본인에게 연 1회 택1 제공한다. 첫해 50만원 이용, 이후 직전 1년 600만원 이용이 필요하다. 호텔다이닝 10만원 할인, 신세계상품권 10만원, SK주유권 5만원 2매, 배달의민족 상품권 10만원, 하나머니 9만원 중 고른다. / 라운지는 본인 가족 동반자 통합 일 3회 연 3회. 첫해 전월 50만원, 이후 직전 1년 600만원 이용이 필요하다. 서비스 연도는 발급월부터 12개월이다. / 프리미엄 바우처와 라운지의 발급연도 실적 및 신청과 사용 이력에 따른 혜택은 자동 계산하지 않는다. 일반 거래의 하나머니 적립만 계산한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다.
새 혜택 key: base-1, special-overseas, special-airline, special-dutyfree, special-travel, special-hana-tour-offline, special-shopping-online, special-shopping-offline. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

hana-19149.yaml: blocked. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/hana/hana-19149.yaml.
원문: https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=19149
손계산 9개. 핵심 영역별 연속 3일 2배 적립 조건 미지원. 일반 결제 9개 혜택은 작성했다.
문장 조건: 영역별 3일 연속 1원 이상 이용하면 기본 적립률이 2배가 된다. 결제 입력 이력으로 판단할 수 있으나 현 엔진에 연속 이용일 조건이 없다. / ALLDAY를 포함한 모드는 앱에서 변경 가능하다. 다른 모드와 해외 외화 하나머니 결제는 별도 규칙이 필요하다. 입점 임대매장과 공식 앱 외 결제는 제외한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다. / 연속 3일 기본 1% 및 온라인 페이 2%를 정확히 계산하는 기능이 필요하다. 누락한 상태로 승인하지 않는다.
새 혜택 key: base-05, online-pay-1, allday-delivery-2, allday-transit-3, allday-taxi-3, allday-taxi-app-3, allday-online-shopping-2, allday-oasis-offline-2, allday-store-2. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

kb-09122.yaml: blocked. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/kb/kb-09122.yaml.
원문: https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09122
손계산 10개. Spend.exclude_billing 기능이 없어 후불교통 무승인 전표만 실적에서 제외할 수 없다. 실적 경계에서 혜택 과지급 가능. 지원 가능한 거래 규칙과 손계산은 보존했다.
문장 조건: 해외 이용금액은 매입 완료일 기준으로 실적에 반영한다. 무승인 자판기, 터널통행료, 항공기내 이용도 실적에서 제외한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다. / 무승인 후불교통 결제만 실적에서 빼는 billing 조건을 실적 규칙에 더해야 한다. 일반 승인 철도 승차권을 제외하지 않도록 광범위한 transit 제외를 제거했다.
새 혜택 key: 없음. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

kb-09771.yaml: blocked. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/kb/kb-09771.yaml.
원문: https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09771
손계산 14개. 해외 수수료 면제 및 실적 채워드림 적용일부터 월말까지의 혜택 계산 미지원. 선택팩 14개 혜택은 작성했다.
문장 조건: 국내외겸용 해외 결제 시 국제브랜드 수수료 1%와 해외서비스 수수료 0.25% 면제. 결제 입력의 원금과 수수료 분리를 계산해야 한다. / 전월 실적 채워드림은 35만원 이상 40만원 미만 회원이 1일부터 25일까지 신청. 신청 다음날부터 월말까지 40만원 구간 혜택. 분기 1회 연 4회이며 취소할 수 없다. 신청 이력과 적용일을 별도로 표현해야 한다. / 배달 멤버십은 제외한다. 대형마트 주차장, 임대매장, 기업형 슈퍼마켓은 제외한다. 카페 앱주문은 제외한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다. / 핵심 해외 수수료 면제와 전월실적 채워드림 적용 이력을 엔진에서 표현해야 한다. 현재 파일은 출시 승인 대상이 아니다.
새 혜택 key: daily-fuel, daily-delivery, daily-telecom, daily-insurance-app, daily-shopping, daily-convenience, daily-hobby, family-bills, family-grocery, family-care, family-academy, family-mart, family-cafe, family-kids-cafe. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

kb-09790.yaml: blocked. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/kb/kb-09790.yaml.
원문: https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09790
손계산 12개. Spend.exclude_billing 기능이 없어 후불교통 무승인 전표만 실적에서 제외할 수 없다. 실적 경계에서 혜택 과지급 가능. 지원 가능한 거래 규칙과 손계산은 보존했다.
문장 조건: 가족카드 실적과 한도는 본인과 합산한다. 무승인 자판기, 터널통행료, 항공기내 결제는 실적에서 제외한다. 전표 매입 순서로 할인한도를 쓴다. / 부분 무이자 할부 이용금액도 전체를 실적에서 제외한다. 결제 입력의 무이자 여부에 부분 무이자도 표시해야 한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다. / 무승인 후불교통 결제만 실적에서 빼는 billing 조건을 실적 규칙에 더해야 한다. 일반 승인 철도 승차권을 제외하지 않도록 광범위한 transit 제외를 제거했다.
새 혜택 key: 없음. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

hyundai-xpe4.yaml: ready. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/hyundai/hyundai-xpe4.yaml.
원문: https://www.hyundaicard.com/cpc/cr/CPCCR0201_01.hc?cardWcd=XPE4 https://www.hyundaicard.com/upload/card/20260330_X.pdf
손계산 4개. 공식 원문 대조와 실제 앱 엔진 손계산 통과. 독립 검토와 운영 승인 대기.
문장 조건: 연간 이용금액 500만원마다 2만원 캐시백, 발급월 포함 12개월에 최대 10만원. 충족한 다음달 15일 이후 지급한다. 결제별 적립으로 나누지 않는다. / 인천공항 라운지와 발레파킹은 각각 일 1회 발급월 포함 12개월 연 2회. 전월 50만원이며 발급 다음달까지 실적 면제한다. / 긴급할인은 선지급 후 상환 약정 서비스이므로 결제별 혜택에 더하지 않는다. 가족카드 실적과 한도는 본인과 합산한다. / 연간 이용금액 500만원당 2만원, 연 최대 10만원 캐시백은 자동 계산하지 않는다. 공항 라운지와 발레파킹은 자동 계산하지 않는다. 전월 실적에 따른 거래별 1% 할인만 계산한다. / 긴급할인 선지급 약정을 이용 중이면 기본 1% 할인과 연간 캐시백은 긴급할인 상환에 쓰인다. 결제 계좌의 즉시 이익으로 더하지 않는다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다.
새 혜택 key: basic-1. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

hyundai-mzroe3.yaml: ready. 연회비·혜택·실적·신규·한도·중복·제외 7개 판단 확인.
사본: C:\Users\SSAFY\Desktop\pjt\cherryConsume\tmp\release-card-expansion\recommended-mixed. 바뀐 파일: catalog/cards/hyundai/hyundai-mzroe3.yaml.
원문: https://www.hyundaicard.com/cpc/cr/CPCCR0201_01.hc?cardWcd=MZROE3 https://www.hyundaicard.com/upload/card/%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_ZERO%20Ed3_%ED%8F%AC%EC%9D%B8%ED%8A%B8_260330.pdf
손계산 4개. 공식 원문 대조와 실제 앱 엔진 손계산 통과. 독립 검토와 운영 승인 대기.
문장 조건: M 긴급적립은 선지급 후 상환하는 별도 약정 서비스다. 결제마다 추가 적립되는 혜택이 아니며 일반 적립에 더하지 않는다. / 부분 무이자 할부는 수수료를 납부하는 개월의 이용 금액에만 적립한다. 가족카드는 회원별 별도 적립한다.
확인 필요: 현재 원문 규칙이 시작된 정확한 날짜를 확인해야 한다. 수집일을 잠정 적용 시작일로 둔다.
새 혜택 key: 없음. 빠진 혜택과 결제조건이 다른 혜택을 나눠 적었다.
공통 추가: needed_common.json 참고. 초중고 납입금은 education.primary_secondary_fee를 연결한다.

ZERO의 m-emergency-earn-500k는 결제별 보상이 아니라 상환 의무가 있는 선지급 서비스이므로 계산 혜택에서 제거하고 안내 문장으로 남겼다.
공통 파일은 수정하지 않았다. 전체 검사에 남은 오류는 필요한 공통 정의뿐이다. 담당 파일의 형식과 구조 오류는 0이다.
ready 네 파일만 docs/databricks.md의 손으로 승인하기 절차로 골드에 넣는다. 독립 검토와 운영 승인을 먼저 받아야 한다. KB ALL은 KB Pay 신규 신청 안내를 함께 확인해 on_sale을 유지했다.
KB 세 상품의 실적에서 transit 전체 제외를 제거했다. 무승인 후불교통 실적 제외에는 Spend.exclude_billing 기능이 필요해 세 카드 모두 blocked다. pending-cases의 올바른 기대값은 현재 엔진에서 실패한다.
현대 X는 연간 이용액 500만원당 2만원 최대 10만원 캐시백을 자동 계산하지 않는다. JADE는 연간 바우처와 라운지를 자동 계산하지 않는다. 승인 목록에 이 범위를 강조해야 한다.