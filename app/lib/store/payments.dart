/// 결제를 DB에서 읽어 엔진 모양으로 바꾼다. 서버 `cherry_api/payments.py`를 옮겼다. 작업 005 설계 5b절
///
/// 가게 이름으로 가맹점을 찾고, 앞선 결제나 고친 결제 때문에 다시 계산할 결제를 정한다
library;

import '../catalog/models.dart';
import '../engine/cond.dart';
import '../engine/engine.dart';
import '../engine/models.dart';
import '../engine/price.dart' show rankedAreas;
import 'store.dart';

Payment toPayment(Map<String, Object?> row, List<AppliedBenefit> benefits) =>
    Payment(
      id: row['id'] as String,
      userCardId: row['user_card_id'] as String,
      amount: row['amount'] as int,
      paidAt: fromMs(row['paid_at'] as int),
      merchant: row['merchant_key'] as String?,
      category: row['category_code'] as String?,
      channel: row['channel'] as String,
      region: row['region'] as String,
      installmentMonths: row['installment_months'] as int,
      interestFree: row['interest_free_installment'] == 1,
      paymentMethod: row['payment_method'] as String?,
      billing: row['billing'] as String?,
      cancelledAmount: row['cancelled_amount'] as int,
      cancelledAt: row['cancelled_at'] == null
          ? null
          : fromMs(row['cancelled_at'] as int),
      timeKnown: row['time_known'] == 1,
      benefits: benefits,
    );

/// 카드마다 지운 것을 뺀 모든 결제와 저장된 혜택. 엔진에 한도 기간 전체를 넘긴다. 결제 시각, 그다음 id 순서다
///
/// ponytail: 카드 한 장의 결제가 수천 건이 되면 한도 기간으로 줄인다
Map<String, List<Payment>> loadPayments(Store s, List<String> userCardIds) {
  final out = {for (final id in userCardIds) id: <Payment>[]};
  if (userCardIds.isEmpty) return out;
  final marks = List.filled(userCardIds.length, '?').join(', ');
  final rows = s.db.select(
    'select * from transactions where user_card_id in ($marks) and deleted_at is null '
    'order by paid_at, id',
    userCardIds,
  );
  final benefits = <String, List<AppliedBenefit>>{};
  for (final b in s.db.select(
    'select b.* from transaction_benefits b join transactions t on t.id = b.transaction_id '
    'where t.user_card_id in ($marks) and t.deleted_at is null order by b.benefit_key',
    userCardIds,
  )) {
    benefits
        .putIfAbsent(b['transaction_id'], () => [])
        .add(
          AppliedBenefit(
            key: b['benefit_key'],
            amount: b['amount'],
            value: b['value'],
            base: b['base_amount'],
          ),
        );
  }
  for (final r in rows) {
    out[r['user_card_id']]!.add(toPayment(r, benefits[r['id']] ?? const []));
  }
  return out;
}

/// 저장 전 결제의 id. 어떤 uuid 글자보다 뒤라 같은 시각의 저장된 결제 뒤에 온다
const draftId = '~draft';

/// 별칭 비교 값. 카탈로그 검사의 별칭 겹침 검사와 같다. 서버 `catalog_sync.py`의 alias_key
String aliasKey(String alias) => alias.replaceAll(' ', '').toLowerCase();

Map<String, String> aliasIndex(Catalog catalog) => {
  for (final m in catalog.merchants.values)
    for (final a in m.aliases) aliasKey(a): m.key,
};

/// 가게 이름의 가맹점. E15
///
/// 앞에서부터 띄어 쓴 낱말 몇 개를 이은 것이 별칭과 같으면 맞는 것으로 보고 가장 긴 별칭을 고른다.
/// "스타벅스 역삼점", "GS25 테헤란점", "LOTTE MART 잠실점"은 맞는다. "롯데하이마트 강남점", "멜론빵 전문점",
/// "이마트트레이더스 월계점"처럼 별칭 뒤에 글자가 붙은 낱말은 맞지 않는다. 2026-10-01 위험 검토 두 번
/// 붙여 쓴 "스타벅스역삼점"도 맞지 않아 사용자가 업종을 고른다. 엉뚱한 가맹점의 혜택으로 저장되는 것보다 낫다. E16
String? matchMerchant(Map<String, String> index, String? name) {
  final words = (name ?? '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final prefixes = {
    for (var k = 1; k <= words.length; k++) aliasKey(words.take(k).join()),
  };
  final hits = [
    for (final a in prefixes)
      if (index.containsKey(a)) a,
  ];
  if (hits.isEmpty) return null;
  return index[hits.reduce((a, b) => b.length > a.length ? b : a)];
}

DateTime _month(Payment p) => monthOf(localDay(p.paidAt));

/// 마지막 결제가 든 달. 결제가 없으면 start다. Python `max(..., default=start)`
DateTime _lastMonth(List<Payment> payments, DateTime start) => payments.isEmpty
    ? start
    : payments.map(_month).reduce((a, b) => b.isAfter(a) ? b : a);

List<Payment> _with(
  List<Payment> payments,
  Map<String, PaymentResult> results,
) => [
  for (final q in payments)
    results.containsKey(q.id)
        ? q.copyWith(benefits: results[q.id]!.benefits)
        : q,
];

/// 지나간 달이고 그 달 개정에 순위 혜택이 있으면 참이다. 그 달은 달 끝 순위로 계산한다. E48
///
/// ponytail: 달 첫날의 개정만 본다. 달 중간에 순위 혜택이 생기는 개정이 오면 그 달 결제마다 본다
bool rankedPast(Engine engine, UserCard card, DateTime month, DateTime now) {
  final found = engine.ctx.rulesOn(card.cardId, month);
  return month.isBefore(monthOf(localDay(now))) &&
      found != null &&
      rankedAreas(found.rules).isNotEmpty;
}

/// 결제일 개정에 취소한 달 기준 순위 그룹이 있는가. E55
bool cancelMonthRanked(Engine engine, UserCard card, Payment p) {
  final found = engine.ctx.rulesOn(card.cardId, localDay(p.paidAt));
  return found != null &&
      found.rules.ranked.any((r) => r.cancellation == 'cancel_month');
}

/// 새 결제 p의 혜택과, p 때문에 다시 계산한 결제의 혜택. 작업 005 설계 5b절
///
/// p보다 뒤 결제가 하나도 없으면 p만 계산한다. 있으면 p가 든 달부터 마지막 결제가 든 달까지 달마다 결제 시각 순서로
/// 다시 계산한다. 카드사처럼 앞 결제가 한도를 먼저 쓴다. E52. 연, 분기, 행사 기간 한도와 지난달 실적으로 바뀐 구간 E53,
/// 실적이 다음 달에 들어가는 결제의 연쇄가 모두 이 순서 계산으로 맞는다. 2026-10-01 사용자가 정했다
/// 지나간 달은 달 끝 순위로 계산한다. E48
Map<String, PaymentResult> pricedWith(
  Engine engine,
  UserCard card,
  List<Payment> history,
  Payment p,
  DateTime now,
) {
  final later = history.any((q) => byTime(q, p) > 0);
  if (!later && !rankedPast(engine, card, _month(p), now)) {
    return {p.id: engine.pricePayment(card, history, p)};
  }
  return repricedFrom(engine, card, [...history, p], _month(p), now);
}

/// start 달부터 마지막 결제가 든 달까지 달마다 결제 시각 순서로 다시 계산한다. 지나간 달은 달 끝 순위다. E48, E52, E56
Map<String, PaymentResult> repricedFrom(
  Engine engine,
  UserCard card,
  List<Payment> payments,
  DateTime start,
  DateTime now,
) {
  final thisMonth = monthOf(localDay(now));
  final out = <String, PaymentResult>{};
  var m = start;
  final last = _lastMonth(payments, start);
  while (!m.isAfter(last)) {
    final results = {
      for (final r in engine.priceMonth(
        card,
        payments,
        month: m,
        isFinal: m.isBefore(thisMonth),
      ))
        r.paymentId: r,
    };
    out.addAll(results);
    payments = _with(payments, results);
    m = addMonths(m, 1);
  }
  return out;
}

/// 새 카드 특례를 넣기 전의 기본 구간. 특례 구간은 결제와 상관없어 결제가 바꾸는 것은 기본 구간뿐이다
int? baseTier(
  Engine engine,
  UserCard card,
  List<Payment> payments,
  DateTime month,
) {
  final status = engine.spendStatus(card, payments, month);
  final found = engine.ctx.rulesOn(card.cardId, month);
  final prev = status.prevMonthCounted;
  if (found == null || prev == null) return status.tier;
  return found.rules.tiers
      .where((t) => t <= prev)
      .reduce((a, b) => a > b ? a : b);
}

/// 고치거나 취소한 결제 changed는 그 결제만 다시 계산한다. E50. drop은 이 카드에서 빠진 결제다
///
/// 그 뒤 start 다음 달부터 기본 구간이 저장된 상태와 처음 다른 달을 찾아 그 달부터 마지막 결제가 든 달까지 달마다
/// 결제 시각 순서로 다시 계산한다. 구간이 그대로인 뒤 달도 연, 분기, 행사 기간 한도가 바뀌어 함께 계산한다. E5, E54.
/// 2026-10-01 사용자가 정했다. 실적이 다음 달에 들어가는 결제가 있어 한 달을 건너 구간이 바뀔 수 있어 마지막 결제가 든
/// 달까지 찾는다. 지나간 달은 달 끝 순위로 계산한다. E48
Map<String, PaymentResult> changedWith(
  Engine engine,
  UserCard card,
  List<Payment> before,
  Payment? changed,
  String? drop,
  DateTime start,
  DateTime now, {
  bool rerank = true,
}) {
  final gone = {drop, changed?.id};
  final others = [
    for (final q in before)
      if (!gone.contains(q.id)) q,
  ];
  final out = <String, PaymentResult>{};
  var payments = others;
  if (changed != null) {
    out[changed.id] = engine.pricePayment(card, others, changed);
    payments = [
      ...others,
      changed.copyWith(benefits: out[changed.id]!.benefits),
    ];
  }
  final thisMonth = monthOf(localDay(now));
  // 고친 결제가 들거나 빠진 지나간 달에 순위 혜택이 있으면 그 달 전체를 달 끝 순위로 다시 계산한다. E48
  // 취소한 달 기준 순위 카드는 취소가 든 달의 영역 이용액도 바뀌어 그 달도 본다. E55
  final moved = [
    for (final q in before)
      if (gone.contains(q.id)) q,
    ?changed,
  ];
  final touched = {
    for (final q in moved) _month(q),
    for (final q in moved)
      if (q.cancelledAt != null && cancelMonthRanked(engine, card, q))
        monthOf(localDay(q.cancelledAt!)),
  };
  for (final m in touched.toList()..sort()) {
    if (rerank && rankedPast(engine, card, m, now)) {
      final results = {
        for (final r in engine.priceMonth(
          card,
          payments,
          month: m,
          isFinal: true,
        ))
          r.paymentId: r,
      };
      out.addAll(results);
      payments = _with(payments, results);
    }
  }
  final last = _lastMonth(payments, start);
  var m = start;
  var redo = false;
  while (m.isBefore(last)) {
    m = addMonths(m, 1);
    if (!redo &&
        baseTier(engine, card, before, m) ==
            baseTier(engine, card, payments, m)) {
      continue;
    }
    redo = true;
    final results = {
      for (final r in engine.priceMonth(
        card,
        payments,
        month: m,
        isFinal: m.isBefore(thisMonth),
      ))
        r.paymentId: r,
    };
    out.addAll(results);
    payments = _with(payments, results);
  }
  return out;
}
