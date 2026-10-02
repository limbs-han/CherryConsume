/// 카탈로그 받기. 앱에서 네트워크를 부르는 곳은 여기 하나뿐이다. 작업 006 설계 2절 "내려받기", 의도 성공 기준 4
///
/// 공개 저장소의 `catalog.json`을 지난번 ETag와 함께 받는다. 같으면 GitHub이 몸통 없이 304로 답한다. 받은 파일은
/// 끝까지 읽히고 앱이 쓰는 카드, 가맹점, 업종이 모두 있어야 두고, 다음에 켤 때부터 쓴다. 보내는 것은 없다
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

import 'cache.dart';

const catalogUrl =
    'https://raw.githubusercontent.com/limbs-han/CherryConsume/master/app/assets/catalog.json';
const maxBytes = 5 * 1024 * 1024;

enum Refresh { saved, notModified, rejected, failed }

class _TooBig implements Exception {}

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
