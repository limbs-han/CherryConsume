# 008 상품공시실 조사

계획 1단계. 2026-10-03 curl로 받았다. User-Agent `cherryconsume-collector`, 요청 사이 2~3초, 카드사마다 15회 안쪽. 받은 원문은 저장소에 넣지 않는다. 확인한 것만 적고 추측은 표시한다.

## 롯데카드

- 막힘: `robots.txt`는 프로토콜과 상관없이 늘 응답이 없다. curl 28. 다른 주소는 기본 설정(HTTP/2 협상)에서 연결이 끊기고(curl 56), `--http1.1`로 받으면 모두 200이다. 쿠키와 CSRF는 필요 없다. 수집기는 HTTP/1.1로 받는다. 끊기는 까닭이 HTTP/2 협상인지 직전 타임아웃 뒤의 보호장치인지는 추측이다.
- 전체 목록: `POST /app/LPSCHAA_V100.lc`, 폼 `collection=disclosure&listcount=500&startcount=0&query=`. 응답의 `Content`가 다시 JSON 글이고 `result.collection[0].docs`가 카드다. 총 531건, 500건 가운데 판매 중 282, 발급 종료 218. 신용과 체크가 한 목록에 섞여 있고 구분 칸이 없다.
- 칸: 이름 `VT_CD_KND_NM`, PDF `https://image.lottecard.co.kr/UploadFiles/cardProvisionPath/<OCY_FILE_NM>`, 발급 종료 `ISU_E_YN`, 마지막 게시일 `BULT_SDT`. 단종일, 출시일, 카드 코드, 상품 페이지는 없다. `DOCID`로 상품 이력 팝업 `LPCMNPD_AJAX.lc?num=135`를 부를 수 있다. 개정 이력이 있는지는 아직 안 봤다.
- 판매 중 카드의 코드와 그림: `POST /app/LPCDADA_A100.lc`(신용 일반), `A101`(제휴), `A102`(프리미엄), 체크는 `LPCDAEA` 쪽으로 추측. 한 쪽 9장, `Param.totalRowCnt`가 총 쪽수. 응답 HTML에서 코드 `vtCdKndC`, 상품 페이지 `LPCDADB_V100.lc?vtCdKndC=<코드>`, 그림 `image.lottecard.co.kr/UploadFiles/ecenterPath/cdInfo/ecenterCdInfo<코드>_nm1_v.png`.
- 공시 목록과 카드 목록은 공통 키가 없어 이름으로 짝짓는다. 표기가 다를 수 있어 사람 확인이 필요하다.
- PDF는 직접 주소. HEAD 200, `application/pdf`, 538KB.

## 카카오뱅크

- 막힘: `www.kakaobank.com`의 robots.txt가 구글, 네이버, 다음, 페이스북만 허용하고 나머지는 전부 금지다. 기술적 차단은 없고 모두 200이었다. 카탈로그 카드사 파일의 "robots.txt가 막아 받지 않는다"가 지금도 맞다. 삼성과 IBK처럼 무시하고 받을지 사용자가 정한다. 공시 파일이 있는 `og.kakaobank.io`는 다른 호스트다.
- 전체 목록: `GET /api/v1/docs/app/productGroupList`. 76그룹 가운데 `chnl_prgr_cd == "03"`이 카드 5그룹. 프렌즈 체크 30, mini 77, 개인사업자 체크 7007, 모임 체크 302, 앱카드 304. 앱카드는 실물 카드가 아닐 수 있다.
- 그룹별 문서: `GET /api/v1/docs/app/<그룹번호>?hmpg_yn=Y`. `agreements[]`에 문서마다 `doc_nm`, 적용일 `aply_stdd`, `pdf_doc_file_id`, `html_doc_file_id`, `txt_doc_file_id`, 종류 `intg_doc_typ_lccd`. 04가 상품설명서. TXT 판이 있어 글 뽑기가 쉬울 수 있다.
- 칸: 이름 `stpl_group_nm`, 코드 `stpl_group_no`, PDF `https://og.kakaobank.io/view/<pdf_doc_file_id>`나 `/download/<id>`. 상품 페이지는 고정 주소 넷. 그림은 상품 페이지의 `img`가 같은 `og.kakaobank.io/view/<uuid>`다. 상품 페이지의 `data-checkcard-group-id`가 공시 그룹 번호라 둘을 짝지을 수 있다.
- 단종: 별도 칸이 없고 이름 뒤 괄호 표기뿐이다. 카드 5그룹은 모두 판매 중.
- PDF는 직접 주소. HEAD 200, `application/pdf`, 179KB.

## 삼성카드

- 막힘: robots.txt는 구글, 네이버, GPTBot, ClaudeBot 같은 이름 붙은 봇에만 안내 페이지 40개쯤을 열고 나머지는 전부 막는다. 기술적 차단은 없어 10회 모두 200이었다. 쿠키와 CSRF는 필요 없다.
- 전체 카드 코드 사전: `GET /home/card/cardinfo/PGHPPDCCardCardinfoRecommendPC001`. Nuxt 서버 렌더링이라 curl 응답 안 `window.__NUXT__=(function(a,b,…){…}(값들))`에 데이터가 있다. 함수 호출 모양이라 풀어야 한다. `data[0].wcms`에 `{code, detailUrl}` 1,383개. 접두사 AAP 1,221, ABP 110, ACP 52이고 신용 개인, 체크, 기업으로 추측. 추천 탭 16개의 합집합이 판매 중 신용 개인카드 134장이다. 나머지는 단종으로 추측. 판매 상태 칸은 없다.
- 체크카드와 사업자카드는 같은 앱의 다른 경로다. `PGHPPCCCardCardinfoCheckcard001`, `PGHPPCCCardCardinfoIndividualBizcard001` 등. 아직 받지 않았다.
- 카드 상세 JSON: `https://static11.samsungcard.com` + `detailUrl`. 그림 `wcms/home/scard/image/personal/b_<코드>.png`, 뒷면 `_back`, 작은 그림 `s_`. 연회비, 부가서비스, 유의사항, 혜택별 HTML 조각이 모두 static11의 정적 파일이다. 단종 카드의 상세 JSON은 `designList`, `benefit`이 빈 배열이고 그림이 `b_basic.png`다. 사람용 상품 페이지 주소는 `PGHPPCCCardCardinfoDetails001?code=<코드>` 모양으로 추측했고 확인은 못 했다.
- 상품설명서는 "이용안내장" PDF이고 신용카드 상품약관 공시 게시판에 있다. `POST /frontservice/SHPPCC0247S01`, 본문 `{"cndt":{"no1PgeSize":"10","pgeNo":"1","itgBlbdChnlDvC":"01","itgBlbdTpDvC":"19",…}}`. 총 564건. 글마다 카드 코드 `bgdAlncPdC`, 제목, 게시 시작일 `bltnStrtdt`, 본문 안에 출시일 글자(형식이 제각각), 첨부 `uploadFileList[]`에 파일명과 암호화된 그룹 번호. PDF 직접 주소는 없고 다운로드 주소 형식은 상세 페이지 `UHPPCI0262M0.jsp`를 한 번 더 봐야 한다. 한 번에 받는 수 `no1PgeSize` 최대값도 아직 모른다.
- 단종일은 어디에도 없다.

## IBK기업은행

- 막힘: robots.txt가 도박 상담 페이지 하나만 열고 전부 막는다. 기술적 차단은 없어 9회 모두 200. 쿠키와 CSRF는 필요 없다. 자바스크립트 없이 목록, 상세, PDF가 모두 받힌다.
- 전체 목록: `GET /cardbiz/listBizNew.ibk?pageId=CA01010000`. 서버 렌더링이고 한 쪽 10장, 쪽 넘김은 `POST /cardbiz/listBizNew.ibk`에 `pageNum`. `CardSaleYn=A` 전체 14쪽 135장, `=1` 판매 중 13쪽. 판매 중지는 5~14장이고 목록 아이콘 `ic_sell_stop2.gif`로 표시된다. 종류별 탭은 `pageId`만 다르다. 신용 `CA01020000`, 체크 `CA01030000`.
- 상세: 목록의 `detail(cd1,cd2,cd3,cd4,cd5,cd_all)`은 폼 POST 하나다. GET으로도 된다. `GET /cardbiz/detailBizNew.ibk?PDLN_CD=12&PDGR_CD=11&PDTM_CD=309&PDCD=0001&pageId=CA01010000`. 카드 코드 `ALL_PDCD`는 네 코드를 이은 11자리. 같은 상품의 신용과 체크는 마지막 네 자리만 다르다.
- 칸: 이름, 한 줄 요약, 그림 `/fup/finemall/card/<파일>.png`, 상세의 약관 구역에 "개인설명서" PDF 직접 링크 `/fup/customer/form/<파일>.pdf`. HEAD 200, 647KB. 연회비, 브랜드, 심의필 날짜가 상세에 있다. 출시일과 단종일은 없다.
- 카드 신청 사이트 `cardapplication.ibk.co.kr`의 `card_prdc_id`는 다른 코드 체계다. 상품 페이지로는 쓰지 않는다.

## KB국민카드

- 막힘 없음. 쿠키와 CSRF 필요 없다. 자바스크립트 없이 표가 HTML에 들어 있다.
- 전체 목록: 상품공시실 > 약관 > 금융약관 `https://card.kbcard.com/SVC/DVIEW/HSHMCXCRSZZC0002`. GET이 개인신용 1쪽, 쪽 넘김은 같은 주소에 POST로 `카드분류코드=0`, `pageCount=<쪽>`. 폼 칸 이름이 한글이다. 한 쪽 10건, 개인신용 489건이라 49쪽. 개인체크 탭 `카드분류코드=1`은 세 가지 인코딩으로 POST해도 개인신용이 와서 못 받았다. 브라우저 개발자 도구로 실제 요청 본문을 봐야 한다.
- 칸: 상품명, 상품설명서 PDF 직접 주소 `https://img2.kbcard.com/obj/card/download/<코드>__prdctOpmn_<등록일>.pdf`, 출시일, 발급중단일. **단종일이 있는 유일한 카드사다.** 1쪽 10건 중 9건이 단종이라 단종 카드가 대부분이다. 카드 코드는 등록이력 버튼의 5자리이고 상품 페이지의 `cooperationcode`와 같다.
- 상품 페이지 `https://card.kbcard.com/CRD/DVIEW/HCAMCXPRICAC0076?mainCC=a&cooperationcode=<코드>`, 그림 `https://img1.kbcard.com/ST/img/cxc/kbcard/upload/img/product/<코드>_img.png`. 단종 카드 코드로도 열리는지는 안 봤다.
- PDF HEAD 200, `application/pdf`, 364KB.

## 우리카드

- 막힘 없음. 다만 공시실 약관 탭 `https://pc.wooricard.com/dcpc/yh1/cct/cct11/prdntc/H1CCT211S09.do`의 표는 `POST getMainDataList.pwkjson`이 채우고, 평문 JSON을 보내면 `ERROR.SYS.002`가 온다. 페이지에 심어진 난독화 스크립트가 요청 본문을 암호화하는 것으로 추측한다. 응답에 `inOutDataEnc: true`가 있다. **자바스크립트 실행 없이는 못 받는다. Playwright가 필요하다.**
- 표 머리글: 상품명, 상품설명서, 국제브랜드 안내장, 발급 중단 여부, 발급 중단일. 그리는 코드의 칸은 `code`, `codeName`, `goodsDescAt`, `issuAt`, `issuDt`. 단종일이 있다. 출시일은 없다. `part` 0 개인, 1 기업. 신용과 체크 구분 칸은 없다.
- 상품 페이지 `H1CRD101S02.do?cdPrdCd=<코드>`도 자바스크립트가 채운다. 그림 주소는 상세 API의 `fileCoursWeb`. 상품설명서는 RAONKUpload 다운로드 솔루션 팝업이라 직접 PDF 주소가 없다.

## 하나카드

- 막힘 없음. 응답은 모두 EUC-KR이다.
- **공시실에는 카드 목록이 없다.** 신용카드상품, 체크카드상품 모두 수수료율과 통계 표뿐이다. 카드 목록은 공시실 밖 "카드 한눈에 보기" `https://www.hanacard.co.kr/OPI22000000D.web?schID=pcd&mID=OPI22000000P`이고 `POST /OPI22000000D.ajax`가 채운다. 파라미터 `targetMethod=searchList`, `CARD_TYPE` R 신용 H 체크 빈 값 전체, `PAGE`. 응답 칸 `CD_ID`, `CD_NM`, `CD_NO`, 그림. curl로 같은 파라미터를 보내면 `FRS00015 일시적 전산장애` 오류다. `executeAction`이 붙이는 추가 칸이나 헤더가 빠진 것으로 추측한다. 지금 수집기는 이 카드사를 Playwright로 받으니 브라우저로는 열릴 것이다.
- 상세 `OPI41000000D.web?CD_PD_SEQ=<번호>`: 이름, 상품설명서 PDF 직접 주소 `https://m.hanacard.co.kr/leaflet/<앞 두 자리>/<코드>_<날짜>.pdf`, 그림 `https://www.hanacard.co.kr/ATTACH/NEW_HOMEPAGE/images/cardinfo/card_img/<코드>.png`. 상세 주소의 번호와 파일명의 코드가 다른 카드가 있다.
- 판매 상태, 단종일, 출시일이 어디에도 없다. 단종 카드 목록도 홈페이지에서 못 찾았다. HEAD는 Content-Length가 이상하게 와서 Range GET으로 확인했다. PDF 4.2MB.

## 신한카드

- 막힘 없음. 쿠키와 CSRF 필요 없다. 목록은 API를 직접 부르면 된다.
- 전체 목록: `GET https://shapi.shinhancard.com/card-apply/search/v1.0/searchPagingFixedCardProductList?listID=202001020012&pageSize=8&index=<쪽>`. 신용 `listID=202001020012` 63장, 체크 `202001020001` 97장. `index`를 `totalPage`까지 돌리면 전부다. 필터 없는 `searchPagingCardProductList`는 신용 74장이라 고정 목록보다 11장 많다.
- 칸: 이름, 상품 페이지 `cardProductUrl`, 그림 `thumbnailImgUrl`과 `mainImgUrl`, 출시일 `cardPdStartDate`, 수정일, 코드 `cardProductCode`, 상세 id, `cardType` 0 신용 1 체크, `applyEnableFlag`. 상품설명서 PDF와 단종일은 없다. 공시실 여섯 탭에 카드 목록이 없고 단종 카드 목록도 못 찾았다.

## 현대카드

- 막힘 없음. 이번에는 연결 끊김도 없었다. 자바스크립트 없이 전부 HTML에 들어 있다.
- 카드 목록 `GET /cpc/ma/CPCMA0101_01.hc`에 84장. 코드 `cardWcd`, 이름, 상품 페이지 `/cpc/cr/CPCCR0201_01.hc?cardWcd=<코드>`, 그림 `https://img.hyundaicard.com/img/com/card/card_<코드>_h.png`, 연회비. 체크카드 섹션은 없다.
- **신용카드 설명서 페이지 `GET /cpu/ug/CPUUG2001_08.hc`에 431건이 HTML에 다 있다.** 이름, 상품출시일, **발급중단일**, 번호 `sqno`. 발급중단일이 있는 것 206건, 없는 것 225건. 설명서 파일 목록은 `POST /cpu/ug/apiCPUUG2001_0404.hc`에 `sqno=<번호>`, 응답에 파일명과 개정일. PDF는 `https://www.hyundaicard.com/upload/card/<파일명>` 직접 주소. HEAD는 405라 GET으로 확인, `application/pdf` 188KB.
- 카드 목록과 설명서 목록은 공통 코드가 없어 이름으로 짝짓는다. 설명서 목록에는 개인사업자 상품과 같은 카드의 에디션이 섞여 있다.

## NH농협카드

- 막힘 없음. 쿠키와 CSRF 필요 없다.
- 전체 목록: `POST https://card.nonghyup.com/servlet/IpCc1210I.jct`. 끝이 `.act`가 아니라 `.jct`다. 본문 `CD_WRS_NM=&pageNum=<쪽>&cardGubun=&…`. `cardGubun` 빈 값 전체, `IPCC0105` 신용 80장, `IPCC0106` 체크. 한 쪽 20장, 전체 168장 9쪽.
- 칸: 이름 `cd_wrsnm`, 상세 번호 `cd_wrs_sqno`로 상품 페이지 `IpCc2021R.act?CD_WRS_SQNO=<번호>`, 코드 `wrs_tup_c`, 그림 `/content/imgs/shopmall/pro_img/card/<코드>.png`, 판매 상태 `sel_yn` 0이면 발급종료, 연회비, 혜택 요약. 출시일은 상세 HTML 본문의 "카드 신규출시 (…)" 글에서 뽑는다. 단종일과 상품설명서 PDF 주소는 없다.
- 상품공시실 메뉴의 "카드 현황" 페이지 주소는 `common_moveMenu`로 이동해 못 찾았다. 단종 카드 현황일 수 있다.

## 열 곳 정리

| 카드사 | 목록 받는 법 | 자바스크립트 | 지금 파는 수 | 판매 상태 | 단종일 | 설명서 PDF | 그림 |
|---|---|---|---|---|---|---|---|
| KB | 공시실 금융약관 표, POST 쪽 넘김 | 불필요 | 개인신용 489건 중 일부. 체크 탭 미확인 | 발급중단일 유무 | **있음** | 직접 주소 | 코드로 조합 |
| 현대 | 카드 목록 84 + 설명서 목록 431 | 불필요 | 84 | 설명서 목록의 발급중단일 | **있음** | 다운로드 API 뒤 직접 주소 | 코드로 조합 |
| 롯데 | 공시 목록 API 531 + 카드 목록 API | 불필요, HTTP/1.1 | 282 | `ISU_E_YN` | 없음 | 직접 주소 | 코드로 조합 |
| 삼성 | 추천 페이지 코드 사전 1,383 + 공시 게시판 564 | 불필요, `__NUXT__` 풀기 | 신용 134, 체크 미확인 | 추천 탭 포함 여부로 추측 | 없음 | 다운로드 주소 형식 미확인 | 코드로 조합 |
| IBK | 목록 GET + POST 쪽 넘김 | 불필요 | 121~130 | 판매중지 아이콘 | 없음 | 직접 주소 | 목록과 상세 |
| 신한 | shapi 목록 API | 불필요 | 신용 63, 체크 97 | `applyEnableFlag` | 없음 | 없음 | 목록 |
| 농협 | `.jct` 목록 API | 불필요 | 168 | `sel_yn` | 없음 | 없음 | 목록 |
| 카카오뱅크 | 공시 API | 불필요 | 5 | 이름 괄호 표기 | 없음 | 직접 주소, TXT도 | 상품 페이지 |
| 우리 | 공시실 약관 탭 | **필요**. 요청 암호화 | 미확인 | `issuAt` | **있음** | 다운로드 솔루션 | 상세 API |
| 하나 | 홈페이지 카드 한눈에 보기 API | 브라우저로 추정 | 미확인 | 없음 | 없음 | 상세에 직접 주소 | 상세 |

- 쿠키나 CSRF가 필요한 곳은 없었다. 기술적으로 막은 곳도 없었다. 롯데만 HTTP/1.1이 필요하다.
- 단종일이 있는 곳은 KB, 현대, 우리 셋뿐이다. 나머지는 처음 사라진 수집일로 추정한다.
- 상품설명서 PDF 주소가 목록이나 상세에 있는 곳은 KB, 현대, 롯데, IBK, 카카오뱅크, 하나다. 신한과 농협은 PDF를 못 찾았고 상품 페이지 HTML을 원문으로 쓴다. 삼성은 다운로드 주소 형식을, 우리는 다운로드 솔루션을 더 봐야 한다.
- 지금 파는 카드는 체크카드와 미확인을 빼고도 1,000장 안팎이다. 설계가 잡은 500~700장보다 많다.
