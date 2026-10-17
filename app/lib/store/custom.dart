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

/// 비율은 소수 둘째 자리까지다. 엔진의 정수 분수가 넘치거나 분모가 0이 되지 않게 한다. 위험 검토 높음 1
final rateShape = RegExp(r'^\d{1,3}(\.\d{1,2})?$');

/// 다른 규칙이 key로 가리키는 혜택. 신규 발급 특례와 우선순위 묶음이다. key가 바뀌면 빠져 복사한 혜택으로 둔다
Set<String> _pointedKeys(Json rules) => {
  ...(((rules['new_card'] as Json?)?['tier_by_benefit'] as Map?) ?? const {})
      .keys
      .cast<String>(),
  for (final s in (rules['stacks'] as List?) ?? const [])
    ...((s as Json)['order'] as List? ?? const []).cast<String>(),
};

/// 입력 화면이 다룰 수 있는 혜택 한 줄인가. 대상은 모든 가맹점이나 업종뿐이고, 조건은 최소 결제액 하나까지, 함께
/// 쓰는 한도와 옵션이 없고, 보상은 고정 비율이나 건당 원이고 원 미만 버림이고, 한도는 월 금액 하나다. 다른 규칙이
/// key로 가리키면 안 된다. 아니면 복사한 혜택으로 둔다. 설계 2.4, 위험 검토 중간 4
Json? simpleOf(Json b, Json rules) {
  final t = b['target'] as Json, r = b['reward'] as Json;
  final limits = (b['limits'] as List?) ?? const [];
  final when = (b['when'] as List?) ?? const [];
  final tiers = b['tiers'] as Json?;
  final type = {
    for (final MapEntry(:key, :value) in rewardTypes.entries) value: key,
  }[r['type']];
  final rate = r['rate'], fixed = r['fixed'];
  final cats = (t['categories'] as List?) ?? const [];
  final min = when.length == 1 ? _minOnly(when.single as Json) : null;
  final ok =
      type != null &&
      (when.isEmpty || (min != null && fixed is int && min >= fixed)) &&
      (fixed == null || min != null) &&
      b['area'] == null &&
      (b['stack'] ?? 'main') == 'main' &&
      b['exclude_applied'] == null &&
      b['valid_from'] == null &&
      b['valid_until'] == null &&
      !_pointedKeys(rules).contains(b['key']) &&
      ((b['unmodeled'] as List?) ?? const []).isEmpty &&
      ((t['merchants'] as List?) ?? const []).isEmpty &&
      ((t['exclude_categories'] as List?) ?? const []).isEmpty &&
      ((t['exclude_merchants'] as List?) ?? const []).isEmpty &&
      (t['all'] == true || (cats.isNotEmpty && cats.length <= 3)) &&
      (r['program'] == null || type != 'points') &&
      r['per_unit'] == null &&
      r['per_liter'] == null &&
      (r['round'] ?? 'floor') == 'floor' &&
      (r['basis'] ?? 'txn') == 'txn' &&
      ((rate is num && fixed == null && rateShape.hasMatch('$rate')) ||
          (fixed is int && rate == null)) &&
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
    'min_amount': ?min,
    if (limits.isNotEmpty) 'month_cap': limits.single['amount'],
    if (tiers?['from'] case final int from when from > 0) 'from_tier': from,
  };
}

/// 최소 결제액 하나만 든 조건이면 그 금액
int? _minOnly(Json c) {
  final a = c['amount'];
  final others = c.entries.where((e) => e.key != 'amount' && e.value != null);
  return others.isEmpty && a is Map && a['min'] is int && a['below'] == null
      ? a['min'] as int
      : null;
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
  // 건당 원 혜택은 최소 결제액이 있다. 1,000원 결제에 5,000원이 나오지 않게 한다. 위험 검토 중간 6
  'when': [
    if (b['min_amount'] != null)
      {
        'amount': {'min': b['min_amount']},
      },
  ],
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

/// 입력에서 카드 규칙으로. baseRules는 비슷한 카드의 규칙이다. 있으면 구간과 혜택만 바꾸고 나머지는 그대로 둔다.
/// 복사한 혜택은 화면이 보낸 key로 바탕 규칙에서 찾고 화면이 보낸 JSON을 규칙에 넣지 않는다. 설계 1.3
Json rulesOf(Json input, Json? baseRules, Map<String, String> categoryNames) {
  final copied = {...((input['copied'] as List?) ?? const []).cast<String>()};
  final kept = [
    for (final b in (baseRules?['benefits'] as List?) ?? const [])
      if (copied.contains((b as Json)['key'])) b,
  ];
  return <String, Object?>{
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
    'tiers': [0, ...(input['tiers'] as List).cast<int>()],
    'benefits': [
      ...kept,
      for (final (i, b) in (input['benefits'] as List).indexed)
        _benefitRule(i + 1, b as Json, categoryNames),
    ],
  };
}

/// 카탈로그 카드 한 벌 JSON. 개정은 하나이고 시작일은 아주 이른 날이라 고치면 모든 달에 새 규칙이 적용된다. E67
Json cardJson(String id, Json input, Json rules, DateTime today) {
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

/// 직접 만든 카드를 카탈로그에 다시 더한다. 지운 카드가 남지 않게 먼저 뺀다. 켤 때와 만들거나 고치거나 기록을 가져온
/// 뒤 부른다. 설계 1.2, 위험 검토 낮음 9
Catalog withCustom(Database db, Catalog catalog) {
  // 옛 표 번호 DB로 저장소를 만드는 시험이 있다. 앱은 표를 다 올린 뒤에만 만든다
  if (db.userVersion < 7) return catalog;
  catalog.cards.removeWhere((id, _) => id.startsWith('custom-'));
  for (final r in db.select('select card_json from custom_cards')) {
    final card = CatalogCard.fromJson(jsonDecode(r['card_json'] as String));
    if (!catalog.issuers.containsKey(card.issuer)) {
      catalog.issuers[card.issuer] = Issuer.fromJson(otherIssuer);
    }
    catalog.cards[card.id] = card;
  }
  return catalog;
}
