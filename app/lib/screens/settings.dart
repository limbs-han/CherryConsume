/// 시안 보드 9 설정. 혜택 계산에 쓰는 답. 가진 카드들의 사람 사실이다. 작업 004 설계 3.1, 작업 005 설계 5e
library;

import 'package:flutter/material.dart';

import '../api.dart';
import 'answer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});
  final Api api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<FactQuestion>> _facts = widget.api.userFacts();

  Future<void> _answer(FactQuestion q, Object value) async {
    try {
      final repriced = await widget.api.answerFacts({q.key: value});
      if (!mounted) return;
      answered(context, repriced);
      setState(() {
        _facts = widget.api.userFacts();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('답을 적지 못했어요.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: FutureBuilder(
      future: _facts,
      builder: (context, snap) => switch (snap) {
        AsyncSnapshot(hasError: true) => const Center(
          child: Text('서버에 연결하지 못했어요.'),
        ),
        AsyncSnapshot(:final data?) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              '혜택 계산에 쓰는 답',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (data.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('지금 가진 카드에는 물을 것이 없어요.'),
              ),
            for (final q in data)
              FactAnswer(
                q: q,
                note: '쓰는 카드 · ${q.cards.join(', ')}',
                onAnswer: (v) => _answer(q, v),
              ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    ),
  );
}
