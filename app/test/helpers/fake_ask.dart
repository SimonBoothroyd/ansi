import 'package:ansi/features/ask/data/ask_voice.dart';
import 'package:ansi/features/ask/domain/ask_repository.dart';

/// One scripted model turn: it reads what was sent and answers.
typedef AskScript = AskReplyData Function(List<Map<String, Object?>> sent);

/// The `ask` relay, answering from [script] in order and recording every
/// conversation it was sent.
class ScriptedAskRepository implements AskRepository {
  ScriptedAskRepository(this.script);

  final List<AskScript> script;
  final List<List<Map<String, Object?>>> sent = [];

  @override
  Future<AskReplyData> turn(List<Map<String, Object?>> messages) async {
    sent.add(messages);
    if (sent.length > script.length) {
      throw const AskException('the script ran out');
    }
    return script[sent.length - 1](messages);
  }
}

/// A model turn that calls one tool.
AskReplyData askToolCall(
  String name,
  Map<String, Object?> input, {
  String id = 'toolu_1',
}) => (
  content: [
    {'type': 'thinking', 'thinking': '', 'signature': 'sig-$id'},
    {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
  ],
  stopReason: 'tool_use',
);

/// A model turn that answers in words.
AskReplyData askSays(String text) => (
  content: [
    {'type': 'text', 'text': text},
  ],
  stopReason: 'end_turn',
);

/// The last tool result's content in a conversation.
String lastToolResult(List<Map<String, Object?>> sent) {
  final blocks = sent.last['content']! as List;
  final result = blocks.last as Map;
  return result['content']! as String;
}

/// The mic and speaker: [listen] hands back [heard] as a finished question
/// (or refuses when [available] is false), and [speak] records what was read.
class FakeAskVoice implements AskVoice {
  FakeAskVoice({this.heard = '', this.available = true});

  String heard;
  bool available;
  final List<String> spoken = [];

  @override
  Future<bool> listen({
    required void Function(String words, {required bool done}) onWords,
  }) async {
    if (!available) return false;
    onWords(heard, done: false);
    onWords(heard, done: true);
    return true;
  }

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stopSpeaking() async {}
}
