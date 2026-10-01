/// 색과 모서리. 화면 시안과 작업 004의 규칙을 따른다. 작업 005 설계 6절
library;

import 'package:flutter/material.dart';

abstract final class C {
  static const text = Color(0xFF191F28);
  static const sub = Color(0xFF4E5968);
  static const faint = Color(0xFF6B7684);
  // 파랑은 할 일, 초록은 혜택 금액, 호박색은 기회, 회색은 알림이다
  static const blue = Color(0xFF3457B2);
  static const blueSoft = Color(0xFFE8EEFB);
  static const green = Color(0xFF2F7A4F);
  static const greenSoft = Color(0xFFE3F2E9);
  static const amber = Color(0xFFB45309);
  static const bg = Color(0xFFF2F4F7);
  static const line = Color(0xFFE1E5EC);
  static const grey = Color(0xFFEEF0F3);
}

// 모서리는 20, 16, 8과 완전히 둥글게 네 가지다
const r20 = BorderRadius.all(Radius.circular(20));
const r16 = BorderRadius.all(Radius.circular(16));
const r8 = BorderRadius.all(Radius.circular(8));

ThemeData theme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: C.blue,
    primary: C.blue,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: C.bg,
  appBarTheme: const AppBarTheme(
    backgroundColor: C.bg,
    foregroundColor: C.text,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: C.text,
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: const RoundedRectangleBorder(borderRadius: r16),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: C.text,
      side: const BorderSide(color: C.line),
      shape: const RoundedRectangleBorder(borderRadius: r16),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  ),
);

/// 흰 바탕 둥근 상자. 시안의 카드 모양이다
class Box extends StatelessWidget {
  const Box({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: color, borderRadius: r20),
    child: child,
  );
}

/// 구간 배지 같은 작은 알약
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.fg = C.blue, this.bg = C.blueSoft});
  final String label;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );
}

void notReady(BuildContext context, String what) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text('$what은 아직 준비 중이에요.')));
