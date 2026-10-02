// 엔진 시험 도우미. Python `backend/tests/engine/conftest.py`를 옮겼다. 작업 006 계획 단계 2
//
// card(...)로 개정 하나짜리 카드를 만들고 engine(...)으로 엔진을 얻는다. 시험 카드사에는 기본값이 없어 합칠 것이
// 없다. 개정을 앱이 담는 JSON 모양으로 바로 만들고 Dart 모델이 기본값을 채운다
import 'dart:convert';
import 'dart:io';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/engine/models.dart';

/// 커밋된 카탈로그. 시험마다 다시 읽지 않는다
final Json realJson =
    jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
final Catalog realCatalog = Catalog.fromJson(realJson);

/// 한국 시간 "2026-09-19T14:20"을 UTC 시각으로. Python 시험의 at()이다
DateTime at(String text) {
  final [date, time] = text.split('T');
  final [y, m, d] = date.split('-').map(int.parse).toList();
  final hm = time.split(':').map(int.parse).toList();
  return DateTime.utc(
    y,
    m,
    d,
    hm[0],
    hm[1],
    hm.length > 2 ? hm[2] : 0,
  ).subtract(const Duration(hours: 9));
}

const common = {
  'categories': [
    {'code': 'cafe', 'name': '카페'},
    {'code': 'convenience', 'name': '편의점'},
    {
      'code': 'restaurant',
      'name': '음식점',
      'children': [
        {'code': 'general', 'name': '일반음식점'},
        {'code': 'fastfood', 'name': '패스트푸드'},
      ],
    },
    {
      'code': 'transit',
      'name': '대중교통',
      'children': [
        {'code': 'subway', 'name': '지하철'},
        {'code': 'bus_express', 'name': '고속버스'},
      ],
    },
    {
      'code': 'telecom',
      'name': '통신요금',
      'children': [
        {'code': 'mobile', 'name': '이동통신'},
        {'code': 'internet_tv', 'name': '인터넷·TV'},
      ],
    },
    {'code': 'tax', 'name': '세금'},
    {'code': 'fuel', 'name': '주유'},
    {'code': 'delivery_app', 'name': '배달앱'},
    {'code': 'other', 'name': '기타'},
  ],
  'merchants': [
    {
      'key': 'starbucks',
      'name': '스타벅스',
      'category': 'cafe',
      'aliases': ['스타벅스'],
    },
    {
      'key': 'ediya',
      'name': '이디야',
      'category': 'cafe',
      'aliases': ['이디야'],
    },
    {
      'key': 'gs25',
      'name': 'GS25',
      'category': 'convenience',
      'aliases': ['GS25'],
    },
    {
      'key': 'kt',
      'name': 'KT',
      'category': 'telecom',
      'aliases': ['KT'],
      'billing': 'autopay',
    },
    {
      'key': 'baemin',
      'name': '배달의민족',
      'category': 'delivery_app',
      'aliases': ['배달의민족'],
    },
    {
      'key': 'sk_energy',
      'name': 'SK에너지',
      'category': 'fuel',
      'aliases': ['SK에너지'],
    },
  ],
  'payment_methods': [
    {'key': 'physical_card', 'name': '실물카드'},
    {'key': 'naver_pay', 'name': '네이버페이'},
    {'key': 'kakao_pay', 'name': '카카오페이'},
  ],
  'point_programs': [
    {'key': 'test_point', 'name': '테스트포인트', 'won_per_point': 1},
  ],
  'reference': [
    {
      'key': 'fuel_price_gasoline',
      'value': 1700,
      'unit': '원/L',
      'as_of': '2026-09-28',
      'source': '오피넷',
    },
  ],
  'issuers': [
    {'id': 'test', 'name': '테스트카드'},
  ],
};

const spendDefault = {
  'basis': 'prev_calendar_month',
  'exclude_categories': ['tax'],
  'installment': 'full_at_purchase',
  'cancellation': 'cancel_month',
};

/// 개정 하나짜리 카드. rules에는 limits, stacks, ranked, options, facts, new_card, benefit_exclusions 등을 준다
Json card(
  List<Json> benefits, {
  String id = 'test-card',
  List<int> tiers = const [0, 300000, 600000],
  Json? spend,
  String start = '2026-01-01',
  bool estimated = false,
  Json rules = const {},
}) => {
  'id': id,
  'issuer': 'test',
  'name': id,
  'kind': 'credit',
  'product_codes': ['T1'],
  'status': 'on_sale',
  'checked_at': '2026-09-28',
  'revisions': [
    {
      'effective_from': start,
      'effective_from_estimated': estimated,
      'source': 'page',
      'sha256': '',
      'rules': {
        'tiers': tiers,
        'spend': {...spendDefault, ...?spend},
        ...rules,
        'benefits': [
          for (final b in benefits) {'title': b['key'], ...b},
        ],
      },
    },
  ],
};

/// 그 카드들이 든 엔진. 공휴일은 커밋된 카탈로그의 목록이다
Engine engine(List<Json> cards) => Engine(
  Catalog.fromJson({
    'schema': catalogSchema,
    'holidays': realJson['holidays'],
    ...common,
    'cards': cards,
  }),
);

var _ids = 0;

const _unset = Object();

Payment pay(
  int amount,
  String when, {
  String? merchant,
  String? category,
  String channel = 'offline',
  String region = 'domestic',
  int installmentMonths = 1,
  bool interestFree = false,
  String? paymentMethod,
  String? billing,
  int cancelledAmount = 0,
  DateTime? cancelledAt,
  bool timeKnown = true,
  List<AppliedBenefit>? benefits,
  String? id,
  String userCardId = 'u1',
}) => Payment(
  id: id ?? 'p${(++_ids).toString().padLeft(4, '0')}',
  userCardId: userCardId,
  amount: amount,
  paidAt: at(when),
  merchant: merchant,
  category: category,
  channel: channel,
  region: region,
  installmentMonths: installmentMonths,
  interestFree: interestFree,
  paymentMethod: paymentMethod,
  billing: billing,
  cancelledAmount: cancelledAmount,
  cancelledAt: cancelledAt,
  timeKnown: timeKnown,
  benefits: benefits,
);

UserCard holder({
  String id = 'u1',
  String cardId = 'test-card',
  Object? registeredOn = _unset,
  DateTime? startedOn,
  List<OptionPick> options = const [],
  Map<String, Object> facts = const {},
  List<FactPick> factPicks = const [],
  int? assumedPrevMonthSpend,
  String? lastPaymentMethod,
  bool removed = false,
}) => UserCard(
  id: id,
  cardId: cardId,
  registeredOn: identical(registeredOn, _unset)
      ? day(2026, 1, 1)
      : registeredOn as DateTime?,
  startedOn: startedOn,
  options: options,
  facts: facts,
  factPicks: factPicks,
  assumedPrevMonthSpend: assumedPrevMonthSpend,
  lastPaymentMethod: lastPaymentMethod,
  removed: removed,
);

/// 결제마다 {혜택 key: 원 가치}
List<Map<String, int>> values(List<PaymentResult> results) => [
  for (final r in results) {for (final b in r.benefits) b.key: b.value},
];

List<String> codes(PaymentResult result) => [
  for (final w in result.warnings) w.code,
];

/// 지난달 실적을 만드는 결제 한 건. 업종은 기타라 혜택이 없다
List<Payment> prevMonth(int amount, [String month = '2026-08']) => [
  pay(amount, '$month-15T12:00', category: 'other'),
];

/// 저장된 결제에 계산한 혜택을 넣는다. Python의 model_copy(update={"benefits": ...})
List<Payment> saved(List<Payment> payments, List<PaymentResult> results) {
  final done = {for (final r in results) r.paymentId: r.benefits};
  return [
    for (final p in payments)
      p.copyWith(benefits: done.containsKey(p.id) ? done[p.id] : p.benefits),
  ];
}
