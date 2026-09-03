/// One honest sentence per failure family.
///
/// Never an exception's `toString()`: that is a developer's sentence in a
/// user's face. The raw text is kept, but it lives behind "Copy details" —
/// useful to whoever is being texted about the problem, invisible to everyone
/// else.
///
/// The voice to match is already in the codebase: *"the import service took too
/// long to answer — check your connection and try again"*, and *"Still used by
/// 3 recipes (4 lines). Change those lines first."* Both say what happened and
/// what to do. Two files over sat *"Could not load the library."*, six times.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A short, lowercase clause naming what went wrong, for the reason line under
/// a shared error state. Never ends with a full stop — the caller composes it.
String describeFailure(Object error) => switch (error) {
  // The server's own words: PostgREST messages are written for a human and are
  // more specific than anything this function could invent.
  PostgrestException(:final message) => message,
  AuthException(:final message) => message,
  FunctionException() => 'the server refused this request',
  TimeoutException() => 'the server didn’t answer in time',
  SocketException() || ClientException() => 'couldn’t reach the server',
  SqliteException() =>
    'the local database didn’t answer — this is on the phone, not the network',
  StateError() => 'something wasn’t ready yet',
  FormatException() => 'the data came back in a shape Ansi didn’t expect',
  _ => 'an unexpected problem',
};

/// The whole truth, for the clipboard: the exception, its type, and the stack.
///
/// Deliberately unformatted — this is for pasting into a message to whoever
/// can fix it, not for reading on a phone.
String failureDetails(Object error, [StackTrace? stack]) =>
    ['${error.runtimeType}: $error', if (stack != null) '$stack'].join('\n');
