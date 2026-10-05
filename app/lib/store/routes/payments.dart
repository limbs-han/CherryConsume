/// 저장 전 결제와 결제 저장. 서버 `cherry_api/routes/payments.py`를 옮겼다. 작업 005 설계 5b절. S3
///
/// 같은 번호 다시 보내기 E24는 서버가 없어 옮기지 않는다. 추천 요청 표 대신 결제에 "추천에서 기록함" 표시를 둔다.
/// 개정 행 번호 대신 계산에 쓴 개정의 시행일과 규칙 지문을 둔다. 작업 006 설계 4절
library;

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/models.dart';
import '../../engine/recommend.dart' show defaultAmount, order;
import '../answers.dart';
import '../db.dart';
import '../payments.dart';
import '../store.dart';
import 'catalog.dart';
import 'imports.dart' show methodOf;
import 'me.dart';

/// 이 업종은 온라인으로 채운다. 앱스토어처럼 업종이 기타인 온라인 가맹점은 사용자가 바꾼다
// ponytail: 업종으로만 정한다. 가맹점마다 채널을 카탈로그에 담으면 그쪽을 따른다
const online = {'online_shopping', 'delivery_app', 'streaming'};

const _billings = {
  'normal',
  'autopay',
  'subscription',
  'postpaid_transit',
  'app_prepay',
  'in_app',
};

ApiError _bad(String message) => ApiError(422, message);

/// 서버의 PaymentFields, Draft, NewPayment 검사. 데이터를 지키는 것만 옮겼다. 모르는 칸은 막지 않는다. 설계 4절
class PaymentBody {
  PaymentBody(Json b, {bool saving = false})
    : merchantName = _text(b, 'merchant_name', max: 100),
      category = _text(b, 'category'),
      paidAt = _time(b['paid_at']),
      channel = _oneOf(b, 'channel', const {'online', 'offline'}),
      region =
          _oneOf(b, 'region', const {'domestic', 'overseas'}) ?? 'domestic',
      installmentMonths = _int(b, 'installment_months', 1, 36) ?? 1,
      interestFree = _bool(b, 'interest_free'),
      paymentMethod = _text(b, 'payment_method'),
      billing = _oneOf(b, 'billing', _billings),
      amount = _int(b, 'amount', 1, maxSpend),
      userCardId = _text(b, 'user_card_id'),
      editing = _text(b, 'editing'),
      fromRecommendation = _bool(b, 'from_recommendation') {
    if (installmentMonths == 1 && interestFree) {
      throw _bad('일시불은 무이자할부가 아니다');
    }
    if (saving && (amount == null || userCardId == null || paidAt == null)) {
      throw _bad('금액, 보유 카드, 결제 시각이 있어야 한다');
    }
  }

  final String? merchantName, category, channel, paymentMethod, billing;
  final String? userCardId, editing;
  final DateTime? paidAt;
  final String region;
  final int installmentMonths;
  final int? amount;
  final bool interestFree, fromRecommendation;

  static String? _text(Json b, String key, {int? max}) {
    final v = b[key];
    if (v == null) return null;
    if (v is! String || (max != null && v.length > max)) {
      throw _bad('$key가 틀렸다');
    }
    return v;
  }

  static String? _oneOf(Json b, String key, Set<String> allowed) {
    final v = _text(b, key);
    if (v != null && !allowed.contains(v)) throw _bad('$key가 틀렸다');
    return v;
  }

  static int? _int(Json b, String key, int lo, int hi) {
    final v = b[key];
    if (v == null) return null;
    if (v is! int || v < lo || v > hi) throw _bad('$key가 틀렸다');
    return v;
  }

  static bool _bool(Json b, String key) {
    final v = b[key] ?? false;
    if (v is! bool) throw _bad('$key가 틀렸다');
    return v;
  }

  static DateTime? _time(Object? v) {
    if (v == null) return null;
    return awareTime(v) ?? (throw _bad('결제 시각은 시간대가 붙은 있는 날의 시각이어야 한다'));
  }
}

/// filled의 결과. 서버 dict의 칸이다
typedef Filled = ({
  String? merchant,
  String? category,
  String? merchantDisplay,
  String? categoryName,
  String channel,
  DateTime paidAt,
  String? billing,
});

Json _filledJson(Filled f) => {
  'merchant': f.merchant,
  'category': f.category,
  'merchant_display': f.merchantDisplay,
  'category_name': f.categoryName,
  'channel': f.channel,
  'paid_at': f.paidAt.toUtc().toIso8601String(),
  'billing': f.billing,
};

/// 가게 이름으로 가맹점과 업종을 채우고 채널과 시각의 기본값을 넣는다. S3
Filled filled(Store s, PaymentBody body) {
  final cat = s.catalog;
  if (body.category != null && !cat.categories.contains(body.category)) {
    throw _bad('모르는 업종이다');
  }
  if (body.paymentMethod != null &&
      !cat.paymentMethods.containsKey(body.paymentMethod)) {
    throw _bad('모르는 결제수단이다');
  }
  final now = s.clock();
  // 추천 요청에는 시각 칸이 없어 지금이다
  final paidAt = body.paidAt ?? now.toUtc();
  if (paidAt.isAfter(now.add(const Duration(days: 1)))) {
    throw _bad('결제 시각이 지금보다 하루 넘게 뒤다');
  }
  final merchant = merchantOf(s, body.merchantName);
  final m = merchant == null ? null : cat.merchants[merchant]!;
  final category =
      body.category ?? autoCategory(s, body.merchantName, merchant);
  // 청구 방식은 저장할 때 정해 둔다. 카탈로그의 가맹점 청구 방식이 바뀌어도 저장한 결제는 그대로다. E18
  final billing = body.billing ?? m?.billing;
  final channel =
      body.channel ??
      (category != null && online.contains(category.split('.').first)
          ? 'online'
          : 'offline');
  return (
    merchant: merchant,
    category: category,
    // 찾은 가맹점 이름. 별칭이 엉뚱한 가게에 걸렸으면 사용자가 화면에서 알아본다
    merchantDisplay: m?.name,
    categoryName: s.categoryNames[category],
    channel: channel,
    paidAt: paidAt,
    billing: billing,
  );
}

/// 가게 이름에서 간편결제 이름을 뗀 가게. 가맹점 찾기와 가게 기억이 모두 이것으로 한다. 가져오기는 원래 이렇게
/// 찾았는데 직접 넣기와 기록 고치기는 이름 전체로 찾아, 가져올 때 CGV이던 "네이버페이(CGV)" 결제를 고치면 네이버페이가
/// 됐다. 작업 016 단계 2~4 검토 중간 2
String shopOf(Store s, String name) => methodOf(s.catalog, name).$2;

/// 가게 이름의 카탈로그 가맹점. E15
String? merchantOf(Store s, String? name) =>
    name == null ? null : matchMerchant(s.aliases, shopOf(s, name));

/// 가게 기억의 열쇠. "네이버페이(CGV)"와 "네이버페이(KFC)"는 다른 가게고 "네이버페이 동네국밥집"과 "동네국밥집"은 같은
/// 가게다. 작업 016 설계 1절, 단계 2~4 검토 중간 1
String shopKey(Store s, String? name) =>
    name == null ? '' : nameKey(shopOf(s, name));

/// 부모 업종을 고른 것이 이미 그 자식 업종인 것을 덮지 않는다. "음식점"을 고르면 "일반음식점"인 결제는 그대로다. 덮으면
/// 자식 업종에만 주는 혜택이 빠진다. E47, 작업 016 단계 2~4 검토 중간 3
bool _covers(String chosen, String? had) =>
    had != null && had.startsWith('$chosen.');

/// 사용자가 고르지 않았을 때의 업종. 기억한 가게 이름의 업종이 카탈로그 가맹점의 업종보다 먼저다. 작업 016 설계 4절
String? autoCategory(Store s, String? name, String? merchant) =>
    rememberedCategory(s, name) ??
    (merchant == null ? null : s.catalog.merchants[merchant]!.category);

/// 사용자가 고른 가게 이름의 업종. 지금 카탈로그에 없는 업종은 쓰지 않는다. 작업 016 설계 3절
String? rememberedCategory(Store s, String? name) {
  final key = shopKey(s, name);
  if (key.isEmpty) return null;
  final found = s.db.select(
    'select category_code from merchant_categories where name_key = ?',
    [key],
  );
  final code = found.isEmpty ? null : found.first['category_code'] as String;
  return code != null && s.catalog.categories.contains(code) ? code : null;
}

/// 사용자가 결제에 고른 업종을 가게 이름으로 기억한다. 고르기 전 업종 before와 같거나 그 부모면 그대로 둔다. 카탈로그
/// 가맹점의 업종과 같으면 기억을 지워 카탈로그가 바뀌어도 카탈로그를 따른다. 작업 016 설계 3절
void rememberCategory(Store s, String? name, String? chosen, String? before) {
  final key = shopKey(s, name);
  if (key.isEmpty || chosen == null || chosen == before) return;
  if (_covers(chosen, before)) return;
  final merchant = merchantOf(s, name);
  if (merchant != null && s.catalog.merchants[merchant]!.category == chosen) {
    s.db.execute('delete from merchant_categories where name_key = ?', [key]);
    return;
  }
  s.db.execute(
    'insert into merchant_categories (name_key, category_code, updated_at) values (?, ?, ?) '
    'on conflict (name_key) do update set category_code = excluded.category_code, '
    'updated_at = excluded.updated_at',
    [key, chosen, ms(s.clock())],
  );
}

/// 같은 가게 이름의 다른 결제 가운데 업종이 code와 다른 결제. 지운 결제와 이미 code의 자식 업종인 결제는 뺀다. 작업
/// 016 설계 5절
List<Map<String, Object?>> sameName(
  Store s,
  String name,
  String code, [
  String? except,
]) {
  final key = shopKey(s, name);
  return [
    for (final r in s.db.select(
      'select id, user_card_id, merchant_name, category_code, paid_at from transactions '
      'where deleted_at is null and merchant_name is not null',
    ))
      if (r['id'] != except &&
          r['category_code'] != code &&
          !_covers(code, r['category_code'] as String?) &&
          shopKey(s, r['merchant_name'] as String) == key)
        {for (final c in r.keys) c: r[c]},
  ];
}

/// 사용자가 업종을 골라 바꿨을 때 같은 가게 결제 가운데 업종이 다른 것의 건수. 화면이 함께 바꿀지 묻는다. 고르지
/// 않았거나 그대로거나 같은 이름 결제가 없으면 null이다. 작업 016 설계 5절
Json? sameNameAsk(
  Store s,
  String? name,
  String? chosen,
  String? before,
  String except,
) {
  if (name == null ||
      shopKey(s, name).isEmpty ||
      chosen == null ||
      chosen == before ||
      _covers(chosen, before)) {
    return null;
  }
  final n = sameName(s, name, chosen, except).length;
  return n == 0
      ? null
      : {
          'count': n,
          'category': chosen,
          'category_name': s.categoryNames[chosen],
        };
}

/// 해지하지 않은 보유 카드와 그 답
List<Map<String, Object?>> myCards(Store s) => attachAnswers(s, [
  for (final r in s.db.select(
    'select * from user_cards where removed_at is null order by added_at, id',
  ))
    named(s, r),
]);

Map<String, Object?> mine(Store s, String tid) {
  final found = s.db.select(
    'select * from transactions where id = ? and deleted_at is null',
    [tid],
  );
  if (found.isEmpty) throw ApiError(404, '결제가 아니다');
  return rowMap(found.first);
}

Payment paymentOf(
  Map<String, Object?> row,
  PaymentBody body,
  int amount,
  Filled f,
  String pid,
) => Payment(
  id: pid,
  userCardId: row['id'] as String,
  amount: amount,
  paidAt: f.paidAt,
  merchant: f.merchant,
  category: f.category,
  channel: f.channel,
  region: body.region,
  installmentMonths: body.installmentMonths,
  interestFree: body.interestFree,
  paymentMethod:
      body.paymentMethod ??
      row['last_payment_method'] as String? ??
      'physical_card',
  billing: f.billing,
);

Json described(Store s, String cardId, DateTime at, PaymentResult result) {
  final found = s.engine.ctx.rulesOn(cardId, localDay(at));
  final titles = {
    for (final b in found?.rules.benefits ?? const <Benefit>[]) b.key: b.title,
  };
  return {
    'value': result.value,
    'benefits': [
      for (final b in result.benefits)
        {
          'key': b.key,
          'title': titles[b.key] ?? b.key,
          'amount': b.amount,
          'value': b.value,
        },
    ],
    'counted': result.spend.any((part) => part.amount > 0),
    'warnings': {for (final w in result.warnings) w.code}.toList()..sort(),
  };
}

/// 업종이 부모까지만 있어 혜택이나 실적 제외를 가리지 못하면 자식 업종을 묻는다. 결제를 저장한 자리에서 한 번이다. E47
Json? askCategory(Store s, PaymentResult result) {
  final needs = [
    for (final w in result.warnings)
      if (w.code == 'needs_input')
        for (final n in (w.data['needs'] as List? ?? const [])) n as List,
  ];
  final parents = {
    for (final n in needs)
      if (n.first == 'category') n[1] as String,
  }.toList()..sort();
  if (parents.isEmpty) return null;
  final names = s.categoryNames, children = s.engine.ctx.children;
  return {
    'parent': parents.first,
    'parent_name': names[parents.first],
    'children': [
      for (final c in [...?children[parents.first]]..sort())
        {'code': c, 'name': names[c]},
    ],
  };
}

/// 추천 줄을 다시 계산한 금액과 실적 인정 여부로 바꾼다. 무이자할부를 실적에서 빼는 카드가 실적 인정으로 앞에 서지 않게 한다
Recommendation again(Recommendation r, PaymentResult result) => Recommendation(
  userCardId: r.userCardId,
  cardId: r.cardId,
  value: result.value,
  benefits: r.benefits,
  counted: result.spend.any((part) => part.amount > 0),
  toKeep: r.toKeep,
  toNext: r.toNext,
  locked: r.locked,
  conditional: r.conditional,
  warnings: r.warnings,
);

/// 저장 전 결제. 카드 순위와 고른 카드의 예상 혜택. 고르지 않았으면 1순위를 고른다. S3
Json draft(Store s, Json raw) {
  final body = PaymentBody(raw);
  final f = filled(s, body);
  final engine = s.engine;
  final rows = myCards(s);
  final cards = {for (final r in rows) r['id'] as String: r};
  Map<String, Object?>? old;
  if (body.editing != null) {
    old = mine(s, body.editing!);
    if (body.amount != null &&
        (old['cancelled_amount'] as int) > body.amount!) {
      throw _bad('취소한 금액보다 작게 고칠 수 없다');
    }
    final card = old['user_card_id'] as String;
    if (!cards.containsKey(card)) {
      // 해지한 카드의 결제는 그 카드로 예상 혜택만 낸다. 순위에는 넣지 않는다. 위험 검토 8번
      final [one] = attachAnswers(s, [
        for (final r in s.db.select('select * from user_cards where id = ?', [
          card,
        ]))
          named(s, r),
      ]);
      cards[card] = one;
    }
  }
  if (cards.isEmpty) {
    return {..._filledJson(f), 'ranking': [], 'pick': null, 'estimate': null};
  }
  final editing = old?['id'] as String?;
  final payments = {
    for (final MapEntry(:key, :value) in loadPayments(
      s,
      cards.keys.toList(),
    ).entries)
      key: [
        for (final q in value)
          if (q.id != editing) q,
      ],
  };
  final query = Query(
    merchant: f.merchant,
    category: f.category,
    amount: body.amount,
    channel: f.channel,
    region: body.region,
    paymentMethod: body.paymentMethod,
  );
  final [ranked] = engine.recommend(
    [for (final r in rows) engineCard(r)],
    payments,
    [query],
    f.paidAt,
  );
  // 순위의 금액은 할부, 무이자, 지역까지 넣은 pricePayment로 다시 계산한다. 추천 질문에는 그 칸이 없어서
  // 1순위 카드의 순위 금액과 예상 혜택이 다를 수 있었다. 줄 세우기는 엔진의 order 그대로다. 같은 금액이면
  // 실적이 모자란 카드가 앞이다. 설계 4.2, S5
  final amount = body.amount ?? defaultAmount;

  (Payment, PaymentResult) pricedOn(String uid) {
    // 고치는 결제는 저장 경로 edit처럼 그 결제의 id와 취소를 그대로 둔다. 같은 시각 결제와의 순서와 남은 금액이 같다
    var p = paymentOf(cards[uid]!, body, amount, f, editing ?? draftId);
    if (old != null && body.amount != null) {
      p = p.copyWith(
        cancelledAmount: old['cancelled_amount'] as int,
        cancelledAt: old['cancelled_at'] == null
            ? null
            : fromMs(old['cancelled_at'] as int),
      );
    }
    return (p, engine.pricePayment(engineCard(cards[uid]!), payments[uid]!, p));
  }

  final priced = {for (final r in ranked) r.userCardId: pricedOn(r.userCardId)};
  final ranking = [
    for (final r in sortedStable([
      for (final r in ranked) again(r, priced[r.userCardId]!.$2),
    ], order))
      r.userCardId,
  ];
  final pick = body.userCardId ?? (ranking.isEmpty ? null : ranking.first);
  if (pick == null || !cards.containsKey(pick)) {
    throw ApiError(404, '보유 카드가 아니다');
  }
  Json? estimate;
  if (body.amount != null) {
    final (p, result) = priced[pick] ??= pricedOn(pick);
    estimate = {
      'user_card_id': pick,
      'payment_method': p.paymentMethod,
      ...described(s, cards[pick]!['card_id'] as String, p.paidAt, result),
    };
  }
  return {
    ..._filledJson(f),
    'ranking': [
      for (final i in ranking)
        {
          'user_card_id': i,
          'name': cards[i]!['name'],
          'value': priced[i]!.$2.value,
        },
    ],
    'pick': pick,
    'estimate': estimate,
  };
}

/// 결제 저장. 엔진이 계산한 혜택을 저장한다. 앞선 결제나 지난달 결제로 다시 계산할 결제가 생기면 함께 바꾼다. E52, E53
Json save(Store s, Json raw) {
  final body = PaymentBody(raw, saving: true);
  final f = filled(s, body);
  final cardId = body.userCardId!;
  return write(s, () {
    final found = s.db.select(
      'select * from user_cards where id = ? and removed_at is null',
      [cardId],
    );
    if (found.isEmpty) throw ApiError(404, '보유 카드가 아니다');
    final row = named(s, found.first);
    attachAnswers(s, [row]);
    final engine = s.engine, now = s.clock();
    final pid = newId(now);
    final p = paymentOf(row, body, body.amount!, f, pid);
    final history = loadPayments(s, [cardId])[cardId]!;
    final results = pricedWith(engine, engineCard(row), history, p, now);
    final result = results[pid]!;

    // 계산에 쓴 개정의 시행일과 규칙 지문. 개정 표가 없어 행 번호 대신 둔다. E18
    (String?, String?) revisionOf(DateTime at) {
      final rev = engine.ctx.rulesOn(row['card_id'] as String, localDay(at));
      return rev == null
          ? (null, null)
          : (dayText(rev.effectiveFrom), rev.sha256);
    }

    final (revFrom, revSha) = revisionOf(p.paidAt);
    s.db.execute(
      'insert into transactions (id, user_card_id, amount, merchant_name, merchant_key, category_code, paid_at, '
      'installment_months, interest_free_installment, channel, region, payment_method, billing, revision_from, '
      "revision_sha, from_recommendation, source, created_at, updated_at) "
      "values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual', ?, ?)",
      [
        pid,
        cardId,
        p.amount,
        body.merchantName,
        p.merchant,
        p.category,
        ms(p.paidAt),
        p.installmentMonths,
        p.interestFree ? 1 : 0,
        p.channel,
        p.region,
        p.paymentMethod,
        p.billing,
        revFrom,
        revSha,
        body.fromRecommendation ? 1 : 0,
        ms(now),
        ms(now),
      ],
    );
    // 업종 고르기로 고른 업종이 자동 업종과 다르면 가게 이름으로 기억한다. 작업 016 설계 3절
    final auto = autoCategory(s, body.merchantName, f.merchant);
    rememberCategory(s, body.merchantName, body.category, auto);
    // 다시 계산한 결제 가운데 혜택이 바뀐 것만 저장된 혜택과 계산에 쓴 개정을 바꾼다. E52, E53
    final before = {for (final q in history) q.id: q};
    List<AppliedBenefit> byKey(List<AppliedBenefit> bs) =>
        [...bs]..sort((a, b) => a.key.compareTo(b.key));
    bool same(String tid, PaymentResult r) {
      final a = byKey(r.benefits), b = byKey(before[tid]!.benefits ?? const []);
      return a.length == b.length &&
          [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
    }

    final changed = [
      for (final MapEntry(key: tid, value: r) in results.entries)
        if (tid != pid && !same(tid, r)) tid,
    ];
    for (final tid in changed) {
      final (from, sha) = revisionOf(before[tid]!.paidAt);
      s.db.execute(
        'delete from transaction_benefits where transaction_id = ?',
        [tid],
      );
      s.db.execute(
        'update transactions set revision_from = ?, revision_sha = ?, updated_at = ? where id = ?',
        [from, sha, ms(now), tid],
      );
    }
    for (final tid in [pid, ...changed]) {
      for (final b in results[tid]!.benefits) {
        s.db.execute(
          'insert into transaction_benefits (transaction_id, benefit_key, amount, value, base_amount) '
          'values (?, ?, ?, ?, ?)',
          [tid, b.key, b.amount, b.value, b.base],
        );
      }
    }
    s.db.execute('update user_cards set last_payment_method = ? where id = ?', [
      p.paymentMethod,
      cardId,
    ]);
    // 혜택이 바뀐 다른 결제 수. 앱이 알린다
    return {
      'id': pid,
      'repriced': changed.length,
      ...described(s, row['card_id'] as String, p.paidAt, result),
      'ask_category': askCategory(s, result),
      'same_name': sameNameAsk(s, body.merchantName, body.category, auto, pid),
    };
  });
}
