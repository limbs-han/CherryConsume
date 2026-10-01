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
  };
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
  final String? category, merchantDisplay, categoryName, pick;
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

  Future<Draft> draft(PaymentInput input) async =>
      Draft(await _send('POST', '/me/payments/draft', body: input.toJson()));

  /// 저장하고 혜택이 바뀐 다른 결제 수를 돌려준다. 앞선 결제나 지난달 결제를 넣으면 생긴다. E52, E53
  Future<int> savePayment(PaymentInput input) async =>
      (await _send('POST', '/me/payments', body: input.toJson()))['repriced']
          as int;
}
