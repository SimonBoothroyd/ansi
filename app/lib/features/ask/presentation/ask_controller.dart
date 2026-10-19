/// The conversation with Ansi: one question in, tool calls run on the phone,
/// one answer out.
///
/// Kept alive, so closing the sheet keeps the thread for the next question;
/// it is cleared after [kAskThreadIdle] or when the app restarts,
/// and never stored or synced.
library;

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/ask_providers.dart';
import '../domain/ask_repository.dart';
import '../domain/ask_screen.dart';
import '../domain/ask_thread.dart';
import '../domain/ask_tool_runner.dart';

part 'ask_controller.g.dart';

/// The most model calls one question may take: a lookup, an action, an
/// answer, with room for a clarifying search.
const kAskMaxRounds = 6;

/// What the member sees when Ansi declines (`stop_reason: refusal`).
const kAskRefusal = 'Ansi can’t help with that one.';

/// The clock the thread's idle rule reads. Tests pin it.
@Riverpod(keepAlive: true)
DateTime Function() askClock(Ref ref) => DateTime.now;

@immutable
class AskState {
  const AskState({this.thread = const AskThread(), this.busy = false});

  final AskThread thread;

  /// Whether a question is in flight.
  final bool busy;

  AskState copyWith({AskThread? thread, bool? busy}) =>
      AskState(thread: thread ?? this.thread, busy: busy ?? this.busy);
}

@Riverpod(keepAlive: true)
class AskController extends _$AskController {
  @override
  AskState build() => const AskState();

  DateTime _now() => ref.read(askClockProvider)();

  /// Clears the thread now (the sheet's "New").
  void clear() => state = const AskState();

  /// Clears the thread when it has sat idle past [kAskThreadIdle].
  void forgetIfStale() {
    if (!state.busy && state.thread.isStale(_now())) clear();
  }

  /// Asks [text] about [screen], running Ansi's tool calls with [runner].
  /// Returns the answer, or null when the question failed (the exchange then
  /// says why).
  Future<String?> ask(
    String text, {
    required AskScreen screen,
    required AskToolRunner runner,
    bool spoken = false,
  }) async {
    final question = text.trim();
    if (question.isEmpty || state.busy) return null;
    forgetIfStale();

    final start = state.thread.trimmed();
    var thread = start
        .plus(AskTurn.question(screen.block, question), _now())
        .copyWith(
          exchanges: [
            ...start.exchanges,
            AskExchange(question: question, spoken: spoken),
          ],
        );
    state = AskState(thread: thread, busy: true);

    final done = <String>[];
    try {
      for (var round = 0; round < kAskMaxRounds; round++) {
        final reply = await ref.read(askRepositoryProvider).turn(thread.wire);
        if (reply.stopReason == 'refusal') {
          return _settle(start, question, spoken, kAskRefusal, done);
        }
        thread = thread.plus(
          AskTurn(role: AskRole.assistant, blocks: reply.content),
          _now(),
        );
        final calls = toolCalls(reply.content);
        if (calls.isEmpty || reply.stopReason != 'tool_use') {
          final said = answerText(reply.content);
          final answer = reply.stopReason == 'max_tokens'
              ? '$said …'.trim()
              : said;
          state = AskState(
            thread: thread.copyWith(
              exchanges: [
                ...start.exchanges,
                AskExchange(
                  question: question,
                  spoken: spoken,
                ).answered(answer.isEmpty ? 'Done.' : answer, done),
              ],
            ),
          );
          return answer;
        }
        final results = <({String id, String content, bool isError})>[];
        for (final call in calls) {
          final outcome = await runner.run(call);
          results.add((
            id: call.id,
            content: outcome.content,
            isError: outcome.isError,
          ));
          if (outcome.done != null) done.add(outcome.done!);
        }
        thread = thread.plus(toolResults(results), _now());
        state = state.copyWith(thread: thread);
      }
      // Still calling tools after every round: the thread ends on tool
      // results, which the next question could not follow, so the question
      // goes.
      return _settle(
        start,
        question,
        spoken,
        'Ansi took too many steps over that — try asking it more simply.',
        done,
        failed: true,
      );
    } on AskException catch (e) {
      return _settle(start, question, spoken, e.message, done, failed: true);
    }
  }

  /// Puts the thread back as it was before the question, keeping the
  /// exchange on screen with [said] — the tail removal the append-only rule
  /// allows.
  String? _settle(
    AskThread start,
    String question,
    bool spoken,
    String said,
    List<String> done, {
    bool failed = false,
  }) {
    state = AskState(
      thread: start.copyWith(
        exchanges: [
          ...start.exchanges,
          AskExchange(
            question: question,
            spoken: spoken,
            failed: failed,
          ).answered(said, done),
        ],
        lastActivity: _now(),
      ),
    );
    return failed ? null : said;
  }
}
