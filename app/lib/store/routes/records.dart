/// 기록 탭. 달별 결제 목록, 고치기, 취소, 지우기. 서버 `cherry_api/routes/records.py`를 옮겼다. 작업 005 설계 5d절. S7, S8
///
/// 서버의 카드 행 잠금은 쓰기 하나를 트랜잭션 하나로 묶는 것으로 대신한다. 쓰기 안에 await가 없어 다른 쓰기가
/// 끼어들지 않는다. 그래서 잠근 뒤 다시 읽는 locked_payment는 옮기지 않았다. 작업 006 설계 4절
library;

import 'package:sqlite3/sqlite3.dart';

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/models.dart';
import '../../engine/price.dart' show beforeCancel, buildLedger;
import '../../engine/spend.dart' show spendParts;
import '../answers.dart';
import '../payments.dart';
import '../store.dart';
import 'me.dart';
import 'payments.dart';

/// 계산에 쓴 개정의 시행일과 규칙 지문. 서버의 revision_for가 돌려주던 개정 행 번호 대신이다
(String?, String?) revisionFor(Store s, String cardId, DateTime at) {
  final rev = s.engine.ctx.rulesOn(cardId, localDay(at));
  return rev == null ? (null, null) : (dayText(rev.effectiveFrom), rev.sha256);
}

/// 결제를 바꾸는 보유 카드 행과 그 답. 해지한 카드도 읽는다
Map<String, Map<String, Object?>> lockCards(Store s, Set<String> ids) {
  final list = ids.toList()..sort();
  final marks = List.filled(list.length, '?').join(', ');
  return {
    for (final r in attachAnswers(s, [
      for (final r in s.db.select(
        'select * from user_cards where id in ($marks) order by id',
        list,
      ))
        named(s, r),
    ]))
      r['id'] as String: r,
  };
}

/// 다시 계산한 결제의 혜택과 개정을 쓴다. always는 고친 결제라 늘 쓴다. 혜택이 바뀐 다른 결제 수를 돌려준다
int store(
  Store s,
  String cardId,
  Map<String, PaymentResult> results,
  Map<String, Payment> before,
  Set<String> always,
  DateTime now,
) {
  List<AppliedBenefit> byKey(List<AppliedBenefit> bs) =>
      [...bs]..sort((a, b) => a.key.compareTo(b.key));
  var changed = 0;
  for (final MapEntry(key: tid, value: r) in results.entries) {
    final old = before[tid];
    final a = byKey(r.benefits), b = byKey(old?.benefits ?? const []);
    final same =
        old != null &&
        a.length == b.length &&
        [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
    if (!always.contains(tid) && same) continue;
    if (!always.contains(tid)) changed += 1;
    s.db.execute('delete from transaction_benefits where transaction_id = ?', [
      tid,
    ]);
    if (old != null && !always.contains(tid)) {
      final (from, sha) = revisionFor(s, cardId, old.paidAt);
      s.db.execute(
        'update transactions set revision_from = ?, revision_sha = ?, updated_at = ? where id = ?',
        [from, sha, ms(now), tid],
      );
    }
    for (final x in r.benefits) {
      s.db.execute(
        'insert into transaction_benefits (transaction_id, benefit_key, amount, value, base_amount) '
        'values (?, ?, ?, ?, ?)',
        [tid, x.key, x.amount, x.value, x.base],
      );
    }
  }
  return changed;
}

/// 그 달 결제를 최근 순으로. 해지한 카드의 결제도 보인다. 받은 혜택은 저장된 혜택이다. E18
Json records(Store s, {String? month, String? card}) {
  final DateTime m;
  if (month == null) {
    m = monthOf(s.today());
  } else {
    final found = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(month);
    final mm = found == null ? 0 : int.parse(found.group(2)!);
    if (found == null || mm < 1 || mm > 12) {
      throw ApiError(422, '달은 2026-09처럼 쓴다');
    }
    m = day(int.parse(found.group(1)!), mm, 1);
  }
  final (start, end) = monthRange(m);
  final cards = {
    for (final r in attachAnswers(s, [
      for (final r in s.db.select(
        'select * from user_cards order by added_at, id',
      ))
        named(s, r),
    ]))
      r['id'] as String: r,
  };
  final rows = s.db.select(
    'select * from transactions where deleted_at is null and paid_at >= ? and paid_at < ? '
    'and (? is null or user_card_id = ?) order by paid_at desc, id desc',
    [ms(start), ms(end), card, card],
  );
  final benefits = <String, List<AppliedBenefit>>{};
  if (rows.isNotEmpty) {
    final marks = List.filled(rows.length, '?').join(', ');
    for (final b in s.db.select(
      'select * from transaction_benefits where transaction_id in ($marks) order by benefit_key',
      [for (final r in rows) r['id']],
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
  }
  final engine = s.engine, names = s.categoryNames;
  final out = <Json>[];
  final history = <String, List<Payment>>{};
  for (final row in rows) {
    final p = toPayment(row, benefits[row['id']] ?? const []);
    final uc = cards[row['user_card_id']]!;
    final found = engine.ctx.rulesOn(
      uc['card_id'] as String,
      localDay(p.paidAt),
    );
    // 결제일에 맞는 개정이 없으면 엔진이 계산하지 않아 실적에도 넣지 않는다. 위험 검토 17번
    var counted = false;
    var rewards = <String>[];
    if (found != null) {
      final card = engineCard(uc);
      List<AppliedBenefit>? before;
      if (p.cancelledAmount > 0) {
        // 취소한 결제는 엔진처럼 취소하지 않았다면 받았을 혜택으로 처음 실적을 센다. 설계 문서 6.5
        if (!history.containsKey(p.userCardId)) {
          history.addAll(loadPayments(s, [p.userCardId]));
        }
        final prior = [
          for (final q in history[p.userCardId]!)
            if (byTime(q, p) < 0) q,
        ];
        before = beforeCancel(
          engine.ctx,
          card,
          p,
          buildLedger(engine.ctx, card, prior),
        );
      }
      final (parts, _) = spendParts(
        engine.ctx,
        card,
        p,
        found.rules,
        p.benefits ?? const [],
        before,
      );
      // 어느 달 실적에도 넣지 않으면 실적 제외다. 취소로 0원이 된 결제는 취소로 보인다
      counted =
          parts.any((part) => part.amount > 0) || p.cancelledAmount == p.amount;
      final types = {
        for (final b in found.rules.benefits) b.key: b.reward.type,
      };
      rewards = {
        for (final b in p.benefits ?? const <AppliedBenefit>[])
          if (types.containsKey(b.key) && b.value > 0) types[b.key]!,
      }.toList()..sort();
    }
    out.add({
      'id': p.id,
      'paid_at': p.paidAt.toIso8601String(),
      'merchant_name': row['merchant_name'],
      'category': p.category,
      'category_name': p.category == null ? null : names[p.category],
      'user_card_id': p.userCardId,
      'card_name': uc['name'],
      'amount': p.amount,
      'cancelled_amount': p.cancelledAmount,
      'cancelled_at': p.cancelledAt?.toIso8601String(),
      // 엑셀에 날짜만 있던 결제는 시각을 모른다. 고치면 시각을 안다. E57
      'time_known': p.timeKnown,
      'value': (p.benefits ?? const []).fold(0, (n, b) => n + b.value),
      'rewards': rewards,
      'counted': counted,
      // 고치기 화면을 채운다
      'channel': p.channel,
      'region': p.region,
      'installment_months': p.installmentMonths,
      'interest_free': p.interestFree,
      'payment_method': p.paymentMethod,
      'billing': row['billing'],
    });
  }
  return {
    'month': dayText(m),
    'count': out.length,
    'amount': out.fold<int>(
      0,
      (n, x) => n + (x['amount'] as int) - (x['cancelled_amount'] as int),
    ),
    'benefit_total': out.fold<int>(0, (n, x) => n + (x['value'] as int)),
    'cards': [
      for (final MapEntry(key: i, value: r) in cards.entries)
        if (r['removed_at'] == null) {'id': i, 'name': r['name']},
    ],
    'payments': out,
  };
}

/// 결제 고치기. 그 결제만 다시 계산한다. E50. 구간이 바뀐 달이 있으면 처음 바뀐 달부터 마지막 결제가 든 달까지 다시 계산한다. E54
Json edit(Store s, String tid, Json raw) {
  final body = PaymentBody(raw, saving: true);
  final f = filled(s, body);
  final newCard = body.userCardId!;
  return write(s, () {
    final old = mine(s, tid);
    final oldCard = old['user_card_id'] as String;
    final rows = lockCards(s, {oldCard, newCard});
    if ((old['cancelled_amount'] as int) > body.amount!) {
      throw ApiError(422, '취소한 금액보다 작게 고칠 수 없다');
    }
    final oldCancelled = old['cancelled_at'] == null
        ? null
        : fromMs(old['cancelled_at'] as int);
    if (oldCancelled != null && f.paidAt.isAfter(oldCancelled)) {
      throw ApiError(422, '결제 시각이 취소 시각보다 뒤다');
    }
    // 새로 고른 카드는 해지하지 않은 카드여야 한다. 해지한 카드의 결제는 그 카드 그대로만 고친다
    if (!rows.containsKey(newCard) ||
        (newCard != oldCard && rows[newCard]!['removed_at'] != null)) {
      throw ApiError(404, '보유 카드가 아니다');
    }
    final now = s.clock(), engine = s.engine;
    final loaded = loadPayments(s, ({oldCard, newCard}.toList()..sort()));
    final oldPaid = fromMs(old['paid_at'] as int);
    final p = paymentOf(rows[newCard]!, body, body.amount!, f, tid).copyWith(
      cancelledAmount: old['cancelled_amount'] as int,
      cancelledAt: oldCancelled,
      // 시각을 모르던 결제는 시각을 바꿔야 안다. 다른 칸만 고치면 12시가 진짜 시각이 되지 않는다. E57
      timeKnown: old['time_known'] == 1 || f.paidAt != oldPaid,
    );
    final a = monthOf(localDay(oldPaid)), b = monthOf(localDay(p.paidAt));
    final start = a.isBefore(b) ? a : b;
    final results = <String, Map<String, PaymentResult>>{};
    if (newCard == oldCard) {
      results[newCard] = changedWith(
        engine,
        engineCard(rows[newCard]!),
        loaded[newCard]!,
        p,
        null,
        start,
        now,
      );
    } else {
      results[oldCard] = changedWith(
        engine,
        engineCard(rows[oldCard]!),
        loaded[oldCard]!,
        null,
        tid,
        start,
        now,
      );
      results[newCard] = changedWith(
        engine,
        engineCard(rows[newCard]!),
        loaded[newCard]!,
        p,
        null,
        start,
        now,
      );
    }
    final (revFrom, revSha) = revisionFor(
      s,
      rows[newCard]!['card_id'] as String,
      p.paidAt,
    );
    try {
      s.db.execute(
        'update transactions set user_card_id = ?, amount = ?, merchant_name = ?, merchant_key = ?, '
        'category_code = ?, paid_at = ?, time_known = ?, installment_months = ?, interest_free_installment = ?, '
        'channel = ?, region = ?, payment_method = ?, billing = ?, revision_from = ?, revision_sha = ?, '
        'updated_at = ? where id = ?',
        [
          newCard,
          p.amount,
          body.merchantName,
          p.merchant,
          p.category,
          ms(p.paidAt),
          p.timeKnown ? 1 : 0,
          p.installmentMonths,
          p.interestFree ? 1 : 0,
          p.channel,
          p.region,
          p.paymentMethod,
          p.billing,
          revFrom,
          revSha,
          ms(now),
          tid,
        ],
      );
    } on SqliteException catch (e) {
      // 옮길 카드에 같은 승인번호의 결제가 이미 있다. E31
      if (e.extendedResultCode == 2067) {
        throw ApiError(409, '옮길 카드에 같은 승인번호의 결제가 있다');
      }
      rethrow;
    }
    var repriced = 0;
    for (final MapEntry(key: cid, value: res) in results.entries) {
      final before = {for (final q in loaded[cid]!) q.id: q};
      repriced += store(
        s,
        rows[cid]!['card_id'] as String,
        res,
        before,
        cid == newCard ? {tid} : {},
        now,
      );
    }
    final result = results[newCard]![tid]!;
    return {
      'id': tid,
      'value': result.value,
      'repriced': repriced,
      'ask_category': askCategory(s, result),
    };
  });
}

/// 취소 기록. 남은 금액으로 그 결제를 다시 계산하고 전액 취소면 혜택은 0이다. 구간이 처음 바뀐 달부터 다시 계산한다. E5, E54
///
/// cancelled_amount는 지금까지 취소한 금액의 합이다. 부분 취소가 여러 번이면 합을 보낸다. 0이면 취소 기록을 되돌린다
Json cancel(Store s, String tid, Json raw) {
  final amount = raw['cancelled_amount'];
  final atText = raw['cancelled_at'];
  if (amount is! int || amount < 0) {
    throw ApiError(422, '취소 금액은 0 이상의 정수다');
  }
  final cancelledAt = awareTime(atText);
  if (cancelledAt == null) {
    throw ApiError(422, '취소 시각은 시간대가 붙은 있는 날의 시각이어야 한다');
  }
  final now = s.clock();
  return write(s, () {
    final old = mine(s, tid);
    final cardId = old['user_card_id'] as String;
    final rows = lockCards(s, {cardId});
    final at = amount > 0 ? cancelledAt : null;
    final paid = fromMs(old['paid_at'] as int);
    if (amount > (old['amount'] as int)) {
      throw ApiError(422, '결제 금액보다 많이 취소할 수 없다');
    }
    if (amount == 0 && old['cancelled_amount'] == 0) {
      throw ApiError(422, '되돌릴 취소 기록이 없다');
    }
    if (at != null &&
        (at.isBefore(paid) || at.isAfter(now.add(const Duration(days: 1))))) {
      throw ApiError(422, '취소 시각이 결제 시각보다 앞서거나 지금보다 하루 넘게 뒤다');
    }
    // 취소 시각은 하나라 다른 달에 더 취소한 금액은 담지 못한다. 취소한 달 기준 카드에서 앞 달 취소분까지 뒤 달 실적에서
    // 빼게 된다. 미지원으로 막는다. 금액을 그대로 두고 시각만 고치는 것은 받는다. 위험 검토 5번
    // ponytail: 결제한 달 기준 카드는 취소 시각이 실적에 쓰이지 않아 담을 수 있지만 함께 막는다. 카드마다 풀면 그때 연다
    final first = old['cancelled_at'] == null
        ? null
        : fromMs(old['cancelled_at'] as int);
    final moved =
        first != null &&
        at != null &&
        monthOf(localDay(first)) != monthOf(localDay(at));
    if (moved && amount != old['cancelled_amount']) {
      throw ApiError(422, '다른 달에 더 취소한 금액은 아직 담지 못한다');
    }
    final loaded = loadPayments(s, [cardId])[cardId]!;
    final before = {for (final q in loaded) q.id: q};
    final p = before[tid]!.copyWith(cancelledAmount: amount, cancelledAt: at);
    final engine = s.engine;
    // 순위 영역 이용액에서 취소를 빼는 달은 카드 칸 ranked[].cancellation이다. 칸이 빈 카드는 확인 필요라 취소로
    // 지나간 달 순위를 다시 매기지 않는다. E55
    final found = engine.ctx.rulesOn(
      rows[cardId]!['card_id'] as String,
      localDay(paid),
    );
    final known =
        found != null &&
        found.rules.ranked.every((r) => r.cancellation != null);
    final res = changedWith(
      engine,
      engineCard(rows[cardId]!),
      loaded,
      p,
      null,
      monthOf(localDay(p.paidAt)),
      now,
      rerank: known,
    );
    // 지금 카탈로그로 다시 계산했으니 개정도 지금 결제일의 개정으로 맞춘다. 위험 검토 12번
    final (revFrom, revSha) = revisionFor(
      s,
      rows[cardId]!['card_id'] as String,
      paid,
    );
    s.db.execute(
      'update transactions set cancelled_amount = ?, cancelled_at = ?, revision_from = ?, revision_sha = ?, '
      'updated_at = ? where id = ?',
      [amount, at == null ? null : ms(at), revFrom, revSha, ms(now), tid],
    );
    final repriced = store(s, rows[cardId]!['card_id'] as String, res, before, {
      tid,
    }, now);
    return {'id': tid, 'value': res[tid]!.value, 'repriced': repriced};
  });
}

/// 결제 지우기. 행은 남기고 지운 시각만 찍는다. S8. 구간이 처음 바뀐 달부터 마지막 결제가 든 달까지 다시 계산한다. E54
Json delete(Store s, String tid) {
  final now = s.clock();
  return write(s, () {
    final old = mine(s, tid);
    final cardId = old['user_card_id'] as String;
    final rows = lockCards(s, {cardId});
    final loaded = loadPayments(s, [cardId])[cardId]!;
    final before = {for (final q in loaded) q.id: q};
    final res = changedWith(
      s.engine,
      engineCard(rows[cardId]!),
      loaded,
      null,
      tid,
      monthOf(localDay(fromMs(old['paid_at'] as int))),
      now,
    );
    s.db.execute(
      'update transactions set deleted_at = ?, updated_at = ? where id = ?',
      [ms(now), ms(now), tid],
    );
    return {
      'id': tid,
      'repriced': store(
        s,
        rows[cardId]!['card_id'] as String,
        res,
        before,
        {},
        now,
      ),
    };
  });
}
