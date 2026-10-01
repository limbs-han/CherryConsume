/// 아래 탭. 홈, 추천, 기록. 설정은 그 슬라이스에서 더한다. 작업 005 설계 8절
library;

import 'package:flutter/material.dart';

import '../api.dart';
import 'home.dart';
import 'records.dart';
import 'recommend.dart';

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api});
  final Api api;

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
      _ => RecordsScreen(api: widget.api),
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
      ],
    ),
  );
}
