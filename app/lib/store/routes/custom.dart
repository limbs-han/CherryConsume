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

/// 입력 칸을 고르고 모양을 본다. 화면이 보낸 값만 규칙이 되므로 여기서 막는다. 설계 1.3
Json _checked(Store s, Json raw) {
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
  final tiers = raw['tiers'];
  if (tiers is! List ||
      tiers.length > maxTiers ||
      tiers.any((t) => t is! int || t <= 0 || t > maxSpend) ||
      [
        for (var i = 1; i < tiers.length; i++) tiers[i - 1] < tiers[i],
      ].contains(false)) {
    throw bad('실적 구간은 커지는 순서의 금액 3개까지다');
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
    if (!rewardTypes.containsKey(type)) throw bad('혜택 방식이 틀렸다');
    final okRate = rate is num && rate > 0 && rate <= 100 && fixed == null;
    final okFixed =
        fixed is int && fixed > 0 && fixed <= 1000000 && rate == null;
    if (!okRate && !okFixed) throw bad('혜택 크기는 % 하나나 원 하나다');
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
      'month_cap': ?cap,
      'from_tier': ?from,
    });
  }
  final copied = raw['copied'] ?? const [];
  if (copied is! List || copied.any((k) => k is! String)) {
    throw bad('복사한 혜택이 틀렸다');
  }
  final base = raw['base_card_id'];
  if (base != null && (base is! String || !s.catalog.cards.containsKey(base))) {
    throw bad('비슷한 카드가 틀렸다');
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

/// 만든다. 등록은 화면이 이어서 등록 시트로 한다. S13
Json createCustom(Store s, Json raw) {
  final input = _checked(s, raw);
  final base = input['base_card_id'] as String?;
  final now = s.clock();
  final id = 'custom-${newId(now)}';
  final card = cardJson(
    id,
    input,
    base == null ? null : _rulesToday(s, base),
    s.categoryNames,
    s.today(),
  );
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

/// 고친다. 그 카드의 모든 결제를 새 규칙으로 다시 계산한다. 혜택이 바뀐 결제 수를 돌려준다. S14, E67
Json updateCustom(Store s, String id, Json raw) {
  final old = s.db.select('select card_json from custom_cards where id = ?', [
    id,
  ]);
  if (old.isEmpty) throw ApiError(404, '직접 만든 카드가 아니다');
  final prev = jsonDecode(old.first['card_json'] as String) as Json;
  final input = {
    ..._checked(s, raw),
    'base_card_id': customInput(s, id)['base_card_id'],
  };
  final card = cardJson(
    id,
    input,
    ((prev['revisions'] as List).single as Json)['rules'] as Json,
    s.categoryNames,
    s.today(),
  );
  final now = s.clock();
  write(
    s,
    () => s.db.execute(
      'update custom_cards set card_json = ?, input_json = ?, updated_at = ? where id = ?',
      [jsonEncode(card), jsonEncode(input), ms(now), id],
    ),
  );
  s.reloadCustom();
  final owners = [
    for (final r in s.db.select('select id from user_cards where card_id = ?', [
      id,
    ]))
      r['id'] as String,
  ];
  final repriced = write(s, () => reprice(s, owners, [DateTime.utc(2000)]));
  return {'repriced': repriced};
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
  if (card == null) throw ApiError(404, '카드가 아니다');
  final rules = _rulesToday(s, baseId);
  final simple = <Json>[], copied = <Json>[];
  for (final b in rules['benefits'] as List) {
    final one = simpleOf(b as Json);
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
    'tiers': [
      for (final t in rules['tiers'] as List)
        if (t != 0) t,
    ],
    'benefits': simple,
    'copied': [for (final c in copied) c['key']],
    'copied_titles': [for (final c in copied) c['title']],
    'base_card_id': baseId,
  };
}
