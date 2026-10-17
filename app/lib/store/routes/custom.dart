/// 직접 만든 카드 만들기와 고치기. 작업 019 설계 1절, S13, S14, E65~E67
library;

import 'dart:convert';

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../custom.dart';
import '../db.dart';
import '../store.dart';
import 'answers.dart' show reprice;
import 'catalog.dart' show maxSpend;

const maxBenefits = 5, maxTiers = 3;

/// 오늘 적용되는 개정의 규칙 원래 JSON
Json _rulesToday(Store s, String cardId) {
  final card = s.catalog.cards[cardId]!;
  final today = s.today();
  var i = 0;
  for (final (k, h) in card.heads.indexed) {
    if (!h.effectiveFrom.isAfter(today)) i = k;
  }
  return card.rulesJson[i];
}

List<int> _tiersOf(Json rules) => [
  for (final t in rules['tiers'] as List)
    if (t != 0) t as int,
];

/// 입력 칸을 고르고 모양을 본다. 화면이 보낸 값만 규칙이 되므로 여기서 막는다. 기록 가져오기도 이것으로 본다. 설계
/// 1.3, 위험 검토 높음 1, 중간 6, 낮음 8. baseRules를 주면 그 바탕으로 본다. 안 주면 비슷한 카드의 오늘 개정이다
Json checkedInput(Store s, Json raw, {Json? baseRules}) {
  ApiError bad(String why) => ApiError(422, why);
  final issuer = raw['issuer'], name = raw['name'], kind = raw['kind'];
  if (issuer is! String ||
      (issuer != otherIssuer['id'] && !s.catalog.issuers.containsKey(issuer))) {
    throw bad('카드사가 틀렸다');
  }
  if (name is! String || name.trim().isEmpty || name.trim().length > 40) {
    throw bad('카드 이름은 1~40자다');
  }
  if (kind != 'credit' && kind != 'check') throw bad('신용이나 체크다');
  final fee = raw['annual_fee'];
  if (fee != null && (fee is! int || fee < 0 || fee > 10000000)) {
    throw bad('연회비가 틀렸다');
  }
  final base = raw['base_card_id'];
  if (base != null &&
      (base is! String ||
          base.startsWith('custom-') ||
          !s.catalog.cards.containsKey(base))) {
    throw bad('비슷한 카드가 틀렸다');
  }
  final rules = base == null ? null : baseRules ?? _rulesToday(s, base);
  final tiers = raw['tiers'];
  if (tiers is! List ||
      tiers.length > maxTiers ||
      tiers.any((t) => t is! int || t <= 0 || t > maxSpend) ||
      [
        for (var i = 1; i < tiers.length; i++) tiers[i - 1] < tiers[i],
      ].contains(false)) {
    throw bad('실적 구간은 커지는 순서의 금액 3개까지다');
  }
  // 복사한 규칙의 표와 한도는 바탕 카드의 구간을 key로 쓴다. 구간을 바꾸면 표에 없는 구간이 생겨 비슷한 카드에서
  // 시작한 카드는 구간을 그대로 둔다. 위험 검토 중간 5
  if (rules != null && tiers.join(',') != _tiersOf(rules).join(',')) {
    throw bad('비슷한 카드에서 시작한 카드는 실적 구간을 바꾸지 않는다');
  }
  final benefits = raw['benefits'];
  if (benefits is! List || benefits.length > maxBenefits) {
    throw bad('혜택은 5줄까지다');
  }
  final out = <Json>[];
  for (final b in benefits) {
    if (b is! Map) throw bad('혜택 줄이 틀렸다');
    final all = b['all'] == true;
    final cats = b['categories'];
    if (!all &&
        (cats is! List ||
            cats.isEmpty ||
            cats.length > 3 ||
            cats.any((c) => !s.categoryNames.containsKey(c)))) {
      throw bad('대상은 모든 가맹점이나 업종 1~3개다');
    }
    final type = b['type'], rate = b['rate'], fixed = b['fixed'];
    final min = b['min_amount'];
    if (!rewardTypes.containsKey(type)) throw bad('혜택 방식이 틀렸다');
    final okRate =
        rate is num &&
        rate > 0 &&
        rate <= 100 &&
        rateShape.hasMatch('$rate') &&
        fixed == null &&
        min == null;
    final okFixed =
        fixed is int &&
        fixed > 0 &&
        fixed <= 1000000 &&
        rate == null &&
        min is int &&
        min >= fixed &&
        min <= maxSpend;
    if (!okRate && !okFixed) {
      throw bad('혜택 크기는 소수 둘째 자리까지의 %나, 최소 결제액이 있는 원이다');
    }
    final cap = b['month_cap'], from = b['from_tier'];
    if (cap != null && (cap is! int || cap <= 0 || cap > maxSpend)) {
      throw bad('월 한도가 틀렸다');
    }
    if (from != null && !tiers.contains(from)) {
      throw bad('필요한 구간은 실적 구간 가운데 하나다');
    }
    out.add({
      if (all) 'all': true else 'categories': [...cats as List],
      'type': type,
      'rate': ?rate,
      'fixed': ?fixed,
      'min_amount': ?min,
      'month_cap': ?cap,
      'from_tier': ?from,
    });
  }
  final copied = raw['copied'] ?? const [];
  final baseKeys = {
    for (final b in (rules?['benefits'] as List?) ?? const []) b['key'],
  };
  if (copied is! List ||
      copied.any(
        (k) => k is! String || k.startsWith('custom-') || !baseKeys.contains(k),
      ) ||
      copied.toSet().length != copied.length) {
    throw bad('복사한 혜택이 틀렸다');
  }
  return {
    'issuer': issuer,
    'name': name.trim(),
    'kind': kind,
    'annual_fee': fee,
    'tiers': [...tiers],
    'benefits': out,
    'copied': [...copied],
    'base_card_id': base,
  };
}

/// 혜택 이름, 지문, 확인한 날을 뺀 카드. 업종 이름은 카탈로그를 받으면 바뀔 수 있다
String _shape(Json card) {
  final j = jsonDecode(jsonEncode(card)) as Json;
  j.remove('checked_at');
  for (final r in j['revisions'] as List) {
    (r as Json).remove('sha256');
    for (final b in r['rules']['benefits'] as List) {
      if ((b['key'] as String).startsWith('custom-')) {
        (b as Json).remove('title');
      }
    }
  }
  return jsonEncode(j);
}

/// 기록 파일의 직접 만든 카드가 입력과 바탕 카드로 다시 만들어지는가. 손으로 고친 규칙이 엔진을 깨지 않게 한다.
/// 바탕 카드는 지금 카탈로그의 어느 개정이든 된다. 위험 검토 높음 2
bool reproducible(Store s, String id, Json card, Json raw) {
  final base = raw['base_card_id'];
  final List<Json?> candidates = base == null
      ? [null]
      : base is String && s.catalog.cards.containsKey(base)
      ? s.catalog.cards[base]!.rulesJson
      : [];
  for (final rules in candidates) {
    try {
      final input = checkedInput(s, raw, baseRules: rules);
      final again = cardJson(
        id,
        input,
        rulesOf(input, rules, s.categoryNames),
        s.today(),
      );
      if (_shape(again) == _shape(card)) return true;
    } on ApiError {
      continue;
    }
  }
  return false;
}

/// 만든다. 등록은 화면이 이어서 등록 시트로 한다. S13
Json createCustom(Store s, Json raw) {
  final input = checkedInput(s, raw);
  final base = input['base_card_id'] as String?;
  final now = s.clock();
  final id = 'custom-${newId(now)}';
  final rules = rulesOf(
    input,
    base == null ? null : _rulesToday(s, base),
    s.categoryNames,
  );
  final card = cardJson(id, input, rules, s.today());
  write(
    s,
    () => s.db.execute(
      'insert into custom_cards (id, card_json, input_json, created_at, updated_at) '
      'values (?, ?, ?, ?, ?)',
      [id, jsonEncode(card), jsonEncode(input), ms(now), ms(now)],
    ),
  );
  s.reloadCustom();
  return {'card_id': id};
}

/// 고친다. 카드 저장과 그 카드의 모든 결제 다시 계산을 한 트랜잭션에서 한다. 혜택이 바뀐 결제 수를 돌려준다. 바탕은
/// 고치기 전 규칙이다. 바탕 카드 규칙에 구간과 혜택만 바꾼 것이라 결과가 같다. S14, E67, 위험 검토 중간 7
Json updateCustom(Store s, String id, Json raw) {
  final old = s.db.select(
    'select card_json, input_json from custom_cards where id = ?',
    [id],
  );
  if (old.isEmpty) throw ApiError(404, '직접 만든 카드가 아니다');
  final prev =
      ((jsonDecode(old.first['card_json'] as String)['revisions'] as List)
                  .single
              as Json)['rules']
          as Json;
  final base =
      (jsonDecode(old.first['input_json'] as String) as Json)['base_card_id'];
  final input = checkedInput(s, {
    ...raw,
    'base_card_id': base,
  }, baseRules: base == null ? null : prev);
  final card = cardJson(
    id,
    input,
    rulesOf(input, base == null ? null : prev, s.categoryNames),
    s.today(),
  );
  final now = s.clock();
  final owners = [
    for (final r in s.db.select('select id from user_cards where card_id = ?', [
      id,
    ]))
      r['id'] as String,
  ];
  try {
    final repriced = write(s, () {
      s.db.execute(
        'update custom_cards set card_json = ?, input_json = ?, updated_at = ? where id = ?',
        [jsonEncode(card), jsonEncode(input), ms(now), id],
      );
      s.reloadCustom();
      return reprice(s, owners, [DateTime.utc(2000)]);
    });
    return {'repriced': repriced};
  } catch (_) {
    // DB는 되돌아갔다. 엔진도 옛 카드로 되돌린다
    s.reloadCustom();
    rethrow;
  }
}

/// 고치기 화면을 채울 입력
Json customInput(Store s, String id) {
  final r = s.db.select('select input_json from custom_cards where id = ?', [
    id,
  ]);
  if (r.isEmpty) throw ApiError(404, '직접 만든 카드가 아니다');
  return jsonDecode(r.first['input_json'] as String) as Json;
}

/// 보유 카드의 카드 id
String customOf(Store s, String userCardId) =>
    s.db.select('select card_id from user_cards where id = ?', [
          userCardId,
        ]).first['card_id']
        as String;

/// 비슷한 카드에서 시작하는 입력. 입력 화면이 다룰 수 있는 혜택은 고칠 수 있는 줄로, 아닌 것은 복사한 혜택으로
/// 둔다. 이름은 비운다. 설계 1.3, 2.2
Json startFrom(Store s, String baseId) {
  final card = s.catalog.cards[baseId];
  if (card == null || baseId.startsWith('custom-')) {
    throw ApiError(404, '카드가 아니다');
  }
  final rules = _rulesToday(s, baseId);
  final simple = <Json>[], copied = <Json>[];
  for (final b in rules['benefits'] as List) {
    final one = simpleOf(b as Json, rules);
    if (one != null && simple.length < maxBenefits) {
      simple.add(one);
    } else {
      copied.add({'key': b['key'], 'title': b['title']});
    }
  }
  final fees = [
    for (final f in card.annualFees)
      if (f.scope == 'domestic') f.amount,
  ];
  return {
    'issuer': card.issuer,
    'name': '',
    'kind': card.kind,
    'annual_fee': fees.isEmpty ? null : fees.reduce((a, b) => a < b ? a : b),
    'tiers': _tiersOf(rules),
    'benefits': simple,
    'copied': [for (final c in copied) c['key']],
    'copied_titles': [for (final c in copied) c['title']],
    'base_card_id': baseId,
  };
}
