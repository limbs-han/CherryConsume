// 이용 내역 엑셀 가져오기 화면. 열 짝짓기, 미리보기, 저장, 묶음 되돌리기. 작업 005 설계 5f. S11, E30, E34
// 작업 006 계획 단계 5의 3에서 가짜 서버 대신 실제 저장소로 바꿨다. Mr.Life 41만 원으로 30만 구간이다
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart' show Api;
import 'package:cherry_consume/main.dart';
import 'package:cherry_consume/screens/import.dart';
import 'package:cherry_consume/store/imports.dart' show signature;
import 'package:cherry_consume/store/routes/imports.dart' as imports;
import 'package:cherry_consume/store/routes/me.dart' show addCard;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_helpers.dart';
import 'store/helpers.dart' show pay;
import 'store/import_formats_test.dart' show banksalad, banksaladHead, sheet;
import 'store/imports_ibk_test.dart' show ibk, line;

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

  testWidgets('결제일과 시각을 같은 열로 짝지어도 다시 읽는다', (tester) async {
    // E30. 2026-10-05 실제 IBK 파일의 승인일시처럼 한 칸에 날짜와 시각이 있다. 화면 검사가 막아 다시 읽기가 꺼져 있었다
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    final file = (
      name: '내역.csv',
      bytes: text('날,곳,값\n2026.09.10 21:30,GS25 강남점,4300\n') as Uint8List?,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImportScreen(
          api: api,
          cards: [(id: card, name: '신한카드 Mr.Life')],
          pick: () async => file,
        ),
      ),
    );
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
    for (final (key, header) in [
      ('date', '날'),
      ('time', '날'),
      ('merchant', '곳'),
      ('amount', '값'),
    ]) {
      final pick = find.byKey(Key('map-$key'));
      await tester.ensureVisible(pick);
      await tester.pumpAndSettle();
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await tester.tap(find.text(header).last);
      await tester.pumpAndSettle();
    }
    final again = find.widgetWithText(FilledButton, '다시 읽기');
    await tester.scrollUntilVisible(again, 200);
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(again).onPressed, isNotNull);
    await tester.tap(again);
    await tester.pumpAndSettle();
    expect(find.text('합계 4,300원'), findsOneWidget);
  });

  testWidgets('없음으로 비운 칸을 저장하면 다음 가져오기에도 비운 채다', (tester) async {
    // E30. 자동이 "상태" 열을 취소 여부로 잡았는데 값이 "취소불가"라 결제가 모두 취소로 빠지는 파일이다. 다시 검토 중간 1
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    final bytes = text(
      '이용일자,가맹점명,이용금액,상태\n2026.09.10 21:30,GS25 강남점,4300,취소불가\n',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImportScreen(
          api: api,
          cards: [(id: card, name: '신한카드 Mr.Life')],
          pick: () async => (name: '내역.csv', bytes: bytes as Uint8List?),
        ),
      ),
    );
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
    final remap = find.text('열 다시 짝짓기');
    await tester.scrollUntilVisible(remap, 200);
    await tester.tap(remap);
    await tester.pumpAndSettle();
    final pick = find.byKey(const Key('map-cancel'));
    await tester.scrollUntilVisible(pick, 200);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();
    await tester.tap(find.text('없음').last);
    await tester.pumpAndSettle();
    final again = find.widgetWithText(FilledButton, '다시 읽기');
    await tester.scrollUntilVisible(again, 200);
    await tester.ensureVisible(again);
    await tester.pumpAndSettle();
    await tester.tap(again);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '1건 저장');
    await tester.scrollUntilVisible(save, 200);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final [kept] = s.db.select('select mapping from import_mappings');
    expect(jsonDecode(kept['mapping'] as String), containsPair('cancel', -1));
    // 다음 가져오기는 기억한 짝으로 읽고 비운 칸을 채우지 않는다
    final next = imports.preview(s, bytes, userCardId: card);
    expect(next['mapping'] as Map, containsPair('cancel', -1));
    // 기억한 짝으로 연 파일을 바꾸지 않고 다시 짝지어 저장해도 비운 칸이 남는다. 다시 검토 중간 1
    final later = text(
      '이용일자,가맹점명,이용금액,상태\n2026.09.11 08:10,CU 역삼점,1500,취소불가\n',
    );
    await tester.pumpWidget(
      // 앞 화면이 저장하며 닫혔으니 앱을 새로 띄운다
      MaterialApp(
        key: UniqueKey(),
        home: ImportScreen(
          api: api,
          cards: [(id: card, name: '신한카드 Mr.Life')],
          pick: () async => (name: '내역.csv', bytes: later as Uint8List?),
        ),
      ),
    );
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
    final remap2 = find.text('열 다시 짝짓기');
    await tester.scrollUntilVisible(remap2, 200);
    await tester.ensureVisible(remap2);
    await tester.pumpAndSettle();
    await tester.tap(remap2);
    await tester.pumpAndSettle();
    final again2 = find.widgetWithText(FilledButton, '다시 읽기');
    await tester.scrollUntilVisible(again2, 200);
    await tester.ensureVisible(again2);
    await tester.pumpAndSettle();
    await tester.tap(again2);
    await tester.pumpAndSettle();
    final save2 = find.widgetWithText(FilledButton, '1건 저장');
    await tester.scrollUntilVisible(save2, 200);
    await tester.tap(save2);
    await tester.pumpAndSettle();
    final [kept2] = s.db.select('select mapping from import_mappings');
    expect(jsonDecode(kept2['mapping'] as String), containsPair('cancel', -1));
  });

  // 작업 015 설계 2절과 4절. 화면이 읽은 형식을 보이고, 모르는 형식에서 자동으로 찾은 짝과 다른 칸을 알린다
  Future<void> open(
    WidgetTester tester,
    Uint8List bytes,
    String card,
    Api api,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportScreen(
          api: api,
          cards: [(id: card, name: '카드')],
          pick: () async => (name: '내역.xls', bytes: bytes as Uint8List?),
        ),
      ),
    );
    await tester.tap(find.text('파일 고르기'));
    await tester.pumpAndSettle();
  }

  const plain = '이용일자,가맹점명,이용금액,상태\n2026.09.10 21:30,GS25 강남점,4300,\n';

  testWidgets('아는 형식은 형식 이름을 보이고 열 짝짓기 단추가 없다', (tester) async {
    final (:api, :s) = app();
    final card =
        addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000)['id']
            as String;
    await open(
      tester,
      ibk([line('원화', '2026-09-10 12:30:00', '편의점 예시', '4,300', '10000001')]),
      card,
      api,
    );
    expect(find.text('기업은행 출력용 형식으로 읽었어요'), findsOneWidget);
    expect(find.text('열 다시 짝짓기'), findsNothing);
  });

  testWidgets('모르는 형식은 열 짝을 확인해 달라고 한다', (tester) async {
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    await open(tester, text(plain), card, api);
    expect(find.text('처음 보는 형식이라 열 짝을 확인해 주세요'), findsOneWidget);
    expect(find.text('열 다시 짝짓기'), findsOneWidget);
    // 자동으로 찾은 짝으로 읽었으면 다르다는 알림이 없다
    expect(find.textContaining('자동으로 찾은 열 짝과 다르게'), findsNothing);
  });

  testWidgets('자동으로 찾은 열을 비우면 칸 아래에 알린다', (tester) async {
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    await open(tester, text(plain), card, api);
    final remap = find.text('열 다시 짝짓기');
    await tester.scrollUntilVisible(remap, 200);
    await tester.ensureVisible(remap);
    await tester.pumpAndSettle();
    await tester.tap(remap);
    await tester.pumpAndSettle();
    expect(find.textContaining('자동으로 찾은 열:'), findsNothing);
    final pick = find.byKey(const Key('map-cancel'));
    await tester.scrollUntilVisible(pick, 200);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();
    await tester.tap(find.text('없음').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('자동으로 찾은 열: 상태.'), findsOneWidget);
  });

  testWidgets('기억한 짝이 자동으로 찾은 짝과 다르면 미리보기에 알린다', (tester) async {
    // 2026-10-05 실제 폰에서 기억한 짝이 취소 여부를 비워 취소와 할인 줄이 읽지 못한 행이 됐다
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    s.db.execute(
      'insert into import_mappings (signature, mapping, updated_at) values (?, ?, 0)',
      [
        signature(['이용일자', '가맹점명', '이용금액', '상태']),
        jsonEncode({'date': 0, 'merchant': 1, 'amount': 2, 'cancel': -1}),
      ],
    );
    await open(tester, text(plain), card, api);
    expect(
      find.text('자동으로 찾은 열 짝과 다르게 읽었어요. 열 다시 짝짓기에서 확인해 주세요'),
      findsOneWidget,
    );
  });

  testWidgets('뱅크샐러드 파일의 신용카드 결제는 일시불로 넣는다고 알린다', (tester) async {
    // 작업 015 설계 3절
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    await open(
      tester,
      sheet([
        banksaladHead,
        banksalad(
          '2026-09-10',
          '12:30:00',
          '편의점 예시',
          -4300,
          card: '신한카드 Mr.Life',
        ),
      ]),
      card,
      api,
    );
    expect(find.text('뱅크샐러드 가계부 내보내기 형식으로 읽었어요'), findsOneWidget);
    expect(
      find.text('신용카드 결제 1건은 할부인지 몰라 일시불로 넣어요. 할부 결제는 기록에서 고쳐 주세요'),
      findsOneWidget,
    );
  });

  testWidgets('미리보기는 넣는 줄만 100줄씩 보이고 넣지 않는 줄은 접어 둔다', (tester) async {
    // 2026-10-06 사용자가 뱅크샐러드 파일에서 다른 카드라 빠지는 줄이 새 결제처럼 섞여 보이고 최근 한 달만 보인다고 했다
    final (:api, :s) = app();
    final card =
        addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
            as String;
    final day = DateTime.utc(2026, 4, 1);
    final lines = [
      '이용일자,가맹점명,이용금액',
      for (var i = 0; i < 130; i++)
        '${day.add(Duration(days: i)).toIso8601String().substring(0, 10).replaceAll('-', '.')},가게 ${i + 1},1000',
      '2026.09.01,오류 가게,금액 모름',
      '2026.09.02,오류 가게,금액 모름',
    ];
    await open(tester, text('${lines.join('\n')}\n'), card, api);
    expect(find.text('가게 100', skipOffstage: false), findsOneWidget);
    expect(find.text('가게 101', skipOffstage: false), findsNothing);
    expect(find.text('오류 가게', skipOffstage: false), findsNothing);
    final more = find.text('30건 더 보기');
    await tester.scrollUntilVisible(more, 300);
    await tester.ensureVisible(more);
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('가게 130', skipOffstage: false), findsOneWidget);
    final rest = find.text('넣지 않는 줄 2건 보기');
    await tester.scrollUntilVisible(rest, 300);
    await tester.ensureVisible(rest);
    await tester.pumpAndSettle();
    await tester.tap(rest);
    await tester.pumpAndSettle();
    expect(find.text('오류 가게', skipOffstage: false), findsNWidgets(2));
  });
}
