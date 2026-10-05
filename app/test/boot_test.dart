// 앱 시작. 파일 DB를 열고 담긴 규칙 파일을 옮기고 목록을 고르고 받기를 건다. 작업 006 계획 단계 4의 7, 작업 014 설계 2절
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/download.dart';
import 'package:cherry_consume/clock.dart' as clock;
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'catalog/split_download_test.dart' show changed, server;
import 'engine/helpers.dart' show realCardFile, realCatalog, realJson;
import 'store/helpers.dart' show pay, start;

final bundled = File('assets/catalog/index.json').readAsStringSync();

Future<String> read(String id) async => realCardFile(id);

String dbPath() {
  final dir = Directory.systemTemp.createTempSync('cherry');
  addTearDown(() => dir.deleteSync(recursive: true));
  return '${dir.path}/cherry.db';
}

String title(Widget app, String id) => (app as CherryApp)
    .api
    .store
    .catalog
    .cards[id]!
    .revisions
    .last
    .rules
    .benefits
    .first
    .title;

void main() {
  test('받은 카탈로그는 그 실행의 계산을 바꾸지 않고 다음에 켤 때부터 쓴다', () async {
    // 작업 006 단계 3 위험 검토. 받기 쪽 시험으로는 볼 수 없어 켜는 함수로 본다
    final path = dbPath();
    final (index, files) = changed(['shinhan-mrlife']);
    final (first, refresh) = await boot(
      path,
      bundled,
      read: read,
      refresh: (db, b, u) =>
          refreshIndex(db, b, u, client: server(index, files)),
    );
    expect(await refresh, Refresh.saved);
    expect(title(first, 'shinhan-mrlife'), isNot('바뀐 혜택'));
    (first as CherryApp).api.store.db.close();

    final (second, again) = await boot(
      path,
      bundled,
      read: read,
      refresh: (db, b, u) =>
          refreshIndex(db, b, u, client: server(index, files)),
    );
    expect(await again, Refresh.notModified);
    expect(title(second, 'shinhan-mrlife'), '바뀐 혜택');
    (second as CherryApp).api.store.db.close();
  });

  testWidgets('앱보다 새 판이 만든 DB면 홈 대신 지우지 말라는 안내를 보인다', (tester) async {
    final path = dbPath();
    sqlite3.open(path)
      ..execute('pragma user_version = 999')
      ..close();
    final (app, refresh) =
        await tester.runAsync(() => boot(path, bundled, read: read))
            as (Widget, Future<Refresh>?);
    expect(refresh, isNull);
    await tester.pumpWidget(app);
    expect(find.text('기록을 열지 못했어요'), findsOneWidget);
    expect(find.textContaining('앱 데이터를 지우면 기록이 모두 사라져요'), findsOneWidget);
    // 안내만 보이고 DB는 건드리지 않는다
    final db = sqlite3.open(path);
    expect(db.userVersion, 999);
    db.close();
  });

  testWidgets('담긴 규칙 파일을 옮기지 못하면 같은 안내를 보인다', (tester) async {
    // 작업 014 단계 3 위험 검토 중간 1. 엔진 안에서 매번 던지지 않고 켤 때 드러낸다
    final path = dbPath();
    final (app, refresh) =
        await tester.runAsync(
              () => boot(
                path,
                bundled,
                read: (id) async =>
                    id == 'shinhan-mrlife' ? '{}' : realCardFile(id),
              ),
            )
            as (Widget, Future<Refresh>?);
    expect(refresh, isNull);
    await tester.pumpWidget(app);
    expect(find.text('기록을 열지 못했어요'), findsOneWidget);
  });

  test('옛 판의 한 벌 카탈로그와 기록이 든 DB를 새 판으로 켜도 그대로 계산한다', () async {
    // 단계 5 위험 검토 낮음 3. 사용자 폰 하나가 이 길을 탄다. 받아 둔 줄에 schema 1 한 벌 본문과 옛 지문이 있다
    clock.now = () => start;
    addTearDown(() => clock.now = DateTime.now);
    final path = dbPath();
    final old = openDb(path, migrations.sublist(0, 3));
    final s = Store(old, realCatalog, clock: () => start);
    // 결제 넣기는 새 판 코드라 표 정의 5번의 가게 업종 표를 읽는다. 옛 판 DB에는 없어 넣는 동안만 두고 지운다. 새 판은
    // DB를 열 때 표 정의를 먼저 돌려 이 경우가 없다. 작업 016
    old.execute(migrations[4]);
    final card = addCard(
      s,
      'shinhan-mrlife',
      assumedPrevMonthSpend: 410000,
    )['id'];
    pay(s, card, 12000, 'GS25 테헤란점', at: '2026-09-10T12:00:00+09:00');
    final before = jsonEncode(home(s));
    old.execute('drop table merchant_categories');
    old.execute(
      'insert into catalog_cache (id, body, etag, bundled) '
      "values (1, ?, 'old-etag', 'old-mark')",
      [jsonEncode(realJson)],
    );
    old.close();
    final (app, refresh) = await boot(
      path,
      bundled,
      read: read,
      refresh: (db, b, u) async => Refresh.failed,
    );
    expect(await refresh, Refresh.failed);
    final store = (app as CherryApp).api.store;
    expect(store.db.userVersion, migrations.length);
    expect(store.db.select('select * from catalog_cache'), isEmpty);
    expect(jsonEncode(home(store)), before);
    store.db.close();
  });
}
