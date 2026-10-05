// 폰 안 표 정의와 열기. 작업 006 설계 4절, 계획 단계 4의 1, 의도 성공 기준 8
import 'dart:io';

import 'package:cherry_consume/store/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const tables = {
  'catalog_cache',
  'user_cards',
  'transactions',
  'transaction_benefits',
  'user_card_options',
  'user_facts',
  'user_card_facts',
  'import_batches',
  'import_cancels',
  'import_mappings',
  // 기록이 아닌 앱 상태. 마지막으로 내보낸 날을 둔다. 작업 012 설계 4.2
  'app_state',
  // 카드 규칙 파일. 작업 014 설계 2절
  'catalog_card_files',
};

Set<String> tablesIn(Database db) => {
  for (final r in db.select(
    "select name from sqlite_master where type = 'table' and name not like 'sqlite_%'",
  ))
    r['name'] as String,
};

void card(
  Database db,
  String id, {
  String cardId = 'shinhan-mrlife',
  int? removedAt,
}) => db.execute(
  'insert into user_cards (id, card_id, added_at, removed_at) values (?, ?, 0, ?)',
  [id, cardId, removedAt],
);

void pay(Database db, Map<String, Object?> row) {
  final full = {
    'id': newId(DateTime.utc(2026, 9, 15, 12)),
    'user_card_id': 'u1',
    'amount': 10000,
    'paid_at': 0,
    'created_at': 0,
    'updated_at': 0,
    ...row,
  };
  db.execute(
    'insert into transactions (${full.keys.join(', ')}) values (${[for (final _ in full.keys) '?'].join(', ')})',
    full.values.toList(),
  );
}

void main() {
  test('test_migrations_run_once', () {
    // 빈 DB에 표가 생기고 다시 열어도 표 정의를 다시 돌리지 않아 그대로다
    final dir = Directory.systemTemp.createTempSync('cherry');
    try {
      final path = '${dir.path}/cherry.db';
      final db = openDb(path);
      expect(tablesIn(db), tables);
      card(db, 'u1');
      db.close();
      final again = openDb(path);
      expect(tablesIn(again), tables);
      expect(again.userVersion, migrations.length);
      expect(again.select('select id from user_cards').single['id'], 'u1');
      again.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('표 바꾸기가 실패하면 모두 되돌린다', () {
    final dir = Directory.systemTemp.createTempSync('cherry');
    try {
      final path = '${dir.path}/cherry.db';
      const first = 'create table a (x integer) strict';
      openDb(path, [first]).close();
      expect(
        () => openDb(path, [
          first,
          'create table b (y integer) strict; insert into nope values (1)',
        ]),
        throwsA(isA<SqliteException>()),
      );
      final again = openDb(path, [first]);
      expect(again.userVersion, 1);
      expect(
        again.select("select name from sqlite_master where name = 'b'"),
        isEmpty,
      );
      again.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('표를 다시 만드는 동안 외래 키를 꺼 자식 행이 지워지지 않는다', () {
    // 2026-10-02 단계 3 위험 검토. 켠 채로 옛 표를 지우면 그 행을 가리키는 결제가 함께 지워진다
    final dir = Directory.systemTemp.createTempSync('cherry');
    try {
      final path = '${dir.path}/cherry.db';
      const first =
          'create table p (id integer primary key) strict; '
          'create table c (p integer references p (id) on delete cascade) strict; '
          'insert into p values (1); insert into c values (1)';
      openDb(path, [first]).close();
      final db = openDb(path, [
        first,
        'create table p2 (id integer primary key, n integer) strict; '
            'insert into p2 select id, 0 from p; drop table p; alter table p2 rename to p',
      ]);
      expect(db.select('select * from c'), hasLength(1));
      expect(db.select('pragma foreign_keys').first.values.first, 1);
      db.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('틀린 금액과 취소액과 칸 값을 DB가 막는다', () {
    // 서버의 CHECK 제약 그대로다. 화면이 실수해도 DB가 막는다. 설계 4절 "값의 모양"
    final db = openDb();
    card(db, 'u1');
    pay(db, {'cancelled_amount': 10000, 'cancelled_at': 1});
    for (final bad in <Map<String, Object?>>[
      {'amount': 0},
      {'amount': -1000},
      {'amount': '1만원'},
      {'cancelled_amount': 10001, 'cancelled_at': 1},
      {'cancelled_amount': -1, 'cancelled_at': 1},
      {'cancelled_amount': 5000},
      {'installment_months': 0},
      {'channel': 'store'},
      {'region': 'mars'},
      {'source': 'server'},
      {'interest_free_installment': 2},
      {'time_known': 2},
      {'from_recommendation': 2},
      {'revision_from': '2026/09/01'},
      {'user_card_id': 'nobody'},
    ]) {
      expect(
        () => pay(db, bad),
        throwsA(isA<SqliteException>()),
        reason: '$bad',
      );
    }
    expect(
      () => db.execute(
        "insert into transaction_benefits values (?, 'm', -1, 0, 0)",
        [db.select('select id from transactions').first['id']],
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('test_same_card_twice_is_refused', () {
    // E21. 가족카드도 같은 카드 한 장이다
    final db = openDb();
    card(db, 'u1');
    expect(() => card(db, 'u2'), throwsA(isA<SqliteException>()));
    card(db, 'u3', cardId: 'kb-toktok');
  });

  test('test_removed_card_can_be_added_again', () {
    final db = openDb();
    card(db, 'u1', removedAt: 5);
    card(db, 'u2');
    expect(db.select('select * from user_cards'), hasLength(2));
  });

  test('같은 카드의 같은 승인번호는 한 번만 들어가고 지운 결제는 다시 넣는다', () {
    // E31
    final db = openDb();
    card(db, 'u1');
    pay(db, {'approval_no': '12345678', 'deleted_at': 9});
    pay(db, {'approval_no': '12345678'});
    expect(
      () => pay(db, {'approval_no': '12345678'}),
      throwsA(isA<SqliteException>()),
    );
  });

  test('보유 카드를 지우면 결제와 혜택과 답이 함께 지워진다', () {
    final db = openDb();
    card(db, 'u1');
    pay(db, {'id': 't1'});
    db.execute(
      "insert into transaction_benefits values ('t1', 'm', 100, 100, 1000)",
    );
    db.execute(
      "insert into user_card_options (user_card_id, option_key, choice_key, effective_from, answered_at) "
      "values ('u1', 'mode', 'auto', '0001-01-01', 0)",
    );
    db.execute('delete from user_cards');
    for (final t in [
      'transactions',
      'transaction_benefits',
      'user_card_options',
    ]) {
      expect(db.select('select * from $t'), isEmpty, reason: t);
    }
  });

  test('표 칸 이름에 카드번호처럼 보이는 것이 없다', () {
    // 의도 성공 기준 8. 서버 test_no_request_field_looks_like_a_card_number의 규칙을 표 칸에 쓴다. 설계 4절 "시험"
    final db = openDb();
    final looks = RegExp(
      r'card_?(no|num)|number|^pan$|cvc|cvv|expir|last_?4|digits',
      caseSensitive: false,
    );
    final names = {
      for (final t in tablesIn(db))
        for (final c in db.select('pragma table_info($t)')) c['name'] as String,
    };
    expect(names, containsAll(['user_card_id', 'approval_no']));
    expect([
      for (final n in names)
        if (looks.hasMatch(n)) n,
    ], isEmpty);
  });

  test('결제 id는 시각 순서 uuid다', () {
    // RFC 9562의 7판. 엔진은 같은 시각의 결제를 id 순서로 세워 먼저 넣은 결제가 하루 1회 한도를 쓴다. 설계 4절
    final shape = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final t = DateTime.utc(2026, 9, 15, 12);
    final ids = [
      for (var i = 0; i < 50; i++) newId(t.add(Duration(milliseconds: i))),
    ];
    expect(ids.every(shape.hasMatch), isTrue);
    expect([...ids]..sort(), ids);
    expect(ids.toSet(), hasLength(50));
    // 앞 48비트가 UTC 밀리초다
    // 다른 시험이 앞서 큰 id를 만들어도 기대지 않게 먼 미래로 본다
    final later = DateTime.utc(2200);
    final ms = later.millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    expect(newId(later).replaceAll('-', '').substring(0, 12), ms);
    // 시계가 멈춰 있어도 뒤에 만든 id가 크다. 같은 시각의 결제가 넣은 순서대로 선다
    final stuck = [for (var i = 0; i < 50; i++) newId(later)];
    expect([...stuck]..sort(), stuck);
  });

  test('다시 연 DB의 새 결제 id는 저장된 id보다 크다', () {
    // 2026-10-02 위험 검토. 앱을 다시 켜면 앞 id를 잊었다. 시계가 앞서던 폰에서 가져온 2100년 id가 있어도 새 id가 크다
    final dir = Directory.systemTemp.createTempSync('cherry');
    try {
      final path = '${dir.path}/cherry.db';
      final db = openDb(path);
      card(db, 'u1');
      final future = DateTime.utc(
        2100,
      ).millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
      final stored =
          '${future.substring(0, 8)}-${future.substring(8)}-7000-8000-000000000000';
      pay(db, {'id': stored});
      db.close();
      forgetIds();
      openDb(path).close();
      expect(
        newId(DateTime.utc(2026, 9, 15)).compareTo(stored),
        greaterThan(0),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
