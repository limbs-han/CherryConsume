// 하단 탭. 고른 탭은 코발트로 채운 그림, 안 고른 탭은 회색 선이다. 작업 011 설계 3절, 계획 단계 1의 4
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';

void main() {
  testWidgets('고른 탭은 채운 코발트, 안 고른 탭은 회색 선이고 누르면 바뀐다', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    Map<String, (bool, Color)> icons() => {
      for (final i in tester.widgetList<TabIcon>(find.byType(TabIcon)))
        i.kind.name: (i.filled, i.color),
    };
    expect(icons(), {
      'home': (true, C.blue),
      'recommend': (false, C.faint),
      'records': (false, C.faint),
      'settings': (false, C.faint),
    });

    await tester.tap(find.text('추천'));
    await tester.pumpAndSettle();
    expect(find.text('어디서 결제하세요?'), findsOneWidget);
    expect(icons()['recommend'], (true, C.blue));
    expect(icons()['home'], (false, C.faint));
    expect(
      tester.getSemantics(find.text('추천')),
      matchesSemantics(
        isSelected: true,
        isButton: true,
        label: '추천',
        hasTapAction: true,
        hasSelectedState: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
  });

  testWidgets('탭 막대는 흰 바탕에 위쪽 선이고 칸마다 누를 자리가 56 이상이다', (tester) async {
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    final bar = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(Tabs),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final d = bar.decoration as BoxDecoration;
    expect(d.color, Colors.white);
    expect((d.border! as Border).top.color, C.line);
    // 막대가 내용 높이만큼만 차지해 화면 몸통을 가리지 않는다
    expect(tester.getSize(find.byType(Tabs)).height, lessThan(80));
    for (final label in ['홈', '추천', '기록', '설정']) {
      final tile = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkResponse),
      );
      expect(
        tester.getSize(tile).height,
        greaterThanOrEqualTo(56),
        reason: label,
      );
    }
  });
}
