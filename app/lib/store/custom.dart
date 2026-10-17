/// 사용자가 직접 만든 카드. 입력 화면의 값을 카탈로그 카드 줄과 규칙 한 벌로 바꾸고, 켤 때 카탈로그에 더한다.
/// 작업 019 설계 1절, 설계 문서 11절
///
/// 사용자는 규칙 JSON을 쓰지 않는다. 입력 칸만 규칙이 되고, 비슷한 카드에서 복사한 규칙은 이미 검사를 통과한 것이다
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../catalog/models.dart';

/// 직접 만든 카드의 카드사 칸이 카탈로그에 없을 때 쓰는 카드사. 앱 안에만 있다. 설계 1.2
const otherIssuer = {'id': 'etc', 'name': '기타 카드사', 'short_name': '기타'};

/// 처음부터 만든 카드의 실적 규칙. 모든 결제를 넣고 취소는 취소한 달에 뺀다. 취소한 달은 카탈로그 카드에서 가장
/// 흔한 값이다. E65
const scratchSpend = {
  'basis': 'prev_calendar_month',
  'regions': ['domestic', 'overseas'],
  'exclude_categories': <String>[],
  'interest_free': 'count',
  'installment': 'full_at_purchase',
  'cancellation': 'cancel_month',
  'cancellation_overrides': <Object>[],
  'month_offset': <String, int>{},
  'exclude_applied': 0,
};

/// 화면 방식에서 규칙의 보상 방식으로. 설계 1.4
const rewardTypes = {
  'discount': 'billing_discount',
  'points': 'points',
  'cashback': 'cashback',
};

/// 입력 화면이 다룰 수 있는 혜택 한 줄인가. 대상은 모든 가맹점이나 업종뿐이고, 조건과 함께 쓰는 한도와 옵션이 없고,
/// 보상은 고정 비율이나 건당 원이고, 한도는 월 금액 하나다. 아니면 복사한 혜택으로 둔다. 설계 2.4
Json? simpleOf(Json b) {
  final t = b['target'] as Json, r = b['reward'] as Json;
  final limits = (b['limits'] as List?) ?? const [];
  final tiers = b['tiers'] as Json?;
  final type = {
    for (final MapEntry(:key, :value) in rewardTypes.entries) value: key,
  }[r['type']];
  final rate = r['rate'], fixed = r['fixed'];
  final cats = (t['categories'] as List?) ?? const [];
  final ok =
      type != null &&
      ((b['when'] as List?) ?? const []).isEmpty &&
      b['area'] == null &&
      (b['stack'] ?? 'main') == 'main' &&
      b['valid_from'] == null &&
      b['valid_until'] == null &&
      ((b['unmodeled'] as List?) ?? const []).isEmpty &&
      ((t['merchants'] as List?) ?? const []).isEmpty &&
      ((t['exclude_categories'] as List?) ?? const []).isEmpty &&
      ((t['exclude_merchants'] as List?) ?? const []).isEmpty &&
      (t['all'] == true || (cats.isNotEmpty && cats.length <= 3)) &&
      (r['program'] == null || type != 'points') &&
      r['per_unit'] == null &&
      r['per_liter'] == null &&
      (r['basis'] ?? 'txn') == 'txn' &&
      ((rate is num && fixed == null) || (fixed is int && rate == null)) &&
      (tiers == null ||
          (tiers['to'] == null && tiers['waived_when'] == null)) &&
      limits.length <= 1 &&
      limits.every(
        (l) =>
            l['per'] == 'month' &&
            l['shared'] == null &&
            l['amount'] is int &&
            l['count'] == null &&
            l['base'] == null &&
            ((l['adjust'] as List?) ?? const []).isEmpty,
      );
  if (!ok) return null;
  return {
    if (t['all'] == true) 'all': true else 'categories': cats,
    'type': type,
    'rate': ?rate,
    'fixed': ?fixed,
    if (limits.isNotEmpty) 'month_cap': limits.single['amount'],
    if (tiers?['from'] case final int from when from > 0) 'from_tier': from,
  };
}

/// 혜택 한 줄의 이름. "카페 10% 할인", "모든 가맹점 1,000원 적립"
String benefitTitle(Json b, Map<String, String> categoryNames) {
  final target = b['all'] == true
      ? '모든 가맹점'
      : [
          for (final c in b['categories'] as List)
            categoryNames[c] ?? c as String,
        ].join(' · ');
  final size = b['rate'] != null
      ? '${b['rate']}%'
      : '${_comma(b['fixed'] as int)}원';
  final kind = {'discount': '할인', 'points': '적립', 'cashback': '캐시백'}[b['type']];
  return '$target $size $kind';
}

String _comma(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

Json _benefitRule(int i, Json b, Map<String, String> categoryNames) => {
  'key': 'custom-$i',
  'title': benefitTitle(b, categoryNames),
  'target': {
    'all': b['all'] == true,
    'categories': b['all'] == true ? <String>[] : b['categories'],
    'merchants': <String>[],
    'exclude_categories': <String>[],
    'exclude_merchants': <String>[],
  },
  'when': <Object>[],
  'area': null,
  'reward': {
    'type': rewardTypes[b['type']],
    'program': null,
    'rate': b['rate'],
    'fixed': b['fixed'],
    'per_unit': null,
    'per_liter': null,
    'round': 'floor',
    'basis': 'txn',
  },
  'limits': [
    if (b['month_cap'] != null) {'per': 'month', 'amount': b['month_cap']},
  ],
  'tiers': b['from_tier'] == null ? null : {'from': b['from_tier'], 'to': null},
  'stack': 'main',
  'exclude_applied': null,
  'valid_from': null,
  'valid_until': null,
  'unmodeled': <String>[],
};

/// 입력에서 카탈로그 카드 한 벌 JSON으로. 개정은 하나이고 시작일은 아주 이른 날이라 고치면 모든 달에 새 규칙이
/// 적용된다. E67. baseRules는 비슷한 카드의 규칙이나 고치기 전 규칙이다. 있으면 구간과 혜택만 바꾸고 나머지는 그대로
/// 둔다
Json cardJson(
  String id,
  Json input,
  Json? baseRules,
  Map<String, String> categoryNames,
  DateTime today,
) {
  final tiers = [0, ...(input['tiers'] as List).cast<int>()];
  // 복사한 혜택은 화면이 보낸 key로 바탕 규칙에서 찾는다. 화면이 보낸 JSON을 규칙에 넣지 않는다. 설계 1.3
  final copied = {...((input['copied'] as List?) ?? const []).cast<String>()};
  final kept = [
    for (final b in (baseRules?['benefits'] as List?) ?? const [])
      if (copied.contains((b as Json)['key'])) b,
  ];
  final rules = <String, Object?>{
    ...?baseRules,
    if (baseRules == null) ...{
      'spend': scratchSpend,
      'new_card': null,
      'benefit_exclusions': {
        'categories': <String>[],
        'when_any': <Object>[],
        'unmodeled': <String>[],
      },
      'facts': <Object>[],
      'options': <Object>[],
      'ranked': <Object>[],
      'limits': <Object>[],
      'stacks': <Object>[],
      'unmodeled': <String>[],
    },
    'tiers': tiers,
    'benefits': [
      ...kept,
      for (final (i, b) in (input['benefits'] as List).indexed)
        _benefitRule(i + 1, b as Json, categoryNames),
    ],
  };
  final fee = input['annual_fee'] as int?;
  return {
    'id': id,
    'issuer': input['issuer'],
    'name': input['name'],
    'short_name': null,
    'search_names': <String>[],
    'kind': input['kind'],
    'product_codes': <String>[],
    'status': 'on_sale',
    'status_since': null,
    'annual_fees': [
      if (fee != null) {'scope': 'domestic', 'amount': fee},
    ],
    'checked_at': dayText(today),
    'open_questions': <Object>[],
    'revisions': [
      {
        'effective_from': '2000-01-01',
        'effective_from_estimated': false,
        'source': 'user',
        'sha256': sha256.convert(utf8.encode(jsonEncode(rules))).toString(),
        'rules': rules,
      },
    ],
  };
}

/// 직접 만든 카드를 카탈로그에 더한다. 켤 때와 만들거나 고친 뒤 부른다. 설계 1.2
Catalog withCustom(Database db, Catalog catalog) {
  // 옛 표 번호 DB로 저장소를 만드는 시험이 있다. 앱은 표를 다 올린 뒤에만 만든다
  if (db.userVersion < 7) return catalog;
  for (final r in db.select('select card_json from custom_cards')) {
    final card = CatalogCard.fromJson(jsonDecode(r['card_json'] as String));
    if (!catalog.issuers.containsKey(card.issuer)) {
      catalog.issuers[card.issuer] = Issuer.fromJson(otherIssuer);
    }
    catalog.cards[card.id] = card;
  }
  return catalog;
}
