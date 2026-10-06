// 이용 내역 엑셀 가져오기. 서버 `backend/tests/api/test_imports.py`를 옮겼다. 작업 006 설계 5절, 계획 단계 5의 2.
// S11, E30~E35, E51, E57
//
// 신한카드 Mr.Life를 지난달 41만 원으로 등록해 30만 구간이다. 편의점 10%는 하루 종일, 하루 1회라 GS25 4,300원은
// 430원이다. 야간 식음료 10%는 21시부터라 21시 카페 4,500원은 450원이다. 시계는 2026-09-15 21:00 한국 시간이다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/imports.dart' show signature;
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show removeCard;
import 'package:cherry_consume/store/routes/records.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const zero = {'card_id': 'hyundai-zero-edition3-discount'};
const head = '이용일자,이용시간,가맹점명,이용금액,할부,승인번호,취소여부';

Uint8List csv(List<String> lines) => cp949.encode([head, ...lines].join('\n'));

Json preview(Store s, Uint8List data, {String? card, Object? mapping}) =>
    imports.preview(s, data, userCardId: card, mapping: mapping);

/// 앱처럼 판정받은 행을 모두 보낸다. 짝을 차지한 겹친 행이 빠지면 다시 판정이 달라진다
Json saveAll(Store s, Json p, [Json? mapping]) => imports.save(s, {
  'rows': [
    for (final r in p['rows'] as List)
      if ((r as Json).containsKey('paid_at')) r,
  ],
  'mapping': mapping,
});

List<(String, String?)> statuses(Json p) => [
  for (final r in p['rows'] as List)
    ((r as Json)['status'] as String, r['reason'] as String?),
];

List<String> only(Json p) => [for (final (s, _) in statuses(p)) s];

List<Json> recordsOf(Store s, [String month = '2026-09']) => [
  for (final x in records(s, month: month)['payments'] as List) x as Json,
];

final month = csv([
  '2026.09.10,21:30,GS25 강남점,"4,300",일시불,A1001,',
  '2026.09.11,,이마트 성수점,"120,000",3개월,A1002,',
  '2026.09.12,22:00,GS25 강남점,"-4,300",일시불,A1001,취소',
  '합계,,,"120,000",,,',
]);

void main() {
  test('test_month_twice_goes_in_once', () {
    // S11 성공 기준. 9월 10일 21시 30분 GS25 4,300원은 430원, 9월 11일 이마트 12만 원 3개월은 0원이다. 9월 12일 GS25 전액
    // 취소는 승인번호가 같은 9월 10일 결제에 붙어 0원이 된다. 이마트는 시각이 없어 그날 12시이고 시각을 모른다. 3개월은
    // 무이자인지 몰라 유이자로 넣고 센다. 같은 파일을 다시 올리면 셋 모두 겹쳐 아무것도 들어가지 않는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final p = preview(s, month, card: mr);
    expect(statuses(p), [('new', null), ('new', null), ('cancel', null)]);
    expect(p['summary'], {
      'rows': 3,
      'new': 2,
      'amount': 124300,
      'duplicates': 0,
      'cancels': 1,
      'orphans': 0,
      'discounts': 0,
      'skipped': 0,
      'installment_assumed': 0,
      'errors': 0,
      'uncategorized': 0,
      'interest_unknown': 1,
      'easy_pay': 0,
      'untimed': 1,
    });
    final second = (p['rows'] as List)[1] as Json;
    expect(
      (second['paid_at'], second['timed']),
      ('2026-09-11T12:00:00+09:00', false),
    );
    final done = saveAll(s, p);
    expect((done['imported'], done['cancels'], done['duplicates']), (2, 1, 0));
    expect(
      {
        for (final r in recordsOf(s))
          r['merchant_name']: (
            r['value'],
            r['cancelled_amount'],
            r['time_known'],
          ),
      },
      {'GS25 강남점': (0, 4300, true), '이마트 성수점': (0, 0, false)},
    );
    expect(only(preview(s, month, card: mr)), [
      'duplicate',
      'duplicate',
      'duplicate',
    ]);
    expect(recordsOf(s), hasLength(2));
  });

  test('test_partial_cancels_on_two_days_go_in_once', () {
    // 높음 1번. 1만 원 결제에 9월 12일 3,000원, 9월 13일 2,000원 취소가 있다. 남은 5,000원의 10%로 500원이다. 같은
    // 파일을 다시 올려도 취소는 5,000원 그대로다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final data = csv([
      '2026.09.10,21:00,GS25,"10,000",,A2001,',
      '2026.09.12,10:00,GS25,"-3,000",,A2001,취소',
      '2026.09.13,10:00,GS25,"-2,000",,A2001,취소',
    ]);
    saveAll(s, preview(s, data, card: mr));
    var [row] = recordsOf(s);
    expect((row['value'], row['cancelled_amount']), (500, 5000));
    expect(only(preview(s, data, card: mr)), [
      'duplicate',
      'duplicate',
      'duplicate',
    ]);
    [row] = recordsOf(s);
    expect(row['cancelled_amount'], 5000);
  });

  test('test_same_rows_in_one_file_are_two_payments', () {
    // 중간 5번. 시각 없는 파일의 같은 날 GS25 1,500원 두 줄은 두 결제다. 이미 있는 결제와만 겹침을 본다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final p = preview(
      s,
      csv(['2026.09.10,,GS25,1500,,,', '2026.09.10,,GS25,1500,,,']),
      card: mr,
    );
    expect(only(p), ['new', 'new']);
  });

  test('test_manual_payment_overlaps_within_ten_minutes', () {
    // E31, 2026-10-02 사용자가 넓혔다. 직접 넣은 21시 3분 "GS25" 4,300원과 파일의 21시 "GS25 역삼점" 4,300원은 10분 안이고
    // 한 이름이 다른 이름을 담아 겹친다. 21시 20분이면 다른 결제다. 원 결제가 없는 취소는 저장하지 않는다. E32
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    pay(s, mr, 4300, 'GS25', at: '2026-09-14T21:03:00+09:00');
    final data = csv([
      '2026.09.14,21:00,GS25 역삼점,"4,300",,,',
      '2026.09.14,21:20,GS25 역삼점,"4,300",,,',
      '2026.09.13,10:00,CU 역삼점,"-2,000",,,취소',
    ]);
    expect(statuses(preview(s, data, card: mr)), [
      ('duplicate', null),
      ('new', null),
      ('orphan', '원 결제를 찾지 못했어요'),
    ]);
  });

  test('test_cancel_with_approval_finds_a_manual_payment', () {
    // 중간 6번. 직접 넣은 결제에는 승인번호가 없다. 승인번호가 같은 결제가 없으면 가맹점과 금액으로 찾는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final tid = pay(
      s,
      mr,
      10000,
      'GS25',
      at: '2026-09-10T21:00:00+09:00',
    )['id'];
    saveAll(
      s,
      preview(s, csv(['2026.09.12,10:00,GS25,"-10,000",,A9,취소']), card: mr),
    );
    expect(
      {for (final r in recordsOf(s)) r['id']: r['cancelled_amount']},
      {tid: 10000},
    );
  });

  test('test_cancel_on_a_payment_already_cancelled_in_the_app', () {
    // 중간 13번. 앱에서 3,000원 취소를 적은 결제에 승인번호 없는 파일의 취소가 오면 겹치는지 몰라 넣지 않는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final tid =
        pay(s, mr, 10000, 'GS25', at: '2026-09-10T21:00:00+09:00')['id']
            as String;
    cancel(s, tid, {
      'cancelled_amount': 3000,
      'cancelled_at': '2026-09-14T10:00:00+09:00',
    });
    final p = preview(
      s,
      csv(['2026.09.12,10:00,GS25,"-3,000",,,취소']),
      card: mr,
    );
    expect(statuses(p), [('orphan', '앱에서 적은 취소가 있어 겹치는지 몰라요. 기록에서 확인해 주세요')]);
  });

  test('test_two_cancels_go_to_two_payments', () {
    // 낮음 22번. 9월 5일과 8일의 GS25 1만 원에 1만 원 취소가 둘이면 하나씩 붙는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final data = csv([
      '2026.09.05,21:00,GS25,10000,,,',
      '2026.09.08,21:00,GS25,10000,,,',
      '2026.09.10,10:00,GS25,-10000,,,취소',
      '2026.09.11,10:00,GS25,-10000,,,취소',
    ]);
    saveAll(s, preview(s, data, card: mr));
    expect(
      [for (final r in recordsOf(s)) r['cancelled_amount'] as int]..sort(),
      [10000, 10000],
    );
  });

  test('test_undo_two_batches_in_any_order', () {
    // 중간 12번. 1만 원 결제에 묶음 1이 3,000원, 묶음 2가 2,000원 취소를 붙였다. 묶음 1을 되돌리면 2,000원이 남고, 묶음 2도
    // 되돌리면 0원이다. 남은 5,000원 취소면 500원, 2,000원이면 남은 8,000원의 10%로 800원, 0원이면 1,000원이다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final tid = pay(
      s,
      mr,
      10000,
      'GS25',
      at: '2026-09-10T21:00:00+09:00',
    )['id'];
    final one = saveAll(
      s,
      preview(s, csv(['2026.09.12,10:00,GS25,-3000,,,취소']), card: mr),
    );
    final two = saveAll(
      s,
      preview(s, csv(['2026.09.13,10:00,GS25,-2000,,,취소']), card: mr),
    );
    (Object?, Object?, Object?) row() {
      final [r] = recordsOf(s);
      return (r['id'], r['cancelled_amount'], r['value']);
    }

    expect(row(), (tid, 5000, 500));
    imports.undo(s, one['id'] as int);
    expect(row(), (tid, 2000, 800));
    imports.undo(s, two['id'] as int);
    expect(row(), (tid, 0, 1000));
    expect(() => imports.undo(s, two['id'] as int), throwsA(status(404)));
  });

  test('test_undo_removes_imported_payments', () {
    // E34. 가져온 결제는 지워지고 목록에 되돌린 시각이 남는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final done = saveAll(
      s,
      preview(s, csv(['2026.09.15,12:00,이마트,30000,,,']), card: mr),
    );
    final [batch] = imports.batches(s);
    expect(
      (batch['id'], batch['imported_count'], batch['undone_at']),
      (done['id'], 1, null),
    );
    imports.undo(s, done['id'] as int);
    expect(recordsOf(s), isEmpty);
    expect(imports.batches(s).first['undone_at'], isNotNull);
  });

  test('test_earlier_imported_payment_takes_the_daily_limit', () {
    // E51. 편의점 10%는 하루 1회다. 직접 넣은 9월 14일 21시 30분 GS25 4,300원이 430원이었다. 같은 날 21시 GS25 5,000원을
    // 가져오면 앞선 결제가 하루 1회를 먼저 써 500원이고 21시 30분 결제는 0원이다. 금액이 달라 겹치지 않는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final late = pay(
      s,
      mr,
      4300,
      'GS25',
      at: '2026-09-14T21:30:00+09:00',
    )['id'];
    final data = csv(['2026.09.14,21:00,GS25 역삼점,"5,000",,,']);
    expect(saveAll(s, preview(s, data, card: mr))['repriced'], 1);
    final values = {for (final r in recordsOf(s)) r['id']: r['value'] as int};
    expect(values[late], 0);
    expect(values.values.toList()..sort(), [0, 500]);
  });

  test('test_untimed_payment_does_not_get_a_night_benefit', () {
    // E57. 야간 식음료는 21시부터다. 시각이 있는 21시 30분 스타벅스 4,500원은 450원이다. 시각이 없는 같은 날 스타벅스는
    // 시각을 몰라 0원이다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    saveAll(
      s,
      preview(
        s,
        csv(['2026.09.10,21:30,스타벅스,4500,,,', '2026.09.11,,스타벅스,4500,,,']),
        card: mr,
      ),
    );
    expect([for (final r in recordsOf(s)) r['value'] as int]..sort(), [0, 450]);
  });

  test('test_easy_pay_future_rows_and_card_column', () {
    // 결제수단은 가맹점명이 간편결제 이름으로 시작하면 그 결제수단이다. 지금보다 하루 넘게 뒤의 결제는 읽지 못한 행이다.
    // 카드 이름 열로 나누고 보유 카드에 없는 카드의 행은 건너뛴다. E33. 고른 카드가 있으면 카드 이름 열보다 앞선다
    final (:s, clock: _) = fresh();
    final [mr, z] = setup(s, [mrlife, zero]);
    final data = Uint8List.fromList(
      utf8.encode(
        [
          '카드명,이용일자,가맹점명,이용금액',
          '신한카드 Mr.Life,2026.09.10,네이버페이 스타벅스,4300',
          '현대카드ZERO Edition3(할인형),2026.09.10,이마트,10000',
          '롯데카드 LOCA 365,2026.09.10,이마트,20000',
          '신한카드 Mr.Life,2026.12.10,이마트,20000',
        ].join('\n'),
      ),
    );
    final p = preview(s, data);
    final rows = [for (final r in p['rows'] as List) r as Json];
    expect(
      [for (final r in rows) (r['status'], r['user_card_id'])],
      [('new', mr), ('new', z), ('skipped', null), ('error', null)],
    );
    expect(
      (rows[0]['payment_method'], rows[3]['reason']),
      ('naver_pay', '지금보다 뒤의 결제예요'),
    );
    expect((p['summary'] as Json)['easy_pay'], 1);
    final chosen = preview(s, data, card: z);
    expect(
      [
        for (final r in (chosen['rows'] as List).take(3))
          (r as Json)['user_card_id'],
      ],
      [z, z, z],
    );
  });

  test('test_mapping_is_kept_when_saving', () {
    // E30. 열 이름을 못 찾으면 머리 줄과 열 이름을 준다. 짝지은 열 번호로 읽고, 저장할 때 남겨 같은 모양의 다음 파일에
    // 쓴다. 미리보기만 하고 그만두면 남기지 않는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final data = Uint8List.fromList(
      utf8.encode('날,곳,값\n2026.09.10,GS25,4300\n'),
    );
    final p = preview(s, data, card: mr);
    expect((p['needs_mapping'], p['header_row']), (true, 0));
    expect(p['headers'], ['날', '곳', '값']);
    expect(p['rows'], isEmpty);
    final mapping = {
      'row': 0,
      'columns': {'date': 0, 'merchant': 1, 'amount': 2},
    };
    final read = preview(s, data, card: mr, mapping: mapping);
    expect((read['summary'] as Json)['new'], 1);
    expect(preview(s, data, card: mr)['needs_mapping'], true);
    saveAll(s, read, {
      'signature': read['signature'],
      'columns': read['mapping'],
    });
    final later = preview(
      s,
      Uint8List.fromList(utf8.encode('날,곳,값\n2026.09.11,CU,1000\n')),
      card: mr,
    );
    expect((later['summary'] as Json)['new'], 1);
  });

  test('test_bad_files_and_requests', () {
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    expect(
      () => preview(
        s,
        Uint8List.fromList([0xd0, 0xcf, 0x11, 0xe0, ...List.filled(64, 0x30)]),
        card: mr,
      ),
      throwsA(
        allOf(
          status(422),
          // 작업 017부터 옛 엑셀을 읽어, 앞머리만 옛 엑셀인 파일은 깨진 파일이다
          isA<ApiError>().having((e) => e.body, 'body', contains('깨져')),
        ),
      ),
    );
    // 카드 이름 열이 없으면 카드를 골라야 한다
    expect(() => preview(s, month), throwsA(status(422)));
    expect(
      () => preview(s, Uint8List(2100000), card: mr),
      throwsA(status(413)),
    );
    // 서버는 열 짝을 JSON 글자로 받아 "{"가 422였다. 폰은 Map으로 받아 Map이 아니면 422다
    expect(
      () => preview(s, month, card: mr, mapping: '{'),
      throwsA(status(422)),
    );
    final row = {
      'user_card_id': mr,
      'paid_at': '2026-09-10T21:30:00+09:00',
      'timed': true,
      'merchant_name': 'GS25',
      'amount': 4300,
      'installment_months': 1,
      'approval_no': null,
      'cancel': false,
    };
    // 빈 저장, 5년보다 오래된 행, 보유 카드가 아닌 카드는 받지 않는다
    expect(() => imports.save(s, {'rows': []}), throwsA(status(422)));
    expect(
      () => imports.save(s, {
        'rows': [
          {...row, 'paid_at': '2019-01-01T12:00:00+09:00'},
        ],
      }),
      throwsA(status(422)),
    );
    // 서버는 남의 카드였다. 사용자가 한 명이라 해지한 카드로 본다
    final [gone] = setup(s, [zero]);
    removeCard(s, gone);
    expect(
      () => imports.save(s, {
        'rows': [
          {...row, 'user_card_id': gone},
        ],
      }),
      throwsA(status(404)),
    );
  });

  test('test_past_month_cancel_on_a_ranked_card_without_the_cancel_month', () {
    // 중간 11번, E55. KB 이지올은 순위 영역의 취소 달 칸이 비어 있다. 지나간 8월 결제의 취소를 가져오면 순위를 다시
    // 매기지 않으려 넣지 않고 기록에서 직접 적게 한다. 2026-10-02 삼성 iD ON은 골드에 cancel_month가 들어가 정상으로 붙는다
    final (:s, clock: _) = fresh();
    final [easy, ion] = setup(s, [
      {'card_id': 'kb-easy-all-titanium'},
      {'card_id': 'samsung-id-on'},
    ]);
    for (final card in [easy, ion]) {
      pay(s, card, 600000, '이마트', at: '2026-07-10T12:00:00+09:00');
      pay(s, card, 10000, '스타벅스', at: '2026-08-05T12:00:00+09:00');
    }
    final data = csv(['2026.08.20,10:00,스타벅스,-5000,,,취소']);
    expect(statuses(preview(s, data, card: easy)), [
      ('orphan', '이 카드는 순위 혜택의 취소 달을 몰라요. 기록에서 직접 적어 주세요'),
    ]);
    expect(statuses(preview(s, data, card: ion)), [('cancel', null)]);
  });

  test('test_save_matches_the_preview', () {
    // 재검토 높음 1번. 직접 넣은 12시 GS25 1,500원과 파일의 12시 2분, 12시 6분 GS25 1,500원이다. 12시 2분이 겹치고 12시 6분은
    // 새 결제다. 저장도 1건이다. 묶음 1이 9월 12일 3,000원 취소를 붙인 결제에 같은 날 3,000원 취소가 두 줄 오면 하나는
    // 겹치고 하나는 진짜 두 번째 취소다. 저장하면 취소가 6,000원이고 남은 4,000원의 10%로 400원이다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    pay(s, mr, 1500, 'GS25', at: '2026-09-10T12:00:00+09:00');
    final p = preview(
      s,
      csv(['2026.09.10,12:02,GS25,1500,,,', '2026.09.10,12:06,GS25,1500,,,']),
      card: mr,
    );
    expect((p['summary'] as Json)['new'], 1);
    expect(saveAll(s, p)['imported'], 1);
    // 서버는 다른 사용자였다. 사용자가 한 명이라 새 DB로 본다
    final (s: other, clock: _) = fresh();
    final [card] = setup(other);
    final tid = pay(
      other,
      card,
      10000,
      'GS25',
      at: '2026-09-10T21:00:00+09:00',
    )['id'];
    saveAll(
      other,
      preview(other, csv(['2026.09.12,10:00,GS25,-3000,,,취소']), card: card),
    );
    final two = preview(
      other,
      csv([
        '2026.09.12,10:00,GS25,-3000,,,취소',
        '2026.09.12,11:00,GS25,-3000,,,취소',
      ]),
      card: card,
    );
    expect(only(two), ['duplicate', 'cancel']);
    expect(saveAll(other, two)['cancels'], 1);
    expect(
      {
        for (final r in recordsOf(other))
          r['id']: (r['cancelled_amount'], r['value']),
      },
      {tid: (6000, 400)},
    );
  });

  test('test_same_approval_in_new_rows_is_one_payment', () {
    // 재검토 중간 3번. 승인 줄과 매입 줄처럼 새 행 둘의 승인번호가 같으면 한 결제다. 저장이 500이 되지 않는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final p = preview(
      s,
      csv([
        '2026.09.10,21:00,GS25,4300,,B5001,',
        '2026.09.11,09:00,GS25,4300,,B5001,',
      ]),
      card: mr,
    );
    expect(only(p), ['new', 'duplicate']);
    expect(saveAll(s, p)['imported'], 1);
  });

  test('test_untimed_cancel_after_a_timed_payment_on_the_same_day', () {
    // 재검토 중간 6번. 9월 12일 21시 30분 GS25 4,300원과 시각 없는 같은 날 취소가 한 파일에 있으면 붙는다. 취소 시각은 결제보다
    // 앞서지 않아 그 결제를 고칠 수 있다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    saveAll(
      s,
      preview(
        s,
        csv(['2026.09.12,21:30,GS25,4300,,,', '2026.09.12,,GS25,-4300,,,취소']),
        card: mr,
      ),
    );
    final [row] = recordsOf(s);
    expect(row['cancelled_amount'], 4300);
    expect(
      DateTime.parse(
        row['cancelled_at'] as String,
      ).isBefore(DateTime.parse(row['paid_at'] as String)),
      isFalse,
    );
    edit(s, row['id'] as String, {
      'user_card_id': mr,
      'amount': 4300,
      'merchant_name': 'GS25 역삼점',
      'paid_at': row['paid_at'],
    });
  });

  test('test_editing_an_untimed_payment_keeps_the_time_unknown', () {
    // 재검토 중간 5번. 시각 없는 결제의 가게만 고치면 시각은 여전히 모른다. 시각을 바꾸면 안다. E57
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    saveAll(s, preview(s, csv(['2026.09.11,,스타벅스,4500,,,']), card: mr));
    var [row] = recordsOf(s);
    final body = {
      'user_card_id': mr,
      'amount': 4500,
      'merchant_name': '스타벅스 역삼',
      'paid_at': row['paid_at'],
    };
    edit(s, row['id'] as String, body);
    expect(recordsOf(s).first['time_known'], false);
    edit(s, row['id'] as String, {
      ...body,
      'paid_at': '2026-09-11T21:30:00+09:00',
    });
    [row] = recordsOf(s);
    expect((row['time_known'], row['value']), (true, 450));
  });

  test('시각 없는 결제의 가게만 고쳐도 시각 조건은 모름으로 계산한다', () {
    // 단계 4 위험 검토 8번. 실제 카탈로그의 시각 조건은 21시부터라 12시로 둔 결제는 시각을 알든 모르든 0원이다. 야간
    // 식음료를 11시~13시로 바꾼 카탈로그로 본다. 시각을 모르면 0원, 12시를 진짜 시각으로 보면 450원이다
    void noon(Object? j) {
      if (j is Map) {
        if (j['time'] case {'from': '21:00', 'to': '09:00'}) {
          j['time'] = {'from': '11:00', 'to': '13:00'};
        }
        j.values.forEach(noon);
      } else if (j is List) {
        j.forEach(noon);
      }
    }

    final (:s, clock: _) = fresh(noon);
    final [mr] = setup(s);
    saveAll(s, preview(s, csv(['2026.09.11,,스타벅스,4500,,,']), card: mr));
    var [row] = recordsOf(s);
    expect(row['value'], 0);
    edit(s, row['id'] as String, {
      'user_card_id': mr,
      'amount': 4500,
      'merchant_name': '스타벅스 역삼',
      'paid_at': row['paid_at'],
    });
    [row] = recordsOf(s);
    expect((row['time_known'], row['value']), (false, 0));
    // 시험이 시각 조건을 실제로 보는지. 같은 12시를 직접 넣으면 시각을 알아 450원이다
    expect(
      pay(s, mr, 4500, '스타벅스', at: '2026-09-12T12:00:00+09:00')['value'],
      450,
    );
  });

  test('test_ten_minutes_is_the_edge', () {
    // E31 경계. 직접 넣은 21시 GS25 4,300원과 파일의 21시 10분은 겹치고 21시 10분 1초는 다른 결제다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    pay(s, mr, 4300, 'GS25', at: '2026-09-10T21:00:00+09:00');
    pay(s, mr, 4300, 'GS25', at: '2026-09-11T21:00:00+09:00');
    final data = csv([
      '2026.09.10,21:10:00,GS25,4300,,,',
      '2026.09.11,21:10:01,GS25,4300,,,',
    ]);
    expect(only(preview(s, data, card: mr)), ['duplicate', 'new']);
  });

  test('test_body_size_edge', () {
    // 2,000,000바이트는 받고 2,000,001바이트는 413이다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final top = cp949.encode('$head\n');
    // 짧은 줄로 채운다. 한 칸이 너무 길면 csv가 읽지 못한다
    final line = [...List.filled(999, 0x78), 10];
    final filler = [
      for (var i = 0; i < (2000000 - top.length) ~/ line.length; i++) ...line,
    ];
    final ok = Uint8List.fromList([
      ...top,
      ...filler,
      ...List.filled(2000000 - top.length - filler.length, 0x78),
    ]);
    expect(ok.length, 2000000);
    expect(preview(s, ok, card: mr)['needs_mapping'], false);
    expect(
      () => preview(s, Uint8List.fromList([...ok, 0x20]), card: mr),
      throwsA(status(413)),
    );
  });
  test('승인번호가 되풀이되는 파일을 다시 올려도 모두 겹치고 저장된다', () {
    // 단계 5 위험 검토 2번, S11. 승인 줄과 매입 줄의 B5001 두 줄은 한 결제다. 다시 올리면 첫 줄이 저장된 결제와 겹치고
    // 둘째 줄도 같은 승인번호라 겹친다. 서버는 둘째 줄을 새 결제로 보아 저장이 409로 막혔다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final data = csv([
      '2026.09.10,21:00,GS25,4300,,B5001,',
      '2026.09.11,09:00,GS25,4300,,B5001,',
    ]);
    expect(saveAll(s, preview(s, data, card: mr))['imported'], 1);
    final again = preview(s, data, card: mr);
    expect(only(again), ['duplicate', 'duplicate']);
    expect(saveAll(s, again)['imported'], 0);
    expect(recordsOf(s), hasLength(1));
  });

  test('저장된 짝이 깨졌거나 맞지 않으면 자동으로 찾는다', () {
    // 단계 5 위험 검토 7번. 단계 6의 가져오기로 들어온 짝이 깨졌어도 그 머리 줄 모양의 파일을 읽는다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final sig = signature(head.split(','));
    for (final broken in ['{', '{"date": 99, "merchant": 2, "amount": 3}']) {
      s.db.execute(
        'insert or replace into import_mappings (signature, mapping, updated_at) values (?, ?, 0)',
        [sig, broken],
      );
      final p = preview(s, month, card: mr);
      expect(p['needs_mapping'], false, reason: broken);
      expect(only(p), ['new', 'new', 'cancel'], reason: broken);
    }
  });

  test('하루 뒤와 5년 전 경계', () {
    // 지금은 2026-09-15 21:00이다. 2026-09-16 21:00은 받고 21:01은 지금보다 뒤다. 5년은 1,825일이라 2021-09-16 21:00은
    // 받고 20:59는 오래됐다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final p = preview(
      s,
      csv([
        '2026.09.16,21:00,GS25,1000,,,',
        '2026.09.16,21:01,CU,1000,,,',
        '2021.09.16,21:00,이마트,1000,,,',
        '2021.09.16,20:59,홈플러스,1000,,,',
      ]),
      card: mr,
    );
    expect(statuses(p), [
      ('new', null),
      ('error', '지금보다 뒤의 결제예요'),
      ('new', null),
      ('error', '5년보다 오래된 결제예요'),
    ]);
  });

  test('보유 카드가 아닌 카드로 미리보기하면 404다', () {
    final (:s, clock: _) = fresh();
    setup(s);
    expect(() => preview(s, month, card: 'nope'), throwsA(status(404)));
  });

  test('가게 이름은 100자에서 자르고 넷째 바이트 글자의 반쪽을 남기지 않는다', () {
    // 99자 뒤의 그림 글자는 UTF-16으로 두 칸이라 100자에 걸리면 통째로 뺀다
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final name = '${'a' * 99}😀b';
    final p = preview(
      s,
      Uint8List.fromList(
        utf8.encode('이용일자,가맹점명,이용금액\n2026.09.10,$name,1000\n'),
      ),
      card: mr,
    );
    expect(((p['rows'] as List).single as Json)['merchant_name'], 'a' * 99);
  });
}
