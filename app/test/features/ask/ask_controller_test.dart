import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/ask/data/ask_providers.dart';
import 'package:ansi/features/ask/domain/ask_repository.dart';
import 'package:ansi/features/ask/domain/ask_screen.dart';
import 'package:ansi/features/ask/domain/ask_tool_runner.dart';
import 'package:ansi/features/ask/presentation/ask_controller.dart';
import 'package:ansi/features/recipes/domain/line_override.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ask.dart';

const _screen = AskRecipeScreen(
  recipeId: 'r1',
  title: 'Ragù',
  servings: 6,
  servingsBase: 4,
);

/// A runner whose tools answer with a fixed result.
AskToolRunner _runner() => AskToolRunner(
  screen: () => _screen,
  loadRecipe: (_) async => null,
  listRecipes: () async => [(id: 'r1', title: 'Ragù')],
  weekOf: (_, _) async => (overrides: const <LineOverride>[], portions: null),
  setServings: (_, _) {},
  startTimer:
      (_, {required step, required ordinal, required low, required high}) {},
  openRecipe: (_) {},
  household: FakeAskHousehold().household,
);

void main() {
  late DateTime now;

  ProviderContainer containerFor(AskRepository repo) {
    final c = ProviderContainer(
      overrides: [
        askRepositoryProvider.overrideWithValue(repo),
        askClockProvider.overrideWithValue(() => now),
        weekShapeProvider.overrideWithValue(WeekShape.monday),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => now = DateTime.utc(2026, 10, 19, 18));

  test(
    'a question runs its tool on the phone and comes back answered',
    () async {
      final repo = ScriptedAskRepository([
        (_) => askToolCall('find_recipe', {'query': 'ragu'}),
        (sent) {
          // The tool ran here, and its result went back in the member's turn.
          expect(lastToolResult(sent), contains('"title":"Ragù"'));
          return askSays('Ragù is in your Library.');
        },
      ]);
      final c = containerFor(repo);
      final answer = await c
          .read(askControllerProvider.notifier)
          .ask('do I have ragu?', screen: _screen, runner: _runner());

      expect(answer, 'Ragù is in your Library.');
      final state = c.read(askControllerProvider);
      expect(state.busy, isFalse);
      expect(state.thread.exchanges.single.answer, 'Ragù is in your Library.');
      // Question, tool call, tool result, answer — append-only, verbatim.
      expect(state.thread.turns.map((t) => t.role.name), [
        'user',
        'assistant',
        'user',
        'assistant',
      ]);
      // The first turn carries the screen ahead of the words.
      final first = repo.sent.first.first['content']! as List;
      expect((first.single as Map)['text'], startsWith('<screen>'));
      // The thinking block went back exactly as it came.
      expect((repo.sent.last[1]['content']! as List).first, {
        'type': 'thinking',
        'thinking': '',
        'signature': 'sig-toolu_1',
      });
    },
  );

  test('a follow-up carries the whole conversation', () async {
    final repo = ScriptedAskRepository([
      (_) => askSays('3 tbsp tamari.'),
      (sent) {
        expect(sent, hasLength(3));
        return askSays('6 cloves garlic.');
      },
    ]);
    final c = containerFor(repo);
    final n = c.read(askControllerProvider.notifier);
    await n.ask('how much tamari?', screen: _screen, runner: _runner());
    await n.ask('and garlic?', screen: _screen, runner: _runner());
    expect(c.read(askControllerProvider).thread.exchanges, hasLength(2));
  });

  test('a refusal takes the question back off the wire and says so', () async {
    final repo = ScriptedAskRepository([
      (_) => askSays('3 tbsp tamari.'),
      (_) => (content: const [], stopReason: 'refusal'),
      (sent) {
        // The refused question is gone; the thread is as it was.
        expect(sent, hasLength(3));
        return askSays('Fine.');
      },
    ]);
    final c = containerFor(repo);
    final n = c.read(askControllerProvider.notifier);
    await n.ask('how much tamari?', screen: _screen, runner: _runner());
    final said = await n.ask(
      'something else',
      screen: _screen,
      runner: _runner(),
    );
    expect(said, kAskRefusal);
    expect(c.read(askControllerProvider).thread.turns, hasLength(2));
    await n.ask('ok', screen: _screen, runner: _runner());
  });

  test('a failed turn says why and leaves the thread askable', () async {
    final repo = ScriptedAskRepository([
      (_) => throw const AskException('Ansi could not be reached'),
    ]);
    final c = containerFor(repo);
    final said = await c
        .read(askControllerProvider.notifier)
        .ask('how much tamari?', screen: _screen, runner: _runner());
    expect(said, isNull);
    final state = c.read(askControllerProvider);
    expect(state.thread.turns, isEmpty);
    expect(state.thread.exchanges.single.failed, isTrue);
    expect(state.thread.exchanges.single.answer, 'Ansi could not be reached');
  });

  test('a model that never stops calling tools is cut off', () async {
    final repo = ScriptedAskRepository([
      for (var i = 0; i < kAskMaxRounds; i++)
        (_) => askToolCall('find_recipe', {'query': 'x'}, id: 't$i'),
    ]);
    final c = containerFor(repo);
    final said = await c
        .read(askControllerProvider.notifier)
        .ask('loop', screen: _screen, runner: _runner());
    expect(said, isNull);
    expect(repo.sent, hasLength(kAskMaxRounds));
    // Nothing ending on a tool result is left for the next question.
    expect(c.read(askControllerProvider).thread.turns, isEmpty);
  });

  test(
    'half an hour idle and the next question starts a fresh thread',
    () async {
      final repo = ScriptedAskRepository([
        (_) => askSays('3 tbsp tamari.'),
        (sent) {
          expect(sent, hasLength(1));
          return askSays('6 cloves garlic.');
        },
      ]);
      final c = containerFor(repo);
      final n = c.read(askControllerProvider.notifier);
      await n.ask('how much tamari?', screen: _screen, runner: _runner());
      now = now.add(const Duration(minutes: 31));
      await n.ask('and garlic?', screen: _screen, runner: _runner());
      expect(c.read(askControllerProvider).thread.exchanges, hasLength(1));
    },
  );
}
