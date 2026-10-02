// 카탈로그 받기. 가짜 응답으로 본다. 작업 006 설계 2절과 4절, 계획 단계 3의 2, 의도 성공 기준 5
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/cache.dart';
import 'package:cherry_consume/catalog/download.dart';
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

final bundled = File('assets/catalog.json').readAsStringSync();
final Json base = jsonDecode(bundled);

/// 담긴 카탈로그에서 카드 하나를 뺀 것. 받은 파일이 들어갔는지 카드 수로 본다
final newer = jsonEncode({
  ...base,
  'cards': [...(base['cards'] as List)]..removeLast(),
});
final firstCard = (base['cards'] as List).first['id'] as String;

MockClient answer(
  int status,
  String body, {
  Map<String, String> headers = const {},
  List<http.Request>? seen,
}) => MockClient((req) async {
  seen?.add(req);
  return http.Response.bytes(utf8.encode(body), status, headers: headers);
});

int cachedCards(Database db) =>
    chooseCatalog(db, bundled, nothing).cards.length;

void main() {
  test('받은 파일을 ETag와 함께 두고 다음에는 ETag를 보내 304면 그대로 둔다', () async {
    final db = openDb();
    final seen = <http.Request>[];
    final first = await refreshCatalog(
      db,
      bundled,
      nothing,
      client: answer(200, newer, headers: {'etag': '"e1"'}, seen: seen),
    );
    expect(first, Refresh.saved);
    expect(seen.single.url.toString(), catalogUrl);
    expect(seen.single.headers.containsKey('If-None-Match'), isFalse);
    expect(cachedCards(db), 19);
    final again = await refreshCatalog(
      db,
      bundled,
      nothing,
      client: answer(304, '', seen: seen),
    );
    expect(again, Refresh.notModified);
    expect(seen.last.headers['If-None-Match'], '"e1"');
    expect(cachedCards(db), 19);
  });

  test('읽히지 않거나 형식 번호가 크면 버리고 가진 것을 쓴다', () async {
    final db = openDb();
    await refreshCatalog(
      db,
      bundled,
      nothing,
      client: answer(200, newer, headers: {'etag': '"e1"'}),
    );
    for (final bad in [
      '{"schema": 1, "cards": [',
      '<html>rate limited</html>',
      jsonEncode({...base, 'schema': catalogSchema + 1}),
      jsonEncode({...base, 'cards': 'none'}),
    ]) {
      expect(
        await refreshCatalog(db, bundled, nothing, client: answer(200, bad)),
        Refresh.rejected,
        reason: bad,
      );
      expect(cachedCards(db), 19);
      expect(cachedCatalog(db)?.etag, '"e1"');
    }
  });

  test('보유 카드나 저장한 결제의 카드, 가맹점, 업종이 빠진 파일은 버린다', () async {
    // 설계 4절. 카탈로그에서 지우지 않는 것이 규칙이지만 빠진 파일을 쓰면 기록이 깨진다
    final db = openDb();
    final noCard = jsonEncode({
      ...base,
      'cards': [...(base['cards'] as List)]..removeAt(0),
    });
    final merchants = base['merchants'] as List;
    final noMerchant = jsonEncode({...base, 'merchants': merchants.sublist(1)});
    final noCategory = jsonEncode({
      ...base,
      'categories': [
        for (final c in base['categories'] as List)
          if (c['code'] != 'transit') c else {...c, 'children': []},
      ],
    });
    final inUse = (
      cards: {firstCard},
      merchants: {merchants.first['key'] as String},
      categories: {'cafe', 'transit.subway'},
    );
    for (final bad in [noCard, noMerchant, noCategory]) {
      expect(
        await refreshCatalog(db, bundled, inUse, client: answer(200, bad)),
        Refresh.rejected,
      );
    }
    expect(db.select('select * from catalog_cache'), isEmpty);
    expect(
      await refreshCatalog(db, bundled, inUse, client: answer(200, bundled)),
      Refresh.saved,
    );
  });

  test('5MB를 넘으면 버린다', () async {
    final db = openDb();
    final big = '$newer${' ' * (maxBytes - utf8.encode(newer).length + 1)}';
    expect(
      await refreshCatalog(db, bundled, nothing, client: answer(200, big)),
      Refresh.rejected,
    );
    final fits = '$newer${' ' * (maxBytes - utf8.encode(newer).length)}';
    expect(
      await refreshCatalog(db, bundled, nothing, client: answer(200, fits)),
      Refresh.saved,
    );
  });

  test('시간이 지나거나 끊기거나 서버 오류면 가진 것을 쓴다', () async {
    final db = openDb();
    final slow = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return http.Response(newer, 200);
    });
    expect(
      await refreshCatalog(
        db,
        bundled,
        nothing,
        client: slow,
        timeout: const Duration(milliseconds: 50),
      ),
      Refresh.failed,
    );
    final cut = MockClient((_) async => throw http.ClientException('끊김'));
    expect(
      await refreshCatalog(db, bundled, nothing, client: cut),
      Refresh.failed,
    );
    expect(
      await refreshCatalog(db, bundled, nothing, client: answer(500, newer)),
      Refresh.failed,
    );
    expect(
      await refreshCatalog(db, bundled, nothing, client: answer(404, newer)),
      Refresh.failed,
    );
    expect(db.select('select * from catalog_cache'), isEmpty);
  });

  test('몸통을 받다가 멈추거나 조각으로 5MB를 넘으면 끊는다', () async {
    // 2026-10-02 위험 검토. 응답 머리는 바로 오고 몸통이 늦거나 큰 경우다
    final db = openDb();
    final stalled = MockClient.streaming((_, _) async {
      final body = StreamController<List<int>>();
      body.add(utf8.encode(newer.substring(0, 100)));
      return http.StreamedResponse(body.stream, 200);
    });
    expect(
      await refreshCatalog(
        db,
        bundled,
        nothing,
        client: stalled,
        timeout: const Duration(milliseconds: 50),
      ),
      Refresh.failed,
    );
    var sent = 0;
    final endless = MockClient.streaming((_, _) async {
      Stream<List<int>> chunks() async* {
        while (true) {
          sent += 1 << 20;
          yield List.filled(1 << 20, 32);
        }
      }

      return http.StreamedResponse(chunks(), 200);
    });
    expect(
      await refreshCatalog(db, bundled, nothing, client: endless),
      Refresh.rejected,
    );
    expect(sent, lessThanOrEqualTo(maxBytes + (2 << 20)));
    expect(db.select('select * from catalog_cache'), isEmpty);
  });

  test('넘겨주기를 따라가지 않는다', () async {
    final seen = <http.Request>[];
    await refreshCatalog(
      openDb(),
      bundled,
      nothing,
      client: answer(304, '', seen: seen),
    );
    expect(seen.single.followRedirects, isFalse);
  });
}
