// 카드 칸 값마다 보유 카드를 고른다. 값은 모두 지어냈다. 작업 017 설계 3절, E60
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show ApiError;
import 'package:cherry_consume/catalog/models.dart' show Json;
import 'package:cherry_consume/store/backup.dart' show exportAll, importAll;
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show addCard, removeCard;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';
import 'import_formats_test.dart' show rowsOf, sheet, shinhan, shinhanHead;

/// 카드 칸 값 A 두 줄과 B 한 줄의 신한카드 이용내역
Uint8List twoCards() => sheet([
  shinhanHead,
  shinhan('2026.09.05 10:00', '가게 하나', 5000.0, '10000061', holder: '본인A*'),
  shinhan('2026.09.06 10:00', '가게 둘', 7000.0, '10000062', holder: '본인A*'),
  shinhan('2026.09.07 10:00', '가게 셋', 3000.0, '10000063', holder: '가족B*'),
]);

({Store s, String ibk, String mr}) twoOwned() {
  final (:s, clock: _) = fresh();
  final [mr] = setup(s);
  final ibk = addCard(s, 'ibk-narasarang')['id'] as String;
  return (s: s, ibk: ibk, mr: mr);
}

List<Json> codesOf(Json p) => (p['card_codes'] as List).cast<Json>();

/// 넣는 줄의 (가게 이름, 보유 카드)
Set<(Object?, Object?)> placed(Json p) => {
  for (final r in rowsOf(p))
    if (r['status'] == 'new') (r['merchant_name'], r['user_card_id']),
};

Json saveWith(Store s, Json p, Map<String, String>? pairs) => imports.save(s, {
  'rows': [
    for (final r in rowsOf(p))
      if (r.containsKey('paid_at')) r,
  ],
  'card_codes': pairs == null ? null : {'format': p['format'], 'pairs': pairs},
});

void main() {
  test('카드 칸 값이 둘이면 값마다 묻고 고르기 전에는 넣지 않는다', () {
    final (:s, :ibk, mr: _) = twoOwned();
    final p = imports.preview(s, twoCards(), userCardId: ibk);
    expect(codesOf(p), [
      {'code': '본인A*', 'count': 2, 'user_card_id': null},
      {'code': '가족B*', 'count': 1, 'user_card_id': null},
    ]);
    expect(
      {for (final r in rowsOf(p)) (r['status'], r['reason'])},
      {('unpaired', '어느 카드인지 골라 주세요')},
    );
  });

  test('고른 짝대로 넣고 고르지 않은 값의 줄은 넣지 않는다', () {
    final (:s, :ibk, :mr) = twoOwned();
    final both = imports.preview(
      s,
      twoCards(),
      userCardId: ibk,
      codes: {'본인A*': ibk, '가족B*': mr},
    );
    expect(placed(both), {('가게 하나', ibk), ('가게 둘', ibk), ('가게 셋', mr)});
    expect(codesOf(both).map((c) => c['user_card_id']), [ibk, mr]);

    final one = imports.preview(
      s,
      twoCards(),
      userCardId: ibk,
      codes: {'본인A*': ibk},
    );
    expect(placed(one), {('가게 하나', ibk), ('가게 둘', ibk)});
    expect(
      [
        for (final r in rowsOf(one))
          if (r['status'] == 'unpaired') r['reason'],
      ],
      ['어느 카드인지 골라 주세요'],
    );
  });

  test('저장할 때 고른 짝을 기억해 다음 가져오기에 쓰고 기록 내보내기에는 넣지 않는다', () {
    final (:s, :ibk, :mr) = twoOwned();
    final pairs = {'본인A*': ibk, '가족B*': mr};
    final p = imports.preview(s, twoCards(), userCardId: ibk, codes: pairs);
    saveWith(s, p, pairs);
    expect(
      s.db
          .select(
            'select format, code, user_card_id from import_card_codes order by code',
          )
          .map((r) => [r['format'], r['code'], r['user_card_id']]),
      [
        ['shinhan-usage', '가족B*', mr],
        ['shinhan-usage', '본인A*', ibk],
      ],
    );
    // 같은 파일을 다시 넣으면 짝은 기억한 대로이고 결제는 겹침이다
    final again = imports.preview(s, twoCards(), userCardId: ibk);
    expect(codesOf(again).map((c) => c['user_card_id']), [ibk, mr]);
    expect({for (final r in rowsOf(again)) r['status']}, {'duplicate'});
    // 카드번호 일부와 카드의 짝은 폰 안에만 둔다
    final out = exportAll(s);
    expect(out, isNot(contains('import_card_codes')));
    expect(out, isNot(contains('본인A*')));
  });

  test('카드 칸 값이 하나뿐이면 묻지 않고 위에서 고른 카드다. 그 짝은 기억하지 않는다', () {
    final (:s, :ibk, mr: _) = twoOwned();
    final p = imports.preview(
      s,
      sheet([
        shinhanHead,
        shinhan('2026.09.05 10:00', '가게 하나', 5000.0, '10000064'),
        shinhan('2026.09.06 10:00', '가게 둘', 7000.0, '10000065'),
      ]),
      userCardId: ibk,
    );
    expect(codesOf(p), [
      {'code': '본인000*', 'count': 2, 'user_card_id': ibk},
    ]);
    expect(placed(p), {('가게 하나', ibk), ('가게 둘', ibk)});
    saveWith(s, p, null);
    expect(s.db.select('select 1 from import_card_codes'), isEmpty);
  });

  test('기억한 짝의 카드를 지우면 그 짝을 쓰지 않는다', () {
    final (:s, :ibk, :mr) = twoOwned();
    final pairs = {'본인A*': ibk, '가족B*': mr};
    saveWith(
      s,
      imports.preview(s, twoCards(), userCardId: ibk, codes: pairs),
      pairs,
    );
    removeCard(s, mr);
    final p = imports.preview(s, twoCards(), userCardId: ibk);
    expect(codesOf(p).map((c) => c['user_card_id']), [ibk, null]);
  });

  test('보유 카드가 아닌 짝은 미리보기도 저장도 받지 않는다', () {
    final (:s, :ibk, mr: _) = twoOwned();
    expect(
      () => imports.preview(
        s,
        twoCards(),
        userCardId: ibk,
        codes: {'본인A*': 'nope'},
      ),
      throwsA(isA<ApiError>()),
    );
    final p = imports.preview(
      s,
      twoCards(),
      userCardId: ibk,
      codes: {'본인A*': ibk},
    );
    expect(() => saveWith(s, p, {'본인A*': 'nope'}), throwsA(isA<ApiError>()));
    expect(
      () => imports.save(s, {
        'rows': [
          for (final r in rowsOf(p))
            if (r.containsKey('paid_at')) r,
        ],
        'card_codes': {
          'format': 'nope',
          'pairs': {'본인A*': ibk},
        },
      }),
      throwsA(isA<ApiError>()),
    );
  });

  test('값이 하나뿐이면 위에서 고른 카드가 예전에 기억한 짝보다 먼저다', () {
    // 단계 2 위험 검토 높음 1
    final (:s, :ibk, :mr) = twoOwned();
    final pairs = {'본인A*': mr, '가족B*': ibk};
    saveWith(s, imports.preview(s, twoCards(), codes: pairs), pairs);
    final one = sheet([
      shinhanHead,
      shinhan('2026.09.15 10:00', '가게 넷', 4000.0, '10000071', holder: '본인A*'),
    ]);
    expect(placed(imports.preview(s, one, userCardId: ibk)), {('가게 넷', ibk)});
    // 위에서 고르지 않으면 기억한 짝이다
    expect(placed(imports.preview(s, one)), {('가게 넷', mr)});
  });

  test('카드 칸이 빈 줄은 값으로 세지 않는다', () {
    // 단계 2 위험 검토 중간 2
    final (:s, :ibk, :mr) = twoOwned();
    final single = sheet([
      shinhanHead,
      shinhan('2026.09.05 10:00', '가게 하나', 5000.0, '10000081', holder: '본인A*'),
      shinhan('2026.09.06 10:00', '빈 칸 가게', 6000.0, '10000082', holder: ''),
    ]);
    final p = imports.preview(s, single, userCardId: ibk);
    expect(codesOf(p), [
      {'code': '본인A*', 'count': 1, 'user_card_id': ibk},
    ]);
    expect(placed(p), {('가게 하나', ibk), ('빈 칸 가게', ibk)});
    // 값이 둘이면 빈 칸 줄은 어느 카드인지 몰라 넣지 않는다
    final two = imports.preview(
      s,
      sheet([
        shinhanHead,
        shinhan(
          '2026.09.05 10:00',
          '가게 하나',
          5000.0,
          '10000083',
          holder: '본인A*',
        ),
        shinhan('2026.09.06 10:00', '가게 둘', 7000.0, '10000084', holder: '가족B*'),
        shinhan('2026.09.07 10:00', '빈 칸 가게', 6000.0, '10000085', holder: ''),
      ]),
      userCardId: ibk,
      codes: {'본인A*': ibk, '가족B*': mr},
    );
    expect(placed(two), {('가게 하나', ibk), ('가게 둘', mr)});
    expect(
      [
        for (final r in rowsOf(two))
          if (r['merchant_name'] == '빈 칸 가게') r['status'],
      ],
      ['unpaired'],
    );
    // 빈 값은 짝으로 남기지 않는다
    expect(() => saveWith(s, two, {'': ibk}), throwsA(isA<ApiError>()));
  });

  test('짝을 바꿔 같은 파일을 다시 넣어도 다른 카드에 이미 있는 결제는 넣지 않는다', () {
    // 단계 2 위험 검토 중간 3
    final (:s, :ibk, :mr) = twoOwned();
    final first = {'본인A*': ibk, '가족B*': mr};
    saveWith(s, imports.preview(s, twoCards(), codes: first), first);
    final swapped = imports.preview(
      s,
      twoCards(),
      codes: {'본인A*': mr, '가족B*': ibk},
    );
    expect(placed(swapped), isEmpty);
    expect(
      {
        for (final r in rowsOf(swapped))
          (r['status'], r['reason'], r.containsKey('paid_at')),
      },
      {('duplicate', '다른 카드에 이미 있는 결제예요', false)},
    );
  });

  test('카드를 지우면 그 카드의 짝을 지우고 기록 가져오기 뒤에는 짝이 없다', () {
    final (:s, :ibk, :mr) = twoOwned();
    final pairs = {'본인A*': ibk, '가족B*': mr};
    saveWith(s, imports.preview(s, twoCards(), codes: pairs), pairs);
    removeCard(s, mr);
    expect(
      s.db.select('select code from import_card_codes').map((r) => r['code']),
      ['본인A*'],
    );
    importAll(s, Uint8List.fromList(utf8.encode(exportAll(s))));
    expect(s.db.select('select 1 from import_card_codes'), isEmpty);
  });

  test('카드 칸이 모두 빈 파일은 위에서 카드를 골라야 한다', () {
    final (:s, :ibk, mr: _) = twoOwned();
    final blank = sheet([
      shinhanHead,
      shinhan('2026.09.05 10:00', '가게 하나', 5000.0, '10000091', holder: ''),
    ]);
    expect(() => imports.preview(s, blank), throwsA(isA<ApiError>()));
    expect(placed(imports.preview(s, blank, userCardId: ibk)), {
      ('가게 하나', ibk),
    });
  });

  test('지운 카드의 결제는 다른 카드 겹침으로 보지 않는다', () {
    final (:s, :ibk, :mr) = twoOwned();
    final wrong = {'본인A*': mr, '가족B*': mr};
    saveWith(s, imports.preview(s, twoCards(), codes: wrong), wrong);
    removeCard(s, mr);
    final p = imports.preview(s, twoCards(), codes: {'본인A*': ibk, '가족B*': ibk});
    expect(placed(p), {('가게 하나', ibk), ('가게 둘', ibk), ('가게 셋', ibk)});
  });
}
