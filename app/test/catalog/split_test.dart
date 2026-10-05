// 목록 파일과 카드별 규칙 파일로 만든 카탈로그. 작업 014 설계 1절, 2절, 4절, 계획 단계 2
//
// 저장소의 앱 파일은 단계 5까지 한 파일이라, 시험이 그 파일을 Python 생성기와 같은 규칙으로 나눠 쓴다
import 'dart:convert';

import 'package:cherry_consume/catalog/models.dart';
import 'package:cherry_consume/engine/engine.dart';
import 'package:cherry_consume/store/db.dart';
import 'package:cherry_consume/store/routes/catalog.dart' as catalog_routes;
import 'package:cherry_consume/store/routes/me.dart';
import 'package:cherry_consume/store/routes/recommend.dart';
import 'package:cherry_consume/store/store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/helpers.dart';
import '../store/helpers.dart' show Clock;
import 'split_helpers.dart';

/// 나눈 카탈로그와 규칙 파일을 읽은 카드 id
({Catalog cat, List<String> loads}) indexCatalog([
  void Function(Json)? edit,
  Map<String, String> Function(Map<String, String>)? editFiles,
]) {
  var (index, files) = splitOf(realJson);
  edit?.call(index);
  files = editFiles?.call(files) ?? files;
  final loads = <String>[];
  final cat = Catalog.fromIndex(index, (id, sha) {
    loads.add(id);
    if (editFiles == null) {
      expect(sha, sha256.convert(utf8.encode(files[id]!)).toString());
    }
    return CardRules.fromFile(jsonDecode(files[id]!) as Json, id);
  });
  return (cat: cat, loads: loads);
}

Store storeOf(Catalog cat) => Store(openDb(), cat, clock: Clock().call);

void main() {
  test('규칙 파일은 그 카드의 규칙을 처음 쓸 때 한 번만 읽는다', () {
    final (:cat, :loads) = indexCatalog();
    final s = storeOf(cat);
    expect(cat.cards.length, 20);
    // 카드 추가 검색, 카드사 칩, 추천 업종 거르기, 카탈로그 날짜는 규칙 파일을 열지 않는다. 설계 4절
    expect(catalog_routes.cards(s), hasLength(greaterThan(10)));
    catalog_routes.issuers(s);
    bound(s, 'cafe');
    expect(loads, isEmpty);
    catalog_routes.preview(s, 'shinhan-mrlife', prev: 410000);
    catalog_routes.preview(s, 'shinhan-mrlife', prev: 0);
    expect(loads, ['shinhan-mrlife']);
  });

  test('나눈 카탈로그도 한 벌 카탈로그와 같은 결과를 낸다', () {
    final full = storeOf(realCatalog), split = storeOf(indexCatalog().cat);
    expect(
      jsonEncode(catalog_routes.cards(split)),
      jsonEncode(catalog_routes.cards(full)),
    );
    for (final id in ['shinhan-mrlife', 'ibk-narasarang', 'samsung-id-on']) {
      for (final prev in [null, 0, 300000, 1200000]) {
        expect(
          jsonEncode(catalog_routes.preview(split, id, prev: prev)),
          jsonEncode(catalog_routes.preview(full, id, prev: prev)),
          reason: '$id $prev',
        );
      }
    }
    // 보유 카드 id는 등록할 때마다 새로 만들어 자리 글자로 바꿔 견준다
    String shown(Object out, List<String> ids) {
      var text = jsonEncode(out);
      for (final (i, id) in ids.indexed) {
        text = text.replaceAll(id, 'card$i');
      }
      return text;
    }

    final ids = [
      for (final s in [full, split])
        [
          addCard(s, 'ibk-narasarang', assumedPrevMonthSpend: 300000)['id']
              as String,
          addCard(s, 'shinhan-mrlife', assumedPrevMonthSpend: 410000)['id']
              as String,
        ],
    ];
    expect(shown(home(split), ids[1]), shown(home(full), ids[0]));
    expect(shown(top(split), ids[1]), shown(top(full), ids[0]));
  });

  test('개정 머리로 고른 개정이 옛 rulesOn과 같다', () {
    // 옛 구현. 시행일이 그날 이하인 마지막 개정이고, 없으면 첫 개정이 추정 시행일일 때만 그것이다
    Revision? old(CatalogCard? card, DateTime day) {
      if (card == null) return null;
      final rs = card.revisions;
      final current = rs.where((r) => !r.effectiveFrom.isAfter(day));
      if (current.isNotEmpty) return current.last;
      return rs.first.effectiveFromEstimated ? rs.first : null;
    }

    // 저장소 카탈로그에는 추정 시행일 개정이 없어 한 카드의 첫 개정을 추정으로 바꿔 그 갈래를 지난다
    final full = jsonDecode(jsonEncode(realJson)) as Json;
    final samsung = (full['cards'] as List).firstWhere(
      (c) => c['id'] == 'samsung-id-on',
    );
    samsung['revisions'][0]['effective_from_estimated'] = true;
    final fullCat = Catalog.fromJson(full);
    final (index, files) = splitOf(full);
    final splitCat = Catalog.fromIndex(
      index,
      (id, _) => CardRules.fromFile(jsonDecode(files[id]!) as Json, id),
    );
    final heads = Engine(splitCat).ctx, rules = Engine(fullCat).ctx;
    for (final id in [...fullCat.cards.keys, 'no-such-card']) {
      // 시행일 당일과 전날이 경계다
      final days = {
        DateTime.utc(2019),
        DateTime.utc(2028, 12, 31),
        for (final h in fullCat.cards[id]?.heads ?? const <RevisionHead>[]) ...[
          h.effectiveFrom,
          h.effectiveFrom.subtract(const Duration(days: 1)),
        ],
      };
      for (final d in days) {
        final want = old(fullCat.cards[id], d);
        expect(rules.rulesOn(id, d)?.sha256, want?.sha256, reason: '$id $d');
        expect(heads.rulesOn(id, d)?.sha256, want?.sha256, reason: '$id $d');
        final h = heads.headOn(id, d);
        expect(h?.effectiveFrom, want?.effectiveFrom, reason: '$id $d');
        expect(h?.effectiveFromEstimated, want?.effectiveFromEstimated);
        expect(h?.tiers, want?.rules.tiers, reason: '$id $d');
      }
    }
    expect(
      heads.rulesOn('samsung-id-on', DateTime.utc(2019))?.effectiveFrom,
      DateTime.utc(2021, 9, 1),
    );
  });

  test('규칙 파일이 목록과 다른 판이면 읽지 않는다', () {
    // 단계 2 위험 검토 중간 1, 낮음 4. 머리로 고른 차례가 다른 개정을 가리켜 혜택이 조용히 틀리지 않게 한다
    Map<String, String> edited(
      Map<String, String> files,
      void Function(Json) f,
    ) {
      final j = jsonDecode(files['samsung-id-on']!) as Json;
      f(j);
      return {...files, 'samsung-id-on': jsonEncode(j)};
    }

    for (final f in <void Function(Json)>[
      (j) => (j['revisions'] as List).removeLast(),
      (j) => j['revisions'][1]['effective_from'] = '2026-02-01',
      (j) => j['revisions'][0]['effective_from_estimated'] = true,
      (j) => j['revisions'][0]['rules']['tiers'] = [0, 1],
      (j) => j['id'] = 'other',
      (j) => j['schema'] = splitSchema + 1,
    ]) {
      final cat = indexCatalog(null, (files) => edited(files, f)).cat;
      expect(
        () => cat.cards['samsung-id-on']!.revisions,
        throwsFormatException,
      );
    }
  });

  test('칸이 빠진 목록 파일은 읽지 않는다', () {
    // 단계 2 위험 검토 중간 2, 낮음 3
    final (index, _) = splitOf(realJson);
    CardRules never(String _, String _) => throw StateError('읽지 않는다');
    expect(
      () => Catalog.fromIndex({...index}..remove('billing_bound'), never),
      throwsFormatException,
    );
    final noSha = [
      for (final c in index['cards'] as List)
        {...c as Json}..remove('file_sha256'),
    ];
    expect(
      () => Catalog.fromIndex({...index, 'cards': noSha}, never),
      throwsA(isA<TypeError>()),
    );
  });

  test('청구 방식 업종은 목록에 적힌 것을 쓴다', () {
    final full = storeOf(realCatalog);
    final listed = storeOf(
      indexCatalog((j) => j['billing_bound'] = ['cafe']).cat,
    );
    expect(bound(listed, 'cafe'), isTrue);
    expect(bound(full, 'cafe'), isFalse);
    // 나눌 때 모은 값과 한 벌 카탈로그에서 모은 값이 같다
    expect(indexCatalog().cat.billingBound, billingBound(realCatalog));
  });

  test('목록 파일 형식 번호가 앱보다 크면 읽지 않는다', () {
    final (index, _) = splitOf(realJson);
    expect(
      () => Catalog.fromIndex({
        ...index,
        'schema': splitSchema + 1,
      }, (_, _) => throw StateError('')),
      throwsFormatException,
    );
  });
}
