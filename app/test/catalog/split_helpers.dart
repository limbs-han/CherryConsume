// 시험이 쓰는 목록 파일과 규칙 파일. 한 벌 JSON을 Python 생성기와 같은 규칙으로 나눈다. 작업 014
import 'dart:convert';

import 'package:cherry_consume/catalog/models.dart';
import 'package:crypto/crypto.dart';

const _info = [
  'id',
  'issuer',
  'name',
  'short_name',
  'search_names',
  'kind',
  'status',
  'status_since',
  'annual_fees',
  'checked_at',
];

/// 한 벌 JSON을 목록과 규칙 파일 글자로 나눈다. Python `app_split`과 같은 규칙이다
(Json, Map<String, String>) splitOf(Json full) {
  bool hasBilling(List conditions) => conditions.any(
    (c) => c['billing'] != null || hasBilling(c['any_of'] as List? ?? const []),
  );
  final files = <String, String>{};
  final heads = <Json>[];
  final bound = <String>{};
  for (final card in (full['cards'] as List).cast<Json>()) {
    for (final r in card['revisions'] as List) {
      for (final b in r['rules']['benefits'] as List) {
        if (hasBilling(b['when'] as List)) {
          bound.addAll((b['target']['categories'] as List).cast<String>());
        }
      }
    }
    final text = jsonEncode({
      'schema': 2,
      'id': card['id'],
      'open_questions': card['open_questions'],
      'revisions': card['revisions'],
    });
    files[card['id']] = text;
    heads.add({
      for (final k in _info)
        if (card.containsKey(k)) k: card[k],
      'revisions': [
        for (final r in card['revisions'] as List)
          {
            'effective_from': r['effective_from'],
            'effective_from_estimated': r['effective_from_estimated'],
            'tiers': r['rules']['tiers'],
          },
      ],
      'file_sha256': sha256.convert(utf8.encode(text)).toString(),
    });
  }
  return (
    {
      for (final MapEntry(:key, :value) in full.entries)
        if (key != 'cards') key: value,
      'schema': 2,
      'billing_bound': bound.toList()..sort(),
      'cards': heads,
    },
    files,
  );
}

/// 카드를 id만 바꿔 copies번 복사한 목록과 규칙 파일. 1,500장 시험 카탈로그다. 설계 6절
(Json, Map<String, String>) copiesOf(
  Json index,
  Map<String, String> files,
  int copies,
) {
  final heads = <Json>[];
  final out = <String, String>{};
  for (var i = 0; i < copies; i++) {
    for (final c in (index['cards'] as List).cast<Json>()) {
      final id = '${c['id']}-$i';
      out[id] = jsonEncode({...jsonDecode(files[c['id']]!) as Json, 'id': id});
      heads.add({
        ...c,
        'id': id,
        'file_sha256': sha256.convert(utf8.encode(out[id]!)).toString(),
      });
    }
  }
  return ({...index, 'cards': heads}, out);
}
