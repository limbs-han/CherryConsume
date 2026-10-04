// 금액 쓰기와 홈 카드 한 줄 모양. 작업 005 계획 슬라이스 1의 7단계
import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/format.dart';
import 'package:cherry_consume/screens/add_card.dart';
import 'package:cherry_consume/screens/home.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCard card({
  List<int> tiers = const [300000, 500000, 1000000],
  String source = 'assumed',
  int counted = 0,
  int? tier = 300000,
  int? toKeep = 300000,
  int? next = 500000,
  int? toNext = 500000,
  String? headline,
}) => HomeCard({
  'id': 'u1',
  'name': '신한카드 Mr.Life',
  'tiers': tiers,
  'headline': headline,
  'spend': {
    'counted': counted,
    'tier': tier,
    'tier_source': source,
    'to_keep': toKeep,
    'next_tier': next,
    'to_next': toNext,
  },
});

void main() {
  test('원', () {
    expect(won(0), '0원');
    expect(won(7669), '7,669원');
    expect(won(1234567), '1,234,567원');
  });

  test('만. 천 원 아래는 올린다', () {
    expect(man(118000), '11.8만');
    expect(man(300000), '30만');
    expect(man(15000), '1.5만');
    // 12만 3,456원이 남았으면 12.3만이 아니라 12.4만이다. 12.3만만 쓰면 모자란다
    expect(man(123456), '12.4만');
    expect(man(10000000), '1,000만');
    expect(man(5000), '5,000원');
    expect(man(9999), '9,999원');
    expect(man(10000), '1만');
    expect(man(10001), '1.1만');
  });

  test('카드 검색 줄', () {
    final hit = CardHit({
      'id': 'shinhan-mrlife',
      'name': '신한카드 Mr.Life',
      'issuer_name': '신한카드',
      'kind': 'credit',
      'annual_fee': 15000,
      'tiers': [300000, 500000, 1000000],
    });
    expect(cardLine(hit), '신용 · 연회비 1.5만 · 실적 30/50/100만');
  });

  test('홈 카드 한 줄. 구간을 지키려면 남은 금액', () {
    // 이번 달 18.2만을 써서 30만 구간까지 11.8만 남았다. 시안 보드 1
    final l = look(card(counted: 182000, toKeep: 118000, toNext: 318000));
    expect((l.ring, l.sub, l.badge), ('60%', '11.8만 더 쓰면 유지', '30만 구간'));
    // 시안은 남은 금액만 코발트로 강조한다. 작업 011 설계 2절 H4
    expect((l.lead, l.tone), ('11.8만', Tone.blue));
  });

  test('홈 카드 한 줄. 다음 달 확정', () {
    final l = look(card(counted: 300000, toKeep: 0, toNext: 200000));
    expect((l.ring, l.sub, l.badge), ('완료', '다음 달 혜택 확정', '30만 구간'));
    expect((l.lead, l.tone), (null, Tone.green));
  });

  test('홈 카드 한 줄. 아직 혜택 구간 전이면 기회 색', () {
    final l = look(
      card(
        source: 'prev_month',
        tier: 0,
        toKeep: null,
        next: 300000,
        toNext: 300000,
      ),
    );
    expect(
      (l.ring, l.sub, l.badge, l.chance),
      ('0%', '30만 더 쓰면 다음 달 30만 구간', '구간 전', true),
    );
    expect((l.lead, l.tone), ('30만', Tone.amber));
  });

  test('홈 카드 한 줄. 실적 무관', () {
    final l = look(
      card(
        tiers: [],
        tier: 0,
        toKeep: null,
        next: null,
        toNext: null,
        headline: '국내외 가맹점 0.8% 할인',
      ),
    );
    expect((l.ring, l.sub, l.badge), ('상시', '국내외 가맹점 0.8% 할인', '실적 무관'));
    expect((l.lead, l.tone), (null, Tone.gray));
  });

  test('홈 카드 한 줄. 실적 계산 미지원', () {
    final l = look(
      card(
        source: 'unsupported',
        tier: 0,
        toKeep: null,
        next: null,
        toNext: null,
      ),
    );
    expect(l.badge, '실적 계산 미지원');
  });
}
