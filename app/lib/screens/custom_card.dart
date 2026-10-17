/// 카드 직접 만들기. 시작 방식, 기본과 실적과 혜택 줄, 혜택 한 줄 시트. 작업 019 설계 2절, S13, S14
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../store/custom.dart' show benefitTitle, otherIssuer, rateShape;
import '../theme.dart';
import '../ui.dart';
import 'add_card.dart';

typedef Input = Map<String, Object?>;

/// 비슷한 카드에서 시작하거나 처음부터 만든다. 만들고 등록까지 마치면 참을 돌려준다
class CustomStartScreen extends StatelessWidget {
  const CustomStartScreen({super.key, required this.api});
  final Api api;

  Future<void> _go(BuildContext context, Input input) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomFormScreen(api: api, input: input),
      ),
    );
    if (added == true && context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _similar(BuildContext context) async {
    final card = await Navigator.of(context).push<CardHit>(
      MaterialPageRoute(
        builder: (_) => AddCardScreen(api: api, pickOnly: true),
      ),
    );
    if (card == null || !context.mounted) return;
    final input = await api.startFrom(card.id);
    if (context.mounted) await _go(context, input);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('카드 직접 만들기')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          '어떻게 만들까요',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Box(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              TapRow(
                title: '비슷한 카드에서 시작',
                sub: '혜택과 실적 규칙을 가져와 고쳐요',
                onTap: () => _similar(context),
              ),
              const Divider(height: 1, color: C.line),
              TapRow(
                title: '처음부터 만들기',
                sub: '모든 결제를 실적에 넣어요',
                onTap: () => _go(context, {
                  'issuer': null,
                  'name': '',
                  'kind': 'credit',
                  'annual_fee': null,
                  'tiers': <int>[],
                  'benefits': <Input>[],
                  'copied': <String>[],
                }),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 기본, 실적, 혜택 줄. editing이 있으면 고치기다. 만들면 등록 시트로 잇고 참을, 고치면 다시 계산한 결제 수를 돌려준다
class CustomFormScreen extends StatefulWidget {
  const CustomFormScreen({
    super.key,
    required this.api,
    required this.input,
    this.editing,
  });
  final Api api;
  final Input input;
  final String? editing;

  @override
  State<CustomFormScreen> createState() => _CustomFormScreenState();
}

class _CustomFormScreenState extends State<CustomFormScreen> {
  late final Input _in = widget.input;
  late String? _issuer = _in['issuer'] as String?;
  late String _kind = _in['kind'] as String? ?? 'credit';
  late final _name = TextEditingController(text: _in['name'] as String? ?? '');
  late final _fee = TextEditingController(
    text: _in['annual_fee'] == null ? '' : comma(_in['annual_fee'] as int),
  );
  late final _tiers = [
    for (var i = 0; i < 3; i++)
      TextEditingController(
        text: i < (_in['tiers'] as List).length
            ? comma((_in['tiers'] as List)[i] as int)
            : '',
      ),
  ];
  late final List<Input> _benefits = [
    for (final b in _in['benefits'] as List) Input.from(b as Map),
  ];
  late final List<String> _copied = [
    ...((_in['copied'] as List?) ?? const []).cast<String>(),
  ];
  late final List<String> _copiedTitles = [
    ...((_in['copied_titles'] as List?) ?? _copied).cast<String>(),
  ];
  late final Future<List<({String code, String name})>> _issuers = widget.api
      .issuers();
  late final Future<List<Category>> _categories = widget.api.categories();
  bool _busy = false;

  bool get _fromBase => _in['base_card_id'] != null;

  List<int> get _tierValues => [
    for (final c in _tiers)
      if (amountOf(c.text) case final int v when v > 0) v,
  ]..sort();

  @override
  void dispose() {
    for (final c in [_name, _fee, ..._tiers]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickIssuer() async {
    final list = await _issuers;
    if (!mounted) return;
    final picked = await pickSheet<String>(
      context,
      title: '카드사',
      options: [
        for (final i in list) (i.code, i.name),
        (otherIssuer['id']!, otherIssuer['name']!),
      ],
      selected: _issuer,
    );
    if (picked != null) setState(() => _issuer = picked);
  }

  Future<void> _editBenefit([int? at]) async {
    final cats = await _categories;
    if (!mounted) return;
    final out = await showModalBottomSheet<Input>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BenefitSheet(
        categories: cats,
        tiers: _tierValues,
        initial: at == null ? null : _benefits[at],
      ),
    );
    if (out == null) return;
    setState(() => at == null ? _benefits.add(out) : _benefits[at] = out);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return _say('카드 이름을 적어 주세요');
    if (_issuer == null) return _say('카드사를 골라 주세요');
    final tiers = _tierValues;
    // 실적 구간을 지우면 그 구간이 필요한 혜택은 실적 무관이 되지 않게 막는다
    if (_benefits.any(
      (b) => b['from_tier'] != null && !tiers.contains(b['from_tier']),
    )) {
      return _say('혜택이 필요한 실적 구간이 없어요. 혜택을 다시 골라 주세요');
    }
    final input = <String, Object?>{
      'issuer': _issuer,
      'name': _name.text.trim(),
      'kind': _kind,
      'annual_fee': amountOf(_fee.text),
      'tiers': tiers,
      'benefits': _benefits,
      'copied': _copied,
      'base_card_id': _in['base_card_id'],
    };
    setState(() => _busy = true);
    try {
      if (widget.editing != null) {
        final n = await widget.api.updateCustom(widget.editing!, input);
        if (mounted) Navigator.of(context).pop(n);
        return;
      }
      final id = await widget.api.createCustom(input);
      final issuers = await _issuers;
      if (!mounted) return;
      final card = CardHit({
        'id': id,
        'name': input['name'],
        'issuer': _issuer,
        'issuer_name':
            issuers.where((i) => i.code == _issuer).firstOrNull?.name ??
            otherIssuer['name'],
        'kind': _kind,
        'annual_fee': input['annual_fee'],
        'tiers': tiers,
        'status': 'on_sale',
      });
      final added = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => RegisterSheet(api: widget.api, card: card),
      );
      if (mounted) Navigator.of(context).pop(added == true);
    } on ApiError catch (e) {
      _say(e.body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.editing == null ? '카드 직접 만들기' : '카드 고치기'),
    ),
    body: FutureBuilder(
      future: Future.wait([_issuers, _categories]),
      builder: (context, snap) {
        final issuers =
            snap.data?[0] as List<({String code, String name})>? ?? const [];
        final names = categoryNames(
          snap.data?[1] as List<Category>? ?? const [],
        );
        final issuerName = _issuer == null
            ? null
            : issuers.where((i) => i.code == _issuer).firstOrNull?.name ??
                  otherIssuer['name'];
        return WithAction(
          action: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.editing == null ? '만들고 등록' : '저장'),
          ),
          children: [
            Box(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TapRow(
                title: '카드사',
                trailing: RowValue(issuerName ?? '고르기'),
                onTap: _pickIssuer,
              ),
            ),
            const SizedBox(height: 20),
            const _Label('카드 이름'),
            TextField(
              key: const Key('custom-name'),
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(
                hintText: '예: 위시플러스',
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final (k, label) in const [
                  ('credit', '신용'),
                  ('check', '체크'),
                ]) ...[
                  ChoicePill(
                    label,
                    selected: _kind == k,
                    onTap: () => setState(() => _kind = k),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 20),
            const _Label('연회비'),
            AmountField(
              key: const Key('custom-fee'),
              controller: _fee,
              label: '연회비',
              hint: '없으면 비워 두세요',
              maxDigits: 8,
            ),
            const SizedBox(height: 20),
            const _Label('실적 구간'),
            Text(
              _fromBase ? '비슷한 카드의 구간을 따라요' : '최대 3개. 비우면 실적과 상관없는 카드예요',
              style: const TextStyle(fontSize: 13, color: C.sub),
            ),
            for (final (i, c) in _tiers.indexed)
              AmountField(
                key: Key('tier-$i'),
                controller: c,
                label: '실적 구간 ${i + 1}',
                hint: i == 0 ? '예: 300,000' : null,
                maxDigits: 9,
                enabled: !_fromBase,
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 24),
            const _Label('혜택'),
            for (final (i, b) in _benefits.indexed)
              _BenefitRow(
                title: benefitTitle(b, names),
                sub: benefitSub(b),
                onTap: () => _editBenefit(i),
                onDelete: () => setState(() => _benefits.removeAt(i)),
              ),
            for (final (i, title) in _copiedTitles.indexed)
              _BenefitRow(
                title: '복사한 혜택 · $title',
                sub: '고칠 수 없어요. 지우기만 할 수 있어요',
                grey: true,
                onDelete: () => setState(() {
                  _copied.removeAt(i);
                  _copiedTitles.removeAt(i);
                }),
              ),
            if (_benefits.length < 5)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _editBenefit(),
                  child: const Text('혜택 더하기'),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// 업종 code에서 이름으로. 자식 업종은 부모 code를 붙인 code다
Map<String, String> categoryNames(List<Category> cats) => {
  for (final c in cats) ...{
    c.code: c.name,
    for (final ch in c.children) ch.code: ch.name,
  },
};

/// 혜택 줄의 둘째 줄. "월 5,000원 · 30만부터"
String benefitSub(Input b) => [
  if (b['min_amount'] != null) '${won(b['min_amount'] as int)} 이상 결제',
  b['month_cap'] == null ? '한도 없음' : '월 ${won(b['month_cap'] as int)}',
  b['from_tier'] == null ? '실적 무관' : '${man(b['from_tier'] as int)}부터',
].join(' · ');

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

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.title,
    required this.sub,
    required this.onDelete,
    this.onTap,
    this.grey = false,
  });
  final String title, sub;
  final VoidCallback onDelete;
  final VoidCallback? onTap;
  final bool grey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Box(
      color: grey ? C.grey : Colors.white,
      padding: const EdgeInsets.only(left: 20),
      child: Row(
        children: [
          Expanded(
            child: TapRow(title: title, sub: sub, onTap: onTap),
          ),
          IconButton(
            tooltip: '지우기',
            onPressed: onDelete,
            icon: const Icon(Icons.close, color: C.sub),
          ),
        ],
      ),
    ),
  );
}

/// 혜택 한 줄. 대상, 방식, 크기, 최소 결제액, 월 한도, 필요한 구간. 작업 019 설계 2.4, 2.5
class BenefitSheet extends StatefulWidget {
  const BenefitSheet({
    super.key,
    required this.categories,
    required this.tiers,
    this.initial,
  });
  final List<Category> categories;
  final List<int> tiers;
  final Input? initial;

  @override
  State<BenefitSheet> createState() => _BenefitSheetState();
}

class _BenefitSheetState extends State<BenefitSheet> {
  late final Input? _i = widget.initial;
  late bool _all = _i?['all'] == true;
  late final List<String> _cats = [
    ...((_i?['categories'] as List?) ?? const []).cast<String>(),
  ];
  late String _type = _i?['type'] as String? ?? 'discount';
  late bool _won = _i?['fixed'] != null;
  late final _size = TextEditingController(
    text: _i?['rate']?.toString() ?? _i?['fixed']?.toString() ?? '',
  );
  late final _min = TextEditingController(
    text: _i?['min_amount'] == null ? '' : comma(_i!['min_amount'] as int),
  );
  late final _cap = TextEditingController(
    text: _i?['month_cap'] == null ? '' : comma(_i!['month_cap'] as int),
  );
  late int? _from = widget.tiers.contains(_i?['from_tier'])
      ? _i!['from_tier'] as int
      : null;
  String? _error;

  @override
  void dispose() {
    for (final c in [_size, _min, _cap]) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    String? error;
    final rate = num.tryParse(_size.text.trim());
    final fixed = amountOf(_size.text.trim());
    final min = amountOf(_min.text);
    if (!_all && _cats.isEmpty) {
      error = '대상을 골라 주세요';
    } else if (!_won &&
        (rate == null ||
            rate <= 0 ||
            rate > 100 ||
            !rateShape.hasMatch(_size.text.trim()))) {
      error = '%는 0보다 크고 100 이하, 소수 둘째 자리까지예요';
    } else if (_won && (fixed == null || fixed <= 0)) {
      error = '혜택 금액을 적어 주세요';
    } else if (_won && (min == null || min < fixed!)) {
      error = '최소 결제액은 혜택 금액 이상이어야 해요';
    }
    if (error != null) return setState(() => _error = error);
    Navigator.of(context).pop(<String, Object?>{
      if (_all) 'all': true else 'categories': _cats,
      'type': _type,
      if (_won) 'fixed': fixed else 'rate': rate,
      if (_won) 'min_amount': min,
      'month_cap': ?amountOf(_cap.text),
      'from_tier': ?_from,
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: WithAction(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        action: FilledButton(onPressed: _done, child: const Text('이 혜택 넣기')),
        children: [
          const Text(
            '혜택 한 줄',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          const _Label('대상 · 업종 3개까지'),
          Wrap(
            spacing: 8,
            children: [
              ChoicePill(
                '모든 가맹점',
                selected: _all,
                onTap: () => setState(() {
                  _all = !_all;
                  _cats.clear();
                }),
              ),
              for (final c in widget.categories)
                ChoicePill(
                  c.name,
                  selected: _cats.contains(c.code),
                  onTap: () => setState(() {
                    _all = false;
                    if (!_cats.remove(c.code) && _cats.length < 3) {
                      _cats.add(c.code);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _Label('방식'),
          Row(
            children: [
              for (final (k, label) in const [
                ('discount', '할인'),
                ('points', '적립'),
                ('cashback', '캐시백'),
              ]) ...[
                ChoicePill(
                  label,
                  selected: _type == k,
                  onTap: () => setState(() => _type = k),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const _Label('크기'),
          Row(
            children: [
              ChoicePill(
                '%',
                selected: !_won,
                onTap: () => setState(() => _won = false),
              ),
              const SizedBox(width: 8),
              ChoicePill(
                '원',
                selected: _won,
                onTap: () => setState(() => _won = true),
              ),
            ],
          ),
          Semantics(
            label: '혜택 크기',
            child: TextField(
              key: const Key('benefit-size'),
              controller: _size,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: _won ? '예: 5000' : '예: 10',
                suffixText: _won ? '원' : '%',
              ),
            ),
          ),
          if (_won) ...[
            const SizedBox(height: 8),
            AmountField(
              key: const Key('benefit-min'),
              controller: _min,
              label: '최소 결제액',
              hint: '최소 결제액',
              maxDigits: 9,
            ),
          ],
          const SizedBox(height: 16),
          const _Label('월 한도'),
          AmountField(
            key: const Key('benefit-cap'),
            controller: _cap,
            label: '월 한도',
            hint: '없으면 비워 두세요',
            maxDigits: 9,
          ),
          const SizedBox(height: 16),
          const _Label('필요한 실적'),
          Wrap(
            spacing: 8,
            children: [
              ChoicePill(
                '실적 무관',
                selected: _from == null,
                onTap: () => setState(() => _from = null),
              ),
              for (final t in widget.tiers)
                ChoicePill(
                  '${man(t)}부터',
                  selected: _from == t,
                  onTap: () => setState(() => _from = t),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: C.sub)),
          ],
        ],
      ),
    ),
  );
}
