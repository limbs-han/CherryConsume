// 손계산 표 읽기. Python `backend/tests/engine/cases.py`를 옮겼다. 엔진 설계 6.1. 표는 test/engine/cases/<카드 id>.yaml이다
//
// card: shinhan-mrlife
// holder: {facts: {}, options: []}          # 모든 경우에 쓰는 보유 카드 값. 없어도 된다
// cases:
//   - name: 주말 이마트 5만원, 30만 구간
//     prev_month_spend: 350000             # 지난달 인정 실적
//     holder: {}                            # 이 경우에만 덮어쓰는 값. 없어도 된다
//     payments:
//       - {at: 2026-09-05T11:00, amount: 50000, merchant: emart, channel: offline}
//     expect:
//       - {payment: 0, benefits: {weekend-mart: 3000}, counted: 50000, warnings: [check_conditions]}
//     calc: 50,000 × 10% = 5,000. 주말 공유 한도 30만 구간 3,000원이라 3,000
//
// - at은 한국 시간이다. 결제의 나머지 칸은 엔진의 Payment와 같다
// - benefits는 그 결제가 받는 혜택 전부다. 값은 보상 단위라 포인트면 포인트 수다. 받는 혜택이 없으면 {}
// - counted는 그 결제가 실적에 넣는 금액의 합이다. warnings는 반드시 있어야 하는 경고 코드다. 둘 다 없어도 된다
// - difference는 엔진과 다른 까닭이다. 실제 명세서 대조에서만 쓴다. 적어 두면 그 결제는 대조하지 않는다. 설계 6.6
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

/// 작업 006 단계 7에서 `backend/tests/engine/`에서 옮겼다
const casesDir = 'test/engine/cases';

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
