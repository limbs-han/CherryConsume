/// 모르는 값 답하기. 카드 사실, 옵션, 쓰기 시작한 날, 사람 사실. 서버 `cherry_api/routes/answers.py`를 옮겼다.
/// 작업 005 설계 5e, E56
///
/// 처음 답은 원래 그랬던 것이라 그 카드의 모든 결제에 쓴다. 바꾼 답은 옵션이면 카탈로그 change대로 오늘이나 다음 달
/// 1일부터, 사실이면 이번 달 1일부터다. 2026-10-02 사용자가 정했다.
library;

import 'dart:convert';

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../answers.dart';
import '../payments.dart';
import '../store.dart';
import 'me.dart';
import 'payments.dart';
import 'records.dart';

Object? checkedValue(Fact f, Object? v) {
  final ok =
      (f.type == 'bool' && v is bool) ||
      (f.type == 'month' && v is int && v >= 1 && v <= 12) ||
      (f.type == 'choice' &&
          v is String &&
          (f.choices ?? const []).contains(v));
  if (!ok) throw ApiError(422, '${f.key}의 답이 종류에 맞지 않다');
  return v;
}

/// 사실 답 하나를 적고 바꾼 날을 돌려준다. 그날 쓰는 답과 같으면 적지 않고 null이다
///
/// owner가 null이면 사람 사실 표 user_facts다. 폰에는 사용자가 한 명이라 주인 칸이 없다. table은 이 파일의 값이다
DateTime? answerFact(
  Store s,
  String table,
  String? owner,
  String key,
  Object value,
  DateTime day,
) {
  final mine = owner == null ? '' : 'user_card_id = ? and ';
  final who = [?owner];
  final rows = [
    for (final r in s.db.select(
      'select effective_from, value from $table where ${mine}key = ?',
      [...who, key],
    ))
      (parseDay(r['effective_from']), jsonDecode(r['value']) as Object?),
  ];
  final eff = rows.isNotEmpty ? monthOf(day) : first;
  final before = atDay([
    for (final x in rows)
      if (x.$1.isBefore(eff)) x,
  ], eff);
  final later = [
    for (final x in rows)
      if (!x.$1.isBefore(eff)) x,
  ];
  if (rows.isEmpty || before != value) {
    final cols = owner == null ? '' : 'user_card_id, ';
    final marks = owner == null ? '' : '?, ';
    s.db.execute(
      'insert into $table (${cols}key, effective_from, value, answered_at) values ($marks?, ?, ?, ?) '
      'on conflict (${cols}key, effective_from) do update set value = excluded.value, '
      'answered_at = excluded.answered_at',
      [...who, key, dayText(eff), jsonEncode(value), ms(s.clock())],
    );
    return later.isNotEmpty && atDay(rows, eff) == value ? null : eff;
  }
  if (later.isEmpty) return null;
  // 이번 달에 바꾼 답을 그 전 답으로 되돌린다
  s.db.execute(
    'delete from $table where ${mine}key = ? and effective_from >= ?',
    [...who, key, dayText(eff)],
  );
  return eff;
}

/// 옵션 답 하나를 적고 바꾼 날을 돌려준다. 다시 계산할 것이 없으면 null이다
///
/// 새 답은 그날부터 뒤로 예약된 답을 지운다. 지금 쓰는 답을 다시 고르면 예약만 지운다. 처음 답이 카탈로그 기본값과
/// 같으면 엔진 계산이 같아 적기만 하고 다시 계산하지 않는다. E18
DateTime? answerOption(
  Store s,
  String uid,
  Option o,
  String choice,
  DateTime day,
) {
  final rows = [
    for (final r in s.db.select(
      'select effective_from, choice_key from user_card_options where user_card_id = ? and option_key = ?',
      [uid, o.key],
    ))
      (parseDay(r['effective_from']), r['choice_key'] as Object?),
  ];
  final eff = rows.isNotEmpty
      ? (o.change == 'immediate' ? day : addMonths(monthOf(day), 1))
      : first;
  final before = rows.isNotEmpty
      ? atDay([
          for (final x in rows)
            if (x.$1.isBefore(eff)) x,
        ], eff)
      : o.defaultChoice;
  final later = [
    for (final x in rows)
      if (!x.$1.isBefore(eff)) x,
  ];
  void insert() => s.db.execute(
    'insert into user_card_options (user_card_id, option_key, choice_key, effective_from, answered_at) '
    'values (?, ?, ?, ?, ?)',
    [uid, o.key, choice, dayText(eff), ms(s.clock())],
  );
  if (before == choice && later.isEmpty) {
    if (rows.isEmpty) insert();
    return null;
  }
  s.db.execute(
    'delete from user_card_options where user_card_id = ? and option_key = ? and effective_from >= ?',
    [uid, o.key, dayText(eff)],
  );
  if (before != choice) insert();
  return eff;
}

/// 답이 바뀐 카드의 결제를 처음 바뀌는 달부터 마지막 결제가 든 달까지 다시 계산한다. 혜택이 바뀐 결제 수. E56
int reprice(Store s, List<String> ids, List<DateTime> starts) {
  if (starts.isEmpty) return 0;
  final engine = s.engine, now = s.clock();
  final rows = lockCards(s, ids.toSet()).values;
  final loaded = loadPayments(s, ids);
  final earliest = starts.reduce((a, b) => a.isBefore(b) ? a : b);
  var changed = 0;
  for (final r in rows) {
    final payments = loaded[r['id']]!;
    if (payments.isEmpty) continue;
    final firstPaid = payments
        .map((q) => q.paidAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final firstMonth = monthOf(localDay(firstPaid));
    final m = monthOf(earliest);
    final start = m.isAfter(firstMonth) ? m : firstMonth;
    final res = repricedFrom(engine, engineCard(r), payments, start, now);
    changed += store(
      s,
      r['card_id'] as String,
      res,
      {for (final q in payments) q.id: q},
      {},
      now,
    );
  }
  return changed;
}

/// 답 몸통의 사실과 옵션. 값은 참과 거짓, 정수, 글자만 받는다. 서버의 StrictBool | StrictInt | StrictStr
Map<String, Object> _facts(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) throw ApiError(422, 'facts가 틀렸다');
  final out = <String, Object>{};
  for (final MapEntry(:key, :value) in raw.entries) {
    if (key is! String || !(value is bool || value is int || value is String)) {
      throw ApiError(422, 'facts의 $key가 틀렸다');
    }
    out[key] = value as Object;
  }
  return out;
}

Map<String, String> _options(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) throw ApiError(422, 'options가 틀렸다');
  final out = <String, String>{};
  for (final MapEntry(:key, :value) in raw.entries) {
    if (key is! String || value is! String) {
      throw ApiError(422, 'options의 $key가 틀렸다');
    }
    out[key] = value;
  }
  return out;
}

/// 카드 사실, 옵션, 쓰기 시작한 날을 답한다. 시안 보드 6의 카드 정보. 작업 004 설계 3.1
///
/// started_on은 보낸 때만 바꾼다. null이면 지운다
Json cardAnswers(Store s, String uid, Json body) {
  final facts = _facts(body['facts']), options = _options(body['options']);
  final sent = body.containsKey('started_on');
  final raw = body['started_on'];
  DateTime? startedOn;
  if (raw != null) {
    startedOn =
        strictDay(raw) ??
        (throw ApiError(422, '쓰기 시작한 날은 2026-09-01처럼 있는 날로 쓴다'));
  }
  return write(s, () {
    final rows = lockCards(s, {uid});
    if (!rows.containsKey(uid) || rows[uid]!['removed_at'] != null) {
      throw ApiError(404, '보유 카드가 아니다');
    }
    final row = rows[uid]!, day = s.today();
    final found = s.engine.ctx.rulesOn(row['card_id'] as String, day);
    final cardFacts = {
      for (final f in found?.rules.facts ?? const <Fact>[])
        if (f.scope == 'card') f.key: f,
    };
    final cardOptions = {
      for (final o in found?.rules.options ?? const <Option>[]) o.key: o,
    };
    for (final MapEntry(:key, :value) in facts.entries) {
      final f = cardFacts[key];
      if (f == null) throw ApiError(422, '이 카드에 묻는 사실이 아니다: $key');
      checkedValue(f, value);
    }
    for (final MapEntry(:key, value: choice) in options.entries) {
      final o = cardOptions[key];
      if (o == null || !o.choices.any((c) => c.key == choice)) {
        throw ApiError(422, '이 카드의 옵션 선택지가 아니다: $key');
      }
    }
    final text = startedOn == null ? null : dayText(startedOn);
    final moved = sent && text != row['started_on'];
    if (moved && startedOn != null && startedOn.isAfter(day)) {
      throw ApiError(422, '쓰기 시작한 날이 오늘보다 뒤다');
    }
    final starts = [
      for (final MapEntry(:key, :value) in facts.entries)
        answerFact(s, 'user_card_facts', uid, key, value, day),
      for (final MapEntry(:key, value: c) in options.entries)
        answerOption(s, uid, cardOptions[key]!, c, day),
    ];
    if (moved) {
      // 쓰기 시작한 날은 카드 한 장에 하나라 바꾸면 모든 결제에 쓴다
      s.db.execute('update user_cards set started_on = ? where id = ?', [
        text,
        uid,
      ]);
      starts.add(first);
    }
    return {
      'repriced': reprice(s, [uid], [...starts.nonNulls]),
    };
  });
}

/// 가진 카드들의 사람 사실과 그 사실을 쓰는 카드. 오늘의 개정을 본다
Map<String, (Fact, List<Map<String, Object?>>)> userFactDefs(
  Store s,
  List<Map<String, Object?>> rows,
) {
  final day = s.today();
  final out = <String, (Fact, List<Map<String, Object?>>)>{};
  for (final r in rows) {
    final found = s.engine.ctx.rulesOn(r['card_id'] as String, day);
    for (final f in found?.rules.facts ?? const <Fact>[]) {
      if (f.scope == 'user') out.putIfAbsent(f.key, () => (f, [])).$2.add(r);
    }
  }
  return out;
}

/// 설정의 혜택 계산에 쓰는 답. 시안 보드 9
List<Json> userFacts(Store s) {
  final defs = userFactDefs(s, myCards(s));
  final rows = s.db.select('select key, effective_from, value from user_facts');
  final day = s.today();
  return [
    for (final key in defs.keys.toList()..sort())
      {
        'key': key,
        'type': defs[key]!.$1.type,
        'ask': defs[key]!.$1.ask,
        'choices': defs[key]!.$1.choices,
        'answer': atDay([
          for (final r in rows)
            if (r['key'] == key)
              (
                parseDay(r['effective_from']),
                jsonDecode(r['value']) as Object?,
              ),
        ], day),
        'cards': [for (final c in defs[key]!.$2) c['name']],
      },
  ];
}

/// 사람 사실을 답한다. 그 사실을 쓰는 카드를 모두 다시 계산한다
Json putUserFacts(Store s, Json body) {
  final facts = _facts(body['facts'] ?? (throw ApiError(422, 'facts가 있어야 한다')));
  return write(s, () {
    final defs = userFactDefs(s, myCards(s));
    for (final MapEntry(:key, :value) in facts.entries) {
      final d = defs[key];
      if (d == null) throw ApiError(422, '가진 카드가 묻는 사람 사실이 아니다: $key');
      checkedValue(d.$1, value);
    }
    // 해지한 카드도 그 사실을 쓰면 다시 계산한다. 엔진은 해지한 카드에도 사람 사실을 넣는다. E56
    final every = [
      for (final r in s.db.select('select * from user_cards')) named(s, r),
    ];
    final using = userFactDefs(s, every);
    final ids = {
      for (final key in facts.keys)
        for (final c in using[key]?.$2 ?? const <Map<String, Object?>>[])
          c['id'] as String,
    };
    final day = s.today();
    final starts = [
      for (final MapEntry(:key, :value) in facts.entries)
        answerFact(s, 'user_facts', null, key, value, day),
    ];
    return {
      'repriced': reprice(s, ids.toList()..sort(), [...starts.nonNulls]),
    };
  });
}
