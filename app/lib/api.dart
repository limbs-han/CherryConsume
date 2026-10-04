/// 화면이 쓰는 데이터 클래스와 폰 안 저장소의 입구 Api. 작업 006 설계 4절
///
/// 데이터 클래스는 서버를 부르던 때와 같다. 저장소가 서버와 같은 모양의 Map을 주기 때문이다
library;

import 'dart:typed_data';

import 'catalog/models.dart' show day;
import 'store/backup.dart' as backup;
import 'store/routes/answers.dart' as answers;
import 'store/routes/catalog.dart' as catalog_routes;
import 'store/routes/imports.dart' as import_routes;
import 'store/routes/me.dart' as me;
import 'store/routes/payments.dart' as payments;
import 'store/routes/recommend.dart' as recommend_routes;
import 'store/routes/records.dart' as records_routes;
import 'store/store.dart';

class ApiError implements Exception {
  ApiError(this.status, this.body);
  final int status;
  final String body;

  @override
  String toString() => 'ApiError($status)';
}

class CardHit {
  CardHit(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      issuer = j['issuer'],
      issuerName = j['issuer_name'],
      kind = j['kind'],
      annualFee = j['annual_fee'],
      tiers = List<int>.from(j['tiers']);
  final String id, name, issuerName, kind;

  /// 카드사 코드. 카드사 색 칸에 쓴다. 작업 011 설계 2절 A1
  final String? issuer;
  final int? annualFee;
  final List<int> tiers;
}

class Preview {
  Preview(Map<String, dynamic> j)
    : tier = j['tier'],
      tierSource = j['tier_source'],
      tiers = List<int>.from(j['tiers']),
      benefits = List<String>.from(j['benefits']);
  final int? tier;
  final String tierSource;
  final List<int> tiers;
  final List<String> benefits;
}

class Spend {
  Spend(Map<String, dynamic> j)
    : counted = j['counted'],
      tier = j['tier'],
      tierSource = j['tier_source'],
      toKeep = j['to_keep'],
      nextTier = j['next_tier'],
      toNext = j['to_next'];
  final int counted;
  final int? tier, toKeep, nextTier, toNext;
  final String tierSource;
}

class HomeCard {
  HomeCard(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      issuer = j['issuer'],
      tiers = List<int>.from(j['tiers']),
      headline = j['headline'],
      spend = Spend(j['spend']);
  final String id, name;

  /// 카드사 코드. 카드사 색 칸에 쓴다. 작업 011 설계 2절 H4
  final String? issuer;
  final List<int> tiers;
  final String? headline;
  final Spend spend;
}

class Home {
  Home(Map<String, dynamic> j)
    : month = DateTime.parse(j['month']),
      benefitTotal = j['benefit_total'],
      cards = [for (final c in j['cards']) HomeCard(c)];
  final DateTime month;
  final int benefitTotal;
  final List<HomeCard> cards;
}

/// 결제 기록 화면의 입력. 저장 전 결제와 저장에 같은 칸을 보낸다. 작업 005 설계 5b절
class PaymentInput {
  int? amount;
  String merchantName = '';
  String? userCardId;
  String? category;
  DateTime? paidAt;
  String? channel;
  int installmentMonths = 1;
  bool interestFree = false;
  bool overseas = false;
  String? paymentMethod;

  /// 추천 결과에서 연 결제 기록이면 참. 저장할 때 "추천에서 기록함" 표시로 남는다. S4, 작업 006 설계 4절
  bool fromRecommendation = false;

  /// 자동납부, 후불교통, 정기결제. 비우면 가맹점의 기본 청구 방식이다
  String? billing;

  Map<String, Object?> toJson() => {
    'amount': amount,
    'merchant_name': merchantName.isEmpty ? null : merchantName,
    'user_card_id': userCardId,
    'category': category,
    // 저장소는 시간대가 붙은 시각만 받는다
    'paid_at': paidAt?.toUtc().toIso8601String(),
    'channel': channel,
    'installment_months': installmentMonths,
    'interest_free': installmentMonths > 1 && interestFree,
    'region': overseas ? 'overseas' : 'domestic',
    'payment_method': paymentMethod,
    'billing': billing,
  };
}

class RecRow {
  RecRow(Map<String, dynamic> j)
    : userCardId = j['user_card_id'],
      name = j['name'],
      value = j['value'],
      title = j['title'],
      rewards = List<String>.from(j['rewards']),
      payWith = [
        for (final m in j['pay_with'])
          (name: m['name'] as String, extra: m['extra'] as int),
      ],
      asks = [
        for (final a in j['ask'] ?? const [])
          (
            kind: a['kind'] as String,
            scope: a['scope'] as String?,
            question: a['question'] as String,
            extra: a['extra'] as int,
          ),
      ],
      exhausted = j['exhausted'],
      limited = j['limited'],
      provisional = j['provisional'];
  final String userCardId, name;
  final int value;
  final String? title;
  final List<String> rewards;
  final List<({String name, int extra})> payWith;

  /// 사실이나 옵션을 답하면 더 받는 금액. 사람 사실은 설정, 나머지는 카드 상세에서 답한다. 작업 005 설계 5e
  final List<({String kind, String? scope, String question, int extra})> asks;
  final bool exhausted, limited, provisional;

  /// 할인, 적립, 캐시백. 함께 받으면 모두 보인다. 포인트는 원으로 바꾼 값이다. E13
  String get kind => {
    for (final r in rewards)
      switch (r) {
        'points' => '적립',
        'cashback' => '캐시백',
        _ => '할인',
      },
  }.join('·');
}

class TopRow {
  TopRow(Map<String, dynamic> j)
    : category = j['category'],
      categoryName = j['category_name'],
      row = RecRow(j);
  final String category, categoryName;
  final RecRow row;
}

class RecResult {
  RecResult(Map<String, dynamic> j)
    : amount = j['amount'],
      unsupported = j['unsupported'],
      merchantDisplay = j['merchant_display'],
      category = j['category'],
      categoryName = j['category_name'],
      ranking = [for (final r in j['ranking']) RecRow(r)];
  final int? amount;

  /// 계산하지 않은 까닭. billing이면 청구 방식에 따라 혜택이 갈리는 업종을 가게 없이 물은 것이다
  final String? unsupported;
  final String? merchantDisplay, category, categoryName;
  final List<RecRow> ranking;
}

class Estimate {
  Estimate(Map<String, dynamic> j)
    : value = j['value'],
      paymentMethod = j['payment_method'],
      counted = j['counted'],
      titles = [for (final b in j['benefits']) b['title'] as String];
  final int value;
  final String? paymentMethod;
  final bool counted;
  final List<String> titles;
}

class Draft {
  Draft(Map<String, dynamic> j)
    : category = j['category'],
      merchantDisplay = j['merchant_display'],
      categoryName = j['category_name'],
      billing = j['billing'],
      channel = j['channel'],
      paidAt = DateTime.parse(j['paid_at']).toLocal(),
      ranking = [
        for (final r in j['ranking'])
          (
            id: r['user_card_id'] as String,
            name: r['name'] as String,
            value: r['value'] as int,
          ),
      ],
      pick = j['pick'],
      estimate = j['estimate'] == null ? null : Estimate(j['estimate']);
  final String? category, merchantDisplay, categoryName, pick, billing;
  final String channel;
  final DateTime paidAt;
  final List<({String id, String name, int value})> ranking;
  final Estimate? estimate;
}

typedef Category = ({
  String code,
  String name,
  List<({String code, String name})> children,
});

/// 기록 한 줄. 고치기 화면을 채우는 칸도 함께 온다
class RecordRow {
  RecordRow(Map<String, dynamic> j)
    : id = j['id'],
      paidAt = DateTime.parse(j['paid_at']).toLocal(),
      merchantName = j['merchant_name'],
      category = j['category'],
      categoryName = j['category_name'],
      userCardId = j['user_card_id'],
      cardName = j['card_name'],
      amount = j['amount'],
      cancelledAmount = j['cancelled_amount'],
      cancelledAt = j['cancelled_at'] == null
          ? null
          : DateTime.parse(j['cancelled_at']).toLocal(),
      timeKnown = j['time_known'] ?? true,
      value = j['value'],
      rewards = List<String>.from(j['rewards']),
      counted = j['counted'],
      channel = j['channel'],
      region = j['region'],
      installmentMonths = j['installment_months'],
      interestFree = j['interest_free'],
      paymentMethod = j['payment_method'],
      billing = j['billing'];
  final String id, userCardId, cardName, channel, region;
  final DateTime paidAt;
  final DateTime? cancelledAt;

  /// 엑셀에 날짜만 있던 결제는 시각을 모른다. 기록에서 시각을 고치면 안다. E57
  final bool timeKnown;
  final String? merchantName, category, categoryName, paymentMethod, billing;
  final int amount, cancelledAmount, value, installmentMonths;
  final List<String> rewards;
  final bool counted, interestFree;

  /// 고치기 화면의 처음 값
  PaymentInput toInput() => PaymentInput()
    ..amount = amount
    ..merchantName = merchantName ?? ''
    ..userCardId = userCardId
    ..category = category
    ..paidAt = paidAt
    ..channel = channel
    ..installmentMonths = installmentMonths
    ..interestFree = interestFree
    ..overseas = region == 'overseas'
    ..paymentMethod = paymentMethod
    ..billing = billing;
}

class Records {
  Records(Map<String, dynamic> j)
    : month = DateTime.parse(j['month']),
      count = j['count'],
      amount = j['amount'],
      benefitTotal = j['benefit_total'],
      cards = [
        for (final c in j['cards'])
          (id: c['id'] as String, name: c['name'] as String),
      ],
      payments = [for (final r in j['payments']) RecordRow(r)];
  final DateTime month;
  final int count, amount, benefitTotal;
  final List<({String id, String name})> cards;
  final List<RecordRow> payments;
}

class CardDetail {
  CardDetail(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      tiers = List<int>.from(j['tiers']),
      spend = Spend(j['spend']),
      prevMonthCounted = j['spend']['prev_month_counted'],
      limits = [
        for (final l in j['limits'])
          (
            title: l['title'] as String,
            per: l['per'] as String,
            usedAmount: l['used_amount'] as int,
            capAmount: l['cap_amount'] as int?,
            usedCount: l['used_count'] as int,
            capCount: l['cap_count'] as int?,
            usedBase: l['used_base'] as int,
            capBase: l['cap_base'] as int?,
          ),
      ],
      locked = [
        for (final l in j['locked'])
          (
            title: l['title'] as String,
            requiredTier: l['required_tier'] as int,
            remaining: l['remaining'] as int,
          ),
      ],
      checkSentences = List<String>.from(j['check_sentences']),
      assumedCount = j['assumed_count'],
      startedOn = j['started_on'],
      revisionFrom = j['revision_from'],
      facts = [for (final q in j['questions']['facts']) FactQuestion(q)],
      options = [for (final q in j['questions']['options']) OptionQuestion(q)];
  final String id, name;
  final List<int> tiers;
  final Spend spend;
  final int? prevMonthCounted;
  final List<
    ({
      String title,
      String per,
      int usedAmount,
      int? capAmount,
      int usedCount,
      int? capCount,
      int usedBase,
      int? capBase,
    })
  >
  limits;
  final List<({String title, int requiredTier, int remaining})> locked;
  final List<String> checkSentences;
  final int assumedCount;
  final String? startedOn, revisionFrom;
  final List<FactQuestion> facts;
  final List<OptionQuestion> options;
}

/// 카드 사실이나 사람 사실 하나. bool은 참과 거짓, month는 1~12, choice는 선택지다. 작업 005 설계 5e
class FactQuestion {
  FactQuestion(Map<String, dynamic> j)
    : key = j['key'],
      type = j['type'],
      ask = j['ask'],
      choices = j['choices'] == null ? null : List<String>.from(j['choices']),
      answer = j['answer'],
      cards = List<String>.from(j['cards'] ?? const []);
  final String key, type, ask;
  final List<String>? choices;
  final Object? answer;

  /// 설정에서만 온다. 이 답을 쓰는 카드 이름
  final List<String> cards;
}

/// 카드 옵션 하나. 다음 달부터 바뀌는 답은 pending이다
class OptionQuestion {
  OptionQuestion(Map<String, dynamic> j)
    : key = j['key'],
      title = j['title'],
      choices = [
        for (final c in j['choices'])
          (key: c['key'] as String, title: c['title'] as String),
      ],
      unsupported = List<String>.from(j['unsupported']),
      answer = j['answer'] ?? j['default'],
      pendingValue = j['pending']?['value'],
      pendingFrom = j['pending']?['from'];
  final String key, title;
  final List<({String key, String title})> choices;
  final List<String> unsupported;
  final String? answer, pendingValue, pendingFrom;
}

/// 엑셀 가져오기 미리보기. 열을 못 찾으면 needsMapping과 열 이름이다
class ImportPreview {
  ImportPreview(Map<String, dynamic> j)
    : needsMapping = j['needs_mapping'],
      headerRow = j['header_row'],
      headers = List<String>.from(j['headers']),
      mapping = j['mapping'] == null
          ? null
          : Map<String, int>.from(j['mapping'] as Map),
      signature = j['signature'],
      topRows = [
        for (final r in j['top_rows'] ?? const []) List<String>.from(r as List),
      ],
      rows = [for (final r in j['rows']) r as Map<String, dynamic>],
      summary = j['summary'] as Map<String, dynamic>?;
  final bool needsMapping;
  final int headerRow;
  final List<String> headers;
  final Map<String, int>? mapping;
  final String? signature;

  /// 머리 줄을 고를 위 10줄. 앱이 올린 파일의 줄이다
  final List<List<String>> topRows;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? summary;
}

/// 저장한 결제. 업종이 부모까지만 있으면 자식 업종을 묻는다. E47
class Saved {
  Saved(Map<String, dynamic> j)
    : id = j['id'],
      repriced = j['repriced'],
      askParent = j['ask_category']?['parent_name'],
      askChildren = [
        for (final c in j['ask_category']?['children'] ?? const [])
          (code: c['code'] as String, name: c['name'] as String),
      ];
  final String id;
  final int repriced;
  final String? askParent;
  final List<({String code, String name})> askChildren;
}

/// 폰 안 저장소를 부르는 앱의 입구. 화면은 서버를 부르던 때와 같은 메서드를 부른다. 작업 006 설계 4절
///
/// store/의 함수는 서버가 주던 JSON과 같은 모양의 Map을 돌려주고 여기서 데이터 클래스에 넣는다. 서버가 404, 409, 422로
/// 거절하던 것은 같은 번호의 ApiError로 던진다. 저장소는 동기라 Future는 화면 코드를 그대로 두려는 것이다
class Api {
  Api(this.store);
  final Store store;

  /// 날짜 고르기가 준 폰 시간 날짜를 저장소의 날짜로
  static DateTime? _day(DateTime? d) =>
      d == null ? null : day(d.year, d.month, d.day);

  Future<List<({String code, String name})>> issuers() async => [
    for (final r in catalog_routes.issuers(store))
      (code: r['code'] as String, name: r['name'] as String),
  ];

  Future<List<CardHit>> searchCards({String q = '', String? issuer}) async => [
    for (final r in catalog_routes.cards(store, q: q, issuer: issuer))
      CardHit(r),
  ];

  Future<Preview> preview(
    String cardId, {
    int? prev,
    DateTime? startedOn,
  }) async => Preview(
    catalog_routes.preview(
      store,
      cardId,
      prev: prev,
      startedOn: _day(startedOn),
    ),
  );

  Future<void> addCard(String cardId, {int? prev, DateTime? startedOn}) async {
    me.addCard(
      store,
      cardId,
      assumedPrevMonthSpend: prev,
      startedOn: _day(startedOn),
    );
  }

  Future<Home> home() async => Home(me.home(store));

  Future<List<Category>> categories() async => [
    for (final c in catalog_routes.categories(store))
      (
        code: c['code'] as String,
        name: c['name'] as String,
        children: [
          for (final ch in c['children'] as List)
            (code: ch['code'] as String, name: ch['name'] as String),
        ],
      ),
  ];

  Future<Map<String, String>> paymentMethods() async => {
    for (final m in catalog_routes.paymentMethods(store))
      m['key'] as String: m['name'] as String,
  };

  /// 고치는 화면이면 editing에 그 결제 id를 넣는다. 옛 값을 빼고 계산한다
  Future<Draft> draft(PaymentInput input, {String? editing}) async =>
      Draft(payments.draft(store, {...input.toJson(), 'editing': ?editing}));

  Future<List<TopRow>> top() async => [
    for (final r in recommend_routes.top(store)) TopRow(r),
  ];

  Future<List<String>> recentMerchants() async =>
      recommend_routes.recent(store);

  Future<RecResult> recommend({
    String? merchantName,
    String? category,
    int? amount,
  }) async => RecResult(
    recommend_routes.recommend(store, {
      'merchant_name': merchantName,
      'category': category,
      'amount': amount,
    }),
  );

  /// 그 달 기록. 비우면 이번 달이다. card를 주면 그 카드만 본다. S7
  Future<Records> records({DateTime? month, String? card}) async => Records(
    records_routes.records(
      store,
      month: month == null
          ? null
          : '${month.year}-${month.month.toString().padLeft(2, '0')}',
      card: card,
    ),
  );

  /// 고치고 혜택이 바뀐 다른 결제 수와 자식 업종 질문을 돌려준다. E54, E47
  Future<Saved> editPayment(String id, PaymentInput input) async =>
      Saved(records_routes.edit(store, id, input.toJson()));

  /// 카드 사실, 옵션, 쓰기 시작한 날을 답하고 혜택이 바뀐 결제 수를 돌려준다. E56
  Future<int> answerCard(String id, Map<String, Object?> body) async =>
      answers.cardAnswers(store, id, body)['repriced'] as int;

  /// 카탈로그 날짜. 카드마다 공식 문구와 대조한 날 가운데 가장 늦은 날이다. 작업 011 설계 2절 S2
  DateTime catalogDay() => store.catalog.cards.values
      .map((c) => c.checkedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  /// 설정의 혜택 계산에 쓰는 답. 가진 카드들의 사람 사실이다
  Future<List<FactQuestion>> userFacts() async => [
    for (final q in answers.userFacts(store)) FactQuestion(q),
  ];

  Future<int> answerFacts(Map<String, Object> facts) async =>
      answers.putUserFacts(store, {'facts': facts})['repriced'] as int;

  /// 지금까지 취소된 금액의 합과 취소한 때를 적고 혜택이 바뀐 다른 결제 수를 돌려준다. 0이면 취소를 되돌린다. E5, E54
  Future<int> cancelPayment(
    String id,
    int cancelledAmount,
    DateTime at,
  ) async =>
      records_routes.cancel(store, id, {
            'cancelled_amount': cancelledAmount,
            'cancelled_at': at.toUtc().toIso8601String(),
          })['repriced']
          as int;

  Future<int> deletePayment(String id) async =>
      records_routes.delete(store, id)['repriced'] as int;

  Future<CardDetail> cardDetail(String id) async =>
      CardDetail(me.cardDetail(store, id));

  Future<void> removeCard(String id) async {
    me.removeCard(store, id);
  }

  /// 저장하고 혜택이 바뀐 다른 결제 수를 돌려준다. 앞선 결제나 지난달 결제를 넣으면 생긴다. E52, E53
  Future<Saved> savePayment(PaymentInput input) async => Saved(
    payments.save(store, {
      ...input.toJson(),
      'from_recommendation': input.fromRecommendation,
    }),
  );

  /// 파일을 읽어 미리보기를 준다. 파일은 메모리에서 읽고 바로 버린다. E35. 짝지은 열이 있으면 그 짝으로 읽는다. E30
  /// ponytail: 읽기와 판정이 화면과 같은 isolate에서 돈다. 2MB 파일이 화면을 눈에 띄게 멈추면 읽기를 Isolate.run으로 옮긴다
  Future<ImportPreview> importPreview(
    Uint8List data, {
    String? userCardId,
    int? headerRow,
    Map<String, int>? columns,
  }) async => ImportPreview(
    import_routes.preview(
      store,
      data,
      userCardId: userCardId,
      mapping: columns == null ? null : {'row': headerRow, 'columns': columns},
    ),
  );

  /// 미리보기의 행을 저장한다. 저장소가 다시 판정한다. 짝지은 열은 이때 남긴다
  Future<Map<String, dynamic>> saveImport(
    List<Map<String, dynamic>> rows, {
    String? signature,
    Map<String, int>? columns,
  }) async => import_routes.save(store, {
    'rows': rows,
    'mapping': columns == null
        ? null
        : {'signature': signature, 'columns': columns},
  });

  Future<List<Map<String, dynamic>>> imports() async =>
      import_routes.batches(store);

  /// 가져온 묶음 되돌리기. E34
  Future<void> undoImport(int id) async => import_routes.undo(store, id);

  /// 기록을 JSON 한 파일로. 작업 006 설계 6절
  /// ponytail: 내보내기와 가져오기가 화면과 같은 isolate에서 돈다. 결제 수만 건에서 화면이 눈에 띄게 멈추면 JSON 읽기와
  /// 쓰기를 Isolate.run으로 옮긴다. 단계 6 위험 검토 9번
  Future<String> exportRecords() async => backup.exportAll(store);

  /// 보유 카드나 결제가 있으면 가져오기 전에 바꿀지 묻는다
  Future<bool> hasRecords() async => backup.hasRecords(store);

  /// 지금 기록을 지우고 파일의 기록으로 바꾼다. 받지 않는 파일이면 지금 기록이 그대로다
  Future<void> importRecords(Uint8List data) async =>
      backup.importAll(store, data);
}
