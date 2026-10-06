/// 보유 카드와 홈. 서버 `cherry_api/routes/me.py`를 옮겼다. 작업 005 설계 5절
///
/// 계정과 탈퇴는 로그인이 없어 옮기지 않는다. 작업 006 설계 4절
library;

import 'package:sqlite3/sqlite3.dart';

import '../../api.dart' show ApiError, billings;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/context.dart' show atTier;
import '../../engine/models.dart';
import '../../engine/spend.dart' show newCardTier;
import '../../format.dart';
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
  // 홈, 결제, 기록, 추천, 설정의 칩과 줄은 짧은 이름을 쓴다. 카드 상세 제목은 전체 이름이다. 작업 011 설계 2.4
  row['name'] = card.shortName ?? card.name;
  row['full_name'] = card.name;
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

/// 함께 쓰는 한도의 이름. 그 한도를 쓰는 혜택은 카드 상세에서 이 한도 상자 안에 묶여 보여 이름에 적지 않는다. 작업 011 설계 2절 D5
String sharedTitle(String key) => key == 'integrated' ? '통합 한도' : '함께 쓰는 한도';

/// 조건 한 줄의 금액. 만 원 단위면 "5만 원", 아니면 "5,000원"이다. 홈의 "11.8만"처럼 올리지 않는다
String _money(int n) =>
    n >= 10000 && n % 10000 == 0 ? '${comma(n ~/ 10000)}만 원' : won(n);

const _periodWords = {'txn': '건당', 'day': '하루'};
const _dayWords = {
  'mon': '월',
  'tue': '화',
  'wed': '수',
  'thu': '목',
  'fri': '금',
  'sat': '토',
  'sun': '일',
};

String _days(Days d) {
  final set = {...?d.days};
  final days = switch (set) {
    _ when set.isEmpty => '',
    _ when set.length == 5 && !set.contains('sat') && !set.contains('sun') =>
      '평일',
    _ when set.length == 2 && set.containsAll(['sat', 'sun']) => '주말',
    _ => [
      for (final k in _dayWords.keys)
        if (set.contains(k)) _dayWords[k],
    ].join('·'),
  };
  return switch (d.holidays) {
    'include' => '$days·공휴일',
    'exclude' => '$days, 공휴일 제외',
    'only' => days.isEmpty ? '공휴일' : '$days 중 공휴일',
    _ => days,
  };
}

/// 결제가 맞아야 하는 조건. 옵션, 답한 사실, 순위 영역, 카드를 쓴 달은 받는 혜택이면 이미 맞아 쓰지 않는다. 갈래 가운데
/// 하나라도 그런 것뿐이면 그 묶음은 쓰지 않는다
List<String> _conditionWords(Condition c, Map<String, String> methods) {
  final bills = {for (final (k, n) in billings) k: n};
  String names(List<String> keys, Map<String, String> m) =>
      keys.map((k) => m[k] ?? k).join('·');
  final a = c.amount;
  final any = c.anyOf == null
      ? null
      : [for (final alt in c.anyOf!) _conditionWords(alt, methods).join(' · ')];
  final not = c.paymentNot;
  return [
    if (a != null)
      [
        if (a.min != null) '${_money(a.min!)} 이상',
        if (a.below != null) '${_money(a.below!)} 미만',
      ].join(' '),
    if (c.day != null) _days(c.day!),
    if (c.time != null) '${c.time!.start}~${c.time!.end}',
    if (c.months != null) '${c.months!.join('·')}월',
    if (c.region != null) c.region == 'overseas' ? '해외' : '국내',
    if (c.channel != null) c.channel == 'online' ? '온라인' : '오프라인',
    if (c.interestFree == true) '무이자 할부',
    if (c.interestFree == false) '무이자 할부 제외',
    if (c.lumpSum == true) '일시불',
    if (c.payment != null) '${names(c.payment!, methods)} 결제',
    if (not != null)
      not.length <= 2
          ? '${names(not, methods)} 제외'
          : '${methods[not.first] ?? not.first} 등 결제수단 ${not.length}개 제외',
    if (c.billing != null) names(c.billing!, bills),
    if (c.billingNot != null) '${names(c.billingNot!, bills)} 제외',
    if (c.monthTotal != null) '그달 대상 이용 ${_money(c.monthTotal!.min)} 이상',
    if (any != null && !any.contains('')) any.join(' 또는 '),
  ].where((w) => w.isNotEmpty).toList();
}

/// 카드 상세에서 혜택을 묶는 업종 이름과 순서. 대상 업종과 대상 가맹점의 업종을 큰 분류로 올린다. 다른 업종이 함께
/// 있으면 기타를 빼고, 여럿이면 카탈로그 업종 순서로 이어 붙인다. 전가맹점은 모든 가맹점이고 맨 앞이다. 순서는 묶음의
/// 첫 업종이 카탈로그에서 몇 번째인지다. 계산에는 쓰지 않는다. 작업 011 설계 2.5
({String name, int order}) benefitGroup(Benefit b, Catalog cat) {
  if (b.target.all) return (name: '모든 가맹점', order: -1);
  String top(String code) => code.split('.').first;
  final codes = {
    for (final c in b.target.categories) top(c),
    for (final m in b.target.merchants)
      // 군마트는 화면에서 묶을 때만 편의점이다. 카탈로그의 가맹점 업종을 바꾸면 편의점 혜택이 군마트 결제에 붙어
      // 계산이 달라진다. 2026-10-05 사용자가 정했다
      if (m == 'px')
        'convenience'
      else if (cat.merchants[m] case final x?)
        top(x.category),
  };
  if (codes.length > 1) codes.remove('other');
  if (codes.isEmpty) codes.add('other');
  final order = [for (final c in cat.categoryTree) c.code];
  int at(String c) => order.contains(c) ? order.indexOf(c) : order.length;
  final sorted = codes.toList()..sort((a, b) => at(a).compareTo(at(b)));
  final names = {for (final c in cat.categoryTree) c.code: c.name};
  return (
    name: [for (final c in sorted) names[c] ?? c].join(' · '),
    order: at(sorted.first),
  );
}

/// 혜택 하나의 조건 한 줄. 1회와 하루 한도를 먼저, 결제 조건을 뒤에 쓴다. 없으면 null이다. 작업 011 설계 2절 D5
///
/// 한도는 그 혜택의 구간 값이다. 엔진 한도 현황은 1회 한도를 기간이 없다고 빼서 카탈로그에서 읽는다. 생일 달처럼 조건에
/// 따라 바뀌는 한도 조정은 넣지 않는다
String? conditionLine(Benefit b, int tier, Map<String, String> methods) {
  final words = [
    for (final lim in b.limits)
      if (lim.shared == null)
        if (_periodWords[lim.per] case final per?) ...[
          if (atTier(lim.amount, tier) case final int a) '$per 최대 ${_money(a)}',
          if (atTier(lim.base, tier) case final int x)
            '$per 결제액 ${_money(x)}까지',
          if (atTier(lim.count, tier) case final int n) '$per $n회',
        ],
    for (final c in b.when) ..._conditionWords(c, methods),
  ];
  return words.isEmpty ? null : words.join(' · ');
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
  final limits = <Json>[], locked = <Json>[], plain = <Json>[];
  var available = <String>{};
  final sentences = <Object?>[
    for (final w in status.warnings)
      if (w.code == 'check_conditions') ...?(w.data['sentences'] as List?),
  ];
  if (found != null) {
    final rules = found.rules;
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
    // 받는 혜택마다 한 줄이다. 기간 한도가 있으면 남은 양을 보이고, 1회와 하루 한도는 남은 양이 아니라 조건이라 결제
    // 조건과 함께 조건 한 줄에 쓴다. 함께 쓰는 한도를 쓰는 혜택은 화면이 그 한도 상자 안에 묶는다. 작업 011 설계 2절 D5
    final uses = engine.limitStatus(card, payments, now);
    final baseTier = prevMonthTier(rules, status);
    final methods = {
      for (final m in s.catalog.paymentMethods.values) m.key: m.name,
    };
    bool capped(LimitUse u) =>
        u.capAmount != null || u.capCount != null || u.capBase != null;
    Json usage(LimitUse u) => {
      'per': u.per,
      'used_amount': u.usedAmount,
      'cap_amount': u.capAmount,
      'used_count': u.usedCount,
      'cap_count': u.capCount,
      // 할인받는 결제액의 한도. 신한 Mr.Life 주말 주유처럼 이것만 있는 한도가 있다. 위험 검토 15번
      'used_base': u.usedBase,
      'cap_base': u.capBase,
    };
    for (final b in got) {
      final mine = [
        for (final u in uses)
          if (u.benefit == b.key) u,
      ];
      final period = [
        for (final u in mine)
          if (u.per != 'txn' && u.per != 'day' && capped(u)) u,
      ];
      final group = benefitGroup(b, s.catalog);
      final row = {
        'title': b.title,
        'key': b.key,
        // 화면이 업종별로 묶는다. 작업 011 설계 2.5
        'group': group.name,
        'group_order': group.order,
        'shared': [for (final lim in b.limits) ?lim.shared],
        'condition': conditionLine(
          b,
          newCardTier(card, month, rules, b.key, baseTier).$1,
          methods,
        ),
      };
      // 기간 한도가 없는 혜택은 남은 양이 없어 limits와 따로 담는다. limits는 남은 양이 있는 줄만이다
      if (period.isEmpty) plain.add(row);
      for (final (i, u) in period.indexed) {
        limits.add({...row, ...usage(u), if (i > 0) 'condition': null});
      }
    }
    for (final u in uses) {
      if (u.benefit == null && sharing.contains(u.key) && capped(u)) {
        limits.add({
          'title': sharedTitle(u.key),
          'key': u.key,
          ...usage(u),
          'shared': const <String>[],
          'condition': null,
          'is_shared': true,
        });
      }
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
  final paths = engine.ctx.assumedOf(row['card_id'] as String);
  final assumed = <String?>{
    null,
    ...available,
  }.fold<int>(0, (n, k) => n + (paths[k]?.length ?? 0));
  return {
    'id': uid,
    'card_id': row['card_id'],
    // 카드 상세 제목은 전체 이름이다. 작업 011 설계 2.4
    'name': row['full_name'],
    'issuer_name': row['issuer_name'],
    'questions': questions(found?.rules, row, day),
    'tiers': tiersShown(found),
    'spend': status.toJson(),
    'limits': limits,
    'plain': plain,
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
    final n = s.db.updatedRows;
    // 카드번호 일부와 이 카드의 짝은 남길 까닭이 없다. 행을 지우지 않아 외래 키로는 지워지지 않는다. 작업 017 단계 2 검토
    // 낮음 4
    if (n > 0) {
      s.db.execute('delete from import_card_codes where user_card_id = ?', [
        uid,
      ]);
    }
    return n;
  });
  if (changed == 0) throw ApiError(404, '보유 카드가 아니다');
  return {'id': uid};
}
