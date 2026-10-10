# 출시용 카드 승인 목록

새 카드 134장을 준비했다. 운영 반영 뒤 기존 카드와 합쳐 193장이다. 운영 반영은 아직 하지 않았다.

새 카드 손계산 1478개, 기존 손계산 281개, 교육비 분류 연결 36개가 앱 계산과 일치했다. 카탈로그 오류 0개와 경고 14개. 실제 승인 함수 검사와 상품 중복 검사를 통과했다.

## 이번 목록에서 확인할 내용

- 2026-10-10 사용자가 "최대한 카드를 많이 담게, 너무 꼼꼼히 말고"라고 해 expand2부터 expand5까지 빠른 방식으로 조사했다. 조사 에이전트가 공식 원문의 핵심 숫자만 확인하고 다른 에이전트의 재대조는 하지 않았다. 손계산 사례는 혜택마다 양수와 실적 경계 정도로 줄였다. 지침은 research/expand*/PROMPT.md
- 담지 못하는 조건은 혜택을 덜 주는 쪽으로 옮겼다. 후불교통 실적 제외는 시내버스·지하철 업종 제외, 불분명한 한도는 함께 쓰는 쪽, 원문보다 넓은 업종에 걸리는 혜택은 뺐다. 핵심 혜택을 담지 못하는 카드는 보류했다
- 같은 상품의 다른 페이지는 카드를 따로 두지 않고 상품 코드만 더했다. I-나눔 셋, 카드의정석 I&U+, SK 주유 400
- 아래는 첫 목록에서 이어지는 확인 내용이다

- JADE Classic는 거래별 하나머니 적립을 계산한다. 바우처와 라운지는 자동 계산하지 않는다.
- 현대 X는 전월실적에 따른 거래별 1% 할인을 계산한다. 연간 500만원당 2만원 캐시백과 라운지·발레파킹은 자동 계산하지 않는다.
- 미미의 09:00 정각 포함 여부는 공식 문구가 명확하지 않아 09:00 미만으로 계산한다.
- zgm 구독의 일부 페이 제외 이름은 공식 문구에 없어 확인 안내로 남겼다.
- 매출표 접수 순서, 입점 매장, 과거 최초 결제 이력처럼 현재 결제 입력으로 알 수 없는 조건은 카드 상세 안내로 남겼다.
- 2026-10-10 expand1로 8장을 더했다. 올리 POINT는 해외 결제가 커피·편의점 등 ①~⑤ 영역 순위에 함께 쌓이지 않게 국내 결제만 세었다. 해피포인트 하나 체크의 취소분 차감 방식은 자동 계산하지 않는다.
- 새 공통 가맹점 뚜레쥬르, LFmall, 농협몰, 미니스톱을 더했다. 미니스톱은 기존 카드의 편의점 혜택에, 뚜레쥬르는 제과 혜택에 새로 걸린다. 두 업종 모두 원문 범위 안이다.

## 카드 목록

| 카드 | 연회비 | 계산 범위 |
|---|---:|---|
| [MULTI Oil 모바일카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=12932) | 15,000원 | 4대 정유사 주유·LPG 10% 할인 · 스타벅스·커피빈 5% 할인 · 페이결제 1% 할인 |
| [MULTI Any 체크카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=13823) | 없음 | 국내외 가맹점 0.2% 적립 · 페이결제 0.4% 적립 · 마트·SSM·백화점 0.6% 적립 외 2개 |
| [하나카드 원더카드 2.0 LIVING](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=15863) | 19,900원 | 아파트관리비·전기·가스 10% 할인 · 병원·약국 10% 할인 · 주유·LPG 충전 10% 할인 외 4개 |
| [하나카드 원더카드 2.0 FREE+](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=16947) | 19,900원 | 국내외 가맹점 0.8% 할인 · 하나페이·간편결제 온라인 1.2% 할인 · 쿠팡 2% 할인 외 6개 |
| [MOVING카드 GLOBAL모드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=19153) | 20,000원 | 온라인 간편결제 1% 적립 · 온라인 쇼핑 1% 적립 · 마트·슈퍼마켓·편의점 1% 적립 외 3개 |
| [케이뱅크-현대카드Z family Edition2](https://www.hyundaicard.com/upload/card/T_AOB-20260804-0944-62_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_%EC%BC%80%EC%9D%B4%EB%B1%85%ED%81%AC%20%ED%98%84%EB%8C%80%EC%B9%B4%EB%93%9CZ%20family%20Ed2_V2_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 20,000원 | 온라인몰 10% 청구 할인 · 병원·약국 10% 청구 할인 · 학원 10% 청구 할인 외 2개 |
| [케이뱅크-현대카드Z play](https://www.hyundaicard.com/upload/card/T_AOB-20260804-0944-62_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_%EC%BC%80%EC%9D%B4%EB%B1%85%ED%81%AC%20%ED%98%84%EB%8C%80%EC%B9%B4%EB%93%9CZ%20play%20Ed2_V2_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 20,000원 | 온라인몰 10% 청구 할인 · 일반음식점 10% 청구 할인 · 영화 10% 청구 할인 외 2개 |
| [NOL 카드](https://www.hyundaicard.com/upload/card/T_AZG-20260323-1455-28_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_NOL_V2_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 20,000원 | NOL 10% NOL 포인트 적립 · 커피전문점 10% NOL 포인트 적립 · 편의점 10% NOL 포인트 적립 외 5개 |
| [K-패스(신용)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=258&PDCD=0004&pageId=CA01010000) | 2,000/4,000원 | 평일 버스·지하철 1회 100~200원 청구할인 · 주말·공휴일 버스·지하철 1회 200~300원 청구할인 · 철도·고속버스 5% 청구할인 외 5개 |
| [AK IBK체크카드](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=298&PDCD=0001&pageId=CA01010000) | 없음 | AK플라자·AK몰 3% 청구할인 · AK플라자 5% 현장할인 · CGV·롯데시네마·메가박스 2천원 청구할인 외 2개 |
| [용인시민카드(신용)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=300&PDCD=0001&pageId=CA01010000) | 5,000/7,000원 | 버스·지하철 3% 청구할인 · 주유 리터당 60원 청구할인 · 대형마트 5% 청구할인 외 5개 |
| [I-나눔(일반)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=338&PDCD=0004&pageId=CA01010000) | 14,000/15,000원 | 온라인쇼핑·홈쇼핑·배달앱 1% 청구할인 · 대형마트·편의점·반려동물 1% 청구할인 · 커피전문점 1% 청구할인 외 6개 |
| [KB국민 Easy all카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09255) | 14,000/20,000원 | [A] 음식 3% 캐시백 · [A] 교육 3% 캐시백 · [A] 병원·약국 3% 캐시백 외 15개 |
| [The CJ 롯데카드](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P01795-A01795) | 5,000/6,000원 | CJ온스타일 5% 청구할인 · 올리브영 10% 현장할인 · 빕스 20% 현장할인 외 2개 |
| [K-패스엔로카](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P15644-A15644) | 20,000원 | 버스·지하철 10~15% 결제일 할인 · 커피 10~15% 결제일 할인 · 편의점 10~15% 결제일 할인 외 2개 |
| [다이소엔로카](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P15841-A15841) | 20,000원 | 다이소 30% 결제일 할인 · 음식점 10% 결제일 할인 · 배달앱 10% 결제일 할인 외 3개 |
| [국민행복카드(체크)](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90000320) | 없음 | A형 병·의원 3% 캐시백 · A형 온라인 쇼핑몰 3% 캐시백 · B형 어린이집·유치원·학원 3% 캐시백 외 7개 |
| [NH올원더풀카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010604) | 28,000/30,000원 | 할인 PACK 백화점 5% 청구할인 · 할인 PACK 대형마트 5% 청구할인 · 할인 PACK 홈쇼핑 5% 청구할인 외 34개 |
| [삼성 iD NOMAD 카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1786) | 47,000/49,000원 | 국내 가맹점 0.5% 빅포인트 적립 · 해외 2% 빅포인트 적립 · 여행·쇼핑 영역 1% 빅포인트 적립 외 4개 |
| [삼성 SFC iD SELECT ON 카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1878) | 20,000원 | [음식점 옵션] 음식점 주중 5% 할인 · [음식점 옵션] 음식점 주말 10% 할인 · [음식점 옵션] 온라인패션몰·쇼핑몰 5% 할인 외 12개 |
| [토스 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1882) | 15,000원 | 토스페이 15% 할인 · 토스쇼핑 15% 할인 · 온라인 간편결제 10% 할인 외 6개 |
| [한화이글스 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1909) | 20,000원 | 한화이글스 홈경기 입장권 50% 할인 · 한화이글스 팀스토어 50% 할인 · 디지털콘텐츠 50% 할인 외 6개 |
| [신한카드 Deep Store(우리먹거리)](https://www.shinhancard.com/pconts/html/card/apply/credit/1229261_2207.html) | 13,000/16,000원 | 생활쇼핑 5만원 이상 15% 할인 · 생활쇼핑 10% 할인 · 커피전문점·제과점 10% 할인 외 2개 |
| [신한카드 경차사랑 Life](https://www.shinhancard.com/pconts/html/card/apply/credit/1188377_2207.html) | 없음 | 경차 유류세 환급 휘발유·경유 리터당 250원 · 주유소 리터당 80원 할인 · 편의점 10% 할인 외 3개 |
| [카드의정석 I&U+](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=102717) | 12,000원 | 국내 가맹점 0.7% 청구할인 · 매출건당 100만원 이상 1.0% 청구할인 · S-OIL·HD현대오일뱅크 리터당 60원 청구할인 외 4개 |
| [위비트래블 J 체크카드](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=103490) | 없음 | 국내 쇼핑 간편결제 5% 캐시백 · 국내 쇼핑 온라인 5% 캐시백 · 올리브영 5% 캐시백 외 4개 |
| [밀리언달러 하나카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=14409) | 15,000원 | 해외 가맹점 0.7% 적립 · 스타벅스 사이렌오더 20% 적립 · 디지털 구독 20% 적립 외 2개 |
| [대구로 카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=16797) | 12,000원 | 대구로 앱 10% 청구할인 · 대구로 택시 앱 10% 청구할인 · 온라인 쇼핑 5% 청구할인 외 5개 |
| [신세계 트래블GO 하나카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=18398) | 20,000원 | 신세계백화점 주중 1% 적립 · 신세계백화점 주말 2% 적립 · 국내·해외 가맹점 0.7% 적립 외 3개 |
| [MOVING카드 PLAY모드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=19151) | 20,000원 | 커피 30% 적립 · 편의점 10% 적립 · 온라인 쇼핑 10% 적립 외 3개 |
| [Kia Members 경차전용카드](https://www.hyundaicard.com/upload/card/T_AO7-20260203-0822-01_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_%EA%B8%B0%EC%95%84_%EA%B2%BD%EC%B0%A8_V1_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 5,000원 | HD현대오일뱅크·SK에너지 리터당 200원 청구 할인 · HD현대오일뱅크·SK에너지 리터당 400원 청구 할인 · 현대해상 자동차 보험료 3만원 청구 할인 외 2개 |
| [GOLD FOR LOTTE DEPARTMENT STORE](https://www.hyundaicard.com/upload/card/T_AOB-20260818-1343-97_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_%EB%A1%AF%EB%8D%B0%EB%B0%B1%ED%99%94%EC%A0%90_GOLD_V3_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 150,000원 | 롯데백화점·롯데아울렛 10% M포인트 적립 · 국내외 가맹점 1% M포인트 적립 |
| [현대카드Z work Edition2](https://www.hyundaicard.com/cpc/cr/CPCCR0201_01.hc?cardWcd=ZWE2) | 20,000원 | 온라인 쇼핑몰 10% 청구 할인 · 편의점 10% 청구 할인 · 커피전문점 10% 청구 할인 외 3개 |
| [IBK hi 카드](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=258&PDCD=0001&pageId=CA01010000) | 2,000/4,000원 | 평일 버스·지하철 1회 100~200원 청구할인 · 주말·공휴일 버스·지하철 1회 200~300원 청구할인 · 철도·고속버스 5% 청구할인 외 5개 |
| [국민행복카드[체크]](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=293&PDCD=0002&pageId=CA01010000) | 없음 | A형 병·의원 3% 캐시백 · A형 온라인 쇼핑몰 3% 캐시백 · B형 어린이집·유치원·학원 3% 캐시백 외 7개 |
| [참! 좋은 다이소카드(신용)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=312&PDCD=0001&pageId=CA01010000) | 10,000/12,000원 | 다이소 30% 청구할인 · 전 주유소 리터당 40원 청구할인 · 편의점·올리브영 10% 청구할인 외 5개 |
| [KB국민 WELCOME PLUS 체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01605) | 없음 | 3대 대형마트 주말 5% 환급할인 · 이동통신요금 자동납부 2천원 환급할인 · 놀이공원 30% 환급할인 외 3개 |
| [KB국민 첵첵 체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01914) | 없음 | CU 편의점 건당 1천~2천원 환급할인 · 스타벅스 건당 1천~2천원 환급할인 · CGV 건당 1천~2천원 환급할인 외 6개 |
| [KB국민 kt M mobile Ⅱ 카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=04368) | 14,000/20,000원 | kt M mobile 알뜰폰 통신료 자동납부 청구할인 |
| [KB Members Plus 카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=07634) | 14,000/20,000원 | 주유·충전소 5% 청구할인 · 이동통신요금 자동납부 5% 청구할인 · 학원 5% 청구할인 외 4개 |
| [KB국민 노리2 체크카드 KB Pay](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=07964) | 없음 | 커피 10% 할인 · 모바일 10% 할인 · 문화 10% 할인 외 9개 |
| [KB ALL 카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09122) | 14,000/20,000원 | 국내 가맹점 1% 할인 · 해외 가맹점 2% 할인 · 쇼핑 멤버십 50% 할인 외 2개 |
| [KB국민 WE:SH Travel 카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09561) | 19,000/25,000원 | 온라인 쇼핑 KB Pay 10% 청구할인 · 온라인 패션 KB Pay 10% 청구할인 · 커피 KB Pay 10% 청구할인 외 4개 |
| [KB NEED Edu 카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09790) | 19,000/20,000/25,000/26,000원 | 교육 업종 5% 할인 (전월실적 40만원 이상) · 교육 업종 5% 할인 (전월실적 80만원 이상) · 교육 업종 5% 할인 (전월실적 160만원 이상) 외 2개 |
| [KB NEED Pay 카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09800) | 13,000/19,000원 | KB Pay 15% 청구할인 · 네이버페이 10% 청구할인 · 카카오페이 10% 청구할인 외 4개 |
| [LG U+ X LOCA](https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/2022-A00005_20220519_10002.pdf) | 20,000원 | LG유플러스 통신요금 결제일 할인 발급월 포함 25개월까지 · LG유플러스 통신요금 결제일 할인 발급월 포함 25개월 초과 |
| [SK인텔릭스 X LOCA](https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/2023-A00028_20251030_10003.pdf) | 20,000원 | SK인텔릭스 구독료 자동납부 결제일 할인 |
| [SK인텔릭스 롯데카드](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P15883-A15883) | 20,000원 | SK인텔릭스 구독료 자동납부 결제일 할인 |
| [라이언 치즈 체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010013) | 없음 | Single Cheezzz 월~금 0.5% NH포인트 적립 · Double Cheezzz 토·일 1% NH포인트 적립 · Triple Cheezzz 교통 1.5% NH포인트 적립 외 6개 |
| [KT 할부 S 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1839) | 25,000원 | KT 통신요금 정기결제 할인 · 커피전문점 5% 할인 · 스타벅스 5% 할인 외 2개 |
| [신세계KB국민은행 삼성체크카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=ABP1333) | 없음 | 대중교통·이동통신요금 1% 캐시백 · 음식점·온라인 쇼핑몰 0.4% 캐시백 · 일반 가맹점 0.2% 캐시백 외 2개 |
| [SC제일은행 삼성체크카드 CASHBACK](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=ABP1459) | 없음 | 음식점·주유·할인점 0.3% 캐시백 · 일반 가맹점 0.2% 캐시백 |
| [신한카드 처음 체크](https://www.shinhancard.com/pconts/html/card/apply/check/1234710_2206.html) | 없음 | 편의점 5% 적립 · 패스트푸드 5% 적립 · 카페 5% 적립 외 2개 |
| [성남사랑 신한카드 Deep Dream 체크(chak)](https://www.shinhancard.com/pconts/html/card/apply/check/1201121_2206.html) | 없음 | 모두드림 0.2% 적립 · 더해드림 할인점 0.6% 적립 · 더해드림 편의점·잡화 0.6% 적립 외 9개 |
| [신한카드 SOL글로벌U 체크(쿠로미)](https://www.shinhancard.com/pconts/html/card/apply/check/1230631_2206.html) | 없음 | 대중교통 10% 캐시백 · 이동통신요금 10% 캐시백 · 커피·편의점 10% 캐시백 외 2개 |
| [SK 주유 400 우리카드](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=104183) | 25,000원 | SK주유소 리터당 120원 청구할인 · SK주유소 리터당 150원 청구할인 · SK주유소 리터당 250원 청구할인 외 4개 |
| [신세계 하나 체크카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=9656) | 없음 | 신세계백화점 5% 캐쉬백 (월 3만원) · 신세계백화점 신세계포인트 0.2% 적립 · 버스·지하철 후불교통 월 3만원 이상 7% 캐쉬백 (월 5천원) |
| [애터미 Any PLUS 카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=11584) | 17,000원 | 국내 가맹점 0.7% 청구할인 · 제약 업종 온라인 0.7% 청구할인 · 국내 온라인 가맹점 1.7% 청구할인 (월 10만원) 외 1개 |
| [모두의 건강 체크카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=13539) | 없음 | 병원·동물병원·약국 0.4% 적립 · 이마트·롯데마트·홈플러스 0.3% 적립 · 국내외 전가맹점 0.2% 적립 |
| [로마드 하나카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=14783) | 18,000원 | 로마드 구독 요금 자동이체 월 13,000원 청구할인 · G마켓·옥션·11번가·롯데홈쇼핑·GS SHOP 3% 청구할인 · 스타벅스 5% 청구할인 |
| [K-패스 하나 체크카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=17033) | 없음 | 버스·지하철 후불교통 10% 캐쉬백 (월 3천원) · 버스·지하철 후불교통 10% 캐쉬백 (월 6천원) · 올리브영 1% 캐쉬백 (다이소와 합쳐 월 1만원) 외 2개 |
| [하나멤버스 1Q(원큐) 카드 ALL in](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=4984) | 28,000/30,000원 | 통신·렌탈·케이블TV·전기 자동이체 10만원마다 5천 하나머니 · 버스·지하철 10만원마다 5천 하나머니 · 마트 10만원마다 5천 하나머니 외 8개 |
| [트래블로그+(플러스) 신용카드](https://www.hanacard.co.kr/OPI41000000D.web?CD_PD_SEQ=18956) | 20,000원 | 해외 가맹점 3% 하나머니 적립 · 국내 항공사 3% 하나머니 적립 · 면세점 3% 하나머니 적립 외 3개 |
| [케이뱅크-현대카드Z work Edition2](https://www.hyundaicard.com/upload/card/T_AOB-20260804-0944-62_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_%EC%BC%80%EC%9D%B4%EB%B1%85%ED%81%AC%20%ED%98%84%EB%8C%80%EC%B9%B4%EB%93%9CZ%20work%20Ed2_V2_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 20,000원 | 온라인 쇼핑몰 10% 청구 할인 · 편의점 10% 청구 할인 · 커피전문점 10% 청구 할인 외 3개 |
| [현대카드 MX Black Edition2](https://www.hyundaicard.com/cpc/cr/CPCCR0201_01.hc?cardWcd=MXBE2) | 200,000원 | 국내외 가맹점 1% M포인트 적립 · 온라인 쇼핑 10% 청구 할인 · 백화점 10% 청구 할인 외 3개 |
| [the Orange](https://www.hyundaicard.com/cpc/cr/CPCCR0621_11.hc?cardflag=TO) | 200,000원 | 국내외 가맹점 1% M포인트 적립 · 온라인몰 10% M포인트 적립 · 다이닝 10% M포인트 적립 외 3개 |
| [K-패스(체크)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=309&PDCD=0852&pageId=CA01010000) | 없음 | 버스·지하철 건당 100원 청구할인 · 편의점·올리브영 5% 청구할인 · 쿠팡·티몬·위메프 10% 청구할인 외 2개 |
| [참! 좋은 다이소카드(체크)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=312&PDCD=0002&pageId=CA01010000) | 없음 | 다이소 20% 청구할인 · 편의점·올리브영 5% 청구할인 · 쿠팡·티몬·위메프 10% 청구할인 외 3개 |
| [코웨이 IBK 카드](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=321&PDCD=0001&pageId=CA01010000) | 12,000/15,000원 | 코웨이 렌탈료 자동이체 청구할인 |
| [I-PET](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=342&PDCD=0001&pageId=CA01010000) | 18,000/19,000원 | 동물병원·반려동물업종 30% 청구할인 · 온라인쇼핑 10% 청구할인 · 커피 10% 청구할인 외 2개 |
| [I-Campus 체크(자기개발형)](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=345&PDCD=0002&pageId=CA01010000) | 없음 | 철도·고속버스 10% 청구할인 · 이동통신요금 자동납부 5% 청구할인 · 학원 5% 청구할인 외 4개 |
| [KB국민 스타체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01552) | 없음 | GS칼텍스 주중 리터당 50원 환급할인 · GS칼텍스 주말 리터당 60원 환급할인 · 에버랜드 50% 환급할인 외 7개 |
| [KB국민 포인트리체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01556) | 없음 | GS칼텍스 주중 리터당 50원 포인트리 적립 · GS칼텍스 주말 리터당 60원 포인트리 적립 · 에버랜드 50% 포인트리 적립 외 7개 |
| [LG U+ KB국민체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01990) | 없음 | LG U+ 이동통신요금 자동납부 4~6천원 환급할인 · 스타벅스 10% 환급할인 · CGV 10% 환급할인 |
| [KB국민 그린카드(서울형)](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=02086) | 없음 | 국내외 가맹점 0.5% 에코머니 적립 · 대형마트·백화점·인터넷쇼핑몰 0.5~2.5% 에코머니 추가적립 · 버스·지하철 9.5~19.5% 에코머니 추가적립 외 1개 |
| [KB저축은행 팡팡 KB체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09581) | 없음 | 오픈마켓 10% 환급할인 · 오픈마켓 KB Pay 결제 10% 추가 환급할인 · 스타벅스·커피빈 10% 환급할인 외 5개 |
| [KB 마라톤카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09821) | 24,000/30,000원 | 러너블 20% 청구할인 · OTT 정기결제 30% 청구할인 · 편의점 업종 5% 청구할인 외 1개 |
| [쿠쿠 X LOCA](https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/2023-A00030_20260916_10003.pdf) | 20,000원 | 쿠쿠 렌탈료 자동납부 결제일 할인 |
| [MY RENTAL+ 롯데카드](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P14114-A14114) | 15,000/18,000원 | 롯데렌탈 월 대여료 자동결제 결제일 할인 · 주유소 5% 결제일 할인 |
| [보험엔로카](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P14828-A14828) | 20,000원 | 생명·손해보험료 자동이체 결제일 할인 |
| [바디프랜드 X LOCA](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P15803-A15803) | 20,000원 | 바디프랜드 렌탈료 자동납부 결제일 할인 |
| [NH1961체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010117) | 없음 | 국내외 전가맹점 0.2% NH포인트 적립 · 농협 판매장 0.3% NH포인트 적립 · NH Pay 결제 0.1% 추가 적립 외 4개 |
| [GOODGAME 체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010186) | 없음 | 애플 앱스토어·구글 플레이 10% NH포인트 적립 · 스팀 10% NH포인트 적립 · PC방 10% NH포인트 적립 외 2개 |
| [NH 모두의카드(체크)](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010470) | 없음 | 버스·지하철 10% 캐시백 · 쏘카 5% 캐시백 · 이동통신요금 자동납부 5% 캐시백 외 3개 |
| [NH 무럭이 체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010491) | 없음 | 국내외 NH포인트 0.2% 기본 적립 · 스마트 적립 1위 온라인쇼핑·배달앱 0.4% 추가 · 스마트 적립 1위 오프라인 마트 0.4% 추가 외 16개 |
| [삼성 iD VITA 카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1790) | 20,000원 | 병의원·약국 20% 할인 · 보험 10% 할인 · 아모레몰·초록마을 20% 할인 외 3개 |
| [하나투어 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1834) | 20,000원 | 생활요금 정기결제 10% 할인 · 생활요금 정기결제 5% 할인 · 주유·온라인쇼핑몰·스타벅스 10% 할인 외 6개 |
| [알라딘 만권당 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1850) | 15,000원 | 알라딘 15% 할인 · 알라딘 만권당 월정액 50% 할인 · 온라인쇼핑몰 5% 할인 외 4개 |
| [T PREMIUM 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1869) | 50,000원 | SKT·SK브로드밴드·SK 세븐모바일 통신요금 할인 · 해외 5% 할인 · 항공 3% 할인 |
| [G마켓 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1889) | 15,000원 | G마켓·옥션 5% 빅포인트 적립 · 편의점 3% 빅포인트 적립 · 배달앱 3% 빅포인트 적립 외 7개 |
| [U+ 라이트 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1893) | 25,000원 | LG U+ 통신요금 정기결제 할인 · 커피전문점 5% 할인 · 스타벅스 5% 할인 외 2개 |
| [롯데마트 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1894) | 20,000원 | 롯데마트·롯데슈퍼 5%/10% 할인 · 롯데마트 제타 5%/10% 할인 · 음식점 5% 할인 외 5개 |
| [신한카드 Way 체크(쥬라기)](https://www.shinhancard.com/pconts/html/card/apply/check/1216885_2206.html) | 없음 | 대중교통 최대 5% 적립 · 통신요금 최대 2% 적립 · 편의점·생활잡화 최대 2% 적립 외 3개 |
| [배민 신한카드 밥친구](https://www.shinhancard.com/pconts/html/card/apply/credit/1234575_2207.html) | 12,000/15,000원 | 배달의민족 5% 결제일 할인 · 배민 외 가맹점 1% 결제일 할인 |
| [신한카드 SOL글로벌 체크(산리오캐릭터즈)](https://www.shinhancard.com/pconts/html/card/apply/check/1230627_2206.html) | 없음 | 대중교통 10% 캐시백 · 이동통신요금 10% 캐시백 · 대형마트 10% 캐시백 외 2개 |
| [K-패스 우리카드(체크)](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=102865) | 없음 | 스타벅스·폴바셋 10% 캐시백 · CU·GS25 10% 캐시백 · 버스·지하철 10% 캐시백 |
| [카드의정석2 ExK 체크](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=103496) | 없음 | 아웃백 5천원 캐시백 (1~6월) · 아웃백 5천원 캐시백 (7~12월) · 메가MGC커피·컴포즈커피 5% 캐시백 외 3개 |
| [VIVA+ 체크카드](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41006884P&CD_PD_SEQ=9047) | 없음 | 해외 가맹점 국제브랜드수수료 1% 면제 · 평일 점심 음식점·커피·편의점 7% 캐쉬백 |
| [국민 행복 카드](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41012792P&CD_PD_SEQ=12792) | 없음 | 어린이집·유치원 본인부담금 월 1만원 청구할인 · 스타벅스·커피빈 10% 청구할인 · 병원·약국 5% 청구할인 |
| [하나 원큐 카드](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41012942P&CD_PD_SEQ=12942) | 15,000원 | 하나페이 결제 1.8% 하나머니 적립 · 해외 전가맹점 1.8% 하나머니 적립 · 국내 전가맹점 0.8% 하나머니 적립 |
| [JADE Prime](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41017769P&CD_PD_SEQ=17769) | 295,000/300,000원 | 디지털 컨텐츠 자동납부 50% 하나머니 적립 · 택시 50% 하나머니 적립 · 주유 리터당 150 하나머니 적립 외 7개 |
| [#MY WAY(샵 마이웨이) 카드](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41006884P&CD_PD_SEQ=15444) | 20,000원 | 버스·지하철 1,200원당 300원 청구할인 · 커피 4사 건당 300원 청구할인 · 편의점 4사 건당 300원 청구할인 외 5개 |
| [그린 카드](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41006884P&CD_PD_SEQ=1215) | 없음 | 국내 가맹점 0.2~0.8% 에코머니 적립 · 많이 쓴 2개 업종 대형할인점 1~4% 적립 · 많이 쓴 2개 업종 백화점 1~4% 적립 외 5개 |
| [HERO 체크카드](https://www.hanacard.co.kr/OPI41000000D.web?schID=pcd&mID=PI41006884P&CD_PD_SEQ=18643) | 없음 | 구독 10% 하나머니 적립 · 통신·관리비·전기·가스 5% 하나머니 적립 · 대형마트 5% 하나머니 적립 외 4개 |
| [SILVER FOR LOTTE DEPARTMENT STORE](https://www.hyundaicard.com/upload/card/T_AOB-20260818-1343-97_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_%EB%A1%AF%EB%8D%B0%EB%B0%B1%ED%99%94%EC%A0%90_SILVER_V3_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 30,000원 | 롯데백화점·롯데아울렛 5% M포인트 적립 · 국내외 가맹점 1% M포인트 적립 |
| [kt-현대카드M Edition3(청구할인형)](https://www.hyundaicard.com/upload/card/T_AOB-20260403-1734-28_%EA%B0%80%EC%9D%B4%EB%93%9C%EB%B6%81_KT_M%20Ed3_%EC%B2%AD%EA%B5%AC_V3_%EA%B3%B5%EC%8B%9C%EC%8B%A4%EC%9A%A9.pdf) | 30,000원 | kt 통신요금 자동이체 청구할인 (1~24개월 차 월 1만3천원·1만8천원, 25개월 차부터 월 6천원) |
| [I-ALL](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=338&PDCD=0001&pageId=CA01010000) | 14,000/15,000원 | 국내·외 가맹점 0.5% 청구할인 · 온라인쇼핑·홈쇼핑·배달앱 1% 청구할인 · 대형마트·편의점·반려동물 1% 청구할인 외 7개 |
| [I-ALL 체크](https://www.ibk.co.kr/cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=338&PDCD=0012&pageId=CA01010000) | 없음 | 국내·외 가맹점 0.2% 청구할인 · 온라인쇼핑 0.6% 청구할인 · 커피전문점 0.6% 청구할인 외 3개 |
| [KB국민 노리 체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01664) | 없음 | 버스·지하철 10% 할인 · 이동통신요금 자동이체 2,500원 할인 · CGV 35% 할인 외 5개 |
| [KB국민 해피노리 체크카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=01670) | 없음 | 버스·지하철 10% 할인 · 이동통신요금 자동이체 2,500원 할인 · CGV 35% 할인 외 6개 |
| [캐시노트 KB국민카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=04291) | 20,000원 | 캐시노트 플러스 멤버십 청구할인 · 국내외 가맹점 0.1% 청구할인 · 전자상거래·주유·통신 0.3% 청구할인 외 3개 |
| [AK KB국민카드](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=04444) | 12,000원 | AK PLAZA 5% 청구할인 · AK PLAZA 7% 청구할인 · AK PLAZA 10% 청구할인 외 4개 |
| [American Express Blue KB Kookmin Card](https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=09115) | 13,000/19,000원 | 온라인 쇼핑 KB Pay 10% 할인 · SK에너지·GS칼텍스 리터당 100원 할인 · CU·GS25 5% 할인 외 4개 |
| [아파트아이 X 디지로카](https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/2025-A00004_20250414_10001.pdf) | 20,000원 | 아파트관리비 자동납부 10% 결제일 할인 · 쿠팡·마켓컬리·SSG.COM 5% 결제일 할인 · 배달앱 5% 결제일 할인 외 3개 |
| [LOCA LIKIT](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P13746-A13746) | 10,000원 | 스타벅스 50% 결제일 할인 · 간편결제 스타벅스 60% 결제일 할인 · 롯데시네마·CGV 50% 결제일 할인 외 3개 |
| [LOCA X BS RENTAL](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P13828-A13828) | 20,000원 | BS렌탈 렌탈료 자동납부 결제일 할인 |
| [LOCA 100 Life](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P13846-A13846) | 20,000원 | 주유 5% 결제일 할인 · 보험료 자동납부 5% 결제일 할인 · 이동통신 자동납부 5% 결제일 할인 외 1개 |
| [청호나이스 X LOCA](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P15683-A15683) | 20,000원 | 청호나이스 렌탈료 자동납부 결제일 할인 |
| [쿠쿠 롯데카드](https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P15895-A15895) | 20,000원 | 쿠쿠 렌탈료 자동납부 결제일 할인 |
| [부자되세요 아파트카드(비씨)](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90000371) | 10,000/12,000원 | 아파트관리비 자동이체 5천원 청구할인 · 아파트관리비 자동이체 1만원 청구할인 · 하나로마트·이마트·홈플러스·롯데마트 5% 청구할인 외 3개 |
| [NH1934 체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010004) | 없음 | 월~토 국내·외 0.2% 청구할인 · 일요일 국내·외 0.2% 청구할인 · 일요일 국내 0.3% 청구할인 외 1개 |
| [폼 체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90010508) | 없음 | 편의점·패스트푸드·커피 건당 200원 할인 · 올리브영 건당 500원 할인 · 시내·마을버스·지하철 5% 할인 외 1개 |
| [올바른GLOBAL체크카드](https://card.nonghyup.com/servlet/IpCc2021R.act?CD_WRS_SQNO=90000390) | 없음 | 해외 이용 2% 캐시백 · 10대 업종 0.5% 캐시백 · 10대 업종 1% 캐시백 외 2개 |
| [트레이더스신세계 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1602) | 15,000원 | 트레이더스 1~5% 할인 · 서점·학습지 5% 할인 · 병원·약국 5% 할인 외 3개 |
| [요기요 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1690) | 10,000원 | 요기요 1% 할인 · 요기요 10% 할인 · 커피전문점·편의점·다이소 5% 할인 외 2개 |
| [삼성 iD MOVE 카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1762) | 20,000원 | 버스·지하철 10% 할인 · 택시 10% 할인 · 이동통신 정기결제 10% 할인 외 6개 |
| [THE iD. PLATINUM (포인트)](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1779) | 215,000/220,000원 | 국내 가맹점 1% 빅포인트 적립 · 생활 편의 영역 1.2% 빅포인트 적립 · 백화점 1.2% 빅포인트 적립 외 7개 |
| [삼성 iD GLOBAL 카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1824) | 20,000원 | 해외 오프라인 삼성페이 5% 할인 · 해외 2% 할인 · 인앱 결제·디지털콘텐츠·멤버십 50% 할인 외 5개 |
| [삼성 iD STATION 카드 (SK에너지)](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1855) | 15,000원 | SK에너지 주유 10% 할인 · 통신요금 정기결제 5% 할인 · 편의점 5% 할인 외 1개 |
| [삼성 iD SELECT ON 카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1877) | 20,000원 | 음식점 주중 5% 할인 · 음식점 주말 10% 할인 · 온라인쇼핑 5% 할인 (음식점 옵션) 외 12개 |
| [오아시스 삼성카드](https://www.samsungcard.com/home/card/cardinfo/PGHPPCCCardCardinfoDetails001?code=AAP1891) | 15,000원 | 오아시스마켓 5,000원 할인 · 커피전문점·델리 50% 할인 · 스타벅스 50% 할인 외 3개 |
| [카드의정석 TEN](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=103686) | 12,000원 | 커피 10% 청구할인 · 편의점 10% 청구할인 · 후불 버스·지하철 10% 청구할인 외 6개 |
| [카드의정석 EVERY DIRECT](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=103740) | 12,000원 | 국내외 가맹점 0.5% 청구할인 · 멤버십 자동납부 20% 할인 · OTT 정기결제 20% 할인 외 3개 |
| [카드의정석 SHOPPING](https://pc.wooricard.com/dcpc/yh1/crd/crd01/H1CRD101S02.do?cdPrdCd=834221) | 10,000/12,000원 | 온라인 쇼핑 10% 청구할인 · 오프라인 쇼핑 10% 청구할인 · 온라인 4대 PAY 5% 추가 청구할인 외 2개 |


## 승인 뒤 처리

승인하면 파일 업로드, 공통 항목과 기존 카드 분류 연결 승인, 새 카드별 승인과 검수 대기 닫기, 봇 내보내기와 앱 카탈로그 확인을 AI가 처리한다. 새 초중고와 유치원 업종이 기존 카드에서 적립 대상으로 바뀌지 않도록 기존 카드 12개와 현대 공통 규칙 1개의 제외 목록을 연결했다. 기존 제외 범위와 혜택을 삭제하지 않았다.

전체 일반 초안 2,162장 중 구조 검사 오류 없이 계산 혜택이 있는 것은 1,034장이다. 이는 원문 대조 완료 수가 아니다. 추가 원문 조사와 계산 기능 보완을 이어 할 대상은 [전체 결과](all-results.json)에 기록했다. KB 노리2·ALL·NEED Edu의 후불교통 실적 제외와 달달의 교통 월합산 조건 등은 실제 거래 금액을 바꾸므로 이번 승인에서 뺐다.

올릴 파일과 지문은 [승인 파일 묶음](approval-manifest.json), 시험 결과는 [검증 기록](checks.json)에 있다. 운영 승인 전 현재 골드 값과 초안 번호를 다시 확인한다.
