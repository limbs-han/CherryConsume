/// 모르는 값의 답. 카드 사실, 사람 사실, 옵션. 서버 `cherry_api/answers.py`를 옮겼다. 작업 005 설계 5e
library;

import 'dart:convert';

import '../catalog/models.dart';
import '../engine/cond.dart';
import '../engine/models.dart';
import 'store.dart';

/// 처음 답은 원래 그랬던 것을 알려 준 것이라 모든 결제에 쓴다. 2026-10-02 사용자가 정했다
final first = firstDay;

/// 보유 카드 행마다 옵션 답과 사실 답을 붙인다. engineCard가 읽는다. 사람 사실은 모든 카드에 넣는다
List<Map<String, Object?>> attachAnswers(
  Store s,
  List<Map<String, Object?>> rows,
) {
  for (final r in rows) {
    r['options'] = <OptionPick>[];
    r['fact_picks'] = <FactPick>[];
  }
  if (rows.isEmpty) return rows;
  final by = {for (final r in rows) r['id'] as String: r};
  final marks = List.filled(by.length, '?').join(', ');
  for (final o in s.db.select(
    'select user_card_id, option_key, choice_key, effective_from from user_card_options '
    'where user_card_id in ($marks)',
    by.keys.toList(),
  )) {
    (by[o['user_card_id']]!['options'] as List<OptionPick>).add(
      OptionPick(
        option: o['option_key'],
        choice: o['choice_key'],
        effectiveFrom: parseDay(o['effective_from']),
      ),
    );
  }
  for (final f in s.db.select(
    'select user_card_id, key, value, effective_from from user_card_facts where user_card_id in ($marks)',
    by.keys.toList(),
  )) {
    (by[f['user_card_id']]!['fact_picks'] as List<FactPick>).add(factPick(f));
  }
  for (final f in s.db.select(
    'select key, value, effective_from from user_facts',
  )) {
    for (final r in rows) {
      (r['fact_picks'] as List<FactPick>).add(factPick(f));
    }
  }
  return rows;
}

FactPick factPick(Map<String, Object?> row) => FactPick(
  key: row['key'] as String,
  value: jsonDecode(row['value'] as String) as Object,
  effectiveFrom: parseDay(row['effective_from'] as String),
);

/// 그날 쓰는 답. rows는 (바꾼 날, 답)이다. 없으면 null
Object? atDay(List<(DateTime, Object?)> rows, DateTime day) {
  final picks = [
    for (final (d, v) in sortedStable(rows, (a, b) => a.$1.compareTo(b.$1)))
      if (!d.isAfter(day)) v,
  ];
  return picks.isEmpty ? null : picks.last;
}
