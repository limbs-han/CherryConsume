/// 카드 정보와 설정에서 쓰는 답 고르기. 사용자가 답할 것은 파랑으로 묻는다. 작업 004 설계 3.1, 작업 005 설계 5e
library;

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../ui.dart';

/// 사실 하나의 고를 것. bool은 예와 아니오, month는 1~12월, choice는 선택지다
List<(Object, String)> factChoices(FactQuestion q) => switch (q.type) {
  'bool' => [(true, '예'), (false, '아니오')],
  'month' => [for (var m = 1; m <= 12; m++) (m, '$m월')],
  _ => [for (final c in q.choices ?? const <String>[]) (c, c)],
};

/// 긴 질문은 첫 문장을 제목, 나머지를 설명으로 나눈다. 한 문장이면 나머지가 없다. 작업 011 설계 2절 S4
(String, String?) firstSentence(String text) {
  final m = RegExp(r'^(.+?[?.])\s+(.+)$', dotAll: true).firstMatch(text);
  return m == null ? (text, null) : (m[1]!, m[2]);
}

/// 사실 하나를 답하는 줄. 질문의 첫 문장이 제목이고 나머지와 note가 설명이다. 오른쪽에 답이나 답하기 배지가 있고 누르면
/// 바닥 시트에서 고른다. 작업 011 설계 2절 S1, S4, T3
class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.q,
    required this.onAnswer,
    this.note,
  });
  final FactQuestion q;
  final ValueChanged<Object> onAnswer;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final (title, rest) = firstSentence(q.ask);
    final choices = factChoices(q);
    final sub = [?rest, ?note].join('\n');
    return TapRow(
      title: title,
      sub: sub.isEmpty ? null : sub,
      trailing: q.answer == null
          ? const Pill('답하기')
          : RowValue(
              choices
                  .firstWhere(
                    (c) => c.$1 == q.answer,
                    orElse: () => (q.answer!, '${q.answer}'),
                  )
                  .$2,
            ),
      onTap: () async {
        final v = await pickSheet<Object>(
          context,
          title: q.ask,
          options: choices,
          selected: q.answer,
        );
        if (v != null) onAnswer(v);
      },
    );
  }
}

/// 옵션 하나를 고르는 줄. 다음 달부터 바뀌는 답은 설명에 쓴다. 계산하지 않는 선택지도 고를 수 있고 그 카드의 혜택은
/// 확인 필요로 보인다. 작업 011 설계 2절 T3
class OptionRow extends StatelessWidget {
  const OptionRow({super.key, required this.q, required this.onAnswer});
  final OptionQuestion q;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final titles = {for (final c in q.choices) c.key: c.title};
    final from = q.pendingFrom == null ? null : DateTime.parse(q.pendingFrom!);
    return TapRow(
      title: q.title,
      sub: from == null
          ? null
          : '${from.month}월 ${from.day}일부터 ${titles[q.pendingValue]}',
      trailing: q.answer == null
          ? const Pill('고르기')
          : RowValue(titles[q.answer] ?? q.answer!),
      onTap: () async {
        final v = await pickSheet<String>(
          context,
          title: q.title,
          options: [
            for (final c in q.choices)
              (
                c.key,
                q.unsupported.contains(c.key) ? '${c.title} · 계산 안 함' : c.title,
              ),
          ],
          selected: q.answer,
        );
        if (v != null) onAnswer(v);
      },
    );
  }
}

/// 답한 뒤의 알림. 다시 계산한 결제가 있으면 그 수를 알린다
void answered(BuildContext context, int repriced) {
  // 답을 잇달아 하면 앞 알림이 뒤 알림을 가리지 않게 닫는다
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          repriced > 0 ? '결제 $repriced건의 혜택을 다시 계산했어요.' : '답을 적었어요.',
        ),
      ),
    );
}
