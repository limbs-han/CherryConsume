/// 시안 보드 9 설정. 맨 위에 계정, 그 아래 혜택 계산에 쓰는 답. 작업 004 설계 3.1, 작업 005 설계 5e, 5g
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../social.dart';
import '../theme.dart';
import 'answer.dart';

const _providers = {'kakao': '카카오', 'google': 'Google', 'dev': '개발용'};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    this.social = const Social(),
  });
  final Api api;
  final Social social;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<FactQuestion>> _facts = widget.api.userFacts();
  late final Future<({String provider, DateTime createdAt})> _account = widget
      .api
      .account();

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

  Future<void> _logout(String? provider) async {
    // 모아 둔 결제는 로그아웃하면 지워진다. 보내지 못한 것이 있으면 묻는다. 설계 5i
    final waiting = (await widget.api.pending()).length;
    if (waiting > 0 && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('로그아웃할까요?'),
          content: Text('아직 보내지 못한 결제 $waiting건이 지워져요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('로그아웃'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.api.logout();
    } catch (_) {
      // 서버에 닿지 않아도 이 기기의 토큰은 지운다
    }
    // 카카오와 Google의 로그인 상태도 지워 폰에 그 토큰이 남지 않게 한다
    if (provider != null) await widget.social.signOut(provider);
    widget.api.onSignedOut?.call();
  }

  /// 탈퇴. 바로 로그인이 막히고 30일 뒤 기록이 모두 지워진다. 그 수단과 앱의 연결도 끊는다. E27, E36
  Future<void> _withdraw(String provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('탈퇴할까요?'),
        content: const Text(
          '바로 로그인할 수 없게 되고, 30일 뒤 카드와 결제 기록이 모두 지워져요. 되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.withdraw();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('탈퇴하지 못했어요.')));
      }
      return;
    }
    await widget.social.unlink(provider);
    widget.api.onSignedOut?.call();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        FutureBuilder(
          future: _account,
          builder: (context, snap) {
            final a = snap.data;
            return Box(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a == null
                        ? '계정'
                        : '${_providers[a.provider] ?? a.provider}로 로그인했어요',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (a != null)
                    Text(
                      '${a.createdAt.year}년 ${a.createdAt.month}월 ${a.createdAt.day}일 가입',
                      style: const TextStyle(fontSize: 13, color: C.sub),
                    ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _logout(a?.provider),
                        child: const Text('로그아웃'),
                      ),
                      TextButton(
                        onPressed: a == null
                            ? null
                            : () => _withdraw(a.provider),
                        child: const Text('탈퇴'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const Text(
          '혜택 계산에 쓰는 답',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        FutureBuilder(
          future: _facts,
          builder: (context, snap) => switch (snap) {
            AsyncSnapshot(hasError: true) => const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('서버에 연결하지 못했어요.'),
            ),
            AsyncSnapshot(:final data?) when data.isEmpty => const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('지금 가진 카드에는 물을 것이 없어요.'),
            ),
            AsyncSnapshot(:final data?) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final q in data)
                  FactAnswer(
                    q: q,
                    note: '쓰는 카드 · ${q.cards.join(', ')}',
                    onAnswer: (v) => _answer(q, v),
                  ),
              ],
            ),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ),
      ],
    ),
  );
}
