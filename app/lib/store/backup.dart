/// 기록 내보내기와 가져오기. 폰을 바꾸거나 앱을 다시 깔 때 기록을 파일 하나로 옮긴다. 서버가 없어 이것이 기록을
/// 옮기는 유일한 길이다. 작업 006 설계 6절, 의도 성공 기준 6
///
/// JSON 한 파일이다. 표마다 칸 이름을 한 번 적고 행은 값 목록이다. 값은 DB의 저장 모양 그대로다. 가져오기는 합치지
/// 않고 바꾼다. 저장된 혜택을 그대로 넣고 다시 계산하지 않는다. E18
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../api.dart' show ApiError;
import 'answers.dart';
import 'db.dart';
import 'imports.dart' show importSources;
import 'payments.dart';
import 'routes/catalog.dart' show maxSpend;
import 'store.dart';

const kind = 'cherryconsume-records';

/// 결제 한 건이 혜택 줄까지 300바이트 안팎이라 결제 6만 건쯤이다. 가져오기가 파일 전체를 메모리에 읽어 상한을 둔다
const maxBytes = 20000000;

/// 사용자 표가 처음 생긴 표 정의 번호. 이보다 낮은 파일에는 기록이 없다
const firstSchema = 2;

/// 기록 표가 마지막으로 바뀐 표 정의 번호. 이 번호 이상의 파일은 기록 표와 칸이 지금과 같아 빠지면 깨진 파일이다. 표 정의
/// 3번은 기록이 아닌 앱 상태 표만, 4번은 카드 규칙 파일 표만 더했다. 기록 표를 바꾸는 번호를 더하면 이 값도 올린다.
/// 작업 012 위험 검토 중간 1, 작업 014 단계 3
const recordSchema = 2;

/// 담는 표. 외래 키를 지키는 넣는 순서다. 받아 둔 카탈로그와 엑셀 열 짝은 담지 않는다. 열 짝 지문은 머리 줄의
/// sha256뿐이라 파일을 가진 사람이 머리 줄 글자를 대입해 되찾을 수 있다. 2026-10-03 사용자가 정했다
const tables = [
  'user_cards',
  'import_batches',
  'transactions',
  'transaction_benefits',
  'import_cancels',
  'user_card_options',
  'user_card_facts',
  'user_facts',
];

/// 보유 카드나 결제나 답이 하나라도 있는가. 있으면 가져오기 전에 바꿀지 묻는다
bool hasRecords(Store s) => s.db
    .select(
      'select 1 from user_cards union all select 1 from transactions '
      'union all select 1 from user_facts limit 1',
    )
    .isNotEmpty;

/// 마지막으로 기록을 내보낸 시각. 내보낸 적이 없으면 null이다. 설정이 알린다. 작업 012 설계 4절
DateTime? lastExported(Store s) {
  final r = s.db.select(
    "select value from app_state where key = 'last_export'",
  );
  return r.isEmpty ? null : fromMs(int.parse(r.first['value'] as String));
}

/// 저장 창에서 파일을 저장했을 때만 부른다
void markExported(Store s) => s.db.execute(
  "insert into app_state (key, value) values ('last_export', ?) "
  'on conflict (key) do update set value = excluded.value',
  ['${s.clock().millisecondsSinceEpoch}'],
);

/// 기록 파일 글자. 가져오기 상한을 넘으면 어느 폰에서도 가져올 수 없어 413으로 막는다
/// ponytail: 상한을 넘는 기록은 옮길 길이 없다. 그런 사용자가 생기면 파일을 나누거나 흘려 읽는 가져오기를 만든다
String exportAll(Store s) {
  final text = jsonEncode({
    'kind': kind,
    'schema': s.db.userVersion,
    'exported_at': s.clock().toUtc().toIso8601String(),
    'tables': {
      for (final t in tables)
        t: () {
          final rs = s.db.select('select * from $t order by rowid');
          return {
            'columns': rs.columnNames,
            'rows': [for (final r in rs) r.values],
          };
        }(),
    },
  });
  if (utf8.encode(text).length > maxBytes) {
    throw ApiError(413, '기록이 20MB보다 커 한 파일에 담지 못해요');
  }
  return text;
}

/// 지금 기록을 지우고 파일의 기록으로 바꾼다. 한 트랜잭션이라 하나라도 틀리면 모두 되돌려 지금 기록이 그대로다.
/// 표마다 넣은 행 수를 돌려준다
Map<String, int> importAll(Store s, Uint8List data) {
  if (data.length > maxBytes) throw ApiError(413, '파일이 20MB보다 커요');
  final notOurs = ApiError(422, '체리컨슘 기록 파일이 아니에요');
  final newer = ApiError(422, '앱을 새 판으로 올린 뒤 다시 가져와 주세요');
  // 새 폰은 처음 켠 실행에서 앱에 담긴 카탈로그를 쓰고 받은 카탈로그는 다음 실행부터 쓴다. 껐다 켜면 풀리는 경우가
  // 많다. 단계 6 위험 검토 3번
  final unknown = ApiError(
    422,
    '앱을 껐다 켠 뒤 다시 가져와 주세요. 그래도 안 되면 앱을 새 판으로 올려 주세요',
  );
  final broken = ApiError(422, '기록 파일이 깨져 가져오지 못했어요. 지금 기록은 그대로예요');
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(data));
  } on FormatException {
    throw notOurs;
  }
  if (json is! Map ||
      json['kind'] != kind ||
      json['schema'] is! int ||
      (json['schema'] as int) < firstSchema ||
      json['tables'] is! Map) {
    throw notOurs;
  }
  final schema = json['schema'] as int;
  if (schema > migrations.length) throw newer;
  // 표 정의는 칸과 표를 더하기만 한다. 옛 번호 파일은 표나 칸이 빠질 수 있고 표 정의의 기본값이 된다. 같은 번호
  // 파일에서 빠졌으면 깨진 파일이다. 혜택 줄이 빠지면 0원으로 굳고 지운 시각 칸이 빠지면 지운 결제가 살아난다
  final exact = schema >= recordSchema;
  final given = json['tables'] as Map;
  if (given.keys.any((k) => !tables.contains(k)) ||
      (exact && !tables.every(given.containsKey))) {
    throw notOurs;
  }
  final rows = <String, List<Map<String, Object?>>>{};
  for (final t in tables) {
    // 칸 이름은 SQL에 그대로 들어가 표에 있는 칸만 받는다
    final known = {
      for (final c in s.db.select('pragma table_info($t)')) c['name'] as String,
    };
    final table = given[t] ?? {'columns': <String>[], 'rows': <List>[]};
    final columns = table is Map ? table['columns'] : null;
    final list = table is Map ? table['rows'] : null;
    if (columns is! List ||
        list is! List ||
        columns.any((c) => c is! String || !known.contains(c)) ||
        columns.toSet().length != columns.length ||
        (exact && columns.length != known.length) ||
        list.any((r) => r is! List || r.length != columns.length)) {
      throw notOurs;
    }
    rows[t] = [
      for (final r in list)
        {for (final (i, c) in columns.indexed) c as String: (r as List)[i]},
    ];
  }
  // 엑셀 묶음의 출처는 읽은 파일 모양 셋이거나 비어 있다. 파일 이름 같은 글자가 든 파일은 받지 않는다. 받으면 다음
  // 내보내기에도 실려 나간다. 작업 013 13-10, 위험 검토 낮음 2
  if (rows['import_batches']!.any(
    (r) => r['source'] != null && !importSources.contains(r['source']),
  )) {
    throw notOurs;
  }
  // 지금 카탈로그에 없는 카드, 가맹점, 업종, 결제수단이 든 파일은 받지 않는다. 받으면 기록과 계산이 깨진다. 설계 4절
  bool inCatalog(String t, String col, bool Function(String) has) =>
      rows[t]!.every(
        (r) => r[col] == null || (r[col] is String && has(r[col] as String)),
      );
  final cat = s.catalog;
  if (!inCatalog('user_cards', 'card_id', cat.cards.containsKey) ||
      !inCatalog(
        'user_cards',
        'last_payment_method',
        cat.paymentMethods.containsKey,
      ) ||
      !inCatalog('transactions', 'merchant_key', cat.merchants.containsKey) ||
      !inCatalog('transactions', 'category_code', cat.categories.contains) ||
      !inCatalog(
        'transactions',
        'payment_method',
        cat.paymentMethods.containsKey,
      )) {
    throw unknown;
  }
  try {
    write(s, () {
      for (final t in tables.reversed) {
        s.db.execute('delete from $t');
      }
      // 표의 제약과 외래 키가 틀린 행을 막는다. 넣은 뒤 외래 키를 한 번 더 본다
      for (final t in tables) {
        for (final r in rows[t]!) {
          final cols = r.keys.toList();
          s.db.execute(
            'insert into $t (${cols.join(', ')}) values (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) r[c]],
          );
        }
      }
      if (s.db.select('pragma foreign_key_check').isNotEmpty) throw broken;
      _readable(s, broken);
    });
  } on SqliteException {
    throw broken;
  } on ArgumentError {
    // 칸 값이 목록이나 Map이면 sqlite3가 넣지 못한다
    throw broken;
  }
  // 가져온 결제보다 새 결제 id가 크게. 앱을 다시 켜지 않아도 같은 시각 결제의 순서가 뒤집히지 않는다
  seenIds(s.db);
  return {for (final t in tables) t: rows[t]!.length};
}

/// 앱이 저장할 때 하는 검사를 커밋 전에 한 번 더 한다. DB 제약에 없는 것이다. 지나가면 커밋된 뒤 홈이 열리지 않고
/// 옛 기록은 이미 지워졌다. 금액은 1억 원까지라 엔진의 분수 곱이 넘치지 않는다. 할부는 36개월까지다. 결제 모델이
/// 채널, 지역, 청구 방식을 보고 답 읽기가 답 값과 날짜를 본다. 단계 6 위험 검토 1번
void _readable(Store s, ApiError broken) {
  try {
    if (s.db.select(
      'select 1 from transactions where amount > ? or installment_months > 36 limit 1',
      [maxSpend],
    ).isNotEmpty) {
      throw broken;
    }
    final cards = [
      for (final r in s.db.select('select * from user_cards')) rowMap(r),
    ];
    loadPayments(s, [for (final c in cards) c['id'] as String]);
    attachAnswers(s, cards);
    for (final f in s.db.select('select * from user_facts')) {
      factPick(rowMap(f));
    }
  } on ApiError {
    rethrow;
  } catch (_) {
    throw broken;
  }
}
