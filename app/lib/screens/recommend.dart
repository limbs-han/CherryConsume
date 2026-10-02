/// 시안 보드 5 추천과 5b 추천 결과. 결제 직전에 고를 카드만 알려 준다. S4
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import 'add_card.dart';
import 'card_detail.dart';
import 'payment.dart';
import 'settings.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key, required this.api});
  final Api api;

  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  late Future<(List<TopRow>, List<String>)> _data = _load();

  Future<(List<TopRow>, List<String>)> _load() async =>
      (await widget.api.top(), await widget.api.recentMerchants());

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _open({
    String? merchantName,
    String? category,
    String? title,
  }) async {
    final repriced = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          api: widget.api,
          merchantName: merchantName,
          category: category,
          title: title,
        ),
      ),
    );
    _reload();
    // 앞선 결제를 넣어 다른 결제가 다시 계산되면 알린다. E52, E53
    if ((repriced ?? 0) > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다른 결제 $repriced건의 혜택도 다시 계산했어요.')),
      );
    }
  }

  Future<void> _addCard() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddCardScreen(api: widget.api)),
    );
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('어디서 결제하세요?')),
    body: FutureBuilder(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: TextButton(
              onPressed: _reload,
              child: const Text('서버에 연결하지 못했어요. 다시 시도'),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (top, recent) = snap.data!;
        // E17. 카드가 없으면 추천할 것이 없다
        if (top.isEmpty) return _NoCards(onAdd: _addCard);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            TextField(
              key: const Key('search'),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '가게 이름이나 업종',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: r16,
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _open(merchantName: v.trim());
              },
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _Heading('최근 간 가게'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in recent)
                    ActionChip(
                      label: Text(name),
                      onPressed: () => _open(merchantName: name),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const _Heading('업종별 지금 1순위'),
            const Text(
              '1만 원 결제 기준 혜택. 가게마다 다른 할인은 가게를 고르면 보여요.',
              style: TextStyle(fontSize: 13, color: C.faint),
            ),
            const SizedBox(height: 8),
            // 누른 자리 물결이 보이게 흰 바탕을 Material로 칠한다
            Material(
              color: Colors.white,
              borderRadius: r20,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final t in top)
                    ListTile(
                      minTileHeight: 64,
                      title: Text(
                        t.categoryName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: C.text,
                        ),
                      ),
                      subtitle: Text(
                        t.row.value > 0
                            ? '${t.row.name} · ${t.row.title}'
                            : t.row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: C.sub),
                      ),
                      trailing: Text(
                        won(t.row.value),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: C.green,
                        ),
                      ),
                      onTap: () =>
                          _open(category: t.category, title: t.categoryName),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '이번 달 남은 한도와 적용 구간을 반영한 추정치예요.',
              style: TextStyle(fontSize: 13, color: C.faint),
            ),
          ],
        );
      },
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
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

class _NoCards extends StatelessWidget {
  const _NoCards({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Box(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '등록된 카드가 없어요',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: C.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '카드를 하나라도 등록하면 가게마다 가장 이득인 카드를 알려 드려요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.sub, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAdd, child: const Text('카드 추가')),
        ],
      ),
    ),
  );
}

/// 5b 추천 결과. 카드마다 순위, 혜택 금액, 이유 한 줄과 결제수단을 바꾸면 더 받는 금액
class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.api,
    this.merchantName,
    this.category,
    this.title,
  });
  final Api api;
  final String? merchantName, category, title;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late String? _category = widget.category;
  int? _amount;
  final _amountText = TextEditingController();
  late Future<RecResult> _result = _ask();
  late final Future<List<Category>> _categories = widget.api.categories();

  Future<RecResult> _ask() => widget.api.recommend(
    merchantName: widget.merchantName,
    category: _category,
    amount: _amount,
  );

  void _refresh() => setState(() {
    _result = _ask();
  });

  @override
  void dispose() {
    _amountText.dispose();
    super.dispose();
  }

  /// 답하면 더 받는 질문을 누르면 답하는 곳으로 간다. 사람 사실은 설정, 나머지는 카드 상세다. 돌아오면 답이 바뀌었을 수
  /// 있어 다시 추천한다. 작업 005 설계 5e
  Future<void> _answerAt(RecRow row, String? scope) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => scope == 'user'
            ? SettingsScreen(api: widget.api)
            : CardDetailScreen(api: widget.api, id: row.userCardId),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _pay(RecResult r, RecRow row) async {
    // 금액칸이 순위를 계산한 금액과 다르면 먼저 다시 추천한다. 1만 원 순위로 15만 원 결제를 열지 않게 한다
    final typed = int.tryParse(_amountText.text);
    if (typed != _amount) {
      _amount = typed;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('적은 금액으로 다시 계산했어요. 1순위를 확인하고 눌러 주세요.')),
      );
      return;
    }
    final input = PaymentInput()
      ..amount = _amount
      ..merchantName = widget.merchantName ?? ''
      ..userCardId = row.userCardId
      ..category = _category
      ..recommendationRequestId = r.requestId;
    final saved = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          api: widget.api,
          cards: [for (final x in r.ranking) (id: x.userCardId, name: x.name)],
          initial: input,
        ),
      ),
    );
    if (saved != null && mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _result,
    builder: (context, snap) {
      final r = snap.data;
      final title =
          r?.merchantDisplay ??
          widget.merchantName ??
          widget.title ??
          r?.categoryName ??
          '추천';
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (r?.categoryName != null)
              Text(r!.categoryName!, style: const TextStyle(color: C.sub)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('amount'),
              controller: _amountText,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: const InputDecoration(
                labelText: '결제 금액',
                hintText: '1만 원 기준',
                suffixText: '원',
              ),
              // 금액을 다 적고 확인을 누를 때만 다시 추천한다. 칠 때마다 부르면 추천 요청 기록이 사용자 의도보다 많이 쌓인다
              textInputAction: TextInputAction.done,
              onSubmitted: (v) {
                _amount = int.tryParse(v);
                _refresh();
              },
            ),
            const SizedBox(height: 16),
            if (snap.hasError)
              const Text('서버에 연결하지 못했어요.', style: TextStyle(color: C.sub)),
            if (r == null && !snap.hasError)
              const Center(child: CircularProgressIndicator()),
            // E16. 가게를 못 찾으면 업종을 골라 추천한다
            if (r != null && r.category == null && widget.merchantName != null)
              FutureBuilder(
                future: _categories,
                builder: (context, cats) => Box(
                  color: C.blueSoft,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${widget.merchantName}”을 찾지 못했어요',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: C.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '업종을 고르면 그 업종으로 추천해요. 가게 이름은 적은 그대로 저장해요.',
                        style: TextStyle(fontSize: 13, color: C.sub),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // 자식 업종이 있으면 자식으로 고른다. 부모 업종으로는 자식 업종 혜택이 빠진다. E47
                          for (final c in cats.data ?? <Category>[])
                            for (final (code, name)
                                in c.children.isEmpty
                                    ? [(c.code, c.name)]
                                    : [
                                        for (final ch in c.children)
                                          (ch.code, ch.name),
                                      ])
                              ActionChip(
                                label: Text(name),
                                onPressed: () {
                                  _category = code;
                                  _refresh();
                                },
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            // 담을 수 없는 질문은 계산하지 않고 까닭을 알린다
            if (r?.unsupported == 'billing')
              const Box(
                color: C.grey,
                padding: EdgeInsets.all(16),
                child: Text(
                  '이 업종은 후불교통이나 자동납부에 따라 받는 혜택이 달라 추천을 계산하지 않아요. 결제 기록의 바꾸기에서 청구 방식을 골라 적어 주세요.',
                  style: TextStyle(color: C.sub, height: 1.5),
                ),
              ),
            if (r != null && r.ranking.isNotEmpty)
              Text(
                '${r.amount == null ? '1만 원' : won(r.amount!)} 결제 기준',
                style: const TextStyle(fontSize: 13, color: C.faint),
              ),
            if (r != null)
              for (final (i, row) in r.ranking.indexed) ...[
                const SizedBox(height: 8),
                _RankRow(
                  rank: i + 1,
                  row: row,
                  onAsk: (scope) => _answerAt(row, scope),
                  // 다시 계산하는 동안에는 누를 수 없다. 이전 순위의 추천 요청으로 결제를 열지 않게 한다
                  onPay: i == 0 && snap.connectionState == ConnectionState.done
                      ? () => _pay(r, row)
                      : null,
                ),
              ],
            const SizedBox(height: 16),
            const Text(
              '혜택 금액은 카탈로그로 계산한 추정치예요. 실제 청구와 다를 수 있어요.',
              style: TextStyle(fontSize: 13, color: C.faint),
            ),
          ],
        ),
      );
    },
  );
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.row,
    this.onPay,
    this.onAsk,
  });
  final int rank;
  final RecRow row;
  final VoidCallback? onPay;
  final ValueChanged<String?>? onAsk;

  @override
  Widget build(BuildContext context) => Box(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$rank',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: C.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                row.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: C.text,
                ),
              ),
            ),
            // 한도를 다 쓴 카드는 회색 알림으로 보인다. E10
            if (row.exhausted)
              const Pill('한도 소진', fg: C.sub, bg: C.grey)
            else
              Text(
                row.value > 0 ? '${won(row.value)} ${row.kind}' : won(0),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: C.green,
                ),
              ),
          ],
        ),
        if (row.title != null && row.value > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              row.title!,
              style: const TextStyle(fontSize: 13, color: C.sub),
            ),
          ),
        ],
        // 한도 때문에 혜택이 줄었을 때만 이유로 보인다. 작업 004 의도 성공 기준 3
        if (row.limited)
          const Padding(
            padding: EdgeInsets.only(left: 24, top: 4),
            child: Pill('한도가 남은 만큼만', fg: C.sub, bg: C.grey),
          ),
        if (row.provisional)
          const Padding(
            padding: EdgeInsets.only(left: 24, top: 4),
            child: Pill('달 끝에 확정', fg: C.sub, bg: C.grey),
          ),
        for (final m in row.payWith)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: Text(
              '${m.name}로 내면 ${won(m.extra)} 더 받아요',
              style: const TextStyle(fontSize: 13, color: C.amber),
            ),
          ),
        for (final a in row.asks)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: InkWell(
              onTap: onAsk == null ? null : () => onAsk!(a.scope),
              child: Text(
                '답하면 ${won(a.extra)} 더 받아요 · ${a.question}',
                style: const TextStyle(fontSize: 13, color: C.blue),
              ),
            ),
          ),
        if (onPay != null) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: onPay, child: const Text('이 카드로 결제 기록')),
        ],
      ],
    ),
  );
}
