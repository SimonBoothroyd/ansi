import 'dart:convert';

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/ask/domain/ask_screen.dart';
import 'package:ansi/features/ask/domain/ask_thread.dart';
import 'package:flutter_test/flutter_test.dart';

AskTurn _answer(String text, {bool thinking = true}) => AskTurn(
  role: AskRole.assistant,
  blocks: [
    if (thinking) {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
    {'type': 'text', 'text': text},
  ],
);

AskThread _thread(int questions) {
  final now = DateTime.utc(2026, 10, 19, 18);
  var t = const AskThread();
  for (var i = 0; i < questions; i++) {
    t = t
        .plus(AskTurn.question('<screen>{}</screen>', 'q$i'), now)
        .plus(_answer('a$i'), now);
    t = t.copyWith(
      exchanges: [
        ...t.exchanges,
        AskExchange(question: 'q$i'),
      ],
    );
  }
  return t;
}

void main() {
  group('the screen block', () {
    test('a recipe screen carries the servings the stepper shows', () {
      const screen = AskRecipeScreen(
        recipeId: 'r1',
        title: 'Ragù',
        servings: 6,
        servingsBase: 4,
        struckSteps: [1, 2],
      );
      expect(screen.chipLabel, 'Ragù · serves 6');
      final block = screen.blockOn(
        AskToday(date: DateTime.utc(2026, 10, 21), shape: WeekShape.monday),
      );
      final json =
          jsonDecode(
                block.substring(
                  '<screen>'.length,
                  block.length - '</screen>'.length,
                ),
              )
              as Map<String, Object?>;
      expect(json['servings'], 6);
      expect(json['struck_steps'], [1, 2]);
      expect(json.containsKey('week'), isFalse);
    });

    test('a dismissed chip sends a screen that names nothing', () {
      expect(const AskNoScreen().toJson(), {'route': 'other'});
      expect(const AskNoScreen().chipLabel, isNull);
    });

    test('a question opens with its screen', () {
      final q = AskTurn.question('<screen>{"route":"other"}</screen>', 'hi');
      expect(q.isQuestion, isTrue);
      expect(q.toJson(), {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '<screen>{"route":"other"}</screen>\nhi'},
        ],
      });
    });
  });

  group('the thread', () {
    test('goes stale after 30 idle minutes, not before', () {
      final last = DateTime.utc(2026, 10, 19, 18);
      final t = AskThread(lastActivity: last);
      expect(t.isStale(last.add(const Duration(minutes: 29))), isFalse);
      expect(t.isStale(last.add(const Duration(minutes: 30))), isTrue);
      expect(const AskThread().isStale(last), isFalse);
    });

    test('under the cap it is left exactly as it was — append-only', () {
      final t = _thread(3);
      expect(identical(t.trimmed(), t), isTrue);
    });

    test('past the cap the oldest questions go, cut at a question', () {
      final t = _thread(25).trimmed();
      expect(t.turns.first.isQuestion, isTrue);
      expect(
        (t.turns.first.blocks.single['text']! as String).endsWith('q5'),
        isTrue,
      );
      expect(t.exchanges.length, 20);
    });

    test('a trim strips every thinking block it leaves behind', () {
      final t = _thread(25).trimmed();
      for (final turn in t.turns) {
        expect(turn.blocks.where((b) => b['type'] == 'thinking'), isEmpty);
        expect(turn.blocks, isNotEmpty);
      }
    });

    test('a failed question is removed from the tail and only the tail', () {
      final now = DateTime.utc(2026, 10, 19, 18);
      final before = _thread(2);
      final pending = before
          .plus(AskTurn.question('<screen>{}</screen>', 'q2'), now)
          .copyWith(
            exchanges: [
              ...before.exchanges,
              const AskExchange(question: 'q2'),
            ],
          );
      final back = pending.withoutLastQuestion();
      expect(back.wire, before.wire);
      expect(back.exchanges.length, 2);
    });

    test(
      'the tool round trip a turn needs: calls out, results back in order',
      () {
        final calls = toolCalls([
          {'type': 'thinking', 'thinking': '', 'signature': 's'},
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'recipe_lines',
            'input': {'recipe_id': 'r1'},
          },
          {'type': 'tool_use', 'id': 't2', 'name': 'method_step', 'input': {}},
        ]);
        expect(
          [for (final c in calls) c.name],
          ['recipe_lines', 'method_step'],
        );
        final back = toolResults([
          (id: 't1', content: '{}', isError: false),
          (id: 't2', content: 'no such step', isError: true),
        ]);
        expect(back.isQuestion, isFalse);
        expect(back.blocks.last, {
          'type': 'tool_result',
          'tool_use_id': 't2',
          'content': 'no such step',
          'is_error': true,
        });
      },
    );

    test('an answer is its text blocks, thinking left out', () {
      expect(
        answerText([
          {'type': 'thinking', 'thinking': 'hidden', 'signature': 's'},
          {'type': 'text', 'text': ' 3 tbsp tamari. '},
        ]),
        '3 tbsp tamari.',
      );
    });
  });
}
