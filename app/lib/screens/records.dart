/// 시안 보드 7 기록. 달마다 결제를 날짜별로 묶어 보인다. 누르면 고친다. S7, S8
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../ui.dart';
import 'import.dart';
import 'payment.dart';

const _days = ['월', '화', '수', '목', '금', '토', '일'];

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key, required this.api, this.card});
  final Api api;

  /// 카드 상세의 "이 카드 결제 보기"에서 열면 그 카드만 보인다
  final String? card;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  DateTime? _month;
  late String? _card = widget.card;
  late Future<Records> _records = _load();

  Future<Records> _load() => widget.api.records(month: _month, card: _card);

  void _reload() => setState(() {
    _records = _load();
  });

  void _shift(Records r, int n) {
    _month = DateTime(r.month.year, r.month.month + n);
    _reload();
  }

  Future<void> _open(Records r, RecordRow row) async {
    final cards = [
      ...r.cards,
      if (!r.cards.any((c) => c.id == row.userCardId))
        (id: row.userCardId, name: row.cardName),
    ];
    final repriced = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          api: widget.api,
          cards: cards,
          initial: row.toInput(),
          editing: row,
        ),
      ),
    );
    if (repriced == null) return;
    _reload();
    // 고치거나 지워 다음 달 구간이 바뀌면 그 달의 결제도 다시 계산한다. E54
    if (repriced > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다른 결제 $repriced건의 혜택도 다시 계산했어요.')),
      );
    }
  }

  /// 이용 내역 가져오기. 저장하면 가져온 건수를 알리고 다시 불러온다. S11
  Future<void> _import(Records r) async {
    final imported = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ImportScreen(api: widget.api, cards: r.cards),
      ),
    );
    if (imported == null || !mounted) return;
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('결제 $imported건을 가져왔어요.')));
  }

  /// 가져온 묶음과 되돌리기. 되돌렸으면 다시 불러온다. E34
  Future<void> _batches() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ImportsScreen(api: widget.api)),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _records,
    builder: (context, snap) {
      final r = snap.data;
      return Scaffold(
        // 작업 011 설계 2절 G6
        floatingActionButton: PayButton(
          key: ObjectKey(_records),
          api: widget.api,
          onSaved: _reload,
        ),
        appBar: AppBar(
          titleSpacing: rootTitleSpacing(context),
          title: const Text('기록'),
          actions: [
            IconButton(
              tooltip: '가져온 묶음',
              onPressed: r == null ? null : _batches,
              icon: const Icon(Icons.history),
            ),
            // 시안대로 오른쪽 위 테두리 버튼이다. 작업 011 설계 2절 Hi1
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: r == null ? null : () => _import(r),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.text,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: C.line),
                  shape: const RoundedRectangleBorder(borderRadius: r16),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.upload, size: 20),
                    SizedBox(width: 6),
                    Text('가져오기'),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: switch (snap) {
          AsyncSnapshot(hasError: true) => Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('기록을 불러오지 못했어요. 다시 시도'),
            ),
          ),
          AsyncSnapshot(hasData: false) => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '지난달',
                    onPressed: () => _shift(r!, -1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${r!.month.month}월',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    tooltip: '다음 달',
                    onPressed: () => _shift(r, 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  // 달 요약은 시안대로 같은 줄 오른쪽이다. 작업 011 설계 2절 Hi1
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${r.count}건 · ${_total(r.amount)}',
                          style: const TextStyle(fontSize: 13, color: C.sub),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          children: [
                            Text('혜택 ${won(r.benefitTotal)}', style: _benefit),
                            const Text(' · 추정', style: _benefit),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 한 줄로 가로로 민다. 목록이 이미 좌우 20 안이다. 작업 011 설계 2절 Z4, G2
              PillRow(
                inset: 0,
                children: [
                  ChoicePill(
                    '모든 카드',
                    selected: _card == null,
                    onTap: () {
                      _card = null;
                      _reload();
                    },
                  ),
                  for (final c in r.cards)
                    ChoicePill(
                      c.name,
                      selected: _card == c.id,
                      onTap: () {
                        _card = c.id;
                        _reload();
                      },
                    ),
                ],
              ),
              if (r.payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      '이 달에 적은 결제가 없어요.',
                      style: TextStyle(color: C.sub),
                    ),
                  ),
                ),
              for (final (day, rows) in _byDay(r.payments)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(
                    '${day.month}월 ${day.day}일 ${_days[day.weekday - 1]}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: C.sub,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    borderRadius: r20,
                    boxShadow: shadow,
                  ),
                  child: Material(
                    color: Colors.white,
                    borderRadius: r20,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, row) in rows.indexed) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                              color: C.line,
                            ),
                          _Row(row: row, onTap: () => _open(r, row)),
                        ],
                      ],
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

const _benefit = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w700,
  color: C.green,
);

/// 74.2만 원처럼 쓴다. 1만 원 아래는 원으로 쓴다
String _total(int n) {
  final m = man(n);
  return m.endsWith('원') ? m : '$m 원';
}

List<(DateTime, List<RecordRow>)> _byDay(List<RecordRow> rows) {
  final out = <(DateTime, List<RecordRow>)>[];
  for (final row in rows) {
    final day = DateTime(row.paidAt.year, row.paidAt.month, row.paidAt.day);
    if (out.isEmpty || out.last.$1 != day) out.add((day, []));
    out.last.$2.add(row);
  }
  return out;
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.onTap});
  final RecordRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = row.rewards.contains('points') ? '적립' : '할인';
    final net = row.amount - row.cancelledAmount;
    final cancelled = row.cancelledAmount > 0;
    // 시안대로 금액은 크고 굵게, 실적 제외 배지는 업종 줄 앞에 둔다. 작업 011 설계 2절 Hi2
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.merchantName ?? row.categoryName ?? '결제',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: C.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  won(net).replaceAll('원', ''),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: C.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!row.counted) ...[
                  const Pill('실적 제외', fg: C.sub, bg: C.grey),
                  const SizedBox(width: 6),
                ],
                if (cancelled) ...[
                  const Pill('취소', fg: C.sub, bg: C.grey),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    '${row.categoryName ?? '업종 미정'} · ${row.cardName} · '
                    '${row.timeKnown ? '${two(row.paidAt.hour)}:${two(row.paidAt.minute)}' : '시각 모름'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: C.sub),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  row.value > 0 ? '${won(row.value)} $kind' : '혜택 없음',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: row.value > 0 ? FontWeight.w700 : null,
                    color: row.value > 0 ? C.green : C.faint,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
