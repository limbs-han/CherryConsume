// 옛 엑셀 읽기. 값은 모두 지어낸 것이다. 작업 017 설계 1절, 4절
import 'dart:typed_data';

import 'package:cherry_consume/store/imports.dart';
import 'package:flutter_test/flutter_test.dart';

import 'xls_build.dart';

int serial(DateTime d, DateTime epoch) => d.difference(epoch).inDays;

void main() {
  final win = DateTime.utc(1899, 12, 30);
  final cells = [
    labelSst(0, 0, 0),
    labelSst(0, 1, 1),
    label(1, 0, '가맹점A'),
    number(1, 1, 12000),
    number(1, 2, 1.5),
    rk(2, 0, (345 << 2) | 2),
    rk(2, 1, (12345 << 2) | 3),
    mulrk(3, 0, [(7 << 2) | 2, (8 << 2) | 2]),
    number(4, 0, serial(DateTime.utc(2026, 9, 10), win) + 0.5, xf: 1),
    number(4, 1, serial(DateTime.utc(2026, 9, 11), win) + 0.75, xf: 2),
    formula(5, 0, value: 99),
    formula(5, 1, text: '합계'),
    boolErr(5, 2, true),
    number(7, 0, 1),
  ];
  Uint8List file({List<List<int>> extra = const []}) => cfb(
    biff(
      strings: ['승인금액', '우리카드ABC'],
      split: 4,
      formats: {164: 'yyyy-mm-dd hh:mm'},
      xfs: [0, 14, 164],
      cells: [...cells, ...extra],
    ),
  );
  final expected = [
    ['승인금액', '우리카드ABC'],
    ['가맹점A', 12000, 1.5],
    [345, 123.45],
    [7, 8],
    [DateTime.utc(2026, 9, 10, 12), DateTime.utc(2026, 9, 11, 18)],
    [99, '합계', true],
    [1],
  ];

  test('작은 흐름의 글자, 숫자, 날짜, 수식 결과, 이어진 공유 글자를 읽는다', () {
    final f = file();
    expect(f.length, lessThan(4096 + 2048));
    final r = readSource(f);
    expect(r.source, 'xls');
    expect(r.rows, expected);
  });

  test('큰 흐름도 같게 읽는다', () {
    // 4096바이트를 넘기려고 9번 줄 뒤에 숫자 250칸을 더한다
    final extra = [for (var c = 0; c < 250; c++) number(9, c, c.toDouble())];
    final r = readSource(file(extra: extra));
    expect(r.rows.take(7), expected);
    expect(r.rows.last.length, 60);
    expect(r.rows.last.last, 59);
  });

  test('1904 날짜 기준을 따른다', () {
    final r = readSource(
      cfb(
        biff(
          xfs: [0, 14],
          date1904: true,
          cells: [
            number(
              0,
              0,
              serial(DateTime.utc(2026, 9, 10), DateTime.utc(1904)).toDouble(),
              xf: 1,
            ),
          ],
        ),
      ),
    );
    expect(r.rows, [
      [DateTime.utc(2026, 9, 10)],
    ]);
  });

  Matcher says(String text) => throwsA(
    isA<Unreadable>().having((e) => e.message, 'message', contains(text)),
  );

  test('깨진 파일은 멈추지 않고 거절한다', () {
    final stream = biff(cells: cells.take(3).toList());
    expect(() => readSource(cfb(stream, loop: true)), says('깨져'));
    expect(() => readSource(cfb(stream, outside: true)), says('깨져'));
    final big = biff(cells: [for (var c = 0; c < 250; c++) number(0, c, 1)]);
    expect(() => readSource(cfb(big, loop: true)), says('깨져'));
    expect(() => readSource(cfb(big, outside: true)), says('깨져'));
    final good = cfb(stream);
    expect(() => readSource(good.sublist(0, 600)), says('깨져'));
    expect(
      () => readSource(
        Uint8List.fromList([0xd0, 0xcf, 0x11, 0xe0, ...List.filled(64, 0x30)]),
      ),
      says('깨져'),
    );
  });

  test('비밀번호가 걸린 파일과 아주 옛 형식은 알맞은 문구로 거절한다', () {
    expect(() => readSource(cfb(biff(password: true))), says('비밀번호'));
    expect(() => readSource(cfb(biff(), name: 'Book')), says('출력용'));
    expect(() => readSource(cfb(biff(version: 0x0500))), says('출력용'));
  });

  test('흐름 이름은 대소문자를 가리지 않고 오류 칸은 오류 글자로 읽는다', () {
    final r = readSource(
      cfb(
        biff(
          cells: [
            label(0, 0, '머리'),
            formula(1, 0, error: 0x2A),
            boolErr(1, 1, false, error: 0x07),
          ],
        ),
        name: 'WORKBOOK',
      ),
    );
    expect(r.rows, [
      ['머리'],
      ['#N/A', '#DIV/0!'],
    ]);
  });

  test('디렉터리 항목이 모두 큰 흐름을 가리키는 2MB 파일도 바로 거절한다', () {
    // 단계 1 위험 검토 중간 1. 항목마다 흐름을 다시 따라가면 이 PC에서 16초가 걸렸다
    const sectors = 4095, fatN = 32, dirStart = 32;
    final f = Uint8List(512 * (sectors + 1));
    final b = ByteData.sublistView(f);
    void put32(int at, int v) => b.setUint32(at, v, Endian.little);
    f.setAll(0, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
    b.setUint16(0x1E, 9, Endian.little);
    put32(0x30, dirStart);
    put32(0x38, 4096);
    put32(0x3C, 0xFFFFFFFE);
    put32(0x44, 0xFFFFFFFE);
    for (var i = 0; i < 109; i++) {
      put32(0x4C + i * 4, i < fatN ? i : 0xFFFFFFFF);
    }
    int fatAt(int n) => 512 + (n ~/ 128) * 512 + (n % 128) * 4;
    for (var n = 0; n < fatN * 128; n++) {
      put32(fatAt(n), n < fatN ? 0xFFFFFFFD : 0xFFFFFFFF);
    }
    for (var n = dirStart; n < sectors; n++) {
      put32(fatAt(n), n == sectors - 1 ? 0xFFFFFFFE : n + 1);
      for (var e = 0; e < 4; e++) {
        final at = 512 * (n + 1) + e * 128;
        b.setUint16(at, 0x52, Endian.little);
        b.setUint16(at + 0x40, 4, Endian.little);
        f[at + 0x42] = 5;
        put32(at + 0x74, dirStart);
      }
    }
    final sw = Stopwatch()..start();
    expect(() => readSource(f), says('깨져'));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });
}
