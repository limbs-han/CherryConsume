/// 추천. 업종별 지금 1순위, 최근 간 가게, 가게와 업종 추천. 서버 `cherry_api/routes/recommend.py`를 옮겼다.
/// 작업 005 설계 5c절. S4
///
/// 추천 요청 표와 추천 결과 표는 두지 않는다. 추천을 따랐는지는 결제의 "추천에서 기록함" 표시로 본다. 그래서
/// request_id는 늘 비어 있다. 작업 006 설계 4절
library;

import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/models.dart';
import '../payments.dart';
import '../store.dart';
import 'me.dart';
import 'payments.dart';

/// 업종별 지금 1순위의 업종. 시안의 다섯에 자주 쓰는 일곱을 더했다. Claude가 정했다
/// 지하철, 시내버스, 휴대폰 요금은 혜택 대부분이 후불교통이나 자동납부 조건이라 가게 없는 질문으로는 1순위를 맞게 못 낸다.
/// 담을 수 없는 것은 계산하지 않는다는 규칙대로 뺐다. 2026-10-01 위험 검토
const topCategories = [
  'cafe',
  'convenience',
  'restaurant.general',
  'restaurant.fastfood',
  'delivery_app',
  'online_shopping',
  'grocery_mart',
  'department_store',
  'taxi',
  'fuel',
  'movie',
  'pharmacy',
];

/// 청구 방식 조건이 붙은 혜택의 대상 업종. 가게 없이 업종만 물으면 후불교통인지 자동납부인지 몰라 1순위를 맞게 못 낸다.
/// 목록 파일이 적어 둔 값이 있으면 그것을 쓴다. 모든 카드의 규칙 파일을 열지 않기 위해서다. 작업 014 설계 4절
Set<String> billingBound(Catalog catalog) {
  if (catalog.billingBound case final listed?) return listed;
  bool hasBilling(List<Condition> conditions) => conditions.any(
    (c) => c.billing != null || hasBilling(c.anyOf ?? const []),
  );
  return {
    for (final card in catalog.cards.values)
      for (final rev in card.revisions)
        for (final b in rev.rules.benefits)
          if (hasBilling(b.when)) ...b.target.categories,
  };
}

final _bound = Expando<Set<String>>();

bool bound(Store s, String code) {
  final found = _bound[s.catalog] ??= billingBound(s.catalog);
  return found.contains(code) || found.contains(code.split('.').first);
}

/// 조건부 혜택 가운데 사실과 옵션의 답. 같은 질문은 더 받는 금액이 가장 큰 것 하나다
List<Json> asks(Rules? rules, List<ConditionalBenefit> conditional) {
  if (rules == null) return [];
  final facts = {for (final f in rules.facts) f.key: f};
  final options = {for (final o in rules.options) o.key: o};
  final out = <Json>[];
  final seen = <(String, String)>{};
  for (final c in sortedStable(
    conditional,
    (a, b) => b.extra.compareTo(a.extra),
  )) {
    final keys = c.needs.keys.toSet();
    Json item;
    if (keys.length == 1 &&
        keys.first == 'fact' &&
        facts.containsKey(c.needs['fact'])) {
      final f = facts[c.needs['fact']]!;
      item = {
        'kind': 'fact',
        'key': f.key,
        'scope': f.scope,
        'question': f.ask,
        'extra': c.extra,
      };
    } else if (keys.length == 2 &&
        keys.containsAll(const {'option', 'choice'}) &&
        options.containsKey(c.needs['option'])) {
      final o = options[c.needs['option']]!;
      final title = o.choices
          .firstWhere((ch) => ch.key == c.needs['choice'])
          .title;
      item = {
        'kind': 'option',
        'key': o.key,
        'choice': c.needs['choice'],
        'question': '${o.title} · $title',
        'extra': c.extra,
      };
    } else {
      continue;
    }
    if (seen.add((item['kind'] as String, item['key'] as String))) {
      out.add(item);
    }
  }
  return out;
}

/// 카드마다 순위, 혜택 금액, 이유 한 줄, 할인과 적립 구분, 결제수단을 바꾸면 더 받는 금액
List<Json> rowsOf(
  Store s,
  Map<String, Map<String, Object?>> cards,
  List<Recommendation> recs,
  DateTime at,
) {
  final engine = s.engine, cat = s.catalog;
  final out = <Json>[];
  for (final (i, r) in recs.indexed) {
    final found = engine.ctx.rulesOn(r.cardId, localDay(at));
    final benefits = {
      for (final b in found?.rules.benefits ?? const <Benefit>[]) b.key: b,
    };
    final best = r.benefits.isEmpty
        ? null
        : r.benefits.reduce((a, b) => b.value > a.value ? b : a);
    final b = best == null ? null : benefits[best.key];
    final received = {
      for (final x in r.benefits)
        if (x.value > 0) x.key,
    };
    // 받은 혜택의 한도 때문에 줄었을 때만 이유로 보인다. 받지 않은 혜택의 한도 소진은 이유가 아니다
    final limited =
        r.value > 0 &&
        r.warnings.any(
          (w) => w.code == 'limit_exhausted' && received.contains(w.benefit),
        );
    final codes = {for (final w in r.warnings) w.code};
    // 받는 혜택의 종류를 모두 준다. 할인과 적립을 함께 받으면 둘 다 보인다. E13
    final rewards = {
      for (final x in r.benefits)
        if (benefits.containsKey(x.key) && x.value > 0)
          benefits[x.key]!.reward.type,
    }.toList()..sort();
    final payWith = <Json>[];
    for (final c in r.conditional) {
      final method =
          c.needs.keys.toSet().length == 1 &&
              c.needs.containsKey('payment_method')
          ? c.needs['payment_method'] as String?
          : null;
      final m = cat.paymentMethods[method];
      if (m != null) {
        payWith.add({
          'payment_method': method,
          'name': m.name,
          'extra': c.extra,
        });
      }
    }
    out.add({
      'rank': i + 1,
      'user_card_id': r.userCardId,
      'name': cards[r.userCardId]!['name'],
      'value': r.value,
      'title': b?.title,
      'rewards': rewards,
      'pay_with': payWith,
      // 사실이나 옵션을 답하면 더 받는 금액과 그 질문. 앱은 카드 상세나 설정으로 보낸다. 작업 005 설계 5e
      'ask': asks(found?.rules, r.conditional),
      // 한도를 다 써 0원이 된 카드. E10
      'exhausted': r.value == 0 && codes.contains('limit_exhausted'),
      // 한도가 남은 만큼만 받는 카드. 작업 004 의도 성공 기준 3대로 한도 때문에 줄었을 때 이유로 보인다
      'limited': limited,
      // 달 끝 순위로 정해지는 혜택. E48
      'provisional': codes.contains('ranked_provisional'),
      // 결제 입력으로 가리지 못해 문장으로 남은 조건. 조건이 없는 것처럼 계산하고 확인 필요를 붙인다. E12, 작업 011 설계 2절 T5
      'checks': [
        for (final w in r.warnings)
          if (w.code == 'check_conditions')
            ...(w.data['sentences'] as List).cast<String>(),
      ],
    });
  }
  return out;
}

/// 업종마다 가게 없이 1만 원으로 추천을 돌린 1위. 설계 문서 6.5
List<Json> top(Store s) {
  final rows = myCards(s);
  if (rows.isEmpty) return [];
  final cards = {for (final r in rows) r['id'] as String: r};
  final now = s.clock();
  final names = s.categoryNames;
  // 카탈로그에서 빠진 업종은 건너뛴다. 카탈로그는 봇이 커밋해 코드와 따로 바뀐다
  final codes = [
    for (final c in topCategories)
      if (names.containsKey(c) && !bound(s, c)) c,
  ];
  // 채널은 결과 화면과 같게 업종으로 채운다. 같은 줄의 금액이 두 화면에서 다르지 않게 한다
  final queries = [
    for (final c in codes)
      Query(
        category: c,
        channel: online.contains(c.split('.').first) ? 'online' : 'offline',
      ),
  ];
  final answers = s.engine.recommend(
    [for (final r in rows) engineCard(r)],
    loadPayments(s, cards.keys.toList()),
    queries,
    now,
  );
  return [
    for (final (i, c) in codes.indexed)
      {
        'category': c,
        'category_name': names[c],
        ...rowsOf(s, cards, answers[i].take(1).toList(), now).first,
      },
  ];
}

/// 최근 간 가게 4곳. 결제에 적은 이름 그대로
List<String> recent(Store s) => [
  for (final r in s.db.select(
    'select merchant_name from transactions where deleted_at is null and merchant_name is not null '
    'group by merchant_name order by max(paid_at) desc limit 4',
  ))
    r['merchant_name'] as String,
];

/// 가게나 업종의 추천. 서버의 Ask 몸통을 받는다. 금액이 없으면 1만 원으로 계산한다. E11
Json recommend(Store s, Json raw) {
  final body = PaymentBody({...raw, 'paid_at': null});
  final f = filled(s, body);
  final result = {
    'merchant': f.merchant,
    'merchant_display': f.merchantDisplay,
    'category': f.category,
    'category_name': f.categoryName,
    'amount': body.amount,
  };
  // 담을 수 없는 질문은 계산하지 않는다. 가게 없이 지하철처럼 청구 방식에 따라 혜택이 갈리는 업종을 물을 때다
  if (f.merchant == null && f.category != null && bound(s, f.category!)) {
    return {
      ...result,
      'request_id': null,
      'unsupported': 'billing',
      'ranking': [],
    };
  }
  final rows = myCards(s);
  final cards = {for (final r in rows) r['id'] as String: r};
  final now = f.paidAt;
  final query = Query(
    merchant: f.merchant,
    category: f.category,
    amount: body.amount,
    channel: f.channel,
    region: body.region,
    paymentMethod: body.paymentMethod,
  );
  final recs = rows.isEmpty
      ? <Recommendation>[]
      : s.engine
            .recommend(
              [for (final r in rows) engineCard(r)],
              loadPayments(s, cards.keys.toList()),
              [query],
              now,
            )
            .first;
  return {
    ...result,
    'request_id': null,
    'unsupported': null,
    'ranking': rowsOf(s, cards, recs, now),
  };
}
