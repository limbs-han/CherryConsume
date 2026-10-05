// 기록 내보내기와 가져오기. 작업 006 설계 6절, 계획 단계 6의 1. 의도 성공 기준 6
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/backup.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/answers.dart';
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/records.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const taptap = {
  'card_id': 'samsung-taptap-o',
  'assumed_prev_month_spend': 300000,
};
const nara = {'card_id': 'ibk-narasarang'};
const zero = {'card_id': 'hyundai-zero-edition3-discount'};

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// 기록을 고루 만든다. 결제, 앱에서 적은 취소, 지운 결제, 해지한 카드와 그 결제, 카드 옵션과 사실, 사람 사실, 엑셀
/// 묶음과 가져오기가 붙인 취소, 열 짝이다
Store sample() {
  final (:s, clock: _) = fresh();
  final [mr, tap, n, z] = setup(s, [mrlife, taptap, nara, zero]);
  pay(s, mr, 4300, 'GS25', at: '2026-09-14T21:00:00+09:00');
  final cafe =
      pay(s, mr, 10000, '스타벅스', at: '2026-09-10T21:30:00+09:00')['id']
          as String;
  cancel(s, cafe, {
    'cancelled_amount': 3000,
    'cancelled_at': '2026-09-12T10:00:00+09:00',
  });
  final gone =
      pay(s, mr, 5000, 'CU', at: '2026-08-20T12:00:00+09:00')['id'] as String;
  delete(s, gone);
  pay(s, tap, 10000, '스타벅스', at: '2026-09-10T12:00:00+09:00');
  cardAnswers(s, tap, {
    'options': {'package': 'p1'},
  });
  cardAnswers(s, n, {
    'facts': {'salary_transfer': true},
  });
  putUserFacts(s, {
    'facts': {'soldier': true},
  });
  pay(s, z, 20000, '이마트', at: '2026-09-01T12:00:00+09:00');
  removeCard(s, z);
  final p = imports.preview(
    s,
    bytes('날,곳,값\n2026.09.05 21:00,GS25,4000\n2026.09.06 10:00,GS25,-4000\n'),
    userCardId: mr,
    mapping: {
      'row': 0,
      'columns': {'date': 0, 'merchant': 1, 'amount': 2},
    },
  );
  imports.save(s, {
    'rows': [
      for (final r in p['rows'] as List)
        if ((r as Json).containsKey('paid_at')) r,
    ],
    'mapping': {'signature': p['signature'], 'columns': p['mapping']},
  });
  return s;
}

List<Map<String, Object?>> rowsOf(Store s, String table) => [
  for (final r in s.db.select('select * from $table order by rowid')) rowMap(r),
];

Map<String, List<Map<String, Object?>>> snapshot(Store s) => {
  for (final t in [...tables, 'import_mappings']) t: rowsOf(s, t),
};

Matcher refused(int code, String message) => throwsA(
  isA<ApiError>()
      .having((e) => e.status, 'status', code)
      .having((e) => e.body, 'body', message),
);

/// 내보낸 파일의 JSON을 고쳐 다시 글자로
String edited(String file, void Function(Json) edit) {
  final j = jsonDecode(file) as Json;
  edit(j);
  return jsonEncode(j);
}

Map table(Json j, String name) => j['tables'][name] as Map;

/// 표의 행 하나의 칸 값을 바꾼다. row가 음수면 끝에서 센다
void put(Json j, String name, int row, String column, Object? value) {
  final t = table(j, name);
  final rows = t['rows'] as List;
  final r = rows[row < 0 ? rows.length + row : row] as List;
  r[(t['columns'] as List).indexOf(column)] = value;
}

void dropColumn(Json j, String name, String column) {
  final t = table(j, name);
  final i = (t['columns'] as List).indexOf(column);
  (t['columns'] as List).removeAt(i);
  for (final r in t['rows'] as List) {
    (r as List).removeAt(i);
  }
}

void main() {
  test('내보내고 빈 DB에 가져오면 홈과 달별 기록이 같다', () {
    // S10 기기 변경. 의도 성공 기준 6
    final s = sample();
    final file = exportAll(s);
    final (s: t, clock: _) = fresh();
    importAll(t, bytes(file));
    for (final table in tables) {
      expect(rowsOf(t, table), rowsOf(s, table), reason: table);
    }
    expect(rowsOf(t, 'transactions'), hasLength(6));
    expect(home(t), home(s));
    for (final month in ['2026-08', '2026-09']) {
      expect(
        records(t, month: month),
        records(s, month: month),
        reason: month,
      );
    }
    // 엑셀 열 짝은 담지 않는다. 2026-10-03 사용자가 정했다
    expect(
      (jsonDecode(file) as Json)['tables'],
      isNot(contains('import_mappings')),
    );
    expect(rowsOf(t, 'import_mappings'), isEmpty);
    expect(rowsOf(s, 'import_mappings'), hasLength(1));
  });

  test('파일 맨 위에 종류, 표 정의 번호, 내보낸 시각이 있다', () {
    final (:s, clock: _) = fresh();
    final j = jsonDecode(exportAll(s)) as Json;
    expect(
      (j['kind'], j['schema'], j['exported_at']),
      ('cherryconsume-records', migrations.length, '2026-09-15T12:00:00.000Z'),
    );
  });

  test('지금 기록이 있으면 파일의 기록으로 바꾸고 이 폰의 열 짝은 그대로 둔다', () {
    final file = exportAll(sample());
    final t = sample();
    final [card] = setup(t, [
      {'card_id': 'lotte-loca365'},
    ]);
    pay(t, card, 9000, '이마트', at: '2026-09-02T12:00:00+09:00');
    final mappings = rowsOf(t, 'import_mappings');
    expect(hasRecords(t), isTrue);
    importAll(t, bytes(file));
    final (:s, clock: _) = fresh();
    importAll(s, bytes(file));
    for (final table in tables) {
      expect(rowsOf(t, table), rowsOf(s, table), reason: table);
    }
    expect(rowsOf(t, 'import_mappings'), mappings);
    expect(hasRecords(fresh().s), isFalse);
    // 답만 있는 폰도 묻는다. 단계 6 위험 검토 6번
    final (s: answered, clock: _) = fresh();
    answered.db.execute(
      "insert into user_facts (key, effective_from, value, answered_at) values ('soldier', '0001-01-01', 'true', 0)",
    );
    expect(hasRecords(answered), isTrue);
  });

  test('받지 않는 파일은 받지 않고 지금 기록이 그대로다', () {
    final file = exportAll(sample());
    final t = sample();
    final before = snapshot(t);
    const notOurs = '체리컨슘 기록 파일이 아니에요';
    const newer = '앱을 새 판으로 올린 뒤 다시 가져와 주세요';
    const unknown = '앱을 껐다 켠 뒤 다시 가져와 주세요. 그래도 안 되면 앱을 새 판으로 올려 주세요';
    const broken = '기록 파일이 깨져 가져오지 못했어요. 지금 기록은 그대로예요';
    final bad = <(String, String, String)>[
      ('깨진 JSON', '{', notOurs),
      ('목록', '[]', notOurs),
      ('다른 종류', '{"kind": "other", "schema": 2, "tables": {}}', notOurs),
      ('기록이 없던 표 번호', edited(file, (j) => j['schema'] = 1), notOurs),
      (
        '모르는 표',
        edited(
          file,
          (j) => j['tables']['sessions'] = {'columns': [], 'rows': []},
        ),
        notOurs,
      ),
      (
        '모르는 칸',
        edited(file, (j) {
          (table(j, 'user_cards')['columns'] as List).add('owner_name');
          for (final r in table(j, 'user_cards')['rows'] as List) {
            (r as List).add('x');
          }
        }),
        notOurs,
      ),
      // 단계 6 위험 검토 4번. 같은 번호 파일에서 표나 칸이 빠지면 혜택이 0원으로 굳거나 지운 결제가 살아난다
      (
        '빠진 표',
        edited(
          file,
          (j) => (j['tables'] as Map).remove('transaction_benefits'),
        ),
        notOurs,
      ),
      (
        '빠진 칸',
        edited(file, (j) => dropColumn(j, 'transactions', 'deleted_at')),
        notOurs,
      ),
      (
        '칸 수가 다른 행',
        edited(
          file,
          (j) => ((table(j, 'transactions')['rows'] as List).first as List)
              .removeLast(),
        ),
        notOurs,
      ),
      (
        '새 표 번호',
        edited(file, (j) => j['schema'] = migrations.length + 1),
        newer,
      ),
      (
        '모르는 카드',
        edited(file, (j) => put(j, 'user_cards', 0, 'card_id', 'nope-card')),
        unknown,
      ),
      (
        '모르는 가맹점',
        edited(
          file,
          (j) => put(j, 'transactions', 0, 'merchant_key', 'nope-shop'),
        ),
        unknown,
      ),
      (
        '모르는 업종',
        edited(file, (j) => put(j, 'transactions', 0, 'category_code', 'nope')),
        unknown,
      ),
      (
        '모르는 결제수단',
        edited(
          file,
          (j) => put(j, 'transactions', 0, 'payment_method', 'nope_pay'),
        ),
        unknown,
      ),
      // 제약을 어기는 행 하나. "4300" 같은 글자는 strict 표가 손실 없이 정수로 바꿔 받는다
      (
        '금액 0',
        edited(file, (j) => put(j, 'transactions', -1, 'amount', 0)),
        broken,
      ),
      (
        '없는 보유 카드',
        edited(
          file,
          (j) => put(j, 'transactions', -1, 'user_card_id', 'nobody'),
        ),
        broken,
      ),
      (
        '수가 아닌 금액',
        edited(file, (j) => put(j, 'transactions', -1, 'amount', '사천삼백')),
        broken,
      ),
      (
        '목록 값',
        edited(file, (j) => put(j, 'transactions', -1, 'merchant_name', [1])),
        broken,
      ),
      (
        '같은 id 두 번',
        edited(file, (j) {
          final rows = table(j, 'transactions')['rows'] as List;
          rows.add(rows.first);
        }),
        broken,
      ),
      // 단계 6 위험 검토 1번. DB 제약에는 없고 앱이 저장할 때 막는 값이다. 받으면 홈이 열리지 않는다
      (
        '모르는 청구 방식',
        edited(file, (j) => put(j, 'transactions', 0, 'billing', 'point_pay')),
        broken,
      ),
      (
        '1억 넘는 금액',
        edited(file, (j) => put(j, 'transactions', -1, 'amount', 100000001)),
        broken,
      ),
      (
        '37개월 할부',
        edited(
          file,
          (j) => put(j, 'transactions', 0, 'installment_months', 37),
        ),
        broken,
      ),
      (
        'JSON이 아닌 답',
        edited(file, (j) => put(j, 'user_facts', 0, 'value', 'yes')),
        broken,
      ),
    ];
    for (final (why, text, message) in bad) {
      expect(
        () => importAll(t, bytes(text)),
        refused(422, message),
        reason: why,
      );
      expect(snapshot(t), before, reason: why);
    }
    expect(
      () => importAll(t, Uint8List(20000001)),
      refused(413, '파일이 20MB보다 커요'),
    );
    expect(snapshot(t), before);
  });

  test('가져오기 상한을 넘는 기록은 내보내지 않는다', () {
    // 단계 6 위험 검토 2번. 내보낸 파일을 어느 폰에서도 가져올 수 없으면 옛 폰을 지운 뒤에야 알게 된다
    final (:s, clock: _) = fresh();
    setup(s);
    s.db.execute('update user_cards set nickname = ?', ['x' * maxBytes]);
    expect(() => exportAll(s), refused(413, '기록이 20MB보다 커 한 파일에 담지 못해요'));
  });

  test('내보내는 칸은 정해 둔 것뿐이다', () {
    // 단계 6 위험 검토 7번. 카드번호 끝자리처럼 폰 밖으로 나가면 안 되는 칸을 표에 더하면 여기서 걸린다. 칸을 더할 때
    // 내보내도 되는지 보고 여기에 적는다
    final j = jsonDecode(exportAll(fresh().s)) as Json;
    expect(
      {for (final t in tables) t: table(j, t)['columns']},
      {
        'user_cards': [
          'id',
          'card_id',
          'nickname',
          'assumed_prev_month_spend',
          'started_on',
          'last_payment_method',
          'added_at',
          'removed_at',
        ],
        'import_batches': [
          'id',
          'source',
          'row_count',
          'imported_count',
          'duplicate_count',
          'cancel_count',
          'created_at',
          'undone_at',
        ],
        'transactions': [
          'id',
          'user_card_id',
          'amount',
          'merchant_name',
          'merchant_key',
          'category_code',
          'paid_at',
          'installment_months',
          'interest_free_installment',
          'cancelled_amount',
          'cancelled_at',
          'channel',
          'region',
          'payment_method',
          'billing',
          'revision_from',
          'revision_sha',
          'approval_no',
          'import_batch_id',
          'source',
          'from_recommendation',
          'time_known',
          'created_at',
          'updated_at',
          'deleted_at',
        ],
        'transaction_benefits': [
          'transaction_id',
          'benefit_key',
          'amount',
          'value',
          'base_amount',
        ],
        'import_cancels': [
          'id',
          'import_batch_id',
          'transaction_id',
          'amount',
          'cancelled_at',
        ],
        'user_card_options': [
          'id',
          'user_card_id',
          'option_key',
          'choice_key',
          'effective_from',
          'answered_at',
        ],
        'user_card_facts': [
          'user_card_id',
          'key',
          'effective_from',
          'value',
          'answered_at',
        ],
        'user_facts': ['key', 'effective_from', 'value', 'answered_at'],
        // 작업 016 설계 6절. 가게 이름 열쇠와 고른 업종이다
        'merchant_categories': ['name_key', 'category_code', 'updated_at'],
      },
    );
  });

  test('가져온 결제보다 새 결제 id가 크다', () {
    // 시계가 앞서던 폰에서 내보낸 기록이다. 가져온 뒤 앱을 다시 켜지 않아도 새 결제가 같은 시각 결제 순서를 뒤집지 않는다
    final s = sample();
    const ahead = 'fff00000-0000-7000-8000-000000000000';
    final file = edited(exportAll(s), (j) {
      final t = table(j, 'transactions');
      final row = (t['rows'] as List).first as List;
      final at = (t['columns'] as List).indexOf('id');
      final old = row[at];
      row[at] = ahead;
      for (final name in ['transaction_benefits', 'import_cancels']) {
        final u = table(j, name);
        final k = (u['columns'] as List).indexOf('transaction_id');
        for (final r in u['rows'] as List) {
          if ((r as List)[k] == old) r[k] = ahead;
        }
      }
    });
    final (s: t, clock: _) = fresh();
    forgetIds();
    importAll(t, bytes(file));
    final card =
        t.db
                .select('select id from user_cards where removed_at is null')
                .first['id']
            as String;
    final id = pay(t, card, 1000, 'GS25')['id'] as String;
    expect(id.compareTo(ahead), greaterThan(0));
  });

  test('기억한 가게 업종을 내보내고 가져오며, 표 정의 4번 파일은 그 표 없이도 받는다', () {
    // 작업 016 설계 6절. 2026-10-05 사용자가 담기로 했다
    final s = sample();
    s.db.execute(
      "insert into merchant_categories (name_key, category_code, updated_at) values ('동네국밥집', 'restaurant', 1)",
    );
    final file = exportAll(s);
    final (s: t, clock: _) = fresh();
    importAll(t, bytes(file));
    expect(rowsOf(t, 'merchant_categories'), rowsOf(s, 'merchant_categories'));
    // 옛 판 파일에는 이 표가 없다
    final (s: u, clock: _) = fresh();
    importAll(
      u,
      bytes(
        edited(file, (j) {
          j['schema'] = 4;
          (j['tables'] as Map).remove('merchant_categories');
        }),
      ),
    );
    expect(rowsOf(u, 'merchant_categories'), isEmpty);
    expect(rowsOf(u, 'transactions'), rowsOf(s, 'transactions'));
    // 5번 파일에서 빠지면 깨진 파일이다. 카탈로그에 없는 업종도 받지 않는다
    expect(
      () => importAll(
        fresh().s,
        bytes(
          edited(
            file,
            (j) => (j['tables'] as Map).remove('merchant_categories'),
          ),
        ),
      ),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => importAll(
        fresh().s,
        bytes(
          edited(
            file,
            (j) => put(j, 'merchant_categories', 0, 'category_code', 'nope'),
          ),
        ),
      ),
      throwsA(isA<ApiError>()),
    );
  });
}
