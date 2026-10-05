/// 폰 안 저장소. 서버의 `app.state`와 요청마다 받던 DB 연결을 한데 둔다. 작업 006 설계 4절
///
/// `store/`의 다른 파일은 서버 파일 나눔대로 옮긴 함수다. 함수 이름도 같다. 쓰기 하나는 트랜잭션 하나다
library;

import 'package:sqlite3/sqlite3.dart';

import '../catalog/cache.dart' show InUse;
import '../catalog/models.dart';
import '../engine/cond.dart';
import '../engine/engine.dart';
import 'payments.dart';

class Store {
  Store(this.db, this.catalog, {DateTime Function()? clock})
    : engine = Engine(catalog),
      clock = clock ?? DateTime.now;

  final Database db;
  final Catalog catalog;
  final Engine engine;

  /// 지금 시각. 시험은 서버 시험처럼 2026-09-15 21:00 한국 시간 시계를 넣는다
  final DateTime Function() clock;

  /// 한국 시간의 오늘. 달 경계는 한국 시간이다. 서버 `deps.py`의 today. E7
  DateTime today() => localDay(clock());

  /// 가게 이름 별칭에서 가맹점으로. 서버 `main.py`의 app.state.aliases
  late final MerchantIndex aliases = aliasIndex(catalog);

  /// 업종 code에서 이름으로. 자식 업종은 부모 code를 붙인 code다
  late final Map<String, String> categoryNames = {
    for (final c in catalog.categoryTree) ...{
      c.code: c.name,
      for (final ch in c.children) '${c.code}.${ch.code}': ch.name,
    },
  };
}

/// 쓰기 하나를 트랜잭션 하나로. 중간에 실패하면 모두 되돌린다. 안에 await가 없어 다른 쓰기가 끼어들지 않는다. 설계 4절
T write<T>(Store s, T Function() f) {
  s.db.execute('begin immediate');
  try {
    final out = f();
    s.db.execute('commit');
    return out;
  } catch (_) {
    if (!s.db.autocommit) s.db.execute('rollback');
    rethrow;
  }
}

/// UTC 밀리초 정수와 시각. DB의 시각 칸은 이 모양이다. 설계 4절 "값의 모양"
int ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime fromMs(int x) => DateTime.fromMillisecondsSinceEpoch(x, isUtc: true);

/// 행을 고칠 수 있는 Map으로. 서버의 dict 행처럼 답을 붙인다
Map<String, Object?> rowMap(Row r) => Map<String, Object?>.of(r);

final _timeShape = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(Z|[+-]\d{2}:?\d{2})$',
);
final _dayShape = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool _realDay(int y, int m, int d) {
  final t = DateTime.utc(y, m, d);
  return t.year == y && t.month == m && t.day == d;
}

/// 시간대가 붙은 ISO 시각. 서버 Pydantic의 AwareDatetime이다. 모양이 틀렸거나 시간대가 없거나 없는 날과 시각이면
/// null이다. DateTime.parse는 9월 31일을 10월 1일로 넘기고 시간대가 없으면 폰의 현지 시각으로 읽는다. 2026-10-02 위험 검토
DateTime? awareTime(Object? v) {
  final m = v is String ? _timeShape.firstMatch(v) : null;
  if (m == null) return null;
  int at(int i) => int.parse(m.group(i) ?? '0');
  if (at(4) > 23 ||
      at(5) > 59 ||
      at(6) > 59 ||
      !_realDay(at(1), at(2), at(3))) {
    return null;
  }
  return DateTime.parse(v as String).toUtc();
}

/// YYYY-MM-DD 날짜. 없는 날이면 null이다. 2026-02-30을 3월 2일로 넘기지 않는다
DateTime? strictDay(Object? v) {
  final m = v is String ? _dayShape.firstMatch(v) : null;
  if (m == null) return null;
  final [y, mo, d] = [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  return _realDay(y, mo, d) ? DateTime.utc(y, mo, d) : null;
}

/// 보유 카드와 결제가 쓰는 카드, 가맹점, 업종, 결제수단. 해지한 카드와 지운 결제도 넣는다. 기록과 사람 사실 답하기가
/// 해지한 카드 이름을 카탈로그에서 읽고, 옛 결제를 고칠 때 그 결제수단을 카탈로그에서 찾는다. 받은 카탈로그와 담긴 카탈로그에 이것이 다 있어야 쓴다. 작업 006 설계 2절, 4절
InUse inUse(Database db) => (
  cards: {
    for (final r in db.select('select distinct card_id from user_cards'))
      r['card_id'] as String,
  },
  merchants: {
    for (final r in db.select(
      'select distinct merchant_key from transactions where merchant_key is not null',
    ))
      r['merchant_key'] as String,
  },
  categories: {
    for (final r in db.select(
      'select distinct category_code from transactions where category_code is not null',
    ))
      r['category_code'] as String,
  },
  methods: {
    for (final r in db.select(
      'select payment_method as m from transactions where payment_method is not null '
      'union select last_payment_method from user_cards where last_payment_method is not null',
    ))
      r['m'] as String,
  },
);
