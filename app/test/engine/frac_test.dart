// 분수. Python의 fractions.Fraction을 대신한다. 작업 006 계획 단계 2의 1
import 'package:cherry_consume/engine/context.dart';
import 'package:cherry_consume/engine/frac.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('카탈로그의 비율을 글자로 읽어 정확한 분수로 만든다', () {
    expect(Frac.of(0.1), Frac(1, 10));
    expect(Frac.of(1.3), Frac(13, 10));
    expect(Frac.of(10.0), Frac(10));
    expect(Frac.parse('1e-07'), Frac(1, 10000000));
    expect(Frac(6, -4), Frac(-3, 2));
    expect((Frac(6, -4).n, Frac(6, -4).d), (-3, 2));
  });

  test('내림과 올림은 음수에서도 Python과 같다', () {
    expect(
      [
        Frac(7, 2).floor(),
        Frac(-7, 2).floor(),
        Frac(7, 2).ceil(),
        Frac(-7, 2).ceil(),
      ],
      [3, -4, 4, -3],
    );
    expect(floorDiv(-7, 2), -4);
  });

  test('반올림과 구간표', () {
    expect(roundMoney(Frac(2405, 10), 'round'), 241);
    expect(roundMoney(Frac(12345), 'floor100'), 12300);
    expect(atTier({300000: 1000, 600000: 2000}, 599999), 1000);
    expect(atTier({300000: 1000}, 0), isNull);
    expect(atTier(5, 0), 5);
  });
}
