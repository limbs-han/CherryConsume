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
