// 사용자가 고른 업종을 가게 이름으로 기억해 같은 이름의 다음 결제에 쓴다. 작업 016 설계 3절, 4절
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/catalog/models.dart' show Json;
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/payments.dart';
import 'package:cherry_consume/store/routes/me.dart' show home;
import 'package:cherry_consume/store/routes/records.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _at = '2026-09-15T21:00:00+09:00';

/// 결제 하나의 업종을 기록에서 고친다. 다른 칸은 그대로 보낸다
Json setCategory(
  Store s,
  String card,
  String tid,
  String name,
  String? category,
) => edit(s, tid, {
  'user_card_id': card,
  'amount': 8000,
  'merchant_name': name,
  'paid_at': _at,
  'category': category,
});

List<Object?> remembered(Store s) => [
  for (final r in s.db.select(
    'select name_key, category_code from merchant_categories order by name_key',
  ))
    (r['name_key'], r['category_code']),
];

void main() {
  test('기록에서 고친 업종을 같은 이름의 다음 결제와 가져오기에 쓴다', () {
    // 작업 016 성공 기준 1. 띄어쓰기가 달라도 같은 가게다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final first = pay(s, card, 8000, '동네 국밥집');
    expect(draft(s, {'merchant_name': '동네국밥집'})['category'], isNull);
    setCategory(s, card, first['id'] as String, '동네 국밥집', 'restaurant');
    expect(remembered(s), [('동네국밥집', 'restaurant')]);
    expect(draft(s, {'merchant_name': '동네국밥집'})['category'], 'restaurant');
    final p = imports.preview(
      s,
      Uint8List.fromList(
        utf8.encode('이용일자,가맹점명,이용금액\n2026.09.16 12:00,동네 국밥집,9000\n'),
      ),
      userCardId: card,
    );
    final [row] = (p['rows'] as List).cast<Json>();
    expect(row['category_name'], s.categoryNames['restaurant']);
    imports.save(s, {
      'rows': [row],
    });
    final saved = s.db.select(
      "select category_code from transactions where amount = 9000",
    );
    expect(saved.single['category_code'], 'restaurant');
  });

  test('결제에 고른 업종, 기억한 업종, 카탈로그 업종 순서로 정한다', () {
    // 작업 016 성공 기준 2. GS25는 카탈로그에서 편의점이다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    expect(draft(s, {'merchant_name': 'GS25 가게점'})['category'], 'convenience');
    final first = pay(s, card, 8000, 'GS25 가게점');
    setCategory(s, card, first['id'] as String, 'GS25 가게점', 'cafe');
    expect(draft(s, {'merchant_name': 'GS25 가게점'})['category'], 'cafe');
    // 가맹점은 그대로라 브랜드 혜택은 받는다
    expect(draft(s, {'merchant_name': 'GS25 가게점'})['merchant'], 'gs25');
    expect(
      draft(s, {
        'merchant_name': 'GS25 가게점',
        'category': 'grocery_mart',
      })['category'],
      'grocery_mart',
    );
    // 다른 지점은 다른 가게라 카탈로그 업종이다
    expect(draft(s, {'merchant_name': 'GS25 다른점'})['category'], 'convenience');
  });

  test('카탈로그 업종으로 되돌리면 기억을 지우고, 다른 칸만 고치면 기억하지 않는다', () {
    // 작업 016 설계 3절
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final first = pay(s, card, 8000, 'GS25 가게점');
    final tid = first['id'] as String;
    setCategory(s, card, tid, 'GS25 가게점', 'convenience');
    expect(remembered(s), isEmpty);
    setCategory(s, card, tid, 'GS25 가게점', 'cafe');
    expect(remembered(s), [('gs25가게점', 'cafe')]);
    setCategory(s, card, tid, 'GS25 가게점', 'convenience');
    expect(remembered(s), isEmpty);
    // 업종이 그대로인 고치기는 기억을 바꾸지 않는다
    final other = pay(
      s,
      card,
      8000,
      '동네 국밥집',
      more: {'category': 'restaurant'},
    );
    expect(remembered(s), [('동네국밥집', 'restaurant')]);
    final second = pay(s, card, 8000, '동네 국밥집');
    setCategory(s, card, second['id'] as String, '동네 국밥집', 'cafe');
    setCategory(s, card, other['id'] as String, '동네 국밥집', 'restaurant');
    expect(remembered(s), [('동네국밥집', 'cafe')]);
  });

  test('업종을 고치면 같은 가게 결제 건수를 알리고, 바꾸기를 고르면 그 결제들의 혜택을 다시 계산한다', () {
    // 작업 016 성공 기준 7, 설계 5절. Mr.Life는 편의점 업종 결제를 10% 할인한다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    Json at(String day, String name) => save(s, {
      'user_card_id': card,
      'amount': 4300,
      'merchant_name': name,
      'paid_at': '2026-09-${day}T12:00:00+09:00',
    });
    final first = at('10', '동네 가게');
    final second = at('11', '동네가게');
    final elsewhere = at('12', '다른 가게');
    int value(Json p) =>
        s.db.select(
              'select coalesce(sum(value), 0) v from transaction_benefits where transaction_id = ?',
              [p['id']],
            ).single['v']
            as int;
    expect([value(first), value(second)], [0, 0]);
    final edited = edit(s, first['id'] as String, {
      'user_card_id': card,
      'amount': 4300,
      'merchant_name': '동네 가게',
      'paid_at': '2026-09-10T12:00:00+09:00',
      'category': 'convenience',
    });
    expect(edited['same_name'], {
      'count': 1,
      'category': 'convenience',
      'category_name': s.categoryNames['convenience'],
    });
    expect(value(first), 430);
    // 그대로 두면 다른 결제는 바뀌지 않는다
    expect(value(second), 0);
    final done = recategorize(s, {
      'merchant_name': '동네 가게',
      'category': 'convenience',
    });
    expect(done['changed'], 1);
    expect(value(second), 430);
    expect(value(elsewhere), 0);
    final cats = {
      for (final r in s.db.select('select id, category_code from transactions'))
        r['id']: r['category_code'],
    };
    expect(
      [cats[first['id']], cats[second['id']], cats[elsewhere['id']]],
      ['convenience', 'convenience', null],
    );
    // 다시 부르면 바꿀 결제가 없다
    expect(
      recategorize(s, {
        'merchant_name': '동네 가게',
        'category': 'convenience',
      })['changed'],
      0,
    );
  });

  test('간편결제 이름을 뗀 가게로 기억한다', () {
    // 작업 016 단계 2~4 검토 중간 1. "네이버페이(CGV)"와 "네이버페이(KFC)"는 다른 가게다
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    pay(s, card, 8000, '동네 국밥집', more: {'category': 'restaurant'});
    expect(
      draft(s, {'merchant_name': '네이버페이 동네국밥집'})['category'],
      'restaurant',
    );
    pay(s, card, 8000, '네이버페이(동네꽃집)', more: {'category': 'other'});
    expect(
      draft(s, {'merchant_name': '네이버페이(동네치킨집)'})['category'],
      isNot('other'),
    );
    // 영문 가게 이름이 든 괄호도 간편결제 이름을 떼고 나면 가게 이름이다
    expect(draft(s, {'merchant_name': '네이버페이(CGV)'})['merchant'], 'cgv');
  });

  test('부모 업종을 고르면 이미 자식 업종인 결제와 기억을 덮지 않는다', () {
    // 작업 016 단계 2~4 검토 중간 3. 덮으면 자식 업종에만 주는 혜택이 빠진다. E47
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final bakery = pay(
      s,
      card,
      8000,
      '동네 빵집',
      more: {'category': 'restaurant.bakery'},
    );
    final cafe = pay(s, card, 8000, '동네 빵집', more: {'category': 'cafe'});
    expect(remembered(s), [('동네빵집', 'cafe')]);
    final asked = setCategory(
      s,
      card,
      cafe['id'] as String,
      '동네 빵집',
      'restaurant',
    );
    expect(asked['same_name'], isNull);
    final done = recategorize(s, {
      'merchant_name': '동네 빵집',
      'category': 'restaurant',
    });
    expect(done['changed'], 0);
    final cats = {
      for (final r in s.db.select('select id, category_code from transactions'))
        r['id']: r['category_code'],
    };
    expect(
      [cats[bakery['id']], cats[cafe['id']]],
      ['restaurant.bakery', 'restaurant'],
    );
    // 자식을 고르면 부모인 결제를 자식으로 바꾼다
    expect(
      setCategory(
        s,
        card,
        cafe['id'] as String,
        '동네 빵집',
        'restaurant.bakery',
      )['same_name'],
      isNull,
    );
  });

  test('가게 이름을 바꾸며 고른 업종은 새 이름의 자동 업종과 견준다', () {
    // 작업 016 단계 2~4 검토 낮음 6
    final (:s, clock: _) = fresh();
    final [card] = setup(s);
    final first = pay(
      s,
      card,
      8000,
      '동네 국밥집',
      more: {'category': 'restaurant'},
    );
    setCategory(s, card, first['id'] as String, '국밥 본점', 'restaurant');
    expect(remembered(s), [('국밥본점', 'restaurant'), ('동네국밥집', 'restaurant')]);
  });

  test('한꺼번에 바꾸면 처음부터 그 업종으로 넣은 것과 결과가 같다', () {
    // 작업 016 단계 2~4 검토 중간 4. 카드 두 장, 두 달, 취소된 결제, 실적에서 빠질 수 있는 상품권 업종이다. 손계산 대신
    // 결제 시각 순서로 하나씩 넣은 결과와 견준다. E52
    List<Object?> run({required bool upfront}) {
      final (:s, clock: _) = fresh();
      final [mr, ibk] = setup(s, [
        mrlife,
        {'card_id': 'ibk-narasarang', 'assumed_prev_month_spend': 300000},
      ]);
      final lines = [
        (mr, '2026-08-05', 120000, '동네 상품권'),
        (mr, '2026-08-20', 300000, '이마트'),
        (ibk, '2026-08-25', 50000, '동네 상품권'),
        (mr, '2026-09-03', 4300, 'GS25 가게점'),
        (mr, '2026-09-10', 90000, '동네 상품권'),
        (ibk, '2026-09-12', 12000, '스타벅스 가게점'),
      ];
      final ids = <String>[];
      for (final (card, day, amount, name) in lines) {
        ids.add(
          save(s, {
                'user_card_id': card,
                'amount': amount,
                'merchant_name': name,
                'paid_at': '${day}T12:00:00+09:00',
                if (upfront && name == '동네 상품권') 'category': 'gift_card',
              })['id']
              as String,
        );
      }
      cancel(s, ids[2], {
        'cancelled_amount': 50000,
        'cancelled_at': '2026-08-27T12:00:00+09:00',
      });
      if (!upfront) {
        recategorize(s, {'merchant_name': '동네 상품권', 'category': 'gift_card'});
      }
      return [
        for (final r in s.db.select(
          'select t.paid_at, t.amount, t.category_code, t.cancelled_amount, '
          '(select coalesce(sum(value), 0) from transaction_benefits b where b.transaction_id = t.id) v '
          'from transactions t order by t.paid_at',
        ))
          [
            r['paid_at'],
            r['amount'],
            r['category_code'],
            r['cancelled_amount'],
            r['v'],
          ],
        // 카드 id는 저장소마다 달라 빼고 견준다. 상품권은 실적에서 빠져 9월 구간이 바뀐다
        home(s)['benefit_total'],
        for (final c in home(s)['cards'] as List)
          jsonEncode((c as Json)['spend']),
      ];
    }

    expect(run(upfront: false), run(upfront: true));
  });
}
