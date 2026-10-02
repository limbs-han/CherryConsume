/// 참, 거짓, 모름 판정. Python `backend/cherry_core/engine/cond.py`를 옮겼다. 엔진 설계 2.1, 3.1, 3.2
///
/// 판정 결과는 (값, 모르는 것들)이다. 값이 null이면 모름이고, 모르는 것들은 `payment_method`, `fact\0key`,
/// `option\0key`, `category\0부모 코드`, `started_on` 같은 글자의 집합이다. Python의 튜플을 `\0`으로 이었다.
/// `\0`은 어떤 글자보다 앞이라 글자 순서가 튜플 순서와 같다
library;

import '../catalog/models.dart';
import 'models.dart';

/// 같은 값의 순서를 지키는 정렬. Python의 sorted()와 같다. Dart의 sort()는 그것을 약속하지 않는다
List<T> sortedStable<T>(Iterable<T> items, int Function(T, T) compare) {
  final indexed = [...items.indexed];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (_, x) in indexed) x];
}

typedef Tri = (bool?, Set<String>);

const Tri yes = (true, <String>{});
const Tri no = (false, <String>{});

/// 모르는 것 하나. 부분을 `\0`으로 잇는다
String need(List<String> parts) => parts.join('\u0000');

List<String> needParts(String n) => n.split('\u0000');

Tri unknown(List<String> parts) => (null, {need(parts)});

Tri allOf(Iterable<Tri> results) {
  final needs = <String>{};
  bool? value = true;
  for (final (v, n) in results) {
    if (v == false) return no;
    if (v == null) {
      value = null;
      needs.addAll(n);
    }
  }
  return value == null ? (null, needs) : yes;
}

Tri anyOf(Iterable<Tri> results) {
  final needs = <String>{};
  bool? value = false;
  for (final (v, n) in results) {
    if (v == true) return yes;
    if (v == null) {
      value = null;
      needs.addAll(n);
    }
  }
  return value == null ? (null, needs) : no;
}

/// 한국 시간의 벽시계로 본 시각. 한국은 1988년 뒤로 서머타임이 없어 UTC에 9시간을 더한다. 폰의 시간대와 상관없다
DateTime kst(DateTime at) => at.toUtc().add(const Duration(hours: 9));

/// 한국 시간으로 그 시각이 든 날
DateTime localDay(DateTime at) {
  final k = kst(at);
  return day(k.year, k.month, k.day);
}

DateTime monthOf(DateTime d) => day(d.year, d.month, 1);

DateTime addMonths(DateTime m, int n) {
  final total = m.month - 1 + n;
  final y = total >= 0 ? total ~/ 12 : -((-total + 11) ~/ 12);
  return day(m.year + y, total - y * 12 + 1, 1);
}

/// 한국 공휴일인가. 카탈로그 JSON의 2020~2036년 목록으로 본다. 대체공휴일과 선거일이 들어 있다. 목록에 없는 해면
/// null이다. 모르는 날을 공휴일이 아니라고 짐작하지 않는다. 작업 006 설계 2절
// ponytail: 공휴일이 아닌 날마다 목록 300여 개를 훑는다. 느려지면 카탈로그에 해 집합을 둔다
bool? isHoliday(DateTime d, Set<DateTime> holidays) => holidays.contains(d)
    ? true
    : holidays.any((h) => h.year == d.year)
    ? false
    : null;

/// 결제 업종이 조건 업종에 맞는지. 결제가 부모 업종까지만 알면 모름이다. 엔진 설계 2.1
Tri categoryMatch(String? paid, String wanted) {
  if (paid == null) return no;
  if (paid == wanted || paid.startsWith('$wanted.')) return yes;
  if (wanted.startsWith('$paid.')) return unknown(['category', paid]);
  return no;
}

Tri categoriesMatch(String? paid, List<String> wanted) =>
    anyOf(wanted.map((w) => categoryMatch(paid, w)));

/// 조건을 판정하는 데 필요한 결제 쪽 값. amount는 혜택마다 다를 수 있어 바꿔 가며 쓴다
class Situation {
  Situation({
    required this.at,
    required this.amount,
    required this.merchant,
    required this.category,
    required this.channel,
    required this.region,
    required this.installmentMonths,
    required this.interestFree,
    required this.paymentMethod,
    required this.billing,
    required this.card,
    this.holidays = const {},
    Map<String, String?>? defaults,
    Map<String, Set<String>>? topAreas,
    this.area,
    this.monthTotal,
    this.skip = const {},
    this.timeKnown = true,
  }) : defaults = defaults ?? {},
       topAreas = topAreas ?? {};

  /// UTC. 한국 시간은 [day]와 [kst]로 본다
  DateTime at;
  int amount;
  String? merchant, category;
  String channel, region;
  int installmentMonths;
  bool interestFree;
  String? paymentMethod;
  String billing;
  UserCard card;

  /// 공휴일 판정에 쓰는 카탈로그의 목록. Python은 holidays 패키지를 바로 불렀다
  Set<DateTime> holidays;
  Map<String, String?> defaults;
  Map<String, Set<String>> topAreas;
  String? area;
  int? monthTotal;
  Set<String> skip;
  bool timeKnown;

  DateTime get day => localDay(at);

  /// 결제일에 골라 둔 선택지. 고른 적이 없으면 카드사 기본값. 엔진 설계 3.8
  String? choice(String option) {
    OptionPick? best;
    for (final p in card.options) {
      if (p.option == option &&
          !p.effectiveFrom.isAfter(day) &&
          (best == null || p.effectiveFrom.isAfter(best.effectiveFrom))) {
        best = p;
      }
    }
    return best != null ? best.choice : defaults[option];
  }
}

const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

String _hhmm(DateTime at) {
  final k = kst(at);
  return '${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}';
}

/// 조건 항목 하나. 적힌 칸이 모두 맞아야 참이다
Tri check(Condition c, Situation s) {
  final parts = <Tri>[];
  void add(Tri t) => parts.add(t);
  Tri of(bool ok) => ok ? yes : no;
  if (c.amount != null) {
    final a = c.amount!;
    add(
      of(
        (a.min == null || s.amount >= a.min!) &&
            (a.below == null || s.amount < a.below!),
      ),
    );
  }
  if (c.day != null) {
    final weekday = _weekdays[s.day.weekday - 1];
    final inDays = (c.day!.days ?? const []).contains(weekday);
    final mode = c.day!.holidays;
    final settled = switch (mode) {
      'ignore' => inDays,
      'include' when inDays => true,
      'exclude' when !inDays => false,
      'include' || 'exclude' || 'only' => null,
      final h => throw StateError('모르는 holidays $h'),
    };
    final holiday = settled == null ? isHoliday(s.day, s.holidays) : null;
    add(
      settled != null
          ? of(settled)
          : holiday == null
          ? unknown(['holiday'])
          : of(mode == 'exclude' ? !holiday : holiday),
    );
  }
  if (c.time != null && !s.timeKnown) {
    add(unknown(['time']));
  } else if (c.time != null) {
    final t = _hhmm(s.at);
    final start = c.time!.start, end = c.time!.end;
    final ok = start.compareTo(end) <= 0
        ? start.compareTo(t) <= 0 && t.compareTo(end) < 0
        : (t.compareTo(start) >= 0 || t.compareTo(end) < 0);
    add(of(ok));
  }
  if (c.months != null) add(of(c.months!.contains(s.day.month)));
  if (c.region != null) add(of(s.region == c.region));
  if (c.channel != null) add(of(s.channel == c.channel));
  if (c.interestFree != null) add(of(s.interestFree == c.interestFree));
  if (c.lumpSum != null) add(of(s.installmentMonths <= 1));
  if (c.payment != null) {
    add(
      s.paymentMethod == null
          ? unknown(['payment_method'])
          : of(c.payment!.contains(s.paymentMethod)),
    );
  }
  if (c.paymentNot != null) {
    final pm = s.paymentMethod;
    add(
      pm == null
          ? unknown(['payment_method'])
          : of(!c.paymentNot!.contains(pm)),
    );
  }
  if (c.billing != null) add(of(c.billing!.contains(s.billing)));
  if (c.billingNot != null) add(of(!c.billingNot!.contains(s.billing)));
  for (final MapEntry(key: option, value: choices)
      in (c.option ?? const <String, List<String>>{}).entries) {
    final chosen = s.choice(option);
    add(
      chosen == null
          ? unknown(['option', option])
          : of(choices.contains(chosen)),
    );
  }
  if (c.fact != null) add(fact(c.fact!, s));
  if (c.ranked != null && !s.skip.contains('ranked')) {
    add(of((s.topAreas[c.ranked] ?? const {}).contains(s.area)));
  }
  if (c.cardMonth != null) {
    final start = s.card.startedOn;
    if (start == null) {
      add(unknown(['started_on']));
    } else {
      final n = (s.day.year - start.year) * 12 + s.day.month - start.month;
      final m = c.cardMonth!;
      add(of((m.min == null || n >= m.min!) && (m.max == null || n <= m.max!)));
    }
  }
  if (c.monthTotal != null && !s.skip.contains('month_total')) {
    add(of((s.monthTotal ?? 0) >= c.monthTotal!.min));
  }
  if (c.anyOf != null) add(anyOf(c.anyOf!.map((sub) => check(sub, s))));
  return allOf(parts);
}

Tri fact(String key, Situation s) {
  final facts = Map<String, Object>.of(s.card.facts);
  // 결제일에 맞는 가장 늦은 답이 facts를 덮는다. 작업 005 설계 5e
  final picks = sortedStable(
    s.card.factPicks.where((p) => !p.effectiveFrom.isAfter(s.day)),
    (a, b) => a.effectiveFrom.compareTo(b.effectiveFrom),
  );
  for (final p in picks) {
    facts[p.key] = p.value;
  }
  if (key == 'birth_month_now') {
    if (!facts.containsKey('birth_month')) {
      return unknown(['fact', 'birth_month']);
    }
    return facts['birth_month'] == s.day.month ? yes : no;
  }
  if (!facts.containsKey(key)) return unknown(['fact', key]);
  return facts[key] == true ? yes : no;
}

Tri checkAll(List<Condition> conditions, Situation s) =>
    allOf(conditions.map((c) => check(c, s)));
