// 앱 시작. 파일 DB를 열고 카탈로그를 고르고 받기를 건다. 작업 006 계획 단계 4의 7
import 'dart:io';

import 'package:cherry_consume/catalog/download.dart';
import 'package:cherry_consume/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'catalog/download_test.dart' show answer, base, bundled, newer;

String dbPath() {
  final dir = Directory.systemTemp.createTempSync('cherry');
  addTearDown(() => dir.deleteSync(recursive: true));
  return '${dir.path}/cherry.db';
}

int cards(Widget app) => (app as CherryApp).api.store.catalog.cards.length;

void main() {
  test('받은 카탈로그는 그 실행의 계산을 바꾸지 않고 다음에 켤 때부터 쓴다', () async {
    // 단계 3 위험 검토. 받기 쪽 시험으로는 볼 수 없어 켜는 함수로 본다. newer는 담긴 것에서 카드 하나를 뺐다
    final path = dbPath();
    final all = (base['cards'] as List).length;
    final (first, refresh) = boot(
      path,
      bundled,
      refresh: (db, b, u) =>
          refreshCatalog(db, b, u, client: answer(200, newer)),
    );
    expect(await refresh, Refresh.saved);
    expect(cards(first), all);
    (first as CherryApp).api.store.db.close();

    final (second, again) = boot(
      path,
      bundled,
      refresh: (db, b, u) => refreshCatalog(db, b, u, client: answer(304, '')),
    );
    expect(await again, Refresh.notModified);
    expect(cards(second), all - 1);
    (second as CherryApp).api.store.db.close();
  });

  testWidgets('앱보다 새 판이 만든 DB면 홈 대신 지우지 말라는 안내를 보인다', (tester) async {
    final path = dbPath();
    sqlite3.open(path)
      ..execute('pragma user_version = 999')
      ..close();
    final (app, refresh) = boot(path, bundled);
    expect(refresh, isNull);
    await tester.pumpWidget(app);
    expect(find.text('기록을 열지 못했어요'), findsOneWidget);
    expect(find.textContaining('앱 데이터를 지우면 기록이 모두 사라져요'), findsOneWidget);
    // 안내만 보이고 DB는 건드리지 않는다
    final db = sqlite3.open(path);
    expect(db.userVersion, 999);
    db.close();
  });
}
