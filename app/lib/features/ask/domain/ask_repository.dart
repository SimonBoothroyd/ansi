/// The ask relay's contract. Pure Dart.
library;

/// What one model call answered: the assistant's blocks, verbatim, and why
/// it stopped.
typedef AskReplyData = ({
  List<Map<String, Object?>> content,
  String stopReason,
});

/// One turn of the conversation, sent whole to the `ask` function.
// The interface is the seam tests fake, so it stays one method.
// ignore: one_member_abstracts
abstract interface class AskRepository {
  /// Sends [messages] (the wire turns, ending on the member) and returns the
  /// assistant's next blocks. Throws an exception carrying a sentence for the
  /// member when the call fails.
  Future<AskReplyData> turn(List<Map<String, Object?>> messages);
}

/// A failed turn, in words for the member.
class AskException implements Exception {
  const AskException(this.message);
  final String message;
  @override
  String toString() => message;
}
