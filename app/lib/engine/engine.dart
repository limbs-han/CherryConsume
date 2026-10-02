/// 계산 엔진. 앱이 켜질 때 카탈로그로 한 번 만들고 함수를 부른다. Python `backend/cherry_core/engine/__init__.py`를
/// 옮겼다. 카탈로그 규칙 검사는 Python이 JSON을 만들 때 했다. 작업 006 설계 3절
library;

import '../catalog/models.dart';
import 'context.dart';
import 'models.dart';
import 'price.dart' as price_;
import 'recommend.dart' as recommend_;

class Engine {
  Engine(Catalog catalog) : ctx = Ctx(catalog);

  final Ctx ctx;

  PaymentResult pricePayment(
    UserCard card,
    List<Payment> history,
    Payment payment,
  ) => price_.pricePayment(ctx, _card(card), history, payment);

  List<PaymentResult> priceMonth(
    UserCard card,
    List<Payment> payments, {
    DateTime? month,
    bool isFinal = false,
  }) => price_.priceMonth(
    ctx,
    _card(card),
    payments,
    month: month == null ? null : _day(month),
    isFinal: isFinal,
  );

  SpendStatus spendStatus(
    UserCard card,
    List<Payment> payments,
    DateTime month,
  ) => price_.spendStatus(ctx, _card(card), payments, _day(month));

  List<LimitUse> limitStatus(
    UserCard card,
    List<Payment> payments,
    DateTime now,
  ) => price_.limitStatus(ctx, _card(card), payments, now);

  List<List<Recommendation>> recommend(
    List<UserCard> cards,
    Map<String, List<Payment>> payments,
    List<Query> queries,
    DateTime now,
  ) => recommend_.recommend(
    ctx,
    [for (final c in cards) _card(c)],
    payments,
    queries,
    now,
  );
}

/// 날짜 인자를 UTC 자정으로 맞춘다. 엔진은 날짜를 `day()`로 만든 UTC 자정끼리 비교하는데, Dart DateTime은 UTC 여부까지
/// 같아야 같은 값이다. 폰 시간 `DateTime(2026, 9, 1)`을 넘기면 그 달 실적을 못 찾는다. Python은 date 타입이라 이런 일이 없었다
DateTime _day(DateTime d) => day(d.year, d.month, d.day);

UserCard _card(UserCard c) {
  DateTime? opt(DateTime? d) => d == null ? null : _day(d);
  return UserCard(
    id: c.id,
    cardId: c.cardId,
    registeredOn: opt(c.registeredOn),
    startedOn: opt(c.startedOn),
    options: [
      for (final o in c.options)
        OptionPick(
          option: o.option,
          choice: o.choice,
          effectiveFrom: _day(o.effectiveFrom),
        ),
    ],
    facts: c.facts,
    factPicks: [
      for (final f in c.factPicks)
        FactPick(
          key: f.key,
          value: f.value,
          effectiveFrom: _day(f.effectiveFrom),
        ),
    ],
    assumedPrevMonthSpend: c.assumedPrevMonthSpend,
    lastPaymentMethod: c.lastPaymentMethod,
    removed: c.removed,
  );
}
