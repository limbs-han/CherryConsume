// 엑셀 가져오기의 파일 읽기. 서버 `backend/tests/api/test_import_parse.py`를 옮겼다. 작업 006 설계 5절, 계획 단계 5의 1
//
// xlsx와 cp949 csv는 Python이 만든 `test/fixtures/imports/`의 파일을 읽는다. backend/tools/make_import_fixtures.py
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cherry_consume/store/imports.dart';
import 'package:flutter_test/flutter_test.dart';

const head = ['이용일자', '이용시간', '가맹점명', '이용금액(원)', '할부', '승인번호', '취소여부'];
const body = [
  ['2026.09.10', '12:30', '스타벅스 강남점', '4,500', '일시불', '11112222', ''],
  ['2026-09-11', '', '이마트 성수점', '120,000', '3개월', '33334444', ''],
  ['2026/09/12', '08:05:09', '스타벅스 강남점', '-4,500', '일시불', '11112222', '취소'],
  ['합계', '', '', '120,000', '', '', ''],
];

// 날짜만 있는 행은 시각이 없다. 취소는 음수거나 취소 여부에 "취소"가 있다. 합계 줄은 건너뛴다
final want = [
  (
    DateTime.utc(2026, 9, 10),
    const Duration(hours: 12, minutes: 30),
    '스타벅스 강남점',
    4500,
    1,
    '11112222',
    false,
  ),
  (DateTime.utc(2026, 9, 11), null, '이마트 성수점', 120000, 3, '33334444', false),
  (
    DateTime.utc(2026, 9, 12),
    const Duration(hours: 8, minutes: 5, seconds: 9),
    '스타벅스 강남점',
    4500,
    1,
    '11112222',
    true,
  ),
];

Uint8List fixture(String name) =>
    File('test/fixtures/imports/$name').readAsBytesSync();

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

List<(DateTime?, Duration?, String, int, int, String?, bool)> rowsOf(
  Uint8List data,
) {
  final table = readTable(data);
  final (start, mapping) = findHeader(table);
  final out = parseRows(table, start!, mapping!);
  expect([for (final r in out) r.error], List.filled(out.length, null));
  return [
    for (final r in out)
      (
        r.day,
        r.at,
        r.merchant,
        r.amount,
        r.installmentMonths,
        r.approvalNo,
        r.cancel,
      ),
  ];
}

final unreadable = throwsA(isA<Unreadable>());

const _ns =
    'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// 가장 작은 xlsx. 시트 하나와 공유 글자, 서식
Uint8List xlsx(
  String rows, {
  String strings = '',
  String styles = '',
  String book = '',
}) {
  final files = {
    '_rels/.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="r1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml':
        '<workbook $_ns>$book<sheets><sheet name="a" sheetId="1" r:id="s1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="s1" Type="$_rel/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="s2" Type="$_rel/sharedStrings" Target="sharedStrings.xml"/>'
        '<Relationship Id="s3" Type="$_rel/styles" Target="/xl/styles.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml':
        '<worksheet $_ns><sheetData>$rows</sheetData></worksheet>',
    'xl/sharedStrings.xml': '<sst $_ns>$strings</sst>',
    'xl/styles.xml': '<styleSheet $_ns>$styles</styleSheet>',
  };
  final archive = Archive();
  for (final MapEntry(:key, :value) in files.entries) {
    archive.add(ArchiveFile.string(key, value));
  }
  return ZipEncoder().encodeBytes(archive);
}

String inline(int row, String col, String v) =>
    '<c r="$col$row" t="inlineStr"><is><t>$v</t></is></c>';

void main() {
  test('test_csv_in_utf8_and_cp949_with_title_rows', () {
    // 머리 줄 위에 제목 두 줄이 있다. 위에서 20줄 안에서 열 이름이 가장 많이 맞는 줄을 머리 줄로 본다
    expect(rowsOf(fixture('utf8.csv')), want);
    // Python이 cp949로 쓴 파일을 같은 글자로 읽는다
    expect(rowsOf(fixture('cp949.csv')), want);
  });

  test('test_xlsx_with_real_dates_and_numbers', () {
    expect(rowsOf(fixture('dates_and_numbers.xlsx')), want);
  });

  test('test_html_table_saved_as_xls', () {
    // 카드사 웹의 xls는 html 표인 경우가 많다
    final cells = [for (final h in head) '<th>$h</th>'].join();
    final rows = [
      for (final row in body)
        '<tr>${[for (final v in row) '<td>$v</td>'].join()}</tr>',
    ].join();
    expect(
      rowsOf(
        text('<html><body><table><tr>$cells</tr>$rows</table></body></html>'),
      ),
      want,
    );
  });

  test('test_unknown_headers_need_mapping_and_user_mapping_works', () {
    // E30. 사전에 없는 열 이름이면 null이다. 사용자가 짝지은 열 이름으로 읽고, 짝은 머리 줄 모양으로 다시 쓴다
    final table = readTable(text('날,곳,값\n2026.09.10,스타벅스,4500\n'));
    expect(findHeader(table), (null, null));
    final (start, mapping) = findHeader(table, {
      'row': 0,
      'columns': {'date': 0, 'merchant': 1, 'amount': 2},
    });
    final [row] = parseRows(table, start!, mapping!);
    expect(
      (row.day, row.merchant, row.amount, row.cancel),
      (DateTime.utc(2026, 9, 10), '스타벅스', 4500, false),
    );
    expect(signature(table[0]), signature([' 날 ', '곳', '값']));
  });

  test('test_bad_rows_and_files', () {
    final table = readTable(
      text('이용일자,가맹점명,이용금액\n2026.13.40,스타벅스,4500\n2026.09.10,스타벅스,사천오백\n'),
    );
    final (start, mapping) = findHeader(table);
    expect(
      [for (final r in parseRows(table, start!, mapping!)) r.error],
      ['날짜를 읽지 못했어요', '금액을 읽지 못했어요'],
    );
    // 진짜 옛 xls는 읽지 않는다. xlsx나 csv로 저장해 올리게 한다
    expect(
      () => readTable(
        Uint8List.fromList([
          0xd0,
          0xcf,
          0x11,
          0xe0,
          0xa1,
          0xb1,
          0x1a,
          0xe1,
          ...List.filled(100, 0),
        ]),
      ),
      unreadable,
    );
    expect(
      () => readTable(text('이용일자,가맹점명,이용금액\n${'2026.09.10,a,1\n' * 3100}')),
      unreadable,
    );
    // 한 열을 두 칸에 고르거나 꼭 필요한 칸을 빼면 받지 않는다
    for (final bad in [
      {'date': 0, 'merchant': 1, 'amount': 1},
      {'date': 0, 'merchant': 1},
    ]) {
      expect(
        () => findHeader(readTable(text('날,곳,값')), {'row': 0, 'columns': bad}),
        unreadable,
      );
    }
  });

  test('test_approval_installment_interest_free_and_region', () {
    // 자리만 채운 승인번호는 버린다. "무이자 3개월"은 무이자, "3개월"만 있으면 무이자인지 모른다. 해외 여부 Y는 해외다
    final table = readTable(
      text(
        [
          '이용일자,가맹점명,이용금액,할부,승인번호,해외여부',
          '2026.09.10,a,1000,무이자 3개월,-,N',
          '2026.09.10,b,1000,3개월,00000000,Y',
          '2026.09.10,c,1000,일시불,0012345,',
        ].join('\n'),
      ),
    );
    final (start, mapping) = findHeader(table);
    expect(
      [
        for (final r in parseRows(table, start!, mapping!))
          (r.installmentMonths, r.interestFree, r.approvalNo, r.overseas),
      ],
      [
        (3, true, null, false),
        (3, null, null, true),
        (1, false, '0012345', false),
      ],
    );
  });

  test('test_xlsx_size_bombs', () {
    // 시트 머리의 크기를 믿지 않는다. 100만 번째 행에 칸 하나가 있어도 정해 둔 만큼만 읽는다
    final table = readTable(fixture('far_cell.xlsx'));
    expect(table, hasLength(2));
    expect(table.every((r) => r.length <= 60), isTrue);
    // 풀면 30MB가 넘는 압축 파일은 열지 않는다
    expect(
      () => readTable(fixture('unzip_bomb.xlsx')),
      throwsA(
        isA<Unreadable>().having(
          (e) => e.message,
          'message',
          '엑셀 파일이 너무 커요. 기간을 나눠 올려 주세요',
        ),
      ),
    );
  });

  test('test_other_zip_methods_and_trailing_minus', () {
    // 재검토 높음 2번. 보통 쓰는 두 방식이 아닌 압축은 목차의 크기와 상관없이 읽지 않는다
    expect(() => readTable(fixture('bzip2.xlsx')), unreadable);
    // 낮음 11번. "4,500-"도 취소다
    final table = readTable(text('이용일자,가맹점명,이용금액\n2026.09.10,스타벅스,"4,500-"\n'));
    final (start, mapping) = findHeader(table);
    final [row] = parseRows(table, start!, mapping!);
    expect((row.amount, row.cancel), (4500, true));
  });

  test('test_committed_fixtures_read_the_same', () {
    // Python 시험도 같은 파일을 같게 읽는다. 두 쪽이 같은 파일을 보는지 확인한다
    for (final name in ['utf8.csv', 'cp949.csv', 'dates_and_numbers.xlsx']) {
      expect(rowsOf(fixture(name)), want, reason: name);
    }
  });

  test('숫자 칸 금액은 Python round처럼 .5를 짝수 쪽으로 반올림한다', () {
    // 설계 5절. Dart의 round()는 0에서 먼 쪽이라 4,500.5가 4,501이 된다
    final table = [
      ['이용일자', '가맹점명', '이용금액'],
      ['2026.09.10', 'a', 4500.5],
      ['2026.09.10', 'b', 4501.5],
      ['2026.09.10', 'c', -4500.5],
    ];
    final (start, mapping) = findHeader(table);
    expect(
      [
        for (final r in parseRows(table, start!, mapping!))
          (r.amount, r.cancel),
      ],
      [(4500, false), (4502, false), (4500, true)],
    );
  });

  test('csv 따옴표 안의 쉼표와 줄바꿈, 겹친 따옴표, CRLF 줄끝을 Python csv처럼 읽는다', () {
    final table = readTable(
      text(
        '이용일자,가맹점명,이용금액\r\n2026.09.10,"스타벅스, 강남\r\n점","4,500"\r\n2026.09.11,"이마트 ""성수""",1000\r\n',
      ),
    );
    expect(table, [
      ['이용일자', '가맹점명', '이용금액'],
      ['2026.09.10', '스타벅스, 강남\r\n점', '4,500'],
      ['2026.09.11', '이마트 "성수"', '1000'],
    ]);
    // 따옴표 밖의 줄 가운데 CR은 Python csv가 읽지 않는다
    expect(() => readTable(text('a,b\rc\n')), unreadable);
  });

  test('xlsx 행이 상한을 넘으면 말없이 자르지 않고 거절한다', () {
    // 서버 시험은 csv로만 봤다. 3,030번째 줄까지 읽고 마지막 열 줄에 값이 있으면 뒤에 더 있는 것이다. 빈 줄 뒤
    // 3,026번째부터 값이 있으면 읽은 값은 일곱 줄뿐이라 행 수 검사로는 못 잡는다
    final head =
        '<row r="1">${inline(1, 'A', '이용일자')}${inline(1, 'B', '가맹점명')}${inline(1, 'C', '이용금액')}</row>';
    String body(int from, int to) => [
      for (var r = from; r <= to; r++)
        '<row r="$r">${inline(r, 'A', '2026.09.10')}${inline(r, 'B', 'a')}<c r="C$r"><v>1</v></c></row>',
    ].join();
    expect(
      () => readTable(xlsx(head + body(2, 3) + body(3026, 3040))),
      throwsA(
        isA<Unreadable>().having(
          (e) => e.message,
          'message',
          '행이 3,000개보다 많아요. 기간을 나눠 올려 주세요',
        ),
      ),
    );
    // 값 없는 줄이 많아도 된다
    final blanks = [for (var r = 3; r <= 5000; r++) '<row r="$r"/>'].join();
    expect(readTable(xlsx(head + body(2, 2) + blanks)), hasLength(2));
  });

  test('공유 글자의 읽는 법은 빼고 한국어 엑셀 날짜 서식을 날짜로 읽는다', () {
    // 서식 31은 한국어 엑셀의 "2026년 9월 10일"이다. openpyxl은 이 번호를 몰라 46275라는 수로 읽었다. 164는 따옴표 안
    // 글자를 빼고 y, m, d가 남아 날짜다. 176은 "원"을 빼면 날짜 글자가 없다. 46275는 1899-12-30부터 센 2026-09-10이다
    const styles =
        '<numFmts><numFmt numFmtId="164" formatCode="yyyy&quot;년&quot; m&quot;월&quot; d&quot;일&quot;"/>'
        '<numFmt numFmtId="176" formatCode="#,##0&quot;원&quot;"/></numFmts>'
        '<cellStyleXfs><xf numFmtId="14"/></cellStyleXfs>'
        '<cellXfs><xf numFmtId="0"/><xf numFmtId="31"/><xf numFmtId="164"/><xf numFmtId="176"/></cellXfs>';
    const strings =
        '<si><r><t>스타벅스</t></r><r><t xml:space="preserve"> 강남점</t></r><rPh sb="0" eb="1"><t>すたば</t></rPh></si>';
    final rows =
        '<row r="1">${inline(1, 'A', '이용일자')}${inline(1, 'B', '가맹점명')}${inline(1, 'C', '이용금액')}</row>'
        '<row r="2"><c r="A2" s="1"><v>46275</v></c><c r="B2" t="s"><v>0</v></c><c r="C2" s="3"><v>4500</v></c></row>'
        '<row r="3"><c r="A3" s="2"><v>46275.5</v></c><c r="B3" t="s"><v>0</v></c><c r="C3" s="0"><v>4500</v></c></row>';
    final table = readTable(xlsx(rows, strings: strings, styles: styles));
    expect(table[1].take(3), [DateTime.utc(2026, 9, 10), '스타벅스 강남점', 4500]);
    expect(table[2].first, DateTime.utc(2026, 9, 10, 12));
    final (start, mapping) = findHeader(table);
    expect(
      [for (final r in parseRows(table, start!, mapping!)) (r.day, r.at)],
      [
        (DateTime.utc(2026, 9, 10), null),
        (DateTime.utc(2026, 9, 10), const Duration(hours: 12)),
      ],
    );
  });
  test('1904년 기준 날짜와 한국어 시각 서식, 경과 시간 서식을 읽는다', () {
    // 맥 엑셀은 1904-01-01부터 센다. 44813은 2026-09-10이다. 서식 32는 한국어 엑셀의 "12시 00분"이라 0.5가 12시다.
    // 46은 경과 시간 [h]:mm:ss이고 0.75를 18시로 읽는다. 단계 5 위험 검토 11번
    const styles =
        '<cellXfs><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="32"/><xf numFmtId="46"/></cellXfs>';
    final rows =
        '<row r="1">${inline(1, 'A', '이용일자')}${inline(1, 'B', '가맹점명')}${inline(1, 'C', '이용금액')}${inline(1, 'D', '이용시간')}</row>'
        '<row r="2"><c r="A2" s="1"><v>44813</v></c>${inline(2, 'B', 'a')}<c r="C2"><v>1000</v></c><c r="D2" s="2"><v>0.5</v></c></row>'
        '<row r="3"><c r="A3" s="1"><v>44813</v></c>${inline(3, 'B', 'b')}<c r="C3"><v>1000</v></c><c r="D3" s="3"><v>0.75</v></c></row>';
    final table = readTable(
      xlsx(rows, styles: styles, book: '<workbookPr date1904="1"/>'),
    );
    final (start, mapping) = findHeader(table);
    expect(
      [for (final r in parseRows(table, start!, mapping!)) (r.day, r.at)],
      [
        (DateTime.utc(2026, 9, 10), const Duration(hours: 12)),
        (DateTime.utc(2026, 9, 10), const Duration(hours: 18)),
      ],
    );
  });

  test('지역 머리에만 암호 표시가 있는 xlsx도 읽지 않는다', () {
    // 단계 5 위험 검토 3번. 중앙 목차는 암호가 없고 첫 항목의 지역 머리만 암호 표시가 있다. archive는 지역 머리를 보고
    // 암호를 풀려다 Unreadable이 아닌 오류를 던졌다
    final data = xlsx('<row r="1">${inline(1, 'A', 'x')}</row>');
    expect([data[0], data[1], data[2], data[3]], [0x50, 0x4b, 3, 4]);
    data[6] |= 1;
    expect(() => readTable(data), unreadable);
  });

  test('html 칸 수가 상한을 넘으면 표를 만들기 전에 거절한다', () {
    // 단계 5 위험 검토 4번. html 파서는 `<tr>` 없이 온 칸에도 줄을 만든다. `<tr`가 하나도 없어도 칸 수로 막는다
    expect(
      () => readTable(text('<table>${'<td>a</td>' * (3020 * 60 + 1)}</table>')),
      throwsA(
        isA<Unreadable>().having(
          (e) => e.message,
          'message',
          '행이 3,000개보다 많아요. 기간을 나눠 올려 주세요',
        ),
      ),
    );
  });

  test('61번째 열 뒤에만 값이 있는 줄은 60열에서 자른 뒤 빈 줄로 거른다', () {
    // 단계 5 위험 검토 5번. 서버처럼 자른 뒤 거른다. 거른 뒤 자르면 빈 줄이 남아 행 수와 머리 줄 찾기가 달라진다
    final table = readTable(
      text('이용일자,가맹점명,이용금액\n${',' * 60}x\n2026.09.10,a,1\n'),
    );
    expect(table, hasLength(2));
    expect(table[1].take(3), ['2026.09.10', 'a', '1']);
  });
}
