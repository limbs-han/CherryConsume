/// 카드사 칩, 카드 검색, 등록 미리보기. 서버 `cherry_api/routes/catalog.py`를 옮겼다. 작업 005 설계 5절
library;

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/models.dart';
import '../../engine/spend.dart';
import '../store.dart';

/// 지난달 쓴 금액의 상한 1억 원
const maxSpend = 100000000;

final _space = RegExp(r'\s+');

String _key(String text) => text.replaceAll(_space, '').toLowerCase();

/// 판매 중인 카드만 새로 등록한다. 단종 카드는 검색에서 숨긴다. E19
CatalogCard registrable(Store s, String cardId) {
  final card = s.catalog.cards[cardId];
  if (card == null || card.status != 'on_sale') {
    throw ApiError(404, '등록할 수 있는 카드가 아니다');
  }
  return card;
}

/// 혜택이 day에 고른 옵션에 맞는지 보는 함수. 엔진처럼 고르지 않은 옵션은 기본값으로 본다. 기본값이 없으면 그 옵션의
/// 혜택은 뺀다. 오늘부터 바뀌는 옵션이 있어 달 첫날이 아니라 그날로 본다
bool Function(Benefit) optionPicked(Rules rules, UserCard card, DateTime day) {
  final chosen = <String, String?>{
    for (final o in rules.options) o.key: o.defaultChoice,
  };
  for (final p in sortedStable(
    card.options,
    (a, b) => a.effectiveFrom.compareTo(b.effectiveFrom),
  )) {
    if (!p.effectiveFrom.isAfter(day)) chosen[p.option] = p.choice;
  }
  // ponytail: when의 첫 단계만 본다. any_of 안의 옵션 조건은 놓친다. 지금 카탈로그에는 없다
  return (b) => !b.when.any(
    (c) =>
        c.option != null &&
        !c.option!.entries.every((e) => e.value.contains(chosen[e.key])),
  );
}

/// 행사 기간 안인가. 엔진 benefitMatch와 같다
bool inPeriod(Benefit b, DateTime day) =>
    !((b.validFrom != null && day.isBefore(b.validFrom!)) ||
        (b.validUntil != null && day.isAfter(b.validUntil!)));

/// 그 달에 받는 혜택. 엔진처럼 새 카드 특례 구간을 혜택마다 본다. 하한과 상한을 모두 넣는다. 행사 기간은 day로 본다
///
/// 제목은 한 개정 안에서 겹칠 수 있어 혜택으로 돌려준다. IBK 나라사랑의 편의점 10% 청구할인 둘이 그렇다.
/// 옵션을 골라야 받는 혜택은 고른 선택지나 기본값에 맞을 때만 넣는다
List<Benefit> benefitsAt(
  Rules rules,
  UserCard card,
  DateTime month,
  SpendStatus status,
  DateTime day,
) {
  final base = prevMonthTier(rules, status);
  final picked = optionPicked(rules, card, day);
  return [
    for (final b in rules.benefits)
      if (picked(b) && inPeriod(b, day))
        if (_inTier(b, rules, newCardTier(card, month, rules, b.key, base).$1))
          b,
  ];
}

/// 지난달 실적으로 정한 기본 구간. 특례는 넣지 않는다
int prevMonthTier(Rules rules, SpendStatus status) {
  final prev = status.prevMonthCounted;
  return prev != null
      ? rules.tiers.where((t) => t <= prev).reduce((a, b) => a > b ? a : b)
      : (status.tier ?? 0);
}

bool _inTier(Benefit b, Rules rules, int tier) {
  final lo = b.tiers?.start ?? rules.tiers.first;
  final hi = b.tiers?.end ?? rules.tiers.last;
  return lo <= tier && tier <= hi;
}

List<int> tiersShown(Revision? found) => shownTiers(found?.rules.tiers);

/// 0원 구간을 뺀 실적 구간
List<int> shownTiers(List<int>? tiers) => [
  for (final t in tiers ?? const <int>[])
    if (t > 0) t,
];

List<Json> issuers(Store s) {
  final selling = {
    for (final c in s.catalog.cards.values)
      if (c.status == 'on_sale') c.issuer,
  };
  return [
    for (final i in s.catalog.issuers.values)
      // 카드 추가의 카드사 칩은 짧은 이름이다. 작업 011 설계 2절 A2
      if (selling.contains(i.id)) {'code': i.id, 'name': i.shortName ?? i.name},
  ]..sort((a, b) => (a['name'] as String).compareTo(b['name']));
}

/// 업종 칩. 자식 업종 code는 부모 code를 붙인 값이다
List<Json> categories(Store s) => [
  for (final c in s.catalog.categoryTree)
    {
      'code': c.code,
      'name': c.name,
      'children': [
        for (final ch in c.children)
          {'code': '${c.code}.${ch.code}', 'name': ch.name},
      ],
    },
];

List<Json> paymentMethods(Store s) => [
  for (final m in s.catalog.paymentMethods.values)
    {'key': m.key, 'name': m.name},
];

List<Json> cards(Store s, {String q = '', String? issuer}) {
  // 구간은 미리보기, 홈과 같게 이달 1일의 개정에서 읽는다. 엔진이 이달 구간을 그 개정으로 정한다. 규칙 파일을 열지
  // 않게 목록의 개정 머리에서 읽는다. 작업 014 설계 4절
  final month = monthOf(s.today()), want = _key(q);
  final out = <Json>[];
  for (final c in s.catalog.cards.values) {
    final issuerName = s.catalog.issuers[c.issuer]!.name;
    if (c.status != 'on_sale' || (issuer != null && c.issuer != issuer)) {
      continue;
    }
    if (want.isNotEmpty &&
        ![
          c.name,
          ...c.searchNames,
          issuerName,
        ].any((n) => _key(n).contains(want))) {
      continue;
    }
    final domestic = [
      for (final f in c.annualFees)
        if (f.scope == 'domestic') f.amount,
    ];
    final fees = domestic.isNotEmpty
        ? domestic
        : [for (final f in c.annualFees) f.amount];
    out.add({
      'id': c.id,
      'name': c.name,
      'issuer': c.issuer,
      'issuer_name': issuerName,
      'kind': c.kind,
      'annual_fee': fees.isEmpty ? null : fees.reduce((a, b) => a < b ? a : b),
      'tiers': shownTiers(s.engine.ctx.headOn(c.id, month)?.tiers),
    });
  }
  return out..sort((a, b) {
    final i = (a['issuer_name'] as String).compareTo(b['issuer_name']);
    return i != 0 ? i : (a['name'] as String).compareTo(b['name']);
  });
}

/// 등록 시트. 지난달 쓴 금액으로 이번 달 구간을 보여 준다. 비우면 최저 구간이다. E1
Json preview(Store s, String cardId, {int? prev, DateTime? startedOn}) {
  if (prev != null && (prev < 0 || prev > maxSpend)) {
    throw ApiError(422, '지난달 쓴 금액은 0원부터 1억 원까지다');
  }
  registrable(s, cardId);
  final day = s.today(), month = monthOf(day);
  final card = UserCard(
    id: 'preview',
    cardId: cardId,
    registeredOn: day,
    assumedPrevMonthSpend: prev,
    startedOn: startedOn,
  );
  final status = s.engine.spendStatus(card, const [], month);
  final found = s.engine.ctx.rulesOn(cardId, month);
  return {
    'tier': status.tier,
    'tier_source': status.tierSource,
    'tiers': tiersShown(found),
    'benefits': found != null && status.tier != null
        ? [
            for (final b in benefitsAt(found.rules, card, month, status, day))
              b.title,
          ]
        : <String>[],
    'warnings': [for (final w in status.warnings) w.code],
  };
}
