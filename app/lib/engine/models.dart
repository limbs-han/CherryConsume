/// 계산 엔진의 입력과 출력. Python `backend/cherry_core/engine/models.py`를 옮겼다. 작업 006 설계 3절
library;

import '../catalog/models.dart';

// 입력

class OptionPick {
  const OptionPick({
    required this.option,
    required this.choice,
    required this.effectiveFrom,
  });
  final String option, choice;
  final DateTime effectiveFrom;
}

/// 바꾼 날이 있는 사실 답. 처음 답은 0001-01-01부터다. 값은 bool, int, String이다
class FactPick {
  const FactPick({
    required this.key,
    required this.value,
    required this.effectiveFrom,
  });
  final String key;
  final Object value;
  final DateTime effectiveFrom;
}

/// 0001-01-01. 처음 답은 원래 그랬던 것을 알려 준 것이라 모든 결제에 쓴다
final firstDay = day(1, 1, 1);

/// 보유 카드 한 장. 사실은 사람 사실과 카드 사실을 합쳐 넣는다
class UserCard {
  const UserCard({
    required this.id,
    required this.cardId,
    this.registeredOn,
    this.startedOn,
    this.options = const [],
    this.facts = const {},
    this.factPicks = const [],
    this.assumedPrevMonthSpend,
    this.lastPaymentMethod,
    this.removed = false,
  });
  final String id, cardId;
  final DateTime? registeredOn, startedOn;
  final List<OptionPick> options;
  final Map<String, Object> facts;

  /// 결제일에 맞는 가장 늦은 답을 facts보다 먼저 쓴다
  final List<FactPick> factPicks;
  final int? assumedPrevMonthSpend;
  final String? lastPaymentMethod;
  final bool removed;

  UserCard copyWith({
    List<OptionPick>? options,
    Map<String, Object>? facts,
    String? cardId,
  }) => UserCard(
    id: id,
    cardId: cardId ?? this.cardId,
    registeredOn: registeredOn,
    startedOn: startedOn,
    options: options ?? this.options,
    facts: facts ?? this.facts,
    factPicks: factPicks,
    assumedPrevMonthSpend: assumedPrevMonthSpend,
    lastPaymentMethod: lastPaymentMethod,
    removed: removed,
  );
}

/// 결제 한 건이 받은 혜택 하나. amount는 보상 단위(원이나 포인트), value는 원 가치다
class AppliedBenefit {
  const AppliedBenefit({
    required this.key,
    required this.amount,
    required this.value,
    required this.base,
  });
  final String key;
  final int amount, value, base;

  @override
  bool operator ==(Object other) =>
      other is AppliedBenefit &&
      other.key == key &&
      other.amount == amount &&
      other.value == value &&
      other.base == base;

  @override
  int get hashCode => Object.hash(key, amount, value, base);

  @override
  String toString() => 'AppliedBenefit($key, $amount, $value, $base)';
}

const _keep = Object();

// Python `catalog/models.py`의 Literal 값
const _channels = {'online', 'offline'};
const _regions = {'domestic', 'overseas'};
const _billings = {
  'normal',
  'autopay',
  'subscription',
  'postpaid_transit',
  'app_prepay',
  'in_app',
};

class Payment {
  Payment({
    required this.id,
    required this.userCardId,
    required this.amount,
    required DateTime paidAt,
    this.merchant,
    this.category,
    this.channel = 'offline',
    this.region = 'domestic',
    this.installmentMonths = 1,
    this.interestFree = false,
    this.paymentMethod,
    this.billing,
    this.cancelledAmount = 0,
    DateTime? cancelledAt,
    this.timeKnown = true,
    this.benefits,
  }) : paidAt = paidAt.toUtc(),
       cancelledAt = cancelledAt?.toUtc() {
    if (amount <= 0) throw ArgumentError('결제 금액은 0보다 크다');
    if (cancelledAmount < 0) throw ArgumentError('취소 금액은 0 이상이다');
    if (installmentMonths < 1) throw ArgumentError('할부 개월은 1 이상이다');
    if (!_channels.contains(channel)) {
      throw ArgumentError('모르는 channel $channel');
    }
    if (!_regions.contains(region)) throw ArgumentError('모르는 region $region');
    if (billing != null && !_billings.contains(billing)) {
      throw ArgumentError('모르는 billing $billing');
    }
    if (cancelledAmount > amount) {
      throw ArgumentError('취소 금액이 결제 금액보다 크다');
    }
    if (cancelledAmount > 0 && this.cancelledAt == null) {
      throw ArgumentError('취소 금액이 있으면 취소 시각도 있어야 한다. E5');
    }
  }

  final String id, userCardId;
  final int amount;

  /// UTC로 둔다. 한국 시간은 엔진이 9시간을 더해 센다
  final DateTime paidAt;
  final String? merchant, category;
  final String channel, region;
  final int installmentMonths;
  final bool interestFree;
  final String? paymentMethod, billing;
  final int cancelledAmount;
  final DateTime? cancelledAt;

  /// 시각을 아는가. 엑셀에 날짜만 있으면 그날 12시로 두고 거짓이다. 시각 조건이 모름이 된다. E57
  final bool timeKnown;
  final List<AppliedBenefit>? benefits;

  /// 업종, 결제수단, 취소 시각, 혜택은 null을 넘기면 비운다. 넘기지 않은 칸은 그대로다
  Payment copyWith({
    String? userCardId,
    Object? category = _keep,
    Object? paymentMethod = _keep,
    int? cancelledAmount,
    Object? cancelledAt = _keep,
    bool? timeKnown,
    Object? benefits = _keep,
  }) => Payment(
    id: id,
    userCardId: userCardId ?? this.userCardId,
    amount: amount,
    paidAt: paidAt,
    merchant: merchant,
    category: identical(category, _keep) ? this.category : category as String?,
    channel: channel,
    region: region,
    installmentMonths: installmentMonths,
    interestFree: interestFree,
    paymentMethod: identical(paymentMethod, _keep)
        ? this.paymentMethod
        : paymentMethod as String?,
    billing: billing,
    cancelledAmount: cancelledAmount ?? this.cancelledAmount,
    cancelledAt: identical(cancelledAt, _keep)
        ? this.cancelledAt
        : cancelledAt as DateTime?,
    timeKnown: timeKnown ?? this.timeKnown,
    benefits: identical(benefits, _keep)
        ? this.benefits
        : benefits as List<AppliedBenefit>?,
  );
}

/// 결제 시각, 그다음 id 순서. 같은 시각이면 먼저 넣은 결제가 앞이다
int byTime(Payment a, Payment b) {
  final c = a.paidAt.compareTo(b.paidAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// 추천 질문. 금액이 없으면 1만원으로 계산한다. E11
class Query {
  const Query({
    this.merchant,
    this.category,
    this.amount,
    this.channel,
    this.region,
    this.paymentMethod,
  });
  final String? merchant, category;
  final int? amount;
  final String? channel, region, paymentMethod;
}

// 출력

class Warn {
  const Warn(this.code, {this.benefit, this.data = const {}});
  final String code;
  final String? benefit;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'code': code,
    'benefit': benefit,
    'data': data,
  };

  @override
  String toString() => 'Warn($code, $benefit, $data)';
}

/// 결제 한 건이 어느 달 실적에 얼마를 넣는지. 취소는 음수다
class SpendPart {
  const SpendPart(this.month, this.amount);
  final DateTime month;
  final int amount;

  @override
  bool operator ==(Object other) =>
      other is SpendPart && other.month == month && other.amount == amount;

  @override
  int get hashCode => Object.hash(month, amount);

  @override
  String toString() => 'SpendPart(${dayText(month)}, $amount)';
}

class ConditionalBenefit {
  const ConditionalBenefit({
    required this.userCardId,
    required this.benefit,
    required this.needs,
    required this.extra,
  });
  final String userCardId, benefit;
  final Map<String, Object?> needs;
  final int extra;
}

class PaymentResult {
  const PaymentResult({
    required this.paymentId,
    this.benefits = const [],
    this.spend = const [],
    this.conditional = const [],
    this.warnings = const [],
  });
  final String paymentId;
  final List<AppliedBenefit> benefits;
  final List<SpendPart> spend;
  final List<ConditionalBenefit> conditional;
  final List<Warn> warnings;

  int get value => benefits.fold(0, (s, b) => s + b.value);
}

class SpendStatus {
  const SpendStatus({
    required this.userCardId,
    required this.month,
    required this.counted,
    required this.tier,
    required this.tierSource,
    required this.prevMonthCounted,
    required this.toKeep,
    required this.nextTier,
    required this.toNext,
    this.warnings = const [],
  });
  final String userCardId;
  final DateTime month;
  final int counted;
  final int? tier;

  /// prev_month, assumed, new_card, none, unsupported
  final String tierSource;
  final int? prevMonthCounted, toKeep, nextTier, toNext;
  final List<Warn> warnings;

  /// 서버가 주던 모양. Python `model_dump(mode="json", exclude={"user_card_id", "month"})`
  Map<String, Object?> toJson() => {
    'counted': counted,
    'tier': tier,
    'tier_source': tierSource,
    'prev_month_counted': prevMonthCounted,
    'to_keep': toKeep,
    'next_tier': nextTier,
    'to_next': toNext,
    'warnings': [for (final w in warnings) w.toJson()],
  };
}

class LimitUse {
  const LimitUse({
    required this.key,
    required this.benefit,
    required this.per,
    required this.usedAmount,
    required this.usedCount,
    required this.usedBase,
    required this.capAmount,
    required this.capCount,
    required this.capBase,
  });
  final String key;
  final String? benefit;
  final String per;
  final int usedAmount, usedCount, usedBase;
  final int? capAmount, capCount, capBase;
}

class LockedBenefit {
  const LockedBenefit({
    required this.userCardId,
    required this.benefit,
    required this.requiredTier,
    required this.remainingThisMonth,
    required this.valueIfUnlocked,
  });
  final String userCardId, benefit;
  final int requiredTier, remainingThisMonth, valueIfUnlocked;
}

class Recommendation {
  const Recommendation({
    required this.userCardId,
    required this.cardId,
    required this.value,
    this.benefits = const [],
    required this.counted,
    required this.toKeep,
    required this.toNext,
    this.locked = const [],
    this.conditional = const [],
    this.warnings = const [],
  });
  final String userCardId, cardId;
  final int value;
  final List<AppliedBenefit> benefits;
  final bool counted;
  final int? toKeep, toNext;
  final List<LockedBenefit> locked;
  final List<ConditionalBenefit> conditional;
  final List<Warn> warnings;
}
