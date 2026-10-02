/// 서버 호출. 작업 005 설계 5절. 테스트는 http 패키지의 가짜 클라이언트를 넣는다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// 연결이 끊겼거나 시간이 지났다. 작업 005 설계 5i
bool disconnected(Object e) =>
    e is http.ClientException || e is TimeoutException || e is IOException;

/// 서버에 닿지 못했는가. 끊김, 서버의 500번대, 408, 429다. 나머지 400번대는 다시 보내도 같다. 설계 5i
bool unreachable(Object e) =>
    disconnected(e) ||
    (e is ApiError && (e.status >= 500 || e.status == 408 || e.status == 429));

/// 결제마다 앱이 만드는 번호. 서버가 같은 번호를 한 번만 넣는다. E24
String newClientId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

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
  Home(
    Map<String, dynamic> j, {
    this.cachedAt,
    this.pending = const [],
    this.sent = 0,
    this.repriced = 0,
  }) : month = DateTime.parse(j['month']),
       benefitTotal = j['benefit_total'],
       cards = [for (final c in j['cards']) HomeCard(c)];
  final DateTime month;
  final int benefitTotal;
  final List<HomeCard> cards;

  /// 서버에 닿지 못해 폰에 둔 홈을 보이면 그 홈을 받은 때다. E26
  final DateTime? cachedAt;

  /// 아직 보내지 못한 결제. E24
  final List<Pending> pending;

  /// 이번에 보낸 모아 둔 결제 수와 그 때문에 혜택이 바뀐 다른 결제 수. E52
  final int sent, repriced;
}

/// 같은 번호의 결제가 이미 서버에 있다. 409다. 새로 적으면 두 건이 되니 기록에서 보게 한다
const alreadySaved = '이미 기록에 있는 결제예요. 기록에서 확인해 주세요';

/// 서버에 닿지 못해 폰에 모아 둔 결제. 저장 몸통을 그대로 둔다. E24
class Pending {
  Pending(Map<String, dynamic> j)
    : body = Map<String, Object?>.from(j['body'] as Map),
      card = j['card'],
      error = j['error'],
      tries = j['tries'] ?? 0;
  Pending.of(this.body, this.card);
  final Map<String, Object?> body;
  final String card;

  /// 서버가 거절한 까닭. 있으면 사용자가 다시 보내기를 누를 때까지 보내지 않는다
  String? error;

  /// 서버 오류로 실패한 횟수. 세 번이면 거절로 본다
  int tries = 0;

  /// 거절됐지만 다시 보내 볼 만한가. 이미 서버에 있는 결제는 다시 보내도 같다
  bool get canRetry => error != null && error != alreadySaved;

  String get clientId => body['client_id'] as String;
  int get amount => body['amount'] as int;
  String? get merchant => body['merchant_name'] as String?;

  Map<String, Object?> toJson() => {
    'body': body,
    'card': card,
    'error': error,
    'tries': tries,
  };
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

  /// 이 결제의 번호. 화면을 열 때 한 번 만든다. 저장할 때만 보낸다. E24
  final String clientId = newClientId();

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
  static const _homeKey = 'home';
  static const _outboxKey = 'outbox';

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
    if (body is Uint8List) {
      // 엑셀 가져오기의 파일은 몸통에 그대로 보낸다. 서버는 읽고 바로 버린다. E35
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = body;
    } else if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    // 신호가 약한 곳에서 끝없이 기다리지 않게 끊는다. 응답 머리를 기다리는 때와 몸통을 받는 때 모두다. 끊긴 저장은
    // 모아 뒀다 같은 번호로 다시 보낸다. 엑셀 파일은 올리는 데 오래 걸릴 수 있어 더 기다린다. 설계 5i
    final long = body is Uint8List || path.startsWith('/me/imports');
    final limit = Duration(seconds: long ? 120 : 30);
    final streamed = await client.send(request).timeout(limit);
    final response = await http.Response.fromStream(streamed).timeout(limit);
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode == 401 && _token != null) {
      // 다른 기기에서 탈퇴했거나 세션이 끝났다. 그 계정의 홈과 모아 둔 결제를 다음 사람이 보지 않게 지운다.
      // 지운 결제 수는 시작 화면이 알린다
      _token = null;
      await storage.delete(key: _tokenKey);
      dropped = (await pending()).length;
      await _forget();
      onSignedOut?.call();
    }
    if (response.statusCode >= 400) throw ApiError(response.statusCode, text);
    return text.isEmpty ? null : jsonDecode(text);
  }

  /// 엑셀 가져오기 미리보기. 카드를 고르면 그 카드로, 안 고르면 파일의 카드 이름 열로 나눈다. 파일 이름은 보내지 않는다.
  /// 이름과 카드번호 끝자리가 들어 있을 수 있다. columns는 사용자가 짝지은 {칸: 열 번호}다. E30
  Future<ImportPreview> importPreview(
    Uint8List data, {
    String? userCardId,
    int? headerRow,
    Map<String, int>? columns,
  }) async => ImportPreview(
    await _send(
      'POST',
      '/me/imports/preview',
      query: {
        'user_card_id': ?userCardId,
        if (columns != null)
          'mapping': jsonEncode({'row': headerRow, 'columns': columns}),
      },
      body: data,
    ),
  );

  /// 미리보기의 새 결제와 취소 행을 저장한다. 서버가 다시 판정한다. 짝지은 열은 이때 남긴다
  Future<Map<String, dynamic>> saveImport(
    List<Map<String, dynamic>> rows, {
    String? signature,
    Map<String, int>? columns,
  }) async =>
      await _send(
            'POST',
            '/me/imports',
            body: {
              'rows': rows,
              'mapping': columns == null
                  ? null
                  : {'signature': signature, 'columns': columns},
            },
          )
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> imports() async => [
    for (final b in await _send('GET', '/me/imports'))
      b as Map<String, dynamic>,
  ];

  /// 가져온 묶음 되돌리기. E34
  Future<void> undoImport(int id) => _send('DELETE', '/me/imports/$id');

  /// 카카오나 Google에서 받은 토큰을 서버가 확인하고 우리 토큰을 준다. provider는 kakao나 google이다. 작업 005 설계 5g
  Future<void> socialLogin(String provider, String token) async {
    final r = await _send(
      'POST',
      '/auth/$provider',
      body: provider == 'kakao' ? {'access_token': token} : {'id_token': token},
    );
    _token = r['token'];
    await storage.write(key: _tokenKey, value: _token);
  }

  /// 설정 맨 위의 계정. 로그인 수단과 가입한 날
  Future<({String provider, DateTime createdAt})> account() async {
    final r = await _send('GET', '/me/account');
    return (
      provider: r['provider'] as String,
      createdAt: DateTime.parse(r['created_at']).toLocal(),
    );
  }

  /// 탈퇴. 서버가 모든 기기의 세션을 지워 바로 로그인을 막는다. E27
  Future<void> withdraw() async {
    await _send('DELETE', '/me');
    _token = null;
    await storage.delete(key: _tokenKey);
    await _forget();
  }

  /// 401로 지운 보내지 못한 결제 수. 시작 화면이 한 번 알리고 0으로 돌린다
  int dropped = 0;

  /// 폰에 둔 홈과 모아 둔 결제를 지운다. 폰을 다른 사람이 써도 남지 않게 한다. 모아 둔 결제를 고치는 줄에 서서
  /// 고치던 쓰기가 뒤에 덮지 않게 한다. 설계 5i
  Future<void> _forget() => _inLine(() async {
    try {
      await storage.delete(key: _homeKey);
      await storage.delete(key: _outboxKey);
    } catch (_) {}
  });

  Future<String?> _read(String key) async {
    try {
      return await storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  /// 로그아웃한 뒤 끝난 요청이 그 사람의 홈이나 결제를 폰에 다시 쓰지 않게 한다
  Future<void> _write(String key, String value) async {
    if (_token == null) return;
    try {
      await storage.write(key: key, value: value);
    } catch (_) {}
  }

  /// 아직 보내지 못한 결제. 기록한 순서다
  Future<List<Pending>> pending() async {
    final t = await _read(_outboxKey);
    if (t == null) return [];
    return [for (final p in jsonDecode(t) as List) Pending(p)];
  }

  Future<void> _outbox = Future.value();

  /// 모아 둔 결제를 읽고 쓰는 일을 한 줄로 세운다. 보내는 사이 새로 모은 결제를 덮어쓰지 않게 한다
  Future<T> _inLine<T>(Future<T> Function() f) {
    final done = _outbox.then((_) => f());
    _outbox = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// 저장소를 읽지 못하면 던진다. 빈 목록으로 보고 고쳐 쓰면 모아 둔 결제를 덮는다
  Future<List<Pending>> _strict() async {
    final t = await storage.read(key: _outboxKey);
    return t == null ? [] : [for (final p in jsonDecode(t) as List) Pending(p)];
  }

  /// 모아 둔 결제를 고쳐 쓴다. 로그아웃한 뒤나 저장소가 실패하면 던진다. 모으기는 화면이 실패로 알린다.
  /// 결제가 아무 데도 없는데 보낸다고 하지 않는다
  Future<void> _change(List<Pending> Function(List<Pending>) f) =>
      _inLine(() async {
        if (_token == null) throw StateError('로그아웃했다');
        final items = f(await _strict());
        await storage.write(
          key: _outboxKey,
          value: jsonEncode([for (final p in items) p.toJson()]),
        );
      });

  /// 서버에 닿지 못한 결제를 모아 둔다. card는 홈에 보일 카드 이름이다. E24
  Future<void> queue(PaymentInput input, String card) =>
      _change((items) => [...items, Pending.of(_saveBody(input), card)]);

  Future<void> dropPending(String clientId) => _change(
    (items) => [
      for (final p in items)
        if (p.clientId != clientId) p,
    ],
  ).catchError((_) {});

  /// 거절된 결제를 다시 보낼 차례에 넣는다
  Future<void> retryPending(String clientId) => _change(
    (items) => [
      for (final p in items)
        if (p.clientId == clientId)
          (p
            ..error = null
            ..tries = 0)
        else
          p,
    ],
  ).catchError((_) {});

  Future<({int sent, int repriced, List<String> failed})>? _flushing;

  /// 모아 둔 결제를 기록한 순서로 보낸다. 서버가 결제 시각 순서로 다시 계산해 보내는 순서는 혜택에 상관없다.
  /// failed는 서버 오류가 난 결제다. 서버가 정상으로 답한 회차인지 알아야 세므로 home이 센다. E24, E52
  Future<({int sent, int repriced, List<String> failed})> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<({int sent, int repriced, List<String> failed})> _flush() async {
    var sent = 0, repriced = 0;
    final failed = <String>[];
    for (final p in await pending()) {
      if (p.error != null) continue;
      // 보내는 사이 사용자가 지운 결제는 보내지 않는다
      final still = await _inLine(
        () async => (await _strict()).any((q) => q.clientId == p.clientId),
      );
      if (!still) continue;
      Object? error;
      dynamic r;
      try {
        r = await _send('POST', '/me/payments', body: p.body);
      } catch (e) {
        error = e;
      }
      if (error == null) {
        sent++;
        repriced += (r['repriced'] as int?) ?? 0;
        await _change(
          (items) => [
            for (final q in items)
              if (q.clientId != p.clientId) q,
          ],
        );
        continue;
      }
      // 끊겼으면 멈추고 다음에 한다. 토큰이 지워졌으면 다시 로그인한 뒤다
      if (disconnected(error) || _token == null) break;
      // 서버 오류는 그 결제 하나가 뒤 결제를 막지 않게 다음 것으로 넘어간다
      if (unreachable(error)) {
        failed.add(p.clientId);
        continue;
      }
      final reason = error is ApiError && error.status == 404
          ? '카드를 찾지 못했어요. 해지한 카드일 수 있어요'
          : error is ApiError && error.status == 409
          ? alreadySaved
          : '서버가 받지 않았어요';
      await _change(
        (items) => [
          for (final q in items)
            if (q.clientId != p.clientId) q else (q..error = reason),
        ],
      );
    }
    return (sent: sent, repriced: repriced, failed: failed);
  }

  /// 서버 오류가 난 결제의 횟수를 올린다. 세 번이면 거절로 본다. 서버가 정상으로 답한 회차에만 부른다.
  /// 서버 전체가 멈춘 동안 모든 결제가 거절로 바뀌어 손으로 다시 보내야 하는 일이 없게 한다
  Future<void> _strike(List<String> ids) => _change(
    (items) => [
      for (final q in items)
        if (!ids.contains(q.clientId))
          q
        else
          (q
            ..tries += 1
            ..error = q.tries >= 3 ? '서버 오류로 보내지 못했어요' : null),
    ],
  );

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
      await _forget();
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

  /// 모아 둔 결제를 먼저 보내고 홈을 받는다. 받은 홈은 폰에 둔다. 닿지 못하면 둔 홈이다. E24, E26
  Future<Home> home() async {
    // 다른 홈이 시작한 보내기를 함께 기다리면 알리지도 세지도 않는다. 알림이 두 번 뜨지 않게 한다
    final mine = _flushing == null;
    var r = (sent: 0, repriced: 0, failed: <String>[]);
    try {
      r = await flush();
    } catch (_) {
      // 폰 저장소가 실패해도 홈은 보인다
    }
    Map<String, dynamic>? j;
    Object? error;
    try {
      j = await _send('GET', '/me/home');
    } catch (e) {
      error = e;
    }
    if (mine && r.failed.isNotEmpty && (j != null || r.sent > 0)) {
      try {
        await _strike(r.failed);
      } catch (_) {}
    }
    final pending = await this.pending();
    final sent = mine ? r.sent : 0, repriced = mine ? r.repriced : 0;
    if (j != null) {
      await _write(
        _homeKey,
        jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'home': j}),
      );
      return Home(j, pending: pending, sent: sent, repriced: repriced);
    }
    final saved = unreachable(error!) ? await _read(_homeKey) : null;
    if (saved == null) throw error;
    final c = jsonDecode(saved);
    return Home(
      c['home'],
      cachedAt: DateTime.parse(c['at']).toLocal(),
      pending: pending,
      sent: sent,
      repriced: repriced,
    );
  }

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

  /// 고치고 혜택이 바뀐 다른 결제 수와 자식 업종 질문을 돌려준다. E54, E47
  Future<Saved> editPayment(String id, PaymentInput input) async =>
      Saved(await _send('PATCH', '/me/payments/$id', body: input.toJson()));

  /// 카드 사실, 옵션, 쓰기 시작한 날을 답하고 혜택이 바뀐 결제 수를 돌려준다. E56
  Future<int> answerCard(String id, Map<String, Object?> body) async =>
      (await _send('PUT', '/me/cards/$id/answers', body: body))['repriced']
          as int;

  /// 설정의 혜택 계산에 쓰는 답. 가진 카드들의 사람 사실이다
  Future<List<FactQuestion>> userFacts() async => [
    for (final q in await _send('GET', '/me/facts')) FactQuestion(q),
  ];

  Future<int> answerFacts(Map<String, Object> facts) async =>
      (await _send('PUT', '/me/facts', body: {'facts': facts}))['repriced']
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
  Future<Saved> savePayment(PaymentInput input) async =>
      Saved(await _send('POST', '/me/payments', body: _saveBody(input)));

  Map<String, Object?> _saveBody(PaymentInput input) => {
    ...input.toJson(),
    'recommendation_request_id': input.recommendationRequestId,
    'client_id': input.clientId,
  };
}
