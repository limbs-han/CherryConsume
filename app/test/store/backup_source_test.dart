// 기록 파일의 엑셀 묶음 출처는 읽은 파일 모양 셋이거나 비어 있어야 한다. 파일 이름 같은 글자가 든 파일은 받지 않는다.
// 설계 문서 8절, 작업 013 13-10과 위험 검토 낮음 2
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/store/backup.dart';
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// csv 한 건을 가져온 기록을 내보낸 JSON
Map<String, dynamic> exported() {
  final (:s, clock: _) = fresh();
  final [mr] = setup(s);
  final p = imports.preview(
    s,
    Uint8List.fromList(
      utf8.encode('이용일자,가맹점명,이용금액\n2026.09.10,GS25 강남점,4300\n'),
    ),
    userCardId: mr,
  );
  imports.save(s, {
    'rows': [
      for (final r in p['rows'] as List)
        if ((r as Map).containsKey('paid_at')) r,
    ],
    'source': p['source'],
  });
  return jsonDecode(exportAll(s)) as Map<String, dynamic>;
}

/// 묶음 표의 출처 칸을 바꾼 기록 파일
Uint8List withSource(Map<String, dynamic> json, Object? source) {
  final t = json['tables']['import_batches'] as Map;
  final at = (t['columns'] as List).indexOf('source');
  for (final r in t['rows'] as List) {
    (r as List)[at] = source;
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(json)));
}

String? sourceIn(Store s) =>
    s.db.select('select source from import_batches').first['source'] as String?;

void main() {
  test('내보내고 가져와도 출처가 그대로다', () {
    final (:s, clock: _) = fresh();
    importAll(s, withSource(exported(), 'csv'));
    expect(sourceIn(s), 'csv');
  });

  test('옛 판의 빈 출처는 받는다', () {
    final (:s, clock: _) = fresh();
    importAll(s, withSource(exported(), null));
    expect(sourceIn(s), isNull);
  });

  test('파일 이름이 든 출처는 받지 않는다', () {
    final (:s, clock: _) = fresh();
    expect(
      () => importAll(s, withSource(exported(), '내역_홍길동_1234.xls')),
      throwsA(isA<ApiError>()),
    );
  });
}
