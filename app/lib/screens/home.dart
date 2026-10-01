/// 시안 보드 1a 빈 홈과 1 홈. 카드마다 이번 달 구간과 남은 금액을 보인다
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
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
  late Future<Home> _home = widget.api.home();

  void _reload() => setState(() {
    _home = widget.api.home();
  });

  Future<void> _pay(List<HomeCard> cards) async {
    final repriced = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          api: widget.api,
          cards: [for (final c in cards) (id: c.id, name: c.name)],
        ),
      ),
    );
    if (repriced == null) return;
    _reload();
    if (repriced > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다른 결제 $repriced건의 혜택도 다시 계산했어요.')),
      );
    }
  }

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
        floatingActionButton: home == null || home.cards.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _pay(home.cards),
                icon: const Icon(Icons.edit),
                label: const Text('결제 기록'),
              ),
        appBar: AppBar(
          title: const Text('내 카드'),
          actions: [
            if (home != null)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Text(
                  '${home.month.month}월',
                  style: const TextStyle(fontSize: 16, color: C.sub),
                ),
              ),
          ],
        ),
        body: switch (snap) {
          AsyncSnapshot(hasError: true) => _Failed(onRetry: _reload),
          AsyncSnapshot(hasData: false) => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _Total(total: home!.benefitTotal, empty: home.cards.isEmpty),
              const SizedBox(height: 12),
              if (home.cards.isEmpty)
                _FirstCard(onAdd: _addCard)
              else ...[
                Box(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '실적 채우기',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: C.sub,
                        ),
                      ),
                      for (final c in home.cards)
                        CardRow(card: c, onTap: () => _detail(c)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                  ),
                  onPressed: _addCard,
                  child: const Text('카드 추가'),
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
        const Text('서버에 연결하지 못했어요.', style: TextStyle(color: C.sub)),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
}

class _Total extends StatelessWidget {
  const _Total({required this.total, required this.empty});
  final int total;
  final bool empty;

  @override
  Widget build(BuildContext context) => Box(
    color: C.blue,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '이번 달 받은 혜택',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (!empty) ...[
              const SizedBox(width: 6),
              // 흰 글자와 바탕 대비가 4.5:1 이상이 되게 바탕을 옅게 둔다
              const Pill('추정', fg: Colors.white, bg: Color(0x26FFFFFF)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          won(total),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (empty) ...[
          const SizedBox(height: 6),
          const Text(
            '카드를 등록하고 결제를 기록하면 여기에 쌓입니다.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

class _FirstCard extends StatelessWidget {
  const _FirstCard({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Box(
    child: Column(
      children: [
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
          '카드사와 이름으로 찾거나\n카드 앞면을 찍으면 됩니다.\n사진은 폰 밖으로 나가지 않습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: C.sub),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onAdd, child: const Text('카드 추가')),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => notReady(context, '카메라 인식'),
          child: const Text('카메라로 인식'),
        ),
      ],
    ),
  );
}

/// 카드 한 줄의 모양. 실적 무관, 구간 전, 구간 유지까지 남음, 다음 달 확정 넷으로 나눈다
({String ring, double value, String sub, String badge, bool chance}) look(
  HomeCard c,
) {
  final s = c.spend;
  String pct(int target) => '${(s.counted * 100 ~/ target).clamp(0, 100)}%';
  double part(int target) => (s.counted / target).clamp(0, 1).toDouble();
  if (s.tierSource == 'unsupported') {
    return (
      ring: '?',
      value: 0,
      sub: '결제일 기준 실적',
      badge: '실적 계산 미지원',
      chance: false,
    );
  }
  if (c.tiers.isEmpty) {
    return (
      ring: '상시',
      value: 1,
      sub: c.headline ?? '실적과 상관없이 받아요',
      badge: '실적 무관',
      chance: false,
    );
  }
  final tier = s.tier ?? 0;
  final next = s.nextTier;
  if (tier == 0 && next != null) {
    return (
      ring: pct(next),
      value: part(next),
      sub: '${man(s.toNext!)} 더 쓰면 다음 달 ${man(next)} 구간',
      badge: '구간 전',
      chance: true,
    );
  }
  if (tier > 0 && (s.toKeep ?? 0) > 0) {
    return (
      ring: pct(tier),
      value: part(tier),
      sub: '${man(s.toKeep!)} 더 쓰면 유지',
      badge: '${man(tier)} 구간',
      chance: false,
    );
  }
  return (
    ring: '완료',
    value: 1,
    sub: '다음 달 혜택 확정',
    badge: tier > 0 ? '${man(tier)} 구간' : '구간 전',
    chance: false,
  );
}

class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.card, this.onTap});
  final HomeCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = look(card);
    // 누르면 카드 상세. 시안 보드 6
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: l.value,
                    strokeWidth: 4,
                    color: C.blue,
                    backgroundColor: C.line,
                  ),
                  Text(
                    l.ring,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: C.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 2),
                  Text(
                    l.sub,
                    style: TextStyle(
                      fontSize: 13,
                      color: l.chance ? C.amber : C.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Pill(
              l.badge,
              fg: l.chance ? C.amber : C.blue,
              bg: l.chance ? C.grey : C.blueSoft,
            ),
          ],
        ),
      ),
    );
  }
}
