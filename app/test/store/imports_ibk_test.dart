// 실제 IBK 나라사랑 파일 모양. 2026-10-05 기업은행 홈페이지 "파일저장"의 "출력용" 파일로 확인한 머리 줄과 줄 모양을
// 지어낸 값으로 옮겼다. 사용자의 실제 결제는 저장소에 넣지 않는다. E30, E32, E59
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/imports.dart' show parseRows, signature;
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _head = [
  'No',
  '승인구분',
  '이용구분',
  '승인일시',
  '카드번호',
  '카드별명',
  '이용가맹점명',
  '승인금액',
  '현지외화금액',
  '제휴카드명',
  '할부개월',
  '승인금액(USD)',
  '적용환율',
  '이용수수료',
  '승인번호',
  '컵보증금',
  '할인금액',
  '취소금액',
  '취소일자',
  '매출표접수일자',
  '결제예정일자',
  '가맹점사업자번호',
];

/// 결제 한 줄. kind는 승인구분이다. 결제는 "원화", 취소와 카드 할인은 "취소또는할인"이다
List<String> line(
  String kind,
  String at,
  String merchant,
  String amount,
  String approval, {
  String? cancelled,
}) => [
  '1',
  kind,
  '국내체크일시불',
  at,
  '0000-****-****-0000',
  '',
  merchant,
  amount,
  '',
  'IBK나라사랑카드(일반)',
  '일시불',
  '0.00',
  '',
  '',
  approval,
  '0',
  '0',
  cancelled ?? (kind == '원화' ? '0' : amount),
  '',
  '',
  '',
  '',
];

String _tr(List<String> cells) =>
    '<tr>${[for (final c in cells) '<td>$c</td>'].join()}</tr>';

/// 확장자는 xls지만 속은 html 표인 출력용 파일. 머리 줄 위에 제목과 합계 줄이 있다
Uint8List ibk(List<List<String>> lines, {List<String> head = _head}) =>
    Uint8List.fromList(
      utf8.encode(
        '<html><head><meta charset="utf-8"></head><body><table>'
        '${_tr(['기간별 사용내역 조회'])}${_tr(['[ 일시불 합계 ] : 원화 : 0'])}${_tr(head)}'
        '${lines.map(_tr).join()}</table></body></html>',
      ),
    );

/// 승인구분 열 이름만 거래구분으로 바꾼 파일. 기업은행 출력용 형식으로 맞지 않아 열 이름 사전과 기억한 짝으로 읽는다.
/// 모르는 형식의 기억한 짝 채우기를 본다. E30
final _plain = [for (final h in _head) h == '승인구분' ? '거래구분' : h];

({Store s, String card}) ibkCard() {
  final (:s, clock: _) = fresh();
  final card =
      addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000)['id']
          as String;
  return (s: s, card: card);
}

List<Json> rowsOf(Json p) => (p['rows'] as List).cast<Json>();

void main() {
  test('IBK 머리 줄을 알아보고 승인일시 칸의 시각을 쓴다', () {
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([line('원화', '2026-09-10 12:30:00', '편의점 예시', '4,300', '10000001')]),
      userCardId: card,
    );
    expect(p['needs_mapping'], isFalse);
    expect(p['mapping'], containsPair('merchant', 6));
    final [r] = rowsOf(p);
    expect(r['paid_at'], '2026-09-10T12:30:00+09:00');
    expect(r['timed'], isTrue);
    expect(r['status'], 'new');
  });

  test('결제일과 시각을 같은 승인일시 열로 짝지어도 읽는다', () {
    // 2026-10-05 사용자가 실제 IBK 파일로 둘 다 승인일시를 골라 막혔다. E30. 기업은행 출력용은 짝을 보내도 형식 표로
    // 읽어 모르는 형식 파일로 본다. 작업 015 설계 2절
    final (:s, :card) = ibkCard();
    final file = ibk([
      line('원화', '2026-09-10 12:30:00', '편의점 예시', '4,300', '10000001'),
    ], head: _plain);
    final p = imports.preview(
      s,
      file,
      userCardId: card,
      mapping: {
        'row': 2,
        'columns': {'date': 3, 'time': 3, 'merchant': 6, 'amount': 7},
      },
    );
    expect(rowsOf(p).single['paid_at'], '2026-09-10T12:30:00+09:00');
    // 다른 칸끼리 한 열을 함께 고르면 여전히 막는다
    expect(
      () => imports.preview(
        s,
        file,
        userCardId: card,
        mapping: {
          'row': 2,
          'columns': {'date': 3, 'merchant': 6, 'amount': 6},
        },
      ),
      throwsA(isA<ApiError>()),
    );
  });

  test('카드가 준 할인 줄은 결제도 취소도 아니라 넣지 않는다', () {
    // E59. "카카오T 자동결제 할인"은 가맹점 이름이 "카카오T"인 결제와 겹쳐 그 결제를 1,000원 취소한 것으로 볼 수 있었다
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-05 10:00:00', '카카오T', '5,000', '10000002'),
        line(
          '취소또는할인',
          '2026-09-06 02:30:00',
          '카카오T 자동결제 할인',
          '1,000',
          'F8000001',
        ),
        line('취소또는할인', '2026-09-06 02:30:00', '통신요금할인', '900', 'F8000002'),
      ]),
      userCardId: card,
    );
    final [pay, kakao, phone] = rowsOf(p);
    expect(pay['status'], 'new');
    for (final r in [kakao, phone]) {
      expect(r['status'], 'discount');
      expect(r['reason'], '카드가 준 할인이라 넣지 않아요');
      // 저장할 때 화면이 보내지 않는 모양이다
      expect(r.containsKey('paid_at'), isFalse);
    }
    expect(p['summary']['discounts'], 2);
    expect(p['summary']['cancels'], 0);
    final saved = imports.save(s, {
      'rows': [
        for (final r in rowsOf(p))
          if (r.containsKey('paid_at')) r,
      ],
    });
    expect(saved['imported'], 1);
    final row = s.db
        .select('select amount, cancelled_amount from transactions')
        .single;
    expect((row['amount'], row['cancelled_amount']), (5000, 0));
  });

  test('승인 줄 없이 취소 줄만 있는 결제는 넣지 않는다', () {
    // IBK는 취소된 결제를 원래 승인 줄 없이 취소 줄로만 적는다. 원 결제를 찾지 못해 넣지 않는 것이 맞다. E32
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([
        line('취소또는할인', '2026-09-08 19:10:00', '한식당 예시', '40,000', '10000003'),
        line('원화', '2026-09-08 19:12:00', '한식당 예시', '38,000', '10000004'),
      ]),
      userCardId: card,
    );
    final statuses = [for (final r in rowsOf(p)) r['status']];
    expect(statuses, ['orphan', 'new']);
  });

  test('진짜 옛 엑셀 형식이면 출력용으로 받으라고 알린다', () {
    // 기업은행 "거래용" 파일은 진짜 옛 xls다
    final (:s, :card) = ibkCard();
    expect(
      () => imports.preview(
        s,
        Uint8List.fromList([0xd0, 0xcf, 0x11, 0xe0, ...List.filled(64, 0x30)]),
        userCardId: card,
      ),
      throwsA(isA<ApiError>().having((e) => e.body, 'body', contains('출력용'))),
    );
  });

  test('이름이 할인으로 끝나도 승인번호가 같은 결제가 있으면 그 결제의 취소다', () {
    // 단계 검토 중간 2. 가게 이름이 "OO할인"이면 진짜 취소를 할인으로 빼 실적이 부풀려질 수 있었다
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-05 10:00:00', '동네할인', '30,000', '10000005'),
        line('취소또는할인', '2026-09-06 10:00:00', '동네할인', '30,000', '10000005'),
      ]),
      userCardId: card,
    );
    expect([for (final r in rowsOf(p)) r['status']], ['new', 'cancel']);
  });

  test('승인번호가 다른 취소는 이름이 같은 결제에 붙이지 않는다', () {
    // 단계 검토 중간 3. 실제 IBK 파일에서 승인 줄 없는 다른 표의 취소가 같은 가게의 다른 결제를 부분 취소한 것으로 붙었다
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-07 20:00:00', '기차표 예시', '15,000', '10000006'),
        line('취소또는할인', '2026-09-07 20:05:00', '기차표 예시', '9,000', '10000007'),
      ]),
      userCardId: card,
    );
    expect([for (final r in rowsOf(p)) r['status']], ['new', 'orphan']);
  });

  test('부분 취소는 취소금액 열의 금액만 뺀다', () {
    // 단계 검토 중간 4. 승인금액은 원래 금액이고 취소금액이 실제로 취소된 금액이다
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-07 12:00:00', '마트 예시', '50,000', '10000008'),
        line(
          '취소또는할인',
          '2026-09-08 12:00:00',
          '마트 예시',
          '50,000',
          '10000008',
          cancelled: '20,000',
        ),
      ]),
      userCardId: card,
    );
    final [_, cancel] = rowsOf(p);
    expect((cancel['status'], cancel['amount']), ('cancel', 20000));
  });

  test('시각을 결제일과 같은 열로 골라도 날짜만 든 칸이면 시각을 모른다', () {
    // 단계 검토 낮음 7. xlsx의 날짜만 든 날짜 칸을 시각으로 다시 읽으면 0시로 읽혀 시각을 안다고 적었다
    final table = [
      ['이용일자', '가맹점명', '이용금액'],
      [DateTime.utc(2026, 9, 10), '편의점 예시', 4300],
    ];
    final [row] = parseRows(table, 0, {
      'date': 0,
      'time': 0,
      'merchant': 1,
      'amount': 2,
    });
    expect(
      (row.day, row.at, row.error),
      (DateTime.utc(2026, 9, 10), null, null),
    );
  });

  test('결제 줄에 취소금액이 찍혔으면 일부 취소된 결제라 넣지 않고 보인다', () {
    // 재검토 중간 1. 그대로 넣으면 취소된 만큼 실적이 부풀려진다
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([
        line(
          '원화',
          '2026-09-07 12:00:00',
          '마트 예시',
          '50,000',
          '10000009',
          cancelled: '20,000',
        ),
      ]),
      userCardId: card,
    );
    final [r] = rowsOf(p);
    expect(
      (r['status'], r['reason']),
      ('error', '일부 취소된 결제예요. 기록에서 직접 적어 주세요'),
    );
  });

  test('할인 줄과 승인번호가 같은 결제가 다른 카드에 있으면 할인으로 본다', () {
    // 재검토 낮음 2. 승인번호 대조는 고른 카드 안에서 한다
    final (:s, :card) = ibkCard();
    final other =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    imports.save(s, {
      'rows': [
        for (final r in rowsOf(
          imports.preview(
            s,
            ibk([
              line('원화', '2026-09-05 10:00:00', '가게 예시', '3,000', 'F8000003'),
            ]),
            userCardId: other,
          ),
        ))
          if (r.containsKey('paid_at')) r,
      ],
    });
    final p = imports.preview(
      s,
      ibk([line('취소또는할인', '2026-09-06 02:30:00', '쇼핑할인', '1,000', 'F8000003')]),
      userCardId: card,
    );
    expect(rowsOf(p).single['status'], 'discount');
  });

  test('기억한 짝에 없는 칸은 자동으로 찾은 열로 채운다', () {
    // E30. 첫 가져오기 때 결제일, 가맹점, 금액만 손으로 짝지으면 다음에 취소 여부 없이 읽혀 취소와 카드 할인 줄이 모두
    // 결제로 들어갔다. 2026-10-05 실제 IBK 파일로 찾았다
    final (:s, :card) = ibkCard();
    s.db.execute(
      'insert into import_mappings (signature, mapping, updated_at) values (?, ?, 0)',
      [
        signature([for (final h in _plain) h]),
        jsonEncode({'date': 3, 'merchant': 6, 'amount': 7}),
      ],
    );
    final p = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000010'),
        line('취소또는할인', '2026-09-06 02:30:00', '쇼핑할인', '1,000', 'F8000004'),
      ], head: _plain),
      userCardId: card,
    );
    expect(p['mapping'], containsPair('cancel', 1));
    // 모르는 형식이라 할인 줄 규칙을 걸지 않는다. 원 결제가 없는 취소다. 작업 015 설계 4절 1
    expect([for (final r in rowsOf(p)) r['status']], ['new', 'orphan']);
  });

  test('기억한 짝의 칸과 열은 자동으로 찾은 것보다 이긴다', () {
    final (:s, :card) = ibkCard();
    // 금액을 승인금액이 아닌 열로 골라 두었다. 자동은 그 칸을 바꾸지 않고, 고른 열을 다른 칸에 쓰지 않는다
    s.db.execute(
      'insert into import_mappings (signature, mapping, updated_at) values (?, ?, 0)',
      [
        signature([for (final h in _plain) h]),
        jsonEncode({'date': 3, 'merchant': 6, 'amount': 17}),
      ],
    );
    final p = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000011'),
      ], head: _plain),
      userCardId: card,
    );
    final m = p['mapping'] as Map;
    expect(m['amount'], 17);
    expect(m.containsKey('cancel_amount'), isFalse);
    expect(m['cancel'], 1);
  });

  test('"없음"으로 비운 칸은 기억한 짝을 채울 때 되살리지 않는다', () {
    // E30. 사용자가 직접 정한 것이 자동으로 찾은 것보다 우선이다. 다시 검토 중간 1
    final (:s, :card) = ibkCard();
    s.db.execute(
      'insert into import_mappings (signature, mapping, updated_at) values (?, ?, 0)',
      [
        signature([for (final h in _plain) h]),
        jsonEncode({'date': 3, 'merchant': 6, 'amount': 7, 'cancel': -1}),
      ],
    );
    final p = imports.preview(
      s,
      ibk([
        line(
          '취소또는할인',
          '2026-09-06 02:30:00',
          '쇼핑할인',
          '1,000',
          'F8000005',
          cancelled: '0',
        ),
      ], head: _plain),
      userCardId: card,
    );
    // 비운 칸은 -1로 돌려준다. 화면이 다시 짝짓고 저장할 때 그대로 남긴다
    final m = p['mapping'] as Map;
    expect(m['cancel'], -1);
    expect(m['approval'], 14);
    expect(rowsOf(p).single['status'], 'new');
    // 화면이 직접 보낸 짝의 비운 칸도 -1로 돌려준다
    final direct = imports.preview(
      s,
      ibk([
        line('원화', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000013'),
      ], head: _plain),
      userCardId: card,
      mapping: {
        'row': 2,
        'columns': {'date': 3, 'merchant': 6, 'amount': 7, 'cancel': -1},
      },
    );
    expect(direct['mapping'] as Map, containsPair('cancel', -1));
    // 꼭 고를 칸은 비울 수 없다
    expect(
      () => imports.preview(
        s,
        ibk([
          line('원화', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000012'),
        ], head: _plain),
        userCardId: card,
        mapping: {
          'row': 2,
          'columns': {'date': 3, 'merchant': 6, 'amount': -1},
        },
      ),
      throwsA(isA<ApiError>()),
    );
  });

  test('기업은행 출력용은 기억한 짝이 무엇이든 형식 표로 읽는다', () {
    // 작업 015 성공 기준 1. 2026-10-05 같은 실제 파일이 기억한 짝에 따라 세 가지 결과로 나왔다
    final lines = [
      line('원화', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000020'),
      line('취소또는할인', '2026-09-06 02:30:00', '쇼핑할인', '1,000', 'F8000020'),
      line('취소또는할인', '2026-09-07 11:00:00', '다른 가게', '3,000', '10000021'),
    ];
    List<Object?> statuses(Map<String, int>? saved) {
      final (:s, :card) = ibkCard();
      if (saved != null) {
        s.db.execute(
          'insert into import_mappings (signature, mapping, updated_at) values (?, ?, 0)',
          [
            signature([for (final h in _head) h]),
            jsonEncode(saved),
          ],
        );
      }
      final p = imports.preview(s, ibk(lines), userCardId: card);
      expect(p['format'], 'ibk-print');
      expect(p['format_name'], '기업은행 출력용');
      return [for (final r in rowsOf(p)) r['status']];
    }

    for (final saved in [
      null,
      {'date': 3, 'merchant': 6, 'amount': 7},
      {'date': 3, 'merchant': 6, 'amount': 7, 'cancel': -1},
    ]) {
      expect(statuses(saved), ['new', 'discount', 'orphan'], reason: '$saved');
    }
  });

  test('모르는 형식의 할인으로 끝나는 취소 줄은 보통 취소로 원 결제를 찾는다', () {
    // 작업 015 성공 기준 6. E59 할인 줄 규칙은 기업은행 출력용에만 건다
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      Uint8List.fromList(
        utf8.encode(
          '이용일자,가맹점명,이용금액,취소여부\n'
          '2026.09.05 10:00,마트할인,5000,\n'
          '2026.09.06 10:00,마트할인,5000,취소\n',
        ),
      ),
      userCardId: card,
    );
    expect(p['format'], isNull);
    expect([for (final r in rowsOf(p)) r['status']], ['new', 'cancel']);
  });

  test('기업은행 출력용에서 본 적 없는 값이 든 줄은 넣지 않고 보인다', () {
    // 작업 015 설계 1절. 해외 결제와 할부는 아직 실제 파일로 보지 못했다
    final (:s, :card) = ibkCard();
    final overseas = line(
      '원화',
      '2026-09-05 10:00:00',
      '가게 예시',
      '5,000',
      '10000030',
    )..[2] = '해외체크일시불';
    final [r] = rowsOf(imports.preview(s, ibk([overseas]), userCardId: card));
    expect((r['status'], r['reason']), ('error', '처음 보는 값이에요. 기록에서 직접 적어 주세요'));
  });

  test('기업은행 출력용 승인구분에 처음 보는 값이 든 줄은 결제로 넣지 않는다', () {
    // 작업 015 단계 검토 낮음 7. 취소를 결제로 넣는 길을 막는다
    final (:s, :card) = ibkCard();
    final [r] = rowsOf(
      imports.preview(
        s,
        ibk([line('취소', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000031')]),
        userCardId: card,
      ),
    );
    expect(r['status'], 'error');
  });

  test('기업은행 출력용은 화면이 보낸 짝도 쓰지 않고 형식 표로 읽는다', () {
    // 작업 015 단계 검토 낮음 6
    final (:s, :card) = ibkCard();
    final p = imports.preview(
      s,
      ibk([line('취소또는할인', '2026-09-06 02:30:00', '쇼핑할인', '1,000', 'F8000040')]),
      userCardId: card,
      mapping: {
        'row': 2,
        'columns': {'date': 3, 'merchant': 6, 'amount': 7},
      },
    );
    expect(p['format'], 'ibk-print');
    expect(rowsOf(p).single['status'], 'discount');
  });
}
