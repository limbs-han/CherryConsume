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
  static const amberSoft = Color(0xFFFFF4E5);
  static const bg = Color(0xFFF2F4F7);
  static const line = Color(0xFFE1E5EC);
  static const grey = Color(0xFFEEF0F3);
}

// 모서리는 20, 16, 8과 완전히 둥글게 네 가지다
const r20 = BorderRadius.all(Radius.circular(20));
const r16 = BorderRadius.all(Radius.circular(16));
const r8 = BorderRadius.all(Radius.circular(8));

ThemeData theme() => ThemeData(
  // 없는 글자는 폰 기본 글꼴로 그려진다. 600은 가까운 700으로 그려진다. 작업 011 설계 1절
  fontFamily: 'CherrySans',
  colorScheme: ColorScheme.fromSeed(
    seedColor: C.blue,
    primary: C.blue,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: C.bg,
  // 시안대로 뒤로 가기 칸은 48, 제목은 그 뒤 4에서 시작한다. 탭 화면은 [rootTitleSpacing]으로 24다. 작업 011 설계 2절 G5
  appBarTheme: const AppBarTheme(
    leadingWidth: 48,
    titleSpacing: 4,
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
  // 주요 버튼은 시안대로 높이 56, 글자 17이다. 작업 011 설계 2절
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: const RoundedRectangleBorder(borderRadius: r16),
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  ),
  // 결제 기록 버튼. 코발트 알약에 흰 글자다. 작업 011 설계 2절 G6
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: C.blue,
    foregroundColor: Colors.white,
    shape: StadiumBorder(),
    extendedSizeConstraints: BoxConstraints(minHeight: 56),
    extendedPadding: EdgeInsets.fromLTRB(16, 0, 20, 0),
    extendedTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
    decoration: BoxDecoration(
      color: color,
      borderRadius: r20,
      // 흰 카드만 시안의 옅은 코발트 그림자를 둔다. 작업 011 설계 2절 G4
      boxShadow: color == Colors.white ? shadow : null,
    ),
    child: child,
  );
}

const shadow = [
  BoxShadow(color: Color(0x143457B2), blurRadius: 18, offset: Offset(0, 6)),
];

/// 구간 배지 같은 작은 배지
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.fg = C.blue, this.bg = C.blueSoft});
  final String label;
  final Color fg, bg;

  @override
  // 시안의 배지는 모서리 8, 글자 12다. 작업 011 설계 2절
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: r8),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
