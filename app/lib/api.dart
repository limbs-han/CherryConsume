/// 서버 호출. 작업 005 설계 5절. 테스트는 http 패키지의 가짜 클라이언트를 넣는다.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

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
      issuerName = j['issuer_name'],
      kind = j['kind'],
      annualFee = j['annual_fee'],
      tiers = List<int>.from(j['tiers']);
  final String id, name, issuerName, kind;
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
      tiers = List<int>.from(j['tiers']),
      headline = j['headline'],
      spend = Spend(j['spend']);
  final String id, name;
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

  /// 추천 결과에서 연 결제 기록이면 그 추천 요청. 저장할 때만 보낸다. S4
  String? recommendationRequestId;

  /// 자동납부, 후불교통, 정기결제. 비우면 가맹점의 기본 청구 방식이다
  String? billing;

  Map<String, Object?> toJson() => {
    'amount': amount,
    'merchant_name': merchantName.isEmpty ? null : merchantName,
    'user_card_id': userCardId,
    'category': category,
    // 서버는 시간대가 붙은 시각만 받는다
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
      exhausted = j['exhausted'],
      limited = j['limited'],
      provisional = j['provisional'];
  final String userCardId, name;
  final int value;
  final String? title;
  final List<String> rewards;
  final List<({String name, int extra})> payWith;
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
    : requestId = j['request_id'],
      amount = j['amount'],
      unsupported = j['unsupported'],
      merchantDisplay = j['merchant_display'],
      category = j['category'],
      categoryName = j['category_name'],
      ranking = [for (final r in j['ranking']) RecRow(r)];
  final String? requestId;
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
      revisionFrom = j['revision_from'];
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
}

class Api {
  Api({
    http.Client? client,
    FlutterSecureStorage? storage,
    this.baseUrl = apiUrl,
  }) : client = client ?? http.Client(),
       storage = storage ?? const FlutterSecureStorage();

  final http.Client client;
  final FlutterSecureStorage storage;
  final String baseUrl;
  String? _token;

  /// 서버가 401을 주면 부른다. 만료됐거나 탈퇴한 토큰이면 시작 화면으로 돌아간다
  void Function()? onSignedOut;

  static const _tokenKey = 'token';

  /// 기기의 안전 저장소에 둔 토큰을 읽는다. 설계 문서 4.3절 4번
  Future<bool> restore() async {
    try {
      _token = await storage.read(key: _tokenKey);
    } catch (_) {
      // 저장소를 읽지 못하면 로그인하지 않은 것으로 본다. 빈 화면에 멈추지 않게 한다
      _token = null;
    }
    return _token != null;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri);
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await client.send(request));
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode == 401 && _token != null) {
      _token = null;
      await storage.delete(key: _tokenKey);
      onSignedOut?.call();
    }
    if (response.statusCode >= 400) throw ApiError(response.statusCode, text);
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<void> devLogin(String name) async {
    final r = await _send('POST', '/auth/dev', body: {'name': name});
    _token = r['token'];
    await storage.write(key: _tokenKey, value: _token);
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/auth/logout');
    } finally {
      _token = null;
      await storage.delete(key: _tokenKey);
    }
  }

  Future<List<({String code, String name})>> issuers() async => [
    for (final r in await _send('GET', '/catalog/issuers'))
      (code: r['code'] as String, name: r['name'] as String),
  ];

  Future<List<CardHit>> searchCards({String q = '', String? issuer}) async => [
    for (final r in await _send(
      'GET',
      '/catalog/cards',
      query: {'q': q, 'issuer': ?issuer},
    ))
      CardHit(r),
  ];

  Future<Preview> preview(
    String cardId, {
    int? prev,
    DateTime? startedOn,
  }) async => Preview(
    await _send(
      'GET',
      '/catalog/cards/$cardId/preview',
      query: {
        'prev': ?prev?.toString(),
        'started_on': ?startedOn?.toIso8601String().substring(0, 10),
      },
    ),
  );

  Future<void> addCard(String cardId, {int? prev, DateTime? startedOn}) =>
      _send(
        'POST',
        '/me/cards',
        body: {
          'card_id': cardId,
          'assumed_prev_month_spend': prev,
          'started_on': startedOn?.toIso8601String().substring(0, 10),
        },
      );

  Future<Home> home() async => Home(await _send('GET', '/me/home'));

  Future<List<Category>> categories() async => [
    for (final c in await _send('GET', '/catalog/categories'))
      (
        code: c['code'] as String,
        name: c['name'] as String,
        children: [
          for (final ch in c['children'])
            (code: ch['code'] as String, name: ch['name'] as String),
        ],
      ),
  ];

  Future<Map<String, String>> paymentMethods() async => {
    for (final m in await _send('GET', '/catalog/payment-methods'))
      m['key'] as String: m['name'] as String,
  };

  /// 고치는 화면이면 editing에 그 결제 id를 넣는다. 서버가 옛 값을 빼고 계산한다
  Future<Draft> draft(PaymentInput input, {String? editing}) async => Draft(
    await _send(
      'POST',
      '/me/payments/draft',
      body: {...input.toJson(), 'editing': ?editing},
    ),
  );

  Future<List<TopRow>> top() async => [
    for (final r in await _send('GET', '/me/recommendations/top')) TopRow(r),
  ];

  Future<List<String>> recentMerchants() async => [
    for (final r in await _send('GET', '/me/recent-merchants')) r as String,
  ];

  Future<RecResult> recommend({
    String? merchantName,
    String? category,
    int? amount,
  }) async => RecResult(
    await _send(
      'POST',
      '/me/recommendations',
      body: {
        'merchant_name': merchantName,
        'category': category,
        'amount': amount,
      },
    ),
  );

  /// 그 달 기록. 비우면 이번 달이다. card를 주면 그 카드만 본다. S7
  Future<Records> records({DateTime? month, String? card}) async => Records(
    await _send(
      'GET',
      '/me/payments',
      query: {
        'month': ?(month == null
            ? null
            : '${month.year}-${month.month.toString().padLeft(2, '0')}'),
        'card': ?card,
      },
    ),
  );

  /// 고치고 혜택이 바뀐 다른 결제 수를 돌려준다. E54
  Future<int> editPayment(String id, PaymentInput input) async =>
      (await _send(
            'PATCH',
            '/me/payments/$id',
            body: input.toJson(),
          ))['repriced']
          as int;

  /// 지금까지 취소된 금액의 합과 취소한 때를 적고 혜택이 바뀐 다른 결제 수를 돌려준다. 0이면 취소를 되돌린다. E5, E54
  Future<int> cancelPayment(
    String id,
    int cancelledAmount,
    DateTime at,
  ) async =>
      (await _send(
            'POST',
            '/me/payments/$id/cancel',
            body: {
              'cancelled_amount': cancelledAmount,
              'cancelled_at': at.toUtc().toIso8601String(),
            },
          ))['repriced']
          as int;

  Future<int> deletePayment(String id) async =>
      (await _send('DELETE', '/me/payments/$id'))['repriced'] as int;

  Future<CardDetail> cardDetail(String id) async =>
      CardDetail(await _send('GET', '/me/cards/$id'));

  Future<void> removeCard(String id) => _send('DELETE', '/me/cards/$id');

  /// 저장하고 혜택이 바뀐 다른 결제 수를 돌려준다. 앞선 결제나 지난달 결제를 넣으면 생긴다. E52, E53
  Future<int> savePayment(PaymentInput input) async =>
      (await _send(
            'POST',
            '/me/payments',
            body: {
              ...input.toJson(),
              'recommendation_request_id': input.recommendationRequestId,
            },
          ))['repriced']
          as int;
}
