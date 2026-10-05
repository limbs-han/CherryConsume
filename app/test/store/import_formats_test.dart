// 카드사 파일 형식 표. 작업 015 설계 1절
import 'dart:typed_data';

import 'package:cherry_consume/catalog/models.dart' show Json;
import 'package:cherry_consume/store/formats.dart';
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'import_parse_test.dart' show inline, xlsx;
import 'imports_ibk_test.dart' show ibk, line;

/// 줄마다 칸을 적은 xlsx. 숫자는 숫자 칸, 글자는 글자 칸이고 빈 글자는 칸을 두지 않는다
Uint8List sheet(List<List<Object>> rows) => xlsx(
  [
    for (final (i, r) in rows.indexed)
      '<row r="${i + 1}">${[for (final (j, v) in r.indexed)
        if (v is num) '<c r="${String.fromCharCode(65 + j)}${i + 1}"><v>$v</v></c>' else if (v != '') inline(i + 1, String.fromCharCode(65 + j), '$v')].join()}</row>',
  ].join(),
);

({Store s, String card}) withCard() {
  final (:s, clock: _) = fresh();
  final card =
      addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000)['id']
          as String;
  return (s: s, card: card);
}

List<Json> rowsOf(Json p) => (p['rows'] as List).cast<Json>();

/// 신한카드 이용내역 한 줄. 2026-10-05 실제 파일의 열 순서다. 값은 지어냈다
List<Object> shinhan(
  String at,
  String merchant,
  num amount,
  String approval, {
  String bought = '결제확정',
  String cancelled = '',
  String holder = '본인000*',
}) => [
  at,
  '체크',
  holder,
  merchant,
  '',
  approval,
  amount,
  bought,
  '일시불',
  '',
  '',
  '',
  cancelled,
];

const banksaladHead = <Object>[
  '날짜',
  '시간',
  '타입',
  '대분류',
  '소분류',
  '내용',
  '금액',
  '화폐',
  '결제수단',
  '메모',
];

/// 뱅크샐러드 가계부 내보내기 한 줄. 2026-10-05 실제 파일의 열 순서다. 값은 지어냈다. 결제는 음수다
List<Object> banksalad(
  String day,
  String time,
  String merchant,
  int amount, {
  String card = 'IBK나라사랑카드(일반)',
  String kind = '지출',
  String currency = 'KRW',
}) => [day, time, kind, '식비', '한식', merchant, amount, currency, card, ''];

/// 미리보기의 저장할 줄을 모두 저장한다. 앱과 같다
void saveAll(Store s, Json p) => imports.save(s, {
  'rows': [
    for (final r in rowsOf(p))
      if (r.containsKey('paid_at')) r,
  ],
});

const shinhanHead = <Object>[
  '거래일',
  '카드구분',
  '이용카드',
  '가맹점명',
  '업종',
  '승인번호',
  '금액',
  '매입구분',
  '이용구분',
  '거래통화',
  '최초결제일자',
  '해외이용금액',
  '취소상태',
];

void main() {
  test('형식이 읽는 열과 본 값을 적은 열은 모두 알아보는 열에 든다', () {
    // 형식이 맞으면 읽을 열이 모두 이름 그대로 있다. 열 이름이 바뀐 파일은 모르는 형식으로 읽힌다. 설계 2절 2
    for (final f in formats) {
      expect(
        f.marks,
        containsAll({...f.columns.values, ...f.seen.keys}),
        reason: f.id,
      );
      expect([for (final m in f.marks) headKey(m)], f.marks, reason: f.id);
    }
    expect({for (final f in formats) f.id}.length, formats.length);
  });

  test('괄호가 붙은 비슷한 열 이름을 읽을 열로 잘못 보지 않는다', () {
    // 작업 015 단계 검토 낮음 3. 승인금액(USD)가 승인금액보다 앞에 있어도 승인금액을 읽는다
    final f = formats.firstWhere((f) => f.id == 'ibk-print');
    final head = ['승인금액(USD)', for (final m in f.marks) m];
    final (_, start, cols) = detect([head])!;
    expect((start, cols['amount']), (0, head.indexOf('승인금액')));
    // 승인금액 없이 승인금액(USD)만 있으면 기업은행 출력용이 아니다
    expect(
      detect([
        [for (final m in f.marks) m == '승인금액' ? '승인금액(USD)' : m],
      ]),
      isNull,
    );
  });

  test('신한카드 이용내역은 거래일 칸의 시각과 금액을 읽는다', () {
    // 작업 015 단계 3. 금액은 숫자 칸이다
    final (:s, :card) = withCard();
    final p = imports.preview(
      s,
      sheet([
        shinhanHead,
        shinhan('2026.09.05 10:00', '가게 예시', 5000.0, '10000050'),
        shinhan('2026.09.06 12:30', '다른 가게', 13400.0, '10000051', bought: '승인'),
        // 맨 아래 합계 줄. 날짜 없이 건수와 합계만 있다. 쉼표가 든 건수도 합계 줄이다
        ['', '', '', '총 2건', '', '', 18400.0, '', '', '', '', '', ''],
        ['', '', '', '총 1,025건', '', '', 18400.0, '', '', '', '', '', ''],
      ]),
      userCardId: card,
    );
    expect((p['format'], p['format_name']), ('shinhan-usage', '신한카드 이용내역'));
    expect(
      [for (final r in rowsOf(p)) (r['status'], r['paid_at'], r['amount'])],
      [
        ('new', '2026-09-05T10:00:00+09:00', 5000),
        ('new', '2026-09-06T12:30:00+09:00', 13400),
      ],
    );
  });

  test('신한카드 이용내역에서 취소상태나 매입구분에 처음 보는 값이 든 줄은 넣지 않는다', () {
    // 작업 015 설계 1절. 받은 파일에 취소가 없어 취소상태에 무엇이 적히는지 모른다. 취소 줄을 결제로 넣지 않는다
    final (:s, :card) = withCard();
    final p = imports.preview(
      s,
      sheet([
        shinhanHead,
        shinhan(
          '2026.09.05 10:00',
          '가게 예시',
          5000.0,
          '10000052',
          cancelled: '취소',
        ),
        shinhan(
          '2026.09.06 10:00',
          '가게 예시',
          5000.0,
          '10000053',
          bought: '매입취소',
        ),
      ]),
      userCardId: card,
    );
    expect([for (final r in rowsOf(p)) r['status']], ['error', 'error']);
  });

  test('뱅크샐러드는 음수를 결제로, 양수를 취소로 읽고 카드 이름으로 줄을 나눈다', () {
    // 작업 015 성공 기준 2, 3. 카드를 고르지 않으면 보유 카드 줄만, 고르면 그 카드 줄만 넣는다
    final file = sheet([
      banksaladHead,
      banksalad('2026-09-05', '10:00:00', '가게 예시', -5000),
      banksalad('2026-09-05', '18:00:00', '가게 예시', 5000),
      banksalad('2026-09-06', '09:00:00', '다른 가게', -3000, card: '다른 체크카드'),
    ]);
    for (final chosen in [false, true]) {
      final (:s, :card) = withCard();
      final p = imports.preview(s, file, userCardId: chosen ? card : null);
      expect(p['format'], 'banksalad');
      expect(
        [for (final r in rowsOf(p)) (r['status'], r['amount'], r['reason'])],
        [
          ('new', 5000, null),
          ('cancel', 5000, null),
          ('skipped', 3000, chosen ? '고른 카드의 줄이 아니에요' : '보유 카드가 아니에요'),
        ],
      );
    }
  });

  test('뱅크샐러드의 신용카드 결제는 할부인지 몰라 일시불로 넣고 알린다', () {
    // 2026-10-05 사용자가 신용카드 줄을 빼는 안 대신 이 안을 골랐다. 작업 015 설계 3절
    final (:s, clock: _) = fresh();
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    final p = imports.preview(
      s,
      sheet([
        banksaladHead,
        banksalad(
          '2026-09-05',
          '10:00:00',
          '가게 예시',
          -5000,
          card: '신한카드 Mr.Life',
        ),
      ]),
    );
    final [r] = rowsOf(p);
    expect((r['status'], r['installment_months']), ('new', 1));
    expect((p['summary'] as Json)['installment_assumed'], 1);
  });

  test('뱅크샐러드에서 지출이 아니거나 원화가 아닌 줄은 넣지 않는다', () {
    // 받은 파일에는 지출과 KRW만 있었다. 작업 015 설계 1절
    final (:s, :card) = withCard();
    final p = imports.preview(
      s,
      sheet([
        banksaladHead,
        banksalad('2026-09-05', '10:00:00', '가게 예시', 5000, kind: '수입'),
        banksalad('2026-09-05', '11:00:00', '가게 예시', -5000, currency: 'USD'),
      ]),
      userCardId: card,
    );
    expect([for (final r in rowsOf(p)) r['status']], ['error', 'error']);
  });

  test('같은 결제를 카드사 파일과 뱅크샐러드로 두 번 올려도 한 번만 들어간다', () {
    // 작업 015 성공 기준 4, 설계 5절. IBK는 취소된 결제의 원래 줄을 빼고 취소 줄만 적고, 뱅크샐러드는 둘 다 적는다
    final card = ibk([
      line('원화', '2026-09-05 10:00:00', '가게 예시', '5,000', '10000060'),
      line('취소또는할인', '2026-09-07 11:00:00', '다른 가게', '3,000', '10000061'),
    ]);
    final book = sheet([
      banksaladHead,
      banksalad('2026-09-05', '10:00:00', '가게 예시', -5000),
      banksalad('2026-09-06', '09:00:00', '다른 가게', -3000),
      banksalad('2026-09-07', '11:00:00', '다른 가게', 3000),
    ]);
    List<Object?> after(List<Uint8List> files) {
      final (:s, card: uid) = withCard();
      for (final f in files) {
        saveAll(s, imports.preview(s, f, userCardId: uid));
      }
      final [r] = s.db.select(
        'select count(*) n, sum(amount) a, sum(cancelled_amount) c from transactions where deleted_at is null',
      );
      return [r['n'], r['a'], r['c']];
    }

    expect(after([card, book]), [2, 8000, 3000]);
    expect(after([book, card]), [2, 8000, 3000]);
  });

  test('신한카드 이용내역에 카드 여러 장의 줄이 섞였으면 넣지 않는다', () {
    // 작업 015 단계 검토 중간 2. 고른 카드 한 장으로 모두 넣으면 실적이 부푼다
    final (:s, :card) = withCard();
    final p = imports.preview(
      s,
      sheet([
        shinhanHead,
        shinhan('2026.09.05 10:00', '가게 예시', 5000.0, '10000054'),
        shinhan(
          '2026.09.06 10:00',
          '가게 예시',
          5000.0,
          '10000055',
          holder: '가족111*',
        ),
      ]),
      userCardId: card,
    );
    expect(
      {for (final r in rowsOf(p)) (r['status'], r['reason'])},
      {('error', '카드 여러 장의 결제가 든 파일이에요. 카드사에서 카드마다 따로 받아 주세요')},
    );
  });

  test('뱅크샐러드 카드 이름은 공식 이름이 같은 보유 카드에만 붙는다', () {
    // 작업 015 단계 검토 중간 1. 검색 이름이나 이름 일부로 맞추면 다른 카드사의 나라사랑카드가 IBK로 들어간다
    final (:s, card: _) = withCard();
    final p = imports.preview(
      s,
      sheet([
        banksaladHead,
        banksalad(
          '2026-09-05',
          '10:00:00',
          '가게 예시',
          -5000,
          card: 'KB국민 나라사랑카드',
        ),
        banksalad('2026-09-05', '11:00:00', '가게 예시', -5000, card: '나라사랑카드(하나)'),
        banksalad('2026-09-05', '12:00:00', '가게 예시', -5000),
      ]),
    );
    expect(
      [for (final r in rowsOf(p)) r['status']],
      ['skipped', 'skipped', 'new'],
    );
  });
}
