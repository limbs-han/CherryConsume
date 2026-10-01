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
}
