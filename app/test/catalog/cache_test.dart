// 쓸 카탈로그 고르기. 작업 006 설계 2절, 계획 단계 3의 1
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/cache.dart';
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final bundled = File('assets/catalog.json').readAsStringSync();
final Json base = jsonDecode(bundled);
final ids = [for (final c in base['cards'] as List) c['id'] as String];

InUse holding(String card) =>
    (cards: {card}, merchants: <String>{}, categories: <String>{});

/// 담긴 카탈로그에서 카드 하나를 뺀 것. 받아 둔 파일과 담긴 파일을 카드 수로 가른다
String withoutCard(String text, [int index = 0]) {
  final j = jsonDecode(text) as Json;
  return jsonEncode({
    ...j,
    'cards': [...(j['cards'] as List)]..removeAt(index),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('앱에 담긴 카탈로그를 자산으로 읽는다', () async {
    // pubspec.yaml의 assets에 적어야 앱에 담긴다
    expect(await rootBundle.loadString('assets/catalog.json'), bundled);
  });

  test('받아 둔 것이 없으면 앱에 담긴 것을 쓴다', () {
    final db = openDb();
    expect(chooseCatalog(db, bundled, nothing).cards, hasLength(20));
  });

  test('받아 둔 것이 있으면 그것을 쓴다', () {
    final db = openDb();
    saveCatalog(db, withoutCard(bundled), '"e1"', bundled);
    expect(chooseCatalog(db, bundled, nothing).cards, hasLength(19));
    expect(cachedCatalog(db)?.etag, '"e1"');
  });

  test('앱에 담긴 파일이 바뀌면 받아 둔 것과 ETag를 지운다', () {
    // 새 판 앱에는 받아 둔 것보다 새 카탈로그가 담겨 있을 수 있다. 담긴 파일의 지문으로 새 판을 안다
    final db = openDb();
    saveCatalog(db, withoutCard(bundled), '"e1"', bundled);
    final newer = withoutCard(bundled, 1);
    final cat = chooseCatalog(db, newer, nothing);
    expect(cat.cards, hasLength(19));
    expect(cat.cards.keys, isNot(contains(ids[1])));
    expect(db.select('select * from catalog_cache'), isEmpty);
  });

  test('새 판에 담긴 파일에 보유 카드가 없으면 받아 둔 것을 그대로 쓴다', () {
    // 2026-10-02 위험 검토. 새 판을 빌드한 뒤 저장소에 더해진 카드를 받아 둔 파일로 등록했다. 새 판을 처음 켤 때
    // 인터넷이 안 되면, 담긴 파일로 돌아가는 순간 그 카드의 혜택이 0으로 저장된다
    final db = openDb();
    saveCatalog(db, bundled, '"e1"', withoutCard(bundled, 1));
    final newer = withoutCard(bundled, 0);
    final cat = chooseCatalog(db, newer, holding(ids[0]));
    expect(cat.cards.keys, contains(ids[0]));
    expect(cachedCatalog(db)?.etag, '"e1"');
  });

  test('받아 둔 것에 보유 카드가 없으면 담긴 것을 쓴다', () {
    final db = openDb();
    saveCatalog(db, withoutCard(bundled, 0), '"e1"', bundled);
    expect(
      chooseCatalog(db, bundled, holding(ids[0])).cards.keys,
      contains(ids[0]),
    );
  });

  test('받아 둔 것이 읽히지 않으면 지우고 담긴 것을 쓴다', () {
    final db = openDb();
    saveCatalog(db, '{"schema": 1', '"e1"', bundled);
    expect(chooseCatalog(db, bundled, nothing).cards, hasLength(20));
    expect(db.select('select * from catalog_cache'), isEmpty);
  });

  test('앱이 정확히 계산하지 못하는 소수가 든 파일은 쓰지 않는다', () {
    // 2026-10-02 위험 검토. Dart 분수는 64비트 정수라 넘치면 조용히 틀린 금액이 된다. Python JSON 만들기와 같은
    // 기준이다. 소수 넷째 자리까지, 10만 미만
    String rate(num x) {
      final j = jsonDecode(bundled) as Json;
      final rules =
          (j['cards'] as List).first['revisions'].first['rules'] as Json;
      final b = (rules['benefits'] as List).firstWhere(
        (b) => b['reward']['rate'] is num,
      );
      b['reward']['rate'] = x;
      return jsonEncode(j);
    }

    expect(usable(rate(12.3456), nothing), isTrue);
    expect(usable(rate(12.34567), nothing), isFalse);
    expect(usable(rate(100000.5), nothing), isFalse);
    expect(numberErrors(jsonDecode(bundled)), isEmpty);
    // 경계. 분모 1만과 10만, 1조. Python 시험과 같은 값이다
    expect(usable(rate(1.0001), nothing), isTrue);
    expect(usable(rate(1.00015), nothing), isFalse);
    expect(
      numberErrors({'c': 99999.9999, 'a': 999999999999, 'b': true}),
      isEmpty,
    );
    expect(numberErrors({'c': 100000.0}), ['c: 100000.0']);
    expect(
      numberErrors({
        'a': [1000000000000],
      }),
      ['a[0]: 1000000000000'],
    );
  });

  test('DB를 다시 열어도 표와 받아 둔 것이 그대로다', () {
    final dir = Directory.systemTemp.createTempSync('cherry');
    final path = '${dir.path}/cherry.db';
    try {
      final db = openDb(path);
      saveCatalog(db, withoutCard(bundled), '"e1"', bundled);
      db.close();
      final again = openDb(path);
      expect(again.userVersion, migrations.length);
      expect(again.select('pragma foreign_keys').first.values.first, 1);
      expect(chooseCatalog(again, bundled, nothing).cards, hasLength(19));
      again.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('앱보다 새 판이 만든 DB는 열지 않는다', () {
    // 모르는 표 모양을 그대로 쓰면 기록이 깨진다. 옛 판을 다시 깐 경우다
    final dir = Directory.systemTemp.createTempSync('cherry');
    final path = '${dir.path}/cherry.db';
    try {
      final db = openDb(path);
      db.userVersion = migrations.length + 1;
      db.close();
      expect(() => openDb(path), throwsStateError);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('지문은 같은 글자에 같고 한 글자만 달라도 다르다', () {
    expect(bundledMark(bundled), bundledMark(bundled));
    expect(bundledMark(bundled), isNot(bundledMark('$bundled ')));
    expect(bundledMark(''), 'cbf29ce484222325');
  });
}
