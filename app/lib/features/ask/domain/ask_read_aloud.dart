/// When Ansi reads an answer aloud. Pure Dart.
library;

/// When an answer is read aloud. The sheet's speaker cycles it.
enum AskReadAloud {
  /// Spoken question, spoken answer; typed question, text only.
  matchQuestion,

  /// Every answer.
  always,

  /// None.
  never;

  /// Whether an answer to a question asked this way is read.
  bool reads({required bool spoken}) => switch (this) {
    matchQuestion => spoken,
    always => true,
    never => false,
  };

  AskReadAloud get next =>
      AskReadAloud.values[(index + 1) % AskReadAloud.values.length];

  String get label => switch (this) {
    matchQuestion => 'Reads answers to spoken questions',
    always => 'Reads every answer',
    never => 'Reads nothing aloud',
  };
}
