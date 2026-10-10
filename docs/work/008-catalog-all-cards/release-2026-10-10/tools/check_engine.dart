import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';

import '../../app/test/engine/cases.dart';

void main(List<String> args) {
  final catalog = Catalog.fromJson(
    jsonDecode(File(args[0]).readAsStringSync()) as Json,
  );
  final cases = loadCases(args[1]);
  final engine = Engine(catalog);
  final failures = <String>[];
  final covered = <String>{};
  for (final c in cases) {
    final mismatch = mismatches(engine, c);
    failures.addAll(mismatch.map((s) => '${c.cardId} ${c.name}: $s'));
    for (final e in c.expect) {
      for (final entry in ((e['benefits'] ?? {}) as Map).entries) {
        if (entry.value > 0) covered.add('${c.cardId}/${entry.key}');
      }
    }
  }
  final testedIds = cases.map((c) => c.cardId).toSet();
  for (final id in (args.length > 2 && args[2] == 'skip-benefit-coverage' ? <String>{} : testedIds)) {
    for (final b in catalog.cards[id]!.revisions.last.rules.benefits) {
      if (!covered.contains('$id/${b.key}')) {
        failures.add('$id/${b.key}: 양수 혜택을 확인하는 손계산이 없다');
      }
    }
  }
  stdout.writeln(jsonEncode({
    'cards': testedIds.length,
    'cases': cases.length,
    'failures': failures,
  }));
  if (failures.isNotEmpty || cases.isEmpty) exitCode = 1;
}
