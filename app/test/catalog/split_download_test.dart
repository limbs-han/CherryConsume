// 목록 파일과 바뀐 규칙 파일 받기. 가짜 응답으로 본다. 작업 014 설계 3절, 계획 단계 4, 의도 성공 기준 5
import 'dart:convert';

import 'package:cherry_consume/catalog/cache.dart';
import 'package:cherry_consume/catalog/download.dart';
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/catalog/split.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';

import '../engine/helpers.dart' show realJson;
import 'split_helpers.dart';

final _split = splitOf(realJson);
final bundled = jsonEncode(_split.$1);

/// 카드들의 첫 혜택 제목을 바꾼 판
(Json, Map<String, String>) changed(List<String> ids) {
  final j = jsonDecode(jsonEncode(realJson)) as Json;
  for (final c in j['cards'] as List) {
    if (ids.contains(c['id'])) {
      c['revisions'].last['rules']['benefits'][0]['title'] = '바뀐 혜택';
    }
  }
  return splitOf(j);
}

Future<Database> ready() async {
  final db = openDb();
  await copyBundled(db, bundled, (id) async => _split.$2[id]!);
  return db;
}

/// 저장소 흉내. 목록은 ETag와 함께, 규칙 파일은 cards 아래 주소로 준다. cardStatus로 카드마다 응답 번호를 바꾼다
MockClient server(
  Json index,
  Map<String, String> files, {
  String etag = '"e1"',
  List<http.Request>? seen,
  Map<String, int> cardStatus = const {},
}) => MockClient((req) async {
  seen?.add(req);
  final url = req.url.toString();
  if (url == indexUrl) {
    if (req.headers['If-None-Match'] == etag) return http.Response('', 304);
    return http.Response.bytes(
      utf8.encode(jsonEncode(index)),
      200,
      headers: {'etag': etag},
    );
  }
  final id = url.substring(cardsUrl.length).replaceAll('.json', '');
  final status = cardStatus[id] ?? 200;
  if (status != 200 || !files.containsKey(id)) {
    return http.Response('', status == 200 ? 404 : status);
  }
  return http.Response.bytes(utf8.encode(files[id]!), 200);
});

List<String> cardRequests(List<http.Request> seen) => [
  for (final r in seen)
    if (r.url.toString().startsWith(cardsUrl))
      r.url.toString().substring(cardsUrl.length),
];

String? pending(Database db) {
  final r = db.select('select value from app_state where key = ?', [
    pendingKey,
  ]);
  return r.isEmpty ? null : r.first['value'] as String;
}

String title(Database db, String id) => chooseIndex(
  db,
  bundled,
  nothing,
).cards[id]!.revisions.last.rules.benefits.first.title;

void main() {
  test('카드 하나만 바뀐 목록이면 그 규칙 파일 하나만 받는다', () async {
    // 의도 성공 기준 5
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife']);
    final seen = <http.Request>[];
    final got = await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(index, files, seen: seen),
    );
    expect(got, Refresh.saved);
    expect(seen.first.url.toString(), indexUrl);
    expect(cardRequests(seen), ['shinhan-mrlife.json']);
    expect(cachedCatalog(db)?.etag, '"e1"');
    expect(pending(db), isNull);
    expect(title(db, 'shinhan-mrlife'), '바뀐 혜택');
    // 다음에는 ETag를 보내 304면 그대로 둔다
    final again = await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(index, files, seen: seen),
    );
    expect(again, Refresh.notModified);
    expect(seen.last.headers['If-None-Match'], '"e1"');
  });

  test('받다 실패하면 목록을 두지 않고 다음 받기가 남은 파일만 받는다', () async {
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife', 'kb-toktok']);
    final first = await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(index, files, cardStatus: {'kb-toktok': 500}),
    );
    expect(first, Refresh.failed);
    expect(cachedCatalog(db), isNull);
    expect(pending(db), isNotNull);
    // 앱을 다시 켜도 받는 중인 파일은 남는다
    chooseIndex(db, bundled, nothing);
    final seen = <http.Request>[];
    final second = await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(index, files, seen: seen),
    );
    expect(second, Refresh.saved);
    expect(cardRequests(seen), ['kb-toktok.json']);
    expect(title(db, 'kb-toktok'), '바뀐 혜택');
  });

  test('지문이 틀리거나 크거나 목록과 다른 판인 규칙 파일은 받지 않는다', () async {
    final (index, files) = changed(['shinhan-mrlife']);
    final body = files['shinhan-mrlife']!;
    Json withHead(void Function(Json) f) {
      final j = jsonDecode(jsonEncode(index)) as Json;
      f((j['cards'] as List).firstWhere((c) => c['id'] == 'shinhan-mrlife'));
      return j;
    }

    final rules = jsonDecode(body) as Json;
    rules['revisions'][0]['rules']['benefits'][0]['reward']['rate'] = 12.34567;
    final badNumber = jsonEncode(rules);
    final cases = <String, (Json, String)>{
      // 글자가 목록의 지문과 다르다
      'sha': (index, '$body '),
      // 1MB를 넘는다
      'big': (
        withHead((c) => c['file_sha256'] = fileSha(body + ' ' * 1100000)),
        body + ' ' * 1100000,
      ),
      // 지문은 맞지만 목록의 개정 머리와 다른 판이다
      'head': (withHead((c) => c['revisions'][0]['tiers'] = [0, 1]), body),
      // 앱이 정확히 계산하지 못하는 수가 있다
      'number': (
        withHead((c) => c['file_sha256'] = fileSha(badNumber)),
        badNumber,
      ),
    };
    for (final MapEntry(key: name, value: (idx, file)) in cases.entries) {
      final db = await ready();
      final got = await refreshIndex(
        db,
        bundled,
        nothing,
        client: server(idx, {...files, 'shinhan-mrlife': file}),
      );
      expect(got, Refresh.rejected, reason: name);
      expect(cachedCatalog(db), isNull, reason: name);
      expect(title(db, 'shinhan-mrlife'), isNot('바뀐 혜택'), reason: name);
    }
  });

  test('보유 카드가 빠진 목록은 규칙 파일을 받지 않고 버린다', () async {
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife']);
    (index['cards'] as List).removeWhere((c) => c['id'] == 'kb-toktok');
    final seen = <http.Request>[];
    final got = await refreshIndex(db, bundled, (
      cards: {'kb-toktok'},
      merchants: <String>{},
      categories: <String>{},
      methods: <String>{},
    ), client: server(index, files, seen: seen));
    expect(got, Refresh.rejected);
    expect(cardRequests(seen), isEmpty);
    expect(pending(db), isNull);
  });

  test('한 번에 받는 양이 상한을 넘으면 그만두고 다음 받기가 이어 받는다', () async {
    // 상한을 두 파일 바이트 합보다 작고 큰 파일 하나보다 크게 잡아야 합계를 본다. 단계 4 위험 검토 낮음 9
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife', 'kb-toktok']);
    final sizes = [
      for (final id in ['shinhan-mrlife', 'kb-toktok'])
        utf8.encode(files[id]!).length,
    ];
    final cap = sizes.reduce((a, b) => a > b ? a : b) + 1;
    expect(cap, lessThan(sizes[0] + sizes[1]));
    final got = await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(index, files),
      maxTotal: cap,
    );
    expect(got, Refresh.failed);
    expect(cachedCatalog(db), isNull);
    expect(pending(db), isNotNull);
    expect(
      await refreshIndex(db, bundled, nothing, client: server(index, files)),
      Refresh.saved,
    );
  });

  test('받는 중인 목록이 있을 때 304면 받는 중 목록을 지운다', () async {
    // 단계 4 위험 검토 낮음 9
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife']);
    await refreshIndex(db, bundled, nothing, client: server(index, files));
    final (newer, newerFiles) = changed(['shinhan-mrlife', 'kb-toktok']);
    await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(
        newer,
        newerFiles,
        etag: '"e2"',
        cardStatus: {'kb-toktok': 500},
      ),
    );
    expect(pending(db), isNotNull);
    // 저장소가 받아 둔 판으로 돌아갔다
    expect(
      await refreshIndex(db, bundled, nothing, client: server(index, files)),
      Refresh.notModified,
    );
    expect(pending(db), isNull);
  });

  test('깨지거나 큰 목록, 다른 카드나 다른 형식 번호의 규칙 파일, 시간 초과', () async {
    // 단계 4 위험 검토 낮음 9
    final (index, files) = changed(['shinhan-mrlife']);
    Json pointing(String body) {
      final j = jsonDecode(jsonEncode(index)) as Json;
      (j['cards'] as List).firstWhere(
        (c) => c['id'] == 'shinhan-mrlife',
      )['file_sha256'] = fileSha(
        body,
      );
      return j;
    }

    final newerSchema = jsonEncode({
      ...jsonDecode(files['shinhan-mrlife']!) as Json,
      'schema': splitSchema + 1,
    });
    final cases = <String, (MockClient, Refresh)>{
      'broken': (
        MockClient((req) async => http.Response('{"schema": 2', 200)),
        Refresh.rejected,
      ),
      'big': (
        MockClient(
          (req) async =>
              http.Response.bytes(List.filled(maxBytes + 1, 32), 200),
        ),
        Refresh.rejected,
      ),
      // 지문은 맞지만 다른 카드의 규칙 파일이다
      'id': (
        server(pointing(files['kb-toktok']!), {
          ...files,
          'shinhan-mrlife': files['kb-toktok']!,
        }),
        Refresh.rejected,
      ),
      'schema': (
        server(pointing(newerSchema), {
          ...files,
          'shinhan-mrlife': newerSchema,
        }),
        Refresh.rejected,
      ),
      'timeout': (
        MockClient((req) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('', 200);
        }),
        Refresh.failed,
      ),
    };
    for (final MapEntry(key: name, value: (client, want)) in cases.entries) {
      final db = await ready();
      final got = await refreshIndex(
        db,
        bundled,
        nothing,
        client: client,
        timeout: const Duration(milliseconds: 100),
      );
      expect(got, want, reason: name);
      expect(cachedCatalog(db), isNull, reason: name);
    }
  });

  test('1MB에 딱 맞는 규칙 파일은 받고 넘으면 버린다', () async {
    // 단계 4 위험 검토 낮음 9
    final (index, files) = changed(['shinhan-mrlife']);
    final body = files['shinhan-mrlife']!;
    for (final (extra, want) in [(0, Refresh.saved), (1, Refresh.rejected)]) {
      final padded =
          body + ' ' * (maxCardBytes - utf8.encode(body).length + extra);
      final j = jsonDecode(jsonEncode(index)) as Json;
      (j['cards'] as List).firstWhere(
        (c) => c['id'] == 'shinhan-mrlife',
      )['file_sha256'] = fileSha(
        padded,
      );
      final db = await ready();
      final got = await refreshIndex(
        db,
        bundled,
        nothing,
        client: server(j, {...files, 'shinhan-mrlife': padded}),
      );
      expect(got, want, reason: '$extra');
    }
  });

  test('받기 둘이 겹치면 하나로 돈다', () async {
    // 단계 4 위험 검토 낮음 5
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife']);
    final seen = <http.Request>[];
    final client = server(index, files, seen: seen);
    final both = await Future.wait([
      refreshIndex(db, bundled, nothing, client: client),
      refreshIndex(db, bundled, nothing, client: client),
    ]);
    expect(both, [Refresh.saved, Refresh.saved]);
    expect(seen, hasLength(2));
  });

  test('다른 주소로 넘겨주기를 따라가지 않는다', () async {
    final db = await ready();
    final (index, files) = changed(['shinhan-mrlife']);
    final seen = <http.Request>[];
    await refreshIndex(
      db,
      bundled,
      nothing,
      client: server(index, files, seen: seen),
    );
    expect(seen, hasLength(2));
    expect(seen.every((r) => !r.followRedirects), isTrue);
    // 302를 받으면 따라가지 않고 그만둔다
    seen.clear();
    final got = await refreshIndex(
      await ready(),
      bundled,
      nothing,
      client: MockClient((req) async {
        seen.add(req);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://example.com/'},
        );
      }),
    );
    expect(got, Refresh.failed);
    expect(seen, hasLength(1));
  });
}
