/// 보유 카드와 홈. 서버 `cherry_api/routes/me.py`를 옮겼다. 작업 005 설계 5절
///
/// 계정과 탈퇴는 로그인이 없어 옮기지 않는다. 작업 006 설계 4절
library;

import 'package:sqlite3/sqlite3.dart';

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/models.dart';
import '../answers.dart';
import '../db.dart';
import '../payments.dart';
import '../store.dart';
import 'catalog.dart';

/// 보유 카드 행을 엔진 카드로. 행에는 attachAnswers로 붙인 답이 있어야 한다. 빠뜨리면 형 변환에서 던져 시험이 잡는다
UserCard engineCard(Map<String, Object?> row) => UserCard(
  id: row['id'] as String,
  cardId: row['card_id'] as String,
  registeredOn: localDay(fromMs(row['added_at'] as int)),
  startedOn: row['started_on'] == null
      ? null
      : parseDay(row['started_on'] as String),
  assumedPrevMonthSpend: row['assumed_prev_month_spend'] as int?,
  lastPaymentMethod: row['last_payment_method'] as String?,
  options: row['options'] as List<OptionPick>,
  factPicks: row['fact_picks'] as List<FactPick>,
);

Json addCard(
  Store s,
  String cardId, {
  int? assumedPrevMonthSpend,
  DateTime? startedOn,
}) {
  final prev = assumedPrevMonthSpend;
  if (prev != null && (prev < 0 || prev > maxSpend)) {
    throw ApiError(422, '지난달 쓴 금액은 0원부터 1억 원까지다');
  }
  registrable(s, cardId);
  final now = s.clock();
  final id = newId(now);
  try {
    write(
      s,
      () => s.db.execute(
        'insert into user_cards (id, card_id, assumed_prev_month_spend, started_on, added_at) '
        'values (?, ?, ?, ?, ?)',
        [
          id,
          cardId,
          prev,
          startedOn == null ? null : dayText(startedOn),
          ms(now),
        ],
      ),
    );
  } on SqliteException catch (e) {
    if (e.extendedResultCode == 2067) throw ApiError(409, '이미 등록한 카드다. E21');
    rethrow;
  }
  return {'id': id};
}

/// 보유 카드 행. 카드 이름과 카드사 이름은 카탈로그에서 붙인다. 서버는 cards, issuers 표와 이었다
Map<String, Object?> named(Store s, Row r) {
  final row = rowMap(r);
  final card = s.catalog.cards[row['card_id']]!;
  row['name'] = card.name;
  row['issuer'] = card.issuer;
  row['issuer_name'] = s.catalog.issuers[card.issuer]!.name;
  row['checked_at'] = card.checkedAt;
  return row;
}

Json home(Store s) {
  final month = monthOf(s.today());
  final rows = [
    for (final r in s.db.select(
      'select * from user_cards where removed_at is null order by added_at, id',
    ))
      named(s, r),
  ];
  attachAnswers(s, rows);
  final engine = s.engine;
  final payments = loadPayments(s, [for (final r in rows) r['id'] as String]);
  // 받은 혜택은 한국 시간으로 이번 달에 결제한 건의 저장된 혜택 원 가치 합이다. E13
  // 해지한 카드의 결제도 넣는다. 그달 실제로 받은 혜택이다. 작업 005 설계 5d절
  final (start, end) = monthRange(month);
  final total =
      s.db.select(
            'select coalesce(sum(b.value), 0) as v from transactions t '
            'join transaction_benefits b on b.transaction_id = t.id '
            'where t.deleted_at is null and t.paid_at >= ? and t.paid_at < ?',
            [ms(start), ms(end)],
          ).first['v']
          as int;
  final cards = <Json>[];
  for (final r in rows) {
    final card = engineCard(r);
    final status = engine.spendStatus(card, payments[r['id']]!, month);
    final found = engine.ctx.rulesOn(r['card_id'] as String, month);
    final got = found != null && status.tier != null
        ? benefitsAt(found.rules, card, month, status, s.today())
        : <Benefit>[];
    cards.add({
      'id': r['id'],
      'card_id': r['card_id'],
      'name': r['name'],
      'issuer': r['issuer'],
      'issuer_name': r['issuer_name'],
      // 비면 실적 무관 카드다
      'tiers': tiersShown(found),
      // 실적 무관 카드는 홈에 남은 금액 대신 이 혜택 제목을 보인다
      'headline': got.isEmpty ? null : got.first.title,
      'spend': status.toJson(),
    });
  }
  return {'month': dayText(month), 'benefit_total': total, 'cards': cards};
}

/// 한국 시간 그 달의 처음과 다음 달 처음. E7
(DateTime, DateTime) monthRange(DateTime month) {
  final nxt = addMonths(month, 1);
  const kstOffset = Duration(hours: 9);
  return (month.subtract(kstOffset), nxt.subtract(kstOffset));
}

String sharedTitle(Rules rules, String key) {
  if (key == 'integrated') return '통합 한도';
  final users = [
    for (final b in rules.benefits)
      for (final lim in b.limits)
        if (lim.shared == key) b.title,
  ];
  return users.isNotEmpty ? '함께 쓰는 한도 · ${users.join(', ')}' : '함께 쓰는 한도';
}

Map<String, Object?> _held(Store s, String uid) {
  final found = s.db.select(
    'select * from user_cards where id = ? and removed_at is null',
    [uid],
  );
  if (found.isEmpty) throw ApiError(404, '보유 카드가 아니다');
  return named(s, found.first);
}

/// 카드 상세. 시안 보드 6. 실적과 구간, 혜택별 남은 한도, 구간이 모자라 못 받는 혜택, 확인 필요 안내. S7, E37
Json cardDetail(Store s, String uid) {
  final row = _held(s, uid);
  attachAnswers(s, [row]);
  final engine = s.engine, now = s.clock();
  final day = s.today();
  final month = monthOf(day);
  final card = engineCard(row);
  final payments = loadPayments(s, [uid])[uid]!;
  final status = engine.spendStatus(card, payments, month);
  // 엔진 limitStatus처럼 오늘의 개정을 본다
  final found = engine.ctx.rulesOn(row['card_id'] as String, day);
  final limits = <Json>[], locked = <Json>[];
  var available = <String>{};
  final sentences = <Object?>[
    for (final w in status.warnings)
      if (w.code == 'check_conditions') ...?(w.data['sentences'] as List?),
  ];
  if (found != null) {
    final rules = found.rules;
    final titles = {for (final b in rules.benefits) b.key: b.title};
    final got = benefitsAt(rules, card, month, status, day);
    available = {for (final b in got) b.key};
    // 받는 혜택에 달린 문장 조건도 보인다. 실적 현황의 경고에는 카드 전체 문장만 있다
    sentences.addAll([for (final b in got) ...b.unmodeled]);
    // 함께 쓰는 한도는 그 한도를 쓰는 혜택 가운데 하나라도 받으면 보인다
    final sharing = {
      for (final b in got)
        for (final lim in b.limits)
          if (lim.shared != null) lim.shared,
    };
    // 1회와 하루 한도는 남은 양이 아니라 조건이라 보이지 않는다. 지금 구간과 옵션에서 못 받는 혜택의 한도도 뺀다
    for (final use in engine.limitStatus(card, payments, now)) {
      if (use.per == 'txn' ||
          use.per == 'day' ||
          (use.capAmount == null &&
              use.capCount == null &&
              use.capBase == null)) {
        continue;
      }
      final shown = use.benefit != null
          ? available.contains(use.benefit)
          : sharing.contains(use.key);
      if (!shown) continue;
      limits.add({
        'title': use.benefit != null
            ? (titles[use.benefit] ?? use.benefit)
            : sharedTitle(rules, use.key),
        'per': use.per,
        'used_amount': use.usedAmount,
        'cap_amount': use.capAmount,
        'used_count': use.usedCount,
        'cap_count': use.capCount,
        // 할인받는 결제액의 한도. 신한 Mr.Life 주말 주유처럼 이것만 있는 한도가 있다. 위험 검토 15번
        'used_base': use.usedBase,
        'cap_base': use.capBase,
      });
    }
    final base = prevMonthTier(rules, status);
    final picked = optionPicked(rules, card, day);
    for (final b in rules.benefits) {
      final lo = b.tiers?.start ?? rules.tiers.first;
      // 구간이 모자라 못 받는 혜택. 필요 금액은 그 구간 하한 빼기 이번 달 인정 실적, 받는 때는 다음 달이다. E37
      // 고르지 않은 옵션의 혜택과 다음 달 전에 끝나는 행사는 구간이 올라도 받지 못해 넣지 않는다. 위험 검토 10번
      if (lo > base &&
          !available.contains(b.key) &&
          picked(b) &&
          inPeriod(b, addMonths(month, 1))) {
        locked.add({
          'title': b.title,
          'required_tier': lo,
          'remaining': lo - status.counted > 0 ? lo - status.counted : 0,
        });
      }
    }
  }
  // 카드 전체 항목과 이번 달 받는 혜택의 항목을 센다. 안내가 "추정으로 계산해요"라 계산에 쓰는 것만 센다. 위험 검토 14번
  final paths = engine.ctx.assumed[row['card_id']] ?? const {};
  final assumed = <String?>{
    null,
    ...available,
  }.fold<int>(0, (n, k) => n + (paths[k]?.length ?? 0));
  return {
    'id': uid,
    'card_id': row['card_id'],
    'name': row['name'],
    'issuer_name': row['issuer_name'],
    'questions': questions(found?.rules, row, day),
    'tiers': tiersShown(found),
    'spend': status.toJson(),
    'limits': limits,
    'locked': locked,
    // 조건을 문장으로만 담은 혜택과 공식 문구로 확인하지 못한 값
    'check_sentences': sentences,
    'assumed_count': assumed,
    'started_on': row['started_on'],
    'registered_on': dayText(localDay(fromMs(row['added_at'] as int))),
    'revision_from': found == null ? null : dayText(found.effectiveFrom),
    'checked_at': dayText(row['checked_at'] as DateTime),
  };
}

/// 카드 정보에서 묻는 카드 사실과 옵션, 지금 답. 다음 달부터 바뀌는 옵션은 pending이다. 작업 005 설계 5e
Json questions(Rules? rules, Map<String, Object?> row, DateTime day) {
  if (rules == null) return {'facts': <Json>[], 'options': <Json>[]};
  final factPicks = row['fact_picks'] as List<FactPick>;
  final optionPicks = row['options'] as List<OptionPick>;
  final facts = [
    for (final f in rules.facts)
      if (f.scope == 'card')
        {
          'key': f.key,
          'type': f.type,
          'ask': f.ask,
          'choices': f.choices,
          'answer': atDay([
            for (final p in factPicks)
              if (p.key == f.key) (p.effectiveFrom, p.value),
          ], day),
        },
  ];
  final options = <Json>[];
  for (final o in rules.options) {
    final picks = [
      for (final p in optionPicks)
        if (p.option == o.key) (p.effectiveFrom, p.choice),
    ];
    final later = [
      for (final x in picks)
        if (x.$1.isAfter(day)) x,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    options.add({
      'key': o.key,
      'title': o.title,
      'choices': [
        for (final c in o.choices) {'key': c.key, 'title': c.title},
      ],
      'default': o.defaultChoice,
      'unsupported': o.unsupported,
      'change': o.change,
      'answer': atDay(picks, day),
      'pending': later.isEmpty
          ? null
          : {'value': later.first.$2, 'from': dayText(later.first.$1)},
    });
  }
  return {'facts': facts, 'options': options};
}

/// 카드 해지. 결제와 기록은 남기고 홈과 추천에서만 뺀다. S9
Json removeCard(Store s, String uid) {
  final changed = write(s, () {
    s.db.execute(
      'update user_cards set removed_at = ? where id = ? and removed_at is null',
      [ms(s.clock()), uid],
    );
    return s.db.updatedRows;
  });
  if (changed == 0) throw ApiError(404, '보유 카드가 아니다');
  return {'id': uid};
}
