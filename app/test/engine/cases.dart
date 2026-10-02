// 손계산 표 읽기. Python `backend/tests/engine/cases.py`를 옮겼다. 표 형식은 그 파일 머리에 있다. 엔진 설계 6.1
//
// 표를 읽는 규칙도 같다. 시간대 없는 시각은 한국 시간, 결제 id는 `경우-결제` 세 자리씩, 카드 파일의 holder를 경우의
// holder가 칸 단위로 덮는다. prev_month_spend가 있으면 첫 결제 달에 등록하고 그 값을 추정값으로 적은 것으로 본다
import 'dart:io';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/cond.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';
import 'package:yaml/yaml.dart';

import 'helpers.dart';

/// 작업 006 단계 7에서 `app/test/engine/`으로 옮긴다
const casesDir = '../backend/tests/engine/cases';

class Case {
  Case(
    this.file,
    this.cardId,
    this.name,
    this.holder,
    this.payments,
    this.expect,
    this.calc,
  );
  final String file, cardId, name;
  final UserCard holder;
  final List<Payment> payments;
  final List<Map> expect;
  final String calc;
}

final _zone = RegExp(r'(Z|[+-]\d\d:?\d\d)$');

DateTime _time(String s) =>
    _zone.hasMatch(s) ? DateTime.parse(s).toUtc() : at(s);

Payment _payment(String id, Map p) {
  final unknown = p.keys.toSet().difference(const {
    'at',
    'amount',
    'merchant',
    'category',
    'channel',
    'region',
    'installment_months',
    'interest_free', //
    'payment_method', 'billing', 'cancelled_amount', 'cancelled_at',
  });
  if (unknown.isNotEmpty) throw FormatException('결제 칸 $unknown을 모른다');
  return Payment(
    id: id,
    userCardId: 'u',
    amount: p['amount'],
    paidAt: _time(p['at']),
    merchant: p['merchant'],
    category: p['category'],
    channel: p['channel'] ?? 'offline',
    region: p['region'] ?? 'domestic',
    installmentMonths: p['installment_months'] ?? 1,
    interestFree: p['interest_free'] ?? false,
    paymentMethod: p['payment_method'],
    billing: p['billing'],
    cancelledAmount: p['cancelled_amount'] ?? 0,
    cancelledAt: p['cancelled_at'] == null ? null : _time(p['cancelled_at']),
  );
}

UserCard _holder(String cardId, Map h) {
  final unknown = h.keys.toSet().difference(const {
    'started_on',
    'facts',
    'options',
    'registered_on',
    'assumed_prev_month_spend', //
  });
  if (unknown.isNotEmpty) throw FormatException('holder 칸 $unknown을 모른다');
  DateTime? date(Object? v) =>
      v == null ? null : (v is DateTime ? v : parseDay(v as String));
  return UserCard(
    id: 'u',
    cardId: cardId,
    registeredOn: date(h['registered_on']),
    startedOn: date(h['started_on']),
    facts: Map<String, Object>.from(h['facts'] ?? const {}),
    options: [
      for (final o in (h['options'] ?? const []) as List)
        OptionPick(
          option: o['option'],
          choice: o['choice'],
          effectiveFrom: parseDay(o['effective_from']),
        ),
    ],
    assumedPrevMonthSpend: h['assumed_prev_month_spend'],
  );
}

List<Case> loadCases([String root = casesDir]) {
  final files =
      Directory(root)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final out = <Case>[];
  for (final f in files) {
    final data = loadYaml(f.readAsStringSync()) as Map;
    final String cardId = data['card'];
    for (final (i, raw) in (data['cases'] as List).indexed) {
      final payments = [
        for (final (j, p) in (raw['payments'] as List).indexed)
          _payment(
            '${i.toString().padLeft(3, '0')}-${j.toString().padLeft(3, '0')}',
            p,
          ),
      ];
      final holder = <Object?, Object?>{...?data['holder'], ...?raw['holder']};
      if (raw['prev_month_spend'] != null) {
        final first = payments
            .map((p) => p.paidAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        holder['registered_on'] = monthOf(localDay(first));
        holder['assumed_prev_month_spend'] = raw['prev_month_spend'];
      }
      holder.putIfAbsent('registered_on', () => day(2020, 1, 1));
      out.add(
        Case(
          f.uri.pathSegments.last,
          cardId,
          raw['name'],
          _holder(cardId, holder),
          payments,
          [for (final e in (raw['expect'] ?? const []) as List) e as Map],
          raw['calc'] ?? '',
        ),
      );
    }
  }
  return out;
}

bool _sameMap(Map a, Map b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// 손계산과 엔진이 다른 곳. difference를 적은 결제는 보지 않는다
List<String> mismatches(Engine eng, Case c) {
  final results = {
    for (final r in eng.priceMonth(c.holder, c.payments)) r.paymentId: r,
  };
  final out = <String>[];
  for (final e in c.expect) {
    if (e.containsKey('difference')) continue;
    final r = results[c.payments[e['payment']].id]!;
    final got = {for (final b in r.benefits) b.key: b.amount};
    final want = (e['benefits'] ?? const {}) as Map;
    if (!_sameMap(got, want)) {
      out.add('결제 ${e['payment']}: 혜택 $got 기대 $want. ${c.calc}');
    }
    final counted = r.spend.fold(0, (s, p) => s + p.amount);
    if (e.containsKey('counted') && counted != e['counted']) {
      out.add('결제 ${e['payment']}: 실적 $counted 기대 ${e['counted']}');
    }
    final missing = {
      ...?(e['warnings'] as List?),
    }.difference({for (final w in r.warnings) w.code});
    if (missing.isNotEmpty) {
      out.add('결제 ${e['payment']}: 없는 경고 ${missing.toList()..sort()}');
    }
  }
  return out;
}
