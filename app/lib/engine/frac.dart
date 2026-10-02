/// 정확한 분수. Python 엔진이 쓰는 `fractions.Fraction`을 대신한다. 부동소수점으로 돈을 계산하지 않기 위해서다.
/// 작업 006 설계 3절
library;

int _gcd(int a, int b) {
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a;
}

/// b가 양수일 때 a / b를 내림한다. Dart의 `~/`는 0 쪽으로 자른다
int floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && a < 0) ? q - 1 : q;
}

/// 분자와 분모를 늘 약분해 둔다. 분모는 양수다
class Frac implements Comparable<Frac> {
  factory Frac(int n, [int d = 1]) {
    if (d == 0) throw ArgumentError('분모가 0이다');
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final g = _gcd(n.abs(), d);
    return Frac._(n ~/ g, d ~/ g);
  }

  const Frac._(this.n, this.d);

  final int n, d;

  /// int, Frac, num을 분수로. num은 글자로 바꿔 읽는다. Python의 Fraction(str(x))와 같다
  static Frac of(Object x) => switch (x) {
    Frac f => f,
    int i => Frac(i),
    num v => parse(v.toString()),
    _ => throw ArgumentError('분수로 바꿀 수 없다: $x'),
  };

  /// "13", "-1.25", "10.0", "1e-07"
  static Frac parse(String s) {
    var t = s.trim().toLowerCase();
    var exp = 0;
    final e = t.indexOf('e');
    if (e >= 0) {
      exp = int.parse(t.substring(e + 1));
      t = t.substring(0, e);
    }
    final negative = t.startsWith('-');
    if (negative || t.startsWith('+')) t = t.substring(1);
    final dot = t.indexOf('.');
    final digits = dot < 0 ? t : t.substring(0, dot) + t.substring(dot + 1);
    final scale = dot < 0 ? 0 : t.length - dot - 1;
    var n = int.parse(digits.isEmpty ? '0' : digits);
    var d = 1;
    final shift = exp - scale;
    for (var i = 0; i < shift.abs(); i++) {
      shift > 0 ? n *= 10 : d *= 10;
    }
    return Frac(negative ? -n : n, d);
  }

  Frac operator +(Object o) {
    final b = of(o);
    return Frac(n * b.d + b.n * d, d * b.d);
  }

  Frac operator -(Object o) {
    final b = of(o);
    return Frac(n * b.d - b.n * d, d * b.d);
  }

  Frac operator *(Object o) {
    final b = of(o);
    return Frac(n * b.n, d * b.d);
  }

  Frac operator /(Object o) {
    final b = of(o);
    return Frac(n * b.d, d * b.n);
  }

  Frac operator -() => Frac._(-n, d);

  bool operator <(Object o) => compareTo(of(o)) < 0;
  bool operator <=(Object o) => compareTo(of(o)) <= 0;
  bool operator >(Object o) => compareTo(of(o)) > 0;
  bool operator >=(Object o) => compareTo(of(o)) >= 0;

  @override
  int compareTo(Frac other) => (n * other.d).compareTo(other.n * d);

  /// 내림. Python의 math.floor
  int floor() => floorDiv(n, d);

  /// 올림. Python의 math.ceil
  int ceil() => -floorDiv(-n, d);

  @override
  bool operator ==(Object other) =>
      other is Frac && other.n == n && other.d == d;

  @override
  int get hashCode => Object.hash(n, d);

  @override
  String toString() => d == 1 ? '$n' : '$n/$d';
}

Frac maxFrac(Frac a, Frac b) => a >= b ? a : b;
