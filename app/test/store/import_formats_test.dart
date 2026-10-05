// 카드사 파일 형식 표. 작업 015 설계 1절
import 'package:cherry_consume/store/formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('형식이 읽는 열과 본 값을 적은 열은 모두 알아보는 열에 든다', () {
    // 형식이 맞으면 읽을 열이 모두 이름 그대로 있다. 열 이름이 바뀐 파일은 모르는 형식으로 읽힌다. 설계 2절 2
    for (final f in formats) {
      expect(
        f.marks,
        containsAll({...f.columns.values, ...f.seen.keys}),
        reason: f.id,
      );
      expect([for (final m in f.marks) headKey(m)], f.marks, reason: f.id);
    }
    expect({for (final f in formats) f.id}.length, formats.length);
  });

  test('괄호가 붙은 비슷한 열 이름을 읽을 열로 잘못 보지 않는다', () {
    // 작업 015 단계 검토 낮음 3. 승인금액(USD)가 승인금액보다 앞에 있어도 승인금액을 읽는다
    final f = formats.firstWhere((f) => f.id == 'ibk-print');
    final head = ['승인금액(USD)', for (final m in f.marks) m];
    final (_, start, cols) = detect([head])!;
    expect((start, cols['amount']), (0, head.indexOf('승인금액')));
    // 승인금액 없이 승인금액(USD)만 있으면 기업은행 출력용이 아니다
    expect(
      detect([
        [for (final m in f.marks) m == '승인금액' ? '승인금액(USD)' : m],
      ]),
      isNull,
    );
  });
}
