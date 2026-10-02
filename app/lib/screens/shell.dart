/// 아래 탭. 홈, 추천, 기록, 설정. 작업 005 설계 8절
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../social.dart';
import 'home.dart';
import 'records.dart';
import 'recommend.dart';
import 'settings.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, this.social = const Social()});
  final Api api;
  final Social social;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    // 탭을 바꿀 때마다 새로 그려 다른 탭에서 바뀐 결제와 카드를 반영한다
    body: switch (_tab) {
      0 => HomeScreen(api: widget.api),
      1 => RecommendScreen(api: widget.api),
      2 => RecordsScreen(api: widget.api),
      _ => SettingsScreen(api: widget.api, social: widget.social),
    },
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
        NavigationDestination(
          icon: Icon(Icons.recommend_outlined),
          label: '추천',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: '기록',
        ),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: '설정'),
      ],
    ),
  );
}
