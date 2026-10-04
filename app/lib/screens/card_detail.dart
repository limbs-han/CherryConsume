/// 시안 보드 6 카드 상세. 실적, 구간, 혜택별 남은 한도, 구간이 모자라 못 받는 혜택. S7, S9, E37
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../clock.dart' as clock;
import '../format.dart';
import '../theme.dart';
import '../ui.dart';
import 'answer.dart';
import 'records.dart';

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({super.key, required this.api, required this.id});
  final Api api;
  final String id;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  late Future<CardDetail> _detail = widget.api.cardDetail(widget.id);

  /// 카드 사실, 옵션, 쓰기 시작한 날을 답하고 다시 불러온다. 처음 답은 모든 결제에, 바꾼 답은 바뀌는 날부터다. E56
  Future<void> _answer(Map<String, Object?> body) async {
    try {
      final repriced = await widget.api.answerCard(widget.id, body);
      if (!mounted) return;
      answered(context, repriced);
      setState(() {
        _detail = widget.api.cardDetail(widget.id);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('답을 적지 못했어요.')));
      }
    }
  }

  Future<void> _pickStart(CardDetail d) async {
    final today = DateUtils.dateOnly(clock.now());
    final day = await showDatePicker(
      context: context,
      initialDate: d.startedOn == null ? today : DateTime.parse(d.startedOn!),
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (day == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    await _answer({
      'started_on': '${day.year}-${two(day.month)}-${two(day.day)}',
    });
  }

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
                icon: const Icon(Icons.more_horiz),
                onSelected: (_) => _remove(d),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'remove', child: Text('카드 해지')),
                ],
              ),
          ],
        ),
        body: switch (snap) {
          AsyncSnapshot(hasError: true) => const Center(
            child: Text('카드 정보를 불러오지 못했어요.'),
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
    // 함께 쓰는 한도마다 회색 상자 하나를 두고 그 한도를 쓰는 혜택을 안에 묶는다. 둘 이상을 쓰는 혜택은 처음 것에 둔다.
    // 작업 011 설계 2절 D3, D5
    final boxes = [
      for (final l in d.limits)
        if (l.isShared) l,
    ];
    final keys = {for (final l in boxes) l.key};
    String? boxOf(Limit l) =>
        l.isShared ? null : l.shared.where(keys.contains).firstOrNull;
    final each = [
      for (final l in d.limits)
        if (!l.isShared && boxOf(l) == null) l,
    ];
    return [
      Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Expanded(
                  child: Text(
                    '이번 달 실적',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: C.sub,
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: comma(s.counted),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const TextSpan(
                        text: '원',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(color: C.text),
                ),
              ],
            ),
            if (d.tiers.isNotEmpty) ...[
              const SizedBox(height: 12),
              TierBar(tiers: d.tiers, counted: s.counted),
              const Divider(height: 28, color: C.line),
              _Row(
                '지금 적용 중',
                tier > 0
                    ? '${man(tier)} 구간${d.prevMonthCounted == null ? '' : ' · 전월 ${man(d.prevMonthCounted!)} 기준'}'
                    : '구간 전',
              ),
              if ((s.toKeep ?? 0) > 0)
                _Row(
                  '다음 달 ${man(tier)} 구간 유지',
                  '${man(s.toKeep!)} 더',
                  color: C.blue,
                ),
              if (s.nextTier != null && s.toNext != null)
                _Row('다음 달 ${man(s.nextTier!)} 구간으로', '${man(s.toNext!)} 더'),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                '실적과 상관없이 혜택을 받는 카드예요',
                style: TextStyle(color: C.sub),
              ),
            ],
          ],
        ),
      ),
      if (d.limits.isNotEmpty || d.locked.isNotEmpty) ...[
        const SizedBox(height: 12),
        Box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '이번 달 혜택',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: C.text,
                ),
              ),
              const SizedBox(height: 12),
              for (final box in boxes)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: const BoxDecoration(
                    color: C.grey,
                    borderRadius: r16,
                  ),
                  child: Column(
                    children: [
                      _LimitRow(box),
                      for (final l in d.limits)
                        if (boxOf(l) == box.key) _LimitRow(l),
                    ],
                  ),
                ),
              for (final l in each) _LimitRow(l),
              if (d.locked.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '구간이 모자라 아직 못 받는 혜택',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: C.sub,
                  ),
                ),
                for (final l in d.locked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: C.text,
                                ),
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
                        const SizedBox(width: 12),
                        Text(
                          '${man(l.remaining)} 더',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: C.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
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
      // 카드 사실과 옵션은 여기서 묻는다. 없는 카드는 쓰기 시작한 달만 있다. 작업 004 설계 3.1
      const _Heading('카드 정보'),
      Box(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              child: Pressable(
                key: const Key('started-on'),
                onTap: () => _pickStart(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '쓰기 시작한 달',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: C.text,
                              ),
                            ),
                            Text(
                              '새 카드 특례 기간을 계산해요',
                              style: TextStyle(fontSize: 13, color: C.sub),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _month(d.startedOn),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: C.text,
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: C.faint),
                    ],
                  ),
                ),
              ),
            ),
            for (final q in d.facts)
              FactAnswer(
                q: q,
                onAnswer: (v) => _answer({
                  'facts': {q.key: v},
                }),
              ),
            for (final q in d.options)
              OptionAnswer(
                q: q,
                onAnswer: (c) => _answer({
                  'options': {q.key: c},
                }),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (d.revisionFrom != null)
        Text(
          '이 카드의 실적 규칙 갱신 ${d.revisionFrom}',
          style: const TextStyle(color: C.sub),
        ),
      const SizedBox(height: 12),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: C.blueSoft,
          foregroundColor: C.blue,
        ),
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

/// "2025-03-01"에서 "2025년 3월". 모르면 "몰라요"
String _month(String? day) {
  if (day == null) return '몰라요';
  final d = DateTime.parse(day);
  return '${d.year}년 ${d.month}월';
}

/// 왼쪽 이름과 오른쪽 굵은 값. 설계 2절 D2
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color = C.text});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: _Pair(
      Text(label, style: const TextStyle(fontSize: 15, color: C.sub)),
      Text(
        value,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ),
  );
}

/// 이름은 왼쪽, 값은 오른쪽 끝에 제 폭대로 둔다. 값이 폭의 70%를 넘으면 그 안에서 줄을 바꾼다. 이름과 값이 폭을 반씩
/// 나누면 값이 가운데서 시작하고 짧은 이름도 줄을 바꾼다. 2026-10-04 에뮬레이터에서 찾았다. 작업 011 설계 2절 D2, D3
class _Pair extends StatelessWidget {
  const _Pair(this.label, this.value, {this.share = 0.7});
  final Widget label, value;

  /// 값 칸이 차지할 수 있는 폭의 몫. 혜택 줄은 "결제액 300,000 / 300,000 남음"처럼 값이 길어 이름이 세 줄로 꺾이지
  /// 않게 절반이다. 2026-10-04 에뮬레이터에서 찾았다
  final double share;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * share),
          child: value,
        ),
      ],
    ),
  );
}

/// 구간 눈금이 있는 실적 막대. 끝은 가장 높은 구간이다. 0.6초 동안 차오른다. 설계 2절 D1
class TierBar extends StatelessWidget {
  const TierBar({super.key, required this.tiers, required this.counted});
  final List<int> tiers;
  final int counted;

  @override
  Widget build(BuildContext context) {
    final top = tiers.last;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return SizedBox(
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: C.bg,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (counted / top).clamp(0, 1)),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Container(
                  width: w * v,
                  height: 8,
                  decoration: BoxDecoration(
                    color: C.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              for (final t in tiers) ...[
                if (t < top)
                  Positioned(
                    left: w * t / top - 1,
                    top: -2,
                    child: Container(width: 2, height: 12, color: C.line),
                  ),
                Positioned(
                  // 끝 구간 글자는 막대 끝에 오른쪽을 맞춘다
                  left: t < top ? w * t / top - 24 : null,
                  right: t < top ? null : 0,
                  top: 16,
                  width: t < top ? 48 : null,
                  child: Text(
                    man(t),
                    textAlign: t < top ? TextAlign.center : TextAlign.end,
                    style: const TextStyle(fontSize: 12, color: C.sub),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 혜택 한 줄. 남은 양 / 한도. 금액, 횟수, 결제액 한도 가운데 남은 비율이 가장 작은 것을 보인다. 먼저 끝나는 쪽이다.
/// 다 써도 0 아래로 내려가지 않는다. 이번 달이 아닌 한도는 기간을 앞에 붙인다
class _LimitRow extends StatelessWidget {
  const _LimitRow(this.l);
  final Limit l;

  // 이름 아래에 조건 한 줄을 둔다. 기간 한도가 없는 혜택은 오른쪽 값이 없다. 작업 011 설계 2절 D5
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Pair(
          Text(
            l.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: l.isShared ? FontWeight.w800 : FontWeight.w700,
              color: C.text,
            ),
          ),
          Text(
            _remain(l) ?? '',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: C.sub,
            ),
          ),
          share: l.isShared ? 0.7 : 0.5,
        ),
        if (l.condition case final c?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(c, style: const TextStyle(fontSize: 13, color: C.sub)),
          ),
      ],
    ),
  );
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

typedef Limit = ({
  String title,
  String key,
  String? per,
  int usedAmount,
  int? capAmount,
  int usedCount,
  int? capCount,
  int usedBase,
  int? capBase,
  List<String> shared,
  String? condition,
  bool isShared,
});

/// 남은 양 / 한도. 시안처럼 금액은 단위를 빼고, 횟수는 "회", 결제액 한도는 "결제액"을 붙인다. 작업 011 설계 2절 D3
String? _remain(Limit l) {
  final per = l.per == 'month' ? '' : '${_periods[l.per] ?? ''} ';
  final options = [
    if (l.capAmount != null) (l.capAmount!, l.usedAmount, '', ''),
    if (l.capCount != null) (l.capCount!, l.usedCount, '', '회'),
    if (l.capBase != null) (l.capBase!, l.usedBase, '결제액 ', ''),
  ];
  double share((int, int, String, String) o) =>
      o.$1 == 0 ? 0 : max(0, o.$1 - o.$2) / o.$1;
  if (options.isEmpty) return null;
  final o = options.reduce((a, b) => share(b) < share(a) ? b : a);
  return '$per${o.$3}${comma(max(0, o.$1 - o.$2))} / ${comma(o.$1)}${o.$4} 남음';
}
