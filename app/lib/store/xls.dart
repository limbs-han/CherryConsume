/// 옛 엑셀 .xls 읽기. 엑셀 97~2003 파일은 여러 흐름을 한 파일에 담는 OLE 복합 파일이고, 그 안의 "Workbook" 흐름에
/// BIFF8 레코드로 표가 들어 있다. 첫 워크시트를 xlsx와 같은 행과 칸으로 돌려준다. 새 의존성 없이 쓴다. 작업 017 설계 1절
///
/// 파일은 사용자가 고른 것이라 믿지 않는다. 번호가 파일 밖을 가리키거나 사슬이 돌면 정해 둔 만큼만 따라가고 거절한다
library;

import 'dart:convert';
import 'dart:typed_data';

import 'imports.dart' show Unreadable, dateIds, fromExcel, isDateFormat;

const _broken = '파일이 깨져 읽지 못했어요';
const _locked = '비밀번호가 걸린 파일이라 읽지 못했어요. 카드사에서 비밀번호 없이 받거나 xlsx로 저장해 올려 주세요';

/// 옛 엑셀의 첫 워크시트. 칸 값은 글자, 정수나 소수, 참거짓, 날짜 서식이면 DateTime이나 Duration이다
List<List<Object?>> readXls(Uint8List data, {required String tooOld}) {
  try {
    final book = _stream(data, tooOld);
    return _sheet(book, tooOld);
  } on Unreadable {
    rethrow;
  } on RangeError {
    throw Unreadable(_broken);
  } on FormatException {
    throw Unreadable(_broken);
  }
}

const _end = 0xFFFFFFFE;

/// OLE 복합 파일에서 "Workbook" 흐름을 꺼낸다. "Book"만 있으면 BIFF5 이전이다
Uint8List _stream(Uint8List data, String tooOld) {
  final b = ByteData.sublistView(data);
  if (data.length < 512) throw Unreadable(_broken);
  final shift = b.getUint16(0x1E, Endian.little);
  if (shift != 9 && shift != 12) throw Unreadable(_broken);
  final size = 1 << shift;
  // 마지막 섹터를 다 채우지 않은 파일도 있다. 모자란 만큼은 흐름 길이로 거른다
  final sectors = (data.length - 1) ~/ size;
  Uint8List sector(int n) {
    if (n < 0 || n >= sectors) throw Unreadable(_broken);
    final at = (n + 1) * size;
    final end = at + size;
    return Uint8List.sublistView(
      data,
      at,
      end < data.length ? end : data.length,
    );
  }

  int u32(Uint8List s, int i) =>
      ByteData.sublistView(s).getUint32(i, Endian.little);

  // 사슬 표 섹터 목록. 머리의 109개와 이어진 목록 섹터들
  final fatIds = <int>[];
  for (var i = 0; i < 109; i++) {
    final id = b.getUint32(0x4C + i * 4, Endian.little);
    if (id < sectors) fatIds.add(id);
  }
  var difat = b.getUint32(0x44, Endian.little);
  for (var hops = 0; difat != _end && difat < sectors; hops++) {
    if (hops > sectors) throw Unreadable(_broken);
    final s = sector(difat);
    for (var i = 0; i < size ~/ 4 - 1; i++) {
      final id = u32(s, i * 4);
      if (id < sectors) fatIds.add(id);
    }
    difat = u32(s, size - 4);
  }
  if (fatIds.length > sectors) throw Unreadable(_broken);
  final fat = <int>[
    for (final id in fatIds)
      for (var i = 0; i < size ~/ 4; i++) u32(sector(id), i * 4),
  ];

  // 사슬을 따라 섹터를 잇는다. 섹터 수보다 많이 따라가면 사슬이 도는 것이다
  Uint8List chain(
    int start,
    List<int> table,
    Uint8List Function(int) at,
    int unit,
  ) {
    final out = BytesBuilder(copy: false);
    var n = start;
    for (var hops = 0; n != _end; hops++) {
      if (hops > table.length || n < 0 || n >= table.length) {
        throw Unreadable(_broken);
      }
      out.add(at(n));
      n = table[n];
    }
    return out.takeBytes();
  }

  final dir = chain(b.getUint32(0x30, Endian.little), fat, sector, size);
  final cutoff = b.getUint32(0x38, Endian.little);
  final miniFat = <int>[];
  final miniStart = b.getUint32(0x3C, Endian.little);
  if (miniStart != _end && miniStart < sectors) {
    final m = chain(miniStart, fat, sector, size);
    for (var i = 0; i + 4 <= m.length; i += 4) {
      miniFat.add(u32(m, i));
    }
  }
  // 흐름 이름과 종류, 시작 섹터, 길이. 이름은 규격대로 대소문자를 가리지 않는다
  ({String name, int type, int start, int bytes})? entryAt(int e) {
    if (e + 128 > dir.length) return null;
    final eb = ByteData.sublistView(dir, e, e + 128);
    final len = eb.getUint16(0x40, Endian.little);
    if (len < 2 || len > 64) return null;
    return (
      name: String.fromCharCodes([
        for (var i = 0; i + 1 < len - 1; i += 2) eb.getUint16(i, Endian.little),
      ]).toLowerCase(),
      type: eb.getUint8(0x42),
      start: eb.getUint32(0x74, Endian.little),
      bytes: eb.getUint32(0x78, Endian.little),
    );
  }

  // 작은 흐름 묶음은 0번 뿌리 항목 하나뿐이다. 흐름은 처음 찾은 Workbook 하나만 읽는다. 항목마다 흐름을 다시 따라가면
  // 깨진 2MB 파일 하나로 수십 GB를 복사해 화면이 멈춘다. 단계 1 위험 검토 중간 1
  final root = entryAt(0);
  if (root == null || root.type != 5) throw Unreadable(_broken);
  var old = false;
  for (var e = 128; e + 128 <= dir.length; e += 128) {
    final entry = entryAt(e);
    if (entry == null || entry.type != 2) continue;
    if (entry.name == 'book') old = true;
    if (entry.name != 'workbook') continue;
    final Uint8List s;
    if (entry.bytes < cutoff) {
      final mini = chain(root.start, fat, sector, size);
      s = chain(entry.start, miniFat, (k) {
        if ((k + 1) * 64 > mini.length) throw Unreadable(_broken);
        return Uint8List.sublistView(mini, k * 64, k * 64 + 64);
      }, 64);
    } else {
      s = chain(entry.start, fat, sector, size);
    }
    if (entry.bytes > s.length) throw Unreadable(_broken);
    return Uint8List.sublistView(s, 0, entry.bytes);
  }
  throw Unreadable(old ? tooOld : _broken);
}

/// 칸 오류 번호와 글자. xlsx를 읽을 때처럼 오류 칸은 이 글자다. 단계 1 위험 검토 낮음 3
const _errors = {
  0x00: '#NULL!',
  0x07: '#DIV/0!',
  0x0F: '#VALUE!',
  0x17: '#REF!',
  0x1D: '#NAME?',
  0x24: '#NUM!',
  0x2A: '#N/A',
};

/// BIFF8 레코드 하나
typedef _Rec = ({int id, Uint8List data, int at});

List<_Rec> _records(Uint8List book, int from) {
  final b = ByteData.sublistView(book);
  final out = <_Rec>[];
  var i = from;
  while (i + 4 <= book.length) {
    final id = b.getUint16(i, Endian.little),
        len = b.getUint16(i + 2, Endian.little);
    if (len > 8224 || i + 4 + len > book.length) throw Unreadable(_broken);
    out.add((
      id: id,
      data: Uint8List.sublistView(book, i + 4, i + 4 + len),
      at: i,
    ));
    i += 4 + len;
    if (id == 0x000A) break;
  }
  return out;
}

/// 레코드 경계를 넘어 이어지는 바이트를 읽는다. 공유 글자 표는 CONTINUE 레코드로 이어지고, 글자가 경계에서 끊기면 다음
/// 조각의 첫 바이트가 그 글자의 새 압축 표시다
class _Reader {
  _Reader(this.chunks);
  final List<Uint8List> chunks;
  int c = 0, i = 0;

  bool get atChunkEnd => i >= chunks[c].length;
  void _next() {
    c++;
    i = 0;
    if (c >= chunks.length) throw Unreadable(_broken);
  }

  int u8() {
    if (atChunkEnd) _next();
    return chunks[c][i++];
  }

  int u16() => u8() | (u8() << 8);
  int u32() => u16() | (u16() << 16);
  void skip(int n) {
    for (var k = 0; k < n; k++) {
      u8();
    }
  }

  /// XLUnicodeRichExtendedString
  String string() {
    final cch = u16();
    var flags = u8();
    final runs = flags & 0x08 != 0 ? u16() : 0;
    final ext = flags & 0x04 != 0 ? u32() : 0;
    final codes = <int>[];
    while (codes.length < cch) {
      if (atChunkEnd) {
        _next();
        flags = chunks[c][i++];
      }
      codes.add(flags & 0x01 != 0 ? u16() : u8());
    }
    skip(runs * 4 + ext);
    return String.fromCharCodes(codes);
  }
}

/// 한 레코드 안의 XLUnicodeString. 공유 글자 표 밖의 글자다
String _plain(Uint8List d, int at) {
  final b = ByteData.sublistView(d);
  final cch = b.getUint16(at, Endian.little);
  final high = d[at + 2] & 0x01 != 0;
  final start = at + 3;
  return high
      ? String.fromCharCodes([
          for (var k = 0; k < cch; k++)
            b.getUint16(start + k * 2, Endian.little),
        ])
      : latin1.decode(Uint8List.sublistView(d, start, start + cch));
}

/// RK 값. 정수이거나 소수의 위 32비트이고, 100으로 나누는 표시가 있다
num _rk(int rk) {
  num v;
  if (rk & 0x02 != 0) {
    v = rk.toSigned(32) >> 2;
  } else {
    final b = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
    v = b.getFloat64(0, Endian.little);
  }
  return rk & 0x01 != 0 ? v / 100 : v;
}

List<List<Object?>> _sheet(Uint8List book, String tooOld) {
  final globals = _records(book, 0);
  if (globals.isEmpty || globals.first.id != 0x0809) throw Unreadable(_broken);
  if (ByteData.sublistView(globals.first.data).getUint16(0, Endian.little) !=
      0x0600) {
    throw Unreadable(tooOld);
  }
  final formats = <int, String>{};
  final xfFormats = <int>[];
  var epoch = DateTime.utc(1899, 12, 30);
  int? sheetAt;
  var strings = const <String>[];
  for (final (k, r) in globals.indexed) {
    final b = ByteData.sublistView(r.data);
    switch (r.id) {
      case 0x002F:
        throw Unreadable(_locked);
      case 0x0022 when b.getUint16(0, Endian.little) == 1:
        epoch = DateTime.utc(1904);
      case 0x041E:
        formats[b.getUint16(0, Endian.little)] = _plain(r.data, 2);
      case 0x00E0:
        xfFormats.add(b.getUint16(2, Endian.little));
      case 0x0085 when sheetAt == null && r.data[5] == 0:
        sheetAt = b.getUint32(0, Endian.little);
      case 0x00FC:
        final chunks = [Uint8List.sublistView(r.data, 8)];
        for (final c in globals.skip(k + 1)) {
          if (c.id != 0x003C) break;
          chunks.add(c.data);
        }
        final unique = b.getUint32(4, Endian.little);
        if (unique > 200000) throw Unreadable(_broken);
        final reader = _Reader(chunks);
        strings = [for (var n = 0; n < unique; n++) reader.string()];
    }
  }
  final at = sheetAt;
  if (at == null || at >= book.length) throw Unreadable(_broken);
  bool isDate(int xf) {
    if (xf >= xfFormats.length) return false;
    final id = xfFormats[xf];
    final custom = formats[id];
    return custom != null ? isDateFormat(custom) : dateIds.contains(id);
  }

  Object number(num n, int xf) {
    if (isDate(xf)) return fromExcel(n, epoch);
    return n is double && n == n.roundToDouble() && n.abs() < 9007199254740992
        ? n.toInt()
        : n;
  }

  final cells = <int, Map<int, Object?>>{};
  void put(int row, int col, Object? v) {
    if (row > 65535 || col > 255) throw Unreadable(_broken);
    (cells[row] ??= {})[col] = v;
  }

  ({int row, int col})? pending;
  for (final r in _records(book, at)) {
    final d = r.data;
    final b = ByteData.sublistView(d);
    int u16(int i) => b.getUint16(i, Endian.little);
    switch (r.id) {
      case 0x00FD:
        final n = b.getUint32(6, Endian.little);
        if (n >= strings.length) throw Unreadable(_broken);
        put(u16(0), u16(2), strings[n]);
      case 0x0204:
        put(u16(0), u16(2), _plain(d, 6));
      case 0x0203:
        put(u16(0), u16(2), number(b.getFloat64(6, Endian.little), u16(4)));
      case 0x027E:
        put(u16(0), u16(2), number(_rk(b.getUint32(6, Endian.little)), u16(4)));
      case 0x00BD:
        final row = u16(0), first = u16(2);
        final count = (d.length - 6) ~/ 6;
        for (var k = 0; k < count; k++) {
          final xf = u16(4 + k * 6);
          put(
            row,
            first + k,
            number(_rk(b.getUint32(6 + k * 6, Endian.little)), xf),
          );
        }
      case 0x0006:
        final row = u16(0), col = u16(2);
        if (u16(12) == 0xFFFF) {
          switch (d[6]) {
            case 0:
              pending = (row: row, col: col);
            case 1:
              put(row, col, d[8] != 0);
            case 2:
              put(row, col, _errors[d[8]] ?? '#VALUE!');
            case 3:
              put(row, col, '');
          }
        } else {
          put(row, col, number(b.getFloat64(6, Endian.little), u16(4)));
        }
      case 0x0207:
        final p = pending;
        if (p != null) put(p.row, p.col, _plain(d, 0));
        pending = null;
      case 0x0205:
        put(u16(0), u16(2), d[7] == 0 ? d[6] != 0 : _errors[d[6]] ?? '#VALUE!');
    }
  }
  if (cells.isEmpty) return [];
  final last = cells.keys.reduce((a, b) => a > b ? a : b);
  return [
    for (var row = 0; row <= last; row++)
      if (cells[row] case final c?)
        [
          for (
            var col = 0;
            col <= c.keys.reduce((a, b) => a > b ? a : b);
            col++
          )
            c[col],
        ]
      else
        const <Object?>[],
  ];
}
