// 앱 글꼴과 함께 쓰는 부품. 작업 011 설계 1절, 4절, 계획 단계 1
import 'dart:io';

import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'app_helpers.dart';

void main() {
  test('글꼴은 Pretendard를 줄인 Cherry Sans 세 굵기이고 라이선스가 함께 있다', () {
    expect(theme().textTheme.bodyMedium!.fontFamily, 'CherrySans');
    final fonts =
        (loadYaml(File('pubspec.yaml').readAsStringSync())['flutter']['fonts']
                as List)
            .single;
    expect(fonts['family'], 'CherrySans');
    final files = {
      for (final f in fonts['fonts'] as List) f['weight'] ?? 400: f['asset'],
    };
    expect(files, {
      400: 'assets/fonts/CherrySans-Regular.otf',
      700: 'assets/fonts/CherrySans-Bold.otf',
      800: 'assets/fonts/CherrySans-ExtraBold.otf',
    });
    for (final f in files.values) {
      expect(File(f).existsSync(), isTrue, reason: f);
    }
    expect(
      File('assets/fonts/OFL.txt').readAsStringSync(),
      contains('Reserved Font Name Pretendard'),
    );
  });

  testWidgets('3버튼 막대 뒤에는 Android가 반투명 바탕을 깐다', (tester) async {
    // Android 15부터 앱이 막대 뒤까지 그려 막대 뒤 글자가 비친다. 설계 2절 Z3
    final (:api, s: _) = app();
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    final styles = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .map((r) => r.value);
    expect(
      styles.where((s) => s.systemNavigationBarContrastEnforced == true),
      isNotEmpty,
    );
  });
}
