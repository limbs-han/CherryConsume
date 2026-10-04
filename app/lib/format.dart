/// 금액 쓰기. 작업 005 설계 6절. 금액은 원 단위 정수다.
library;

/// 7669 → "7,669"
String comma(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// 7669 → "7,669원"
String won(int n) => '${comma(n)}원';

/// 118000 → "11.8만", 300000 → "30만". 1만 원 아래는 원으로 쓴다.
/// 천 원 아래는 올린다. "더 쓰면" 금액이 모자라게 보이지 않게 하려는 것이다.
String man(int n) {
  if (n < 10000) return won(n);
  final tenths = (n + 999) ~/ 1000;
  final whole = comma(tenths ~/ 10);
  return tenths % 10 == 0 ? '$whole만' : '$whole.${tenths % 10}만';
}
