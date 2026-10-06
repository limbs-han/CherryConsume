// 시험용 옛 엑셀 파일 만들기. 512바이트 섹터의 OLE 복합 파일 안에 BIFF8 흐름 하나를 넣는다. 작업 017 설계 4절
import 'dart:typed_data';

const _end = 0xFFFFFFFE, _free = 0xFFFFFFFF, _fatSect = 0xFFFFFFFD;

Uint8List _u16(int v) =>
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List();
Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
Uint8List _f64(double v) =>
    (ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List();

/// 레코드 하나
List<int> rec(int id, List<int> data) => [
  ..._u16(id),
  ..._u16(data.length),
  ...data,
];

/// XLUnicodeString. 한글이 있으면 두 바이트 글자다
List<int> ustr(String s, {int lenBytes = 2}) {
  final high = s.codeUnits.any((c) => c > 0xFF);
  return [
    ...(lenBytes == 2 ? _u16(s.length) : [s.length]),
    high ? 1 : 0,
    for (final c in s.codeUnits) ...(high ? _u16(c) : [c]),
  ];
}

List<int> cellHead(int row, int col, int xf) => [
  ..._u16(row),
  ..._u16(col),
  ..._u16(xf),
];
List<int> number(int row, int col, double v, {int xf = 0}) =>
    rec(0x0203, [...cellHead(row, col, xf), ..._f64(v)]);
List<int> label(int row, int col, String s) =>
    rec(0x0204, [...cellHead(row, col, 0), ...ustr(s)]);
List<int> labelSst(int row, int col, int n) =>
    rec(0x00FD, [...cellHead(row, col, 0), ..._u32(n)]);
List<int> rk(int row, int col, int value, {int xf = 0}) =>
    rec(0x027E, [...cellHead(row, col, xf), ..._u32(value)]);
List<int> mulrk(int row, int first, List<int> values) => rec(0x00BD, [
  ..._u16(row),
  ..._u16(first),
  for (final v in values) ...[..._u16(0), ..._u32(v)],
  ..._u16(first + values.length - 1),
]);

/// 수식. 숫자 결과면 [value], 글자 결과면 [text]로 STRING 레코드가 뒤따른다
List<int> formula(
  int row,
  int col, {
  double? value,
  String? text,
  int? error,
}) => [
  ...rec(0x0006, [
    ...cellHead(row, col, 0),
    ...(text != null
        ? [0, 0, 0, 0, 0, 0, 0xFF, 0xFF]
        : error != null
        ? [2, 0, error, 0, 0, 0, 0xFF, 0xFF]
        : _f64(value!)),
    0, 0, 0, 0, 0, 0, // 옵션과 chn
    0, 0, // 수식 길이 0
  ]),
  if (text != null) ...rec(0x0207, ustr(text)),
];
List<int> boolErr(int row, int col, bool v, {int? error}) => rec(0x0205, [
  ...cellHead(row, col, 0),
  error ?? (v ? 1 : 0),
  error == null ? 0 : 1,
]);

/// BIFF8 흐름. [strings]는 공유 글자 표다. [split]이면 마지막 글자를 그 글자 수에서 끊어 CONTINUE로 잇고, 이어지는
/// 조각은 한 바이트 글자로 적는다. [formats]는 사용자 서식 번호와 문구, [xfs]는 칸 서식마다의 서식 번호다
Uint8List biff({
  List<String> strings = const [],
  int? split,
  Map<int, String> formats = const {},
  List<int> xfs = const [0],
  bool date1904 = false,
  bool password = false,
  int version = 0x0600,
  List<List<int>> cells = const [],
}) {
  List<int> sst() {
    final body = <int>[..._u32(strings.length), ..._u32(strings.length)];
    final last = strings.isEmpty ? '' : strings.last;
    for (final s
        in split == null ? strings : strings.sublist(0, strings.length - 1)) {
      body.addAll(ustr(s));
    }
    if (split == null) return rec(0x00FC, body);
    // 첫 조각은 두 바이트 글자, 이어지는 조각은 한 바이트 글자다
    final head = last.substring(0, split), tail = last.substring(split);
    body.addAll([
      ..._u16(last.length),
      1,
      for (final c in head.codeUnits) ..._u16(c),
    ]);
    return [
      ...rec(0x00FC, body),
      ...rec(0x003C, [0, ...tail.codeUnits]),
    ];
  }

  List<int> globals(int sheetAt) => [
    ...rec(0x0809, [
      ..._u16(version),
      ..._u16(0x0005),
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]),
    if (password) ...rec(0x002F, [0, 0, 1, 0, ...List.filled(48, 0)]),
    if (date1904) ...rec(0x0022, _u16(1)),
    for (final MapEntry(:key, :value) in formats.entries)
      ...rec(0x041E, [..._u16(key), ...ustr(value)]),
    for (final f in xfs)
      ...rec(0x00E0, [0, 0, ..._u16(f), ...List.filled(16, 0)]),
    ...rec(0x0085, [..._u32(sheetAt), 0, 0, ...ustr('Page', lenBytes: 1)]),
    ...sst(),
    ...rec(0x000A, []),
  ];
  final at = globals(0).length;
  return Uint8List.fromList([
    ...globals(at),
    ...rec(0x0809, [
      ..._u16(version),
      ..._u16(0x0010),
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]),
    for (final c in cells) ...c,
    ...rec(0x000A, []),
  ]);
}

/// OLE 복합 파일. 4096바이트보다 작은 흐름은 작은 흐름 표로 넣는다. [loop]면 흐름 사슬이 제 자신을 가리키고,
/// [outside]면 흐름의 첫 섹터가 파일 밖이다
Uint8List cfb(
  Uint8List stream, {
  String name = 'Workbook',
  bool loop = false,
  bool outside = false,
}) {
  const size = 512;
  final mini = stream.length < 4096;
  int sectorsOf(int n, int unit) => (n + unit - 1) ~/ unit;
  List<int> pad(List<int> b, int unit) => [
    ...b,
    ...List.filled(sectorsOf(b.length, unit) * unit - b.length, 0),
  ];

  // 섹터 차례: 0 사슬 표, 1 디렉터리, 미니면 2 작은 사슬 표와 3부터 작은 흐름 묶음, 아니면 2부터 흐름
  final body = mini ? pad(stream, 64) : stream.toList();
  final first = mini ? 3 : 2;
  final count = sectorsOf(body.length, size);
  final fat = List.filled(128, _free);
  fat[0] = _fatSect;
  fat[1] = _end;
  if (mini) fat[2] = _end;
  for (var k = 0; k < count; k++) {
    fat[first + k] = k == count - 1 ? _end : first + k + 1;
  }
  final miniCount = sectorsOf(stream.length, 64);
  final miniFat = List.filled(128, _free);
  if (mini) {
    for (var k = 0; k < miniCount; k++) {
      miniFat[k] = k == miniCount - 1 ? _end : k + 1;
    }
  }
  if (loop) (mini ? miniFat : fat)[mini ? 0 : first] = mini ? 0 : first;

  List<int> entry(
    String n,
    int type,
    int start,
    int bytes, {
    int child = _free,
  }) {
    final name = [for (final c in n.codeUnits) ..._u16(c), 0, 0];
    return [
      ...name,
      ...List.filled(64 - name.length, 0),
      ..._u16(name.length),
      type,
      1,
      ..._u32(_free),
      ..._u32(_free),
      ..._u32(child),
      ...List.filled(16 + 4 + 8 + 8, 0),
      ..._u32(start),
      ..._u32(bytes),
      0,
      0,
      0,
      0,
    ];
  }

  final streamStart = outside ? 9999 : (mini ? 0 : first);
  final dir = [
    ...entry(
      'Root Entry',
      5,
      mini ? first : _end,
      mini ? body.length : 0,
      child: 1,
    ),
    ...entry(name, 2, streamStart, stream.length),
    ...List.filled(256, 0),
  ];
  final header = [
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
    ...List.filled(16, 0),
    ..._u16(0x3E),
    ..._u16(3),
    ..._u16(0xFFFE),
    ..._u16(9),
    ..._u16(6),
    ...List.filled(6, 0),
    ..._u32(0),
    ..._u32(1),
    ..._u32(1),
    ..._u32(0),
    ..._u32(4096),
    ..._u32(mini ? 2 : _end),
    ..._u32(mini ? 1 : 0),
    ..._u32(_end),
    ..._u32(0),
    ..._u32(0),
    for (var k = 1; k < 109; k++) ..._u32(_free),
  ];
  return Uint8List.fromList([
    ...header,
    for (final v in fat) ..._u32(v),
    ...dir,
    if (mini)
      for (final v in miniFat) ..._u32(v),
    ...pad(body, size),
  ]);
}
