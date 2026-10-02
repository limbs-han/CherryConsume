// 손계산 표. Python `backend/tests/engine/test_cases.py`를 옮겼다. 엔진 설계 6.1과 6.2.
// 표 형식, 모든 혜택이 한 번 이상 나오는지, 엔진과 같은지를 본다. 카탈로그는 커밋된 `assets/catalog.json`이다
import 'dart:convert';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/cond.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cases.dart';
import 'helpers.dart';

final cases = loadCases();

/// 혜택 key마다 내용이 같은 기간. (key, 시작, 끝, 내용). 끝은 다음 개정 시행일이고 없으면 null
List<(String, DateTime, DateTime?, String)> versions(Json card) {
  final revs = card['revisions'] as List;
  final out = <(String, DateTime, DateTime?, String)>[];
  for (final (i, rev) in revs.indexed) {
    final from = parseDay(rev['effective_from']);
    final end = i + 1 < revs.length
        ? parseDay(revs[i + 1]['effective_from'])
        : null;
    for (final b in rev['rules']['benefits'] as List) {
      final String key = b['key'];
      final dump = jsonEncode(b);
      final at = out.indexWhere(
        (v) => v.$1 == key && v.$4 == dump && v.$3 == from,
      );
      if (at >= 0) {
        out[at] = (key, out[at].$2, end, dump);
      } else {
        out.add((key, from, end, dump));
      }
    }
  }
  return out;
}

void main() {
  final catalog = realCatalog;

  test('test_case_files_are_valid', () {
    final problems = <String>[];
    for (final c in cases) {
      final where = '${c.file} ${c.name}';
      final card = catalog.cards[c.cardId];
      if (card == null) {
        problems.add('$where: 카드 ${c.cardId}가 없다');
        continue;
      }
      final keys = {
        for (final r in card.revisions)
          for (final b in r.rules.benefits) b.key,
      };
      for (final p in c.payments) {
        if (p.merchant != null && !catalog.merchants.containsKey(p.merchant)) {
          problems.add('$where: 가맹점 ${p.merchant}가 없다');
        }
        if (p.category != null && !catalog.categories.contains(p.category)) {
          problems.add('$where: 업종 ${p.category}가 없다');
        }
        if (p.paymentMethod != null &&
            !catalog.paymentMethods.containsKey(p.paymentMethod)) {
          problems.add('$where: 결제수단 ${p.paymentMethod}가 없다');
        }
      }
      for (final e in c.expect) {
        final int i = e['payment'];
        if (i < 0 || i >= c.payments.length) {
          problems.add('$where: payment $i가 결제 목록 밖이다');
        }
        for (final k in ((e['benefits'] ?? const {}) as Map).keys) {
          if (!keys.contains(k)) problems.add('$where: 혜택 $k가 카드에 없다');
        }
      }
      if (c.calc.isEmpty) problems.add('$where: calc가 비어 있다');
    }
    expect(problems, isEmpty);
  });

  test('test_every_benefit_is_covered', () {
    // 작업 002 intent 성공 기준 1. 혜택마다, 개정으로 내용이 바뀐 혜택은 바뀐 내용마다 양수로 한 번 이상 나온다
    final covered = <String, List<DateTime>>{};
    for (final c in cases) {
      for (final e in c.expect) {
        final d = localDay(c.payments[e['payment']].paidAt);
        for (final MapEntry(:key, :value)
            in ((e['benefits'] ?? const {}) as Map).entries) {
          if (value > 0) {
            covered.putIfAbsent('${c.cardId}:$key', () => []).add(d);
          }
        }
      }
    }
    final missing = <String>[];
    final cards = [for (final c in realJson['cards'] as List) c as Json]
      ..sort((a, b) => (a['id'] as String).compareTo(b['id']));
    for (final card in cards) {
      for (final (key, start, end, _) in versions(card)) {
        final days = covered['${card['id']}:$key'] ?? const [];
        if (!days.any(
          (d) => !d.isBefore(start) && (end == null || d.isBefore(end)),
        )) {
          missing.add('${card['id']}:$key@${dayText(start)}');
        }
      }
    }
    expect(missing, isEmpty);
  });

  group('test_case_matches_engine', () {
    final eng = Engine(catalog);
    for (final c in cases) {
      test('${c.cardId}:${c.name}', () => expect(mismatches(eng, c), isEmpty));
    }
  });
}
