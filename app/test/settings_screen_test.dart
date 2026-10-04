// 설정 화면을 시안대로. 작업 011 설계 2절 S1, S2, 계획 단계 3의 8
import 'dart:io';

import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/settings.dart' show appVersion;
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'engine/helpers.dart' show realJson;

const soldier = '현역병으로 인정되었나요?';

Future<void> open(WidgetTester tester) async {
  final (:api, :s) = app();
  addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000);
  await tester.pumpWidget(CherryApp(api: api));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Tabs), matching: find.text('설정')),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('앱 판은 pubspec.yaml의 version과 같다', () {
    final line = File(
      'pubspec.yaml',
    ).readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(' ').last.split('+').first, appVersion);
  });

  testWidgets('묶음마다 흰 카드에 줄과 화살표다. 답하지 않은 답은 답하기 배지, 누르면 시트에서 고른다', (
    tester,
  ) async {
    await open(tester);
    for (final group in ['혜택 계산에 쓰는 답', '기록 옮기기', '앱']) {
      expect(find.text(group), findsOneWidget);
    }
    final row = find
        .ancestor(of: find.textContaining(soldier), matching: find.byType(Row))
        .first;
    expect(find.ancestor(of: row, matching: find.byType(Box)), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.widgetWithText(Pill, '답하기')),
      findsOneWidget,
    );

    await tester.tap(find.textContaining(soldier));
    await tester.pumpAndSettle();
    await tester.tap(find.text('예').last);
    await tester.pumpAndSettle();
    expect(find.text('답을 적었어요.'), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('예')), findsOneWidget);
  });

  testWidgets('앱 정보 줄에 앱 판과 카탈로그 날짜가 있다', (tester) async {
    await open(tester);
    // 카탈로그 날짜는 카드마다 공식 문구와 대조한 날 가운데 가장 늦은 날이다
    final last = [
      for (final c in realJson['cards'] as List) c['checked_at'] as String,
    ].reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    final day = DateTime.parse(last);
    final info = find.text('$appVersion · 카탈로그 ${day.month}/${day.day}');
    await tester.scrollUntilVisible(info, 100);
    expect(info, findsOneWidget);
    expect(find.text('앱 정보'), findsOneWidget);
  });
}
