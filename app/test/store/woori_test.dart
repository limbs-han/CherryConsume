// 우리카드 거래승인내역. 2026-10-06 실제 메일 파일과 같은 모양이고 값은 모두 지어냈다. 작업 017 설계 2절
import 'dart:typed_data';

import 'package:cherry_consume/catalog/models.dart' show Json;
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'import_formats_test.dart' show rowsOf;
import 'xls_build.dart';

const head = [
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
  '',
  '사업자번호',
];

/// 결제 한 줄. 승인금액만 숫자 칸이다
List<Object> woori(
  int no,
  String at,
  String merchant,
  int amount, {
  String card = 'A111',
  String member = '본인',
  String how = '일시불',
  String cancelled = '-',
  String months = '',
}) => [
  '$no',
  member,
  card,
  how,
  '9000000$no',
  at,
  amount,
  months,
  '10/01',
  cancelled,
  merchant,
  '',
  '000-00-00000',
];

/// 제목, 카드와 조회 기간 줄, 머리 줄, 결제 줄, 합계 줄 셋
Uint8List file(List<List<Object>> lines, {String title = '국내 거래승인내역(정상)'}) {
  final rows = <List<Object>>[
    [],
    [title],
    [],
    ['카드번호 :', '', '', '0000000******'],
    ['성  명 :', '', '', '가*나'],
    ['조회기간 :', '', '', '2026/09/01~2026/09/30'],
    [],
    ['* 안내 문구'],
    [],
    head,
    ...lines,
    ['국내 승인건수', '', '', '', lines.length, '', '', '국내 승인금액', '', '', '', 1, ''],
    ['국외 승인건수', '', '', '', 0, '', '', '국외 승인금액', '', '', '', 0, ''],
    ['취소건수', '', '', '', 0, '', '', '취소금액', '', '', '', 0, ''],
  ];
  return cfb(
    biff(
      cells: [
        for (final (r, line) in rows.indexed)
          for (final (c, v) in line.indexed)
            if (v is int)
              number(r, c, v.toDouble())
            else if (v != '')
              label(r, c, v as String),
      ],
    ),
  );
}

void main() {
  test('우리카드 거래승인내역을 형식 표로 읽고 카드 칸 값마다 고른다', () {
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final ibk = addCard(s, 'ibk-narasarang')['id'] as String;
    final data = file([
      woori(1, '2026/09/05 10:00:00', '가게 하나', 5000),
      woori(2, '2026/09/06 11:30:00', '가게 둘', 12000, how: '체크계좌'),
      woori(3, '2026/09/07 09:00:00', '가게 셋', 3000, card: 'B222'),
    ]);
    final p = imports.preview(
      s,
      data,
      userCardId: ibk,
      codes: {'A111': ibk, 'B222': mr},
    );
    expect(p['format'], 'woori-approvals');
    expect(p['source'], 'xls');
    final rows = rowsOf(p);
    expect(
      [
        for (final r in rows)
          (r['status'], r['merchant_name'], r['amount'], r['user_card_id']),
      ],
      [
        ('new', '가게 하나', 5000, ibk),
        ('new', '가게 둘', 12000, ibk),
        ('new', '가게 셋', 3000, mr),
      ],
    );
    expect(rows.first['paid_at'], '2026-09-05T10:00:00+09:00');
    expect((p['summary'] as Json)['new'], 3);
  });

  test('본 적 없는 회원, 요청방식, 취소일이 든 줄은 넣지 않는다', () {
    final (:s, clock: _) = fresh();
    final ibk = addCard(s, 'ibk-narasarang')['id'] as String;
    final p = imports.preview(
      s,
      file([
        woori(1, '2026/09/05 10:00:00', '가게 하나', 5000),
        woori(2, '2026/09/06 10:00:00', '가족 가게', 5000, member: '가족'),
        woori(3, '2026/09/07 10:00:00', '할부 가게', 5000, how: '할부'),
        woori(4, '2026/09/08 10:00:00', '취소 가게', 5000, cancelled: '2026/09/09'),
      ]),
      userCardId: ibk,
    );
    expect(
      [for (final r in rowsOf(p)) (r['merchant_name'], r['status'])],
      [
        ('가게 하나', 'new'),
        ('가족 가게', 'error'),
        ('할부 가게', 'error'),
        ('취소 가게', 'error'),
      ],
    );
  });

  test('취소일에 날짜가 든 줄은 취소된 결제라고 알리고 할부 칸에 값이 든 줄은 넣지 않는다', () {
    final (:s, clock: _) = fresh();
    final ibk = addCard(s, 'ibk-narasarang')['id'] as String;
    final p = imports.preview(
      s,
      file([
        woori(1, '2026/09/08 10:00:00', '취소 가게', 5000, cancelled: '2026/09/09'),
        woori(2, '2026/09/10 10:00:00', '할부 칸 가게', 30000, months: '3'),
      ]),
      userCardId: ibk,
    );
    expect(
      [for (final r in rowsOf(p)) (r['status'], r['reason'])],
      [
        ('error', '취소된 결제예요. 이미 넣었다면 기록에서 취소를 적어 주세요'),
        ('error', '처음 보는 값이에요. 카드 결제라면 기록에서 직접 적어 주세요'),
      ],
    );
  });

  test('머리 줄이 같아도 국내 정상 승인 파일이 아니면 넣지 않는다', () {
    // 작업 017 단계 3 검토 중간 1, 3. 국외 결제가 국내 결제로 들어가지 않게 한다
    final (:s, clock: _) = fresh();
    final ibk = addCard(s, 'ibk-narasarang')['id'] as String;
    final p = imports.preview(
      s,
      file([
        woori(1, '2026/09/05 10:00:00', '해외 가게', 5000),
      ], title: '해외 거래승인내역(정상)'),
      userCardId: ibk,
    );
    expect(p['format'], 'woori-approvals');
    expect(
      [for (final r in rowsOf(p)) (r['status'], r['reason'])],
      [('error', '우리카드 거래승인내역 가운데 국내 정상 승인 파일만 읽어요')],
    );
  });
}
