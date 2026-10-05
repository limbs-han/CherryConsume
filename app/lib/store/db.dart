/// 폰 안 DB. 작업 006 설계 4절 "열 때"
///
/// 표 정의는 번호 붙은 SQL 목록이고 `PRAGMA user_version`에 돌린 번호를 적는다. 열 때마다 남은 것을 한 트랜잭션에서
/// 돌린다. 이미 낸 번호의 SQL은 고치지 않고 새 번호로 더한다
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart';

const migrations = <String>[
  // 1. 받아 둔 카탈로그 한 줄과 ETag, 받을 때 앱에 담긴 파일의 지문. 설계 2절
  '''
  create table catalog_cache (
    id integer primary key check (id = 1),
    body text not null,
    etag text,
    bundled text not null
  )''',
  // 2. 사용자 표. 서버 마이그레이션 001~007에서 사용자, 로그인, 세션, 카탈로그, 추천 표와 user_id, card_revision_id,
  // recommendation_request_id, client_id를 뺐다. 결제에 개정 시행일과 지문, 추천에서 기록함 표시를 더했다. 설계 4절
  // 시각은 UTC 밀리초 정수, 날짜는 YYYY-MM-DD 글자, 참과 거짓은 0과 1이다. strict 표라 칸 타입이 틀린 값도 막는다
  '''
  create table user_cards (
    id text primary key,
    card_id text not null,
    nickname text,
    assumed_prev_month_spend integer check (assumed_prev_month_spend >= 0),
    started_on text check (started_on glob $_date),
    last_payment_method text,
    added_at integer not null,
    removed_at integer
  ) strict;
  -- 같은 카드를 두 장 가지지 않는다. 가족카드도 한 장이다. E21
  create unique index user_cards_one_active on user_cards (card_id) where removed_at is null;

  -- 가져오기 한 번이 한 행이다. 묶음 단위로 되돌린다. 파일 이름은 남기지 않는다. E34
  create table import_batches (
    id integer primary key,
    source text,
    row_count integer not null check (row_count >= 0),
    imported_count integer not null check (imported_count >= 0),
    duplicate_count integer not null check (duplicate_count >= 0),
    cancel_count integer not null check (cancel_count >= 0),
    created_at integer not null,
    undone_at integer
  ) strict;

  create table transactions (
    id text primary key,
    user_card_id text not null references user_cards (id) on delete cascade,
    amount integer not null check (amount > 0),
    merchant_name text,
    merchant_key text,
    category_code text,
    paid_at integer not null,
    installment_months integer not null default 1 check (installment_months >= 1),
    interest_free_installment integer not null default 0 check (interest_free_installment in (0, 1)),
    cancelled_amount integer not null default 0 check (cancelled_amount >= 0 and cancelled_amount <= amount),
    cancelled_at integer,
    channel text not null default 'offline' check (channel in ('online', 'offline')),
    region text not null default 'domestic' check (region in ('domestic', 'overseas')),
    payment_method text,
    billing text,
    -- 계산에 쓴 개정의 시행일과 규칙 지문. 개정 표는 두지 않는다. E18
    revision_from text check (revision_from glob $_date),
    revision_sha text,
    approval_no text,
    import_batch_id integer references import_batches (id),
    source text not null default 'manual' check (source in ('manual', 'excel', 'notification')),
    from_recommendation integer not null default 0 check (from_recommendation in (0, 1)),
    -- 엑셀에 날짜만 있으면 그날 12시로 두고 시각을 모른다고 적는다. E57
    time_known integer not null default 1 check (time_known in (0, 1)),
    created_at integer not null,
    updated_at integer not null,
    deleted_at integer,
    check (cancelled_amount = 0 or cancelled_at is not null)
  ) strict;
  -- 실적과 한도는 카드마다 결제 시각 순서로 읽는다. 최근 간 가게는 결제를 최근 순으로 읽는다
  create index transactions_card_time on transactions (user_card_id, paid_at);
  create index transactions_time on transactions (paid_at);
  create index transactions_import_batch on transactions (import_batch_id) where import_batch_id is not null;
  -- 같은 카드의 같은 승인번호는 한 번만 들어간다. 지운 결제는 다시 넣을 수 있다. E31
  create unique index transactions_card_approval on transactions (user_card_id, approval_no)
    where approval_no is not null and deleted_at is null;

  -- 저장한 혜택은 다시 계산하지 않는다. E18
  create table transaction_benefits (
    transaction_id text not null references transactions (id) on delete cascade,
    benefit_key text not null,
    amount integer not null check (amount >= 0),
    value integer not null check (value >= 0),
    base_amount integer not null check (base_amount >= 0),
    primary key (transaction_id, benefit_key)
  ) strict;

  -- 답마다 바꾼 날을 남긴다. 처음 답은 0001-01-01부터다. E56
  create table user_card_options (
    id integer primary key,
    user_card_id text not null references user_cards (id) on delete cascade,
    option_key text not null,
    choice_key text not null,
    effective_from text not null check (effective_from glob $_date),
    answered_at integer not null,
    unique (user_card_id, option_key, effective_from)
  ) strict;
  -- 사람 사실. 생일 달, 현역병 여부처럼 모든 카드에 쓴다
  create table user_facts (
    key text not null,
    effective_from text not null check (effective_from glob $_date),
    value text not null,
    answered_at integer not null,
    primary key (key, effective_from)
  ) strict;
  -- 카드 사실. 급여이체, 마이태그 등록처럼 그 카드에만 쓴다
  create table user_card_facts (
    user_card_id text not null references user_cards (id) on delete cascade,
    key text not null,
    effective_from text not null check (effective_from glob $_date),
    value text not null,
    answered_at integer not null,
    primary key (user_card_id, key, effective_from)
  ) strict;

  -- 가져오기가 붙인 취소 한 줄마다 한 행이다. E32, E34
  create table import_cancels (
    id integer primary key,
    import_batch_id integer not null references import_batches (id) on delete cascade,
    transaction_id text not null references transactions (id) on delete cascade,
    amount integer not null check (amount > 0),
    cancelled_at integer not null
  ) strict;
  create index import_cancels_transaction on import_cancels (transaction_id);

  -- 사용자가 짝지은 열. 머리 줄 모양의 해시마다 하나다. 열 이름 대신 열 번호만 남긴다. E30
  create table import_mappings (
    signature text primary key,
    mapping text not null,
    updated_at integer not null
  ) strict''',
  // 3. 앱 상태. 기록이 아니라 기록 내보내기 파일에 넣지 않고 기록을 가져와도 그대로 둔다. 마지막으로 내보낸 날을 둔다.
  // 작업 012 설계 4.2
  '''
  create table app_state (
    key text primary key,
    value text not null
  ) strict''',
  // 4. 카드 규칙 파일. 지문마다 한 줄이다. 앱에 담긴 파일과 받은 파일이 같은 표에 든다. 실행 중에는 이 표에서만 규칙을
  // 읽는다. 작업 014 설계 2절
  '''
  create table catalog_card_files (
    card_id text not null,
    sha256 text not null,
    body text not null,
    primary key (card_id, sha256)
  ) strict''',
  // 5. 사용자가 고른 가게 이름별 업종. 같은 이름의 다음 결제에 카탈로그 가맹점의 업종보다 먼저 쓴다. 기록이라 기록
  // 내보내기 파일에 든다. 작업 016 설계 3절
  '''
  create table merchant_categories (
    name_key text primary key,
    category_code text not null,
    updated_at integer not null
  ) strict''',
];

/// 날짜 칸의 모양. YYYY-MM-DD 글자라 글자 순서가 날짜 순서와 같다
const _date = "'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'";

/// path가 없으면 메모리 DB다. steps는 시험이 실패하는 SQL을 넣어 볼 때만 준다
Database openDb([String? path, List<String> steps = migrations]) {
  final db = path == null ? sqlite3.openInMemory() : sqlite3.open(path);
  // 깨진 파일이나 다른 연결의 쓰기 잠금으로 어디서 던져도 DB를 연 채 남기지 않는다
  try {
    final from = db.userVersion;
    if (from > steps.length) {
      throw StateError('앱보다 새 판이 만든 DB다. 표 번호 $from');
    }
    if (from < steps.length) {
      // SQLite 권장 순서. 외래 키는 트랜잭션 안에서 끌 수 없어, 표를 다시 만드는 SQL이 옛 표를 지울 때 걸리지 않게
      // 끄고 돌린 뒤 커밋 전에 어긋난 것이 없는지 본다
      db.execute('pragma foreign_keys = off');
      db.execute('begin immediate');
      try {
        for (final sql in steps.skip(from)) {
          db.execute(sql);
        }
        if (db.select('pragma foreign_key_check').isNotEmpty) {
          throw StateError('표를 바꾼 뒤 외래 키가 어긋났다');
        }
        db.userVersion = steps.length;
        db.execute('commit');
      } catch (_) {
        // 디스크가 가득 차면 SQLite가 이미 되돌렸을 수 있다
        if (!db.autocommit) db.execute('rollback');
        rethrow;
      }
    }
    // SQLite는 외래 키 검사가 기본으로 꺼져 있다
    db.execute('pragma foreign_keys = on');
    seenIds(db);
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

final _random = Random.secure();

/// 시각 순서 uuid. RFC 9562의 7판. 서버 `payments.py`의 new_id를 옮겼다. 엔진은 같은 시각의 결제를 id 순서로 세워
/// 먼저 넣은 결제가 앞이 된다. 설계 4절
///
/// 같은 밀리초에 둘을 만들거나 시계가 멈춰 있어도 앞 id보다 크게 만든다. 앞 id의 밀리초에 1을 더한다. 서버는 밀리초가
/// 같으면 순서가 무작위였다. 2026-10-02 시험 시계로 같은 시각 결제를 넣다가 찾았다
String newId(DateTime now) {
  String hex(int x, int len) => x.toRadixString(16).padLeft(len, '0');
  String rand(int len) =>
      [for (var i = 0; i < len; i++) hex(_random.nextInt(16), 1)].join();
  final t = now.millisecondsSinceEpoch;
  _lastMs = t > _lastMs ? t : _lastMs + 1;
  final ms = hex(_lastMs, 12);
  final variant = hex(8 + _random.nextInt(4), 1);
  return '${ms.substring(0, 8)}-${ms.substring(8)}-7${rand(3)}-$variant${rand(3)}-${rand(12)}';
}

var _lastMs = 0;

/// 앱을 다시 켠 것처럼 앞 id를 잊는다
@visibleForTesting
void forgetIds() => _lastMs = 0;

/// 저장된 가장 큰 결제 id의 밀리초를 기억한다. 앱을 다시 켠 뒤에도 새 id가 저장된 id보다 크다. 폰 시계가 뒤로 갔거나
/// 시계가 앞서던 폰에서 가져온 기록이 있어도 같은 시각 결제의 순서가 뒤집히지 않는다. 2026-10-02 위험 검토
void seenIds(Database db) {
  final has = db.select(
    "select 1 from sqlite_master where type = 'table' and name = 'transactions'",
  );
  if (has.isEmpty) return;
  final top = db.select('select max(id) as m from transactions').first['m'];
  final ms = top is String
      ? int.tryParse(
          top.replaceAll('-', '').padRight(12).substring(0, 12),
          radix: 16,
        )
      : null;
  if (ms != null && ms > _lastMs) _lastMs = ms;
}
