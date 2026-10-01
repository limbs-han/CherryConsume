import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/shell.dart';
import 'screens/start.dart';
import 'theme.dart';

void main() => runApp(CherryApp(api: Api()));

class CherryApp extends StatefulWidget {
  const CherryApp({
    super.key,
    required this.api,
    this.devLogin = const bool.fromEnvironment('DEV_LOGIN'),
  });
  final Api api;

  /// 개발용 로그인 버튼. `--dart-define=DEV_LOGIN=true`로 빌드할 때만 보인다. 작업 005 설계 3절
  final bool devLogin;

  @override
  State<CherryApp> createState() => _CherryAppState();
}

class _CherryAppState extends State<CherryApp> {
  bool? _loggedIn;
  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.api.onSignedOut = () {
      // 위에 열어 둔 카드 추가 화면과 시트까지 닫아야 시작 화면이 보인다
      _nav.currentState?.popUntil((r) => r.isFirst);
      if (mounted) setState(() => _loggedIn = false);
    };
    widget.api.restore().then((ok) => setState(() => _loggedIn = ok));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '체리컨슘',
    navigatorKey: _nav,
    theme: theme(),
    home: switch (_loggedIn) {
      null => const Scaffold(),
      true => Shell(api: widget.api),
      false => StartScreen(
        api: widget.api,
        devLogin: widget.devLogin,
        onLoggedIn: () => setState(() => _loggedIn = true),
      ),
    },
  );
}
