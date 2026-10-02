/// 쓸 카탈로그 고르기와 받아 둔 카탈로그 한 줄. 작업 006 설계 2절 "내려받기"
///
/// 받아 둔 것이 있으면 그것을, 없으면 앱에 담긴 것을 쓴다. 받을 때 담긴 파일의 지문을 함께 적고, 켤 때 담긴 파일이
/// 그때와 다르면 앱이 새 판이라 담긴 것을 먼저 본다. 어느 쪽이든 끝까지 읽히고 보유 카드와 저장한 결제의 카드,
/// 가맹점, 업종이 다 있어야 쓴다. 규칙 검사는 Python이 JSON을 만들 때 했고 커밋 훅이 맞춰 본다. 설계 3절
library;

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../engine/engine.dart';
import '../engine/frac.dart';
import 'models.dart';

/// 보유 카드의 카드 id, 저장한 결제의 가맹점과 업종. 카탈로그에 하나라도 없으면 그 카탈로그를 쓰지 않는다. 설계 4절
typedef InUse = ({
  Set<String> cards,
  Set<String> merchants,
  Set<String> categories,
});

/// Python `app_json.py`의 MAX_DENOMINATOR, MAX_DECIMAL, MAX_INTEGER와 같다. 앱 엔진은 64비트 정수 분수로 계산한다
const maxDenominator = 10000;
const maxDecimal = 100000;
const maxInteger = 1000000000000;

/// 앱이 정확히 계산하지 못하는 수의 자리. 소수 넷째 자리를 넘거나 10만 이상인 소수, 1조 이상인 정수면 분수가 넘쳐
/// 조용히 틀린다
List<String> numberErrors(Object? json, [String path = '']) => switch (json) {
  final double x
      when x.abs() >= maxDecimal ||
          Frac.parse(x.toString()).d > maxDenominator =>
    ['$path: $x'],
  final int x when x.abs() >= maxInteger => ['$path: $x'],
  final Map m => [
    for (final MapEntry(:key, :value) in m.entries)
      ...numberErrors(value, path.isEmpty ? '$key' : '$path.$key'),
  ],
  final List l => [
    for (final (i, v) in l.indexed) ...numberErrors(v, '$path[$i]'),
  ],
  _ => const [],
};

/// 쓸 수 있는 카탈로그. 읽히지 않거나 앱이 쓰는 것이 빠졌으면 null이다
Catalog? _read(String body, InUse inUse) {
  try {
    final json = jsonDecode(body);
    if (numberErrors(json).isNotEmpty) return null;
    final cat = Catalog.fromJson(json as Json);
    Engine(cat);
    final ok =
        cat.cards.keys.toSet().containsAll(inUse.cards) &&
        cat.merchants.keys.toSet().containsAll(inUse.merchants) &&
        cat.categories.containsAll(inUse.categories);
    return ok ? cat : null;
  } catch (_) {
    return null;
  }
}

bool usable(String body, InUse inUse) => _read(body, inUse) != null;

/// 담긴 파일의 지문. 64비트 FNV-1a다. 폰 int는 64비트라 곱이 넘치면 그대로 접힌다
String bundledMark(String text) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(text)) {
    h = (h ^ b) * 0x100000001b3;
  }
  // int는 부호가 있어 위아래 32비트로 나눠 적는다
  String hex(int x) => x.toRadixString(16).padLeft(8, '0');
  return hex(h >>> 32) + hex(h & 0xffffffff);
}

/// 받아 둔 한 줄
({String body, String? etag, String bundled})? cachedCatalog(Database db) {
  final rows = db.select('select body, etag, bundled from catalog_cache');
  if (rows.isEmpty) return null;
  final r = rows.first;
  return (
    body: r['body'] as String,
    etag: r['etag'] as String?,
    bundled: r['bundled'] as String,
  );
}

/// 켤 때 쓸 카탈로그. 담긴 파일이 받을 때와 같으면 받아 둔 것을, 다르면 담긴 것을 먼저 본다.
/// 먼저 본 것을 쓸 수 없으면 다른 것을 쓴다. 둘 다 쓸 수 없으면 담긴 것을 쓴다
Catalog chooseCatalog(Database db, String bundled, InUse inUse) {
  final cached = cachedCatalog(db);
  if (cached == null) return Catalog.fromJson(jsonDecode(bundled) as Json);
  final sameApp = cached.bundled == bundledMark(bundled);
  Catalog? fromCache() {
    final cat = _read(cached.body, inUse);
    // 읽히지 않는 받아 둔 것은 지운다. 모델이 바뀐 새 판에서 생길 수 있다
    if (cat == null && _read(cached.body, nothing) == null) {
      db.execute('delete from catalog_cache');
    }
    return cat;
  }

  Catalog? fromApp() {
    final cat = _read(bundled, inUse);
    if (cat != null && !sameApp) db.execute('delete from catalog_cache');
    return cat;
  }

  return (sameApp ? fromCache() ?? fromApp() : fromApp() ?? fromCache()) ??
      Catalog.fromJson(jsonDecode(bundled) as Json);
}

const nothing = (
  cards: <String>{},
  merchants: <String>{},
  categories: <String>{},
);

/// 받은 카탈로그를 둔다. 다음에 앱을 켤 때부터 쓴다
void saveCatalog(Database db, String body, String? etag, String bundled) =>
    db.execute(
      'insert into catalog_cache (id, body, etag, bundled) values (1, ?, ?, ?) '
      'on conflict (id) do update set '
      'body = excluded.body, etag = excluded.etag, bundled = excluded.bundled',
      [body, etag, bundledMark(bundled)],
    );
