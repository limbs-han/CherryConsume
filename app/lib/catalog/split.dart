/// 목록 파일과 카드별 규칙 파일을 폰 DB에 두고 쓸 목록을 고른다. 작업 014 설계 2절
///
/// 실행 중에는 규칙을 `catalog_card_files` 표에서만 읽는다. 저장소와 엔진이 동기 함수라 앱에 담긴 파일을 그 자리에서
/// 읽을 수 없어서다. 앱에 담긴 규칙 파일은 앱 판이 바뀐 뒤 처음 켤 때 한 번 표로 옮긴다
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../engine/engine.dart';
import 'cache.dart';
import 'models.dart';

/// 규칙 파일 글자의 지문. 목록 파일의 `file_sha256`이다
String fileSha(String body) => sha256.convert(utf8.encode(body)).toString();

/// 앱 판마다 한 번, 담긴 목록이 가리키는 규칙 파일을 표로 옮긴다. 글자만 옮기고 해석하지 않는다. 지문이 목록과 다른
/// 파일은 옮기지 않는다. 그런 판은 켤 때 담긴 목록을 쓰지 못한다. 작업 014 단계 5의 시험이 커밋된 파일의 지문을 모두
/// 확인한다
Future<void> copyBundled(
  Database db,
  String index,
  Future<String> Function(String cardId) read,
) async {
  final mark = bundledMark(index);
  final done = db.select(
    "select value from app_state where key = 'bundled_catalog'",
  );
  if (done.isNotEmpty && done.first['value'] == mark) return;
  final have = {
    for (final r in db.select('select card_id, sha256 from catalog_card_files'))
      '${r['card_id']} ${r['sha256']}',
  };
  final want = [
    for (final c in (jsonDecode(index) as Json)['cards'] as List)
      if (!have.contains('${c['id']} ${c['file_sha256']}'))
        (id: c['id'] as String, sha: c['file_sha256'] as String),
  ];
  final bodies = await Future.wait([for (final w in want) read(w.id)]);
  db.execute('begin immediate');
  try {
    for (final (i, w) in want.indexed) {
      saveCardFile(db, w.id, w.sha, bodies[i]);
    }
    db.execute(
      "insert into app_state (key, value) values ('bundled_catalog', ?) "
      'on conflict (key) do update set value = excluded.value',
      [mark],
    );
    db.execute('commit');
  } catch (_) {
    if (!db.autocommit) db.execute('rollback');
    rethrow;
  }
}

/// 규칙 파일 하나를 넣는다. 글자의 지문이 sha가 아니면 넣지 않고 false다. 한 번 들어간 줄은 그 지문의 본문으로 굳는다.
/// 단계 3 위험 검토 낮음 5
bool saveCardFile(Database db, String id, String sha, String body) {
  if (fileSha(body) != sha) return false;
  db.execute(
    'insert or ignore into catalog_card_files (card_id, sha256, body) '
    'values (?, ?, ?)',
    [id, sha, body],
  );
  return true;
}

/// 목록의 모든 카드 규칙 파일이 표에 있는가. 없는 카드를 등록하거나 그 카드가 든 기록을 가져오면 그 뒤 홈이 계산하지
/// 못한다. 해석하지 않고 지문만 본다. 단계 3 위험 검토 중간 1, 2
bool _complete(Database db, Json index) {
  final have = {
    for (final r in db.select('select card_id, sha256 from catalog_card_files'))
      '${r['card_id']} ${r['sha256']}',
  };
  return (index['cards'] as List).every(
    (c) => have.contains('${c['id']} ${c['file_sha256']}'),
  );
}

/// 표의 규칙 파일 하나. 없거나, 앱이 정확히 계산하지 못하는 수가 있거나, 그 카드 파일이 아니면 던진다
CardRules loadCardFile(Database db, String id, String sha) {
  final rows = db.select(
    'select body from catalog_card_files where card_id = ? and sha256 = ?',
    [id, sha],
  );
  if (rows.isEmpty) throw FormatException('$id의 규칙 파일이 없다');
  final json = jsonDecode(rows.first['body'] as String);
  if (numberErrors(json).isNotEmpty) {
    throw FormatException('$id의 규칙 파일에 앱이 담지 못하는 수가 있다');
  }
  return CardRules.fromFile(json as Json, id);
}

Catalog _index(Database db, String body) => Catalog.fromIndex(
  jsonDecode(body) as Json,
  (id, sha) => loadCardFile(db, id, sha),
);

/// 쓸 수 있는 목록. 끝까지 읽히고, 모든 카드의 규칙 파일이 표에 있고, 보유 카드와 결제가 쓰는 카드, 가맹점, 업종,
/// 결제수단이 있고, 보유 카드의 규칙 파일이 읽혀야 한다. 아니면 null이다
Catalog? readIndex(Database db, String body, InUse inUse) {
  try {
    final json = jsonDecode(body);
    if (numberErrors(json).isNotEmpty || !_complete(db, json as Json)) {
      return null;
    }
    final cat = _index(db, body);
    Engine(cat);
    final ok =
        cat.cards.keys.toSet().containsAll(inUse.cards) &&
        cat.merchants.keys.toSet().containsAll(inUse.merchants) &&
        cat.categories.containsAll(inUse.categories) &&
        cat.paymentMethods.keys.toSet().containsAll(inUse.methods);
    if (!ok) return null;
    for (final id in inUse.cards) {
      cat.cards[id]!.revisions;
    }
    return cat;
  } catch (_) {
    return null;
  }
}

/// 켤 때 쓸 목록. 지금 `chooseCatalog`와 같은 차례로 고른다. 담긴 판이 받을 때와 같으면 받아 둔 것을, 다르면 담긴
/// 것을 먼저 본다. 둘 다 못 쓰면 담긴 목록을 쓰되, 그 규칙 파일이 표에 다 없으면 던져 켜기 화면이 "기록을 열지
/// 못했어요"를 보인다. 옛 한 벌 카탈로그가 켤 때 깨지던 것과 같은 자리다. 고른 뒤 쓰지 않는 규칙 파일 줄을 지운다
Catalog chooseIndex(Database db, String bundled, InUse inUse) {
  final cached = cachedCatalog(db);
  Catalog? cat;
  if (cached != null) {
    final sameApp = cached.bundled == bundledMark(bundled);
    Catalog? fromCache() {
      final c = readIndex(db, cached.body, inUse);
      // 읽히지 않는 받아 둔 것은 지운다. 옛 판이 받은 한 벌 카탈로그도 여기서 지워진다
      if (c == null && readIndex(db, cached.body, nothing) == null) {
        db.execute('delete from catalog_cache');
      }
      return c;
    }

    Catalog? fromApp() {
      final c = readIndex(db, bundled, inUse);
      if (c != null && !sameApp) db.execute('delete from catalog_cache');
      return c;
    }

    cat = sameApp ? fromCache() ?? fromApp() : fromApp() ?? fromCache();
  }
  dropUnusedFiles(db, bundled);
  if (cat != null) return cat;
  if (!_complete(db, jsonDecode(bundled) as Json)) {
    throw StateError('앱에 담긴 카드 규칙 파일이 표에 다 없다');
  }
  return _index(db, bundled);
}

/// 받는 중인 목록. 받기가 규칙 파일을 받기 전에 적고 다 받으면 받아 둔 목록으로 옮긴다. 켤 때 이 목록이 가리키는
/// 파일도 남겨 다음 받기가 이어 받는다. 단계 3 위험 검토 중간 3
const pendingKey = 'pending_catalog';

/// 담긴 목록, 받아 둔 목록, 받는 중인 목록이 가리키지 않는 규칙 파일 줄을 한 트랜잭션에서 지운다. 켤 때만 부른다.
/// 실행 중에 부르면 지금 쓰는 목록의 파일을 지울 수 있다
void dropUnusedFiles(Database db, String bundled) {
  Set<String> pointed(String body) {
    try {
      return {
        for (final c in (jsonDecode(body) as Json)['cards'] as List)
          '${c['id']} ${c['file_sha256']}',
      };
    } catch (_) {
      return const {};
    }
  }

  final pending = db.select('select value from app_state where key = ?', [
    pendingKey,
  ]);
  final keep = {
    ...pointed(bundled),
    if (cachedCatalog(db) case final c?) ...pointed(c.body),
    if (pending.isNotEmpty) ...pointed(pending.first['value'] as String),
  };
  final gone = [
    for (final r in db.select('select card_id, sha256 from catalog_card_files'))
      if (!keep.contains('${r['card_id']} ${r['sha256']}'))
        [r['card_id'], r['sha256']],
  ];
  if (gone.isEmpty) return;
  // 1,500장의 지문이 모두 바뀐 판이면 줄마다 따로 커밋해 첫 화면이 늦지 않게 한 번에 지운다. 단계 3 위험 검토 중간 4
  db.execute('begin immediate');
  try {
    final del = db.prepare(
      'delete from catalog_card_files where card_id = ? and sha256 = ?',
    );
    for (final g in gone) {
      del.execute(g);
    }
    del.close();
    db.execute('commit');
  } catch (_) {
    if (!db.autocommit) db.execute('rollback');
    rethrow;
  }
}
