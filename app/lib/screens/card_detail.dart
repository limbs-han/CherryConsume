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
  bool _lockedOpen = false;

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
    // 함께 쓰는 한도 상자. 같은 혜택들이 쓰는 한도는 한 상자에 두고 제목을 한 번만 쓴다. 놀이공원 할인의 월 1회와 연
    // 2회다. 다른 상자 혜택의 일부만 쓰는 한도는 그 상자 안의 흰 상자다. KB Easy all의 해외·면세점 한도가 통합 한도
    // 안에 든다. 혜택은 자기가 쓰는 상자 가운데 가장 작은 상자에 둔다. 2026-10-05 실제 폰에서 한 상자가 비거나 같은
    // 제목이 겹쳐 보여 고쳤다. 작업 011 설계 2절 D3, D5, F7, F8
    final groups = <String, List<Limit>>{};
    final members = <String, Set<String>>{};
    for (final l in d.limits) {
      if (!l.isShared) continue;
      final users = {
        for (final b in d.limits)
          if (!b.isShared && b.shared.contains(l.key)) b.key,
      };
      final id = (users.toList()..sort()).join('|');
      (groups[id] ??= []).add(l);
      members[id] = users;
    }
    String? smallest(Iterable<String> ids) => ids.isEmpty
        ? null
        : ids.reduce(
            (a, b) => members[a]!.length <= members[b]!.length ? a : b,
          );
    final parent = {
      for (final g in groups.keys)
        g: smallest([
          for (final h in groups.keys)
            if (members[h]!.length > members[g]!.length &&
                members[h]!.containsAll(members[g]!))
              h,
        ]),
    };
    String? boxOf(Limit l) => l.isShared
        ? null
        : smallest([
            for (final g in groups.keys)
              if (members[g]!.contains(l.key)) g,
          ]);
    final each = [
      for (final l in d.limits)
        if (!l.isShared && boxOf(l) == null) l,
    ];
    Widget sharedBox(String g, int depth) => Container(
      margin: EdgeInsets.only(top: depth > 0 ? 4 : 0, bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: depth > 0 ? 12 : 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: depth.isEven ? C.grey : Colors.white,
        borderRadius: BorderRadius.circular(depth > 0 ? 12 : 16),
      ),
      child: Column(
        children: [
          for (final (i, l) in groups[g]!.indexed) _LimitRow(l, title: i == 0),
          for (final l in d.limits)
            if (boxOf(l) == g) _LimitRow(l),
          for (final h in groups.keys)
            if (parent[h] == g) sharedBox(h, depth + 1),
        ],
      ),
    );
    // 못 받는 혜택을 필요한 구간마다 묶는다. 낮은 구간부터다
    final lockedByTier =
        <int, List<({String title, int requiredTier, int remaining})>>{};
    for (final l in d.locked) {
      (lockedByTier[l.requiredTier] ??= []).add(l);
    }
    final lockedTiers = lockedByTier.keys.toList()..sort();
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
      if (d.limits.isNotEmpty) ...[
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
              for (final g in groups.keys)
                if (parent[g] == null) sharedBox(g, 0),
              for (final l in each) _LimitRow(l),
            ],
          ),
        ),
      ],
      // 구간이 모자라 아직 못 받는 혜택은 이번 달 혜택과 따로 접어 둔다. 섞여 있으면 정보가 너무 많다. 금액은 그 구간까지
      // 남은 실적이다. 2026-10-05 사용자가 실제 폰에서 정했다. E37, 작업 011 설계 2절 F3, F4
      if (d.locked.isNotEmpty) ...[
        const SizedBox(height: 12),
        Box(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                expanded: _lockedOpen,
                child: Pressable(
                  onTap: () => setState(() => _lockedOpen = !_lockedOpen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '구간이 모자라 아직 못 받는 혜택',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: C.text,
                            ),
                          ),
                        ),
                        Text(
                          '${d.locked.length}개',
                          style: const TextStyle(fontSize: 15, color: C.sub),
                        ),
                        Icon(
                          _lockedOpen ? Icons.expand_less : Icons.expand_more,
                          color: C.faint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 같은 구간의 혜택은 남은 금액이 같아 구간마다 머리줄에 한 번만 쓰고 아래에 이름만 둔다. 줄마다 "29.6만 더"가
              // 되풀이되어 어색했다. 2026-10-05 사용자가 골랐다. 작업 011 설계 2절 F4
              if (_lockedOpen)
                for (final tier in lockedTiers) ...[
                  Text.rich(
                    lockedByTier[tier]!.first.remaining > 0
                        ? TextSpan(
                            children: [
                              TextSpan(text: '${man(tier)} 구간까지 '),
                              TextSpan(
                                text: _left(
                                  lockedByTier[tier]!.first.remaining,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: C.amber,
                                ),
                              ),
                              const TextSpan(text: ' 남았어요'),
                            ],
                          )
                        : TextSpan(text: '${man(tier)} 구간 실적을 채웠어요'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: C.text,
                    ),
                  ),
                  const Text(
                    '다음 달부터 받아요',
                    style: TextStyle(fontSize: 13, color: C.faint),
                  ),
                  const SizedBox(height: 6),
                  for (final l in lockedByTier[tier]!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '·  ',
                            style: TextStyle(fontSize: 14, color: C.faint),
                          ),
                          Expanded(
                            child: Text(
                              l.title,
                              style: const TextStyle(
                                fontSize: 14,
                                color: C.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
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
            // 설정처럼 줄마다 답하기 배지와 화살표이고 누르면 바닥 시트에서 고른다. 작업 011 설계 2절 T3
            for (final q in d.facts) ...[
              const Divider(height: 1, color: C.line),
              FactRow(
                q: q,
                onAnswer: (v) => _answer({
                  'facts': {q.key: v},
                }),
              ),
            ],
            for (final q in d.options) ...[
              const Divider(height: 1, color: C.line),
              OptionRow(
                q: q,
                onAnswer: (c) => _answer({
                  'options': {q.key: c},
                }),
              ),
            ],
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

/// 남은 금액. 1만 원부터는 "29.6만 원", 아래는 "5,000원"이다
String _left(int n) => n >= 10000 ? '${man(n)} 원' : won(n);

/// 막대가 찬 몫. 눈금을 같은 간격으로 두고 눈금 사이에서는 금액 비율대로 찬다. 구간 0은 막대 시작이다. 작업 011 설계 2절 F2
double tierFill(List<int> tiers, int counted) {
  var low = 0;
  for (final (i, t) in tiers.indexed) {
    if (counted < t) return (i + (counted - low) / (t - low)) / tiers.length;
    low = t;
  }
  return 1;
}

/// 구간 눈금이 있는 실적 막대. 끝은 가장 높은 구간이다. 0.6초 동안 차오른다. 설계 2절 D1
///
/// 눈금은 금액 비율이 아니라 같은 간격이다. 비율대로 두면 IBK 나라사랑의 20만과 25만처럼 가까운 구간의 글자가 겹쳤고,
/// 겹친 글자를 아랫줄로 내린 것도 이상했다. 2026-10-05 사용자가 골랐다. 작업 011 설계 2절 F2
class TierBar extends StatelessWidget {
  const TierBar({super.key, required this.tiers, required this.counted});
  final List<int> tiers;
  final int counted;

  @override
  Widget build(BuildContext context) {
    final n = tiers.length;
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(const TextStyle(fontSize: 12, color: C.sub));
    // 끝 구간 글자도 눈금 가운데에 두려고 막대를 그 글자 폭의 절반만큼 줄인다. 끝에 오른쪽을 맞추면 끝 글자가 안으로
    // 당겨져 앞 글자와 붙었다
    final half =
        (TextPainter(
          text: TextSpan(text: man(tiers.last), style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout()).width /
        2;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth - half;
        final slot = w / n;
        return SizedBox(
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: w,
                height: 8,
                decoration: BoxDecoration(
                  color: C.bg,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: tierFill(tiers, counted)),
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
              for (final (i, t) in tiers.indexed) ...[
                if (i < n - 1)
                  Positioned(
                    left: slot * (i + 1) - 1,
                    top: -2,
                    child: Container(width: 2, height: 12, color: C.line),
                  ),
                // 글자는 제 크기로 눈금 가운데에 둔다
                Positioned(
                  left: slot * (i + 1),
                  top: 16,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, 0),
                    child: Text(man(t), style: style),
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
  const _LimitRow(this.l, {this.title = true});
  final Limit l;

  /// 한 상자에 함께 쓰는 한도 줄이 여럿이면 첫 줄만 이름을 쓴다
  final bool title;

  // 이름 아래에 조건 한 줄을 둔다. 기간 한도가 없는 혜택은 오른쪽 값이 없다. 작업 011 설계 2절 D5
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Pair(
          Text(
            title ? l.title : '',
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
