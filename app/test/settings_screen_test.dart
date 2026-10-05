// 설정 화면을 시안대로. 작업 011 설계 2절 S1, S2, 계획 단계 3의 8
import 'dart:io';

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/clock.dart' as clock;
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/settings.dart';
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
  privacyTests();
  exportDateTests();

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
    // 긴 질문은 첫 문장을 제목으로, 나머지를 설명으로 둔다. 작업 011 설계 2절 S4
    expect(find.text(soldier), findsOneWidget);
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('IBK장병내일준비적금이 있거나'),
      ),
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

void exportDateTests() {
  Future<void> openWith(
    WidgetTester tester,
    Api api, {
    bool saves = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(api: api, save: (_, _) async => saves),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> export(WidgetTester tester) async {
    await tester.tap(find.text('기록 내보내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('내보내기'));
    await tester.pumpAndSettle();
  }

  testWidgets('기록 내보내기 줄 아래에 마지막으로 내보낸 날을 보인다', (tester) async {
    // 기록이 폰 안에만 있어 폰을 잃으면 사라진다. 사용자가 스스로 내보내게 알린다. 작업 012 설계 4.1
    final (:api, s: _) = app();
    await openWith(tester, api);
    expect(find.text('아직 내보낸 적 없어요'), findsOneWidget);
    await export(tester);
    expect(find.text('마지막으로 내보낸 날 9월 15일'), findsOneWidget);
    expect(find.text('아직 내보낸 적 없어요'), findsNothing);
    expect(find.text('기록을 내보냈어요.'), findsOneWidget);
  });

  testWidgets('저장 창을 닫으면 내보낸 날을 적지 않는다', (tester) async {
    final (:api, s: _) = app();
    await openWith(tester, api, saves: false);
    await export(tester);
    expect(find.text('아직 내보낸 적 없어요'), findsOneWidget);
  });

  testWidgets('해가 다르면 해를 붙인다', (tester) async {
    final (:api, :s) = app(DateTime.utc(2025, 9, 19, 12));
    await openWith(tester, api);
    await export(tester);
    expect(find.text('마지막으로 내보낸 날 9월 19일'), findsOneWidget);
    clock.now = () => DateTime.utc(2026, 9, 15, 12);
    await openWith(tester, Api(s));
    expect(find.text('마지막으로 내보낸 날 2025년 9월 19일'), findsOneWidget);
  });
}

void privacyTests() {
  testWidgets('앱 묶음의 개인정보처리방침 줄을 누르면 방침 주소를 브라우저로 연다', (tester) async {
    // Play 정책은 방침을 Play Console 칸과 앱 안 두 곳에 두라고 한다. 작업 012 설계 1.4
    final (:api, s: _) = app();
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: api,
          open: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.text('개인정보처리방침');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(opened, [
      Uri.parse('https://limbs-han.github.io/CherryConsume/privacy/'),
    ]);
  });

  testWidgets('브라우저를 열지 못하면 주소를 알린다', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(api: api, open: (_) async => false),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.text('개인정보처리방침');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('limbs-han.github.io/CherryConsume/privacy'),
      findsOneWidget,
    );
  });
}
