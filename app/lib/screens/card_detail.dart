/// 시안 보드 6 카드 상세. 실적, 구간, 혜택별 남은 한도, 구간이 모자라 못 받는 혜택. S7, S9, E37
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import 'records.dart';

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.api, required this.id});
  final Api api;
  final String id;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  late final Future<CardDetail> _detail = widget.api.cardDetail(widget.id);

  /// 카드 해지. 결제와 기록은 남고 홈과 추천에서만 빠진다. S9
  Future<void> _remove(CardDetail d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${d.name}을 해지할까요?'),
        content: const Text('홈과 추천에서 빠져요. 이 카드로 적은 결제는 기록에 남아요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해지'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.removeCard(d.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('해지하지 못했어요.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _detail,
    builder: (context, snap) {
      final d = snap.data;
      return Scaffold(
        appBar: AppBar(
          title: Text(d?.name ?? ''),
          actions: [
            if (d != null)
              PopupMenuButton<String>(
                onSelected: (_) => _remove(d),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('카드 해지')),
                ],
              ),
          ],
        ),
        body: switch (snap) {
          AsyncSnapshot(hasError: true) => const Center(
            child: Text('서버에 연결하지 못했어요.'),
          ),
          AsyncSnapshot(hasData: false) => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: _body(d!),
          ),
        },
      );
    },
  );

  List<Widget> _body(CardDetail d) {
    final s = d.spend;
    final tier = s.tier ?? 0;
    return [
      Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이번 달 실적', style: TextStyle(fontSize: 13, color: C.sub)),
            Text(
              won(s.counted),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: C.text,
              ),
            ),
            if (d.tiers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in d.tiers)
                    Pill(
                      man(t),
                      fg: t == tier ? Colors.white : C.sub,
                      bg: t == tier ? C.blue : C.grey,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tier > 0
                    ? '지금 적용 중 · ${man(tier)} 구간${d.prevMonthCounted == null ? '' : ' · 전월 ${man(d.prevMonthCounted!)} 기준'}'
                    : '지금은 혜택 구간 전이에요',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: C.text,
                ),
              ),
              if ((s.toKeep ?? 0) > 0)
                Text(
                  '다음 달 ${man(tier)} 구간 유지 · ${man(s.toKeep!)} 더',
                  style: const TextStyle(color: C.sub),
                ),
              if (s.nextTier != null && s.toNext != null)
                Text(
                  '다음 달 ${man(s.nextTier!)} 구간으로 · ${man(s.toNext!)} 더',
                  style: const TextStyle(color: C.sub),
                ),
            ] else
              const Text(
                '실적과 상관없이 혜택을 받는 카드예요',
                style: TextStyle(color: C.sub),
              ),
          ],
        ),
      ),
      if (d.limits.isNotEmpty) ...[
        const _Heading('남은 한도'),
        Box(
          child: Column(
            children: [
              for (final l in d.limits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.title,
                          style: const TextStyle(color: C.text),
                        ),
                      ),
                      Text(
                        _left(l),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: C.green,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      if (d.locked.isNotEmpty) ...[
        const _Heading('구간이 모자라 아직 못 받는 혜택'),
        Box(
          child: Column(
            children: [
              for (final l in d.locked)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.title,
                              style: const TextStyle(color: C.text),
                            ),
                            Text(
                              '${man(l.requiredTier)} 구간부터 · 다음 달부터 받아요',
                              style: const TextStyle(
                                fontSize: 13,
                                color: C.faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${man(l.remaining)} 더',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: C.amber,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      if (d.checkSentences.isNotEmpty || d.assumedCount > 0) ...[
        const _Heading('확인이 필요한 것'),
        Box(
          color: C.grey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in d.checkSentences.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    t,
                    style: const TextStyle(fontSize: 13, color: C.sub),
                  ),
                ),
              if (d.assumedCount > 0)
                Text(
                  '카드사 공식 문구로 확인하지 못한 값 ${d.assumedCount}개는 추정으로 계산해요.',
                  style: const TextStyle(fontSize: 13, color: C.sub),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (d.startedOn != null)
        Text(
          '쓰기 시작한 달 · ${d.startedOn!.substring(0, 7)}',
          style: const TextStyle(color: C.sub),
        ),
      if (d.revisionFrom != null)
        Text(
          '이 카드의 실적 규칙 갱신 ${d.revisionFrom}',
          style: const TextStyle(color: C.sub),
        ),
      const SizedBox(height: 12),
      OutlinedButton(
        style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecordsScreen(api: widget.api, card: d.id),
          ),
        ),
        child: const Text('이 카드 결제 보기'),
      ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: C.sub,
      ),
    ),
  );
}

const _periods = {
  'month': '이번 달',
  'quarter': '이번 분기',
  'year': '올해',
  'period': '행사 기간',
  'lifetime': '전체 기간',
};

/// 한도 한 줄의 남은 양. 금액, 횟수, 결제액 한도 가운데 남은 비율이 가장 작은 것을 보인다. 먼저 끝나는 쪽이다.
/// 다 써도 0 아래로 내려가지 않는다
String _left(
  ({
    String title,
    String per,
    int usedAmount,
    int? capAmount,
    int usedCount,
    int? capCount,
    int usedBase,
    int? capBase,
  })
  l,
) {
  final per = _periods[l.per] ?? '';
  final options = [
    if (l.capAmount != null) (l.capAmount!, l.usedAmount, (int n) => won(n)),
    if (l.capCount != null) (l.capCount!, l.usedCount, (int n) => '$n회'),
    if (l.capBase != null) (l.capBase!, l.usedBase, (int n) => '결제액 ${won(n)}'),
  ];
  double share((int, int, String Function(int)) o) =>
      o.$1 == 0 ? 0 : max(0, o.$1 - o.$2) / o.$1;
  final o = options.reduce((a, b) => share(b) < share(a) ? b : a);
  return '$per ${o.$3(max(0, o.$1 - o.$2))} 남음';
}
