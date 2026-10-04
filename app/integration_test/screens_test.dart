// 화면을 시안과 나란히 보려고 에뮬레이터에서 화면마다 찍는다. 시안의 카드 세 장과 9월 결제를 넣는다.
// 찍기는 이 시험이 "SHOT 이름"을 출력하면 backend/tools/screens.py가 adb로 화면 전체를 찍는다. 시스템 막대까지 찍혀야
// 가려지는 곳을 볼 수 있어서다. 작업 011 설계 2절
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/clock.dart' as clock;
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/shell.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 시안의 날. 2026-09-19 15:00 한국 시간
final now = DateTime.utc(2026, 9, 19, 6);

DateTime kst(int day, int hour, int minute) =>
    DateTime.utc(2026, 9, day, hour - 9, minute);

Future<Api> fresh() async {
  clock.now = () => now;
  final json = await rootBundle.loadString('assets/catalog.json');
  final catalog = Catalog.fromJson(jsonDecode(json) as Map<String, dynamic>);
  return Api(Store(openDb(), catalog, clock: () => clock.now()));
}

/// 시안 홈과 기록의 카드 세 장과 결제
Future<Api> seeded() async {
  final api = await fresh();
  await api.addCard('shinhan-mrlife', prev: 410000);
  await api.addCard('ibk-narasarang', prev: 200000);
  await api.addCard('hyundai-zero-edition3-discount');
  final cards = (await api.home()).cards;
  String id(String part) => cards.firstWhere((c) => c.name.contains(part)).id;
  for (final (amount, name, card, category, channel, at) in [
    (169500, '이마트 성수점', 'Mr.Life', 'grocery_mart', 'offline', kst(10, 18, 30)),
    (128000, '서울시 자동차세', 'ZERO', 'tax', 'online', kst(18, 10, 0)),
    (36900, '쿠팡', 'ZERO', 'online_shopping', 'online', kst(18, 20, 10)),
    (4300, 'GS25 테헤란점', '나라사랑', 'convenience', 'offline', kst(19, 9, 2)),
    (12500, '스타벅스 역삼점', 'Mr.Life', 'cafe', 'offline', kst(19, 14, 20)),
  ]) {
    await api.savePayment(
      PaymentInput()
        ..amount = amount
        ..merchantName = name
        ..userCardId = id(card)
        ..category = category
        ..channel = channel
        ..paidAt = at,
    );
  }
  return api;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    print('SHOT $name');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
  }

  Finder tab(String label) =>
      find.descendant(of: find.byType(Tabs), matching: find.text(label));

  /// 긴 목록에서 아직 그리지 않은 자리면 내려서 그린 뒤 보이게 한다
  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
    }
    await tester.ensureVisible(f);
  }

  /// 작은 화면에서는 버튼이 화면 밖에 있을 수 있어 그 자리까지 내린 뒤 누른다
  Future<void> tapIn(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.pumpAndSettle();
    await tester.tap(f);
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 60));
    await tester.pumpAndSettle();
  }

  testWidgets('화면마다 찍는다', (tester) async {
    // 빈 앱을 먼저 띄웠다가 바꿔 끼우면 홈의 결제 기록 버튼이 찍히지 않아 빈 홈은 맨 끝에 찍는다. 작업 011 단계 2 Z6
    await tester.pumpWidget(CherryApp(api: await seeded()));
    await shot(tester, '1-home');

    await tapIn(tester, find.text('카드 추가'));
    await shot(tester, '2-add-card');
    await tester.enterText(find.byType(TextField).first, '처음');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tapIn(tester, find.textContaining('처음').last);
    await shot(tester, '2b-register-sheet');
    await closeSheet(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapIn(tester, find.textContaining('Mr.Life').first);
    await shot(tester, '6-card-detail');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('결제 기록'));
    await shot(tester, '4-payment');
    await tester.enterText(find.byType(TextField).at(0), '12500');
    await tester.enterText(find.byType(TextField).at(1), '스타벅스 역삼점');
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '4-payment-filled');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('바꾸기'));
    await shot(tester, '4-payment-bottom');
    await tester.tap(find.text('바꾸기'));
    await shot(tester, '4b-details');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '확인'));
    await shot(tester, '4b-details-bottom');
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(tab('추천'));
    await shot(tester, '5-recommend');
    await tapIn(tester, find.text('스타벅스 역삼점').first);
    await shot(tester, '5b-result');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(tab('기록'));
    await shot(tester, '7-history');
    await tester.tap(find.text('가져오기'));
    await shot(tester, '8-import');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(tab('설정'));
    await shot(tester, '9-settings');

    await tester.pumpWidget(CherryApp(key: UniqueKey(), api: await fresh()));
    await shot(tester, '1a-home-empty');
  });
}
