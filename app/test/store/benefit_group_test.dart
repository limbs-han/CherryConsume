// 카드 상세에서 혜택을 묶는 업종. 작업 011 설계 2.5, 계획 단계 5의 1-3
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/store/routes/me.dart' show benefitGroup;
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart' show realCatalog;

Benefit benefit(String card, String title) => realCatalog
    .cards[card]!
    .revisions
    .last
    .rules
    .benefits
    .firstWhere((b) => b.title == title);

String group(String card, String title) =>
    benefitGroup(benefit(card, title), realCatalog).name;

void main() {
  test('대상 업종을 큰 분류로 올린 이름이다', () {
    expect(group('ibk-narasarang', '편의점 10% 청구할인'), '편의점');
    // 시내버스와 지하철은 대중교통의 자식 업종이다
    expect(group('ibk-narasarang', '대중교통 20% 청구할인'), '대중교통');
  });

  test('가맹점만 있는 혜택은 가맹점의 업종이다', () {
    expect(group('ibk-narasarang', 'CGV 1,500원 현장할인'), '영화');
  });

  test('다른 업종이 함께 있으면 기타를 뺀다', () {
    // 쿠팡은 온라인 쇼핑, 다이소와 올리브영은 업종이 정해지지 않아 기타다
    expect(group('ibk-narasarang', '쿠팡·다이소·올리브영 1천원 청구할인'), '온라인 쇼핑');
  });

  test('여러 업종은 카탈로그 업종 순서로 이어 붙인다', () {
    expect(group('shinhan-mrlife', '야간 식음료 10% 할인'), '카페 · 음식점');
    // 전기와 가스는 공과금, KT와 LG유플러스와 SKT는 통신요금이다. 카탈로그에서 통신요금이 공과금보다 앞이다
    expect(group('shinhan-mrlife', '전기·가스·통신요금 10% 할인'), '통신요금 · 공과금');
  });

  test('군마트는 화면에서 묶을 때만 편의점이다', () {
    // 카탈로그의 가맹점 업종은 기타 그대로다. 바꾸면 편의점 혜택이 군마트 결제에 붙어 계산이 달라진다
    expect(realCatalog.merchants['px']!.category, 'other');
    expect(group('ibk-narasarang', '군마트(PX) 3만원 미만 15% 할인'), '편의점');
  });

  test('전가맹점 혜택은 모든 가맹점이고 맨 앞이다', () {
    final all = benefitGroup(
      benefit('ibk-narasarang', 'Npay 결제 10% 포인트 적립'),
      realCatalog,
    );
    expect(all.name, '모든 가맹점');
    final cafe = benefitGroup(
      benefit('shinhan-mrlife', '야간 식음료 10% 할인'),
      realCatalog,
    );
    expect(all.order, lessThan(cafe.order));
    final px = benefitGroup(
      benefit('ibk-narasarang', '군마트(PX) 3만원 미만 15% 할인'),
      realCatalog,
    );
    // 카탈로그에서 카페가 편의점보다 앞이다
    expect(cafe.order, lessThan(px.order));
  });
}
