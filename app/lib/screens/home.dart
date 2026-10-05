/// 시안 보드 1a 빈 홈과 1 홈. 카드마다 이번 달 구간과 남은 금액을 보인다
/// 모양은 작업 011 설계 2절 H1~H6을 따른다
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../ui.dart';
import 'add_card.dart';
import 'card_detail.dart';
import 'payment.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final Api api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Home> _home = _load();

  void _reload() => setState(() {
    _home = _load();
  });

  Future<Home> _load() => widget.api.home();

  Future<void> _detail(HomeCard c) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CardDetailScreen(api: widget.api, id: c.id),
      ),
    );
    _reload();
  }

  Future<void> _addCard() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddCardScreen(api: widget.api)),
    );
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _home,
    builder: (context, snap) {
      final home = snap.data;
      return Scaffold(
        // 홈을 다시 불러오면 버튼도 카드 목록을 다시 본다
        floatingActionButton: PayButton(
          refresh: _home,
          api: widget.api,
          onSaved: _reload,
        ),
        appBar: AppBar(
          titleSpacing: rootTitleSpacing(context),
          title: const Text('내 카드'),
          actions: [
            if (home != null)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Text(
                  '${home.month.month}월',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: C.sub,
                  ),
                ),
              ),
          ],
        ),
        body: switch (snap) {
          AsyncSnapshot(hasError: true) => _Failed(onRetry: _reload),
          AsyncSnapshot(hasData: false) => const Center(
            child: CircularProgressIndicator(),
          ),
          // 아래 여백은 결제 기록 버튼이 마지막 카드를 가리지 않게 둔다
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
            children: [
              _Total(total: home!.benefitTotal, empty: home.cards.isEmpty),
              const SizedBox(height: 12),
              if (home.cards.isEmpty)
                _FirstCard(onAdd: _addCard)
              else ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    '실적 채우기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: C.sub,
                    ),
                  ),
                ),
                for (final c in home.cards) ...[
                  CardRow(card: c, onTap: () => _detail(c)),
                  const SizedBox(height: 12),
                ],
                Semantics(
                  button: true,
                  child: Pressable(
                    onTap: _addCard,
                    child: const DashedBox(
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add, color: C.sub),
                            SizedBox(width: 8),
                            Text(
                              '카드 추가',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: C.sub,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        },
      );
    },
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('홈을 불러오지 못했어요.', style: TextStyle(color: C.sub)),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}

/// 큰 금액과 작은 "원"
class _Amount extends StatelessWidget {
  const _Amount(this.value, {required this.color});
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: comma(value),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.1,
          ),
        ),
        const TextSpan(
          text: '원',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    ),
    style: TextStyle(color: color),
  );
}

/// 이번 달 받은 혜택 띠. 카드가 없으면 연한 점선 상자에 회색 0원이다. 설계 2절 H1, H2
class _Total extends StatelessWidget {
  const _Total({required this.total, required this.empty});
  final int total;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    if (empty) {
      return const DashedBox(
        key: Key('total'),
        color: C.blueSoft,
        borderColor: Color(0xFFB9C6EA),
        radius: 20,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이번 달 받은 혜택',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: C.blue,
              ),
            ),
            SizedBox(height: 4),
            _Amount(0, color: C.faint),
            SizedBox(height: 4),
            Text(
              '카드를 등록하고 결제를 기록하면 여기에 쌓입니다.',
              style: TextStyle(fontSize: 13, height: 1.5, color: C.sub),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const Key('total'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(color: C.blue, borderRadius: r20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '이번 달 받은 혜택',
                style: TextStyle(
                  color: C.blueSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 8),
              // 흰 글자와 바탕 대비가 4.5:1 이상이 되게 진한 코발트를 쓴다
              Pill('추정', fg: Colors.white, bg: Color(0xFF2A468F)),
            ],
          ),
          const SizedBox(height: 4),
          CountUp(total, builder: (n) => _Amount(n, color: Colors.white)),
        ],
      ),
    );
  }
}

class _FirstCard extends StatelessWidget {
  const _FirstCard({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Box(
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: C.blueSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.credit_card, size: 32, color: C.blue),
        ),
        const SizedBox(height: 12),
        const Text(
          '첫 카드를 등록해 보세요',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: C.text,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '카드사와 이름으로 찾으면 됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: C.sub),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onAdd, child: const Text('카드 추가')),
      ],
    ),
  );
}

/// 카드 줄의 색 단계. 구간 유지까지 남음은 코발트, 구간 전은 호박색, 다음 달 확정은 초록, 실적 무관은 회색이다
enum Tone { blue, amber, green, gray }

const _toneColors = {
  Tone.blue: (fg: C.blue, bg: C.blueSoft, ring: C.blue),
  Tone.amber: (fg: C.amber, bg: C.amberSoft, ring: C.amber),
  Tone.green: (fg: C.green, bg: C.greenSoft, ring: Color(0xFF8CCBA9)),
  Tone.gray: (fg: C.sub, bg: C.grey, ring: C.grey),
};

/// 카드 한 줄의 모양. 실적 무관, 구간 전, 구간 유지까지 남음, 다음 달 확정, 실적 계산 미지원 다섯으로 나눈다.
/// lead는 문구 앞에서 색으로 강조하는 금액이다. 없으면 문구 전체가 색이다. 작업 011 설계 2절 H4
({
  String ring,
  double value,
  String sub,
  String? lead,
  String badge,
  bool chance,
  Tone tone,
})
look(HomeCard c) {
  final s = c.spend;
  String pct(int target) => '${(s.counted * 100 ~/ target).clamp(0, 100)}%';
  double part(int target) => (s.counted / target).clamp(0, 1).toDouble();
  if (s.tierSource == 'unsupported') {
    return (
      ring: '?',
      value: 0,
      sub: '결제일 기준 실적',
      lead: null,
      badge: '실적 계산 미지원',
      chance: false,
      tone: Tone.gray,
    );
  }
  if (c.tiers.isEmpty) {
    return (
      ring: '상시',
      value: 1,
      sub: c.headline ?? '실적과 상관없이 받아요',
      lead: null,
      badge: '실적 무관',
      chance: false,
      tone: Tone.gray,
    );
  }
  final tier = s.tier ?? 0;
  final next = s.nextTier;
  if (tier == 0 && next != null) {
    return (
      ring: pct(next),
      value: part(next),
      sub: '${man(s.toNext!)} 더 쓰면 다음 달 ${man(next)} 구간',
      lead: man(s.toNext!),
      badge: '구간 전',
      chance: true,
      tone: Tone.amber,
    );
  }
  if (tier > 0 && (s.toKeep ?? 0) > 0) {
    return (
      ring: pct(tier),
      value: part(tier),
      sub: '${man(s.toKeep!)} 더 쓰면 유지',
      lead: man(s.toKeep!),
      badge: '${man(tier)} 구간',
      chance: false,
      tone: Tone.blue,
    );
  }
  return (
    ring: '완료',
    value: 1,
    sub: '다음 달 혜택 확정',
    lead: null,
    badge: tier > 0 ? '${man(tier)} 구간' : '구간 전',
    chance: false,
    tone: Tone.green,
  );
}

/// 실적 고리. 0.6초 동안 차오른다. 실적 무관은 고리 대신 회색 원이다. 원칙 3
class _Ring extends StatelessWidget {
  const _Ring({required this.text, required this.value, required this.tone});
  final String text;
  final double value;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors[tone]!;
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: colors.fg,
      ),
    );
    return SizedBox(
      width: 48,
      height: 48,
      child: tone == Tone.gray
          ? DecoratedBox(
              decoration: const BoxDecoration(
                color: C.grey,
                shape: BoxShape.circle,
              ),
              child: Center(child: label),
            )
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: v,
                      strokeWidth: 6,
                      color: colors.ring,
                      backgroundColor: C.bg,
                    ),
                  ),
                  label,
                ],
              ),
            ),
    );
  }
}

/// 카드마다 따로 놓인 흰 카드. 고리, 이름, 강조한 문구, 구간 배지, 카드사 색 칸이다
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.card, this.onTap});
  final HomeCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = look(card);
    final colors = _toneColors[l.tone]!;
    // 코발트와 호박색은 금액만 강조하고 나머지는 검은 글자다. 초록과 회색은 문구 전체가 그 색이다
    final restColor = l.lead == null ? colors.fg : C.text;
    // 누르면 카드 상세. 시안 보드 6
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: Box(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              _Ring(text: l.ring, value: l.value, tone: l.tone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: C.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (l.lead != null)
                            TextSpan(
                              text: l.lead,
                              style: TextStyle(color: colors.fg),
                            ),
                          TextSpan(
                            text: l.lead == null
                                ? l.sub
                                : l.sub.substring(l.lead!.length),
                            style: TextStyle(color: restColor),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Pill(l.badge, fg: colors.fg, bg: colors.bg),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IssuerSwatch(card.issuer),
            ],
          ),
        ),
      ),
    );
  }
}
