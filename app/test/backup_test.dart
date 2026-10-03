// 설정의 기록 내보내기와 가져오기. 작업 006 설계 6절, 계획 단계 6의 2
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/screens/settings.dart';
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:cherry_consume/store/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Future<void> open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

List<Object?> payments(Store s) => [
  for (final r in s.db.select(
    'select merchant_name, amount from transactions order by paid_at',
  ))
    (r['merchant_name'], r['amount']),
];

void main() {
  testWidgets('내보낸 파일을 다른 폰에서 가져오면 기록이 같고 지금 기록이 있으면 먼저 묻는다', (tester) async {
    // 옛 폰. GS25 4,300원을 적고 내보낸다. 결제 기록이 그대로 들어 있다고 알린다
    final (api: oldApi, s: old) = app();
    final card =
        addCard(old, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    pay(old, card, 4300, 'GS25');
    String? name;
    Uint8List? file;
    await open(
      tester,
      SettingsScreen(
        api: oldApi,
        save: (n, b) async {
          (name, file) = (n, b);
          return true;
        },
      ),
    );
    await tap(tester, find.text('기록 내보내기'));
    expect(find.text('이 파일에는 결제 기록이 그대로 들어 있어요. 남에게 보내지 마세요.'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, '내보내기'));
    expect(find.text('기록을 내보냈어요.'), findsOneWidget);
    expect(name, 'cherryconsume-20260915.json');
    expect(jsonDecode(utf8.decode(file!))['kind'], 'cherryconsume-records');

    // 새 폰. 이미 이마트 결제를 적었다. 바꿀지 묻고 취소하면 그대로다
    final (:api, :s) = app();
    final mine = addCard(s, 'hyundai-zero-edition3-discount')['id'] as String;
    pay(s, mine, 9000, '이마트');
    await open(
      tester,
      SettingsScreen(api: api, pick: () async => (name: name!, bytes: file)),
    );
    await tap(tester, find.text('기록 가져오기'));
    expect(find.text('지금 기록을 지우고 파일의 기록으로 바꿀까요?'), findsOneWidget);
    await tap(tester, find.text('취소'));
    expect(payments(s), [('이마트', 9000)]);

    await tap(tester, find.text('기록 가져오기'));
    await tap(tester, find.widgetWithText(FilledButton, '바꾸기'));
    expect(find.text('기록을 가져왔어요.'), findsOneWidget);
    expect(payments(s), payments(old));
  });

  testWidgets('받지 않는 파일과 큰 파일은 까닭을 알리고 기록이 그대로다', (tester) async {
    // 빈 폰이라 묻지 않고 바로 읽는다
    final (:api, :s) = app();
    var picked = (
      name: 'x.json',
      bytes: Uint8List.fromList(utf8.encode('{')) as Uint8List?,
    );
    await open(tester, SettingsScreen(api: api, pick: () async => picked));
    await tap(tester, find.text('기록 가져오기'));
    expect(find.text('지금 기록을 지우고 파일의 기록으로 바꿀까요?'), findsNothing);
    expect(find.text('체리컨슘 기록 파일이 아니에요'), findsOneWidget);
    picked = (name: 'big.json', bytes: null);
    await tap(tester, find.text('기록 가져오기'));
    expect(find.text('파일이 20MB보다 커요.'), findsOneWidget);
    expect(payments(s), isEmpty);
  });

  testWidgets('내보내기를 취소하면 쓰지 않고 파일 고르기가 실패하면 알린다', (tester) async {
    // 단계 6 위험 검토 5번, 12번
    final (:api, s: _) = app();
    var saved = 0;
    await open(
      tester,
      SettingsScreen(
        api: api,
        save: (_, _) async {
          saved++;
          return true;
        },
        pick: () async => throw Exception('복사 실패'),
      ),
    );
    await tap(tester, find.text('기록 내보내기'));
    await tap(tester, find.text('취소'));
    expect(saved, 0);
    expect(find.text('기록을 내보냈어요.'), findsNothing);
    await tap(tester, find.text('기록 가져오기'));
    expect(find.text('파일을 읽지 못했어요.'), findsOneWidget);
  });
}
