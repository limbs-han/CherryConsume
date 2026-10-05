// 화면 시험의 앱. 가짜 서버 대신 메모리 SQLite와 커밋된 카탈로그 위의 실제 저장소다. 작업 006 설계 4절 "시험"
//
// 시계는 서버 시험처럼 2026-09-15 21:00 한국 시간이다. 화면과 저장소가 같은 시계를 본다
import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/clock.dart' as clock;
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:cherry_consume/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/helpers.dart' show realCatalog;
import 'store/helpers.dart' show start;

({Api api, Store s}) app([DateTime? at]) {
  final fixed = at ?? start;
  clock.now = () => fixed;
  addTearDown(() => clock.now = DateTime.now);
  final s = Store(openDb(), realCatalog, clock: () => clock.now());
  return (api: Api(s), s: s);
}

/// 흐린 글자 `C.faint`가 흰 상자 밖에 있는 글자들. 회색 바탕 위에서는 대비가 4.19:1이라 흰 상자 안에서만 쓴다.
/// 작업 004 설계 2.1, 작업 013 13-14
List<String> faintOffWhite(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate())
    if ((e.widget as Text).style?.color == C.faint && backgroundOf(e) != Colors.white)
      (e.widget as Text).data ?? '',
];

/// 위젯 뒤에 칠해진 가장 가까운 바탕색
Color? backgroundOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    final c = switch (w) {
      Container(:final color?) => color,
      Container(decoration: BoxDecoration(:final color?)) => color,
      DecoratedBox(decoration: BoxDecoration(:final color?)) => color,
      ColoredBox(:final color) => color,
      Material(:final color?) when w.type != MaterialType.transparency => color,
      _ => null,
    };
    if (c == null || c.a == 0) return true;
    found = c;
    return false;
  });
  return found;
}

/// 진동 호출을 모은다. 값은 `HapticFeedbackType.lightImpact` 같은 종류다. 작업 013 13-16
List<String> haptics(WidgetTester tester) {
  final log = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}');
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return log;
}
