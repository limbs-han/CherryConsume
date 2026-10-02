// 엔진 입력 모델. Python `backend/cherry_core/engine/models.py`의 Pydantic 검사를 옮겼는지 본다. 2026-10-02 위험 검토
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('결제는 Python 모델이 막던 값을 막는다', () {
    final cancel = at('2026-09-02T10:00');
    expect(
      () => pay(
        10000,
        '2026-09-01T10:00',
        cancelledAmount: -5000,
        cancelledAt: cancel,
      ),
      throwsArgumentError,
    );
    expect(
      () => pay(10000, '2026-09-01T10:00', installmentMonths: 0),
      throwsArgumentError,
    );
    expect(
      () => pay(10000, '2026-09-01T10:00', channel: 'store'),
      throwsArgumentError,
    );
    expect(
      () => pay(10000, '2026-09-01T10:00', region: 'mars'),
      throwsArgumentError,
    );
    expect(
      () => pay(10000, '2026-09-01T10:00', billing: 'cash'),
      throwsArgumentError,
    );
    expect(
      pay(
        10000,
        '2026-09-01T10:00',
        billing: 'autopay',
        region: 'overseas',
      ).billing,
      'autopay',
    );
  });

  test('copyWith에 null을 넘기면 업종과 결제수단도 비운다', () {
    final p = pay(
      10000,
      '2026-09-01T10:00',
      category: 'cafe',
      paymentMethod: 'naver_pay',
    );
    final cleared = p.copyWith(category: null, paymentMethod: null);
    expect((cleared.category, cleared.paymentMethod), (null, null));
    final kept = p.copyWith();
    expect((kept.category, kept.paymentMethod), ('cafe', 'naver_pay'));
  });
}
