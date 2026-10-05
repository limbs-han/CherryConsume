// 마지막으로 기록을 내보낸 날. 기록이 아니라 앱 상태라 내보내기 파일에 넣지 않고 기록을 가져와도 그대로 둔다.
// 작업 012 설계 4절
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/store/backup.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart' show realCatalog;

import 'helpers.dart';

void main() {
  test('내보낸 적이 없으면 비어 있고 적으면 그 시각이다', () {
    final (:s, :clock) = fresh();
    expect(lastExported(s), isNull);
    markExported(s);
    expect(lastExported(s), start);
    clock.now = start.add(const Duration(days: 3));
    markExported(s);
    expect(lastExported(s), start.add(const Duration(days: 3)));
  });

  test('내보내기 파일에 넣지 않고 기록을 가져와도 그대로다', () {
    final (:s, clock: _) = fresh();
    setup(s);
    markExported(s);
    final file = exportAll(s);
    expect((jsonDecode(file) as Map)['tables'], isNot(contains('app_state')));
    final (s: other, clock: _) = fresh();
    importAll(other, Uint8List.fromList(utf8.encode(file)));
    expect(lastExported(other), isNull);
    importAll(s, Uint8List.fromList(utf8.encode(file)));
    expect(lastExported(s), start);
  });

  // 표 번호 3은 앱 상태 표만 더했다. 기록 표는 2와 같아 2번 파일도 빠진 표와 칸을 검사해야 한다. 혜택 줄이 빠지면 0원으로
  // 굳고 지운 시각 칸이 빠지면 지운 결제가 살아난다. 위험 검토 중간 1
  Uint8List asSchema2(
    String file, [
    void Function(Map<String, dynamic>)? edit,
  ]) {
    final j = jsonDecode(file) as Map<String, dynamic>;
    j['schema'] = 2;
    edit?.call(j);
    return Uint8List.fromList(utf8.encode(jsonEncode(j)));
  }

  String recorded() {
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    pay(s, mr, 4300, 'GS25 강남점');
    return exportAll(s);
  }

  test('지금 앱이 내보낸 2번 파일은 그대로 받는다', () {
    final file = recorded();
    final (:s, clock: _) = fresh();
    importAll(s, asSchema2(file));
    expect(s.db.select('select count(*) as n from transactions').first['n'], 1);
    expect(
      s.db.select('select count(*) as n from transaction_benefits').first['n'],
      greaterThan(0),
    );
  });

  test('2번 파일에서 혜택 표나 지운 시각 칸이 빠지면 받지 않는다', () {
    final file = recorded();
    final (:s, clock: _) = fresh();
    expect(
      () => importAll(
        s,
        asSchema2(
          file,
          (j) => (j['tables'] as Map).remove('transaction_benefits'),
        ),
      ),
      throwsA(isA<ApiError>()),
    );
    expect(
      () => importAll(
        s,
        asSchema2(file, (j) {
          final t = j['tables']['transactions'] as Map;
          final at = (t['columns'] as List).indexOf('deleted_at');
          (t['columns'] as List).removeAt(at);
          for (final r in t['rows'] as List) {
            (r as List).removeAt(at);
          }
        }),
      ),
      throwsA(isA<ApiError>()),
    );
  });

  test('카드가 든 2번 DB를 지금 번호로 올려도 기록이 그대로다', () {
    // 위험 검토 낮음 3
    final dir = Directory.systemTemp.createTempSync('cherry');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/cherry.db';
    final old = openDb(path, migrations.sublist(0, 2));
    addCard(Store(old, realCatalog, clock: () => start), 'shinhan-mrlife');
    old.close();
    final db = openDb(path);
    addTearDown(db.close);
    expect(db.userVersion, migrations.length);
    expect(db.select('select count(*) as n from user_cards').first['n'], 1);
    expect(db.select('select count(*) as n from app_state').first['n'], 0);
  });
}
