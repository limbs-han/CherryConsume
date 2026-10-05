// 엑셀 묶음의 출처는 실제로 읽은 파일 모양이다. 파일 이름은 남기지 않는다. 설계 문서 8절 기록 남기기, 작업 013 13-10
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// 미리보기의 행을 모두 저장하고 묶음 출처를 돌려준다
String? saved(Store s, Uint8List data, String card) {
  final p = imports.preview(s, data, userCardId: card);
  imports.save(s, {
    'rows': [
      for (final r in p['rows'] as List)
        if ((r as Map).containsKey('paid_at')) r,
    ],
    'source': p['source'],
  });
  return s.db
          .select('select source from import_batches order by id desc')
          .first['source']
      as String?;
}

void main() {
  test('csv, html 표, xlsx를 읽은 모양으로 남긴다', () {
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    const head = '이용일자,가맹점명,이용금액';
    final csv = Uint8List.fromList(
      utf8.encode('$head\n2026.09.10,GS25 강남점,4300\n'),
    );
    expect(saved(s, csv, mr), 'csv');

    // 카드사가 xls라는 이름으로 주는 파일 가운데 html 표가 있다
    final html = Uint8List.fromList(
      utf8.encode(
        '<table><tr><td>이용일자</td><td>가맹점명</td><td>이용금액</td></tr>'
        '<tr><td>2026.09.11</td><td>이마트 성수점</td><td>12000</td></tr></table>',
      ),
    );
    expect(saved(s, html, mr), 'html');

    final xlsx = File(
      'test/fixtures/imports/dates_and_numbers.xlsx',
    ).readAsBytesSync();
    expect(saved(s, xlsx, mr), 'xlsx');
  });

  test('모르는 출처는 남기지 않는다', () {
    final (:s, clock: _) = fresh();
    final [mr] = setup(s);
    final data = Uint8List.fromList(
      utf8.encode('이용일자,가맹점명,이용금액\n2026.09.10,GS25 강남점,4300\n'),
    );
    final p = imports.preview(s, data, userCardId: mr);
    imports.save(s, {
      'rows': [
        for (final r in p['rows'] as List)
          if ((r as Map).containsKey('paid_at')) r,
      ],
      'source': '내역_홍길동_1234.xls',
    });
    expect(
      s.db.select('select source from import_batches').first['source'],
      isNull,
    );
  });
}
