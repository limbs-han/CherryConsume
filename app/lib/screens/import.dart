/// 이용 내역 엑셀 가져오기. 카드 고르기, 파일 고르기, 열 짝짓기, 미리보기, 저장. 가져온 묶음과 되돌리기. S11, E30~E35
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../theme.dart';

const _maxBytes = 2000000;

/// 고른 파일. 너무 크면 bytes가 null이다. 시험에서는 바꿔 끼운다
typedef PickFile = Future<({String name, Uint8List? bytes})?> Function();

Future<({String name, Uint8List? bytes})?> pickWithSystem() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv'],
  );
  if (files.isEmpty) return null;
  final f = files.first;
  try {
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
  ('approval', '승인번호'),
  ('card', '카드 이름'),
  ('region', '해외 여부'),
];

const _status = {
  'new': '새 결제',
  'duplicate': '이미 있어 넣지 않아요',
  'cancel': '원 결제에 취소로 붙여요',
  'orphan': '넣지 않아요',
  'skipped': '넣지 않아요',
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
  // 사용자가 짝지은 {칸: 열 번호}. 비우면 서버가 찾는다
  Map<String, int>? _columns;
  bool _remap = false;
  String? _error;
  bool _busy = false;
  // 늦게 온 응답이 마지막 요청의 미리보기를 덮지 않게 센다
  int _seq = 0;

  Future<void> _pick() async {
    final f = await widget.pick();
    if (f == null || !mounted) return;
    if (f.bytes == null) {
      setState(() => _error = '파일이 2MB보다 커요. 기간을 나눠 올려 주세요.');
      return;
    }
    _file = (name: f.name, bytes: f.bytes!);
    _columns = null;
    _headerRow = null;
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
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _preview = p;
        _headerRow = p.headerRow;
        _remap = p.needsMapping;
      });
    } on ApiError catch (e) {
      // 서버가 준 까닭을 그대로 보인다. 옛 xls, 카드를 고르지 않음 같은 것이다
      final detail = RegExp(r'"detail":"([^"]*)"').firstMatch(e.body)?.group(1);
      if (mounted && seq == _seq) {
        setState(() => _error = detail ?? '파일을 읽지 못했어요.');
      }
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _error = '서버에 연결하지 못했어요.');
    } finally {
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  Future<void> _save(ImportPreview p) async {
    setState(() => _busy = true);
    try {
      // 판정받은 행을 모두 보낸다. 서버가 같은 행으로 다시 판정한다. 겹친 행이 빠지면 결제나 취소가 사라진다
      final rows = [
        for (final r in p.rows)
          if (r.containsKey('paid_at')) r,
      ];
      // 사용자가 짝지은 열만 남긴다. 저장할 때 남겨 미리보기만 보고 그만둔 짝은 남지 않는다. E30
      final done = await widget.api.saveImport(
        rows,
        signature: p.signature,
        columns: _columns,
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
    setState(() => _card = id);
    // 짝짓는 중이면 덜 채운 짝으로 다시 읽지 않는다. 다시 읽기를 누를 때 고른 카드로 읽는다
    if (!_remap) _read();
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('이용 내역 가져오기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const Text(
            '카드사 웹에서 받은 이용 내역 파일을 올려요. 파일은 읽은 뒤 바로 지워요.',
            style: TextStyle(color: C.sub),
          ),
          const SizedBox(height: 16),
          const Text('어느 카드의 내역인가요', style: TextStyle(color: C.text)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.cards)
                ChoiceChip(
                  label: Text(c.name),
                  selected: _card == c.id,
                  onSelected: _busy ? null : (_) => _chooseCard(c.id),
                ),
              ChoiceChip(
                label: const Text('파일에 카드 이름이 있어요'),
                selected: _card == null,
                onSelected: _busy ? null : (_) => _chooseCard(null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _pick,
            child: Text(_file == null ? '파일 고르기' : '${_file!.name} · 다른 파일'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: C.amber)),
            ),
          if (p != null && _remap) ..._mappingView(p),
          if (p != null && !_remap && p.summary != null)
            ..._previewView(p, p.summary!),
        ],
      ),
    );
  }

  /// 열 짝짓기. 열 이름을 못 찾았을 때와 사용자가 다시 짝지을 때다. E30
  List<Widget> _mappingView(ImportPreview p) {
    final row = _headerRow ?? p.headerRow;
    final headers = row < p.topRows.length ? p.topRows[row] : p.headers;
    // 머리 줄을 바꾸거나 열이 밀려도 없는 열을 고른 채로 두지 않는다
    final columns = {
      for (final e in (_columns ?? p.mapping ?? const <String, int>{}).entries)
        if (e.value < headers.length && headers[e.value].isNotEmpty)
          e.key: e.value,
    };
    final used = columns.values.toList();
    final ok =
        ['date', 'merchant', 'amount'].every(columns.containsKey) &&
        used.toSet().length == used.length;
    return [
      const SizedBox(height: 16),
      const Text(
        '어느 열이 무엇인지 짝지어 주세요',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const Text(
        '한 열은 한 칸에만 골라요. 결제일, 가맹점명, 금액은 꼭 골라요.',
        style: TextStyle(fontSize: 13, color: C.sub),
      ),
      // 위에 조회 기간이나 카드 정보 줄이 있으면 열 이름이 있는 줄을 고른다
      if (p.topRows.length > 1)
        Row(
          children: [
            const SizedBox(width: 96, child: Text('열 이름 줄')),
            Expanded(
              child: DropdownButton<int>(
                key: const Key('map-row'),
                isExpanded: true,
                value: row,
                items: [
                  for (final (i, r) in p.topRows.indexed)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${i + 1}줄 · ${r.where((c) => c.isNotEmpty).take(3).join(', ')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _headerRow = v;
                  _columns = {};
                }),
              ),
            ),
          ],
        ),
      for (final (key, label) in _fields)
        Row(
          children: [
            SizedBox(width: 96, child: Text(label)),
            Expanded(
              child: DropdownButton<int?>(
                key: Key('map-$key'),
                isExpanded: true,
                value: columns[key],
                hint: const Text('없음'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('없음')),
                  for (final (i, h) in headers.indexed)
                    if (h.isNotEmpty)
                      DropdownMenuItem<int?>(value: i, child: Text(h)),
                ],
                onChanged: (v) => setState(() {
                  final next = Map.of(columns);
                  if (v == null) {
                    next.remove(key);
                  } else {
                    next[key] = v;
                  }
                  _columns = next;
                }),
              ),
            ),
          ],
        ),
      FilledButton(
        onPressed: ok && !_busy
            ? () {
                _columns = columns;
                _read();
              }
            : null,
        child: const Text('다시 읽기'),
      ),
    ];
  }

  List<Widget> _previewView(ImportPreview p, Map<String, dynamic> s) {
    final lines = [
      '새 결제 ${s['new']}건 · ${won(s['amount'] as int)}',
      if (s['duplicates'] > 0) '이미 있는 결제 ${s['duplicates']}건은 넣지 않아요',
      if (s['cancels'] > 0) '취소 ${s['cancels']}건을 원 결제에 붙여요',
      if (s['orphans'] > 0) '원 결제가 없거나 담지 못하는 취소 ${s['orphans']}건은 넣지 않아요',
      if (s['skipped'] > 0) '보유 카드가 아닌 행 ${s['skipped']}건은 넣지 않아요',
      if (s['errors'] > 0) '읽지 못한 행 ${s['errors']}건',
      if (s['uncategorized'] > 0)
        '업종을 모르는 결제 ${s['uncategorized']}건은 기록에서 고칠 수 있어요',
      if ((s['interest_unknown'] ?? 0) > 0)
        '무이자인지 모르는 할부 ${s['interest_unknown']}건은 유이자로 넣어요. 기록에서 고칠 수 있어요',
      if ((s['untimed'] ?? 0) > 0)
        '시각이 없는 결제 ${s['untimed']}건은 시간대 할인을 확인 필요로 둬요',
      '결제수단은 실물카드로 넣어요. 간편결제 이름이 찍힌 ${s['easy_pay'] ?? 0}건은 그 결제수단이에요',
    ];
    final ready = s['new'] > 0 || s['cancels'] > 0;
    return [
      const SizedBox(height: 16),
      Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(l, style: const TextStyle(color: C.text)),
              ),
          ],
        ),
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _remap = true),
        child: const Text('열 다시 짝짓기'),
      ),
      for (final r in p.rows.take(100))
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('${r['merchant_name']} · ${won(r['amount'] as int)}'),
          subtitle: Text(
            [
              if (r['card_name'] != null) r['card_name'],
              _status[r['status']] ?? '',
              if (r['reason'] != null) r['reason'],
            ].join(' · '),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: ready && !_busy ? () => _save(p) : null,
        child: const Text('저장'),
      ),
    ];
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

  /// 가져온 날. 서버 시각을 폰 시간으로 바꿔 보인다
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
            child: Text('서버에 연결하지 못했어요.'),
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
