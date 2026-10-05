/// 이용 내역 엑셀 가져오기. 미리보기, 저장, 목록, 되돌리기. 서버 `cherry_api/routes/imports.py`를 옮겼다.
/// 작업 005 설계 5f, 작업 006 설계 5절. S11, E30~E35, E51, E57
///
/// 파일은 폰 안 메모리에서 읽고 바로 버린다. 파일과 파일 이름은 남기지 않는다. E35
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../api.dart' show ApiError;
import '../../catalog/models.dart';
import '../../engine/cond.dart';
import '../../engine/models.dart';
import '../db.dart';
import '../formats.dart' show Format, detect;
import '../imports.dart' hide norm, required;
import '../payments.dart';
import '../store.dart';
import 'catalog.dart' show maxSpend;
import 'me.dart' show engineCard;
import 'payments.dart' show PaymentBody, filled, myCards, paymentOf;
import 'records.dart' show lockCards, revisionFor, store;

const maxBytes = 2000000;

/// 직접 넣은 결제와 파일의 행이 같은 결제로 보이는 시각 차이. 결제 알림의 겹침과 같다. 2026-10-02 사용자가 정했다. E31
const near = Duration(minutes: 10);
const oldest = Duration(days: 365 * 5);

ApiError _bad(String message) => ApiError(422, message);

/// 미리보기의 행. 저장할 때 앱이 판정받은 행을 모두 돌려보낸다. 같은 행으로 다시 판정한다
class Line {
  Line({
    required this.userCardId,
    required this.paidAt,
    required this.timed,
    required this.merchantName,
    required this.amount,
    required this.installmentMonths,
    required this.interestFree,
    required this.overseas,
    required this.approvalNo,
    required this.cancel,
  });

  /// 서버의 ImportRow 검사. 틀리면 422다
  factory Line.fromJson(Object? raw) {
    if (raw is! Map) throw _bad('행이 틀렸다');
    T want<T>(String key, [T? fallback]) {
      final v = raw[key] ?? fallback;
      if (v is! T) throw _bad('$key가 틀렸다');
      return v;
    }

    final at = awareTime(raw['paid_at']) ?? (throw _bad('paid_at가 틀렸다'));
    final name = want<String>('merchant_name');
    final amount = want<int>('amount');
    final months = want<int>('installment_months');
    final approval = raw['approval_no'];
    if (name.isEmpty || name.length > 100) throw _bad('merchant_name이 틀렸다');
    if (amount <= 0 || amount > maxSpend) throw _bad('amount가 틀렸다');
    if (months < 1 || months > 36) throw _bad('installment_months가 틀렸다');
    if (approval != null && (approval is! String || approval.length > 40)) {
      throw _bad('approval_no가 틀렸다');
    }
    final trimmed = (approval as String?)?.trim();
    return Line(
      userCardId: want<String>('user_card_id'),
      paidAt: at,
      timed: want<bool>('timed'),
      merchantName: name,
      amount: amount,
      installmentMonths: months,
      interestFree: want<bool>('interest_free', false),
      overseas: want<bool>('overseas', false),
      approvalNo: trimmed == null || trimmed.isEmpty ? null : trimmed,
      cancel: want<bool>('cancel'),
    );
  }

  final String userCardId;
  final DateTime paidAt;

  /// 파일에 시각이 있었는가. 없으면 그날 12시이고 시각 조건은 모름이다. E57
  final bool timed;
  final String merchantName;
  final int amount, installmentMonths;
  final bool interestFree, overseas, cancel;
  final String? approvalNo;

  Json toJson() => {
    'user_card_id': userCardId,
    'paid_at': kstIso(paidAt),
    'timed': timed,
    'merchant_name': merchantName,
    'amount': amount,
    'installment_months': installmentMonths,
    'interest_free': interestFree,
    'overseas': overseas,
    'approval_no': approvalNo,
    'cancel': cancel,
  };
}

/// 한국 시간 ISO 글자. 서버가 주던 "2026-09-11T12:00:00+09:00" 모양이다
String kstIso(DateTime at) {
  final k = kst(at);
  String two(int n) => n.toString().padLeft(2, '0');
  final micro = k.millisecond * 1000 + k.microsecond;
  return '${k.year.toString().padLeft(4, '0')}-${two(k.month)}-${two(k.day)}T${two(k.hour)}:${two(k.minute)}:${two(k.second)}'
      '${micro == 0 ? '' : '.${micro.toString().padLeft(6, '0')}'}+09:00';
}

/// 한국 시간의 날과 시각을 UTC 시각으로
DateTime _fromKst(DateTime day, Duration at) => DateTime.utc(
  day.year,
  day.month,
  day.day,
).add(at).subtract(const Duration(hours: 9));

/// 판정에 쓰는 결제. 이미 있는 결제와 이번 파일의 새 결제다
class _Pay {
  _Pay(
    this.id,
    this.userCardId,
    this.paidAt,
    this.timed,
    this.amount,
    this.merchant,
    this.key,
    this.approval, {
    this.cancelledAmount = 0,
    this.cancelledAt,
    this.saved = false,
  });
  final String id, userCardId, merchant;
  final DateTime paidAt;
  final bool timed, saved;
  final int amount;
  final String? key, approval;
  int cancelledAmount;
  DateTime? cancelledAt;

  /// 이 결제에 가져오기가 붙인 취소. (날짜, 금액)이다. 되돌린 묶음의 것은 뺀다
  final imported = <(DateTime, int)>[];
  final taken = <int>{};
  var used = false;

  /// 앱에서 적은 취소가 있는가. 결제의 취소액이 가져오기가 붙인 취소의 합보다 크면 그렇다
  bool get manualCancel =>
      cancelledAmount > imported.fold(0, (a, c) => a + c.$2);
}

String _norm(String name) => name.replaceAll(RegExp(r'\s'), '').toLowerCase();

bool _has(String? s) => s != null && s.isNotEmpty;

/// 가맹점명이 같거나 한쪽이 다른 쪽을 담거나 같은 가맹점으로 알아보면 같다. E31
bool _sameMerchant(_Pay a, String name, String? key) {
  final b = _norm(name);
  if (a.merchant == b || (a.key != null && a.key == key)) return true;
  final short = a.merchant.length < b.length ? a.merchant.length : b.length;
  return short >= 2 && (b.contains(a.merchant) || a.merchant.contains(b));
}

bool _near(_Pay a, Line r) => a.timed && r.timed
    ? a.paidAt.difference(r.paidAt).abs() <= near
    : localDay(a.paidAt) == localDay(r.paidAt);

bool _before(_Pay a, Line r) => a.timed && r.timed
    ? !a.paidAt.isAfter(r.paidAt)
    : !localDay(a.paidAt).isAfter(localDay(r.paidAt));

/// (결제수단, 가게 이름). 가맹점명이 간편결제 이름으로 시작하면 그 결제수단이고 가게는 나머지로 찾는다. 아니면
/// 실물카드다. 2026-10-02 사용자가 정했다. 작업 001 설계 3절
(String, String) methodOf(Catalog catalog, String merchant) {
  final text = merchant.trim();
  for (final MapEntry(:key, value: m) in catalog.paymentMethods.entries) {
    for (final name in m.statementNames) {
      if (_norm(text).startsWith(_norm(name))) {
        final rest = text.toLowerCase().startsWith(name.toLowerCase())
            ? text.substring(name.length)
            : text;
        final shop = rest.replaceAll(RegExp(r'^[ ()*_\-]+|[ ()*_\-]+$'), '');
        return (key, shop.isEmpty ? text : shop);
      }
    }
  }
  return ('physical_card', text);
}

/// 행마다 new, duplicate, cancel, orphan을 정한다. 같은 날의 결제를 그날의 취소보다 먼저 본다. E31, E32
List<Json> plan(
  Store s,
  Map<String, Map<String, Object?>> cards,
  List<Line> rows,
  DateTime now,
) {
  final pool = <_Pay>[];
  final byId = <String, _Pay>{};
  final ids = cards.keys.toList();
  if (ids.isNotEmpty) {
    final marks = List.filled(ids.length, '?').join(', ');
    for (final r in s.db.select(
      'select * from transactions where user_card_id in ($marks) and deleted_at is null order by paid_at, id',
      ids,
    )) {
      final p = _Pay(
        r['id'],
        r['user_card_id'],
        fromMs(r['paid_at']),
        r['time_known'] == 1,
        r['amount'],
        _norm(r['merchant_name'] ?? ''),
        r['merchant_key'],
        approvalKey(r['approval_no']),
        cancelledAmount: r['cancelled_amount'],
        cancelledAt: r['cancelled_at'] == null
            ? null
            : fromMs(r['cancelled_at']),
        saved: true,
      );
      pool.add(p);
      byId[p.id] = p;
    }
    for (final c in s.db.select(
      'select c.transaction_id, c.amount, c.cancelled_at from import_cancels c '
      'join import_batches b on b.id = c.import_batch_id '
      'join transactions t on t.id = c.transaction_id '
      'where b.undone_at is null and t.user_card_id in ($marks) and t.deleted_at is null',
      ids,
    )) {
      byId[c['transaction_id']]?.imported.add((
        localDay(fromMs(c['cancelled_at'])),
        c['amount'] as int,
      ));
    }
  }
  final engine = s.engine;

  /// 취소 달 칸이 빈 순위 카드의 지나간 달 결제인가. 취소 경로처럼 순위를 다시 매기지 않으려 붙이지 않는다. E55
  bool rankedUnknown(_Pay p) {
    final card = engineCard(cards[p.userCardId]!);
    final found = engine.ctx.rulesOn(card.cardId, localDay(p.paidAt));
    final unknown =
        found != null && found.rules.ranked.any((g) => g.cancellation == null);
    return unknown &&
        rankedPast(engine, card, monthOf(localDay(p.paidAt)), now);
  }

  final out = List<Json>.filled(rows.length, const {});
  // 한쪽 시각을 모르면 12시라 시각 순서가 틀릴 수 있어 날짜, 결제와 취소, 시각 순서로 본다. E57. 같으면 파일 순서다
  final order = List.generate(rows.length, (i) => i)
    ..sort((a, b) {
      final x = rows[a], y = rows[b];
      var c = localDay(x.paidAt).compareTo(localDay(y.paidAt));
      if (c == 0) c = (x.cancel ? 1 : 0) - (y.cancel ? 1 : 0);
      if (c == 0) c = x.paidAt.compareTo(y.paidAt);
      return c == 0 ? a - b : c;
    });
  for (final i in order) {
    final r = rows[i];
    final key = matchMerchant(
      s.aliases,
      methodOf(s.catalog, r.merchantName).$2,
    );
    final sameCard = [
      for (final p in pool)
        if (p.userCardId == r.userCardId) p,
    ];
    if (r.cancel) {
      out[i] = _cancelOf(r, key, sameCard, rankedUnknown);
      continue;
    }
    final ap = approvalKey(r.approvalNo);
    // 이미 있는 결제 하나는 파일의 한 행만 겹친다. 파일 안의 똑같은 두 행은 두 결제다
    // 가장 맞는 결제와 짝짓는다. 승인번호나 가맹점이 같은 것, 그다음 시각이 가까운 것이다
    _Pay? hit;
    (int, Duration)? best;
    for (final p in sameCard) {
      if (!p.saved || p.used || !_duplicate(p, r, key)) continue;
      final match =
          (_has(ap) && p.approval == ap) || (key != null && p.key == key);
      final rank = (match ? 0 : 1, p.paidAt.difference(r.paidAt).abs());
      if (best == null ||
          rank.$1 < best.$1 ||
          (rank.$1 == best.$1 && rank.$2 < best.$2)) {
        best = rank;
        hit = p;
      }
    }
    if (hit != null) {
      hit.used = true;
      out[i] = {'status': 'duplicate'};
      continue;
    }
    // 승인번호가 같으면 같은 결제다. 승인 줄과 매입 줄, 달마다 찍힌 할부 줄이 그렇다. 저장된 결제를 앞 행이 이미
    // 차지했어도 같다. 서버는 새 행끼리만 봐서 그런 파일을 다시 올리면 둘째 줄이 새 결제가 되고 저장이 409로 막혔다.
    // 단계 5 위험 검토 2번. E31, S11
    if (_has(ap) && sameCard.any((p) => p.approval == ap)) {
      out[i] = {'status': 'duplicate'};
      continue;
    }
    final p = _Pay(
      newId(now),
      r.userCardId,
      r.paidAt,
      r.timed,
      r.amount,
      _norm(r.merchantName),
      key,
      ap,
    );
    pool.add(p);
    out[i] = {'status': 'new', 'id': p.id};
  }
  return out;
}

/// 겹침. 승인번호가 둘 다 있으면 그것만 본다. 없으면 같은 금액, 가까운 시각, 같은 가맹점이다. E31
bool _duplicate(_Pay p, Line r, String? key) {
  final ap = approvalKey(r.approvalNo);
  if (_has(p.approval) && _has(ap)) return p.approval == ap;
  return p.amount == r.amount &&
      _near(p, r) &&
      _sameMerchant(p, r.merchantName, key);
}

/// 취소 행을 앞선 원 결제에 붙인다. E32, E5
Json _cancelOf(
  Line r,
  String? key,
  List<_Pay> sameCard,
  bool Function(_Pay) rankedUnknown,
) {
  final earlier =
      [
        for (final (i, p) in sameCard.indexed)
          if (_before(p, r)) (i, p),
      ]..sort((a, b) {
        final c = a.$2.paidAt.compareTo(b.$2.paidAt);
        return c == 0 ? a.$1 - b.$1 : c;
      });
  final ap = approvalKey(r.approvalNo);
  var found = [
    for (final (_, p) in earlier)
      if (_has(ap) && p.approval == ap) p,
  ];
  if (found.isEmpty) {
    // 승인번호가 같은 결제가 없으면 가맹점과 금액으로 찾는다. 직접 넣은 결제에는 승인번호가 없다. 둘 다 승인번호가
    // 있고 다르면 다른 결제다. IBK는 취소된 결제를 승인 줄 없이 취소 줄로만 적어, 이름이 같은 다른 결제를 취소한
    // 것으로 잘못 붙일 수 있었다. 잘못 붙으면 보이지 않게 틀리고, 못 붙이면 미리보기에 보인다. 단계 검토 중간 3
    found = [
      for (final (_, p) in earlier)
        if (!(_has(ap) && _has(p.approval)) &&
            _sameMerchant(p, r.merchantName, key) &&
            p.amount >= r.amount)
          p,
    ];
  }
  if (found.isEmpty) return {'status': 'orphan', 'reason': '원 결제를 찾지 못했어요'};
  final day = localDay(r.paidAt);
  // 같은 파일을 다시 올렸으면 가져오기가 이미 붙인 같은 날 같은 금액의 취소다
  for (final p in found.reversed) {
    for (final (j, (d, a)) in p.imported.indexed) {
      if (d == day && a == r.amount && !p.taken.contains(j)) {
        p.taken.add(j);
        return {'status': 'duplicate'};
      }
    }
  }
  final fit = [
    for (final p in found)
      if (p.amount - p.cancelledAmount >= r.amount) p,
  ];
  if (fit.isEmpty) return {'status': 'orphan', 'reason': '결제 금액보다 많이 취소됐어요'};
  final p = fit.last;
  if (p.saved && p.manualCancel) {
    return {
      'status': 'orphan',
      'reason': '앱에서 적은 취소가 있어 겹치는지 몰라요. 기록에서 확인해 주세요',
    };
  }
  if (p.cancelledAt != null &&
      monthOf(localDay(p.cancelledAt!)) != monthOf(day)) {
    // 취소 시각은 결제마다 하나라 다른 달의 추가 취소는 담지 못한다. 설계 문서 6.5
    return {'status': 'orphan', 'reason': '다른 달에 더 취소된 금액은 아직 담지 못해요'};
  }
  if (p.saved && rankedUnknown(p)) {
    return {
      'status': 'orphan',
      'reason': '이 카드는 순위 혜택의 취소 달을 몰라요. 기록에서 직접 적어 주세요',
    };
  }
  p.cancelledAmount += r.amount;
  // 취소는 결제보다 앞서지 않는다. 한쪽 시각을 모르면 12시라 결제보다 앞설 수 있다
  final at = _later(r.paidAt, p.paidAt);
  p.cancelledAt = p.cancelledAt == null ? at : _later(p.cancelledAt!, at);
  return {'status': 'cancel', 'target': p.id};
}

DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// 카드 이름 열을 보유 카드와 맞춘다. 이름이 같은 카드가 먼저고, 없으면 파일 이름이 카드 이름을 담는 카드가 한 장일
/// 때만이다. 괄호 안의 카드번호 끝자리와 상품 구분은 뺀다. E33
String? cardOf(
  Map<String, Map<String, Object?>> cards,
  Catalog catalog,
  String? name,
) {
  if (name == null) return null;
  String bare(String n) => _norm(n.replaceAll(RegExp(r'\(.*?\)'), ''));
  final wanted = bare(name);
  final names = {
    for (final MapEntry(key: uid, value: r) in cards.entries)
      uid: [
        for (final n in [
          catalog.cards[r['card_id']]!.name,
          ...catalog.cards[r['card_id']]!.searchNames,
        ])
          bare(n),
      ],
  };
  final exact = [
    for (final MapEntry(key: uid, value: ns) in names.entries)
      if (ns.contains(wanted)) uid,
  ];
  if (exact.isNotEmpty) return exact.first;
  final part = [
    for (final MapEntry(key: uid, value: ns) in names.entries)
      if (ns.any((n) => n.length >= 4 && wanted.contains(n))) uid,
  ];
  return part.length == 1 ? part.first : null;
}

/// 가게 이름은 100자까지다. 넷째 바이트 글자의 반쪽을 남기지 않는다
String _cut(String s) {
  if (s.length <= 100) return s;
  final end = s.codeUnitAt(99) >= 0xd800 && s.codeUnitAt(99) <= 0xdbff
      ? 99
      : 100;
  return s.substring(0, end);
}

/// 파일을 읽어 미리보기를 준다. 파일은 메모리에서 읽고 바로 버린다. E35. mapping은 사용자가 짝지은
/// {"row": 줄, "columns": {칸: 열 번호}}다
Json preview(Store s, Uint8List data, {String? userCardId, Object? mapping}) {
  if (data.length > maxBytes) {
    throw ApiError(413, '파일이 2MB보다 커요. 기간을 나눠 올려 주세요');
  }
  final List<List<Object?>> table;
  final String source;
  int? start;
  Map<String, int>? cols;
  // 아는 형식. 작업 015 설계 2절
  Format? format;
  // 사용자가 "없음"으로 비운 칸. 화면이 보낸 짝이나 기억한 짝에서 모은다
  var cleared = const <String>{};
  // 아는 형식이면 형식 표로만 읽는다. 기억한 짝, 화면이 보낸 짝, 열 이름 사전을 쓰지 않아 같은 형식의 파일은 앞서
  // 무엇을 기억했든 결과가 같다. 작업 015 설계 2절
  (Format, int, Map<String, int>)? known;
  try {
    (rows: table, :source) = readSource(data);
    known = detect(table);
    if (mapping != null && mapping is! Map) throw Unreadable('열 짝이 맞지 않아요');
    if (mapping != null && known == null) {
      (start, cols) = findHeader(
        table,
        Map<String, Object?>.from(mapping as Map),
      );
      // findHeader를 지났으면 columns는 맞는 Map이다
      cleared = {
        for (final MapEntry(:key, :value)
            in (mapping['columns'] as Map).entries)
          if (value == -1) '$key',
      };
    }
  } on Unreadable catch (e) {
    throw _bad(e.message);
  }
  if (known != null) (format, start, cols) = known;
  // 모르는 형식에서 열 이름 사전으로 자동으로 찾은 짝. 화면이 이 짝과 다른 칸을 알린다. 작업 015 설계 4절 2
  final (autoStart, auto) = known == null ? findHeader(table) : (null, null);
  if (mapping == null && known == null) {
    final saved = {
      for (final r in s.db.select(
        'select signature, mapping from import_mappings',
      ))
        r['signature'] as String: r['mapping'] as String,
    };
    // 사용자가 짝지은 열을 자동으로 찾은 열보다 먼저 쓴다. 자동이 틀려 고친 짝이 다음에도 쓰인다. E30
    var chosen = const <String>{};
    for (final (i, row) in table.take(20).indexed) {
      final found = saved[signature(row)];
      if (found == null) continue;
      try {
        final picked = jsonDecode(found);
        (start, cols) = findHeader(table, {'row': i, 'columns': picked});
        // findHeader를 지났으면 짝이 맞는 Map이다. "없음"으로 비운 -1 칸까지 사용자가 정한 칸이다. 깨진 짝이면
        // 자동으로 찾으니 비운 칸을 남기지 않는다
        chosen = {for (final k in (picked as Map).keys) '$k'};
        cleared = {
          for (final MapEntry(:key, :value) in picked.entries)
            if (value == -1) '$key',
        };
      } on Unreadable {
        (start, cols) = (null, null);
      } on FormatException {
        // 기억한 짝이 깨졌으면 자동으로 찾는다
        (start, cols) = (null, null);
      }
      break;
    }
    // 기억한 짝에 없는 칸은 같은 머리 줄에서 자동으로 찾은 열로 채운다. 고른 칸, "없음"으로 비운 칸, 고른 열은 그대로
    // 둔다. 세 칸만 손으로 짝지은 IBK 파일이 다음에 취소 여부 없이 읽혀 취소와 카드 할인 줄이 모두 결제로 들어갔다.
    // 2026-10-05 E30
    if (start != null && cols != null) {
      if (autoStart == start && auto != null) {
        final used = cols.values.toSet();
        cols = {
          ...cols,
          for (final MapEntry(:key, :value) in auto.entries)
            if (!chosen.contains(key) && !used.contains(value)) key: value,
        };
      }
    }
    if (start == null) (start, cols) = (autoStart, auto);
  }
  if (start == null || cols == null) {
    final top = table.isEmpty ? 0 : topRow(table);
    return {
      'needs_mapping': true,
      'header_row': top,
      'headers': table.isEmpty
          ? <String>[]
          : [for (final c in table[top]) pyStr(c).trim()],
      'mapping': null,
      'signature': table.isEmpty ? null : signature(table[top]),
      'source': source,
      'top_rows': topRows(table),
      'rows': <Json>[],
      'summary': null,
    };
  }
  final cards = {for (final r in myCards(s)) r['id'] as String: r};
  if (userCardId != null && !cards.containsKey(userCardId)) {
    throw ApiError(404, '보유 카드가 아니다');
  }
  if (!cols.containsKey('card') && userCardId == null) {
    throw _bad('어느 카드의 내역인지 골라 주세요');
  }
  final catalog = s.catalog, now = s.clock();
  final shown = <Json>[];
  final rows = <Line>[];
  final parsed = parseRows(table, start, cols, format);
  // 카드마다 결제의 승인번호. 파일의 결제 줄과 저장된 기록이다. 할인으로 끝나는 이름의 취소 줄이 진짜 취소인지 본다
  String? uidOf(ImportRow p) => userCardId ?? cardOf(cards, catalog, p.card);
  final paid = <String, Set<String>>{};
  for (final r in s.db.select(
    'select user_card_id, approval_no from transactions '
    'where approval_no is not null and deleted_at is null',
  )) {
    final k = approvalKey(r['approval_no'] as String);
    if (_has(k)) {
      paid.putIfAbsent(r['user_card_id'] as String, () => {}).add(k!);
    }
  }
  for (final p in parsed) {
    final (u, k) = (uidOf(p), approvalKey(p.approvalNo));
    if (!p.cancel && u != null && _has(k)) {
      paid.putIfAbsent(u, () => {}).add(k!);
    }
  }
  for (final p in parsed) {
    final base = <String, Object?>{
      'line': p.line,
      'merchant_name': p.merchant,
      'amount': p.amount,
      'cancel': p.cancel,
      'user_card_id': null,
    };
    final at = p.day == null
        ? null
        : _fromKst(p.day!, p.at ?? const Duration(hours: 12));
    if (p.error == null &&
        at != null &&
        at.isAfter(now.add(const Duration(days: 1)))) {
      p.error = '지금보다 뒤의 결제예요';
    }
    if (p.error == null && at != null && at.isBefore(now.subtract(oldest))) {
      p.error = '5년보다 오래된 결제예요';
    }
    if (p.error != null) {
      shown.add({...base, 'status': 'error', 'reason': p.error});
      continue;
    }
    // 이름이 할인으로 끝나도 승인번호가 같은 결제가 파일이나 기록에 있으면 그 결제의 취소다. 단계 검토 중간 2
    if (p.discount &&
        !(paid[uidOf(p)]?.contains(approvalKey(p.approvalNo)) ?? false)) {
      shown.add({...base, 'status': 'discount', 'reason': '카드가 준 할인이라 넣지 않아요'});
      continue;
    }
    // 고른 카드가 있으면 그 카드다. 없으면 카드 이름 열로 나눈다. E33
    final uid = userCardId ?? cardOf(cards, catalog, p.card);
    if (uid == null) {
      shown.add({...base, 'status': 'skipped', 'reason': '보유 카드가 아니에요'});
      continue;
    }
    final Line row;
    try {
      row = Line.fromJson({
        'user_card_id': uid,
        'paid_at': kstIso(at!),
        'timed': p.at != null,
        'merchant_name': _cut(p.merchant),
        'amount': p.amount,
        'installment_months': p.installmentMonths,
        'interest_free': p.interestFree ?? false,
        'overseas': p.overseas,
        'approval_no': p.approvalNo,
        'cancel': p.cancel,
      });
    } on ApiError {
      shown.add({...base, 'status': 'error', 'reason': '금액이나 할부를 읽지 못했어요'});
      continue;
    }
    rows.add(row);
    shown.add({
      ...base,
      ...row.toJson(),
      'interest_unknown': p.interestFree == null,
      'payment_method': methodOf(catalog, p.merchant).$1,
    });
  }
  final judged = plan(s, cards, rows, now).iterator;
  for (final x in shown) {
    if (!x.containsKey('paid_at')) continue;
    judged.moveNext();
    x['status'] = judged.current['status'];
    if (judged.current.containsKey('reason')) {
      x['reason'] = judged.current['reason'];
    }
    final key = matchMerchant(
      s.aliases,
      methodOf(catalog, x['merchant_name'] as String).$2,
    );
    x['category_name'] = key == null
        ? null
        : s.categoryNames[catalog.merchants[key]!.category];
    x['card_name'] = cards[x['user_card_id']]!['name'];
  }
  final fresh = [
    for (final x in shown)
      if (x['status'] == 'new') x,
  ];
  int count(String k) => shown.where((x) => x['status'] == k).length;
  return {
    'needs_mapping': false,
    'header_row': start,
    'headers': [for (final c in table[start]) pyStr(c).trim()],
    // 비운 칸도 -1로 돌려준다. 화면이 다시 짝짓고 저장할 때 -1이 빠지면 다음에 채우기가 그 칸을 되살린다. E30
    'mapping': {...cols, for (final k in cleared) k: -1},
    'format': format?.id,
    'format_name': format?.name,
    // 자동으로 찾은 머리 줄과 짝. 기억한 짝이 다른 머리 줄을 골랐어도 화면이 알 수 있게 줄을 함께 준다
    'auto_header_row': autoStart,
    'auto_mapping': autoStart == start ? auto : null,
    'signature': signature(table[start]),
    'source': source,
    'top_rows': topRows(table),
    'rows': shown,
    'summary': {
      'rows': shown.length,
      'new': fresh.length,
      'amount': fresh.fold<int>(0, (a, x) => a + (x['amount'] as int)),
      'duplicates': count('duplicate'),
      'cancels': count('cancel'),
      'orphans': count('orphan'),
      'discounts': count('discount'),
      'skipped': count('skipped'),
      'errors': count('error'),
      'uncategorized': fresh.where((x) => x['category_name'] == null).length,
      // 무이자인지 모르는 할부. 유이자로 넣는다. 2026-10-02 사용자가 정했다
      'interest_unknown': fresh
          .where((x) => x['interest_unknown'] == true)
          .length,
      // 가맹점명으로 알아본 간편결제. 나머지는 실물카드다
      'easy_pay': fresh
          .where((x) => x['payment_method'] != 'physical_card')
          .length,
      'untimed': fresh.where((x) => x['timed'] != true).length,
    },
  };
}

/// 미리보기의 행을 저장한다. 겹침과 취소를 다시 판정한다. 가져온 결제가 든 가장 앞 달부터 다시 계산한다. E51
Json save(Store s, Json body) {
  final raw = body['rows'];
  // 미리보기가 받는 줄 수와 같다. 서버는 3,000이라 미리보기는 되는데 저장이 막히는 파일이 있었다. 단계 5 위험 검토 8번
  if (raw is! List || raw.isEmpty || raw.length > maxRows + 20) {
    throw _bad('rows가 틀렸다');
  }
  final rows = [for (final r in raw) Line.fromJson(r)];
  final picked = body['mapping'];
  String? sig;
  Map<String, int>? columns;
  if (picked != null) {
    final sg = picked is Map ? picked['signature'] : null;
    final cs = picked is Map ? picked['columns'] : null;
    if (sg is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sg) ||
        cs is! Map ||
        cs.entries.any((e) => e.key is! String || e.value is! int)) {
      throw _bad('mapping이 틀렸다');
    }
    (sig, columns) = (sg, Map<String, int>.from(cs));
  }
  final now = s.clock();
  if (rows.any(
    (r) =>
        r.paidAt.isAfter(now.add(const Duration(days: 1))) ||
        r.paidAt.isBefore(now.subtract(oldest)),
  )) {
    throw _bad('지금보다 뒤이거나 5년보다 오래된 결제가 있다');
  }
  return write(s, () {
    final engine = s.engine, catalog = s.catalog;
    final ids = {for (final r in rows) r.userCardId};
    final cards = lockCards(s, ids);
    if (ids.any(
      (i) => !cards.containsKey(i) || cards[i]!['removed_at'] != null,
    )) {
      throw ApiError(404, '보유 카드가 아니다');
    }
    final judged = plan(s, cards, rows, now);
    // 출처는 미리보기가 읽은 파일 모양이다. 모르는 값은 남기지 않는다. 파일 이름이 들어오지 않게 한다. 작업 013 13-10
    final source = importSources.contains(body['source'])
        ? body['source'] as String
        : null;
    s.db.execute(
      'insert into import_batches (source, row_count, imported_count, duplicate_count, cancel_count, created_at) values (?, ?, 0, 0, 0, ?)',
      [source, rows.length, ms(now)],
    );
    final batch = s.db.lastInsertRowId;
    final sorted = ids.toList()..sort();
    final loaded = loadPayments(s, sorted);
    final fresh = <String, Line>{};
    final cancels = <String, List<Line>>{};
    for (final (k, r) in rows.indexed) {
      final j = judged[k];
      if (j['status'] == 'new') {
        fresh[j['id'] as String] = r;
      } else if (j['status'] == 'cancel') {
        cancels.putIfAbsent(j['target'] as String, () => []).add(r);
      }
    }
    final payments = {for (final uid in ids) uid: <Payment>[]};
    final starts = {for (final uid in ids) uid: <DateTime>[]};
    for (final MapEntry(key: pid, value: r) in fresh.entries) {
      final (method, shop) = methodOf(catalog, r.merchantName);
      // 가게는 간편결제 이름을 뺀 나머지로 찾는다. 기록에는 파일의 가맹점명을 그대로 둔다
      final fields = PaymentBody({
        'merchant_name': shop,
        'paid_at': kstIso(r.paidAt),
        'installment_months': r.installmentMonths,
        'interest_free': r.interestFree && r.installmentMonths > 1,
        'region': r.overseas ? 'overseas' : 'domestic',
        'payment_method': method,
      });
      final p = paymentOf(
        cards[r.userCardId]!,
        fields,
        r.amount,
        filled(s, fields),
        pid,
      ).copyWith(timeKnown: r.timed);
      payments[r.userCardId]!.add(p);
      starts[r.userCardId]!.add(monthOf(localDay(p.paidAt)));
    }
    for (final uid in ids) {
      final list = payments[uid] = [...loaded[uid]!, ...payments[uid]!];
      for (final (k, q) in list.indexed) {
        final lines = cancels[q.id];
        if (lines == null) continue;
        // 취소는 결제보다 앞서지 않는다
        final at = [
          q.paidAt,
          for (final r in lines) r.paidAt,
          ?q.cancelledAt,
        ].reduce(_later);
        list[k] = q.copyWith(
          cancelledAmount:
              q.cancelledAmount + lines.fold(0, (a, r) => a + r.amount),
          cancelledAt: at,
        );
        starts[uid]!.add(monthOf(localDay(q.paidAt)));
      }
    }
    final byId = {
      for (final ps in payments.values)
        for (final q in ps) q.id: q,
    };
    try {
      _insert(s, batch, cards, fresh, byId, now);
    } on SqliteException catch (e) {
      // 판정은 같은 승인번호를 겹침으로 보지만 그사이 다른 저장과 겹치면 여기서 막힌다
      if (e.extendedResultCode == 2067) {
        throw ApiError(409, '같은 승인번호의 결제가 이미 있다. 다시 미리보기 해 주세요');
      }
      rethrow;
    }
    for (final MapEntry(key: target, value: lines) in cancels.entries) {
      final q = byId[target]!;
      if (!fresh.containsKey(target)) {
        // 지금 카탈로그로 다시 계산하니 개정도 결제일의 지금 개정으로 맞춘다. 위험 검토 12번
        final (from, sha) = revisionFor(
          s,
          cards[q.userCardId]!['card_id'] as String,
          q.paidAt,
        );
        s.db.execute(
          'update transactions set cancelled_amount = ?, cancelled_at = ?, revision_from = ?, revision_sha = ?, '
          'updated_at = ? where id = ?',
          [q.cancelledAmount, ms(q.cancelledAt!), from, sha, ms(now), target],
        );
      }
      for (final r in lines) {
        s.db.execute(
          'insert into import_cancels (import_batch_id, transaction_id, amount, cancelled_at) values (?, ?, ?, ?)',
          [batch, target, r.amount, ms(_later(r.paidAt, q.paidAt))],
        );
      }
    }
    var repriced = 0;
    for (final uid in ids) {
      if (starts[uid]!.isEmpty) continue;
      final first = starts[uid]!.reduce((a, b) => b.isBefore(a) ? b : a);
      final res = repricedFrom(
        engine,
        engineCard(cards[uid]!),
        payments[uid]!,
        first,
        now,
      );
      final before = {for (final q in loaded[uid]!) q.id: q};
      final always = {
        for (final q in payments[uid]!)
          if (fresh.containsKey(q.id) || cancels.containsKey(q.id)) q.id,
      };
      repriced += store(
        s,
        cards[uid]!['card_id'] as String,
        res,
        before,
        always,
        now,
      );
    }
    final counts = {
      'imported': fresh.length,
      'duplicates': judged.where((j) => j['status'] == 'duplicate').length,
      'cancels': cancels.values.fold(0, (a, v) => a + v.length),
      'orphans': judged.where((j) => j['status'] == 'orphan').length,
    };
    s.db.execute(
      'update import_batches set imported_count = ?, duplicate_count = ?, cancel_count = ? where id = ?',
      [counts['imported'], counts['duplicates'], counts['cancels'], batch],
    );
    // 사용자가 짝지은 열. 저장할 때 남겨 같은 모양의 다음 파일에 쓴다. 미리보기만 보고 그만두면 남기지 않는다. E30
    if (sig != null) {
      s.db.execute(
        'insert into import_mappings (signature, mapping, updated_at) values (?, ?, ?) '
        'on conflict (signature) do update set mapping = excluded.mapping, updated_at = excluded.updated_at',
        [sig, jsonEncode(columns), ms(now)],
      );
    }
    return {'id': batch, ...counts, 'repriced': repriced};
  });
}

/// 가져온 새 결제를 넣는다. 시각을 아는지, 승인번호, 묶음을 함께 적는다
void _insert(
  Store s,
  int batch,
  Map<String, Map<String, Object?>> cards,
  Map<String, Line> fresh,
  Map<String, Payment> byId,
  DateTime now,
) {
  for (final MapEntry(key: pid, value: r) in fresh.entries) {
    final q = byId[pid]!;
    final (from, sha) = revisionFor(
      s,
      cards[r.userCardId]!['card_id'] as String,
      q.paidAt,
    );
    s.db.execute(
      'insert into transactions (id, user_card_id, amount, merchant_name, merchant_key, category_code, paid_at, time_known, '
      'installment_months, interest_free_installment, channel, region, payment_method, billing, revision_from, revision_sha, '
      "approval_no, import_batch_id, cancelled_amount, cancelled_at, source, created_at, updated_at) "
      "values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'excel', ?, ?)",
      [
        pid,
        r.userCardId,
        q.amount,
        r.merchantName,
        q.merchant,
        q.category,
        ms(q.paidAt),
        q.timeKnown ? 1 : 0,
        q.installmentMonths,
        q.interestFree ? 1 : 0,
        q.channel,
        q.region,
        q.paymentMethod,
        q.billing,
        from,
        sha,
        r.approvalNo,
        batch,
        q.cancelledAmount,
        q.cancelledAt == null ? null : ms(q.cancelledAt!),
        ms(now),
        ms(now),
      ],
    );
  }
}

/// 가져온 묶음. 최근 것이 앞이다
List<Json> batches(Store s) => [
  for (final r in s.db.select(
    'select id, row_count, imported_count, duplicate_count, cancel_count, created_at, undone_at '
    'from import_batches order by id desc',
  ))
    {
      ...rowMap(r),
      'created_at': fromMs(r['created_at']).toIso8601String(),
      'undone_at': r['undone_at'] == null
          ? null
          : fromMs(r['undone_at']).toIso8601String(),
    },
];

/// 묶음 되돌리기. 가져온 결제를 지우고 이 묶음이 붙인 취소만 뺀 뒤 다시 계산한다. 다른 묶음의 취소는 남는다. E34
Json undo(Store s, int bid) => write(s, () {
  if (s.db.select(
    'select id from import_batches where id = ? and undone_at is null',
    [bid],
  ).isEmpty) {
    throw ApiError(404, '가져온 묶음이 아니다');
  }
  final ids = {
    for (final r in s.db.select(
      'select user_card_id from transactions where import_batch_id = ? '
      'union select t.user_card_id from import_cancels c join transactions t on t.id = c.transaction_id '
      'where c.import_batch_id = ?',
      [bid, bid],
    ))
      r['user_card_id'] as String,
  };
  final cards = ids.isEmpty
      ? <String, Map<String, Object?>>{}
      : lockCards(s, ids);
  final now = s.clock(), engine = s.engine;
  final loaded = loadPayments(s, ids.toList()..sort());
  final mineIds = {
    for (final r in s.db.select(
      'select id from transactions where import_batch_id = ? and deleted_at is null',
      [bid],
    ))
      r['id'] as String,
  };
  final gone = {
    for (final ps in loaded.values)
      for (final q in ps)
        if (mineIds.contains(q.id)) q.id,
  };
  final mine = <String, int>{};
  for (final c in s.db.select(
    'select transaction_id, amount from import_cancels where import_batch_id = ?',
    [bid],
  )) {
    mine[c['transaction_id']] =
        (mine[c['transaction_id']] ?? 0) + (c['amount'] as int);
  }
  final others = <String, (DateTime, int)>{};
  for (final c in s.db.select(
    'select c.transaction_id, max(c.cancelled_at) as at, sum(c.amount) as amount from import_cancels c '
    'join import_batches b on b.id = c.import_batch_id '
    'where b.undone_at is null and b.id <> ? and c.transaction_id in (select transaction_id from import_cancels where import_batch_id = ?) '
    'group by c.transaction_id',
    [bid, bid],
  )) {
    others[c['transaction_id']] = (fromMs(c['at']), c['amount'] as int);
  }
  s.db.execute(
    'update transactions set deleted_at = ?, updated_at = ? where import_batch_id = ? and deleted_at is null',
    [ms(now), ms(now), bid],
  );
  s.db.execute('update import_batches set undone_at = ? where id = ?', [
    ms(now),
    bid,
  ]);
  var repriced = 0;
  for (final uid in ids) {
    final payments = <Payment>[];
    final months = <DateTime>[];
    final back = <String>{};
    for (var q in loaded[uid]!) {
      if (gone.contains(q.id)) {
        months.add(monthOf(localDay(q.paidAt)));
        continue;
      }
      if (mine.containsKey(q.id)) {
        final left = q.cancelledAmount - mine[q.id]!;
        final amount = left < 0 ? 0 : left;
        final other = others[q.id];
        // 남은 취소가 다른 묶음의 것뿐이면 그 가운데 가장 늦은 시각이다. 앱에서 적은 취소가 남으면 결제에 적혀 있던 시각을 둔다
        final at = amount == 0
            ? null
            : other != null && amount <= other.$2
            ? other.$1
            : q.cancelledAt;
        q = q.copyWith(cancelledAmount: amount, cancelledAt: at);
        final (from, sha) = revisionFor(
          s,
          cards[uid]!['card_id'] as String,
          q.paidAt,
        );
        s.db.execute(
          'update transactions set cancelled_amount = ?, cancelled_at = ?, revision_from = ?, revision_sha = ?, '
          'updated_at = ? where id = ?',
          [amount, at == null ? null : ms(at), from, sha, ms(now), q.id],
        );
        months.add(monthOf(localDay(q.paidAt)));
        back.add(q.id);
      }
      payments.add(q);
    }
    if (months.isEmpty) continue;
    final first = months.reduce((a, b) => b.isBefore(a) ? b : a);
    final res = repricedFrom(
      engine,
      engineCard(cards[uid]!),
      payments,
      first,
      now,
    );
    repriced += store(
      s,
      cards[uid]!['card_id'] as String,
      res,
      {for (final q in loaded[uid]!) q.id: q},
      back,
      now,
    );
  }
  return {'id': bid, 'repriced': repriced};
});
