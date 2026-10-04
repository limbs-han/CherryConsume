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

/// 사실 하나
class FactAnswer extends StatelessWidget {
  const FactAnswer({
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
    return _Ask(
      title: q.ask,
      note: note,
      chips: [
        for (final (value, label) in factChoices(q))
          ChoicePill(
            label,
            selected: q.answer == value,
            onTap: () => onAnswer(value),
          ),
      ],
    );
  }
}

/// 옵션 하나. 계산하지 않는 선택지도 고를 수 있고 그 카드의 혜택은 확인 필요로 보인다
class OptionAnswer extends StatelessWidget {
  const OptionAnswer({super.key, required this.q, required this.onAnswer});
  final OptionQuestion q;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final titles = {for (final c in q.choices) c.key: c.title};
    final from = q.pendingFrom == null ? null : DateTime.parse(q.pendingFrom!);
    return _Ask(
      title: q.title,
      note: from == null
          ? null
          : '${from.month}월 ${from.day}일부터 ${titles[q.pendingValue]}',
      chips: [
        for (final c in q.choices)
          ChoicePill(
            q.unsupported.contains(c.key) ? '${c.title} · 계산 안 함' : c.title,
            selected: q.answer == c.key,
            onTap: () => onAnswer(c.key),
          ),
      ],
    );
  }
}

class _Ask extends StatelessWidget {
  const _Ask({required this.title, required this.chips, this.note});
  final String title;
  final String? note;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: C.text)),
        if (note != null)
          Text(note!, style: const TextStyle(fontSize: 13, color: C.sub)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    ),
  );
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
