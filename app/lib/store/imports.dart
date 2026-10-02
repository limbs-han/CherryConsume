/// 이용 내역 엑셀 가져오기의 파일 읽기. csv, xlsx, html 표로 된 xls. 서버 `cherry_api/imports.py`를 옮겼다.
/// 작업 005 설계 5f, 작업 006 설계 5절
///
/// 파일은 메모리에서 읽고 저장하지 않는다. E35. 칸 값은 String, int, double, bool, 날짜와 시각인 DateTime,
/// 시각만 있는 Duration이다. DateTime은 시간대 없는 벽시계 값을 UTC 칸에 둔다
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:archive/archive.dart' show InputMemoryStream, ZipDirectory;
import 'package:cp949_codec/cp949_codec.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml_events.dart';

const maxRows = 3000;
const maxCols = 60;

/// xlsx를 풀었을 때의 크기. 몇 KB짜리 파일이 수 GB로 풀리는 압축 폭탄을 막는다
const maxUnzipped = 30000000;

/// 열 이름 사전. 띄어쓰기와 괄호 안을 뺀 이름으로 맞춘다. 앞에 있는 이름이 먼저다
/// ponytail: 흔한 이름만 넣었다. 카드사 실제 파일을 받으면 카드사별 매핑 표로 채운다
const names = {
  'date': [
    '이용일자',
    '이용일',
    '승인일자',
    '승인일',
    '거래일자',
    '거래일',
    '사용일자',
    '사용일',
    '이용일시',
    '승인일시',
    '거래일시',
  ],
  'time': ['이용시간', '승인시간', '거래시간', '사용시간', '이용시각', '승인시각', '시간'],
  'merchant': ['가맹점명', '이용가맹점', '이용하신가맹점', '가맹점', '이용처', '사용처', '거래처'],
  'amount': ['이용금액', '승인금액', '거래금액', '사용금액', '결제금액', '금액'],
  'installment': ['할부개월', '할부기간', '할부개월수', '할부', '이용구분'],
  'cancel': ['취소여부', '승인구분', '취소구분', '상태', '거래구분', '구분'],
  'approval': ['승인번호'],
  'card': ['카드명', '이용카드', '카드이름', '카드'],
  'interest_free': ['무이자여부', '무이자구분', '무이자'],
  'region': ['해외여부', '국내외구분', '국내외', '해외구분', '이용국가'],
};
const required = ['date', 'merchant', 'amount'];

/// 읽을 수 없는 파일. 문구는 앱이 그대로 보인다
class Unreadable implements Exception {
  Unreadable(this.message);
  final String message;

  @override
  String toString() => message;
}

class ImportRow {
  ImportRow(this.line, {this.day, this.merchant = ''});
  final int line;
  DateTime? day;
  Duration? at;
  String merchant;
  int amount = 0;
  bool cancel = false;
  int installmentMonths = 1;
  String? approvalNo;
  String? card;

  /// 할부인데 무이자인지 모르면 null이다. 유이자로 넣고 미리보기에 알린다. 2026-10-02 사용자가 정했다
  bool? interestFree = false;
  bool overseas = false;
  String? error;
}

/// Python `str(v or "")`. 빈 값, 0, 거짓은 빈 글자다
String pyStr(Object? v) => switch (v) {
  null || false || 0 || 0.0 || '' => '',
  true => 'True',
  final DateTime d =>
    '${_four(d.year)}-${_two(d.month)}-${_two(d.day)} ${_clock(d.hour, d.minute, d.second, d.millisecond * 1000 + d.microsecond)}',
  final Duration t => _clock(
    t.inHours,
    t.inMinutes % 60,
    t.inSeconds % 60,
    t.inMicroseconds % 1000000,
  ),
  _ => '$v',
};

String _two(int n) => n.toString().padLeft(2, '0');
String _four(int n) => n.toString().padLeft(4, '0');
String _clock(int h, int m, int s, int micro) =>
    '${_two(h)}:${_two(m)}:${_two(s)}${micro == 0 ? '' : '.${micro.toString().padLeft(6, '0')}'}';

final _bracket = RegExp(r'\(.*?\)|\[.*?\]|\s');
String norm(Object? name) => pyStr(name).replaceAll(_bracket, '');

/// 머리 줄 모양의 sha256. 사용자가 짝지은 열을 같은 모양의 다음 파일에 다시 쓴다. E30
///
/// 머리 줄이 이름이나 카드번호가 적힌 줄일 수 있어 글자를 남기지 않는다. 빈 칸도 자리로 넣어 열이 밀리면 다른
/// 모양이다. 서버는 사용자마다 다른 값을 앞에 섞었다. 폰 안에서는 섞을 까닭이 없어 빈 값이다. 작업 006 설계 5절
String signature(List<Object?> headers) =>
    sha256.convert(utf8.encode('|${headers.map(norm).join('|')}')).toString();

final _tooMany = '행이 ${_comma(maxRows)}개보다 많아요. 기간을 나눠 올려 주세요';
String _comma(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

bool _filled(List<Object?> r) => r.any((c) => pyStr(c).trim().isNotEmpty);

/// 파일을 행 목록으로. 칸은 글자나 숫자, 날짜다
List<List<Object?>> readTable(Uint8List data) {
  List<List<Object?>> rows;
  if (_starts(data, const [0x50, 0x4b])) {
    rows = _xlsx(data);
  } else if (_starts(data, const [0xd0, 0xcf, 0x11, 0xe0])) {
    throw Unreadable('옛 엑셀 형식이라 읽지 못했어요. 엑셀에서 xlsx나 csv로 저장해 올려 주세요');
  } else {
    final text = _text(data);
    final lower = text.toLowerCase();
    // 행을 만들기 전에 센다. 줄바꿈만 수백만 개인 파일이 메모리를 다 쓰지 않게 한다
    if (text.trimLeft().startsWith('<') && lower.contains('<table')) {
      // html 파서는 `<tr>` 없이 온 칸에도 줄을 만든다. 칸 수도 센다. 단계 5 위험 검토 4번
      if ('<tr'.allMatches(lower).length > maxRows + 20 ||
          _cell.allMatches(lower).length > (maxRows + 20) * maxCols) {
        throw Unreadable(_tooMany);
      }
      rows = _html(text);
    } else {
      if ('\n'.allMatches(text).length > (maxRows + 20) * 4) {
        throw Unreadable(_tooMany);
      }
      rows = _csv(text);
    }
  }
  // 60열에서 자른 뒤 빈 줄을 거른다. 61번째 열 뒤에만 값이 있는 줄은 빈 줄이다. 서버와 같은 순서다
  rows = [
    for (final r in rows)
      if (r.length > maxCols ? r.sublist(0, maxCols) : r case final c
          when _filled(c))
        c,
  ];
  if (rows.length > maxRows + 20) throw Unreadable(_tooMany);
  return rows;
}

final _cell = RegExp(r'<t[dh][\s>/]');

bool _starts(Uint8List data, List<int> head) =>
    data.length >= head.length &&
    [for (var i = 0; i < head.length; i++) data[i] == head[i]].every((b) => b);

String _text(Uint8List data) {
  try {
    final s = utf8.decode(data);
    // utf-8-sig처럼 앞의 BOM 하나를 뗀다
    return s.startsWith('﻿') ? s.substring(1) : s;
  } on FormatException {
    try {
      return cp949.decode(data);
    } catch (_) {
      throw Unreadable('글자를 읽지 못했어요. UTF-8이나 CP949로 저장한 파일을 올려 주세요');
    }
  }
}

/// html 표. 칸 안의 글자를 띄어쓰기 하나로 이어 붙인다
List<List<Object?>> _html(String text) => [
  for (final tr in html.parse(text).querySelectorAll('tr'))
    [
      for (final cell in tr.children)
        if (cell.localName == 'td' || cell.localName == 'th')
          cell.text.trim().split(RegExp(r'\s+')).join(' '),
    ],
];

const _fieldLimit = 131072;

/// Python csv 모듈의 기본 방식. 쉼표로 가르고 따옴표 안의 쉼표와 줄바꿈은 글자로 둔다. `""`는 따옴표 하나다.
/// 줄은 `\n`에서 나눠 읽고, 따옴표 밖의 줄 가운데 CR은 읽지 않는다. 칸 하나는 131,072자까지다
List<List<String>> _csv(String text) {
  const eol = -1, quote = 0x22, comma = 0x2c, cr = 0x0d, lf = 0x0a;
  final rows = <List<String>>[];
  var fields = <String>[];
  final field = StringBuffer();
  var len = 0;
  var state = _Csv.startRecord;
  final bad = Unreadable('csv 파일을 읽지 못했어요');

  void save() {
    fields.add(field.toString());
    field.clear();
    len = 0;
  }

  void add(int c) {
    if (++len > _fieldLimit) throw bad;
    field.writeCharCode(c);
  }

  void endField(int c) {
    save();
    state = c == eol ? _Csv.startRecord : _Csv.eatCrlf;
  }

  void step(int c) {
    switch (state) {
      case _Csv.startRecord:
        if (c == eol) return;
        if (c == lf || c == cr) {
          state = _Csv.eatCrlf;
          return;
        }
        state = _Csv.startField;
        step(c);
      case _Csv.startField:
        if (c == lf || c == cr || c == eol) {
          endField(c);
        } else if (c == quote) {
          state = _Csv.inQuoted;
        } else if (c == comma) {
          save();
        } else {
          add(c);
          state = _Csv.inField;
        }
      case _Csv.inField:
        if (c == lf || c == cr || c == eol) {
          endField(c);
        } else if (c == comma) {
          save();
          state = _Csv.startField;
        } else {
          add(c);
        }
      case _Csv.inQuoted:
        if (c == eol) return;
        if (c == quote) {
          state = _Csv.quoteInQuoted;
        } else {
          add(c);
        }
      case _Csv.quoteInQuoted:
        if (c == quote) {
          add(c);
          state = _Csv.inQuoted;
        } else if (c == comma) {
          save();
          state = _Csv.startField;
        } else if (c == lf || c == cr || c == eol) {
          endField(c);
        } else {
          add(c);
          state = _Csv.inField;
        }
      case _Csv.eatCrlf:
        if (c == lf || c == cr) return;
        if (c == eol) {
          state = _Csv.startRecord;
          return;
        }
        throw bad;
    }
  }

  var i = 0;
  while (i < text.length) {
    final n = text.indexOf('\n', i);
    final j = n < 0 ? text.length : n + 1;
    for (final c in text.substring(i, j).runes) {
      step(c);
    }
    step(eol);
    if (state == _Csv.startRecord) {
      rows.add(fields);
      fields = [];
    }
    i = j;
  }
  // 따옴표가 닫히지 않은 채 끝나면 그때까지를 칸 하나로 둔다
  if (len != 0 || state == _Csv.inQuoted) {
    save();
    rows.add(fields);
  }
  return rows;
}

enum _Csv { startRecord, startField, inField, inQuoted, quoteInQuoted, eatCrlf }

/// 쓴 만큼 세다가 넘으면 멈춘다
class _Budget {
  int left = maxUnzipped;
  void spend(int n) {
    left -= n;
    if (left < 0) throw Unreadable('엑셀 파일이 너무 커요. 기간을 나눠 올려 주세요');
  }
}

class _Counted implements Sink<List<int>> {
  _Counted(this.budget);
  final _Budget budget;
  final out = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    budget.spend(chunk.length);
    out.add(chunk);
  }

  @override
  void close() {}
}

/// xlsx를 실제로 풀며 크기를 센다. 목차에 적힌 크기는 꾸밀 수 있다. 보통 쓰는 두 방식만 받는다. 압축 폭탄을 막는다.
/// archive는 목차만 읽는다. archive의 풀기는 다 푼 뒤에 넘겨 주어 도중에 셀 수 없다. ZipDecoder는 바로가기로 적힌
/// 항목을 읽을 때 그 자리에서 다 풀어 쓰지 않는다. 그 길로 2MB 파일이 2GB로 풀릴 수 있다. 단계 5 위험 검토 1번
Map<String, Uint8List> _unzip(Uint8List data) {
  final bad = Unreadable('엑셀 파일을 읽지 못했어요');
  final zip = ZipDirectory();
  try {
    zip.read(InputMemoryStream(data));
  } catch (_) {
    throw bad;
  }
  final budget = _Budget();
  final files = <String, Uint8List>{};
  for (final h in zip.fileHeaders) {
    // 암호를 건 항목, 저장과 deflate가 아닌 압축. 암호는 중앙 목차와 지역 머리 둘 다 본다. 지역 머리에만 있으면 archive가
    // 암호를 풀려다 던진다
    if (h.generalPurposeBitFlag & 1 != 0 ||
        (h.file?.flags ?? 0) & 1 != 0 ||
        (h.compressionMethod != 0 && h.compressionMethod != 8)) {
      throw bad;
    }
    final Uint8List raw;
    try {
      raw = h.file?.getStream(decompress: false).toUint8List() ?? Uint8List(0);
    } catch (_) {
      throw bad;
    }
    final Uint8List content;
    if (h.compressionMethod == 0) {
      budget.spend(raw.length);
      content = raw;
    } else {
      final sink = _Counted(budget);
      try {
        final inflate = ZLibDecoder(raw: true).startChunkedConversion(sink);
        for (var i = 0; i < raw.length; i += 1 << 16) {
          inflate.add(
            raw.sublist(
              i,
              i + (1 << 16) > raw.length ? raw.length : i + (1 << 16),
            ),
          );
        }
        inflate.close();
      } on Unreadable {
        rethrow;
      } catch (_) {
        throw bad;
      }
      content = sink.out.takeBytes();
    }
    files[h.filename] = content;
  }
  return files;
}

/// 엑셀이 날짜로 보이는 기본 서식 번호. openpyxl의 BUILTIN_FORMATS 가운데 날짜인 것과, 한국어 엑셀이 날짜에 쓰는
/// 27~36, 50~58이다. openpyxl은 27~36, 50~58을 모르는 서식으로 보아 날짜를 숫자로 읽는다. 작업 006 설계 5절
const _dateIds = {
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  45,
  46,
  47,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  50,
  51,
  52,
  53,
  54,
  55,
  56,
  57,
  58,
};

final _literal = RegExp(r'".*?"|\[(?!hh?\]|mm?\]|ss?\])[^\]]*\]');
final _dateLetter = RegExp(r'(?<![_\\])[dmhysDMHYS]');

/// openpyxl `is_date_format`. 첫 서식만 보고 따옴표 안 글자와 대괄호 안 지역 표시를 뺀 뒤 날짜 글자가 있으면 날짜다
bool isDateFormat(String fmt) =>
    _dateLetter.hasMatch(fmt.split(';').first.replaceAll(_literal, ''));

final _windowsEpoch = DateTime.utc(1899, 12, 30);
final _macEpoch = DateTime.utc(1904);

/// openpyxl `from_excel`. 1 미만은 시각만, 그 밖은 날짜와 시각이다. 1900년 1~2월은 엑셀이 없는 2월 29일을 세어 하루를
/// 더한다. 날짜로 둘 수 없는 값은 openpyxl처럼 "#VALUE!"다
/// ponytail: `[h]:mm` 같은 경과 시간 서식도 시각으로 읽는다. openpyxl은 경과 시간으로 읽는다. 카드 내역에 쓰이면 고친다
Object fromExcel(num value, DateTime epoch) {
  // 1만 년을 넘는 수는 날짜가 아니다. Duration이 넘치기 전에 막는다
  if (!value.isFinite || value.abs() > 4000000) return '#VALUE!';
  var day = value.floor();
  final ms = pyRound(((value - day) * 86400 * 1000).toDouble());
  final diff = Duration(milliseconds: ms);
  if (value >= 0 && value < 1 && diff.inDays == 0) return diff;
  if (value > 0 && value < 60 && epoch == _windowsEpoch) day += 1;
  final at = epoch.add(Duration(days: day)).add(diff);
  return at.year < 1 || at.year > 9999 ? '#VALUE!' : at;
}

/// Python `round()`. .5는 짝수 쪽으로 간다
int pyRound(double x) {
  final f = x.floorToDouble();
  final d = x - f;
  final n = f.toInt();
  return d > 0.5 || (d == 0.5 && n.isOdd) ? n + 1 : n;
}

String _xmlText(Uint8List bytes) => utf8.decode(bytes, allowMalformed: false);

Iterable<XmlEvent> _events(Uint8List bytes) => parseEvents(_xmlText(bytes));

String? _attr(XmlStartElementEvent e, String local) {
  for (final a in e.attributes) {
    if (a.localName == local) return a.value;
  }
  return null;
}

/// 관계 파일. {id: (종류 끝 이름, 경로)}. 경로는 관계 파일이 가리키는 파일의 폴더에서 센다
Map<String, (String, String)> _rels(Map<String, Uint8List> files, String part) {
  final slash = part.lastIndexOf('/');
  final dir = slash < 0 ? '' : part.substring(0, slash + 1);
  final bytes = files['${dir}_rels/${part.substring(slash + 1)}.rels'];
  if (bytes == null) return {};
  return {
    for (final e in _events(bytes).whereType<XmlStartElementEvent>())
      if (e.localName == 'Relationship')
        _attr(e, 'Id')!: (
          _attr(e, 'Type')!.split('/').last,
          _resolve(dir, _attr(e, 'Target')!),
        ),
  };
}

String _resolve(String dir, String target) {
  final parts = target.startsWith('/')
      ? <String>[]
      : dir.split('/').where((p) => p.isNotEmpty).toList();
  for (final p in target.split('/')) {
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (p.isNotEmpty && p != '.') {
      parts.add(p);
    }
  }
  return parts.join('/');
}

/// 첫 시트의 행. 행 번호와 열 번호는 1부터다. 시트 머리에 적힌 크기를 믿지 않는다. 행과 열을 정해 둔 만큼만 읽는다
List<List<Object?>> _xlsx(Uint8List data) {
  final files = _unzip(data);
  try {
    return _sheet(files);
  } on Unreadable {
    rethrow;
  } catch (_) {
    throw Unreadable('엑셀 파일을 읽지 못했어요');
  }
}

List<List<Object?>> _sheet(Map<String, Uint8List> files) {
  final book = _rels(
    files,
    '',
  ).values.firstWhere((r) => r.$1 == 'officeDocument').$2;
  final bookRels = _rels(files, book);
  var epoch = _windowsEpoch;
  String? first;
  for (final e in _events(files[book]!).whereType<XmlStartElementEvent>()) {
    if (e.localName == 'workbookPr' &&
        const {'1', 'true'}.contains(_attr(e, 'date1904'))) {
      epoch = _macEpoch;
    }
    if (e.localName == 'sheet' && first == null) {
      final rel = bookRels[_attr(e, 'id')];
      if (rel != null && rel.$1 == 'worksheet') first = rel.$2;
    }
  }
  String? part(String type) =>
      bookRels.values.where((r) => r.$1 == type).firstOrNull?.$2;
  final strings = _strings(files[part('sharedStrings')]);
  final dates = _dateStyles(files[part('styles')]);

  const limit = maxRows + 30;
  final rows = <int, List<Object?>>{};
  var last = 0;
  var rowNo = 0, colNo = 0;
  List<Object?>? row;
  // 칸 하나를 읽는 동안의 값
  String? type;
  var style = 0;
  var col = 0;
  StringBuffer? v, inline;
  var inV = false, inIs = false, inT = false, inRph = false;

  for (final e in _events(files[first]!)) {
    if (e is XmlStartElementEvent) {
      switch (e.localName) {
        case 'row':
          final r = _attr(e, 'r');
          rowNo = r == null ? rowNo + 1 : int.parse(r);
          colNo = 0;
          if (rowNo > limit) break;
          row = List.filled(maxCols, null);
          if (e.isSelfClosing) {
            rows[rowNo] = row;
            last = rowNo;
            row = null;
          }
        case 'c':
          final ref = _attr(e, 'r');
          colNo = ref == null ? colNo + 1 : _column(ref);
          col = colNo;
          type = _attr(e, 't') ?? 'n';
          style = int.tryParse(_attr(e, 's') ?? '') ?? 0;
          v = null;
          inline = null;
          if (e.isSelfClosing) _put(row, col, null);
        case 'v':
          inV = !e.isSelfClosing;
          v = StringBuffer();
        case 'is':
          inIs = !e.isSelfClosing;
          inline = StringBuffer();
        case 'rPh':
          inRph = !e.isSelfClosing;
        case 't':
          inT = inIs && !inRph && !e.isSelfClosing;
      }
      if (rowNo > limit) break;
    } else if (e is XmlEndElementEvent) {
      switch (e.localName) {
        case 'v':
          inV = false;
        case 'is':
          inIs = false;
        case 'rPh':
          inRph = false;
        case 't':
          inT = false;
        case 'c':
          _put(
            row,
            col,
            _value(
              type!,
              v?.toString(),
              inline?.toString(),
              style,
              strings,
              dates,
              epoch,
            ),
          );
        case 'row':
          if (row != null) {
            rows[rowNo] = row;
            last = rowNo;
            row = null;
          }
      }
    } else if (e is XmlTextEvent || e is XmlCDATAEvent) {
      final s = e is XmlTextEvent ? e.value : (e as XmlCDATAEvent).value;
      if (inV) v!.write(s);
      if (inT) inline!.write(s);
    }
  }
  // 정해 둔 줄 끝까지 읽었는데 마지막 줄들에 값이 있으면 뒤에 행이 더 있다. 말없이 자르지 않는다
  if (rowNo >= limit &&
      [
        for (var i = limit - 9; i <= limit; i++) rows[i],
      ].any((r) => r != null && _filled(r))) {
    throw Unreadable(_tooMany);
  }
  return [
    for (var i = 1; i <= (last > limit ? limit : last); i++)
      rows[i] ?? const [],
  ];
}

void _put(List<Object?>? row, int col, Object? value) {
  if (row != null && col >= 1 && col <= maxCols) row[col - 1] = value;
}

/// "AB12"의 열 번호 28
int _column(String ref) {
  var n = 0;
  for (final c in ref.toUpperCase().codeUnits) {
    if (c < 0x41 || c > 0x5a) break;
    n = n * 26 + c - 0x40;
  }
  return n;
}

/// openpyxl `parse_cell`을 data_only로 읽을 때와 같다. 수식은 저장된 값을 쓴다
Object? _value(
  String type,
  String? v,
  String? inline,
  int style,
  List<String> strings,
  Set<int> dates,
  DateTime epoch,
) {
  if (type == 'inlineStr') return inline;
  if (v == null || v.isEmpty) return null;
  switch (type) {
    case 'n':
      final t = v.trim();
      final num n = t.contains(RegExp('[.Ee]'))
          ? double.parse(t)
          : (int.tryParse(t) ?? double.parse(t));
      return dates.contains(style) ? fromExcel(n, epoch) : n;
    case 's':
      return strings[int.parse(v.trim())];
    case 'b':
      return int.parse(v.trim()) != 0;
    case 'd':
      final d = DateTime.parse(v.trim());
      return DateTime.utc(
        d.year,
        d.month,
        d.day,
        d.hour,
        d.minute,
        d.second,
        d.millisecond,
        d.microsecond,
      );
    default:
      return v;
  }
}

/// 공유 글자 표. 덧붙인 읽는 법 rPh는 뺀다
List<String> _strings(Uint8List? bytes) {
  if (bytes == null) return const [];
  final out = <String>[];
  StringBuffer? si;
  var inT = false, inRph = false;
  for (final e in _events(bytes)) {
    if (e is XmlStartElementEvent) {
      switch (e.localName) {
        case 'si':
          si = StringBuffer();
          if (e.isSelfClosing) {
            out.add('');
            si = null;
          }
        case 'rPh':
          inRph = !e.isSelfClosing;
        case 't':
          inT = si != null && !inRph && !e.isSelfClosing;
      }
    } else if (e is XmlEndElementEvent) {
      switch (e.localName) {
        case 'si':
          out.add(si.toString());
          si = null;
        case 'rPh':
          inRph = false;
        case 't':
          inT = false;
      }
    } else if (inT && (e is XmlTextEvent || e is XmlCDATAEvent)) {
      si!.write(e is XmlTextEvent ? e.value : (e as XmlCDATAEvent).value);
    }
  }
  return out;
}

/// 날짜 서식을 쓰는 칸 서식 번호. cellXfs의 순서가 칸의 s다
Set<int> _dateStyles(Uint8List? bytes) {
  if (bytes == null) return const {};
  final custom = <int, String>{};
  final out = <int>{};
  var inXfs = false;
  var index = 0;
  for (final e in _events(bytes)) {
    if (e is XmlStartElementEvent) {
      switch (e.localName) {
        case 'numFmt':
          custom[int.parse(_attr(e, 'numFmtId')!)] =
              _attr(e, 'formatCode') ?? '';
        case 'cellXfs':
          inXfs = !e.isSelfClosing;
        case 'xf' when inXfs:
          final id = int.tryParse(_attr(e, 'numFmtId') ?? '') ?? 0;
          final fmt = custom[id];
          if (fmt != null ? isDateFormat(fmt) : _dateIds.contains(id)) {
            out.add(index);
          }
          index++;
      }
    } else if (e is XmlEndElementEvent && e.localName == 'cellXfs') {
      inXfs = false;
    }
  }
  return out;
}

/// 짝짓기 화면에서 머리 줄을 고를 위 10줄
List<List<String>> topRows(List<List<Object?>> table) => [
  for (final r in table.take(10)) [for (final c in r) pyStr(c).trim()],
];

/// 열 이름을 못 찾을 때 짝짓기 화면에 보일 줄. 위 20줄에서 칸이 셋 이상인 첫 줄이다
int topRow(List<List<Object?>> table) {
  for (final (i, r) in table.take(20).indexed) {
    if (r.where((c) => pyStr(c).trim().isNotEmpty).length >= 3) return i;
  }
  return 0;
}

/// 머리 줄과 열 짝 {칸: 열 번호}. mapping은 사용자가 짝지은 {"row": 줄, "columns": {칸: 열 번호}}다.
/// 사전으로 못 찾으면 (null, null)이다. E30
(int?, Map<String, int>?) findHeader(
  List<List<Object?>> table, [
  Map<String, Object?>? mapping,
]) {
  if (mapping != null) {
    final row = mapping['row'], cols = mapping['columns'];
    final ok =
        row is int &&
        row >= 0 &&
        row < (table.length < 20 ? table.length : 20) &&
        cols is Map &&
        cols.keys.every(names.containsKey) &&
        required.every(cols.containsKey) &&
        cols.values.every((j) => j is int && j >= 0 && j < table[row].length) &&
        cols.values.toSet().length == cols.length;
    if (!ok) {
      throw Unreadable('열 짝이 맞지 않아요. 한 열은 한 칸에만 고르고 결제일, 가맹점명, 금액은 꼭 골라 주세요');
    }
    return (
      row,
      {
        for (final MapEntry(:key, :value) in cols.entries)
          key as String: value as int,
      },
    );
  }
  (int, int, Map<String, int>)? best;
  for (final (i, row) in table.take(20).indexed) {
    final ns = [for (final c in row) norm(c)];
    final found = <String, int>{};
    for (final MapEntry(key: field, value: words) in names.entries) {
      for (final w in words) {
        final j = [
          for (final (j, n) in ns.indexed)
            if (n == w && !found.values.contains(j)) j,
        ].firstOrNull;
        if (j != null) {
          found[field] = j;
          break;
        }
      }
    }
    if (required.every(found.containsKey) &&
        (best == null || found.length > best.$1)) {
      best = (found.length, i, found);
    }
  }
  return best == null ? (null, null) : (best.$2, best.$3);
}

final _dateRe = RegExp(
  r'(\d{2,4})\s*[.\-/년]?\s*(\d{1,2})\s*[.\-/월]?\s*(\d{1,2})',
);
final _timeRe = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?');
final _digits = RegExp(r'^\d+$');

(DateTime?, Duration?) _day(Object? v) {
  if (v is DateTime) {
    final day = DateTime.utc(v.year, v.month, v.day);
    final at = v.difference(day);
    return (day, at == Duration.zero ? null : at);
  }
  final s = pyStr(v).trim();
  final m = _dateRe.firstMatch(s);
  if (m == null) return (null, null);
  final [y, mo, d] = [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  final year = y < 100 ? y + 2000 : y;
  final day = DateTime.utc(year, mo, d);
  // 없는 날은 받지 않는다. 2026.13.40을 다음 해로 넘기지 않는다
  if (year < 1 || day.year != year || day.month != mo || day.day != d) {
    return (null, null);
  }
  return (day, _time(s.substring(m.end)));
}

Duration? _time(Object? v) {
  if (v is Duration) return v;
  if (v is DateTime) return v.difference(DateTime.utc(v.year, v.month, v.day));
  final s = pyStr(v).trim();
  final m =
      _timeRe.firstMatch(s) ??
      (_digits.hasMatch(s)
          ? RegExp(r'^(\d{2})(\d{2})(\d{2})?$').firstMatch(s)
          : null);
  if (m == null) return null;
  final h = int.parse(m.group(1)!),
      mi = int.parse(m.group(2)!),
      sec = int.parse(m.group(3) ?? '0');
  return h < 24 && mi < 60 && sec < 60
      ? Duration(hours: h, minutes: mi, seconds: sec)
      : null;
}

final _amountJunk = RegExp(r'[,\s원₩]');

int? _amount(Object? v) {
  if (v is bool) return null;
  if (v is int) return v;
  if (v is double) return v.isFinite ? pyRound(v) : null;
  var s = pyStr(v).replaceAll(_amountJunk, '');
  // "-4,500", "4,500-", "(4,500)"은 모두 취소다
  final negative =
      s.startsWith('-') ||
      s.endsWith('-') ||
      (s.startsWith('(') && s.endsWith(')'));
  s = s.replaceAll(RegExp(r'^[\-()]+|[\-()]+$'), '');
  if (!_digits.hasMatch(s)) return null;
  // 너무 큰 수는 읽지 못한 금액이다. 서버는 큰 수로 읽은 뒤 금액 범위에서 막았다
  final n = int.tryParse(s);
  return n == null ? null : (negative ? -n : n);
}

/// 자리만 채운 "-", "0", "00000000" 같은 값은 승인번호가 아니다. xlsx 숫자 칸은 앞의 0이 빠져 비교할 때 뗀다
String? _approval(Object? v) {
  var s = pyStr(v).trim();
  if (s.endsWith('.0') && _digits.hasMatch(s.substring(0, s.length - 2))) {
    s = s.substring(0, s.length - 2);
  }
  return s.length >= 4 && s.codeUnits.any((c) => c > 0x30 && c <= 0x39)
      ? s
      : null;
}

String? approvalKey(String? v) => v?.replaceFirst(RegExp('^0+'), '');

bool? _yes(Object? v) {
  final s = norm(v).toLowerCase();
  if (s.isEmpty) return null;
  if (const {'y', '예', 'o', 'yes'}.contains(s) ||
      s.contains('무이자') ||
      s.contains('해외')) {
    return true;
  }
  if (const {'n', '아니오', 'x', 'no'}.contains(s) ||
      s.contains('유이자') ||
      s.contains('국내')) {
    return false;
  }
  return null;
}

int _installment(Object? v) {
  final m = RegExp(r'\d+').firstMatch(pyStr(v).trim());
  if (m == null) return 1;
  // 너무 큰 수는 할부 범위 1~36에서 막히게 999로 둔다. 서버는 큰 수 그대로 막았다
  final n = int.tryParse(m.group(0)!) ?? 999;
  return n < 1 ? 1 : n;
}

/// 머리 줄 아래 행을 결제 행으로. 날짜도 가맹점도 없는 합계 줄은 건너뛴다
List<ImportRow> parseRows(
  List<List<Object?>> table,
  int start,
  Map<String, int> mapping,
) {
  final out = <ImportRow>[];
  for (final (k, raw) in table.skip(start + 1).indexed) {
    Object? get(String field) {
      final j = mapping[field];
      return j != null && j < raw.length ? raw[j] : null;
    }

    final (day, at) = _day(get('date'));
    final merchant = pyStr(
      get('merchant'),
    ).trim().split(RegExp(r'\s+')).join(' ');
    if (day == null && merchant.isEmpty) continue;
    final row = ImportRow(start + 2 + k, day: day, merchant: merchant);
    final amount = _amount(get('amount'));
    if (day == null) {
      row.error = '날짜를 읽지 못했어요';
    } else if (amount == null || amount == 0) {
      row.error = '금액을 읽지 못했어요';
    } else {
      // 시각 열이 비면 날짜 칸에 든 시각을 쓴다
      row.at = (mapping.containsKey('time') ? _time(get('time')) : null) ?? at;
      row.amount = amount.abs();
      row.cancel = amount < 0 || pyStr(get('cancel')).contains('취소');
      row.installmentMonths = _installment(get('installment'));
      row.approvalNo = _approval(get('approval'));
      final card = pyStr(get('card')).trim();
      row.card = card.isEmpty ? null : card;
      var free = mapping.containsKey('interest_free')
          ? _yes(get('interest_free'))
          : null;
      if (free == null && pyStr(get('installment')).contains('무이자')) {
        free = true;
      }
      // 일시불은 무이자가 아니다. 할부인데 무이자인지 모르면 null이다
      row.interestFree = row.installmentMonths == 1 ? false : free;
      // 해외 여부 Y나 국내외 구분 "해외"면 해외다. 열이 없거나 모르면 국내다
      // ponytail: 이용 국가 열의 나라 이름은 읽지 않는다. 실제 파일을 받으면 더한다
      row.overseas = _yes(get('region')) == true;
    }
    out.add(row);
  }
  return out;
}
