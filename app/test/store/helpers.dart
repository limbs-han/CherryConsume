// 저장소 시험 도우미. Python `backend/tests/api/conftest.py`를 옮겼다. 작업 006 설계 4절 "시험"
//
// 메모리 SQLite와 커밋된 카탈로그로 돈다. 시계는 서버 시험처럼 2026-09-15 21:00 한국 시간에서 시작하고 시험이
// 옮길 수 있다. 사용자가 한 명이라 로그인은 없다
import 'dart:convert';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/payments.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart';

/// 2026-09-15 21:00 한국 시간
final start = DateTime.utc(2026, 9, 15, 12);

class Clock {
  DateTime now = start;
  DateTime call() => now;
}

/// 빈 DB의 저장소. edit로 카탈로그 JSON을 고쳐 넣을 수 있다
({Store s, Clock clock}) fresh([void Function(Json)? edit]) {
  final clock = Clock();
  var catalog = realCatalog;
  if (edit != null) {
    final j = jsonDecode(jsonEncode(realJson)) as Json;
    edit(j);
    catalog = Catalog.fromJson(j);
  }
  return (s: Store(openDb(), catalog, clock: clock.call), clock: clock);
}

const mrlife = {
  'card_id': 'shinhan-mrlife',
  'assumed_prev_month_spend': 410000,
};

/// 카드를 등록하고 보유 카드 id를 돌려준다. 서버 시험의 setup
List<String> setup(
  Store s, [
  List<Map<String, Object?>> cards = const [mrlife],
]) => [
  for (final c in cards)
    addCard(
      s,
      c['card_id'] as String,
      assumedPrevMonthSpend: c['assumed_prev_month_spend'] as int?,
      startedOn: c['started_on'] == null
          ? null
          : parseDay(c['started_on'] as String),
    )['id'],
];

/// 결제 저장. 서버 시험의 pay
Json pay(
  Store s,
  String card,
  int amount,
  String? merchant, {
  String at = '2026-09-15T21:00:00+09:00',
  Json more = const {},
}) => save(s, {
  'user_card_id': card,
  'amount': amount,
  'merchant_name': merchant,
  'paid_at': at,
  ...more,
});

/// 서버가 답하던 상태 번호의 ApiError
Matcher status(int code) =>
    isA<ApiError>().having((e) => e.status, 'status', code);
