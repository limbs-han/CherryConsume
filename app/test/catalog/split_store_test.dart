// 폰 DB에 규칙 파일을 두고 쓸 목록 고르기. 작업 014 설계 2절, 계획 단계 3
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:cherry_consume/catalog/cache.dart';
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/catalog/split.dart';
import 'package:cherry_consume/store/backup.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/catalog.dart' as catalog_routes;
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../engine/helpers.dart' show realCatalog, realJson;
import '../store/helpers.dart' show Clock, pay;
import 'split_helpers.dart';

final _split = splitOf(realJson);
final _index = _split.$1, _files = _split.$2;
final bundled = jsonEncode(_index);

/// 한 카드의 혜택 제목을 바꾼 판. 그 카드의 규칙 파일과 목록 줄만 바뀐다
(String, Map<String, String>) changed(String cardId) {
  final j = jsonDecode(jsonEncode(realJson)) as Json;
  final card = (j['cards'] as List).firstWhere((c) => c['id'] == cardId);
  card['revisions'].last['rules']['benefits'][0]['title'] = '바뀐 혜택';
  final (index, files) = splitOf(j);
  return (jsonEncode(index), files);
}

Future<Database> ready([String? index, Map<String, String>? files]) async {
  final db = openDb();
  await copyBundled(db, index ?? bundled, (id) async => (files ?? _files)[id]!);
  return db;
}

int rows(Database db) =>
    db.select('select count(*) as n from catalog_card_files').first['n'] as int;

Store storeOf(Database db, Catalog cat) => Store(db, cat, clock: Clock().call);

String firstTitle(Catalog cat, String id) =>
    cat.cards[id]!.revisions.last.rules.benefits.first.title;

InUse holding(String card) => (
  cards: {card},
  merchants: <String>{},
  categories: <String>{},
  methods: <String>{},
);

void main() {
  test('담긴 규칙 파일을 앱 판마다 한 번 표로 옮긴다', () async {
    final db = openDb();
    var reads = 0;
    Future<String> counting(String id) async {
      reads++;
      return _files[id]!;
    }

    await copyBundled(db, bundled, counting);
    expect((reads, rows(db)), (20, 20));
    await copyBundled(db, bundled, counting);
    expect(reads, 20);
    // 새 판에 담긴 목록은 바뀐 카드 파일만 새로 옮긴다
    final (index2, files2) = changed('shinhan-mrlife');
    reads = 0;
    await copyBundled(db, index2, (id) async {
      reads++;
      return files2[id]!;
    });
    expect((reads, rows(db)), (1, 21));
  });

  test('지문이 목록과 다른 담긴 파일은 옮기지 않는다', () async {
    final db = await ready(bundled, {
      ..._files,
      'shinhan-mrlife': '${_files['shinhan-mrlife']!} ',
    });
    expect(rows(db), 19);
    expect(
      db.select(
        "select 1 from catalog_card_files where card_id = 'shinhan-mrlife'",
      ),
      isEmpty,
    );
  });

  test('받아 둔 것이 없으면 담긴 목록을 쓴다', () async {
    final db = await ready();
    expect(chooseIndex(db, bundled, nothing).cards, hasLength(20));
  });

  test('보유 카드의 규칙 파일이 표에 없는 목록은 쓰지 않는다', () async {
    final db = await ready();
    final (index2, files2) = changed('shinhan-mrlife');
    saveCatalog(db, index2, '"e1"', bundled);
    final held = holding('shinhan-mrlife');
    expect(
      firstTitle(chooseIndex(db, bundled, held), 'shinhan-mrlife'),
      isNot('바뀐 혜택'),
    );
    // 받은 파일이 표에 들어오면 받아 둔 목록을 쓴다
    saveCatalog(db, index2, '"e1"', bundled);
    final sha = fileSha(files2['shinhan-mrlife']!);
    saveCardFile(db, 'shinhan-mrlife', sha, files2['shinhan-mrlife']!);
    expect(
      firstTitle(chooseIndex(db, bundled, held), 'shinhan-mrlife'),
      '바뀐 혜택',
    );
  });

  test('1,500장에서 보유 카드 3장이면 켤 때 규칙 파일 3개만 읽는다', () async {
    // 의도 성공 기준 2
    final (bigIndex, bigFiles) = copiesOf(_index, _files, 75);
    final big = jsonEncode(bigIndex);
    expect(bigFiles, hasLength(1500));
    final db = await ready(big, bigFiles);
    expect(rows(db), 1500);
    final first = storeOf(db, chooseIndex(db, big, nothing));
    for (final id in [
      'shinhan-mrlife-3',
      'ibk-narasarang-40',
      'hana-wonder2-daily-74',
    ]) {
      addCard(first, id, assumedPrevMonthSpend: 300000);
    }
    // 다시 켠다
    final cat = chooseIndex(db, big, inUse(db));
    home(storeOf(db, cat));
    expect(
      [
        for (final c in cat.cards.values)
          if (c.rulesRead) c.id,
      ]..sort(),
      ['hana-wonder2-daily-74', 'ibk-narasarang-40', 'shinhan-mrlife-3'],
    );
  });

  test('인터넷 없이 담긴 카드를 검색, 미리보기, 등록한다', () async {
    // 의도 성공 기준 3. 받기를 부르지 않는다
    final db = await ready();
    final s = storeOf(db, chooseIndex(db, bundled, nothing));
    expect(
      catalog_routes.cards(s, q: 'mr').map((c) => c['id']),
      contains('shinhan-mrlife'),
    );
    expect(
      catalog_routes.preview(s, 'shinhan-mrlife', prev: 410000)['benefits'],
      isNotEmpty,
    );
    addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000);
    expect(home(s)['cards'], hasLength(1));
  });

  test('앱 판을 올려도 보유 카드의 규칙이 있고 안 쓰는 파일 줄은 지운다', () async {
    // 의도 성공 기준 8
    final db = await ready();
    final (got, gotFiles) = changed('shinhan-mrlife');
    saveCatalog(db, got, '"e1"', bundled);
    final sha = fileSha(gotFiles['shinhan-mrlife']!);
    saveCardFile(db, 'shinhan-mrlife', sha, gotFiles['shinhan-mrlife']!);
    addCard(storeOf(db, chooseIndex(db, bundled, nothing)), 'shinhan-mrlife');
    // 새 판은 다른 카드가 바뀌었다. 담긴 것을 먼저 보고 받아 둔 것은 지운다
    final (newer, newerFiles) = changed('ibk-narasarang');
    await copyBundled(db, newer, (id) async => newerFiles[id]!);
    final cat = chooseIndex(db, newer, inUse(db));
    expect(cachedCatalog(db), isNull);
    expect(firstTitle(cat, 'shinhan-mrlife'), isNot('바뀐 혜택'));
    expect(firstTitle(cat, 'ibk-narasarang'), '바뀐 혜택');
    // 받아 둔 mrlife 파일과 옛 판의 ibk 파일은 어느 목록도 가리키지 않는다
    expect(rows(db), 20);
    expect(home(storeOf(db, cat))['cards'], hasLength(1));
  });

  test('기록을 가져온 뒤에도 가져온 카드의 규칙이 있다', () async {
    // 의도 성공 기준 8
    final from = storeOf(openDb(), realCatalog);
    final card = addCard(
      from,
      'kb-toktok',
      assumedPrevMonthSpend: 300000,
    )['id'];
    pay(from, card, 12000, 'GS25 테헤란점', at: '2026-09-10T12:00:00+09:00');
    final file = Uint8List.fromList(utf8.encode(exportAll(from)));
    final db = await ready();
    final s = storeOf(db, chooseIndex(db, bundled, nothing));
    importAll(s, file);
    expect(home(s)['cards'], hasLength(1));
    expect(s.catalog.cards['kb-toktok']!.rulesRead, isTrue);
  });

  test('규칙 파일 하나라도 표에 없는 목록은 쓰지 않는다', () async {
    // 단계 3 위험 검토 중간 2. 보유하지 않은 카드라도 등록하거나 기록을 가져오면 그 뒤 홈이 계산하지 못한다
    final db = await ready();
    final (index2, _) = changed('kb-toktok');
    saveCatalog(db, index2, '"e1"', bundled);
    final cat = chooseIndex(db, bundled, holding('shinhan-mrlife'));
    expect(firstTitle(cat, 'kb-toktok'), isNot('바뀐 혜택'));
    expect(cachedCatalog(db), isNull);
  });

  test('담긴 규칙 파일이 표에 다 없고 받아 둔 것도 못 쓰면 켜지 않는다', () async {
    // 단계 3 위험 검토 중간 1. 엔진 안에서 매번 던지는 대신 켜기 화면이 "기록을 열지 못했어요"를 보인다
    final db = await ready(bundled, {
      ..._files,
      'shinhan-mrlife': '${_files['shinhan-mrlife']!} ',
    });
    expect(() => chooseIndex(db, bundled, nothing), throwsStateError);
  });

  test('담긴 파일을 읽다 실패하면 아무것도 옮기지 않고 다음에 다시 한다', () async {
    // 단계 3 위험 검토 낮음 8
    final db = openDb();
    await expectLater(
      copyBundled(db, bundled, (id) async => throw const FileSystemException()),
      throwsA(isA<FileSystemException>()),
    );
    expect(rows(db), 0);
    expect(db.select('select * from app_state'), isEmpty);
    await copyBundled(db, bundled, (id) async => _files[id]!);
    expect(rows(db), 20);
  });

  test('받는 중인 목록이 가리키는 파일은 켤 때 지우지 않는다', () async {
    // 단계 3 위험 검토 중간 3. 받다 꺼져도 다음 받기가 이어 받는다
    final db = await ready();
    final (index2, files2) = changed('shinhan-mrlife');
    final sha = fileSha(files2['shinhan-mrlife']!);
    expect(
      saveCardFile(db, 'shinhan-mrlife', sha, files2['shinhan-mrlife']!),
      isTrue,
    );
    db.execute('insert into app_state (key, value) values (?, ?)', [
      pendingKey,
      index2,
    ]);
    chooseIndex(db, bundled, nothing);
    expect(rows(db), 21);
    db.execute('delete from app_state where key = ?', [pendingKey]);
    chooseIndex(db, bundled, nothing);
    expect(rows(db), 20);
  });

  test('지문이 맞지 않는 규칙 파일은 표에 넣지 않는다', () {
    // 단계 3 위험 검토 낮음 5
    final db = openDb();
    final body = _files['shinhan-mrlife']!;
    expect(
      saveCardFile(db, 'shinhan-mrlife', fileSha('$body '), body),
      isFalse,
    );
    expect(rows(db), 0);
  });

  test('같은 판의 받아 둔 목록으로 켜도 보유 카드 규칙 파일만 읽는다', () async {
    // 단계 3 위험 검토 낮음 7. 자주 타는 길이다
    final (bigIndex, bigFiles) = copiesOf(_index, _files, 75);
    final big = jsonEncode(bigIndex);
    final db = await ready(big, bigFiles);
    saveCatalog(db, big, '"e1"', big);
    addCard(storeOf(db, chooseIndex(db, big, nothing)), 'kb-toktok-9');
    final cat = chooseIndex(db, big, inUse(db));
    expect(cachedCatalog(db)?.etag, '"e1"');
    home(storeOf(db, cat));
    expect(
      [
        for (final c in cat.cards.values)
          if (c.rulesRead) c.id,
      ],
      ['kb-toktok-9'],
    );
  });
}
