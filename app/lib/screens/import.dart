/// 이용 내역 엑셀 가져오기. 카드 고르기, 파일 고르기, 열 짝짓기, 미리보기, 저장. 가져온 묶음과 되돌리기. S11, E30~E35
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';
import '../ui.dart';

const _maxBytes = 2000000;

/// 고른 파일. 너무 크면 bytes가 null이다. 시험에서는 바꿔 끼운다
typedef PickFile = Future<({String name, Uint8List? bytes})?> Function();

Future<({String name, Uint8List? bytes})?> pickWithSystem() async {
  // 고르기 안에서 복사가 실패해도 사본 조각을 지우게 고르기부터 감싼다. 작업 006 단계 6 위험 검토 5번
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );
    if (files.isEmpty) return null;
    final f = files.first;
    final size = await f.length();
    if (size != null && size > _maxBytes) return (name: f.name, bytes: null);
    // 크기를 모르면 읽은 뒤에 본다
    final bytes = await f.readAsBytes();
    return (name: f.name, bytes: bytes.length > _maxBytes ? null : bytes);
  } finally {
    // Android는 고른 파일을 앱 임시 폴더에 복사한다. 읽기가 실패해도 이용 내역 사본이 폰에 남지 않게 지운다. E35
    await FilePicker.clearTemporaryFiles();
  }
}

/// 짝지을 칸. 앞의 셋은 꼭 있어야 한다. 작업 005 설계 5f
const _fields = [
  ('date', '결제일'),
  ('merchant', '가맹점명'),
  ('amount', '금액'),
  ('time', '시각'),
  ('installment', '할부'),
  ('interest_free', '무이자 여부'),
  ('cancel', '취소 여부'),
  ('cancel_amount', '취소금액'),
  ('approval', '승인번호'),
  ('card', '카드 이름'),
  ('region', '해외 여부'),
];

const _guideText = TextStyle(fontSize: 15, color: C.text, height: 1.5);

/// 미리보기 목록을 한 번에 그리는 줄 수
const _page = 100;

const _status = {
  'new': '새 결제',
  'duplicate': '이미 있어 넣지 않아요',
  'cancel': '원 결제에 취소로 붙여요',
  'orphan': '넣지 않아요',
  'skipped': '넣지 않아요',
  'discount': '카드 할인이라 넣지 않아요',
  'error': '읽지 못했어요',
};

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.api,
    required this.cards,
    this.pick = pickWithSystem,
  });
  final Api api;
  final List<({String id, String name})> cards;
  final PickFile pick;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // 고르면 그 카드로 넣는다. 비우면 파일의 카드 이름 열로 나눈다. E33
  late String? _card = widget.cards.length == 1 ? widget.cards.first.id : null;
  ({String name, Uint8List bytes})? _file;
  ImportPreview? _preview;
  int? _headerRow;
  // 사용자가 짝지은 {칸: 열 번호}. 비우면 저장소가 찾는다
  Map<String, int>? _columns;
  // 사용자가 고른 {카드 칸 값: 보유 카드}. 작업 017 설계 3절
  Map<String, String> _codes = {};
  bool _remap = false;
  // 미리보기 목록에 보이는 넣는 줄과 넣지 않는 줄 수, 넣지 않는 줄을 펼쳤는가
  int _more = _page, _restMore = _page;
  bool _restOpen = false;
  String? _error;
  bool _busy = false;
  // 늦게 온 응답이 마지막 요청의 미리보기를 덮지 않게 센다
  int _seq = 0;

  Future<void> _pick() async {
    final f = await widget.pick();
    if (f == null || !mounted) return;
    if (f.bytes == null) {
      // 앞 파일을 지운다. 남기면 아래 저장 버튼이 켜진 채로 앞 파일을 저장한다. 작업 011 위험 검토 5번
      setState(() {
        _file = null;
        _preview = null;
        _error = '파일이 2MB보다 커요. 기간을 나눠 올려 주세요.';
      });
      return;
    }
    _file = (name: f.name, bytes: f.bytes!);
    _columns = null;
    _headerRow = null;
    _codes = {};
    _remap = false;
    await _read();
  }

  Future<void> _read() async {
    final f = _file;
    if (f == null) return;
    final seq = ++_seq;
    setState(() {
      _busy = true;
      _error = null;
      // 실패해도 옛 미리보기로 저장하지 않게 지운다
      _preview = null;
    });
    try {
      final p = await widget.api.importPreview(
        f.bytes,
        userCardId: _card,
        headerRow: _headerRow,
        columns: _columns == null ? null : Map.of(_columns!),
        codes: _codes.isEmpty ? null : Map.of(_codes),
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _preview = p;
        _headerRow = p.headerRow;
        _remap = p.needsMapping;
        _more = _restMore = _page;
        _restOpen = false;
      });
    } on ApiError catch (e) {
      // 저장소가 준 까닭을 그대로 보인다. 옛 xls, 2MB 넘는 파일, 카드를 고르지 않음 같은 것이다
      final detail = e.status == 413 || e.status == 422 ? e.body : null;
      if (mounted && seq == _seq) {
        setState(() => _error = detail ?? '파일을 읽지 못했어요.');
      }
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _error = '파일을 읽지 못했어요.');
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  Future<void> _save(ImportPreview p) async {
    setState(() => _busy = true);
    try {
      // 판정받은 행을 모두 보낸다. 저장소가 같은 행으로 다시 판정한다. 겹친 행이 빠지면 결제나 취소가 사라진다
      final rows = [
        for (final r in p.rows)
          if (r.containsKey('paid_at')) r,
      ];
      // 사용자가 짝지은 열만 남긴다. 저장할 때 남겨 미리보기만 보고 그만둔 짝은 남지 않는다. E30
      final done = await widget.api.saveImport(
        rows,
        signature: p.signature,
        columns: _columns,
        source: p.source,
        // 고른 카드 칸 짝만 남긴다. 위에서 고른 카드로 들어간 값은 남기지 않는다
        format: p.format,
        codes: _codes,
      );
      if (mounted) Navigator.of(context).pop(done['imported'] as int);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요.')));
      }
    }
  }

  void _chooseCard(String? id) {
    // 고르기 줄에서 고른 짝이 새로 고른 카드를 말없이 이기지 않게 비운다. 단계 2 재검토 중간 1
    setState(() {
      _card = id;
      _codes = {};
    });
    // 짝짓는 중이면 덜 채운 짝으로 다시 읽지 않는다. 다시 읽기를 누를 때 고른 카드로 읽는다
    if (!_remap) _read();
  }

  /// 엑셀 받는 곳 안내. 작업 011 설계 2절 I1
  void _guide() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '엑셀은 어디서 받나요',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12),
            Text(
              '카드사 PC 웹사이트의 이용 내역 조회에서 기간을 정해 엑셀로 내려받아요. 받은 파일을 폰으로 옮긴 뒤 여기서 골라요.',
              style: _guideText,
            ),
            SizedBox(height: 8),
            Text(
              '열 이름을 알아보지 못하면 어느 열이 결제일, 가맹점명, 금액인지 짝지어 달라고 물어요.',
              style: _guideText,
            ),
            SizedBox(height: 8),
            Text(
              '파일은 2MB까지 올릴 수 있어요. 읽은 뒤 바로 지우고 폰 밖으로 보내지 않아요.',
              style: _guideText,
            ),
          ],
        ),
      ),
    ),
  );

  /// 아래에 고정한 단계 버튼. 파일 고르기, 다시 읽기, 저장 차례다. 작업 011 설계 1절 원칙 1
  Widget _action(ImportPreview? p) {
    if (p != null && _remap) {
      final m = _mapped(p);
      return FilledButton(
        onPressed: m.ok && !_busy
            ? () {
                _columns = {..._cleared(p), ...m.columns};
                _read();
              }
            : null,
        child: const Text('다시 읽기'),
      );
    }
    final s = p?.summary;
    if (p != null && s != null) {
      final ready = s['new'] > 0 || s['cancels'] > 0;
      return FilledButton(
        onPressed: ready && !_busy ? () => _save(p) : null,
        // 시안대로 넣을 건수를 버튼에 쓴다. 취소만 붙이는 파일은 건수 없이 저장이다. 작업 011 설계 2절 I3
        child: Text(s['new'] > 0 ? '${s['new']}건 저장' : '저장'),
      );
    }
    return FilledButton(
      onPressed: _busy ? null : _pick,
      child: const Text('파일 고르기'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final read = p != null && !_remap;
    return Scaffold(
      appBar: AppBar(title: const Text('이용 내역 가져오기')),
      body: WithAction(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        action: _action(p),
        children: [
          const Text(
            '카드사 웹에서 받은 이용 내역 파일을 올려요. 파일은 읽은 뒤 바로 지워요.',
            style: TextStyle(color: C.sub),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _guide,
              style: TextButton.styleFrom(
                foregroundColor: C.blue,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 6),
                  Text('엑셀은 어디서 받나요'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '어느 카드의 내역인가요',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: C.sub,
            ),
          ),
          const SizedBox(height: 8),
          // 시안대로 알약이다. 작업 011 설계 2절 G2
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.cards)
                ChoicePill(
                  c.name,
                  selected: _card == c.id,
                  onTap: () {
                    if (!_busy) _chooseCard(c.id);
                  },
                ),
              ChoicePill(
                '파일에 카드 이름이 있어요',
                selected: _card == null,
                onTap: () {
                  if (!_busy) _chooseCard(null);
                },
              ),
            ],
          ),
          if (_file != null) ...[
            const SizedBox(height: 16),
            // 고른 파일. 시안대로 이름과 다른 파일 고르기다. 설계 2절 I1
            Box(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Icon(
                    read ? Icons.check : Icons.description_outlined,
                    size: 20,
                    color: read ? C.green : C.sub,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _file!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: C.text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _pick,
                    style: TextButton.styleFrom(
                      foregroundColor: C.blue,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('다른 파일'),
                  ),
                ],
              ),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: C.sub)),
            ),
          if (p != null && _remap) ..._mappingView(p),
          if (read && p.summary != null) ..._previewView(p, p.summary!),
        ],
      ),
    );
  }

  /// 사용자가 "없음"으로 비운 칸. -1로 보내고 저장해야 다음에 기억한 짝을 자동으로 채울 때 되살리지 않는다. E30
  Map<String, int> _cleared(ImportPreview p) => {
    for (final e in (_columns ?? p.mapping ?? const <String, int>{}).entries)
      if (e.value < 0) e.key: e.value,
  };

  /// 짝지은 열. 머리 줄을 바꾸거나 열이 밀려도 없는 열을 고른 채로 두지 않는다
  ({List<String> headers, Map<String, int> columns, bool ok}) _mapped(
    ImportPreview p,
  ) {
    final row = _headerRow ?? p.headerRow;
    final headers = row < p.topRows.length ? p.topRows[row] : p.headers;
    final columns = {
      for (final e in (_columns ?? p.mapping ?? const <String, int>{}).entries)
        if (e.value >= 0 &&
            e.value < headers.length &&
            headers[e.value].isNotEmpty)
          e.key: e.value,
    };
    // 결제일 칸에 시각이 함께 든 파일은 시각도 그 열을 고를 수 있다. 저장소 findHeader와 같다. E30
    final used = [
      for (final MapEntry(:key, :value) in columns.entries)
        if (key != 'time' || value != columns['date']) value,
    ];
    final ok =
        ['date', 'merchant', 'amount'].every(columns.containsKey) &&
        used.toSet().length == used.length;
    return (headers: headers, columns: columns, ok: ok);
  }

  /// 열 짝짓기. 열 이름을 못 찾았을 때와 사용자가 다시 짝지을 때다. E30
  List<Widget> _mappingView(ImportPreview p) {
    final row = _headerRow ?? p.headerRow;
    final (:headers, :columns, ok: _) = _mapped(p);
    // 자동으로 찾은 짝은 저장소가 찾은 머리 줄의 열 번호다. 열 이름 줄을 바꾸면 견주지 않는다
    final auto = row == p.headerRow ? p.autoMapping : null;
    String rowLabel(int i) =>
        '${i + 1}줄 · ${p.topRows[i].where((c) => c.isNotEmpty).take(3).join(', ')}';
    return [
      const SizedBox(height: 16),
      const Text(
        '어느 열이 무엇인지 짝지어 주세요',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const Text(
        '결제일과 시각 말고는 한 열을 한 칸에만 골라요. 결제일, 가맹점명, 금액은 꼭 골라요. '
        '열 이름 줄이 없는 파일은 카드사에서 다른 저장 방식으로 받아 주세요. 기업은행은 출력용으로 받으면 돼요.',
        style: TextStyle(fontSize: 13, color: C.sub),
      ),
      // 위에 조회 기간이나 카드 정보 줄이 있으면 열 이름이 있는 줄을 고른다
      if (p.topRows.length > 1)
        Row(
          children: [
            const SizedBox(width: 96, child: Text('열 이름 줄')),
            Expanded(
              child: _PickField(
                key: const Key('map-row'),
                label: rowLabel(row),
                onTap: () async {
                  final v = await pickSheet<int>(
                    context,
                    title: '열 이름 줄',
                    options: [
                      for (final (i, _) in p.topRows.indexed) (i, rowLabel(i)),
                    ],
                    selected: row,
                  );
                  // 같은 줄을 다시 고르면 고른 짝과 비운 칸을 지우지 않는다
                  if (v != null && v != row) {
                    setState(() {
                      _headerRow = v;
                      _columns = {};
                    });
                  }
                },
              ),
            ),
          ],
        ),
      for (final (key, label) in _fields) ...[
        Row(
          children: [
            SizedBox(width: 96, child: Text(label)),
            Expanded(
              child: _PickField(
                key: Key('map-$key'),
                label: columns[key] == null ? '없음' : headers[columns[key]!],
                onTap: () async {
                  // 시트를 그냥 닫으면 null이라 없음은 -1로 고른다
                  final v = await pickSheet<int>(
                    context,
                    title: label,
                    options: [
                      (-1, '없음'),
                      for (final (i, h) in headers.indexed)
                        if (h.isNotEmpty) (i, h),
                    ],
                    selected: columns[key] ?? -1,
                  );
                  if (v == null) return;
                  setState(() {
                    // "없음"은 -1로 남긴다. 기억한 짝을 다음에 자동으로 채울 때 사용자가 비운 칸을 되살리지 않는다. E30
                    _columns = {
                      ..._cleared(p),
                      ...columns,
                      key: v < 0 ? -1 : v,
                    };
                  });
                },
              ),
            ),
          ],
        ),
        // 자동으로 찾은 열과 다르게 고르거나 비우면 알린다. 작업 015 설계 4절 2
        if (auto?[key] case final a?
            when a < headers.length && columns[key] != a)
          Padding(
            padding: const EdgeInsets.only(left: 96, bottom: 4),
            child: Text(
              '자동으로 찾은 열: ${headers[a]}. 바꾸면 결과가 달라질 수 있어요. 미리보기 숫자를 확인해 주세요',
              style: const TextStyle(fontSize: 12, color: C.sub),
            ),
          ),
      ],
    ];
  }

  /// 미리보기. 시안대로 숫자 타일, 카드와 달과 합계, 날짜가 든 줄이다. 업종을 여기서 정하는 칩은 새 기능이라 두지 않는다.
  /// 작업 011 설계 2절 I3
  List<Widget> _previewView(ImportPreview p, Map<String, dynamic> s) {
    final auto = p.autoMapping;
    final notes = [
      // 기억한 짝이나 고른 짝이 자동으로 찾은 머리 줄이나 짝과 다르면 알린다. 2026-10-05 실제 폰에서 기억한 짝이 취소
      // 여부를 비워 취소와 할인 줄이 읽지 못한 행이 됐다. 작업 015 설계 4절 2
      if (p.autoHeaderRow != null &&
          (p.autoHeaderRow != p.headerRow ||
              (auto?.entries.any((e) => p.mapping?[e.key] != e.value) ??
                  false)))
        '자동으로 찾은 열 짝과 다르게 읽었어요. 열 다시 짝짓기에서 확인해 주세요',
      if (s['cancels'] > 0) '취소 ${s['cancels']}건을 원 결제에 붙여요',
      if (s['orphans'] > 0) '원 결제가 없거나 담지 못하는 취소 ${s['orphans']}건은 넣지 않아요',
      if ((s['unpaired'] ?? 0) > 0)
        '어느 카드인지 고르지 않은 행 ${s['unpaired']}건은 넣지 않아요',
      if (s['skipped'] > 0)
        '${_card == null ? '보유 카드' : '고른 카드'}가 아닌 행 ${s['skipped']}건은 넣지 않아요',
      if ((s['discounts'] ?? 0) > 0)
        '카드가 준 할인 ${s['discounts']}건은 결제가 아니라 넣지 않아요. 혜택은 앱이 따로 계산해요',
      if (s['errors'] > 0) '읽지 못한 행 ${s['errors']}건',
      if (s['uncategorized'] > 0)
        '업종을 모르는 결제 ${s['uncategorized']}건은 기록에서 고칠 수 있어요',
      if ((s['installment_assumed'] ?? 0) > 0)
        '신용카드 결제 ${s['installment_assumed']}건은 할부인지 몰라 일시불로 넣어요. 할부 결제는 기록에서 고쳐 주세요',
      if ((s['interest_unknown'] ?? 0) > 0)
        '무이자인지 모르는 할부 ${s['interest_unknown']}건은 유이자로 넣어요. 기록에서 고칠 수 있어요',
      if ((s['untimed'] ?? 0) > 0)
        '시각이 없는 결제 ${s['untimed']}건은 시간대 할인을 확인 필요로 둬요',
      '결제수단은 실물카드로 넣어요. 간편결제 이름이 찍힌 ${s['easy_pay'] ?? 0}건은 그 결제수단이에요',
    ];
    // 결제 시각 글자의 앞 7자리가 한국 시간 연월이다
    final months = {
      for (final r in p.rows)
        if (r['paid_at'] case final String at) at.substring(0, 7),
    }.toList()..sort();
    String month(String ym) =>
        '${ym.substring(0, 4)}년 ${int.parse(ym.substring(5))}월';
    final period = months.isEmpty
        ? null
        : months.length == 1
        ? month(months.first)
        : '${month(months.first)} ~ ${month(months.last)}';
    // 카드 칸 값이 둘 이상이면 줄마다 다른 카드로 들어간다. 단계 2 위험 검토 높음 1
    final many = _card == null || p.cardCodes.length > 1;
    final card = many
        ? '여러 카드'
        : widget.cards.firstWhere((c) => c.id == _card).name;
    // 넣는 줄은 모두 보이고 넣지 않는 줄은 접어 둔다. 길면 100줄씩 더 본다. 2026-10-06 사용자가 뱅크샐러드 파일에서 다른
    // 카드라 빠지는 줄이 새 결제처럼 섞여 보이고 앞 100줄인 최근 한 달만 보인다고 해 정했다
    bool saving(Map r) => r['status'] == 'new' || r['status'] == 'cancel';
    final kept = [
      for (final r in p.rows)
        if (saving(r)) r,
    ];
    final rest = [
      for (final r in p.rows)
        if (!saving(r)) r,
    ];
    List<Widget> rows(
      List<Map<String, dynamic>> list,
      int limit,
      VoidCallback more,
    ) => [
      if (list.isNotEmpty)
        Box(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (final (i, r) in list.take(limit).indexed) ...[
                if (i > 0) const Divider(height: 1, color: C.line),
                _PreviewRow(r, showCard: many),
              ],
            ],
          ),
        ),
      if (list.length > limit)
        Center(
          child: TextButton(
            onPressed: more,
            child: Text(
              '${list.length - limit < _page ? list.length - limit : _page}건 더 보기',
            ),
          ),
        ),
    ];
    return [
      // 읽은 형식이나 모르는 형식 안내. 작업 015 설계 4절 3
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(
          p.formatName == null
              ? '처음 보는 형식이라 열 짝을 확인해 주세요'
              : '${p.formatName} 형식으로 읽었어요',
          style: const TextStyle(fontSize: 13, color: C.sub),
        ),
      ),
      // 카드 칸 값이 둘 이상이거나 짝이 없는 값이 있으면 값마다 보유 카드를 고른다. 작업 017 설계 3절
      if (p.cardCodes.length > 1 ||
          p.cardCodes.any((c) => c.userCardId == null)) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            '파일에 카드가 여럿이에요. 카드 칸 값마다 어느 카드인지 골라 주세요',
            style: TextStyle(fontSize: 13, color: C.sub),
          ),
        ),
        for (final (i, c) in p.cardCodes.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text('${c.code} · ${c.count}건')),
                Expanded(
                  child: _PickField(
                    key: Key('code-$i'),
                    label:
                        [
                          for (final k in widget.cards)
                            if (k.id == c.userCardId) k.name,
                        ].firstOrNull ??
                        '카드 고르기',
                    onTap: () async {
                      final v = await pickSheet<String>(
                        context,
                        title: '${c.code} 카드',
                        options: [for (final k in widget.cards) (k.id, k.name)],
                        selected: c.userCardId,
                      );
                      if (v == null || !mounted) return;
                      _codes = {..._codes, c.code: v};
                      _read();
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
      Row(
        children: [
          _Tile('읽은 행', s['rows'] as int),
          const SizedBox(width: 8),
          _Tile('저장 예정', s['new'] as int, fg: C.green, bg: C.greenSoft),
          const SizedBox(width: 8),
          _Tile('중복 제외', s['duplicates'] as int),
          const SizedBox(width: 8),
          _Tile('업종 미정', s['uncategorized'] as int, fg: C.blue, bg: C.blueSoft),
        ],
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [card, ?period].join(' · '),
                style: const TextStyle(fontSize: 14, color: C.sub),
              ),
            ),
            Text(
              '합계 ${won(s['amount'] as int)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: C.text,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: Text(n, style: const TextStyle(fontSize: 13, color: C.sub)),
        ),
      // 아는 형식은 형식 표로만 읽는다. 손으로 고른 열과 형식 규칙이 엇갈리지 않게 한다. 작업 015 설계 2절 2
      if (p.format == null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => setState(() => _remap = true),
            child: const Text('열 다시 짝짓기'),
          ),
        ),
      ...rows(kept, _more, () => setState(() => _more += _page)),
      if (rest.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _restOpen = !_restOpen),
            child: Text(
              _restOpen ? '넣지 않는 줄 접기' : '넣지 않는 줄 ${rest.length}건 보기',
            ),
          ),
        ),
      if (_restOpen)
        ...rows(rest, _restMore, () => setState(() => _restMore += _page)),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text(
          '저장하면 그 달 혜택과 다음 달 구간을 다시 계산해요. 가져온 묶음에서 통째로 되돌릴 수 있어요.',
          style: TextStyle(fontSize: 12, color: C.sub),
        ),
      ),
    ];
  }
}

/// 미리보기 숫자 타일 하나
class _Tile extends StatelessWidget {
  const _Tile(
    this.label,
    this.value, {
    this.fg = C.text,
    this.bg = Colors.white,
  });
  final String label;
  final int value;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(color: bg, borderRadius: r16),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: C.sub,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 미리보기 한 줄. 날짜, 가맹점, 업종과 상태, 금액이다. 취소는 금액 앞에 빼기를 붙인다
class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.r, {required this.showCard});
  final Map<String, dynamic> r;
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    final at = r['paid_at'] as String?;
    final cancel = r['status'] == 'cancel';
    // 카드 할인 줄은 결제가 아니라 업종과 사유를 붙이지 않는다
    final sub = r['status'] == 'discount'
        ? _status['discount']!
        : [
            r['category_name'] ?? '업종 미정',
            if (showCard && r['card_name'] != null) r['card_name'],
            if (r['status'] != 'new' && !cancel) _status[r['status']] ?? '',
            if (r['reason'] != null) r['reason'],
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              at == null
                  ? ''
                  : '${int.parse(at.substring(5, 7))}/${int.parse(at.substring(8, 10))}',
              style: const TextStyle(fontSize: 13, color: C.sub),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['merchant_name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: C.text,
                  ),
                ),
                Text(sub, style: const TextStyle(fontSize: 12, color: C.sub)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${cancel ? '-' : ''}${comma(r['amount'] as int? ?? 0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: C.text,
                ),
              ),
              if (cancel)
                const Text('취소', style: TextStyle(fontSize: 12, color: C.sub)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 가져온 묶음과 되돌리기. E34
class ImportsScreen extends StatefulWidget {
  const ImportsScreen({super.key, required this.api});
  final Api api;

  @override
  State<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends State<ImportsScreen> {
  late Future<List<Map<String, dynamic>>> _batches = widget.api.imports();
  bool _changed = false;

  Future<void> _undo(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 묶음을 되돌릴까요?'),
        content: Text('가져온 결제 ${b['imported_count']}건을 지우고 이 묶음이 붙인 취소를 빼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('되돌리기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.undoImport(b['id'] as int);
      _changed = true;
      if (mounted) {
        setState(() {
          _batches = widget.api.imports();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('되돌리지 못했어요.')));
      }
    }
  }

  /// 가져온 날. 저장한 시각을 폰 시간으로 바꿔 보인다
  String _day(String at) {
    final d = DateTime.parse(at).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_changed);
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('가져온 묶음')),
      body: FutureBuilder(
        future: _batches,
        builder: (context, snap) => switch (snap) {
          AsyncSnapshot(hasError: true) => const Center(
            child: Text('가져온 묶음을 불러오지 못했어요.'),
          ),
          AsyncSnapshot(:final data?) when data.isEmpty => const Center(
            child: Text('가져온 묶음이 없어요.'),
          ),
          AsyncSnapshot(:final data?) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              for (final b in data)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_day(b['created_at'] as String)} 가져오기'),
                  subtitle: Text(
                    '결제 ${b['imported_count']}건 · 취소 ${b['cancel_count']}건'
                    '${b['undone_at'] == null ? '' : ' · 되돌림'}',
                  ),
                  trailing: b['undone_at'] == null
                      ? TextButton(
                          onPressed: () => _undo(b),
                          child: const Text('되돌리기'),
                        )
                      : null,
                ),
            ],
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    ),
  );
}

/// 열 짝짓기 칸. 누르면 바닥 시트에서 고른다. 고를 것이 넷 이상이면 바닥 시트다. 설계 문서 10절 원칙 5, 작업 013 13-18
class _PickField extends StatelessWidget {
  const _PickField({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.expand_more, color: C.sub),
        ],
      ),
    ),
  );
}
