/// 카탈로그 받기. 앱에서 네트워크를 부르는 곳은 여기 하나뿐이다. 작업 006 설계 2절 "내려받기", 의도 성공 기준 4
///
/// 공개 저장소의 `catalog.json`을 지난번 ETag와 함께 받는다. 같으면 GitHub이 몸통 없이 304로 답한다. 받은 파일은
/// 끝까지 읽히고 앱이 쓰는 카드, 가맹점, 업종, 결제수단이 모두 있어야 두고, 다음에 켤 때부터 쓴다. 보내는 것은 없다
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

import 'cache.dart';
import 'models.dart';
import 'split.dart';

const catalogUrl =
    'https://raw.githubusercontent.com/limbs-han/CherryConsume/master/app/assets/catalog.json';
const maxBytes = 5 * 1024 * 1024;

enum Refresh { saved, notModified, rejected, failed }

class _TooBig implements Exception {}

/// 목록 파일과 규칙 파일 주소. 작업 014 설계 1절, 3절
const catalogBase =
    'https://raw.githubusercontent.com/limbs-han/CherryConsume/master/app/assets/catalog/';
const indexUrl = '${catalogBase}index.json';
const cardsUrl = '${catalogBase}cards/';

/// 규칙 파일 하나의 상한과 한 번 받기에서 규칙 파일을 모두 합친 상한
const maxCardBytes = 1024 * 1024;
const maxTotalBytes = 30 * 1024 * 1024;

class _Rejected implements Exception {}

/// 한 번 받기의 합계 상한을 넘었다. 다음 받기가 이어 받는다
class _TooMuch implements Exception {}

/// 규칙 파일 하나가 상한을 넘은 응답의 자리 번호
const _tooBigFile = -1;

/// 받은 규칙 파일 글자. 지문이 맞고, 읽히고, 앱이 정확히 계산하지 못하는 수가 없고, 목록의 개정 머리와 같은 판이어야
/// 한다. 아니면 null이다
String? _valid(Uint8List bytes, String id, String sha, Json head) {
  try {
    final text = utf8.decode(bytes);
    if (fileSha(text) != sha) return null;
    final json = jsonDecode(text);
    if (numberErrors(json).isNotEmpty) return null;
    final rules = CardRules.fromFile(json as Json, id);
    CatalogCard.fromIndex(head, () => rules).revisions;
    return text;
  } catch (_) {
    // 날짜 모양이 틀린 것처럼 어떤 오류든 틀린 파일이다. 단계 4 위험 검토 낮음 3
    return null;
  }
}

/// 한 주소를 받는다. 다른 주소로 넘겨주기를 따라가지 않고, limit를 넘으면 그만둔다. count는 받은 바이트를 센다
Future<(int, Map<String, String>, Uint8List)> _get(
  http.Client c,
  String url,
  int limit,
  Duration timeout, {
  String? etag,
  void Function(int)? count,
}) => () async {
  final req = http.Request('GET', Uri.parse(url))..followRedirects = false;
  if (etag != null) req.headers['If-None-Match'] = etag;
  final res = await c.send(req);
  final buf = BytesBuilder(copy: false);
  await for (final chunk in res.stream) {
    buf.add(chunk);
    count?.call(chunk.length);
    if (buf.length > limit) throw _TooBig();
  }
  return (res.statusCode, res.headers, buf.takeBytes());
}().timeout(timeout);

/// 도는 중인 받기. 둘이 겹치면 먼저 끝난 쪽이 다른 쪽의 받는 중 표시를 지운다. 단계 4 위험 검토 낮음 5
Future<Refresh>? _running;

/// 목록 파일을 받고 표에 없는 규칙 파일을 받는다. 규칙 파일을 받기 전에 받은 목록을 받는 중인 목록으로 적어, 받다 꺼져도
/// 켤 때 받은 파일을 지우지 않고 다음 받기가 이어 받는다. 모든 파일이 들어가면 받아 둔 목록으로 옮긴다. 다음에 켤 때부터
/// 쓴다. 실행 중에는 안 쓰는 파일을 지우지 않는다. 이미 도는 받기가 있으면 그것을 기다린다. 작업 014 설계 3절
///
/// rejected는 받은 것이 틀렸다는 뜻이고 failed는 망이나 상한 때문에 다 받지 못했다는 뜻이다. 둘 다 다음에 켤 때 다시 받는다
Future<Refresh> refreshIndex(
  Database db,
  String bundled,
  InUse inUse, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
  int maxTotal = maxTotalBytes,
}) => _running ??= _refreshIndex(
  db,
  bundled,
  inUse,
  client,
  timeout,
  maxTotal,
).whenComplete(() => _running = null);

Future<Refresh> _refreshIndex(
  Database db,
  String bundled,
  InUse inUse,
  http.Client? client,
  Duration timeout,
  int maxTotal,
) async {
  final c = client ?? http.Client();
  try {
    final (status, headers, bytes) = await _get(
      c,
      indexUrl,
      maxBytes,
      timeout,
      etag: cachedCatalog(db)?.etag,
    );
    if (status == 304) {
      // 받아 둔 것이 저장소와 같다. 받는 중이던 더 새 목록은 저장소에서 사라졌다
      db.execute('delete from app_state where key = ?', [pendingKey]);
      return Refresh.notModified;
    }
    if (status != 200) return Refresh.failed;
    final String body;
    final Json json;
    final Catalog index;
    try {
      body = utf8.decode(bytes);
      json = jsonDecode(body) as Json;
      if (numberErrors(json).isNotEmpty) return Refresh.rejected;
      index = Catalog.fromIndex(json, (_, _) => throw _Rejected());
    } catch (_) {
      // 읽히지 않는 목록은 어떤 오류든 틀린 파일이다. 단계 4 위험 검토 낮음 3
      return Refresh.rejected;
    }
    final ok =
        index.cards.keys.toSet().containsAll(inUse.cards) &&
        index.merchants.keys.toSet().containsAll(inUse.merchants) &&
        index.categories.containsAll(inUse.categories) &&
        index.paymentMethods.keys.toSet().containsAll(inUse.methods);
    if (!ok) return Refresh.rejected;
    db.execute(
      'insert into app_state (key, value) values (?, ?) '
      'on conflict (key) do update set value = excluded.value',
      [pendingKey, body],
    );
    final have = {
      for (final r in db.select(
        'select card_id, sha256 from catalog_card_files',
      ))
        '${r['card_id']} ${r['sha256']}',
    };
    final heads = {
      for (final h in json['cards'] as List) h['id'] as String: h as Json,
    };
    final want = [
      for (final h in heads.values)
        if (!have.contains('${h['id']} ${h['file_sha256']}')) h['id'] as String,
    ];
    var total = 0;
    void count(int n) {
      total += n;
      if (total > maxTotal) throw _TooMuch();
    }

    // 동시에 넷까지 받는다. 한 파일이 시간을 넘기거나 끊기거나 상한을 넘어도 같은 묶음에서 받은 파일은 넣어, 다음 받기가
    // 남은 것만 받게 한다. 단계 4 위험 검토 낮음 1
    Future<(int, Uint8List)?> fetch(String id) async {
      try {
        final (status, _, bytes) = await _get(
          c,
          '$cardsUrl$id.json',
          maxCardBytes,
          timeout,
          count: count,
        );
        return (status, bytes);
      } on _TooBig {
        return (_tooBigFile, Uint8List(0));
      } catch (_) {
        return null;
      }
    }

    for (var i = 0; i < want.length; i += 4) {
      final got = await Future.wait([
        for (final id in want.skip(i).take(4)) fetch(id),
      ]);
      Refresh? bad;
      db.execute('begin immediate');
      try {
        for (final (k, r) in got.indexed) {
          final id = want[i + k], sha = heads[id]!['file_sha256'] as String;
          if (r != null && r.$1 == _tooBigFile) {
            bad ??= Refresh.rejected;
          } else if (r == null || r.$1 != 200) {
            bad ??= Refresh.failed;
          } else if (_valid(r.$2, id, sha, heads[id]!) case final text?) {
            saveCardFile(db, id, sha, text);
          } else {
            bad ??= Refresh.rejected;
          }
        }
        db.execute('commit');
      } catch (_) {
        if (!db.autocommit) db.execute('rollback');
        rethrow;
      }
      if (bad != null) return bad;
    }
    if (readIndex(db, body, inUse) == null) return Refresh.rejected;
    db.execute('begin immediate');
    try {
      saveCatalog(db, body, headers['etag'], bundled);
      db.execute('delete from app_state where key = ?', [pendingKey]);
      db.execute('commit');
    } catch (_) {
      if (!db.autocommit) db.execute('rollback');
      rethrow;
    }
    return Refresh.saved;
  } on _TooBig {
    // 목록이 5MB를 넘었다
    return Refresh.rejected;
  } catch (_) {
    return Refresh.failed;
  } finally {
    if (client == null) c.close();
  }
}

/// 화면을 막지 않게 기다리지 않고 부른다. 실패해도 던지지 않고 가진 것을 그대로 둔다
Future<Refresh> refreshCatalog(
  Database db,
  String bundled,
  InUse inUse, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final c = client ?? http.Client();
  try {
    // https에서 http로 내려가는 넘겨주기를 따라가지 않는다
    final req = http.Request('GET', Uri.parse(catalogUrl))
      ..followRedirects = false;
    final etag = cachedCatalog(db)?.etag;
    if (etag != null) req.headers['If-None-Match'] = etag;
    final (status, headers, bytes) = await () async {
      final res = await c.send(req);
      final buf = BytesBuilder(copy: false);
      await for (final chunk in res.stream) {
        buf.add(chunk);
        if (buf.length > maxBytes) throw _TooBig();
      }
      return (res.statusCode, res.headers, buf.takeBytes());
    }().timeout(timeout);
    if (status == 304) return Refresh.notModified;
    if (status != 200) return Refresh.failed;
    final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      return Refresh.rejected;
    }
    if (!usable(body, inUse)) return Refresh.rejected;
    saveCatalog(db, body, headers['etag'], bundled);
    return Refresh.saved;
  } on _TooBig {
    return Refresh.rejected;
  } catch (_) {
    return Refresh.failed;
  } finally {
    if (client == null) c.close();
  }
}
