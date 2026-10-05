// 카탈로그 모델. 작업 006 계획 단계 2의 2
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart' show realCatalog, realJson;

Json readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Json;

void main() {
  test('커밋된 카탈로그 전체가 읽힌다', () {
    final cat = Catalog.fromJson(realJson);
    expect(cat.cards.length, 20);
    final mrlife = cat.cards['shinhan-mrlife']!;
    expect(mrlife.revisions.first.rules.tiers, [0, 300000, 500000, 1000000]);
    expect(cat.categories, contains('restaurant.general'));
    expect(cat.holidays, contains(day(2026, 10, 5)));
    expect(cat.merchants['gs25']!.category, 'convenience');
    expect(
      Catalog.fromJson(
        readJson('test/fixtures/mockup_catalog.json'),
      ).cards.length,
      3,
    );
  });

  test('칸이 비면 Pydantic과 같은 기본값이 들어간다', () {
    final r = Rules.fromJson({
      'tiers': [0],
      'spend': {
        'basis': 'prev_calendar_month',
        'installment': 'full_at_purchase',
        'cancellation': 'cancel_month',
      },
      'benefits': [
        {
          'key': 'b',
          'title': 'b',
          'target': {'all': true},
          'reward': {'type': 'billing_discount', 'rate': 1},
        },
      ],
    });
    expect(r.spend.regions, ['domestic', 'overseas']);
    expect((r.spend.interestFree, r.spend.excludeApplied), ('count', 0));
    final b = r.benefits.single;
    expect((b.stack, b.reward.round, b.reward.basis), ('main', 'floor', 'txn'));
    expect(r.benefitExclusions.categories, isEmpty);
  });

  test('한도 조정은 적어 둔 칸을 안다', () {
    final cat = realCatalog;
    final adjusts = [
      for (final r in cat.cards['ibk-narasarang']!.revisions)
        for (final b in r.rules.benefits)
          for (final l in b.limits) ...l.adjust,
      for (final r in cat.cards['ibk-narasarang']!.revisions)
        for (final l in r.rules.limits) ...l.adjust,
    ];
    // 횟수를 null로 적은 조정은 제한 없음이다
    expect(
      adjusts.where((a) => a.given.contains('count') && a.count == null),
      hasLength(2),
    );
    expect(adjusts.every((a) => !a.given.contains('amount')), isTrue);
  });

  test('형식 번호가 크면 읽지 않는다', () {
    expect(
      () => Catalog.fromJson({'schema': catalogSchema + 1}),
      throwsFormatException,
    );
  });
}
