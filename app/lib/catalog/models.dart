/// 카탈로그 2판 모델. Python `backend/cherry_core/catalog/models.py`를 옮겼다. 엔진과 화면이 쓰는 칸만 읽는다.
/// 앱이 담는 `assets/catalog/`의 목록 파일과 카드별 규칙 파일은 Python이 검사를 통과한 카탈로그에서 만든다. 시험은
/// 한 벌 JSON도 읽는다. 그래서 여기서는 규칙을 다시
/// 검사하지 않는다. 작업 006 설계 2절, 3절
library;

/// 이 앱이 읽는 카탈로그 JSON의 형식 번호. 이보다 큰 파일은 쓰지 않는다
const catalogSchema = 1;

/// 목록 파일과 카드별 규칙 파일의 형식 번호. 작업 014 설계 1절
const splitSchema = 2;

/// 날짜는 UTC 자정의 DateTime으로 둔다. 시간대 없이 날짜끼리 비교하고 요일을 센다
DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

DateTime parseDay(String s) {
  final [y, m, d] = s.split('-').map(int.parse).toList();
  return day(y, m, d);
}

String dayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

typedef Json = Map<String, dynamic>;

List<T> _list<T>(Object? v, T Function(Json) f) => [
  for (final x in (v as List?) ?? const []) f(x as Json),
];

List<String> _strs(Object? v) => [
  for (final x in (v as List?) ?? const []) x as String,
];

DateTime? _day(Object? v) => v == null ? null : parseDay(v as String);

/// 금액, 횟수, 비율 또는 구간표. 구간표는 JSON에서 글자 키라 정수로 바꾼다. 엔진의 atTier가 읽는다
Object? _table(Object? v) => v is Map
    ? {
        for (final e in v.entries)
          (e.key is int ? e.key as int : int.parse(e.key as String)): e.value,
      }
    : v;

// 2.4 조건

class AmountRange {
  AmountRange.fromJson(Json j) : min = j['min'], below = j['below'];
  final int? min, below;
}

class Days {
  Days.fromJson(Json j)
    : days = j['in'] == null ? null : _strs(j['in']),
      holidays = j['holidays'] ?? 'ignore';
  final List<String>? days;
  final String holidays;
}

class TimeRange {
  TimeRange.fromJson(Json j) : start = j['from'], end = j['to'];
  final String start, end;
}

class CardMonth {
  CardMonth.fromJson(Json j) : min = j['min'], max = j['max'];
  final int? min, max;
}

class MonthTotal {
  MonthTotal.fromJson(Json j) : min = j['min'];
  final int min;
}

/// 항목 하나에 적은 조건은 전부 맞아야 한다
class Condition {
  Condition.fromJson(Json j)
    : amount = j['amount'] == null ? null : AmountRange.fromJson(j['amount']),
      day = j['day'] == null ? null : Days.fromJson(j['day']),
      time = j['time'] == null ? null : TimeRange.fromJson(j['time']),
      months = j['months'] == null ? null : List<int>.from(j['months']),
      region = j['region'],
      channel = j['channel'],
      interestFree = j['interest_free'],
      lumpSum = j['lump_sum'],
      payment = j['payment'] == null ? null : _strs(j['payment']),
      paymentNot = j['payment_not'] == null ? null : _strs(j['payment_not']),
      billing = j['billing'] == null ? null : _strs(j['billing']),
      billingNot = j['billing_not'] == null ? null : _strs(j['billing_not']),
      option = j['option'] == null
          ? null
          : {
              for (final e in (j['option'] as Map).entries)
                e.key as String: _strs(e.value),
            },
      fact = j['fact'],
      ranked = j['ranked'],
      cardMonth = j['card_month'] == null
          ? null
          : CardMonth.fromJson(j['card_month']),
      monthTotal = j['month_total'] == null
          ? null
          : MonthTotal.fromJson(j['month_total']),
      anyOf = j['any_of'] == null
          ? null
          : _list(j['any_of'], Condition.fromJson);
  final AmountRange? amount;
  final Days? day;
  final TimeRange? time;
  final List<int>? months;
  final String? region, channel;
  final bool? interestFree, lumpSum;
  final List<String>? payment, paymentNot, billing, billingNot;
  final Map<String, List<String>>? option;
  final String? fact, ranked;
  final CardMonth? cardMonth;
  final MonthTotal? monthTotal;
  final List<Condition>? anyOf;
}

// 2.3 대상, 2.5 보상

class Target {
  Target.fromJson(Json j)
    : all = j['all'] ?? false,
      categories = _strs(j['categories']),
      merchants = _strs(j['merchants']),
      excludeCategories = _strs(j['exclude_categories']),
      excludeMerchants = _strs(j['exclude_merchants']);
  final bool all;
  final List<String> categories, merchants, excludeCategories, excludeMerchants;
}

class PerUnit {
  PerUnit.fromJson(Json j) : unit = j['unit'], amount = j['amount'];
  final int unit, amount;
}

class Reward {
  Reward.fromJson(Json j)
    : type = j['type'],
      program = j['program'],
      rate = _table(j['rate']),
      fixed = _table(j['fixed']),
      perUnit = j['per_unit'] == null ? null : PerUnit.fromJson(j['per_unit']),
      perLiter = j['per_liter'],
      round = j['round'] ?? 'floor',
      basis = j['basis'] ?? 'txn';
  final String type;
  final String? program;

  /// num 또는 {구간: num}
  final Object? rate;

  /// int 또는 {구간: int}
  final Object? fixed;
  final PerUnit? perUnit;
  final int? perLiter;
  final String round, basis;
}

// 2.6 한도

/// 한도 조정. null은 제한 없음이라 칸을 안 쓴 것과 다르다. JSON에는 적어 둔 칸만 있다. 엔진은 [given]으로 가린다
class Adjust {
  Adjust.fromJson(Json j)
    : when = Condition.fromJson(j['when']),
      amount = _table(j['amount']),
      count = _table(j['count']),
      base = _table(j['base']),
      multiply = j['multiply'],
      add = j['add'],
      given = {
        for (final k in const ['amount', 'count', 'base', 'multiply', 'add'])
          if (j.containsKey(k)) k,
      };
  final Condition when;
  final Object? amount, count, base;
  final num? multiply;
  final int? add;
  final Set<String> given;
}

/// 혜택 하나의 한도. 공유 한도를 가리키거나 직접 적는다
class Limit {
  Limit.fromJson(Json j)
    : shared = j['shared'],
      per = j['per'],
      amount = _table(j['amount']),
      count = _table(j['count']),
      base = _table(j['base']),
      adjust = _list(j['adjust'], Adjust.fromJson);
  Limit({required this.per, this.amount})
    : shared = null,
      count = null,
      base = null,
      adjust = const [];
  final String? shared, per;
  final Object? amount, count, base;
  final List<Adjust> adjust;
}

/// 여러 혜택이 같이 쓰는 한도. 엔진은 Limit처럼 읽는다
class SharedLimit implements Limit {
  SharedLimit.fromJson(Json j)
    : key = j['key'],
      per = j['per'],
      amount = _table(j['amount']),
      count = _table(j['count']),
      base = _table(j['base']),
      adjust = _list(j['adjust'], Adjust.fromJson);
  final String key;
  @override
  final String per;
  @override
  final Object? amount, count, base;
  @override
  final List<Adjust> adjust;
  @override
  String? get shared => null;
}

// 2.7 중복 묶음, 2.8 옵션, 2.9 사실

class Stack {
  Stack.fromJson(Json j)
    : key = j['key'],
      pick = j['pick'] ?? 'best',
      order = _strs(j['order']),
      spill = j['spill'] ?? 'none';
  final String key, pick, spill;
  final List<String> order;
}

class Choice {
  Choice.fromJson(Json j) : key = j['key'], title = j['title'];
  final String key, title;
}

class Option {
  Option.fromJson(Json j)
    : key = j['key'],
      title = j['title'],
      choices = _list(j['choices'], Choice.fromJson),
      defaultChoice = j['default'],
      change = j['change'],
      unsupported = _strs(j['unsupported']);
  final String key, title, change;
  final List<Choice> choices;
  final String? defaultChoice;
  final List<String> unsupported;
}

class Ranked {
  Ranked.fromJson(Json j)
    : key = j['key'],
      top = _table(j['top']),
      by = j['by'] ?? 'month_amount',
      cancellation = j['cancellation'];
  final String key, by;

  /// int 또는 {구간: int}
  final Object? top;

  /// 영역 이용액에서 취소를 빼는 달. 비우면 확인 필요라 결제한 달에서 뺀다. E55
  final String? cancellation;
}

class Fact {
  Fact.fromJson(Json j)
    : key = j['key'],
      type = j['type'],
      scope = j['scope'],
      ask = j['ask'],
      choices = j['choices'] == null ? null : _strs(j['choices']);
  final String key, type, scope, ask;
  final List<String>? choices;
}

// 2.10 실적 규칙과 신규 발급 특례, 2.11 공통 제외

class CancellationOverride {
  CancellationOverride.fromJson(Json j)
    : when = Condition.fromJson(j['when']),
      use = j['use'];
  final Condition when;
  final String use;
}

class Spend {
  Spend.fromJson(Json j)
    : basis = j['basis'],
      regions = j['regions'] == null
          ? const ['domestic', 'overseas']
          : _strs(j['regions']),
      excludeCategories = _strs(j['exclude_categories']),
      interestFree = j['interest_free'] ?? 'count',
      installment = j['installment'],
      cancellation = j['cancellation'],
      cancellationOverrides = _list(
        j['cancellation_overrides'],
        CancellationOverride.fromJson,
      ),
      monthOffset = Map<String, int>.from(j['month_offset'] ?? const {}),
      excludeApplied = j['exclude_applied'] ?? 0;
  final String basis, interestFree, installment, cancellation;
  final List<String> regions, excludeCategories;
  final List<CancellationOverride> cancellationOverrides;
  final Map<String, int> monthOffset;

  /// 0, 0.5, 1
  final num excludeApplied;
}

class NewCard {
  NewCard.fromJson(Json j)
    : start = j['from'],
      until = j['until'],
      tier = j['tier'],
      tierByBenefit = Map<String, int>.from(j['tier_by_benefit'] ?? const {});
  final String start, until;
  final int tier;
  final Map<String, int> tierByBenefit;
}

class BenefitExclusions {
  BenefitExclusions.fromJson(Json j)
    : categories = _strs(j['categories']),
      whenAny = _list(j['when_any'], Condition.fromJson),
      unmodeled = _strs(j['unmodeled']);
  final List<String> categories;
  final List<Condition> whenAny;
  final List<String> unmodeled;
}

// 혜택과 개정

class BenefitTiers {
  BenefitTiers.fromJson(Json j)
    : start = j['from'],
      end = j['to'],
      waivedWhen = j['waived_when'] == null
          ? null
          : Condition.fromJson(j['waived_when']);
  final int? start, end;
  final Condition? waivedWhen;
}

class Benefit {
  Benefit.fromJson(Json j)
    : key = j['key'],
      title = j['title'],
      target = Target.fromJson(j['target']),
      when = _list(j['when'], Condition.fromJson),
      area = j['area'],
      reward = Reward.fromJson(j['reward']),
      limits = _list(j['limits'], Limit.fromJson),
      tiers = j['tiers'] == null ? null : BenefitTiers.fromJson(j['tiers']),
      stack = j['stack'] ?? 'main',
      excludeApplied = j['exclude_applied'],
      validFrom = _day(j['valid_from']),
      validUntil = _day(j['valid_until']),
      unmodeled = _strs(j['unmodeled']);
  final String key, title, stack;
  final Target target;
  final List<Condition> when;
  final String? area;
  final Reward reward;
  final List<Limit> limits;
  final BenefitTiers? tiers;

  /// 0, 0.5, 1. 비우면 실적 규칙의 값이다
  final num? excludeApplied;
  final DateTime? validFrom, validUntil;
  final List<String> unmodeled;
}

/// 카드사 기본값과 패치를 합친 뒤의 개정 하나
class Rules {
  Rules.fromJson(Json j)
    : tiers = List<int>.from(j['tiers']),
      spend = Spend.fromJson(j['spend']),
      newCard = j['new_card'] == null ? null : NewCard.fromJson(j['new_card']),
      benefitExclusions = BenefitExclusions.fromJson(
        j['benefit_exclusions'] ?? const {},
      ),
      facts = _list(j['facts'], Fact.fromJson),
      options = _list(j['options'], Option.fromJson),
      ranked = _list(j['ranked'], Ranked.fromJson),
      limits = _list(j['limits'], SharedLimit.fromJson),
      stacks = _list(j['stacks'], Stack.fromJson),
      benefits = _list(j['benefits'], Benefit.fromJson),
      unmodeled = _strs(j['unmodeled']);
  final List<int> tiers;
  final Spend spend;
  final NewCard? newCard;
  final BenefitExclusions benefitExclusions;
  final List<Fact> facts;
  final List<Option> options;
  final List<Ranked> ranked;
  final List<SharedLimit> limits;
  final List<Stack> stacks;
  final List<Benefit> benefits;
  final List<String> unmodeled;
}

/// 시행일이 있는 개정. 지문은 규칙 내용으로 만든 64자리 글자라 내용이 바뀌면 바뀐다. 작업 006 설계 4절
class Revision {
  Revision.fromJson(Json j)
    : effectiveFrom = parseDay(j['effective_from']),
      effectiveFromEstimated = j['effective_from_estimated'] ?? false,
      source = j['source'],
      sha256 = j['sha256'],
      rules = Rules.fromJson(j['rules']);
  final DateTime effectiveFrom;
  final bool effectiveFromEstimated;
  final String source, sha256;
  final Rules rules;
}

// 카드

class AnnualFee {
  AnnualFee.fromJson(Json j)
    : brand = j['brand'],
      scope = j['scope'],
      form = j['form'] ?? 'physical',
      amount = j['amount'];
  final String? brand;
  final String scope, form;
  final int amount;
}

class OpenQuestion {
  OpenQuestion.fromJson(Json j)
    : path = j['path'],
      question = j['question'],
      assumed = j['assumed'];
  final String path, question;
  final Object? assumed;
}

/// 카드 규칙 파일 하나. 개정과 확인 필요 항목이다. 작업 014 설계 1절
class CardRules {
  CardRules.fromJson(Json j)
    : openQuestions = _list(j['open_questions'], OpenQuestion.fromJson),
      revisions = _list(j['revisions'], Revision.fromJson);

  /// 카드 하나의 규칙 파일. 형식 번호와 카드 id가 맞아야 읽는다
  factory CardRules.fromFile(Json j, String id) {
    if (j['schema'] != splitSchema || j['id'] != id) {
      throw FormatException('$id의 규칙 파일이 아니다');
    }
    return CardRules.fromJson(j);
  }
  final List<OpenQuestion> openQuestions;

  /// 시행일 오름차순
  final List<Revision> revisions;
}

/// 목록 파일에 든 개정 머리. 규칙 파일을 열지 않고 그날의 개정과 실적 구간을 고른다. 작업 014 설계 4절
class RevisionHead {
  RevisionHead(this.effectiveFrom, this.effectiveFromEstimated, this.tiers);
  RevisionHead.fromJson(Json j)
    : effectiveFrom = parseDay(j['effective_from']),
      effectiveFromEstimated = j['effective_from_estimated'] ?? false,
      tiers = [for (final t in j['tiers'] as List) t as int];
  final DateTime effectiveFrom;
  final bool effectiveFromEstimated;
  final List<int> tiers;
}

class CatalogCard {
  /// 한 벌 JSON의 카드 줄. 규칙도 같이 읽는다
  CatalogCard.fromJson(Json j) : this._(j, CardRules.fromJson(j), null);

  /// 목록 파일의 카드 줄. 규칙은 [revisions]나 [openQuestions]를 처음 부를 때 load로 읽는다. 작업 014 설계 2절
  CatalogCard.fromIndex(Json j, CardRules Function() load)
    : this._(j, null, load);

  CatalogCard._(Json j, this._rules, this._load)
    : id = j['id'],
      issuer = j['issuer'],
      name = j['name'],
      shortName = j['short_name'],
      searchNames = _strs(j['search_names']),
      kind = j['kind'],
      productCodes = _strs(j['product_codes']),
      status = j['status'],
      statusSince = _day(j['status_since']),
      annualFees = _list(j['annual_fees'], AnnualFee.fromJson),
      checkedAt = parseDay(j['checked_at']),
      heads = _rules != null
          ? [
              for (final r in _rules.revisions)
                RevisionHead(
                  r.effectiveFrom,
                  r.effectiveFromEstimated,
                  r.rules.tiers,
                ),
            ]
          : _list(j['revisions'], RevisionHead.fromJson);
  final String id, issuer, name, kind, status;

  /// 칩과 줄처럼 좁은 곳에 쓰는 이름. 없으면 [name]을 쓴다. 작업 011 설계 2.4
  final String? shortName;
  final List<String> searchNames, productCodes;
  final DateTime? statusSince;
  final List<AnnualFee> annualFees;
  final DateTime checkedAt;

  /// 시행일 오름차순. [revisions]와 같은 차례다
  final List<RevisionHead> heads;

  CardRules? _rules;
  final CardRules Function()? _load;
  CardRules get _loaded => _rules ??= _checked(_load!());

  /// 목록의 개정 머리와 규칙 파일의 개정이 같은 차례인가. 다른 판끼리 묶이면 머리로 고른 차례가 다른 개정을 가리켜
  /// 혜택이 조용히 틀린다. 작업 014 단계 2 위험 검토 중간 1
  CardRules _checked(CardRules rules) {
    final r = rules.revisions;
    bool same(int i) {
      final (a, h) = (r[i], heads[i]);
      return a.effectiveFrom == h.effectiveFrom &&
          a.effectiveFromEstimated == h.effectiveFromEstimated &&
          a.rules.tiers.join(',') == h.tiers.join(',');
    }

    if (r.length != heads.length ||
        !Iterable<int>.generate(r.length).every(same)) {
      throw FormatException('$id의 규칙 파일이 목록과 다른 판이다');
    }
    return rules;
  }

  /// 규칙을 이미 읽었는가. 켤 때 보유 카드 것만 읽는지 시험이 센다. 작업 014 성공 기준 2
  bool get rulesRead => _rules != null;

  List<OpenQuestion> get openQuestions => _loaded.openQuestions;

  /// 시행일 오름차순
  List<Revision> get revisions => _loaded.revisions;
}

// 공통 파일

class CategoryChild {
  CategoryChild.fromJson(Json j)
    : code = j['code'],
      name = j['name'],
      kakao = j['kakao'];
  final String code, name;
  final String? kakao;
}

class Category {
  Category.fromJson(Json j)
    : code = j['code'],
      name = j['name'],
      kakao = j['kakao'],
      children = _list(j['children'], CategoryChild.fromJson);
  final String code, name;
  final String? kakao;
  final List<CategoryChild> children;
}

class Merchant {
  Merchant.fromJson(Json j)
    : key = j['key'],
      name = j['name'],
      category = j['category'],
      aliases = _strs(j['aliases']),
      billing = j['billing'] ?? 'normal';
  final String key, name, category, billing;
  final List<String> aliases;
}

class PaymentMethod {
  PaymentMethod.fromJson(Json j)
    : key = j['key'],
      name = j['name'],
      statementNames = _strs(j['statement_names']);
  final String key, name;
  final List<String> statementNames;
}

class PointProgram {
  PointProgram.fromJson(Json j)
    : key = j['key'],
      name = j['name'],
      wonPerPoint = j['won_per_point'] ?? 1;
  final String key, name;
  final num wonPerPoint;
}

class ReferenceValue {
  ReferenceValue.fromJson(Json j)
    : key = j['key'],
      value = j['value'],
      unit = j['unit'],
      asOf = parseDay(j['as_of']),
      source = j['source'];
  final String key, unit, source;
  final num value;
  final DateTime asOf;
}

class Issuer {
  Issuer.fromJson(Json j)
    : id = j['id'],
      name = j['name'],
      shortName = j['short_name'];
  final String id, name;

  /// "신한"처럼 칩에 쓰는 이름. 없으면 [name]을 쓴다. 작업 011 설계 2.4
  final String? shortName;
}

/// 앱이 담거나 받은 카탈로그 한 벌
class Catalog {
  /// 형식 번호가 [catalogSchema]보다 크면 FormatException이다. 새 칸이 생긴 파일을 옛 앱이 잘못 읽지 않게 한다
  factory Catalog.fromJson(Json j) {
    final schema = j['schema'];
    if (schema is! int || schema > catalogSchema) {
      throw FormatException('카탈로그 형식 번호 $schema를 읽지 못한다');
    }
    return Catalog._(j, CatalogCard.fromJson);
  }

  /// 목록 파일. 카드 규칙은 쓸 때 load(카드 id, 규칙 파일 지문)로 읽는다. 작업 014 설계 2절
  factory Catalog.fromIndex(
    Json j,
    CardRules Function(String id, String sha256) load,
  ) {
    final schema = j['schema'];
    if (schema is! int || schema != splitSchema) {
      throw FormatException('목록 파일 형식 번호 $schema를 읽지 못한다');
    }
    // 칸이 빠진 목록은 깨진 파일이다. 청구 방식 업종이 비면 추천이 담을 수 없는 업종을 계산해 버린다. 단계 2 위험
    // 검토 중간 2, 낮음 3
    if (j['billing_bound'] is! List) {
      throw const FormatException('목록 파일에 청구 방식 업종이 없다');
    }
    return Catalog._(j, (c) {
      final id = c['id'] as String, sha = c['file_sha256'] as String;
      return CatalogCard.fromIndex(c, () => load(id, sha));
    }, billingBound: {..._strs(j['billing_bound'])});
  }

  Catalog._(Json j, CatalogCard Function(Json) card, {this.billingBound})
    : holidays = {for (final h in _strs(j['holidays'])) parseDay(h)},
      categoryTree = _list(j['categories'], Category.fromJson),
      merchants = {
        for (final m in _list(j['merchants'], Merchant.fromJson)) m.key: m,
      },
      paymentMethods = {
        for (final m in _list(j['payment_methods'], PaymentMethod.fromJson))
          m.key: m,
      },
      pointPrograms = {
        for (final m in _list(j['point_programs'], PointProgram.fromJson))
          m.key: m,
      },
      reference = {
        for (final m in _list(j['reference'], ReferenceValue.fromJson))
          m.key: m,
      },
      issuers = {for (final i in _list(j['issuers'], Issuer.fromJson)) i.id: i},
      cards = {for (final c in _list(j['cards'], card)) c.id: c};

  /// 목록 파일이 적어 둔 청구 방식 조건의 대상 업종. 한 벌 JSON이면 null이고 추천이 모은다. 작업 014 설계 4절
  final Set<String>? billingBound;

  /// 한국 공휴일. 대체공휴일과 선거일이 들어 있다
  final Set<DateTime> holidays;
  final List<Category> categoryTree;
  final Map<String, Merchant> merchants;
  final Map<String, PaymentMethod> paymentMethods;
  final Map<String, PointProgram> pointPrograms;
  final Map<String, ReferenceValue> reference;
  final Map<String, Issuer> issuers;
  final Map<String, CatalogCard> cards;

  /// 부모 업종과 `부모.자식` 업종 코드
  late final Set<String> categories = {
    for (final c in categoryTree) ...[
      c.code,
      for (final ch in c.children) '${c.code}.${ch.code}',
    ],
  };
}
