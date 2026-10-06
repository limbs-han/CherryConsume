/// 카드사 파일 형식 표. 아는 형식이면 기억한 짝과 열 이름 사전을 쓰지 않고 이 표로 읽는다. 실제 파일에서 본 것만
/// 적는다. 작업 015 설계 1절과 3절
library;

import 'imports.dart' show pyStr;

/// 형식 표에서 열 이름을 견주는 모양. 띄어쓰기만 뺀다. 괄호 안은 남겨 "승인금액(USD)"를 "승인금액"으로 보지 않는다
String headKey(Object? c) => pyStr(c).replaceAll(RegExp(r'\s'), '');

class Format {
  const Format({
    required this.id,
    required this.name,
    required this.marks,
    required this.columns,
    this.cancelValues = const {},
    this.reversed = false,
    this.cardRows = false,
    this.discountRows = false,
    this.seen = const {},
    this.cardCodes,
    this.title,
  });

  final String id, name;

  /// 머리 줄에 모두 있어야 이 형식으로 아는 열 이름. 띄어쓰기를 뺀 이름이다. 읽는 열과 본 값을 적은 열을 모두
  /// 담는다
  final List<String> marks;

  /// 칸마다 읽을 열 이름
  final Map<String, String> columns;

  /// 취소 여부 열에서 취소인 값
  final Set<String> cancelValues;

  /// 음수가 결제이고 양수가 취소다
  final bool reversed;

  /// 줄마다 카드 이름 열로 보유 카드를 찾는다. 이름이 고른 카드나 보유 카드와 맞지 않는 줄은 넣지 않는다
  final bool cardRows;

  /// 취소 줄인데 가맹점명이 할인으로 끝나면 카드가 준 할인이다. E59
  final bool discountRows;

  /// 열마다 실제 파일에서 본 값. 본 적 없는 값이 든 줄은 넣지 않고 보인다
  final Map<String, Set<String>> seen;

  /// 줄마다 어느 카드인지 적힌 열. 값은 카드번호 일부라 카드 이름으로 맞출 수 없어 사용자가 값마다 보유 카드를
  /// 고른다. 고르지 않은 값의 줄은 넣지 않는다. 고른 카드 한 장으로 모두 넣으면 실적이 부푼다. 작업 017 설계 3절
  final String? cardCodes;

  /// 머리 줄 위에 있어야 하는 제목. 띄어쓰기를 뺀 글자다. 머리 줄이 같은 다른 판의 파일이면 줄을 넣지 않는다. 형식으로
  /// 알아보지 않으면 열 이름 사전으로 읽혀 국외 결제까지 들어가 형식은 그대로 알아본다. 작업 017 단계 3 검토 중간 1, 3
  final String? title;
}

const formats = [
  // 기업은행 홈페이지 "파일저장"의 "출력용". 2026-10-05 실제 IBK 나라사랑 체크카드 파일
  Format(
    id: 'ibk-print',
    name: '기업은행 출력용',
    marks: [
      '승인구분',
      '이용구분',
      '승인일시',
      '카드번호',
      '이용가맹점명',
      '승인금액',
      '현지외화금액',
      '할부개월',
      '승인번호',
      '컵보증금',
      '할인금액',
      '취소금액',
    ],
    columns: {
      'date': '승인일시',
      'time': '승인일시',
      'merchant': '이용가맹점명',
      'amount': '승인금액',
      'installment': '할부개월',
      'cancel': '승인구분',
      'approval': '승인번호',
      'cancel_amount': '취소금액',
    },
    cancelValues: {'취소또는할인'},
    discountRows: true,
    seen: {
      '승인구분': {'원화', '취소또는할인'},
      '이용구분': {'국내체크일시불'},
      '할부개월': {'일시불'},
      '현지외화금액': {''},
      '컵보증금': {'0'},
      '할인금액': {'0'},
    },
    cardCodes: '카드번호',
  ),
  // 신한카드 홈페이지 이용내역 엑셀. 확장자는 xls이고 속은 xlsx다. 2026-10-05 실제 체크카드 파일 25건. 취소가 없어
  // 취소상태에 무엇이 적히는지 모른다. 이용카드 열에는 카드번호 일부가 들어 읽지 않는다
  Format(
    id: 'shinhan-usage',
    name: '신한카드 이용내역',
    marks: [
      '거래일',
      '카드구분',
      '이용카드',
      '가맹점명',
      '승인번호',
      '금액',
      '매입구분',
      '이용구분',
      '거래통화',
      '해외이용금액',
      '취소상태',
    ],
    columns: {
      'date': '거래일',
      'time': '거래일',
      'merchant': '가맹점명',
      'amount': '금액',
      'installment': '이용구분',
      'cancel': '취소상태',
      'approval': '승인번호',
    },
    seen: {
      '매입구분': {'승인', '결제확정'},
      '이용구분': {'일시불'},
      '거래통화': {''},
      '해외이용금액': {''},
      '취소상태': {''},
    },
    cardCodes: '이용카드',
  ),
  // 우리카드가 메일로 보내는 "국내 거래승인내역(정상)". 옛 엑셀 형식이다. 2026-10-06 실제 파일 102건. 카드 두 장의 줄이
  // 섞여 카드 칸 값마다 고른다. 이름이 "정상"이라 취소 줄이 없어 취소일에 날짜가 든 줄은 넣지 않고 보인다. 이미 넣은
  // 결제가 뒤에 취소되면 이 파일로는 알 수 없다. 요청방식 "일시불"이 신용 결제인지 후불교통 같은 것인지는 확인 필요다.
  // 맨 아래 승인 건수와 금액 합계 줄은 결제일과 가맹점이 비어 건너뛴다. 작업 017 설계 2절
  Format(
    id: 'woori-approvals',
    name: '우리카드 거래승인내역',
    marks: [
      'No',
      '회원',
      '카드',
      '요청방식',
      '승인번호',
      '승인일자',
      '승인금액',
      '할부',
      '접수일',
      '취소일',
      '가맹점',
      '사업자번호',
    ],
    columns: {
      'date': '승인일자',
      'time': '승인일자',
      'merchant': '가맹점',
      'amount': '승인금액',
      'installment': '할부',
      'approval': '승인번호',
      'cancel': '취소일',
    },
    seen: {
      '회원': {'본인'},
      '요청방식': {'일시불', '체크계좌'},
      '할부': {''},
      '취소일': {'-'},
    },
    cardCodes: '카드',
    title: '국내거래승인내역(정상)',
  ),
  // 뱅크샐러드 가계부 설정의 "파일로 받기". 2026-10-05 실제 1년치 파일. 카드 다섯 장이 한 파일에 있고 모두 체크카드다.
  // 결제는 음수, 취소는 양수다. 할부 열이 없어 일시불로 넣는다
  Format(
    id: 'banksalad',
    name: '뱅크샐러드 가계부 내보내기',
    // 읽지 않는 대분류, 소분류, 메모는 넣지 않는다. 그 열 이름만 바뀌어도 모르는 형식으로 읽히지 않게 한다
    marks: ['날짜', '시간', '타입', '내용', '금액', '화폐', '결제수단'],
    columns: {
      'date': '날짜',
      'time': '시간',
      'merchant': '내용',
      'amount': '금액',
      'card': '결제수단',
    },
    reversed: true,
    cardRows: true,
    seen: {
      '타입': {'지출'},
      '화폐': {'KRW'},
    },
  ),
];

/// 아는 형식과 머리 줄과 열 짝 {칸: 열 번호}. 위 20줄에서 찾고, 두 형식이 맞으면 알아보는 열이 많은 형식이다.
/// 모르면 null이다. 작업 015 설계 1절
(Format, int, Map<String, int>)? detect(List<List<Object?>> table) {
  (Format, int, Map<String, int>)? best;
  for (final (i, row) in table.take(20).indexed) {
    final ns = [for (final c in row) headKey(c)];
    for (final f in formats) {
      if (!f.marks.every(ns.contains)) continue;
      if (best != null && best.$1.marks.length >= f.marks.length) continue;
      best = (
        f,
        i,
        {
          for (final MapEntry(:key, :value) in f.columns.entries)
            key: ns.indexOf(value),
        },
      );
    }
  }
  return best;
}
