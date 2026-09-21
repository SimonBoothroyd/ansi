/// One honest sentence per failure family. Never an exception's `toString()`;
/// the raw text lives behind "Copy details". Each sentence says what happened
/// and, where it can, what to do.
library;

import 'dart:async';
// SocketException only. On the web this resolves to Flutter's stub library.
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A short, lowercase clause naming what went wrong, for the reason line under
/// a shared error state. No trailing full stop; the caller composes it.
String describeFailure(Object error) => switch (error) {
  // PostgREST messages are written for a human.
  PostgrestException(:final message) => message,
  AuthException(:final message) => message,
  FunctionException() => 'the server refused this request',
  TimeoutException() => 'the server didn’t answer in time',
  // Nothing came back. SocketException is a phone's; ClientException is a
  // browser's, where every failed fetch (DNS, offline, CORS) is reported alike.
  SocketException() || ClientException() => 'couldn’t reach the server',
  SqliteException() =>
    'the local database didn’t answer — this is on the phone, not the network',
  StateError() => 'something wasn’t ready yet',
  FormatException() => 'the data came back in a shape Ansi didn’t expect',
  _ => 'an unexpected problem',
};

/// The exception, its type and the stack, unformatted, for the clipboard.
String failureDetails(Object error, [StackTrace? stack]) =>
    ['${error.runtimeType}: $error', if (stack != null) '$stack'].join('\n');
