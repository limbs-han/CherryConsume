/// 시안 보드 0 시작. 카카오와 Google로 시작한다. 작업 005 설계 5g. S1, S10, E29
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../social.dart';
import '../theme.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    required this.api,
    required this.devLogin,
    required this.onLoggedIn,
    this.social = const Social(),
  });
  final Api api;
  final bool devLogin;
  final Social social;
  final VoidCallback onLoggedIn;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool _busy = false;

  /// 카카오나 Google에서 토큰을 받아 서버에 로그인한다. 사용자가 그만두면 아무것도 하지 않는다
  Future<void> _login(String provider) async {
    setState(() => _busy = true);
    try {
      final token = provider == 'kakao'
          ? await widget.social.kakao()
          : await widget.social.google();
      if (token == null) return;
      await widget.api.socialLogin(provider, token);
      widget.onLoggedIn();
    } on ApiError catch (e) {
      // 탈퇴한 계정은 서버가 까닭을 준다. E27
      String? detail;
      try {
        final body = jsonDecode(e.body);
        if (body is Map && body['detail'] is String) detail = body['detail'];
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.status == 403 && detail != null ? detail : '로그인하지 못했어요.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('로그인하지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
              onPressed: _busy ? null : () => _login('kakao'),
              child: const Text('카카오로 시작'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
              onPressed: _busy ? null : () => _login('google'),
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
            const SizedBox(height: 4),
            // 같은 사람도 다른 수단으로 들어오면 다른 계정이다. 1차는 합치지 않는다. E29
            const Text(
              '전에 쓴 수단으로 로그인해 주세요. 다른 수단으로 들어오면 새 계정이에요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: C.sub),
            ),
          ],
        ),
      ),
    ),
  );
}
