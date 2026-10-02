/// 시안 보드 2 카드 추가와 등록 시트. 등록하면 true로 돌아간다
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../clock.dart' as clock;
import '../format.dart';
import '../theme.dart';

String cardLine(CardHit c) {
  final kind = c.kind == 'credit' ? '신용' : '체크';
  final fee = (c.annualFee ?? 0) == 0 ? '연회비 없음' : '연회비 ${man(c.annualFee!)}';
  final spend = c.tiers.isEmpty
      ? '실적 무관'
      : '실적 ${c.tiers.map((t) => man(t).replaceAll('만', '')).join('/')}만';
  return '$kind · $fee · $spend';
}

class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key, required this.api});
  final Api api;

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  late final Future<List<({String code, String name})>> _issuers = widget.api
      .issuers();
  late Future<List<CardHit>> _cards = widget.api.searchCards();
  String _q = '';
  String? _issuer;
  Timer? _wait;

  void _search() => setState(() {
    _cards = widget.api.searchCards(q: _q, issuer: _issuer);
  });

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  Future<void> _pick(CardHit card) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RegisterSheet(api: widget.api, card: card),
    );
    if (added == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('카드 추가')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '카드 이름 검색. 예: Mr.Life, 나라사랑',
              prefixIcon: Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: r16,
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) {
              _q = v;
              _wait?.cancel();
              _wait = Timer(const Duration(milliseconds: 250), _search);
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: FutureBuilder(
            future: _issuers,
            builder: (context, snap) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final (code, name) in [
                  (null, '전체'),
                  for (final i in snap.data ?? []) (i.code, i.name),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: _issuer == code,
                      onSelected: (_) {
                        _issuer = code;
                        _search();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _cards,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('카드 목록을 불러오지 못했어요.'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.data!.isEmpty) {
                return const Center(
                  child: Text('찾는 카드가 없어요.', style: TextStyle(color: C.sub)),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  for (final c in snap.data!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: r16,
                        child: ListTile(
                          minTileHeight: 64,
                          shape: const RoundedRectangleBorder(
                            borderRadius: r16,
                          ),
                          title: Text(
                            c.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: C.text,
                            ),
                          ),
                          subtitle: Text(
                            cardLine(c),
                            style: const TextStyle(color: C.sub),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: C.faint,
                          ),
                          onTap: () => _pick(c),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
            onPressed: () => notReady(context, '카메라 인식'),
            child: const Text('카메라로 카드 인식'),
          ),
        ),
      ],
    ),
  );
}

class RegisterSheet extends StatefulWidget {
  const RegisterSheet({
    super.key,
    required this.api,
    required this.card,
    this.today,
  });
  final Api api;
  final CardHit card;

  /// 테스트에서 날짜를 정한다
  final DateTime? today;

  @override
  State<RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends State<RegisterSheet> {
  late Future<Preview> _preview = widget.api.preview(widget.card.id);
  int? _prev;
  bool _isNew = false;
  int _monthsAgo = 0;
  bool _busy = false;
  Timer? _wait;

  DateTime? get _startedOn {
    if (!_isNew) return null;
    // 달 경계는 한국 시간이다. 폰이 다른 나라 시간이어도 한국 날짜로 센다. E7
    final now =
        widget.today ?? clock.now().toUtc().add(const Duration(hours: 9));
    return DateTime(now.year, now.month - _monthsAgo);
  }

  void _refresh() => setState(() {
    _preview = widget.api.preview(
      widget.card.id,
      prev: _prev,
      startedOn: _startedOn,
    );
  });

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() => _busy = true);
    try {
      await widget.api.addCard(
        widget.card.id,
        prev: _prev,
        startedOn: _startedOn,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      final text = e.status == 409 ? '이미 등록한 카드예요.' : '등록하지 못했어요.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('등록하지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    // 키보드와 아래 시스템 막대에 등록 버튼이 가리지 않게 한다
    padding: EdgeInsets.fromLTRB(
      20,
      24,
      20,
      16 +
          MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).viewPadding.bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.card.name} 등록',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: C.text,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '지난달 이 카드로 쓴 금액',
            style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
          ),
          const SizedBox(height: 4),
          const Text(
            '대략 적으면 이번 달 혜택 구간을 바로 계산해요. 모르면 비워 두세요.',
            style: TextStyle(fontSize: 13, color: C.sub),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('prev'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: const InputDecoration(
              suffixText: '원',
              hintText: '예: 410000',
            ),
            onChanged: (v) {
              _prev = int.tryParse(v);
              _wait?.cancel();
              _wait = Timer(const Duration(milliseconds: 300), _refresh);
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder(
            future: _preview,
            builder: (context, snap) => Box(
              color: C.blueSoft,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: _PreviewText(snap.data),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '최근 두 달 안에 새로 받은 카드인가요?',
            style: TextStyle(fontWeight: FontWeight.w700, color: C.text),
          ),
          const SizedBox(height: 4),
          const Text(
            '새 카드는 실적이 모자라도 혜택을 주는 기간이 있어요. 예를 고르면 받은 달을 물어요.',
            style: TextStyle(fontSize: 13, color: C.sub),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('아니요')),
              ButtonSegment(value: true, label: Text('예')),
            ],
            selected: {_isNew},
            onSelectionChanged: (v) {
              _isNew = v.first;
              _refresh();
            },
          ),
          if (_isNew) ...[
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('이번 달')),
                ButtonSegment(value: 1, label: Text('지난달')),
              ],
              selected: {_monthsAgo},
              onSelectionChanged: (v) {
                _monthsAgo = v.first;
                _refresh();
              },
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _register,
            child: const Text('등록'),
          ),
        ],
      ),
    ),
  );
}

class _PreviewText extends StatelessWidget {
  const _PreviewText(this.p);
  final Preview? p;

  @override
  Widget build(BuildContext context) {
    final p = this.p;
    if (p == null || p.tier == null) return const Text(' ');
    final tier = p.tier!;
    final head = switch (p) {
      _ when p.tiers.isEmpty => '실적과 상관없이 혜택을 받아요',
      _ when p.tierSource == 'new_card' => '새 카드라 이번 달은 ${man(tier)} 구간이 적용돼요',
      // 0원 구간에서도 받는 혜택이 있는 카드는 "구간 전"이라 하지 않는다
      _ when tier == 0 && p.benefits.isNotEmpty =>
        '이번 달은 기본 혜택만 받아요. ${man(p.tiers.first)}부터 더 받아요',
      _ when tier == 0 => '이번 달은 혜택 구간 전이에요. ${man(p.tiers.first)}부터 받아요',
      _ => '이번 달은 ${man(tier)} 구간이 적용돼요',
    };
    final b = p.benefits;
    final more = b.length > 2 ? ' 외 ${b.length - 2}개' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          head,
          style: const TextStyle(fontWeight: FontWeight.w700, color: C.blue),
        ),
        if (b.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${b.take(2).join(', ')}$more',
            style: const TextStyle(fontSize: 13, color: C.sub),
          ),
        ],
      ],
    );
  }
}
