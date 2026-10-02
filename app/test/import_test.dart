// 이용 내역 엑셀 가져오기. 열 짝짓기, 미리보기, 저장. 작업 005 설계 5f. S11, E30
import 'dart:convert';
import 'dart:typed_data';

import 'package:cherry_consume/api.dart';
import 'package:cherry_consume/screens/import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response ok(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> row(String status, String name, int amount) => {
  'line': 2,
  'user_card_id': 'u1',
  'card_name': '신한카드 Mr.Life',
  'paid_at': '2026-09-10T21:30:00+09:00',
  'timed': true,
  'merchant_name': name,
  'amount': amount,
  'installment_months': 1,
  'approval_no': null,
  'cancel': status == 'cancel',
  'status': status,
  'category_name': '편의점',
};

class FakeServer {
  final previews = <Map<String, String>>[];
  final uploads = <List<int>>[];
  List<dynamic>? saved;
  Map<String, dynamic>? savedMapping;

  Future<http.Response> call(http.Request req) async {
    switch ((req.method, req.url.path)) {
      case ('POST', '/me/imports/preview'):
        previews.add(req.url.queryParameters);
        uploads.add(req.bodyBytes);
        if (!req.url.queryParameters.containsKey('mapping')) {
          return ok({
            'needs_mapping': true,
            'header_row': 0,
            'headers': ['날', '곳', '값'],
            'mapping': null,
            'signature': 'a' * 64,
            'rows': [],
            'summary': null,
          });
        }
        return ok({
          'needs_mapping': false,
          'header_row': 0,
          'headers': ['날', '곳', '값'],
          'mapping': {'date': 0, 'merchant': 1, 'amount': 2},
          'signature': 'a' * 64,
          'rows': [
            row('new', 'GS25 강남점', 4300),
            row('duplicate', '이마트', 120000),
            row('cancel', 'GS25 강남점', 4300),
          ],
          'summary': {
            'rows': 3,
            'new': 1,
            'amount': 4300,
            'duplicates': 1,
            'cancels': 1,
            'orphans': 0,
            'skipped': 0,
            'errors': 0,
            'uncategorized': 0,
          },
        });
      case ('POST', '/me/imports'):
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        saved = body['rows'];
        savedMapping = body['mapping'];
        return ok({
          'id': 7,
          'imported': 1,
          'duplicates': 1,
          'cancels': 1,
          'orphans': 0,
          'repriced': 0,
        }, 201);
    }
    return ok({'detail': 'not found'}, 404);
  }
}

void main() {
  testWidgets('열을 짝지어 다시 읽고 미리보기를 보고 새 결제와 취소만 저장한다', (tester) async {
    final server = FakeServer();
    final api = Api(
      client: MockClient((r) => server(r)),
      baseUrl: 'http://test',
    );
    final file = (
      name: '내역.csv',
      bytes: Uint8List.fromList(utf8.encode('날,곳,값')) as Uint8List?,
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
                    cards: const [(id: 'u1', name: '신한카드 Mr.Life')],
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

    // 카드가 한 장이면 그 카드로 보낸다. 파일은 몸통에 그대로 간다
    expect(server.previews.single['user_card_id'], 'u1');
    expect(server.uploads.single, file.bytes);
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
    await tester.tap(find.widgetWithText(FilledButton, '다시 읽기'));
    await tester.pumpAndSettle();
    // 파일 이름은 보내지 않는다. 짝은 머리 줄과 열 번호다
    expect(server.previews.last.containsKey('file_name'), isFalse);
    expect(jsonDecode(server.previews.last['mapping']!), {
      'row': 0,
      'columns': {'date': 0, 'merchant': 1, 'amount': 2},
    });

    expect(find.text('새 결제 1건 · 4,300원'), findsOneWidget);
    expect(find.text('이미 있는 결제 1건은 넣지 않아요'), findsOneWidget);
    expect(find.text('취소 1건을 원 결제에 붙여요'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '저장'),
      200,
    );
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();
    // 판정받은 행을 모두 보낸다. 서버가 같은 행으로 다시 판정한다
    expect(
      [for (final r in server.saved!) r['status']],
      ['new', 'duplicate', 'cancel'],
    );
    // 짝지은 열은 저장할 때 남긴다. E30
    expect(server.savedMapping, {
      'signature': 'a' * 64,
      'columns': {'date': 0, 'merchant': 1, 'amount': 2},
    });
    expect(result, 1);
  });
}
