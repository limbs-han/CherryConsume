// 담긴 카탈로그 자산, 수 검사, 지문, DB 열기. 작업 006 설계 2절, 계획 단계 3의 1, 작업 014 설계 2절
//
// 쓸 목록 고르기는 split_store_test, 받기는 split_download_test다
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/cache.dart';
import 'package:cherry_consume/catalog/split.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart' show realCardFile, realIndex;

final bundled = File('assets/catalog/index.json').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('앱에 담긴 목록 파일과 규칙 파일을 자산으로 읽는다', () async {
    // pubspec.yaml의 assets에 폴더마다 적어야 앱에 담긴다
    expect(await rootBundle.loadString('assets/catalog/index.json'), bundled);
    for (final c in realIndex['cards'] as List) {
      expect(
        await rootBundle.loadString('assets/catalog/cards/${c['id']}.json'),
        realCardFile(c['id']),
      );
    }
  });

  test('앱이 정확히 계산하지 못하는 수를 찾는다', () {
    // 2026-10-02 위험 검토. Dart 분수는 64비트 정수라 넘치면 조용히 틀린 금액이 된다. Python JSON 만들기와 같은
    // 기준이다. 소수 넷째 자리까지, 10만 미만. 받은 규칙 파일과 표에서 읽는 규칙 파일이 이 검사를 거친다
    expect(numberErrors(jsonDecode(bundled)), isEmpty);
    for (final c in realIndex['cards'] as List) {
      expect(numberErrors(jsonDecode(realCardFile(c['id']))), isEmpty);
    }
    expect(numberErrors({'r': 12.3456}), isEmpty);
    expect(numberErrors({'r': 12.34567}), ['r: 12.34567']);
    expect(numberErrors({'r': 100000.5}), ['r: 100000.5']);
    // 경계. 분모 1만과 10만, 1조. Python 시험과 같은 값이다
    expect(numberErrors({'r': 1.0001}), isEmpty);
    expect(numberErrors({'r': 1.00015}), ['r: 1.00015']);
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

  test('DB를 다시 열어도 표와 받아 둔 것이 그대로다', () async {
    final dir = Directory.systemTemp.createTempSync('cherry');
    final path = '${dir.path}/cherry.db';
    try {
      final db = openDb(path);
      await copyBundled(db, bundled, (id) async => realCardFile(id));
      saveCatalog(db, bundled, '"e1"', bundled);
      db.close();
      final again = openDb(path);
      expect(again.userVersion, migrations.length);
      expect(again.select('pragma foreign_keys').first.values.first, 1);
      expect(chooseIndex(again, bundled, nothing).cards, hasLength(20));
      expect(cachedCatalog(again)?.etag, '"e1"');
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
