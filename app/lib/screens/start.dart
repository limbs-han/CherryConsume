/// 시안 보드 0 시작. 카카오와 Google은 슬라이스 7에서 붙인다
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    required this.api,
    required this.devLogin,
    required this.onLoggedIn,
  });
  final Api api;
  final bool devLogin;
  final VoidCallback onLoggedIn;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _busy = false;

  Future<void> _devLogin() async {
    setState(() => _busy = true);
    try {
      await widget.api.devLogin('jihan');
      widget.onLoggedIn();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('서버에 연결하지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          children: [
            const Spacer(),
            const Text(
              '체리컨슘',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: C.text,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '이번 달 실적은 얼마나 남았고,\n지금 이 가게에서는 어느 카드가 나은지.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5, color: C.sub),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFEE500),
                foregroundColor: const Color(0xFF191919),
              ),
              onPressed: () => notReady(context, '카카오 로그인'),
              child: const Text('카카오로 시작'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
              onPressed: () => notReady(context, 'Google 로그인'),
              child: const Text('Google로 시작'),
            ),
            if (widget.devLogin) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _devLogin,
                child: const Text('개발용으로 시작'),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '카드번호는 받지 않아요. 카드 이름과 결제 금액만 저장해요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: C.sub),
            ),
          ],
        ),
      ),
    ),
  );
}
