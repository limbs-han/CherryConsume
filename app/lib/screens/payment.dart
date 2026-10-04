/// 시안 보드 4 결제 기록. 금액, 가게, 카드만 받고 나머지는 채워 한 줄로 접는다. S3
/// 저장하면 혜택이 바뀐 다른 결제 수로 돌아간다
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../clock.dart' as clock;
import '../format.dart';
import '../theme.dart';
import '../ui.dart';

String two(int n) => n.toString().padLeft(2, '0');

/// 홈, 추천, 기록 탭의 결제 기록 버튼. 지금 가진 카드가 없으면 보이지 않는다. 작업 011 설계 2절 G6
/// 저장하면 onSaved로 그 탭을 다시 불러오고, 다른 결제를 다시 계산했으면 알린다
class PayButton extends StatefulWidget {
  const PayButton({super.key, required this.api, required this.onSaved});
  final Api api;
  final VoidCallback onSaved;

  @override
  State<PayButton> createState() => _PayButtonState();
}

class _PayButtonState extends State<PayButton> {
  late final Future<Home> _home = widget.api.home();

  Future<void> _pay(List<HomeCard> cards) async {
    final repriced = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          api: widget.api,
          cards: [for (final c in cards) (id: c.id, name: c.name)],
        ),
      ),
    );
    if (repriced == null || !mounted) return;
    widget.onSaved();
    if (repriced > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다른 결제 $repriced건의 혜택도 다시 계산했어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _home,
    builder: (context, snap) {
      final cards = snap.data?.cards ?? const <HomeCard>[];
      if (cards.isEmpty) return const SizedBox.shrink();
      return FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _pay(cards),
        icon: const Icon(Icons.add),
        label: const Text('결제 기록'),
      );
    },
  );
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.api,
    required this.cards,
    this.initial,
    this.editing,
  });
  final Api api;
  final List<({String id, String name})> cards;

  /// 기록에서 열면 고치는 결제다. 저장은 고치기이고 취소 기록과 지우기를 할 수 있다. S8
  final RecordRow? editing;

  /// 추천 결과에서 열면 가게, 금액, 카드, 업종, 추천 요청이 채워져 있다. S4
  final PaymentInput? initial;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late final _input = widget.initial ?? PaymentInput();

  /// 고치기와 추천에서 연 결제는 처음 금액을 쉼표로 채운다
  late final _amountText = TextEditingController(
    text: _input.amount == null ? '' : comma(_input.amount!),
  );
  late final Future<List<Category>> _categories = widget.api.categories();
  late final Future<Map<String, String>> _methods = widget.api.paymentMethods();
  Draft? _draft;
  bool _busy = false;

  /// 입력이 0.3초 멈추면 다시 계산한다
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _wait?.cancel();
    _amountText.dispose();
    super.dispose();
  }

  void _changed() {
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _refresh() async {
    try {
      final d = await widget.api.draft(_input, editing: widget.editing?.id);
      if (mounted) setState(() => _draft = d);
    } catch (_) {
      // 저장 전 계산이 실패해도 입력은 계속 받는다. 저장할 때 다시 알린다
    }
  }

  String? get _cardId => _input.userCardId ?? _draft?.pick;

  Future<void> _save() async {
    setState(() => _busy = true);
    _wait?.cancel();
    try {
      // 마지막 입력으로 다시 계산한 1순위로 저장한다. 0.3초 전의 응답을 쓰면 고치기 전 가게의 카드로 저장될 수 있었다
      // 업종과 채널은 사용자가 바꾸기에서 고른 것만 보낸다. 나머지는 저장소가 가게 이름으로 채운다
      final shown = _cardId;
      final d = await widget.api.draft(_input, editing: widget.editing?.id);
      if (!mounted) return;
      if (_input.userCardId == null && d.pick != shown) {
        // 사용자가 본 카드와 다른 카드로 저장하지 않는다. 화면을 바꾸고 다시 누르게 한다
        setState(() => _draft = d);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가장 이득인 카드가 바뀌었어요. 확인하고 다시 저장해 주세요.')),
        );
        return;
      }
      _input
        ..userCardId ??= d.pick
        ..paidAt ??= clock.now();
      final editing = widget.editing;
      final saved = editing == null
          ? await widget.api.savePayment(_input)
          : await widget.api.editPayment(editing.id, _input);
      var repriced = saved.repriced;
      final code = await _askCategory(saved);
      if (code != null) {
        // 자식 업종을 답하면 그 결제만 다시 계산한다. E47, E50. 결제는 이미 저장됐으니 고치기가 실패해도 화면을 닫는다.
        // 남겨 두면 다시 눌러 같은 결제가 두 건이 된다
        _input.category = code;
        try {
          repriced += (await widget.api.editPayment(saved.id, _input)).repriced;
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('저장했지만 업종은 고치지 못했어요. 기록에서 고쳐 주세요.')),
            );
          }
        }
      }
      if (mounted) Navigator.of(context).pop(repriced);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 업종이 부모까지만 있어 혜택을 가리지 못하면 저장한 자리에서 한 번 묻는다. 모르면 닫는다. E47
  Future<String?> _askCategory(Saved saved) async {
    if (saved.askChildren.isEmpty || !mounted) return null;
    final shown = _input.merchantName.isEmpty ? '이 결제' : _input.merchantName;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$shown은 ${saved.askParent} 가운데 어느 쪽인가요'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 칩은 알약이다. 작업 011 설계 2절 T2
            for (final c in saved.askChildren)
              ChoicePill(
                c.name,
                selected: false,
                onTap: () => Navigator.pop(context, c.code),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('모르겠어요'),
          ),
        ],
      ),
    );
  }

  /// 카드사에서 이번에 취소된 금액과 날짜를 적는다. 지금까지의 합에 더해 보낸다. 결제를 지우지 않고 남은 금액으로
  /// 다시 계산한다. 이미 적은 취소는 지울 수 있다. E5
  Future<void> _cancel() async {
    final e = widget.editing!;
    final text = TextEditingController();
    // 날짜는 늘 오늘에서 시작한다. 옛 취소일로 채우면 다른 달에 더 취소된 금액이 옛 달로 조용히 들어간다
    final today = DateUtils.dateOnly(clock.now());
    final first = DateUtils.dateOnly(e.paidAt);
    final last = first.isAfter(today) ? first : today;
    var day = last;
    final before = e.cancelledAt;
    final picked = await showDialog<(int, DateTime)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('이번에 취소된 금액'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.cancelledAmount > 0 && before != null)
                Text(
                  '지금까지 ${won(e.cancelledAmount)} 취소 · ${before.month}월 ${before.day}일',
                  style: const TextStyle(color: C.sub),
                ),
              // 취소 금액도 쉼표를 넣는 금액 칸이다. 작업 011 설계 1절 원칙 6
              AmountField(
                key: const Key('cancel-amount'),
                controller: text,
                maxDigits: 9,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('취소한 날 ${day.month}월 ${day.day}일')),
                  TextButton(
                    key: const Key('cancel-day'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: first,
                        lastDate: last,
                      );
                      if (d != null) setDialog(() => day = d);
                    },
                    child: const Text('바꾸기'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            if (e.cancelledAmount > 0)
              TextButton(
                key: const Key('cancel-undo'),
                onPressed: () => Navigator.pop(context, (0, day)),
                child: const Text('취소 기록 지우기'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () {
                final n = amountOf(text.text);
                Navigator.pop(context, n == null || n <= 0 ? null : (n, day));
              },
              child: const Text('기록'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final (added, on) = picked;
    final total = added == 0 ? 0 : e.cancelledAmount + added;
    // 고른 날의 한국 시간 23:59로 적는다. 실적의 달은 한국 시간으로 가른다. E7. 지금보다 뒤면 지금, 결제보다 앞서면
    // 결제 시각이다
    var at = DateTime.utc(on.year, on.month, on.day, 14, 59);
    final now = clock.now();
    if (at.isAfter(now)) at = now;
    if (at.isBefore(e.paidAt)) at = e.paidAt;
    try {
      final repriced = await widget.api.cancelPayment(e.id, total, at);
      if (mounted) Navigator.of(context).pop(repriced);
    } on ApiError catch (err) {
      if (!mounted) return;
      // 취소 시각은 하나라 다른 달에 더 취소된 금액은 담지 못한다. 저장소가 422로 막는다. 위험 검토 5번
      final otherMonth = err.status == 422 && err.body.contains('다른 달');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            otherMonth ? '다른 달에 더 취소된 금액은 아직 담지 못해요.' : '취소를 기록하지 못했어요.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('취소를 기록하지 못했어요.')));
      }
    }
  }

  /// 결제를 지운다. 되돌릴 수 없어 한 번 더 묻는다. S8
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 결제를 지울까요?'),
        content: const Text('지우면 실적과 받은 혜택에서 빠져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final repriced = await widget.api.deletePayment(widget.editing!.id);
      if (mounted) Navigator.of(context).pop(repriced);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지우지 못했어요.')));
      }
    }
  }

  Future<void> _editDetails() async {
    final d = _draft;
    if (d == null) return;
    final categories = await _categories;
    final methods = await _methods;
    if (!mounted) return;
    _input
      ..category ??= d.category
      ..channel ??= d.channel
      ..paidAt ??= d.paidAt
      ..paymentMethod ??= d.estimate?.paymentMethod
      ..billing ??= d.billing;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetailsSheet(
        input: _input,
        categories: categories,
        methods: methods,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final est = d?.estimate;
    final top = d != null && d.ranking.isNotEmpty ? d.ranking.first : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? '결제 기록' : '결제 고치기'),
        actions: [
          if (widget.editing != null)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'cancel' ? _cancel() : _delete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cancel', child: Text('취소 기록')),
                PopupMenuItem(value: 'delete', child: Text('지우기')),
              ],
            ),
        ],
      ),
      // 저장은 아래에 고정해 키보드와 아래 막대에 가리지 않는다. 작업 011 설계 1절 원칙 1, 2절 Z2
      body: WithAction(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        action: FilledButton(
          onPressed: _busy || (_input.amount ?? 0) <= 0 || _cardId == null
              ? null
              : _save,
          child: const Text('저장'),
        ),
        children: [
          const _Label('얼마 썼나요'),
          // 시안대로 44 크기에 쉼표를 넣고, 열면 바로 금액을 친다. 작업 011 설계 1절 원칙 6, 2절 P1
          AmountField(
            key: const Key('amount'),
            controller: _amountText,
            size: 44,
            autofocus: true,
            maxDigits: 9,
            onChanged: (v) {
              _input.amount = v;
              _changed();
            },
          ),
          const SizedBox(height: 20),
          const _Label('어디서요'),
          // 가게를 찾는 칸이라 시안대로 돋보기가 있는 흰 상자다. 설계 2절 P2
          TextFormField(
            key: const Key('merchant'),
            initialValue: _input.merchantName,
            style: const TextStyle(fontSize: 16, color: C.text),
            decoration: const InputDecoration(
              hintText: '가게 이름',
              prefixIcon: Icon(Icons.search, color: C.sub),
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: r16,
                borderSide: BorderSide(color: C.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: r16,
                borderSide: BorderSide(color: C.blue, width: 1.5),
              ),
            ),
            onChanged: (v) {
              _input
                ..merchantName = v.trim()
                ..category = null
                ..channel = null
                ..billing = null;
              _changed();
            },
          ),
          const SizedBox(height: 20),
          const _Label('어느 카드로요'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.cards)
                ChoicePill(
                  c.name,
                  selected: _cardId == c.id,
                  onTap: () {
                    setState(() => _input.userCardId = c.id);
                    _refresh();
                  },
                ),
            ],
          ),
          if (_input.userCardId == null && top != null && top.value > 0) ...[
            const SizedBox(height: 8),
            // 시안대로 체크와 파란 굵은 글자다. 설계 2절 P4
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check, size: 18, color: C.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '이 가게에선 ${top.name}가 가장 이득이라 골라 뒀어요',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: C.blue,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (est != null)
            Box(
              color: C.greenSoft,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '예상 혜택',
                          style: TextStyle(fontSize: 13, color: C.sub),
                        ),
                        if (est.titles.isNotEmpty)
                          Text(
                            est.titles.join(', '),
                            style: const TextStyle(fontSize: 13, color: C.sub),
                          ),
                      ],
                    ),
                  ),
                  if (!est.counted) ...[
                    const Pill('실적 제외', fg: C.sub, bg: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    won(est.value),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: C.green,
                    ),
                  ),
                ],
              ),
            ),
          if (d != null) ...[
            const SizedBox(height: 12),
            Box(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FutureBuilder(
                      future: _methods,
                      builder: (context, snap) => _Summary(
                        draft: d,
                        input: _input,
                        methods: snap.data ?? {},
                      ),
                    ),
                  ),
                  TextButton(onPressed: _editDetails, child: const Text('바꾸기')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
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

/// "자동으로 채웠어요" 한 줄. 업종, 시각, 채널, 할부, 결제수단
class _Summary extends StatelessWidget {
  const _Summary({
    required this.draft,
    required this.input,
    required this.methods,
  });
  final Draft draft;
  final PaymentInput input;
  final Map<String, String> methods;

  @override
  Widget build(BuildContext context) {
    final at = input.paidAt ?? draft.paidAt;
    final now = clock.now();
    final day =
        at.year == now.year && at.month == now.month && at.day == now.day
        ? '오늘'
        : '${at.month}월 ${at.day}일';
    final channel = (input.channel ?? draft.channel) == 'online'
        ? '온라인'
        : '오프라인';
    final months = input.installmentMonths == 1
        ? '일시불'
        : '${input.installmentMonths}개월 ${input.interestFree ? '무이자' : '할부'}';
    final region = input.overseas ? ' · 해외' : '';
    final billing = [
      for (final (key, name) in billings)
        if (key == (input.billing ?? draft.billing) && key != 'normal')
          ' · $name',
    ].join();
    final method =
        methods[input.paymentMethod ?? draft.estimate?.paymentMethod] ?? '실물카드';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('자동으로 채웠어요', style: TextStyle(fontSize: 12, color: C.faint)),
        const SizedBox(height: 2),
        Text(
          // 찾은 가맹점을 보여 별칭이 다른 가게에 걸렸으면 사용자가 알아보게 한다
          '${draft.merchantDisplay == null ? '' : '${draft.merchantDisplay} · '}${draft.categoryName ?? '업종 미정'} · $day ${two(at.hour)}:${two(at.minute)}',
          style: const TextStyle(fontSize: 14, color: C.text),
        ),
        Text(
          '$channel · $months · $method$region$billing',
          style: const TextStyle(fontSize: 14, color: C.text),
        ),
      ],
    );
  }
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.input,
    required this.categories,
    required this.methods,
  });
  final PaymentInput input;
  final List<Category> categories;
  final Map<String, String> methods;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  PaymentInput get i => widget.input;

  Future<void> _pickTime() async {
    final at = i.paidAt ?? clock.now();
    final day = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(at.year - 1),
      lastDate: clock.now(),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (time == null) return;
    setState(
      () => i.paidAt = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parent = i.category?.split('.').first;
    final children = widget.categories
        .where((c) => c.code == parent)
        .expand((c) => c.children)
        .toList();
    // 확인은 시트 아래에 고정한다. 시트는 상태 표시줄 아래에서 멈춘다. 작업 011 설계 2절 Z1
    // 시트는 Scaffold 밖이라 키보드가 열려 있으면 그만큼 직접 올린다
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: WithAction(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        action: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('업종'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in widget.categories)
                    ChoicePill(
                      c.name,
                      selected: parent == c.code,
                      onTap: () => setState(() => i.category = c.code),
                    ),
                ],
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ch in children)
                      ChoicePill(
                        ch.name,
                        selected: i.category == ch.code,
                        onTap: () => setState(() => i.category = ch.code),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const _Label('결제 시각'),
              OutlinedButton(
                onPressed: _pickTime,
                child: Text(() {
                  final at = i.paidAt ?? clock.now();
                  return '${at.month}월 ${at.day}일 ${two(at.hour)}:${two(at.minute)}';
                }()),
              ),
              const SizedBox(height: 16),
              const _Label('어디서 결제했나요'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'offline', label: Text('오프라인')),
                  ButtonSegment(value: 'online', label: Text('온라인')),
                ],
                selected: {i.channel ?? 'offline'},
                onSelectionChanged: (v) => setState(() => i.channel = v.first),
              ),
              const SizedBox(height: 16),
              _PickRow(
                label: '할부',
                // 엑셀로 가져온 24개월처럼 고르는 줄에 없는 개월도 그대로 보인다. 위험 검토 1번
                options: [
                  for (final m in {
                    1,
                    2,
                    3,
                    4,
                    5,
                    6,
                    10,
                    12,
                    i.installmentMonths,
                  }.toList()..sort())
                    (m, m == 1 ? '일시불' : '$m개월'),
                ],
                value: i.installmentMonths,
                onPick: (v) => setState(() => i.installmentMonths = v),
              ),
              // 무이자할부는 혜택이나 실적에서 빼는 카드가 많다. 일시불이면 묻지 않는다
              if (i.installmentMonths > 1)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('무이자할부'),
                  value: i.interestFree,
                  onChanged: (v) => setState(() => i.interestFree = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('해외 결제'),
                value: i.overseas,
                onChanged: (v) => setState(() => i.overseas = v),
              ),
              const SizedBox(height: 16),
              _PickRow(
                label: '청구 방식',
                options: billings,
                value: i.billing ?? 'normal',
                onPick: (v) => setState(() => i.billing = v),
              ),
              _PickRow(
                label: '결제수단',
                options: [
                  for (final e in widget.methods.entries) (e.key, e.value),
                ],
                value: i.paymentMethod ?? 'physical_card',
                onPick: (v) => setState(() => i.paymentMethod = v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 이름, 고른 값, 화살표 한 줄. 누르면 바닥 시트에서 고른다. 드롭다운 대신이다. 작업 011 설계 1절 원칙 5, 2절 P5
class _PickRow<T> extends StatelessWidget {
  const _PickRow({
    required this.label,
    required this.options,
    required this.value,
    required this.onPick,
  });
  final String label;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final shown = options
        .firstWhere((o) => o.$1 == value, orElse: () => options.first)
        .$2;
    return Semantics(
      button: true,
      child: Pressable(
        key: Key('pick-$label'),
        onTap: () async {
          final v = await pickSheet<T>(
            context,
            title: label,
            options: options,
            selected: value,
          );
          if (v != null) onPick(v);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 15, color: C.sub),
                ),
              ),
              Text(
                shown,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: C.text,
                ),
              ),
              const Icon(Icons.chevron_right, color: C.faint),
            ],
          ),
        ),
      ),
    );
  }
}
