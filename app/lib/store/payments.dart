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

/// 맞추거나 열쇠를 만들기 전에 뺄 괄호. 영문만 든 괄호와 회사 표시다. "씨유(CU)", "(주)". 다른 괄호 안은 가게 이름일
/// 수 있어 남긴다. "네이버페이(스타벅스)", "이마트(트레이더스)월계점". 작업 016 단계 1 검토 낮음 6
final _noise = RegExp(r'\([A-Za-z0-9 &.\-]*\)|\((주|유|사|재)\)|㈜');

/// 같은 가게를 알아보는 열쇠. 영문 괄호와 회사 표시를 빼고, 괄호 글자와 띄어쓰기를 빼고, 영문은 소문자다. "씨유(CU)
/// 가게점"과 "씨유가게점"은 같은 가게고, "네이버페이(꽃집)"과 "네이버페이(치킨집)"은 다른 가게다. 작업 016 설계 1절
String nameKey(String name) => name
    .replaceAll(_noise, '')
    .replaceAll(RegExp(r'[\s()\[\]]'), '')
    .toLowerCase();

/// 붙여 쓴 지점 이름을 맞출 업종. 지점이 많고 이름 뒤에 다른 낱말이 붙는 일이 적다. 2026-10-05 사용자가 골랐다
const _branchy = {'convenience', 'cafe'};

/// 흔한 낱말과 같은 별칭. 붙여 쓴 이름으로는 맞추지 않는다. "커피빈스강남점"은 동네 카페다. 작업 016 단계 1 검토 중간 4
/// ponytail: 카탈로그를 사람이 보고 넣는다. 가맹점이 늘면 카탈로그 칸으로 옮긴다
const _common = {'커피빈'};

/// 가게 이름 찾기 표. names는 별칭에서 가맹점으로, glued는 붙여 쓴 지점 이름을 맞출 편의점과 카페의 별칭과 공식
/// 이름이다. 편의점과 카페는 공식 이름도 별칭처럼 맞춘다. 다른 업종의 공식 이름은 "KT",
/// "FLO"처럼 흔한 낱말과 겹쳐 "KT 대리점"이 통신요금 혜택에 맞아 넣지 않는다. 작업 016 설계 2절, 단계 1 검토 높음 1
typedef MerchantIndex = ({
  Map<String, String> names,
  Map<String, String> glued,
});

MerchantIndex aliasIndex(Catalog catalog) {
  final ms = catalog.merchants.values;
  bool branchy(Merchant m) => _branchy.contains(m.category.split('.').first);
  return (
    // 공식 이름은 다른 가맹점의 별칭과 겹치면 별칭을 쓴다. 뒤에 넣은 별칭이 앞의 이름을 덮는다
    names: {
      for (final m in ms)
        if (branchy(m)) aliasKey(m.name): m.key,
      for (final m in ms)
        for (final a in m.aliases) aliasKey(a): m.key,
    },
    glued: {
      for (final m in ms)
        if (branchy(m))
          for (final a in [m.name, ...m.aliases])
            if (!_common.contains(a)) aliasKey(a): m.key,
    },
  );
}

/// 붙여 쓴 지점 이름의 나머지. 한글 세 글자 이상이고 "점"으로 끝난다
final _branch = RegExp(r'^[가-힣]{2,}점$');

/// 가게 이름의 가맹점. E15
///
/// 앞에서부터 띄어 쓴 낱말 몇 개를 이은 것이 별칭과 같으면 맞는 것으로 보고 가장 긴 별칭을 고른다.
/// "스타벅스 역삼점", "GS25 테헤란점", "LOTTE MART 잠실점"은 맞는다. "롯데하이마트 강남점", "멜론빵 전문점",
/// "이마트트레이더스 월계점"처럼 별칭 뒤에 글자가 붙은 낱말은 맞지 않는다. 2026-10-01 위험 검토 두 번
/// 붙여 쓴 "롯데마트잠실점"도 맞지 않아 사용자가 업종을 고른다. 엉뚱한 가맹점의 혜택으로 저장되는 것보다 낫다. E16
///
/// 영문 괄호와 회사 표시는 띄어쓰기로 보고 맞춘다. "씨유(CU) 가게점"은 "씨유 가게점"이다. 편의점과 카페는 첫 낱말에
/// 지점 이름을 붙여 쓴 "세븐일레븐가게점", "스타벅스역삼점"도 맞는다. 나머지는 한글 세 글자 이상이고 "점"으로
/// 끝나야 한다. "CUBE점", "CU-BE점", "스타벅스점"은 맞지 않는다. 2026-10-05 사용자가 편의점과 카페만 골랐다. 작업 016
/// 설계 2절, 단계 1 검토 중간 3, 낮음 5
String? matchMerchant(MerchantIndex index, String? name) {
  final words = (name ?? '')
      .replaceAll(_noise, ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final prefixes = {
    for (var k = 1; k <= words.length; k++) aliasKey(words.take(k).join()),
  };
  String? longest(Iterable<String> keys) =>
      keys.isEmpty ? null : keys.reduce((a, b) => b.length > a.length ? b : a);
  final hit = longest(prefixes.where(index.names.containsKey));
  if (hit != null) return index.names[hit];
  if (words.isEmpty) return null;
  final first = aliasKey(words.first);
  final glued = longest([
    for (final a in index.glued.keys)
      if (first.startsWith(a) && _branch.hasMatch(first.substring(a.length))) a,
  ]);
  return glued == null ? null : index.glued[glued];
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
