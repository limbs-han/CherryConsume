// 이용 내역 엑셀 가져오기 화면. 열 짝짓기, 미리보기, 저장, 묶음 되돌리기. 작업 005 설계 5f. S11, E30, E34
// 작업 006 계획 단계 5의 3에서 가짜 서버 대신 실제 저장소로 바꿨다. Mr.Life 41만 원으로 30만 구간이다
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/import.dart';
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  testWidgets('열을 짝지어 다시 읽고 미리보기를 보고 새 결제와 취소만 저장한다', (tester) async {
    // 열 이름이 사전에 없어 짝지어야 한다. 9월 10일 21시 30분 GS25는 새 결제, 9월 11일 이마트 12만 원은 직접 넣은 같은 날
    // 결제와 겹친다. 9월 12일 GS25 취소는 새 GS25에 붙는다
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    pay(s, card, 120000, '이마트', at: '2026-09-11T19:00:00+09:00');
    final file = (
      name: '내역.csv',
      bytes:
          text(
                '날,곳,값\n2026.09.10 21:30,GS25 강남점,4300\n2026.09.11,이마트,120000\n2026.09.12 22:00,GS25 강남점,-4300\n',
              )
              as Uint8List?,
    );
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<int>(
                MaterialPageRoute(
                  builder: (_) => ImportScreen(
                    api: api,
                    cards: [(id: card, name: '신한카드 Mr.Life')],
                    pick: () async => file,
                  ),
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();

    expect(find.text('어느 열이 무엇인지 짝지어 주세요'), findsOneWidget);
    for (final (key, header) in [
      ('date', '날'),
      ('merchant', '곳'),
      ('amount', '값'),
    ]) {
      await tester.tap(find.byKey(Key('map-$key')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(header).last);
      await tester.pumpAndSettle();
    }
    final again = find.widgetWithText(FilledButton, '다시 읽기');
    await tester.scrollUntilVisible(again, 200);
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.pumpAndSettle();

    // 새 결제와 겹친 결제는 숫자 타일과 합계로 보인다. 작업 011 설계 2절 I3
    expect(find.text('합계 4,300원'), findsOneWidget);
    expect(find.text('중복 제외'), findsOneWidget);
    expect(find.text('취소 1건을 원 결제에 붙여요'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, '1건 저장');
    await tester.scrollUntilVisible(save, 200);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, 1);

    final rows = s.db.select(
      'select merchant_name, amount, cancelled_amount, source from transactions order by paid_at',
    );
    expect(
      [
        for (final r in rows)
          (r['merchant_name'], r['amount'], r['cancelled_amount'], r['source']),
      ],
      [('GS25 강남점', 4300, 4300, 'excel'), ('이마트', 120000, 0, 'manual')],
    );
    // 짝지은 열은 저장할 때 남긴다. 열 이름 대신 열 번호만 남는다. E30
    final [kept] = s.db.select('select mapping from import_mappings');
    expect(jsonDecode(kept['mapping'] as String), {
      'date': 0,
      'merchant': 1,
      'amount': 2,
    });
  });

  testWidgets('가져온 묶음을 되돌리면 기록을 다시 불러온다', (tester) async {
    // E34. 가져온 결제 둘과 취소 하나가 한 묶음이다. 되돌리면 기록에서 빠진다
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    final p = imports.preview(
      s,
      text(
        '이용일자,이용시간,가맹점명,이용금액,승인번호,취소여부\n'
        '2026.09.10,21:30,GS25 강남점,4300,A1,\n'
        '2026.09.11,,이마트 성수점,120000,A2,\n'
        '2026.09.12,22:00,GS25 강남점,-4300,A1,취소\n',
      ),
      userCardId: card,
    );
    imports.save(s, {
      'rows': [
        for (final r in p['rows'] as List)
          if ((r as Map).containsKey('paid_at')) r,
      ],
    });
    await tester.pumpWidget(CherryApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록'));
    await tester.pumpAndSettle();
    expect(find.text('이마트 성수점'), findsOneWidget);

    await tester.tap(find.byTooltip('가져온 묶음'));
    await tester.pumpAndSettle();
    expect(find.text('2026-09-15 가져오기'), findsOneWidget);
    expect(find.text('결제 2건 · 취소 1건'), findsOneWidget);
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '되돌리기'));
    await tester.pumpAndSettle();
    expect(find.text('결제 2건 · 취소 1건 · 되돌림'), findsOneWidget);
    expect(
      s.db.select('select * from transactions where deleted_at is null'),
      isEmpty,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('이마트 성수점'), findsNothing);
  });
}
