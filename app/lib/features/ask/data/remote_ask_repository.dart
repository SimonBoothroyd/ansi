/// The `ask` edge function, as Ansi's relay.
///
/// The conversation goes up whole and the assistant's blocks come back: no
/// stream, because a turn is a sentence or a tool call. The function holds
/// the key and the prompt; this side holds the conversation and runs the
/// tools.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ask_repository.dart';

/// How long the app waits for one turn.
///
/// The server's own budget is `ASK_DEADLINE_MS` (30 s,
/// `_shared/adapters/claude_ask.ts`); `_shared/timeouts.test.ts` holds this
/// rung above that worst case, so the server gives up with a sentence first.
const askTurnTimeout = Duration(seconds: 60);

class EdgeAskRepository implements AskRepository {
  const EdgeAskRepository({required FunctionsClient functions})
    : _functions = functions;

  final FunctionsClient _functions;

  @override
  Future<AskReplyData> turn(List<Map<String, Object?>> messages) async {
    try {
      return await _turn(messages).timeout(askTurnTimeout);
    } on TimeoutException {
      throw const AskException(
        'Ansi was still thinking when it ran out of time — try asking again',
      );
    }
  }

  Future<AskReplyData> _turn(List<Map<String, Object?>> messages) async {
    final FunctionResponse response;
    try {
      response = await _functions.invoke(
        'ask',
        body: <String, Object?>{'messages': messages},
      );
    } on FunctionException catch (e) {
      final details = e.details;
      // The server's own sentence wins: it was written for a person.
      if (details is Map && details['error'] is String) {
        throw AskException(details['error'] as String);
      }
      throw AskException(switch (e.status) {
        0 => 'Ansi could not be reached — check the connection and try again',
        504 || 408 =>
          'Ansi was still thinking when it ran out of time — try asking again',
        _ => 'Ansi could not answer that (HTTP ${e.status})',
      });
    }
    final data = response.data;
    if (data is! Map || data['content'] is! List) {
      throw const AskException('Ansi sent something we could not read');
    }
    return (
      content: [
        for (final b in data['content'] as List)
          if (b is Map) Map<String, Object?>.from(b),
      ],
      stopReason: data['stop_reason'] is String
          ? data['stop_reason'] as String
          : 'end_turn',
    );
  }
}
