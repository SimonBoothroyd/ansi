/// The conversation with Ansi on this device. Pure Dart.
///
/// The thread is the Messages API's own turns, kept verbatim and sent whole
/// each time: the `ask` function stores nothing. Three rules shape it.
///
/// - **Append-only.** A thinking block the model returned is valid only while
///   everything before it is unchanged, so blocks are never edited. The only
///   removal is at the tail (a question that failed), which nothing after it
///   depends on.
/// - **Cleared when idle.** After [kAskThreadIdle] with no message the next
///   question starts a fresh thread ([AskThread.isStale]).
/// - **Trimmed when long.** Past [kAskMaxExchanges] questions the oldest are
///   dropped — an edit to the history, so every thinking block left is
///   stripped with them ([AskThread.trimmed]).
library;

import 'package:meta/meta.dart';

/// How long a thread survives with no message.
const kAskThreadIdle = Duration(minutes: 30);

/// How many questions a thread keeps before the oldest go.
const kAskMaxExchanges = 20;

/// One turn on the wire: a role and its content blocks, verbatim.
@immutable
class AskTurn {
  const AskTurn({required this.role, required this.blocks});

  /// The member's question: the screen block, then what they said.
  factory AskTurn.question(String screenBlock, String text) => AskTurn(
    role: AskRole.user,
    blocks: [
      {'type': 'text', 'text': '$screenBlock\n$text'},
    ],
  );

  final AskRole role;
  final List<Map<String, Object?>> blocks;

  /// Whether this turn opens a question (the member's words, not tool
  /// results).
  bool get isQuestion =>
      role == AskRole.user && blocks.any((b) => b['type'] == 'text');

  Map<String, Object?> toJson() => {'role': role.name, 'content': blocks};
}

enum AskRole { user, assistant }

/// What one exchange looks like to the member: their words and Ansi's.
@immutable
class AskExchange {
  const AskExchange({
    required this.question,
    this.answer,
    this.done = const [],
    this.spoken = false,
    this.failed = false,
  });

  final String question;

  /// Ansi's words, or null while it is still thinking.
  final String? answer;

  /// What Ansi did on the phone, said in a few words ("Started 6–8 min").
  final List<String> done;

  /// Whether the question was spoken, so the answer is too.
  final bool spoken;

  /// Whether [answer] says why the question failed rather than answering it.
  /// A failed question is not in the wire turns: it can be asked again.
  final bool failed;

  AskExchange answered(String answer, List<String> done) => AskExchange(
    question: question,
    answer: answer,
    done: done,
    spoken: spoken,
    failed: failed,
  );
}

@immutable
class AskThread {
  const AskThread({
    this.turns = const [],
    this.exchanges = const [],
    this.lastActivity,
  });

  /// The wire turns, oldest first.
  final List<AskTurn> turns;

  /// What the sheet shows, oldest first.
  final List<AskExchange> exchanges;

  /// When the last message went either way.
  final DateTime? lastActivity;

  bool get isEmpty => turns.isEmpty;

  /// Whether the thread has sat idle past [kAskThreadIdle] at [now].
  bool isStale(DateTime now) {
    final last = lastActivity;
    return last != null && now.difference(last) >= kAskThreadIdle;
  }

  /// The wire form of every turn.
  List<Map<String, Object?>> get wire => [for (final t in turns) t.toJson()];

  AskThread copyWith({
    List<AskTurn>? turns,
    List<AskExchange>? exchanges,
    DateTime? lastActivity,
  }) => AskThread(
    turns: turns ?? this.turns,
    exchanges: exchanges ?? this.exchanges,
    lastActivity: lastActivity ?? this.lastActivity,
  );

  /// This thread with [turn] appended.
  AskThread plus(AskTurn turn, DateTime now) =>
      copyWith(turns: [...turns, turn], lastActivity: now);

  /// This thread keeping at most [max] questions.
  ///
  /// The oldest whole exchanges go, cut where a question opens, so a tool
  /// call never loses its result. Dropping them edits the history, which
  /// would invalidate every thinking block after the cut, so those are
  /// stripped; the blocks a later answer produces are bound to the new,
  /// shorter history.
  AskThread trimmed({int max = kAskMaxExchanges}) {
    final starts = [
      for (var i = 0; i < turns.length; i++)
        if (turns[i].isQuestion) i,
    ];
    if (starts.length <= max) return this;
    final cut = starts[starts.length - max];
    final kept = [
      for (final t in turns.sublist(cut))
        AskTurn(
          role: t.role,
          blocks: [
            for (final b in t.blocks)
              if (b['type'] != 'thinking' && b['type'] != 'redacted_thinking')
                b,
          ],
        ),
    ];
    final shown = exchanges.length <= max
        ? exchanges
        : exchanges.sublist(exchanges.length - max);
    return copyWith(turns: kept, exchanges: shown);
  }

  /// This thread as it stood before its last question: the tail removal a
  /// failed or refused question needs, and the only removal there is.
  AskThread withoutLastQuestion() {
    final last = turns.lastIndexWhere((t) => t.isQuestion);
    if (last < 0) return this;
    return copyWith(
      turns: turns.sublist(0, last),
      exchanges: exchanges.isEmpty
          ? exchanges
          : exchanges.sublist(0, exchanges.length - 1),
    );
  }
}

/// The text an assistant turn says, its text blocks joined.
String answerText(List<Map<String, Object?>> blocks) => [
  for (final b in blocks)
    if (b['type'] == 'text' && b['text'] is String)
      (b['text']! as String).trim(),
].where((s) => s.isNotEmpty).join('\n');

/// The tool calls an assistant turn makes, in order.
List<AskToolCall> toolCalls(List<Map<String, Object?>> blocks) => [
  for (final b in blocks)
    if (b['type'] == 'tool_use')
      AskToolCall(
        id: b['id']! as String,
        name: b['name']! as String,
        input: Map<String, Object?>.from(
          (b['input'] as Map?) ?? const <String, Object?>{},
        ),
      ),
];

/// One tool call the model asked the app to run.
@immutable
class AskToolCall {
  const AskToolCall({
    required this.id,
    required this.name,
    required this.input,
  });

  final String id;
  final String name;
  final Map<String, Object?> input;
}

/// The member's turn carrying every result of the turn before, in call order
/// — all in one message, as the API expects.
AskTurn toolResults(
  List<({String id, String content, bool isError})> results,
) => AskTurn(
  role: AskRole.user,
  blocks: [
    for (final r in results)
      {
        'type': 'tool_result',
        'tool_use_id': r.id,
        'content': r.content,
        if (r.isError) 'is_error': true,
      },
  ],
);
